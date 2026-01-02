import 'package:flutter/material.dart';
import '../models/legacy_gantt_task.dart';
import '../models/legacy_gantt_dependency.dart';
import '../models/legacy_gantt_resource.dart';
import 'gantt_sync_client.dart';
import 'merkle_tree.dart';
import 'hlc.dart';

class CRDTEngine {
  /// Merges a list of tasks with a list of operations.
  /// Uses Last-Write-Wins (LWW) based on timestamps.
  /// Merges a list of tasks with a list of operations.
  /// Uses "Hybrid Sovereignty" logic:
  /// - Field-Level LWW (Map-CRDT) for properties.
  /// - Add-Wins OR-Set (Tombstones) for existence.
  List<LegacyGanttTask> mergeTasks(
    List<LegacyGanttTask> currentTasks,
    List<Operation> operations,
  ) {
    // 1. Initialize map with existing tasks
    final taskMap = {for (var t in currentTasks) t.id: t};

    // 2. Apply operations sequentially
    for (var op in operations) {
      if (op.type == 'BATCH_UPDATE') {
        final subOpsList = op.data['operations'] as List? ?? [];
        for (final subOpMaps in subOpsList) {
          try {
            final opMap = subOpMaps as Map<String, dynamic>;
            final subOp = Operation.fromJson(opMap);
            _applyOp(taskMap, subOp);
          } catch (e) {
            print('CRDTEngine Error processing batch op: $e');
          }
        }
      } else {
        _applyOp(taskMap, op);
      }
    }

    // 3. Return only non-deleted tasks (Tombstones are filtered out for UI)
    return taskMap.values.where((t) => !t.isDeleted).toList();
  }

  /// Merges a list of resources with a list of operations.
  List<LegacyGanttResource> mergeResources(
    List<LegacyGanttResource> currentResources,
    List<Operation> operations,
  ) {
    // 1. Initialize map with existing resources
    final resourceMap = {for (var r in currentResources) r.id: r};

    // 2. Apply operations sequentially
    for (var op in operations) {
      if (op.type == 'BATCH_UPDATE') {
        final subOpsList = op.data['operations'] as List? ?? [];
        for (final subOpMaps in subOpsList) {
          try {
            final opMap = subOpMaps as Map<String, dynamic>;
            final subOp = Operation.fromJson(opMap);
            _applyResourceOp(resourceMap, subOp);
          } catch (e) {
            print('CRDTEngine Error processing batch op (resource): $e');
          }
        }
      } else {
        _applyResourceOp(resourceMap, op);
      }
    }

    // 3. Return non-deleted resources
    return resourceMap.values.where((r) => !r.isDeleted).toList();
  }

  void _applyResourceOp(Map<String, LegacyGanttResource> resourceMap, Operation op) {
    if (op.type == 'DELETE_RESOURCE') {
      final resourceId = op.data['id'] as String? ?? op.data['resourceId'] as String?;
      if (resourceId == null) return;

      final existing = resourceMap[resourceId];
      if (existing != null) {
        resourceMap[resourceId] = existing.copyWith(isDeleted: true);
      }
      return;
    }

    if (op.type != 'INSERT_RESOURCE' && op.type != 'UPDATE_RESOURCE') return;

    final opData = op.data;
    var effectiveData = opData;
    if (effectiveData.containsKey('data') && effectiveData['data'] is Map) {
      effectiveData = effectiveData['data'];
    }

    final String? resourceId = effectiveData['id'] as String?;
    if (resourceId == null) return;

    // For now, resources are simple LWW on the whole object or fields.
    // simpler model than tasks: just overwrite properties if needed.
    // But consistent with tasks, let's just do a full replace/merge.

    final existing = resourceMap[resourceId];
    // If not exists, create new
    final base = existing ??
        LegacyGanttResource(
          id: resourceId,
          name: '',
          isDeleted: true, // will be resurrected
        );

    resourceMap[resourceId] = _mergeResource(base, op, effectiveData);
  }

