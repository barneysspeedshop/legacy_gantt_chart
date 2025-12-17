import 'package:flutter/material.dart';
import '../models/legacy_gantt_task.dart';
import 'gantt_sync_client.dart';

class CRDTEngine {
  /// Merges a list of tasks with a list of operations.
  /// Uses Last-Write-Wins (LWW) based on timestamps.
  List<LegacyGanttTask> mergeTasks(
    List<LegacyGanttTask> currentTasks,
    List<Operation> operations,
  ) {
    final taskMap = {for (var t in currentTasks) t.id: t};

    for (var op in operations) {
      if (op.type == 'BATCH_UPDATE') {
        final subOpsList = op.data['operations'] as List? ?? [];
        for (final subOpMaps in subOpsList) {
          try {
            final opMap = subOpMaps as Map<String, dynamic>;
            final subOp = Operation(
              type: opMap['type'],
              data: opMap['data'],
              timestamp: opMap['timestamp'],
              actorId: opMap['actorId'] ?? op.actorId,
            );
            _applyOp(taskMap, subOp);
          } catch (e) {
            print('CRDTEngine Error processing batch op: $e');
          }
        }
      } else {
        _applyOp(taskMap, op);
      }
    }

    return taskMap.values.toList();
  }

  void _applyOp(Map<String, LegacyGanttTask> taskMap, Operation op) {
    final opData = op.data;
    // Handle both 'id' and 'taskId' for robustness
    // Also handle nested 'data' wrapper if present (common in deserialization)
    var effectiveData = opData;
    if (effectiveData.containsKey('data') && effectiveData['data'] is Map) {
      effectiveData = effectiveData['data'];
    }

    final String? taskId = effectiveData['id'] as String? ?? effectiveData['taskId'] as String?;

    if (taskId == null) {
      // Skip operations without a valid task ID
      // print('CRDTEngine Warning: Operation ${op.type} missing id. Data: $opData');
      return;
    }

    if (op.type == 'UPDATE_TASK' || op.type == 'INSERT_TASK') {
      final existingTask = taskMap[taskId];

      // LWW check
      if (existingTask == null || (existingTask.lastUpdated ?? 0) < op.timestamp) {
        // Apply update
        if (effectiveData.containsKey('start') ||
            effectiveData.containsKey('end') ||
            effectiveData.containsKey('name') ||
            effectiveData.containsKey('start_date') ||
            effectiveData.containsKey('color') ||
            effectiveData.containsKey('text_color')) {
          taskMap[taskId] = _createTaskFromOp(op, existingTask, effectiveData);
        }
      }
    } else if (op.type == 'DELETE_TASK') {
      final existingTask = taskMap[taskId];
      if (existingTask == null || (existingTask.lastUpdated ?? 0) < op.timestamp) {
        taskMap.remove(taskId);
      }
    }
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

  LegacyGanttTask _createTaskFromOp(Operation op, LegacyGanttTask? existing, Map<String, dynamic> data) =>
      LegacyGanttTask(
        id: data['id'],
        rowId: data['rowId'] ?? existing?.rowId ?? '',
        start: data['start'] != null
            ? DateTime.parse(data['start'])
            : (data['start_date'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['start_date'])
                : (existing?.start ?? DateTime.now())),
        end: data['end'] != null
            ? DateTime.parse(data['end'])
            : (data['end_date'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['end_date'])
                : (existing?.end ?? DateTime.now().add(const Duration(days: 1)))),
        name: data['name'] ?? existing?.name,
        color: _parseColor(data['color']) ?? existing?.color,
        textColor: _parseColor(data['text_color']) ?? existing?.textColor,
        stackIndex: data['stackIndex'] ?? existing?.stackIndex ?? 0,
        originalId: data['originalId'] ?? existing?.originalId,
        isSummary: data['isSummary'] ?? existing?.isSummary ?? false,
        isTimeRangeHighlight: data['isTimeRangeHighlight'] ?? existing?.isTimeRangeHighlight ?? false,
        isOverlapIndicator: data['isOverlapIndicator'] ?? existing?.isOverlapIndicator ?? false,
        completion: (data['completion'] as num?)?.toDouble() ?? existing?.completion ?? 0.0,
        lastUpdated: op.timestamp,
        lastUpdatedBy: op.actorId,
      );
}
