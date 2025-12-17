import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import '../data/mock_api_service.dart';
import '../data/models.dart';
import '../ui/gantt_grid_data.dart';

class ProcessedScheduleData {
  final List<LegacyGanttTask> ganttTasks;
  final List<LegacyGanttTask> conflictIndicators;
  final List<GanttGridData> gridData;
  final Map<String, int> rowMaxStackDepth;
  final Map<String, GanttEventData> eventMap;
  final GanttResponse apiResponse;

  ProcessedScheduleData({
    required this.ganttTasks,
    required this.conflictIndicators,
    required this.gridData,
    required this.rowMaxStackDepth,
    required this.eventMap,
    required this.apiResponse,
  });
}

class GanttScheduleService {
  final MockApiService _apiService = MockApiService();

  Future<ProcessedScheduleData> fetchAndProcessSchedule({
    required DateTime startDate,
    required int range,
    required int personCount,
    required int jobCount,
  }) async {
    final formattedStartDate = _formatDateToISO(startDate);
    final formattedEndDate = _formatDateToISO(startDate.add(Duration(days: range)));

    final apiResponseJson = await _apiService.get(
      'yeah',
      params: {
        'startDateIso': formattedStartDate,
        'endDateIso': formattedEndDate,
        'personCount': personCount,
        'jobCount': jobCount
      },
    );

    final apiResponse = GanttResponse.fromJson(apiResponseJson);

    return await processGanttResponse(apiResponse, startDate: startDate, range: range);
  }

