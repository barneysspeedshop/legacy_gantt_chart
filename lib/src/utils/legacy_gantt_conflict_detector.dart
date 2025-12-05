import '../models/legacy_gantt_task.dart';

/// A utility to detect and create indicators for conflicting tasks in a Gantt chart.
///
/// This class encapsulates the logic for identifying when two or more tasks
/// within the same logical group (e.g., assigned to the same person) overlap in time.
class LegacyGanttConflictDetector {
  /// Runs the conflict detection process.
  ///
  /// Takes a list of all [tasks] and a [taskGrouper] function. The [taskGrouper]
  /// is responsible for assigning each task to a group. Tasks with the same
  /// group key will be checked against each other for conflicts.
  ///
  /// - [tasks]: The list of all `LegacyGanttTask`s to process.
  /// - [taskGrouper]: A function that returns a group identifier (of type `T`)
  ///   for a given task. If it returns `null`, the task is ignored for conflict detection.
  ///
  /// Returns a list of new [LegacyGanttTask]s that should be rendered as
  /// conflict indicators (i.e., red bars).
  List<LegacyGanttTask> run<T>({
    required List<LegacyGanttTask> tasks,
    required T? Function(LegacyGanttTask task) taskGrouper,
  }) {
    final List<LegacyGanttTask> conflictIndicators = [];
    final eventTasksForOverlapDetection = tasks.where((t) => !t.isTimeRangeHighlight).toList();

    // 1. Group tasks using the provided grouper function.
    final Map<T, List<LegacyGanttTask>> groupedTasks = {};
    for (final task in eventTasksForOverlapDetection) {
      final key = taskGrouper(task);
      if (key != null) {
        groupedTasks.putIfAbsent(key, () => []).add(task);
      }
    }

    // 2. Find and create indicators for overlaps within each group.
    groupedTasks.forEach((groupId, shifts) {
      final actualShifts = shifts.where((s) => !s.isSummary).toList();
      if (actualShifts.length < 2) {
        return;
      }

      // Find raw overlaps between child shifts
      final rawOverlaps = _findRawOverlaps(actualShifts);
      if (rawOverlaps.isEmpty) {
        return;
      }

      // Add indicators for the conflicting child tasks
      // Add indicators for the conflicting child tasks
      for (int i = 0; i < rawOverlaps.length; i++) {
        final overlap = rawOverlaps[i];
        conflictIndicators
            .add(_createIndicator(task: overlap.taskA, start: overlap.start, end: overlap.end, idSuffix: 'a-$i'));
        conflictIndicators
            .add(_createIndicator(task: overlap.taskB, start: overlap.start, end: overlap.end, idSuffix: 'b-$i'));
      }

      // Merge overlap intervals to handle complex multi-shift conflicts
      final mergedOverlaps = _mergeOverlapIntervals(rawOverlaps.map((o) => (start: o.start, end: o.end)).toList());

      // Find all summary tasks within the same group
      final allParentSummaryTasks = shifts.where((task) => task.isSummary).toList();

      // For each distinct conflict period, create an indicator on the parent summary bar
      for (int i = 0; i < mergedOverlaps.length; i++) {
        final mergedOverlap = mergedOverlaps[i];

        // Find parent summary bars that intersect with this conflict period
        final involvedParentSummaryTasks = allParentSummaryTasks.where(
          (summaryTask) =>
              summaryTask.start.isBefore(mergedOverlap.end) && summaryTask.end.isAfter(mergedOverlap.start),
        );

        for (final summaryTask in involvedParentSummaryTasks) {
          // The indicator should only cover the intersection of the summary bar and the conflict
          final indicatorStart =
              summaryTask.start.isAfter(mergedOverlap.start) ? summaryTask.start : mergedOverlap.start;
          final indicatorEnd = summaryTask.end.isBefore(mergedOverlap.end) ? summaryTask.end : mergedOverlap.end;

          if (indicatorEnd.isAfter(indicatorStart)) {
            conflictIndicators.add(LegacyGanttTask(
              id: 'overlap-parent-${summaryTask.id}-$i',
              rowId: summaryTask.rowId, // Use the summary task's rowId
              start: indicatorStart,
              end: indicatorEnd,
              stackIndex: summaryTask.stackIndex,
              isOverlapIndicator: true,
            ));
          }
        }
      }
    });

    return conflictIndicators;
  }

  /// Gets the actual work intervals for a task.
  /// If the task has segments, it returns the start/end of each segment.
  /// Otherwise, it returns the overall start/end of the task.
  List<({DateTime start, DateTime end})> _getWorkIntervals(LegacyGanttTask task) {
    if (task.segments != null && task.segments!.isNotEmpty) {
      return task.segments!.map((s) => (start: s.start, end: s.end)).toList();
    }
    return [(start: task.start, end: task.end)];
  }

  List<({LegacyGanttTask taskA, LegacyGanttTask taskB, DateTime start, DateTime end})> _findRawOverlaps(
      List<LegacyGanttTask> shifts) {
    final List<({LegacyGanttTask taskA, LegacyGanttTask taskB, DateTime start, DateTime end})> overlaps = [];
    for (int i = 0; i < shifts.length; i++) {
      for (int j = i + 1; j < shifts.length; j++) {
        final taskA = shifts[i];
        final taskB = shifts[j];

        // Get the work intervals for each task (segments or the whole task)
        final intervalsA = _getWorkIntervals(taskA);
        final intervalsB = _getWorkIntervals(taskB);

        // Compare each interval of taskA with each interval of taskB
        for (final intervalA in intervalsA) {
          for (final intervalB in intervalsB) {
            // Check for a time overlap between the two intervals
            if (intervalA.start.isBefore(intervalB.end) && intervalA.end.isAfter(intervalB.start)) {
              // Calculate the exact start and end of the overlap
              final overlapStart = intervalA.start.isAfter(intervalB.start) ? intervalA.start : intervalB.start;
              final overlapEnd = intervalA.end.isBefore(intervalB.end) ? intervalA.end : intervalB.end;

              // If the overlap has a positive duration, record it
              if (overlapEnd.isAfter(overlapStart)) {
                overlaps.add((taskA: taskA, taskB: taskB, start: overlapStart, end: overlapEnd));
              }
            }
          }
        }
      }
    }
    return overlaps;
  }

  LegacyGanttTask _createIndicator(
          {required LegacyGanttTask task, required DateTime start, required DateTime end, required String idSuffix}) =>
      LegacyGanttTask(
          id: 'overlap-${task.id}-$idSuffix',
          rowId: task.rowId,
          start: start,
          end: end,
          stackIndex: task.stackIndex,
          isOverlapIndicator: true);

  List<({DateTime start, DateTime end})> _mergeOverlapIntervals(List<({DateTime start, DateTime end})> intervals) {
    if (intervals.isEmpty) {
      return [];
    }
    intervals.sort((a, b) => a.start.compareTo(b.start));
    final List<({DateTime start, DateTime end})> merged = [intervals.first];
    for (int i = 1; i < intervals.length; i++) {
      final current = intervals[i];
      final lastMerged = merged.last;
      if (current.start.isBefore(lastMerged.end) || current.start == lastMerged.end) {
        final newEnd = current.end.isAfter(lastMerged.end) ? current.end : lastMerged.end;
        merged[merged.length - 1] = (start: lastMerged.start, end: newEnd);
      } else {
        merged.add(current);
      }
    }
    return merged;
  }
}