  LegacyGanttResource _mergeResource(LegacyGanttResource target, Operation op, Map<String, dynamic> changes) {
    // Simple LWW for now as resources don't have field-level timestamps in the model yet.
    // Assuming operation timestamp > current state timestamp?
    // We don't track 'lastUpdated' per resource in the model yet, so we just Apply.
    // In a real CRDT we need per-field timestamps or at least 1 timestamp.
    // For this implementation, we trust the incoming op is newer or we just LWW.

    String newName = target.name;
    if (changes.containsKey('name')) newName = changes['name'];

    String? newParentId = target.parentId;
    if (changes.containsKey('parentId')) newParentId = changes['parentId'];

    bool newIsExpanded = target.isExpanded;
    if (changes.containsKey('isExpanded')) newIsExpanded = changes['isExpanded'] == true;

    String newGanttType = target.ganttType;
    if (changes.containsKey('ganttType')) newGanttType = changes['ganttType'];

    // Implicit resurrection
    return target.copyWith(
      name: newName,
      parentId: newParentId,
      isExpanded: newIsExpanded,
      ganttType: newGanttType,
      isDeleted: false,
    );
  }

  void _applyOp(Map<String, LegacyGanttTask> taskMap, Operation op) {
    if (op.type == 'DELETE_TASK') {
      final taskId = op.data['id'] as String? ?? op.data['taskId'] as String?;
      if (taskId == null) return;

      final existing = taskMap[taskId];

      // If task exists, try to set isDeleted=true using merge logic
      // If task doesn't exist, we could create a tombstone, but for simplicity we ignore
      // pure deletions of unknown tasks unless we want strictly causal consistency.
      // Hybrid Sovereignty prefers "Add Wins", so invisible deletions are fine to ignore
      // if we assume they are superseded or irrelevant.
      // However, to be robust, let's create a tombstone if we have an ID,
      // so if an older INSERT arrives later, we know to ignore it (if DELETE was newer).

      final base = existing ?? LegacyGanttTask.empty().copyWith(id: taskId);
      taskMap[taskId] = _mergeTask(base, op, {'isDeleted': true});
      return;
    }

    final opData = op.data;
    var effectiveData = opData;
    if (effectiveData.containsKey('data') && effectiveData['data'] is Map) {
      effectiveData = effectiveData['data'];
    }

    final String? taskId = effectiveData['id'] as String? ?? effectiveData['taskId'] as String?;
    if (taskId == null) return;

    final existing = taskMap[taskId];

    // For INSERT/UPDATE, we assume isDeleted=false (Resurrection)
    final base = existing ?? LegacyGanttTask.empty().copyWith(id: taskId, isDeleted: true); // Default to deleted if new

    // Inject isDeleted=false into the data to force resurrection check
    final mergeData = Map<String, dynamic>.from(effectiveData);
    mergeData['isDeleted'] = false;

    taskMap[taskId] = _mergeTask(base, op, mergeData);
  }