  /// Processes a [GanttResponse] object to produce data ready for the UI.
  ///
  /// This logic is separated so it can be re-run on the existing API response
  /// after in-memory mutations, ensuring data consistency without another API call.
  Future<ProcessedScheduleData> processGanttResponse(
    GanttResponse apiResponse, {
    required DateTime startDate,
    required int range,
    bool showConflicts = true,
    bool isFirstLoad = true,
    bool showEmptyParentRows = false,
  }) async {
    if (!apiResponse.success) {
      throw Exception(apiResponse.error ?? 'Failed to load schedule data');
    }

    final eventMap = {for (var event in apiResponse.eventsData) event.id: event};
    final jobMap = {
      for (var resource in apiResponse.resourcesData)
        for (var job in resource.children) job.id: job
    };

    final parentResourceIds = apiResponse.resourcesData.map((r) => r.id).toSet();
    final List<LegacyGanttTask> fetchedTasks = [];
    for (var assignment in apiResponse.assignmentsData) {
      final event = eventMap[assignment.event];
      final isParentAssignment = parentResourceIds.contains(assignment.resource);

      if (event != null && event.utcStartDate != null && event.utcEndDate != null && !isParentAssignment) {
        final colorHex = event.referenceData?.taskColor;
        final textColorHex = event.referenceData?.taskTextColor;
        final job = jobMap[assignment.resource];

        fetchedTasks.add(LegacyGanttTask(
          id: assignment.id,
          rowId: assignment.resource,
          name: event.name ?? 'Unnamed Task',
          start: DateTime.parse(event.utcStartDate!),
          end: DateTime.parse(event.utcEndDate!),
          color: _parseColorHex(colorHex != null ? '#$colorHex' : null, Colors.blue),
          textColor: _parseColorHex(textColorHex != null ? '#$textColorHex' : null, Colors.white),
          originalId: event.id,
          isSummary: false,
          completion: job?.completion ?? 0.0,
        ));
      }
    }
    for (final resource in apiResponse.resourcesData) {
      final childRowIds = resource.children.map((child) => child.id).toSet();
      final childrenTasks = fetchedTasks.where((task) => childRowIds.contains(task.rowId)).toList();

      if (childrenTasks.isNotEmpty) {
        DateTime minStart = childrenTasks.first.start;
        DateTime maxEnd = childrenTasks.first.end;

        for (final task in childrenTasks.skip(1)) {
          if (task.start.isBefore(minStart)) minStart = task.start;
          if (task.end.isAfter(maxEnd)) maxEnd = task.end;
        }

        fetchedTasks.add(LegacyGanttTask(
            id: 'summary-task-${resource.id}',
            rowId: resource.id,
            name: resource.taskName ?? resource.name,
            start: minStart,
            end: maxEnd,
            isSummary: true));
      }
    }

    final Map<String, List<Duration>> jobEventDurations = {};
    for (final assignment in apiResponse.assignmentsData) {
      final event = eventMap[assignment.event];
      if (event != null && event.utcStartDate != null && event.utcEndDate != null) {
        final start = DateTime.parse(event.utcStartDate!);
        final end = DateTime.parse(event.utcEndDate!);
        if (end.isAfter(start)) {
          jobEventDurations.putIfAbsent(assignment.resource, () => []).add(end.difference(start));
        }
      }
    }

    final activeRowIds = fetchedTasks.map((task) => task.rowId).toSet();

    final List<GanttGridData> processedGridData = [];
    bool isFirstParent = isFirstLoad;
    for (final resource in apiResponse.resourcesData) {
      final visibleChildren = resource.children
          .where((job) => activeRowIds.contains(job.id))
          .map((job) => GanttGridData.fromJob(job))
          .toList();

      final bool hasDirectTask = activeRowIds.contains(resource.id);
      if (showEmptyParentRows || hasDirectTask || visibleChildren.isNotEmpty) {
        double totalWeightedDurationMs = 0;
        double totalDurationMs = 0;

        for (final job in resource.children) {
          if (activeRowIds.contains(job.id)) {
            final durations = jobEventDurations[job.id] ?? [];
            final jobCompletion = job.completion ?? 0.0;
            for (final duration in durations) {
              totalDurationMs += duration.inMilliseconds;
              totalWeightedDurationMs += duration.inMilliseconds * jobCompletion;
            }
          }
        }

        final double parentCompletion = totalDurationMs > 0 ? totalWeightedDurationMs / totalDurationMs : 0.0;

        processedGridData.add(GanttGridData(
          id: resource.id,
          name: resource.name,
          isParent: true,
          children: visibleChildren,
          taskName: resource.taskName,
          isExpanded: isFirstParent, // Default to collapsed
          completion: parentCompletion,
        ));
        isFirstParent = false;
      }
    }

    for (var timeRange in apiResponse.resourceTimeRangesData) {
      if (timeRange.utcStartDate.isNotEmpty && timeRange.utcEndDate.isNotEmpty) {
        fetchedTasks.add(LegacyGanttTask(
          id: timeRange.id,
          rowId: timeRange.resourceId,
          start: DateTime.parse(timeRange.utcStartDate),
          end: DateTime.parse(timeRange.utcEndDate),
          isTimeRangeHighlight: true,
        ));
      }
    }

    for (var resource in apiResponse.resourcesData) {
      final summaryEvent = apiResponse.eventsData.firstWhere(
        (event) => event.id == 'event-${resource.id}-summary',
        orElse: () => GanttEventData(id: '', utcStartDate: null, utcEndDate: null),
      );
      if (summaryEvent.utcStartDate != null && summaryEvent.utcEndDate != null) {
        fetchedTasks.add(LegacyGanttTask(
          id: 'summary-highlight-${summaryEvent.id}',
          rowId: resource.id,
          start: DateTime.parse(summaryEvent.utcStartDate!),
          end: DateTime.parse(summaryEvent.utcEndDate!),
          isTimeRangeHighlight: true,
        ));
      }
    }

    final allRows = processedGridData.expand((e) => [e, ...e.children]).map((e) => LegacyGanttRow(id: e.id)).toList();
    fetchedTasks.addAll(_generateWeekendHighlights(allRows, startDate, startDate.add(Duration(days: range))));

    final (stackedTasks, maxDepthPerRow, conflictIndicators) =
        _calculateTaskStacking(fetchedTasks, apiResponse, showConflicts: showConflicts);

    return ProcessedScheduleData(
      ganttTasks: stackedTasks,
      gridData: processedGridData,
      rowMaxStackDepth: maxDepthPerRow,
      eventMap: eventMap,
      apiResponse: apiResponse,
      conflictIndicators: conflictIndicators,
    );
  }

  String _formatDateToISO(DateTime date) => date.toIso8601String().substring(0, 19);

  Color _parseColorHex(String? hexString, Color defaultColor) {
    if (hexString == null || hexString.isEmpty) return defaultColor;
    String cleanHex = hexString.startsWith('#') ? hexString.substring(1) : hexString;
    if (cleanHex.length == 3) cleanHex = cleanHex.split('').map((char) => char * 2).join();
    if (cleanHex.length == 6) {
      try {
        return Color(int.parse(cleanHex, radix: 16) + 0xFF000000);
      } catch (e) {
        debugPrint('Error parsing hex color "$hexString": $e');
        return defaultColor;
      }
    }
    return defaultColor;
  }

