import '../models/legacy_gantt_task.dart';
import '../models/resource_bucket.dart';

/// Aggregates the load for each resource from the provided list of [tasks].
///
/// Returns a map where the key is the `resourceId` and the value is a list of
/// [ResourceBucket]s sorted by date.
import '../models/work_calendar.dart';

/// Aggregates the load for each resource from the provided list of [tasks].
///
/// Returns a map where the key is the `resourceId` and the value is a list of
/// [ResourceBucket]s sorted by date.
Map<String, List<ResourceBucket>> aggregateResourceLoad(
  List<LegacyGanttTask> tasks, {
  DateTime? start,
  DateTime? end,
  WorkCalendar? workCalendar,
}) {
  final Map<String, Map<DateTime, double>> resourceDailyLoad = {};

  for (final task in tasks) {
    if (task.resourceId == null) continue;
    if (task.isSummary || task.isMilestone) continue;

    final double taskLoad = task.load;

    DateTime current = DateTime(task.start.year, task.start.month, task.start.day);
    final taskEndDay = DateTime(task.end.year, task.end.month, task.end.day);

    while (current.isBefore(taskEndDay) || current.isAtSameMomentAs(taskEndDay)) {
      bool shouldAddLoad = true;

      if (task.usesWorkCalendar && workCalendar != null) {
        if (!workCalendar.isWorkingDay(current)) {
          shouldAddLoad = false;
        }
      }

      if (shouldAddLoad && (start == null || !current.isBefore(start)) && (end == null || !current.isAfter(end))) {
        if (!resourceDailyLoad.containsKey(task.resourceId)) {
          resourceDailyLoad[task.resourceId!] = {};
        }

        final dailyLoad = resourceDailyLoad[task.resourceId!]!;
        dailyLoad[current] = (dailyLoad[current] ?? 0.0) + taskLoad;
      }

      current = current.add(const Duration(days: 1));
    }
  }

  final Map<String, List<ResourceBucket>> result = {};
  resourceDailyLoad.forEach((resourceId, dailyMap) {
    final buckets = dailyMap.entries
        .map((entry) => ResourceBucket(
              date: entry.key,
              resourceId: resourceId,
              totalLoad: entry.value,
            ))
        .toList();

    buckets.sort((a, b) => a.date.compareTo(b.date));

    result[resourceId] = buckets;
  });

  return result;
}