  LegacyGanttTask _mergeTask(LegacyGanttTask target, Operation op, Map<String, dynamic> changes) {
    final newTimestamps = Map<String, Hlc>.from(target.fieldTimestamps);

    // Helper to check LWW per field
    bool shouldUpdate(String field) {
      final lastHlc = newTimestamps[field] ?? target.lastUpdated;
      // return true; // No history = update < old implementation
      // LWW: strictly greater or tie-break? Usually strictly greater for convergence,
      // or compare Actor ID on ties. Hlc.compareTo handles node ID tie-breaking.
      return op.timestamp >= lastHlc;
    }

    // Helper to update field
    T update<T>(String field, T candidate, T current) {
      if (shouldUpdate(field)) {
        newTimestamps[field] = op.timestamp;
        return candidate;
      }
      return current;
    }

    // 1. Merge "isDeleted" (Resurrection / Deletion)
    bool newIsDeleted = target.isDeleted;
    if (changes.containsKey('isDeleted')) {
      newIsDeleted = update<bool>('isDeleted', changes['isDeleted'], target.isDeleted);
    }

    // 2. Merge Properties
    String newRowId = target.rowId;
    if (changes.containsKey('rowId')) newRowId = update('rowId', changes['rowId'], target.rowId);

    DateTime newStart = target.start;
    final startVal = changes['start'] ?? changes['startDate'] ?? changes['start_date'];
    if (startVal != null) {
      final parsed = _parseDate(startVal);
      if (parsed != null) newStart = update('start', parsed, target.start);
    }

    DateTime newEnd = target.end;
    final endVal = changes['end'] ?? changes['endDate'] ?? changes['end_date'];
    if (endVal != null) {
      final parsed = _parseDate(endVal);
      if (parsed != null) newEnd = update('end', parsed, target.end);
    }

    String? newName = target.name;
    if (changes.containsKey('name')) newName = update('name', changes['name'], target.name);

    Color? newColor = target.color;
    if (changes.containsKey('color')) newColor = update('color', _parseColor(changes['color']), target.color);

    Color? newTextColor = target.textColor;
    if (changes.containsKey('text_color')) {
      newTextColor = update('text_color', _parseColor(changes['text_color']), target.textColor);
    }

    double newCompletion = target.completion;
    if (changes.containsKey('completion')) {
      newCompletion = update('completion', (changes['completion'] as num).toDouble(), target.completion);
    }

    String? newResourceId = target.resourceId;
    if (changes.containsKey('resourceId')) {
      newResourceId = update('resourceId', changes['resourceId'], target.resourceId);
    }

    String? newParentId = target.parentId;
    if (changes.containsKey('parentId')) newParentId = update('parentId', changes['parentId'], target.parentId);

    String? newNotes = target.notes;
    if (changes.containsKey('notes')) newNotes = update('notes', changes['notes'], target.notes);

    bool newIsSummary = target.isSummary;
    if (changes.containsKey('isSummary')) {
      newIsSummary = update('isSummary', changes['isSummary'] == true, target.isSummary);
    }

    // ... handle other fields as needed ...

    return target.copyWith(
      rowId: newRowId,
      start: newStart,
      end: newEnd,
      name: newName,
      color: newColor,
      textColor: newTextColor,
      completion: newCompletion,
      resourceId: newResourceId,
      parentId: newParentId,
      notes: newNotes,
      isSummary: newIsSummary,
      fieldTimestamps: newTimestamps,
      isDeleted: newIsDeleted,
      lastUpdated: op.timestamp > target.lastUpdated ? op.timestamp : target.lastUpdated, // Aggregate update time
      lastUpdatedBy: op.timestamp > target.lastUpdated ? op.actorId : target.lastUpdatedBy,
    );
  }

  Color? _parseColor(dynamic value) {
    if (value == null) return null;
    if (value is int) return Color(value);
    if (value is String) {
      try {
        if (value.startsWith('#')) {
          return Color(int.parse(value.substring(1), radix: 16));
        }
        return Color(int.parse(value, radix: 16));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt;
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  /// Computes the Merkle Root for a list of tasks and dependencies using the deterministic content hash.
  String computeMerkleRoot(
    List<LegacyGanttTask> tasks, {
    List<LegacyGanttTaskDependency> dependencies = const [],
    List<LegacyGanttResource> resources = const [],
  }) {
    final taskHashes = tasks.map((t) => t.contentHash);
    final depHashes = dependencies.map((d) => d.contentHash);
    final resourceHashes = resources.map((r) => r.contentHash);
    final allHashes = [...taskHashes, ...depHashes, ...resourceHashes];

    if (allHashes.isEmpty) return MerkleTree.computeRoot([]);
    return MerkleTree.computeRoot(allHashes.toList());
  }
}
