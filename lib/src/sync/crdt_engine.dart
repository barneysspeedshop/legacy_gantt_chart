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
      if (op.type == 'UPDATE_TASK') {
        final taskId = op.data['id'] as String;
        final existingTask = taskMap[taskId];

        // LWW check
        if (existingTask == null || (existingTask.lastUpdated ?? 0) < op.timestamp) {
          // Apply update
          // We need to reconstruct the task from the operation data
          // This assumes the operation data contains the full task or a partial update
          // For simplicity, let's assume it contains the fields that changed or the full task

          // If it's a full replacement (simplest for now):
          if (op.data.containsKey('start') && op.data.containsKey('end')) {
            taskMap[taskId] = _createTaskFromOp(op, existingTask);
          }
        }
      } else if (op.type == 'DELETE_TASK') {
        final taskId = op.data['id'] as String;
        final existingTask = taskMap[taskId];
        if (existingTask == null || (existingTask.lastUpdated ?? 0) < op.timestamp) {
          taskMap.remove(taskId);
        }
      }
    }

    return taskMap.values.toList();
  }

  LegacyGanttTask _createTaskFromOp(Operation op, LegacyGanttTask? existing) {
    // This is a simplified reconstruction. In a real app, you'd probably
    // have a more robust fromJson or copyWithFromMap method.
    // Here we assume the operation carries the essential data.

    final data = op.data;

    return LegacyGanttTask(
      id: data['id'],
      rowId: data['rowId'] ?? existing?.rowId ?? '',
      start: DateTime.parse(data['start']),
      end: DateTime.parse(data['end']),
      name: data['name'] ?? existing?.name,
      color: existing?.color, // Color serialization is tricky, skipping for brevity
      textColor: existing?.textColor,
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
}