  List<LegacyGanttTask> _generateWeekendHighlights(List<LegacyGanttRow> rows, DateTime start, DateTime end) {
    if (rows.length > 100) {
      return [];
    }
    final List<LegacyGanttTask> holidays = [];
    for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
      if (day.weekday == DateTime.saturday) {
        final weekendStart = day;
        final weekendEnd = day.add(const Duration(days: 2));
        for (final row in rows) {
          holidays.add(LegacyGanttTask(
            id: 'weekend-${row.id}-${day.toIso8601String()}',
            rowId: row.id,
            start: weekendStart,
            end: weekendEnd,
            isTimeRangeHighlight: true,
          ));
        }
      }
    }
    return holidays;
  }

  (List<LegacyGanttTask>, Map<String, int>, List<LegacyGanttTask>) publicCalculateTaskStacking(
          List<LegacyGanttTask> tasks, GanttResponse apiResponse,
          {bool showConflicts = true, Set<String>? visibleRowIds}) =>
      _calculateTaskStacking(tasks, apiResponse, showConflicts: showConflicts, visibleRowIds: visibleRowIds);

  (List<LegacyGanttTask>, Map<String, int>, List<LegacyGanttTask>) _calculateTaskStacking(
      List<LegacyGanttTask> tasks, GanttResponse apiResponse,
      {bool showConflicts = true, Set<String>? visibleRowIds}) {
    final Map<String, List<LegacyGanttTask>> eventTasksByRow = {};
    final List<LegacyGanttTask> nonStackableTasks = [];
    final List<LegacyGanttTask> actualEventTasks = [];

    for (var task in tasks) {
      if (task.isTimeRangeHighlight) {
        nonStackableTasks.add(task); // Only add highlights
      } else if (!task.isOverlapIndicator) {
        actualEventTasks.add(task);
      }
    }

    for (var task in actualEventTasks) {
      eventTasksByRow.putIfAbsent(task.rowId, () => []).add(task);
    }

    final List<LegacyGanttTask> stackedTasks = [];
    final Map<String, int> rowMaxDepth = {};

    eventTasksByRow.forEach((rowId, rowTasks) {
      final sortedRowTasks = List<LegacyGanttTask>.from(rowTasks)..sort((a, b) => a.start.compareTo(b.start));

      final Map<String, int> taskStackIndices = {};
      final List<DateTime> stackEndTimes = [];

      for (var currentTask in sortedRowTasks) {
        int currentStackIndex = -1;
        for (int i = 0; i < stackEndTimes.length; i++) {
          if (stackEndTimes[i].isBefore(currentTask.start) || stackEndTimes[i] == currentTask.start) {
            currentStackIndex = i;
            break;
          }
        }

        if (currentStackIndex == -1) {
          currentStackIndex = stackEndTimes.length;
          stackEndTimes.add(currentTask.end);
        } else {
          stackEndTimes[currentStackIndex] = currentTask.end;
        }

        taskStackIndices[currentTask.id] = currentStackIndex;
      }
      rowMaxDepth[rowId] = stackEndTimes.length;

      for (var task in rowTasks) {
        final stackIndex = taskStackIndices[task.id] ?? 0;
        stackedTasks.add(task.copyWith(stackIndex: stackIndex));
      }
    });

    final Map<String, String> lineItemToContactMap = {
      for (final resource in apiResponse.resourcesData)
        for (final child in resource.children) child.id: resource.id
    };
    final parentResourceIds = apiResponse.resourcesData.map((r) => r.id).toSet();

    List<LegacyGanttTask> conflictIndicators = [];
    if (showConflicts) {
      final conflictDetector = LegacyGanttConflictDetector();
      final tasksForConflictDetection = stackedTasks;
      conflictIndicators = conflictDetector.run<String>(
        tasks: tasksForConflictDetection,
        taskGrouper: (task) {
          final resourceId = task.rowId;
          final group =
              lineItemToContactMap[resourceId] ?? (parentResourceIds.contains(resourceId) ? resourceId : null);
          final finalGroup = group ?? resourceId;
          return finalGroup;
        },
      );
    }

    var finalTasks = [...stackedTasks, ...nonStackableTasks];
    var finalConflictIndicators = conflictIndicators;
    var finalRowMaxDepth = Map<String, int>.from(rowMaxDepth);
    return (finalTasks, finalRowMaxDepth, finalConflictIndicators);
  }
}
