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

    return taskMap.values.toList();
  }

  void _applyOp(Map<String, LegacyGanttTask> taskMap, Operation op) {
    final opData = op.data;
    var effectiveData = opData;
    if (effectiveData.containsKey('data') && effectiveData['data'] is Map) {
      effectiveData = effectiveData['data'];
    }

    final String? taskId = effectiveData['id'] as String? ?? effectiveData['taskId'] as String?;

    if (taskId == null) {
      return;
    }

    if (op.type == 'UPDATE_TASK' || op.type == 'INSERT_TASK') {
      final existingTask = taskMap[taskId];

      // HLC Comparison: op.timestamp > existingTask.lastUpdated
      if (existingTask == null || existingTask.lastUpdated < op.timestamp) {
        if (effectiveData.containsKey('start') ||
            effectiveData.containsKey('end') ||
            effectiveData.containsKey('name') ||
            effectiveData.containsKey('start_date') ||
            effectiveData.containsKey('startDate') ||
            effectiveData.containsKey('end_date') ||
            effectiveData.containsKey('endDate') ||
            effectiveData.containsKey('color') ||
            effectiveData.containsKey('text_color') ||
            effectiveData.containsKey('completion') ||
            effectiveData.containsKey('resourceId') ||
            effectiveData.containsKey('baselineStart') ||
            effectiveData.containsKey('baselineEnd') ||
            effectiveData.containsKey('notes') ||
            effectiveData.containsKey('parentId') ||
            effectiveData.containsKey('isMilestone') ||
            effectiveData.containsKey('isSummary') ||
            effectiveData.containsKey('rowId') ||
            effectiveData.containsKey('usesWorkCalendar') ||
            effectiveData.containsKey('isAutoScheduled')) {
          taskMap[taskId] = _createTaskFromOp(op, existingTask, effectiveData);
        }
      }
    } else if (op.type == 'DELETE_TASK') {
      final existingTask = taskMap[taskId];
      if (existingTask == null || existingTask.lastUpdated < op.timestamp) {
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
            : (data['startDate'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['startDate'])
                : (data['start_date'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(data['start_date'])
                    : (existing?.start ?? DateTime.now()))),
        end: data['end'] != null
            ? DateTime.parse(data['end'])
            : (data['endDate'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['endDate'])
                : (data['end_date'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(data['end_date'])
                    : (existing?.end ?? DateTime.now().add(const Duration(days: 1))))),
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
        resourceId: data['resourceId'] ?? existing?.resourceId,
        baselineStart: data['baselineStart'] != null
            ? DateTime.parse(data['baselineStart'])
            : (data['baseline_start'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['baseline_start'])
                : existing?.baselineStart),
        baselineEnd: data['baselineEnd'] != null
            ? DateTime.parse(data['baselineEnd'])
            : (data['baseline_end'] != null
                ? DateTime.fromMillisecondsSinceEpoch(data['baseline_end'])
                : existing?.baselineEnd),
        notes: data['notes'] ?? existing?.notes,
        isMilestone: data['isMilestone'] ?? existing?.isMilestone ?? false,
        parentId: data['parentId'] ?? existing?.parentId,
        usesWorkCalendar: data['usesWorkCalendar'] ?? existing?.usesWorkCalendar ?? false,
        load: (data['load'] as num?)?.toDouble() ?? existing?.load ?? 1.0,
        isAutoScheduled: data['isAutoScheduled'] ?? existing?.isAutoScheduled,
      );
}
