import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/offline_sync.dart';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart' as scrubber;

import '../data/models.dart';
import '../data/local/local_gantt_repository.dart';
import '../services/gantt_schedule_service.dart';
import '../ui/dialogs/create_task_dialog.dart';
import '../ui/gantt_grid_data.dart';
import '../data/local/gantt_db.dart';

/// An enum to manage the different theme presets demonstrated in the example.
enum ThemePreset {
  standard,
  forest,
  midnight,
}

enum TimelineAxisFormat {
  auto,
  dayOfMonth,
  dayAndMonth,
  monthAndYear,
  dayOfWeek,
  custom,
}

class GanttViewModel extends ChangeNotifier {
  final LocalGanttRepository _localRepository = LocalGanttRepository();
  bool _useLocalDatabase = false;
  StreamSubscription<List<LegacyGanttTask>>? _tasksSubscription;
  StreamSubscription<List<LegacyGanttTaskDependency>>? _dependenciesSubscription;
  StreamSubscription<List<LocalResource>>? _resourcesSubscription;

  /// The main list of tasks displayed on the Gantt chart, including regular tasks,
  /// summary tasks, highlights, and conflict indicators.
  List<LegacyGanttTask> _ganttTasks = [];
  List<LegacyGanttTask> get data => UnmodifiableListView(_ganttTasks);

  /// The complete source list of tasks from the database or API.
  /// Used for filtering visible rows without losing data.
  List<LegacyGanttTask> _allGanttTasks = [];

  /// A separate list for conflict indicators.
  List<LegacyGanttTask> _conflictIndicators = [];

  /// The list of dependencies between tasks.
  List<LegacyGanttTaskDependency> _dependencies = [];
  List<LocalResource> _localResources = [];

  /// The hierarchical data structure for the grid on the left side of the chart.
  List<GanttGridData> _gridData = [];

  /// A map that stores the maximum number of overlapping tasks for each row,
  /// used to calculate the row's total height.
  Map<String, int> _rowMaxStackDepth = {};

  /// The original API response from the service. This is kept to allow for
  /// reprocessing data (e.g., when a task is edited) and for exporting the original data structure.
  GanttResponse? _apiResponse;

  /// A map for quick lookups of original event data by task ID, used for tooltips.
  Map<String, GanttEventData> _eventMap = {};

  /// The currently selected theme preset.
  ThemePreset _selectedTheme = ThemePreset.standard;

  /// Flags to enable or disable interactive features of the Gantt chart.
  bool _dragAndDropEnabled = true;
  bool _resizeEnabled = true;
  bool _createTasksEnabled = true;
  bool _dependencyCreationEnabled = true;
  bool _showConflicts = true;
  bool _showEmptyParentRows = false;
  bool _showDependencies = true;
  bool _showResourceHistogram = false;
  bool _enableWorkCalendar = false;

  bool _showCriticalPath = false;
  bool _rollUpMilestones = false;
  Map<String, CpmTaskStats> _cpmStats = {};

  /// The width of the resize handles on the edges of task bars.
  double _resizeHandleWidth = 10.0;

  /// The height of a single task lane within a row.
  final double rowHeight = 27.0;

  /// The currently selected locale for date and time formatting.
  String _selectedLocale = 'en_US';

  /// The format for labels on the timeline axis.
  TimelineAxisFormat _selectedAxisFormat = TimelineAxisFormat.dayOfMonth;

  /// A function to format the date in the resize tooltip. This is updated by the view.
  String Function(DateTime)? _resizeTooltipDateFormat;

  /// The type of progress indicator to show during loading.
  GanttLoadingIndicatorType _loadingIndicatorType = GanttLoadingIndicatorType.circular;

  /// The position of the linear progress indicator.
  GanttLoadingIndicatorPosition _loadingIndicatorPosition = GanttLoadingIndicatorPosition.top;

  /// The start date for fetching schedule data.
  DateTime _startDate = DateTime.now();

  /// Default start and end times used when creating new tasks.
  final TimeOfDay _defaultStartTime = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay _defaultEndTime = const TimeOfDay(hour: 17, minute: 0);

  /// The number of days to fetch data for.
  int _range = 14; // Default range for data fetching

  /// The number of "persons" (parent rows) to generate in the sample data.
  int _personCount = 10;

  /// The number of "jobs" (child rows) to generate in the sample data.
  int _jobCount = 16;

  /// The start and end dates of the entire dataset.
  DateTime? _totalStartDate;
  DateTime? _totalEndDate;

  /// The start and end dates of the currently visible window in the Gantt chart.
  DateTime? _visibleStartDate;
  DateTime? _visibleEndDate;

  /// Padding added to the total date range to provide scrollable space at the edges of the timeline.
  final Duration _ganttStartPadding = const Duration(days: 7);
  final Duration _ganttEndPadding = const Duration(days: 7);

  /// Scroll controllers to synchronize the vertical scroll of the grid and chart,
  /// and to manage the horizontal scroll of the chart.
  final ScrollController _ganttScrollController = ScrollController();

  bool get showResourceHistogram => _showResourceHistogram;
  void setShowResourceHistogram(bool value) {
    if (_showResourceHistogram == value) return;
    _showResourceHistogram = value;
    notifyListeners();
  }

  bool get rollUpMilestones => _rollUpMilestones;
  void setRollUpMilestones(bool value) {
    if (_rollUpMilestones == value) return;
    _rollUpMilestones = value;
    notifyListeners();
  }

  @visibleForTesting
  void setSyncClient(GanttSyncClient client) {
    _syncClient = client;
  }

  bool get enableWorkCalendar => _enableWorkCalendar;
  void setEnableWorkCalendar(bool value) {
    if (_enableWorkCalendar == value) return;
    _enableWorkCalendar = value;

    if (_allGanttTasks.isNotEmpty) {
      final updatedTasks = _allGanttTasks.map((t) => t.copyWith(usesWorkCalendar: value)).toList();
      _allGanttTasks = updatedTasks;
      _localRepository.insertTasks(updatedTasks); // Batch update local DB

      _processLocalData();
    }

    notifyListeners();
  }

  WorkCalendar? get workCalendar => _enableWorkCalendar
      ? WorkCalendar(
          weekendDays: const {DateTime.saturday, DateTime.sunday},
          holidays: {DateTime(DateTime.now().year, 12, 25)}, // Christmas for current year
        )
      : null;
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _ganttHorizontalScrollController = ScrollController();

  bool _isSyncingGridScroll = false;
  bool _isSyncingGanttScroll = false;
  bool _areScrollListenersAttached = false;

  /// The controller for the Gantt chart.
  late final LegacyGanttController controller;

  /// A flag to prevent a feedback loop between the timeline scrubber and the horizontal scroll controller.
  bool _isScrubberUpdating = false; // Prevents feedback loop between scroller and scrubber

  /// A flag to indicate when data is being fetched.
  bool _isLoading = true;

  /// The ID of the task that currently has keyboard focus.
  String? _focusedTaskId;
  int _seedVersion = 0;
  int get seedVersion => _seedVersion;
  bool _pendingSeedReset = false;

  OverlayEntry? _tooltipOverlay;
  String? _hoveredTaskId;

  final GanttScheduleService _scheduleService = GanttScheduleService();
  GanttResponse? get apiResponse => _apiResponse;

  bool get useLocalDatabase => _useLocalDatabase;

  Future<void> setUseLocalDatabase(bool value) async {
    if (_useLocalDatabase == value) return;
    _useLocalDatabase = value;
    notifyListeners();
    if (_useLocalDatabase) {
      await _initLocalMode();
    } else {
      await _exitLocalMode();
    }
  }

  bool _shouldAutoSeed = false;

  Future<void> _initLocalMode() async {
    _isLoading = true;
    _shouldAutoSeed = true;
    notifyListeners();
    await _localRepository.init();

    _tasksSubscription?.cancel();
    _dependenciesSubscription?.cancel();
    _resourcesSubscription?.cancel();

    _resourcesSubscription = _localRepository.watchResources().listen((resources) {
      _localResources = resources;
      if (_ganttTasks.isNotEmpty) {
        _processLocalData();
      }
    });

    _tasksSubscription = _localRepository.watchTasks().listen((tasks) async {
      if (tasks.isEmpty && _shouldAutoSeed) {
        _shouldAutoSeed = false;
        await seedLocalDatabase();
        return;
      }
      _shouldAutoSeed = false;

      _allGanttTasks = tasks;
      await _processLocalData();
    });

    _dependenciesSubscription = _localRepository.watchDependencies().listen((deps) {
      _dependencies = deps;
      _syncToController();
      notifyListeners();
    });

    _syncClient ??= OfflineGanttSyncClient(GanttDb.db);

    _pendingSeedReset = true;
    notifyListeners();
  }

  Future<void> _processLocalData() async {
    if (_allGanttTasks.isEmpty) {
      _isLoading = false;
      _conflictIndicators = [];
      _gridData = [];
      _rowMaxStackDepth = {};
      notifyListeners();
      return;
    }

    _gridData = _buildGridDataFromResources(_localResources, _allGanttTasks);
    _cachedFlatGridData = null; // Invalidate cache

    if (_pendingSeedReset) {
      _seedVersion++;
      _pendingSeedReset = false;
    }

    final visibleRowIds = <String>{};
    void collectVisible(List<GanttGridData> nodes) {
      for (final node in nodes) {
        visibleRowIds.add(node.id);
        if (node.isExpanded) {
          collectVisible(node.children);
        }
      }
    }

    collectVisible(_gridData);

    final List<GanttResourceData> resourcesData = [];
    final parentResources = _localResources.where((r) => r.parentId == null);

    for (final parent in parentResources) {
      final List<LocalResource> allDescendants = [];
      void collectDescendants(String parentId) {
        final children = _localResources.where((r) => r.parentId == parentId);
        for (final child in children) {
          allDescendants.add(child);
          collectDescendants(child.id);
        }
      }

      collectDescendants(parent.id);

      final children = allDescendants
          .map((child) => GanttJobData(
                id: child.id,
                name: child.name ?? 'Unnamed', // Name defaults
                taskName: null,
                status: 'Open', // Dummy data
                taskColor: '888888', // Dummy data
                completion: 0,
              ))
          .toList();

      resourcesData.add(GanttResourceData(
        id: parent.id,
        name: parent.name ?? 'Unnamed',
        taskName: null,
        children: children,
      ));
    }

    final dummyResponse = GanttResponse(
      success: true,
      resourcesData: resourcesData,
      eventsData: [],
      assignmentsData: [],
      resourceTimeRangesData: [],
    );
    _apiResponse = dummyResponse;

    final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
        _allGanttTasks, dummyResponse,
        showConflicts: _showConflicts, visibleRowIds: visibleRowIds);

    _ganttTasks = recalculatedTasks;
    _conflictIndicators = newConflictIndicators;
    _rowMaxStackDepth = newMaxDepth;

    if (_ganttTasks.isNotEmpty) {
      DateTime minStart = _ganttTasks.first.start;
      DateTime maxEnd = _ganttTasks.first.end;
      for (final task in _ganttTasks) {
        if (task.start.isBefore(minStart)) minStart = task.start;
        if (task.end.isAfter(maxEnd)) maxEnd = task.end;
      }
      _totalStartDate = minStart;
      _totalEndDate = maxEnd;

      if (_visibleStartDate == null || _visibleEndDate == null) {
        _visibleStartDate = _totalStartDate!.subtract(_ganttStartPadding);
        _visibleEndDate = _totalEndDate!.add(_ganttEndPadding);
      }
    }

    _isLoading = false;
    _syncToController();
    notifyListeners();
  }

  Future<void> convertTaskType(LegacyGanttTask task, String newType) async {
    LegacyGanttTask newTask = task;
    String ganttType = 'task';

    if (newType == 'milestone') {
      ganttType = 'milestone';
      newTask = task.copyWith(
        isMilestone: true,
        isSummary: false,
        end: task.start,
      );
    } else if (newType == 'summary') {
      ganttType = 'summary';
      DateTime newEnd = task.end;
      if (task.isMilestone && task.start == task.end) {
        newEnd = task.start.add(const Duration(days: 1));
      }
      newTask = task.copyWith(
        isMilestone: false,
        isSummary: true,
        end: newEnd,
      );
    } else if (newType == 'task') {
      ganttType = 'task';
      DateTime newEnd = task.end;
      if (task.isMilestone && task.start == task.end) {
        newEnd = task.start.add(const Duration(days: 1));
      }
      newTask = task.copyWith(
        isMilestone: false,
        isSummary: false,
        end: newEnd,
        propagatesMoveToChildren: true,
        resizePolicy: ResizePolicy.none,
      );
    }

    if (newType != 'summary') {
      newTask = newTask.copyWith(propagatesMoveToChildren: true, resizePolicy: ResizePolicy.none);
    }

    await _localRepository.insertOrUpdateTask(newTask);

    if (_syncClient != null) {
      await _syncClient!.sendOperation(Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': newTask.id,
          'start_date': newTask.start.millisecondsSinceEpoch,
          'end_date': newTask.end.millisecondsSinceEpoch,
          'gantt_type': ganttType,
          'is_summary': newTask.isSummary, // explicit field sometimes used
          'completion': newTask.completion,
          'resourceId': newTask.resourceId,
          'baseline_start': newTask.baselineStart?.millisecondsSinceEpoch,
          'baseline_end': newTask.baselineEnd?.millisecondsSinceEpoch,
          'notes': newTask.notes,
          'uses_work_calendar': newTask.usesWorkCalendar,
          'parentId': newTask.parentId,
          'propagates_move_to_children': newTask.propagatesMoveToChildren,
          'resize_policy': newTask.resizePolicy.index,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }
  }

  Future<void> updateTask(LegacyGanttTask task) async {
    await _localRepository.insertOrUpdateTask(task);

    if (_syncClient != null) {
      String ganttType = 'task';
      if (task.isMilestone) {
        ganttType = 'milestone';
      } else if (task.isSummary) {
        ganttType = 'summary';
      }

      await _syncClient!.sendOperation(Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': task.id,
          'color': task.color?.toARGB32().toRadixString(16),
          'text_color': task.textColor?.toARGB32().toRadixString(16),
          'name': task.name,
          'start_date': task.start.millisecondsSinceEpoch,
          'end_date': task.end.millisecondsSinceEpoch,
          'gantt_type': ganttType,
          'is_summary': task.isSummary,
          'completion': task.completion,
          'resourceId': task.resourceId,
          'baseline_start': task.baselineStart?.millisecondsSinceEpoch,
          'baseline_end': task.baselineEnd?.millisecondsSinceEpoch,
          'notes': task.notes,
          'uses_work_calendar': task.usesWorkCalendar,
          'parentId': task.parentId,
          'propagates_move_to_children': task.propagatesMoveToChildren,
          'resize_policy': task.resizePolicy.index,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user', // Should ideally represent the current user
      ));
    }
  }

  Future<void> updateTaskBehavior(LegacyGanttTask task, {bool? propagates, ResizePolicy? policy}) async {
    final newTask = task.copyWith(
      propagatesMoveToChildren: propagates ?? task.propagatesMoveToChildren,
      resizePolicy: policy ?? task.resizePolicy,
    );
    await updateTask(newTask);
  }

  Map<String, dynamic> exportToJson() {
    final exportedEvents = _ganttTasks
        .where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)
        .map((t) => GanttEventData(
              id: t.id,
              name: t.name,
              utcStartDate: t.start.toUtc().toIso8601String(),
              utcEndDate: t.end.toUtc().toIso8601String(),
              resourceId: t.rowId,
              referenceData: GanttReferenceData(
                taskName: t.name,
                taskColor: t.color?.toARGB32().toRadixString(16).padLeft(8, '0'),
                taskTextColor: t.textColor?.toARGB32().toRadixString(16).padLeft(8, '0'),
              ),
            ))
        .toList();

    final exportedResources = _localResources.where((r) => r.parentId == null).map((parent) {
      final children = _localResources
          .where((r) => r.parentId == parent.id)
          .map((child) => GanttJobData(
                id: child.id,
                name: child.name ?? 'Unnamed',
                status: 'Open',
              ))
          .toList();
      return GanttResourceData(
        id: parent.id,
        name: parent.name ?? 'Unnamed',
        children: children,
      );
    }).toList();

    final response = GanttResponse(
      success: true,
      eventsData: exportedEvents,
      resourcesData: exportedResources,
      assignmentsData: [], // Re-generate if needed, but resourceId in event is usually sufficient
      resourceTimeRangesData: _apiResponse?.resourceTimeRangesData ?? [],
    );

    final json = response.toJson();
    json['conflictIndicators'] = _conflictIndicators
        .map((c) => {
              'id': c.id,
              'rowId': c.rowId,
              'start': c.start.toIso8601String(),
              'end': c.end.toIso8601String(),
            })
        .toList();

    return json;
  }

  Future<void>? _activeSeedingFuture;

  Future<void> seedLocalDatabase() async {
    if (_activeSeedingFuture != null) {
      return _activeSeedingFuture;
    }

    _activeSeedingFuture = _seedLocalDatabaseInternal();
    try {
      await _activeSeedingFuture;
    } finally {
      _activeSeedingFuture = null;
    }
  }

  Future<void> _seedLocalDatabaseInternal() async {
    _isLoading = true;
    notifyListeners();

    await _localRepository.deleteAllDependencies();
    await _localRepository.deleteAllTasks();
    await _localRepository.deleteAllResources();

    if (_syncClient is OfflineGanttSyncClient) {
      await (_syncClient as OfflineGanttSyncClient).clearQueue();
    }

    final processedData = await _scheduleService.fetchAndProcessSchedule(
      startDate: _startDate,
      range: _range,
      personCount: _personCount,
      jobCount: _jobCount,
    );

    final tasks = processedData.ganttTasks;

    final taskByRow = {for (var t in tasks) t.rowId: t};

    void assignParents(List<GanttGridData> nodes, String? parentTaskId) {
      for (final node in nodes) {
        final task = taskByRow[node.id];
        String? currentScopeTaskId = parentTaskId;

        if (task != null) {
          if (parentTaskId != null && task.parentId == null) {
            final updatedTask = task.copyWith(parentId: parentTaskId);
            taskByRow[node.id] = updatedTask;
            final index = tasks.indexWhere((t) => t.id == task.id);
            if (index != -1) tasks[index] = updatedTask;
          }
          currentScopeTaskId = task.id;
        }

        if (node.children.isNotEmpty) {
          assignParents(node.children, currentScopeTaskId);
        }
      }
    }

    assignParents(processedData.gridData, null);

    if (processedData.gridData.isNotEmpty && processedData.gridData.first.children.isNotEmpty) {
      final parentRowId = processedData.gridData.first.id;
      final parentTask = taskByRow[parentRowId];

      final firstChildRowId = processedData.gridData.first.children.first.id;
      final milestoneDate = _startDate.add(const Duration(days: 5));
      final milestone = LegacyGanttTask(
        id: 'milestone_demo_1',
        rowId: firstChildRowId,
        name: 'Project Kick-off',
        start: milestoneDate,
        end: milestoneDate, // start and end are the same for a milestone
        isMilestone: true,
        color: Colors.deepPurple, // Give it a distinct color
        parentId: parentTask?.id,
      );
      tasks.add(milestone);
    }

    final dependencies = <LegacyGanttTaskDependency>[];
    final successorForContainedDemo = tasks.firstWhere(
      (t) => !t.isSummary && !t.isTimeRangeHighlight,
      orElse: () => tasks.first,
    );

    for (final task in tasks) {
      if (task.isSummary) {
        dependencies.add(
          LegacyGanttTaskDependency(
            predecessorTaskId: task.id,
            successorTaskId: successorForContainedDemo.id,
            type: DependencyType.contained,
          ),
        );
      }
    }

    final validTasksForDependency =
        tasks.where((task) => !task.isSummary && !task.isTimeRangeHighlight && !task.isOverlapIndicator).toList();

    if (validTasksForDependency.length > 1) {
      validTasksForDependency.sort((a, b) {
        final startCompare = a.start.compareTo(b.start);
        if (startCompare != 0) return startCompare;
        return a.id.compareTo(b.id);
      });
      dependencies.add(
        LegacyGanttTaskDependency(
          predecessorTaskId: validTasksForDependency[0].id,
          successorTaskId: validTasksForDependency[1].id,
        ),
      );
    }

    await _localRepository.insertTasks(tasks);
    await _localRepository.insertDependencies(dependencies);
    if (_syncClient != null) {
      final opsToSend = <Operation>[];
      opsToSend.add(Operation(
        type: 'RESET_DATA',
        data: {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
      for (final task in tasks) {
        String ganttType = 'task';
        if (task.isMilestone) {
          ganttType = 'milestone';
        } else if (task.isSummary) {
          ganttType = 'summary';
        }

        opsToSend.add(Operation(
          type: 'INSERT_TASK',
          data: {
            'gantt_type': ganttType,
            'data': {
              'id': task.id,
              'rowId': task.rowId,
              'name': task.name,
              'start_date': task.start.millisecondsSinceEpoch,
              'end_date': task.end.millisecondsSinceEpoch,
              'is_summary': task.isSummary,
              'isMilestone': task.isMilestone,
              'color': task.color?.toARGB32().toRadixString(16),
              'textColor': task.textColor?.toARGB32().toRadixString(16),
              'completion': task.completion,
              'resourceId': task.resourceId,
              'baseline_start': task.baselineStart?.millisecondsSinceEpoch,
              'baseline_end': task.baselineEnd?.millisecondsSinceEpoch,
              'notes': task.notes,
              'parentId': task.parentId,
            }
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }
      for (final dep in dependencies) {
        opsToSend.add(Operation(
          type: 'INSERT_DEPENDENCY',
          data: {
            'predecessorTaskId': dep.predecessorTaskId,
            'successorTaskId': dep.successorTaskId,
            'dependency_type': dep.type.name,
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }

      await _syncClient!.sendOperations(opsToSend);
    }

    final expansionMap = <String, bool>{};
    void fillExpansion(List<GanttGridData> nodes) {
      for (final node in nodes) {
        expansionMap[node.id] = node.isExpanded;
        fillExpansion(node.children);
      }
    }

    fillExpansion(processedData.gridData);

    final resourcesToInsert = <LocalResource>[];
    for (int i = 0; i < processedData.apiResponse.resourcesData.length; i++) {
      final resource = processedData.apiResponse.resourcesData[i];
      final isExpanded = i == 0; // Only expand the first one

      resourcesToInsert
          .add(LocalResource(id: resource.id, name: resource.name, parentId: null, isExpanded: isExpanded));

      for (final child in resource.children) {
        resourcesToInsert.add(LocalResource(id: child.id, name: child.name, parentId: resource.id, isExpanded: true));
      }
    }
    await _localRepository.insertResources(resourcesToInsert);

    if (_syncClient != null) {
      final resourceOps = <Operation>[];
      for (int i = 0; i < processedData.apiResponse.resourcesData.length; i++) {
        final resource = processedData.apiResponse.resourcesData[i];
        final isExpanded = i == 0; // Only expand the first one

        resourceOps.add(Operation(
          type: 'INSERT_RESOURCE',
          data: {
            'gantt_type': 'person',
            'data': {
              'id': resource.id,
              'name': resource.name,
              'parentId': null,
              'isExpanded': isExpanded,
            }
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));

        for (final child in resource.children) {
          resourceOps.add(Operation(
            type: 'INSERT_RESOURCE',
            data: {
              'gantt_type': 'job',
              'data': {
                'id': child.id,
                'name': child.name,
                'parentId': resource.id,
                'isExpanded': true,
              }
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            actorId: 'local-user',
          ));
        }
      }
      await _syncClient!.sendOperations(resourceOps);
    }

    _pendingSeedReset = true;
    notifyListeners();
  }

  Future<void> _exitLocalMode() async {
    _tasksSubscription?.cancel();
    _dependenciesSubscription?.cancel();
    await fetchScheduleData();
  }

  List<GanttGridData> _buildGridDataFromResources(List<LocalResource> resources, List<LegacyGanttTask> tasks) {
    if (resources.isEmpty) {
      return _buildGridDataFromTasksFallback(tasks);
    }

    final activeRowIds = tasks.map((t) => t.rowId).toSet();
    final byParent = <String?, List<LocalResource>>{};
    for (final res in resources) {
      byParent.putIfAbsent(res.parentId, () => []).add(res);
    }

    List<GanttGridData> buildNodes(String? parentId) {
      final children = byParent[parentId] ?? [];
      final List<GanttGridData> nodes = [];

      for (final child in children) {
        final grandChildren = buildNodes(child.id);

        final hasDirectTask = activeRowIds.contains(child.id);
        final hasVisibleChildren = grandChildren.isNotEmpty;

        if (hasDirectTask || hasVisibleChildren || _showEmptyParentRows) {
          double completion = 0.0;
          if (hasDirectTask) {
            final rowTasks =
                tasks.where((t) => t.rowId == child.id && !t.isTimeRangeHighlight && !t.isOverlapIndicator).toList();
            if (rowTasks.isNotEmpty) {
              final totalCompletion = rowTasks.fold(0.0, (sum, t) => sum + t.completion);
              completion = totalCompletion / rowTasks.length;
            }
          } else if (hasVisibleChildren) {
            if (grandChildren.isNotEmpty) {
              final total = grandChildren.fold(0.0, (sum, c) => sum + (c.completion ?? 0.0));
              completion = total / grandChildren.length;
            }
          }

          nodes.add(GanttGridData(
            id: child.id,
            name: child.name ?? 'Unnamed',
            isParent: grandChildren.isNotEmpty,
            children: grandChildren,
            isExpanded: child.isExpanded,
            completion: completion,
          ));
        }
      }
      return nodes;
    }

    return buildNodes(null);
  }

  List<GanttGridData> _buildGridDataFromTasksFallback(List<LegacyGanttTask> tasks) {
    final Map<String, List<LegacyGanttTask>> byRow = {};
    for (final t in tasks) {
      if (!t.isTimeRangeHighlight && !t.isOverlapIndicator) {
        byRow.putIfAbsent(t.rowId, () => []).add(t);
      }
    }

    final List<GanttGridData> grid = [];

    for (final key in byRow.keys) {
      grid.add(GanttGridData(
        id: key,
        name: tasks.firstWhereOrNull((t) => t.rowId == key)?.name ?? 'Row $key',
        isParent: false,
        children: [],
      ));
    }
    return grid;
  }

  double? _gridWidth;
  double? _controlPanelWidth = 300.0;
  List<LegacyGanttTask> get ganttTasks => _ganttTasks;
  List<LegacyGanttTask> get conflictIndicators => _showConflicts ? _conflictIndicators : [];
  String Function(DateTime)? get resizeTooltipDateFormat => _resizeTooltipDateFormat;
  List<LegacyGanttTaskDependency> get dependencies => _showDependencies ? _dependencies : [];
  List<GanttGridData> get gridData => _gridData;
  ThemePreset get selectedTheme => _selectedTheme;
  List<LegacyGanttTask> get tasks => _ganttTasks;
  List<LegacyGanttTask> get allGanttTasks => _allGanttTasks;
  bool get dragAndDropEnabled => _dragAndDropEnabled;
  bool get resizeEnabled => _resizeEnabled;
  bool get createTasksEnabled => _createTasksEnabled;
  bool get dependencyCreationEnabled => _dependencyCreationEnabled;
  bool get showConflicts => _showConflicts;
  bool get showEmptyParentRows => _showEmptyParentRows;
  bool get showDependencies => _showDependencies;
  bool get showCriticalPath => _showCriticalPath;
  double get resizeHandleWidth => _resizeHandleWidth;
  DateTime get startDate => _startDate;
  GanttLoadingIndicatorType get loadingIndicatorType => _loadingIndicatorType;
  GanttLoadingIndicatorPosition get loadingIndicatorPosition => _loadingIndicatorPosition;
  TimeOfDay get defaultStartTime => _defaultStartTime;
  TimeOfDay get defaultEndTime => _defaultEndTime;
  int get range => _range;
  int get personCount => _personCount;
  int get jobCount => _jobCount;
  DateTime? get totalStartDate => _totalStartDate;
  DateTime? get totalEndDate => _totalEndDate;
  DateTime? get visibleStartDate => _visibleStartDate;
  DateTime? get visibleEndDate => _visibleEndDate;
  bool get isLoading => _isLoading;
  String? get focusedTaskId => _focusedTaskId;

  String? get selectedRowId {
    if (_focusedTaskId == null) return null;
    final task = _ganttTasks.firstWhereOrNull((t) => t.id == _focusedTaskId);
    return task?.rowId;
  }

  /// The effective total date range, including padding. This is passed to the Gantt chart widget
  /// to define the full scrollable width of the timeline.
  DateTime? get effectiveTotalStartDate => _totalStartDate?.subtract(_ganttStartPadding);
  DateTime? get effectiveTotalEndDate => _totalEndDate?.add(_ganttEndPadding);

  /// A map of row IDs to their maximum task stack depth, used by the Gantt chart widget.
  Map<String, int> get rowMaxStackDepth => _rowMaxStackDepth;
  ScrollController get ganttScrollController => _ganttScrollController;
  ScrollController get gridScrollController => _gridScrollController;
  ScrollController get ganttHorizontalScrollController => _ganttHorizontalScrollController;
  double? get gridWidth => _gridWidth;
  double? get controlPanelWidth => _controlPanelWidth;

  List<GanttGridData> get visibleGridData => _gridData;
  LocalGanttRepository get localRepository => _localRepository;

  /// Returns a signature string representing the current expansion state of the grid.
  /// Used to force a grid rebuild when expansion changes remotely.
  String get expansionSignature {
    final ids = <String>[];
    void traverse(List<GanttGridData> nodes) {
      for (final node in nodes) {
        if (node.isExpanded) ids.add(node.id);
        traverse(node.children);
      }
    }

    traverse(_gridData);
    ids.sort();
    return ids.join(',');
  }

  List<Map<String, dynamic>>? _cachedFlatGridData;

  /// Flattens the hierarchical `_gridData` into a single list suitable for `UnifiedDataGrid`.
  /// It also adds a 'parentId' to each child's data map.
  List<Map<String, dynamic>> get flatGridData {
    if (_cachedFlatGridData != null) return _cachedFlatGridData!;
    final List<Map<String, dynamic>> flatList = [];
    for (final parent in _gridData) {
      flatList.add({
        'id': parent.id,
        'name': parent.name,
        'completion': parent.completion,
        'parentId': null, // Explicitly set parentId to null for root nodes
        'isExpanded': parent.isExpanded,
      });
      for (final child in parent.children) {
        flatList.add({
          'id': child.id,
          'name': child.name,
          'completion': child.completion,
          'parentId': parent.id,
          'isExpanded': child.isExpanded,
        });
      }
    }
    _cachedFlatGridData = flatList;
    return flatList;
  }

  /// Calculates the list of `LegacyGanttRow`s that should be visible based on the
  /// expanded/collapsed state of the parent items in the `gridData`.
  /// This is passed to the `LegacyGanttChartWidget` to determine which rows to render.
  List<LegacyGanttRow> get visibleGanttRows {
    final List<LegacyGanttRow> rows = [];
    for (final item in visibleGridData) {
      rows.add(LegacyGanttRow(id: item.id));
      if (item.isParent && item.isExpanded) {
        rows.addAll(item.children.map((child) => LegacyGanttRow(id: child.id)));
      }
    }
    return rows;
  }

  /// Constructor initializes the locale and sets up a listener for horizontal scrolling.
  GanttViewModel({String? initialLocale, bool useLocalDatabase = false}) {
    controller = LegacyGanttController(
      initialVisibleStartDate: _startDate,
      initialVisibleEndDate: _startDate.add(Duration(days: _range)),
    );

    if (initialLocale != null) {
      _selectedLocale = initialLocale;
    }
    _ganttHorizontalScrollController.addListener(_onGanttScroll);

    if (useLocalDatabase) {
      setUseLocalDatabase(true);
    } else {
      fetchScheduleData();
    }
  }

  /// Attaches the vertical scroll listeners. This should be called after the
  /// widgets using the controllers have been built.
  void attachScrollListeners() {
    if (_areScrollListenersAttached) return;
    _gridScrollController.addListener(_syncGanttScroll);
    _ganttScrollController.addListener(_syncGridScroll);
    _gridScrollController.addListener(_broadcastPresence);

    _areScrollListenersAttached = true;
  }

  void _calculateCpm() {
    if (!_showCriticalPath) {
      _cpmStats = {};
      return;
    }
    final calculator = CriticalPathCalculator();
    final result = calculator.calculate(tasks: _ganttTasks, dependencies: _dependencies);
    _cpmStats = result.taskStats;
  }

  Map<String, CpmTaskStats> get cpmStats => _cpmStats;

  void setShowCriticalPath(bool value) {
    if (_showCriticalPath == value) return;
    _showCriticalPath = value;
    _calculateCpm();
    notifyListeners();
  }

  void _syncGanttScroll() {
    if (_isSyncingGanttScroll) return;
    if (!_ganttScrollController.hasClients || !_gridScrollController.hasClients) return;

    _isSyncingGridScroll = true;
    if (_ganttScrollController.offset != _gridScrollController.offset) {
      _gridScrollController.jumpTo(_ganttScrollController.offset);
    }
    _isSyncingGridScroll = false;
    _broadcastPresence(); // Broadcast vertical scroll change
  }

  void _syncGridScroll() {
    if (_isSyncingGridScroll) return;
    if (!_ganttScrollController.hasClients || !_gridScrollController.hasClients) return;

    _isSyncingGanttScroll = true;
    if (_gridScrollController.offset != _ganttScrollController.offset) {
      _ganttScrollController.jumpTo(_gridScrollController.offset);
    }
    _isSyncingGanttScroll = false;
    _broadcastPresence(); // Broadcast vertical scroll change
  }

  @override
  void dispose() {
    _removeTooltip();
    _tasksSubscription?.cancel();
    _dependenciesSubscription?.cancel();
    _resourcesSubscription?.cancel();
    if (_syncClient is OfflineGanttSyncClient) {
      (_syncClient as OfflineGanttSyncClient).dispose();
    } else if (_syncClient is WebSocketGanttSyncClient) {
      (_syncClient as WebSocketGanttSyncClient).dispose();
    }
    _gridScrollController.removeListener(_syncGanttScroll);
    _ganttScrollController.removeListener(_syncGridScroll);
    _gridScrollController.dispose();
    _ganttScrollController.dispose();
    _ganttHorizontalScrollController.removeListener(_onGanttScroll);
    _ganttHorizontalScrollController.dispose();
    super.dispose();
  }

  /// Disposes of the view model and its resources asynchronously.
  /// This is preferred over [dispose] when using [OfflineGanttSyncClient], as it
  /// ensures that any active background flush operations are completed before
  /// the method returns.
  Future<void> disposeAsync() async {
    _removeTooltip();
    if (_activeSeedingFuture != null) {
      try {
        await _activeSeedingFuture;
      } catch (e) {
        debugPrint('Error waiting for seeding during dispose: $e');
      }
    }

    await _tasksSubscription?.cancel();
    await _dependenciesSubscription?.cancel();
    await _resourcesSubscription?.cancel();
    if (_syncClient is OfflineGanttSyncClient) {
      await (_syncClient as OfflineGanttSyncClient).dispose();
    } else if (_syncClient is WebSocketGanttSyncClient) {
      await (_syncClient as WebSocketGanttSyncClient).dispose();
    }
    _gridScrollController.removeListener(_syncGanttScroll);
    _ganttScrollController.removeListener(_syncGridScroll);
    _gridScrollController.dispose();
    _ganttScrollController.dispose();
    _ganttHorizontalScrollController.removeListener(_onGanttScroll);
    _ganttHorizontalScrollController.dispose();
    super.dispose();
  }

  void setGridWidth(double? value) {
    _gridWidth = value;
    notifyListeners();
  }

  void setControlPanelWidth(double? value) {
    if (_controlPanelWidth == value) return;
    _controlPanelWidth = value;
    notifyListeners();
  }

  void setSelectedTheme(ThemePreset theme) {
    _selectedTheme = theme;
    notifyListeners();
  }

  void setDragAndDropEnabled(bool value) {
    _dragAndDropEnabled = value;
    notifyListeners();
  }

  void setResizeEnabled(bool value) {
    _resizeEnabled = value;
    notifyListeners();
  }

  void setCreateTasksEnabled(bool value) {
    _createTasksEnabled = value;
    notifyListeners();
  }

  void setDependencyCreationEnabled(bool value) {
    _dependencyCreationEnabled = value;
    notifyListeners();
  }

  void setShowDependencies(bool value) {
    if (_showDependencies == value) return;
    _showDependencies = value;
    notifyListeners();
  }

  void setShowConflicts(bool value) {
    _showConflicts = value;
    _recalculateStackingAndNotify();
  }

  Future<void> setShowEmptyParentRows(bool value) async {
    if (_showEmptyParentRows == value) return;
    _showEmptyParentRows = value;
    if (_useLocalDatabase) {
      await _processLocalData();
    } else {
      await _reprocessDataFromApiResponse();
    }
  }

  void setResizeHandleWidth(double value) {
    if (_resizeHandleWidth == value) return;
    _resizeHandleWidth = value;
    notifyListeners();
  }

  void setPersonCount(int value) {
    if (_personCount == value) return;
    _personCount = value;
    fetchScheduleData();
    notifyListeners();
  }

  void setJobCount(int value) {
    if (_jobCount == value) return;
    _jobCount = value;
    fetchScheduleData();
    notifyListeners();
  }

  void setLoadingIndicatorType(GanttLoadingIndicatorType value) {
    if (_loadingIndicatorType == value) return;
    _loadingIndicatorType = value;
    notifyListeners();
  }

  void setLoadingIndicatorPosition(GanttLoadingIndicatorPosition value) {
    if (_loadingIndicatorPosition == value) return;
    _loadingIndicatorPosition = value;
    notifyListeners();
  }

  void setSelectedLocale(String value) {
    if (_selectedLocale == value) return;
    _selectedLocale = value;
    notifyListeners();
  }

  void setSelectedAxisFormat(TimelineAxisFormat value) {
    if (_selectedAxisFormat == value) return;
    _selectedAxisFormat = value;
    notifyListeners();
  }

  void updateResizeTooltipDateFormat(String Function(DateTime)? newFormat) {
    if (_resizeTooltipDateFormat != newFormat) {
      _resizeTooltipDateFormat = newFormat;
      notifyListeners();
    }
  }

  /// Sets the currently focused task and notifies listeners.
  /// This is called by the Gantt chart widget when focus changes.
  void setFocusedTaskId(String? taskId) {
    if (_focusedTaskId == taskId) return;
    _focusedTaskId = taskId;
    notifyListeners();
  }

  /// Fetches new schedule data from the `GanttScheduleService` and processes it
  /// into the data structures required by the UI (`_ganttTasks`, `_gridData`, etc.).
  /// This method is called on initial load and whenever data generation parameters change.
  Future<void> fetchScheduleData() async {
    _ganttTasks = [];
    _isLoading = true;
    _conflictIndicators = [];
    _dependencies = [];
    _gridData = [];
    _rowMaxStackDepth = {};
    _totalStartDate = null;
    _totalEndDate = null;
    _visibleStartDate = null;
    _visibleEndDate = null;
    _cachedFlatGridData = null;
    notifyListeners();

    try {
      final processedData = await _scheduleService.fetchAndProcessSchedule(
        startDate: _startDate,
        range: _range,
        personCount: _personCount,
        jobCount: _jobCount,
      );

      final newDependencies = <LegacyGanttTaskDependency>[];
      final ganttTasks = processedData.ganttTasks;
      final successorForContainedDemo = ganttTasks.firstWhere(
        (t) => !t.isSummary && !t.isTimeRangeHighlight,
        orElse: () => ganttTasks.first, // Fallback
      );
      for (final task in ganttTasks) {
        if (task.isSummary) {
          newDependencies.add(
            LegacyGanttTaskDependency(
              predecessorTaskId: task.id,
              successorTaskId: successorForContainedDemo.id, // The successor is arbitrary for the background to draw
              type: DependencyType.contained,
            ),
          );
        }
      }

      final validTasksForDependency = ganttTasks
          .where((task) => !task.isSummary && !task.isTimeRangeHighlight && !task.isOverlapIndicator)
          .toList();

      if (validTasksForDependency.length > 1) {
        validTasksForDependency.sort((a, b) {
          final startCompare = a.start.compareTo(b.start);
          if (startCompare != 0) return startCompare;
          return a.id.compareTo(b.id);
        });

        newDependencies.add(
          LegacyGanttTaskDependency(
            predecessorTaskId: validTasksForDependency[0].id,
            successorTaskId: validTasksForDependency[1].id,
          ),
        );
      }

      _ganttTasks = processedData.ganttTasks;
      _allGanttTasks = processedData.ganttTasks;
      _conflictIndicators = processedData.conflictIndicators;
      _dependencies = newDependencies;
      _gridData = processedData.gridData;
      _rowMaxStackDepth = processedData.rowMaxStackDepth;
      _eventMap = processedData.eventMap;
      _apiResponse = processedData.apiResponse;

      if (_gridData.isNotEmpty && _gridData.first.children.isNotEmpty) {
        final firstChildRowId = _gridData.first.children.first.id;
        final milestoneDate = _startDate.add(const Duration(days: 5));
        final milestone = LegacyGanttTask(
          id: 'milestone_demo_1',
          rowId: firstChildRowId,
          name: 'Project Kick-off',
          start: milestoneDate,
          end: milestoneDate,
          isMilestone: true,
          color: Colors.deepPurple,
        );
        _ganttTasks.add(milestone);
      }
      if (_ganttTasks.isNotEmpty) {
        DateTime minStart = _ganttTasks.first.start;
        DateTime maxEnd = _ganttTasks.first.end;
        for (final task in _ganttTasks) {
          if (task.start.isBefore(minStart)) {
            minStart = task.start;
          }
          if (task.end.isAfter(maxEnd)) {
            maxEnd = task.end;
          }
        }
        _totalStartDate = minStart;
        _totalEndDate = maxEnd;
      } else {
        _totalStartDate = _startDate;
        _totalEndDate = _startDate.add(Duration(days: _range));
      }

      _isLoading = false;
      _visibleStartDate = _visibleStartDate ?? effectiveTotalStartDate;
      _visibleEndDate = _visibleEndDate ?? effectiveTotalEndDate;
      if (_visibleStartDate == null || _visibleEndDate == null) _setInitialVisibleWindow();

      notifyListeners();

      WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialScroll());
      _syncToController();
    } catch (e) {
      debugPrint('Error fetching schedule data: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets a default visible window when no other range is available.
  void _setInitialVisibleWindow() {
    final now = DateTime.now();
    _totalStartDate = now.subtract(const Duration(days: 15));
    _totalEndDate = now.add(const Duration(days: 15));
    _visibleStartDate = effectiveTotalStartDate;
    _visibleEndDate = effectiveTotalEndDate;
  }

  Color _parseColorHex(String? hexString, Color defaultColor) {
    if (hexString == null || hexString.isEmpty) {
      return defaultColor;
    }
    String cleanHex = hexString.startsWith('#') ? hexString.substring(1) : hexString;
    if (cleanHex.length == 3) {
      cleanHex = cleanHex.split('').map((char) => char * 2).join();
    }
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

  void onRangeChange(int? newRange) {
    if (newRange != null) {
      _range = newRange;
      notifyListeners();
      fetchScheduleData();
    }
  }

  Future<void> onSelectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (pickedDate != null && pickedDate != _startDate) {
      _startDate = pickedDate;
      notifyListeners();
      fetchScheduleData();
    }
  }

  /// Callback from the `LegacyGanttTimelineScrubber`. This is triggered when the user
  /// drags the window on the scrubber.
  ///
  /// It updates the `_visibleStartDate` and `_visibleEndDate`, which causes the
  /// main Gantt chart to rebuild. It then programmatically scrolls the chart to the new position.
  void onScrubberWindowChanged(DateTime newStart, DateTime newEnd, [scrubber.ScrubberHandle? handle]) {
    _isScrubberUpdating = true;

    if (handle == scrubber.ScrubberHandle.left) {
      _visibleStartDate = newStart;
    } else if (handle == scrubber.ScrubberHandle.right) {
      _visibleEndDate = newEnd;
    } else {
      _visibleStartDate = newStart;
      _visibleEndDate = newEnd;
    }

    _broadcastPresence();
    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (effectiveTotalStartDate != null &&
          _ganttHorizontalScrollController.hasClients &&
          effectiveTotalEndDate != null &&
          _ganttHorizontalScrollController.hasClients) {
        final totalDataDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
        if (totalDataDuration <= 0) return;

        final position = _ganttHorizontalScrollController.position;
        final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
        if (totalGanttWidth > 0) {
          final DateTime anchorDate;
          if (handle == scrubber.ScrubberHandle.right) {
            anchorDate = _visibleStartDate!;
          } else {
            anchorDate = newStart;
          }

          final startOffsetMs = anchorDate.difference(effectiveTotalStartDate!).inMilliseconds;
          final newScrollOffset = (startOffsetMs / totalDataDuration) * totalGanttWidth;

          _ganttHorizontalScrollController.jumpTo(newScrollOffset.clamp(0.0, position.maxScrollExtent));
        }
      }
      _isScrubberUpdating = false;
    });
  }

  double? _lastTotalGanttWidth;

  /// Listener for the `_ganttHorizontalScrollController`. This is triggered when the
  /// user scrolls the main Gantt chart horizontally.
  ///
  /// It calculates the new visible date window based on the scroll offset and updates
  /// the state, which in turn updates the position of the window on the timeline scrubber.
  void _onGanttScroll() {
    if (_isScrubberUpdating || effectiveTotalStartDate == null || effectiveTotalEndDate == null) return;

    final position = _ganttHorizontalScrollController.position;
    final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
    if (totalGanttWidth <= 0) return;

    final totalDataDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    if (totalDataDuration <= 0) return;

    final startOffsetMs = (position.pixels / totalGanttWidth) * totalDataDuration;
    final newVisibleStart = effectiveTotalStartDate!.add(Duration(milliseconds: startOffsetMs.round()));
    final newVisibleEnd = newVisibleStart.add(_visibleEndDate!.difference(_visibleStartDate!));

    if (newVisibleStart != _visibleStartDate || newVisibleEnd != _visibleEndDate) {
      _visibleStartDate = newVisibleStart;
      _visibleEndDate = newVisibleEnd;
      _broadcastPresence();
      notifyListeners();
    }
  }

  /// Called by the view when the layout width of the gantt chart changes (e.g. window resize).
  /// This ensures we adjust the scroll offset to keep the current date in view, preventing drift.
  void maintainScrollOffsetForWidth(double totalWidth) {
    if (_lastTotalGanttWidth != null && (totalWidth - _lastTotalGanttWidth!).abs() > 1.0) {
      _lastTotalGanttWidth = totalWidth;

      if (effectiveTotalStartDate == null || effectiveTotalEndDate == null) return;

      final totalDataDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
      if (totalDataDuration <= 0) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_ganttHorizontalScrollController.hasClients) return;
        if (effectiveTotalStartDate == null) return;

        final startOffsetMs = _visibleStartDate!.difference(effectiveTotalStartDate!).inMilliseconds;
        final newScrollOffset = (startOffsetMs / totalDataDuration) * totalWidth;

        _ganttHorizontalScrollController
            .jumpTo(newScrollOffset.clamp(0.0, _ganttHorizontalScrollController.position.maxScrollExtent));
      });
    }
    _lastTotalGanttWidth = totalWidth;
  }

  /// Sets the initial horizontal scroll position of the Gantt chart after data
  /// has been loaded and the layout has been built for the first time.
  void _setInitialScroll() {
    if (!_ganttHorizontalScrollController.hasClients ||
        effectiveTotalStartDate == null ||
        effectiveTotalEndDate == null ||
        _visibleStartDate == null) {
      return;
    }

    final totalDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    if (totalDuration <= 0) return;

    final position = _ganttHorizontalScrollController.position;
    final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
    if (totalGanttWidth <= 0) return;

    final startOffsetMs = _visibleStartDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    final newScrollOffset = (startOffsetMs / totalDuration) * totalGanttWidth;
    _ganttHorizontalScrollController.jumpTo(newScrollOffset.clamp(0.0, position.maxScrollExtent));
  }

  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  /// Displays a custom tooltip when the user hovers over a task.
  /// It uses an `OverlayEntry` to position the tooltip near the cursor.
  void showTooltip(BuildContext context, LegacyGanttTask task, Offset globalPosition) {
    _removeTooltip(); // Remove previous tooltip first

    final overlay = Overlay.of(context);

    int? dayNumber;

    if (!task.isSummary && task.originalId != null) {
      final childEvent = _eventMap[task.originalId];
      if (childEvent?.resourceId != null) {
        final parentEvent = _eventMap[childEvent!.resourceId];
        if (parentEvent?.utcStartDate != null) {
          final parentStartDate = DateTime.tryParse(parentEvent!.utcStartDate!);
          if (parentStartDate != null) {
            dayNumber = task.start.toUtc().difference(parentStartDate.toUtc()).inDays + 1;
          }
        }
      }
    }

    _tooltipOverlay = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final event = _eventMap[task.originalId];
        final statusText = event?.referenceData?.taskName;
        final taskColorHex = event?.referenceData?.taskColor;
        final taskColor = taskColorHex != null ? _parseColorHex('#$taskColorHex', Colors.transparent) : null;
        final textStyle = theme.textTheme.bodySmall;
        final boldTextStyle = textStyle?.copyWith(fontWeight: FontWeight.bold);

        return Positioned(
          left: globalPosition.dx + 15, // Offset from cursor
          top: globalPosition.dy + 15,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(4),
            color: Colors.transparent, // Make Material transparent to show Container's decor
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480), // Style: max-width
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Important for Column in Overlay
                children: [
                  if (dayNumber != null) Text('Day $dayNumber', style: boldTextStyle),
                  Text(task.name ?? '', style: boldTextStyle),
                  if (statusText != null && taskColor != null && taskColor != Colors.transparent)
                    Container(
                      margin: const EdgeInsets.only(top: 2, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: taskColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: textStyle?.copyWith(
                          color: ThemeData.estimateBrightnessForColor(taskColor) == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text('Start: ${_getTooltipDateFormat()(task.start.toLocal())}', style: textStyle),
                  Text('End: ${_getTooltipDateFormat()(task.end.toLocal())}', style: textStyle),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_tooltipOverlay!);
    _hoveredTaskId = task.id;
    notifyListeners();
  }

  /// A callback from the Gantt chart widget when the user's cursor moves over a task.
  void onTaskHover(LegacyGanttTask? task, BuildContext context, Offset globalPosition) {
    if (_hoveredTaskId == task?.id) return;
    _hoveredTaskId = task?.id;
    _removeTooltip();
    if (task != null && !task.isTimeRangeHighlight) {
      showTooltip(context, task, globalPosition);
    }
    notifyListeners();
  }

  /// A helper method to update the task list and stack depth map, then notify listeners.
  void _updateTasksAndStacking(
      List<LegacyGanttTask> tasks, Map<String, int> maxDepth, List<LegacyGanttTask> conflictIndicators) {
    _ganttTasks = tasks;
    _conflictIndicators = conflictIndicators;
    _rowMaxStackDepth = maxDepth;
    _syncToController();
    notifyListeners();
  }

  void _syncToController() {
    controller.setTasks(_ganttTasks);
    controller.setDependencies(_dependencies);
    controller.setConflictIndicators(_conflictIndicators);
  }

  final Map<String, RemoteGhost> _connectedUsers = {};
  Map<String, RemoteGhost> get connectedUsers => Map.unmodifiable(_connectedUsers);

  String? _followedUserId;
  String? get followedUserId => _followedUserId;

  Timer? _presenceThrottle;

  void setFollowedUser(String? userId) {
    _followedUserId = userId;
    notifyListeners();
    if (userId != null && _connectedUsers.containsKey(userId)) {
      _applyFollowedUserView(_connectedUsers[userId]!);
    }
  }

  void setVisibleRange(DateTime start, DateTime end) {
    _visibleStartDate = start;
    _visibleEndDate = end;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (effectiveTotalStartDate != null &&
          _ganttHorizontalScrollController.hasClients &&
          effectiveTotalEndDate != null) {
        final totalDataDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
        if (totalDataDuration <= 0) return;

        final position = _ganttHorizontalScrollController.position;
        final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
        if (totalGanttWidth > 0) {
          final startOffsetMs = start.difference(effectiveTotalStartDate!).inMilliseconds;
          final newScrollOffset = (startOffsetMs / totalDataDuration) * totalGanttWidth;
          _ganttHorizontalScrollController.jumpTo(newScrollOffset.clamp(0.0, position.maxScrollExtent));
        }
      }
    });
  }

  void _broadcastPresence() {
    if (_syncClient == null) return;
    if (_presenceThrottle?.isActive ?? false) return;

    _presenceThrottle = Timer(const Duration(milliseconds: 100), () {
      if (visibleStartDate != null && visibleEndDate != null) {
        print('Broadcasting Presence: User ${_syncClient?.hashCode}');

        if (_currentUsername != null) {
          const localId = 'me';
          _connectedUsers[localId] = RemoteGhost(
            userId: localId,
            lastUpdated: DateTime.now(),
            viewportStart: visibleStartDate,
            viewportEnd: visibleEndDate,
            userName: _currentUsername,
            userColor: '#00FF00', // Green for self
          );
          notifyListeners();
        }

        double verticalScroll = 0.0;
        if (_gridScrollController.hasClients) {
          verticalScroll = _gridScrollController.offset;
        } else if (_ganttScrollController.hasClients) {
          verticalScroll = _ganttScrollController.offset;
        }

        try {
          _syncClient?.sendOperation(Operation(
            type: 'PRESENCE_UPDATE',
            data: {
              'viewportStart': visibleStartDate!.millisecondsSinceEpoch,
              'viewportEnd': visibleEndDate!.millisecondsSinceEpoch,
              'verticalScrollOffset': verticalScroll,
              'userName': _currentUsername ?? 'User ${_syncClient?.hashCode ?? "Me"}',
              'userColor': '#FF0000',
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            actorId: 'me',
          ));
        } catch (e) {
          print('Warning: Failed to broadcast presence: $e');
        }
      }
    });
  }

  void _applyFollowedUserView(RemoteGhost ghost) {
    if (ghost.viewportStart != null && ghost.viewportEnd != null) {
      setVisibleRange(ghost.viewportStart!, ghost.viewportEnd!);
    }
    if (ghost.verticalScrollOffset != null) {
      ScrollController? targetController;
      if (_gridScrollController.hasClients) {
        targetController = _gridScrollController;
      } else if (_ganttScrollController.hasClients) {
        targetController = _ganttScrollController;
      }

      if (targetController != null) {
        final maxScroll = targetController.position.maxScrollExtent;
        final targetScroll = ghost.verticalScrollOffset!.clamp(0.0, maxScroll);

        if ((targetController.offset - targetScroll).abs() > 1.0) {
          targetController.jumpTo(targetScroll);
        }
      }
    }
  }

  String? _currentUsername;

  GanttSyncClient? _syncClient;
  StreamSubscription<Operation>? _syncOperationsSubscription;
  StreamSubscription<bool>? _connectionStateSubscription;

  /// Factory for creating the sync client. Can be overridden for testing.
  GanttSyncClient Function({required Uri uri, required String authToken})? syncClientFactory;

  GanttSyncClient? get syncClient => _syncClient;
  bool _isSyncConnected = false;
  bool get isSyncConnected => _isSyncConnected;

  Stream<int> get outboundPendingCount {
    if (_syncClient != null) {
      return _syncClient!.outboundPendingCount;
    }
    return Stream.value(0);
  }

  Stream<SyncProgress> get inboundProgress {
    if (_syncClient != null) {
      return _syncClient!.inboundProgress;
    }
    return Stream.value(const SyncProgress(processed: 0, total: 0));
  }

  /// Function for logging in. Can be overridden for testing.
  Future<String> Function({required Uri uri, required String username, required String password})? loginFunction;

  Future<void> connectSync({
    required String uri,
    required String tenantId,
    required String username,
    required String password,
  }) async {
    try {
      _currentUsername = username;
      final parsedUri = Uri.parse(uri);
      final loginCall = loginFunction ?? WebSocketGanttSyncClient.login;
      final token = await loginCall(
        uri: parsedUri,
        username: username,
        password: password,
      );

      final wsUri = parsedUri.replace(scheme: parsedUri.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
      WebSocketGanttSyncClient? wsClientToConnect;

      if (syncClientFactory != null) {
        _syncClient = syncClientFactory!(uri: wsUri, authToken: token);
        if (_syncClient is WebSocketGanttSyncClient) {
          wsClientToConnect = _syncClient as WebSocketGanttSyncClient;
        }
      } else {
        final wsClient = WebSocketGanttSyncClient(
          uri: wsUri,
          authToken: token,
        );
        wsClientToConnect = wsClient;

        if (_syncClient is OfflineGanttSyncClient) {
          await (_syncClient as OfflineGanttSyncClient).setInnerClient(wsClient);
        } else {
          if (_syncClient is WebSocketGanttSyncClient) {
            await (_syncClient as WebSocketGanttSyncClient).dispose();
          }
          final offlineClient = OfflineGanttSyncClient(GanttDb.db);
          await offlineClient.setInnerClient(wsClient);
          _syncClient = offlineClient;
        }
      }

      _connectionStateSubscription?.cancel();
      Stream<bool>? connectionStream;
      if (_syncClient is OfflineGanttSyncClient) {
        connectionStream = (_syncClient as OfflineGanttSyncClient).connectionStateStream;
      } else if (_syncClient is WebSocketGanttSyncClient) {
        connectionStream = (_syncClient as WebSocketGanttSyncClient).connectionStateStream;
      }

      if (connectionStream != null) {
        _connectionStateSubscription = connectionStream.listen((isConnected) {
          if (_isSyncConnected != isConnected) {
            _isSyncConnected = isConnected;
            notifyListeners();
          }
        });
      }

      Future<void> opChain = Future.value();
      _syncOperationsSubscription = _syncClient!.operationStream.listen((op) {
        opChain = opChain.then((_) => _handleIncomingOperation(op)).catchError((e) {
          print('Error processing operation in chain: $e');
        });
      });

      _isSyncConnected = true;
      _broadcastPresence();
      notifyListeners();

      if (wsClientToConnect != null) {
        int? lastSynced;
        if (_useLocalDatabase) {
          lastSynced = await _localRepository.getLastServerSyncTimestamp();
        }
        wsClientToConnect.connect(tenantId, lastSyncedTimestamp: lastSynced);
      }
    } catch (e) {
      print('Sync connection error: $e');
      rethrow;
    }
  }

  Future<void> disconnectSync() async {
    _syncOperationsSubscription?.cancel();
    _connectionStateSubscription?.cancel();

    if (_syncClient is OfflineGanttSyncClient) {
      await (_syncClient as OfflineGanttSyncClient).removeInnerClient();
      if (!_useLocalDatabase) {
        await (_syncClient as OfflineGanttSyncClient).dispose();
        _syncClient = null;
      }
    } else if (_syncClient is WebSocketGanttSyncClient) {
      await (_syncClient as WebSocketGanttSyncClient).dispose();
      _syncClient = null;
    }

    _isSyncConnected = false;
    notifyListeners();
  }

  Future<void> handleIncomingOperationForTesting(Operation op) => _handleIncomingOperation(op);

  Future<void> _handleIncomingOperation(Operation op) async {
    print('SyncClient: Received operation ${op.type} with timestamp ${op.timestamp}');

    if (_useLocalDatabase) {
      await _localRepository.setLastServerSyncTimestamp(op.timestamp);
    }

    if (op.type == 'BATCH_UPDATE') {
      final operations = op.data['operations'] as List? ?? [];
      final batchTasks = <LegacyGanttTask>[];
      final batchDependencies = <LegacyGanttTaskDependency>[];
      final batchResources = <LocalResource>[];

      for (final opEnv in operations) {
        try {
          final opMap = opEnv as Map<String, dynamic>;
          final opType = opMap['type'] as String;
          var opData = opMap['data'] as Map<String, dynamic>;
          final opTs = opMap['timestamp'] as int;
          final opActor = opMap['actorId'] as String;

          if (opData.containsKey('data') && opData['data'] is Map) {
            final innerData = opData['data'] as Map<String, dynamic>;
            if (opData.containsKey('gantt_type')) {
              innerData['gantt_type'] = opData['gantt_type'];
            }
            opData = innerData;
          }

          final subOp = Operation(
            type: opType,
            data: opData,
            timestamp: opTs,
            actorId: opActor,
          );

          await _processOperationInternal(
            subOp,
            notify: false,
            batchTasks: batchTasks,
            batchDependencies: batchDependencies,
            batchResources: batchResources,
          );
        } catch (e) {
          print('Error processing batch item: $e');
        }
      }

      if (_useLocalDatabase) {
        if (batchTasks.isNotEmpty) {
          await _localRepository.insertTasks(batchTasks);
        }
        if (batchDependencies.isNotEmpty) {
          await _localRepository.insertDependencies(batchDependencies);
        }
        if (batchResources.isNotEmpty) {
          await _localRepository.insertResources(batchResources);
        }
      }

      try {
        await _processLocalData();
      } catch (e) {
        print('Error in _processLocalData during batch update: $e');
      } finally {
        notifyListeners();
      }
    } else {
      await _processOperationInternal(op, notify: true);
    }
  }

  Future<void> _processOperationInternal(
    Operation op, {
    bool notify = true,
    List<LegacyGanttTask>? batchTasks,
    List<LegacyGanttTaskDependency>? batchDependencies,
    List<LocalResource>? batchResources,
  }) async {
    // Removed actorId check as it is unreliable when server overwrites it

    final data = op.data;
    final taskData = data;

    if (op.type == 'UPDATE_TASK') {
      var innerData = taskData;
      String? ganttType;

      ganttType = innerData['gantt_type'] as String?;

      if (innerData.containsKey('data') && innerData['data'] is Map) {
        ganttType ??= (innerData['gantt_type'] ?? innerData['ganttType']) as String?;
        innerData = innerData['data'] as Map<String, dynamic>;
        ganttType ??= (innerData['gantt_type'] ?? innerData['ganttType']) as String?;
      }

      final taskIdRaw = innerData['id'];
      if (taskIdRaw == null) {
        return;
      }
      final taskId = taskIdRaw.toString().trim();

      final sourceIndex = _allGanttTasks.indexWhere((t) => t.id == taskId);

      if (sourceIndex != -1) {
        final existingTask = _allGanttTasks[sourceIndex];

        if (existingTask.lastUpdated != null && op.timestamp <= existingTask.lastUpdated!) {
          return;
        }

        DateTime? parseDate(dynamic value) {
          if (value == null) return null;
          if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
          if (value is String) return DateTime.tryParse(value);
          return null;
        }

        final newStart =
            parseDate(innerData['start_date']) ?? parseDate(innerData['start']) ?? parseDate(innerData['startDate']);
        final newEnd =
            parseDate(innerData['end_date']) ?? parseDate(innerData['end']) ?? parseDate(innerData['endDate']);

        final updatedTask = existingTask.copyWith(
          name: innerData['name'] ?? existingTask.name,
          start: newStart ?? existingTask.start,
          end: newEnd ?? existingTask.end,
          lastUpdated: op.timestamp,
          isMilestone: ganttType != null ? ganttType == 'milestone' : existingTask.isMilestone,
          isSummary: ganttType != null
              ? (ganttType == 'summary')
              : (innerData['is_summary'] == true || innerData['isSummary'] == true ? true : existingTask.isSummary),
          color: _parseColor(innerData['color']) ?? existingTask.color,
          textColor:
              _parseColor(innerData['text_color']) ?? _parseColor(innerData['textColor']) ?? existingTask.textColor,
          completion: (innerData['completion'] as num?)?.toDouble() ?? existingTask.completion,
          resourceId: innerData['resourceId'] as String? ?? existingTask.resourceId,
          baselineStart: parseDate(innerData['baseline_start']) ?? existingTask.baselineStart,
          baselineEnd: parseDate(innerData['baseline_end']) ?? existingTask.baselineEnd,
          notes: innerData['notes'] as String? ?? existingTask.notes,
          parentId: innerData['parentId'] as String? ?? innerData['parent_id'] as String? ?? existingTask.parentId,
          usesWorkCalendar: innerData['uses_work_calendar'] == true || innerData['usesWorkCalendar'] == true
              ? true
              : (innerData['uses_work_calendar'] == false ? false : existingTask.usesWorkCalendar),
          isAutoScheduled: innerData['is_auto_scheduled'] == true
              ? true
              : (innerData['is_auto_scheduled'] == false ? false : existingTask.isAutoScheduled),
        );

        try {
          if (_useLocalDatabase) {
            if (batchTasks != null) {
              batchTasks.add(updatedTask);
            } else {
              await _localRepository.insertOrUpdateTask(updatedTask);
            }
          }

          _allGanttTasks = List.from(_allGanttTasks);
          _allGanttTasks[sourceIndex] = updatedTask;

          final visibleIndex = _ganttTasks.indexWhere((t) => t.id == taskId);
          if (visibleIndex != -1) {
            _ganttTasks[visibleIndex] = updatedTask;
          }
          if (notify) await _processLocalData();
        } catch (e) {
          print('Error processing UPDATE_TASK for $taskId: $e');
        }
      } else {
        final newTask = LegacyGanttTask(
          id: taskId,
          rowId: innerData['rowId'] ?? 'unknown_row',
          name: innerData['name'] ?? 'Unnamed Task',
          start: (innerData['start_date'] ?? innerData['startDate']) != null
              ? DateTime.fromMillisecondsSinceEpoch((innerData['start_date'] ?? innerData['startDate']) as int)
              : DateTime.now(),
          end: (innerData['end_date'] ?? innerData['endDate']) != null
              ? DateTime.fromMillisecondsSinceEpoch((innerData['end_date'] ?? innerData['endDate']) as int)
              : DateTime.now().add(const Duration(days: 1)),
          isSummary: (ganttType == 'summary') || (innerData['is_summary'] == true) || (innerData['isSummary'] == true),
          isMilestone: ganttType == 'milestone',
          color: _parseColor(innerData['color']),
          textColor: _parseColor(innerData['text_color']) ?? _parseColor(innerData['textColor']),
          completion: (innerData['completion'] as num?)?.toDouble() ?? 0.0,
          resourceId: innerData['resourceId'] as String?,
          baselineStart: innerData['baseline_start'] != null
              ? DateTime.fromMillisecondsSinceEpoch(innerData['baseline_start'] as int)
              : null,
          baselineEnd: innerData['baseline_end'] != null
              ? DateTime.fromMillisecondsSinceEpoch(innerData['baseline_end'] as int)
              : null,
          notes: innerData['notes'] as String?,
          parentId: innerData['parentId'] as String? ?? innerData['parent_id'] as String?,
          usesWorkCalendar: innerData['uses_work_calendar'] == true || innerData['usesWorkCalendar'] == true,
          isAutoScheduled: innerData['is_auto_scheduled'] != false,
        );

        if (_useLocalDatabase) {
          if (batchTasks != null) {
            batchTasks.add(newTask);
          } else {
            await _localRepository.insertOrUpdateTask(newTask);
          }
        }

        _allGanttTasks = List.from(_allGanttTasks)..add(newTask);
        if (notify) await _processLocalData();
      }
    } else if (op.type == 'INSERT_TASK') {
      var data = op.data;
      String? ganttType;

      ganttType = (data['gantt_type'] ?? data['ganttType']) as String?;

      if (data.containsKey('data') && data['data'] is Map) {
        ganttType ??= (data['gantt_type'] ?? data['ganttType']) as String?;
        data = data['data'] as Map<String, dynamic>;
        ganttType ??= (data['gantt_type'] ?? data['ganttType']) as String?;
      }

      final taskId = data['id']?.toString().trim() ?? '';
      final existingIndex = _allGanttTasks.indexWhere((t) => t.id == taskId);
      if (existingIndex != -1) {
        final existing = _allGanttTasks[existingIndex];
        if (existing.lastUpdated != null && op.timestamp <= existing.lastUpdated!) {
          return;
        }
      }

      final newTask = LegacyGanttTask(
        id: taskId,
        rowId: data['rowId']?.toString().trim() ?? '',
        name: data['name'],
        start: DateTime.fromMillisecondsSinceEpoch(data['start_date']),
        end: DateTime.fromMillisecondsSinceEpoch(data['end_date']),
        isSummary: ganttType == 'summary' || data['is_summary'] == true,
        isMilestone: ganttType == 'milestone',
        color: _parseColor(data['color']),
        textColor: _parseColor(data['textColor']),
        completion: (data['completion'] as num?)?.toDouble() ?? 0.0,
        resourceId: data['resourceId'] as String?,
        baselineStart:
            data['baseline_start'] != null ? DateTime.fromMillisecondsSinceEpoch(data['baseline_start'] as int) : null,
        baselineEnd:
            data['baseline_end'] != null ? DateTime.fromMillisecondsSinceEpoch(data['baseline_end'] as int) : null,
        notes: data['notes'] as String?,
        parentId: data['parentId'] as String?,
        usesWorkCalendar: data['uses_work_calendar'] == true,
        isAutoScheduled: data['is_auto_scheduled'] != false,
      );

      if (_useLocalDatabase) {
        if (batchTasks != null) {
          batchTasks.add(newTask);
        } else {
          await _localRepository.insertOrUpdateTask(newTask);
        }
      }

      if (existingIndex != -1) {
        _allGanttTasks = List.from(_allGanttTasks);
        _allGanttTasks[existingIndex] = newTask;
      } else {
        _allGanttTasks = List.from(_allGanttTasks)..add(newTask);
      }
      if (notify) await _processLocalData();
    } else if (op.type == 'DELETE_TASK') {
      final taskId = taskData['id'];
      if (taskId == null) return;

      if (_useLocalDatabase) {
        if (batchTasks != null && batchTasks.isNotEmpty) {
          await _localRepository.insertTasks(batchTasks);
          batchTasks.clear();
        }
        await _localRepository.deleteTask(taskId);
      }

      _ganttTasks.removeWhere((t) => t.id == taskId);
      _allGanttTasks.removeWhere((t) => t.id == taskId);
      _dependencies.removeWhere((d) => d.predecessorTaskId == taskId || d.successorTaskId == taskId);
      if (notify) await _processLocalData();
    } else if (op.type == 'PRESENCE_UPDATE') {
      final data = op.data;
      final userId = op.actorId;

      final viewportStartMs = data['viewportStart'] as int?;
      final viewportEndMs = data['viewportEnd'] as int?;

      _connectedUsers[userId] = RemoteGhost(
        userId: userId,
        lastUpdated: DateTime.now(),
        viewportStart: viewportStartMs != null ? DateTime.fromMillisecondsSinceEpoch(viewportStartMs) : null,
        viewportEnd: viewportEndMs != null ? DateTime.fromMillisecondsSinceEpoch(viewportEndMs) : null,
        verticalScrollOffset: (data['verticalScrollOffset'] as num?)?.toDouble(),
        userName: data['userName'] as String?,
        userColor: data['userColor'] as String?,
      );
      if (notify) notifyListeners();

      if (followedUserId == userId) {
        _applyFollowedUserView(_connectedUsers[userId]!);
      }
    } else if (op.type == 'INSERT_DEPENDENCY') {
      final data = op.data;
      final dependencyTypeString = (data['dependency_type'] ?? data['type'] ?? 'finishToStart').toString();
      final dependencyType = DependencyType.values.firstWhere(
        (e) => e.name.toLowerCase() == dependencyTypeString.toLowerCase(),
        orElse: () => DependencyType.finishToStart,
      );
      final newDep = LegacyGanttTaskDependency(
        predecessorTaskId: data['predecessorTaskId'] ?? data['predecessor_task_id'],
        successorTaskId: data['successorTaskId'] ?? data['successor_task_id'],
        type: dependencyType,
      );

      if (_useLocalDatabase) {
        if (batchDependencies != null) {
          batchDependencies.add(newDep);
        } else {
          await _localRepository.insertOrUpdateDependency(newDep);
        }
        if (notify) await _processLocalData();
      } else {
        if (!_dependencies.contains(newDep)) {
          _dependencies.add(newDep);
          if (notify) notifyListeners();
        }
      }
    } else if (op.type == 'DELETE_DEPENDENCY') {
      final data = op.data;
      final pred = data['predecessorTaskId'];
      final succ = data['successorTaskId'];

      if (_useLocalDatabase) {
        if (batchDependencies != null && batchDependencies.isNotEmpty) {
          await _localRepository.insertDependencies(batchDependencies);
          batchDependencies.clear();
        }
        await _localRepository.deleteDependency(pred, succ);
        if (notify) await _processLocalData();
      } else {
        _dependencies.removeWhere((d) => d.predecessorTaskId == pred && d.successorTaskId == succ);
        if (notify) notifyListeners();
      }
    } else if (op.type == 'CLEAR_DEPENDENCIES') {
      final taskId = op.data['taskId'];
      if (taskId == null) return;

      if (_useLocalDatabase) {
        if (batchDependencies != null && batchDependencies.isNotEmpty) {
          await _localRepository.insertDependencies(batchDependencies);
          batchDependencies.clear();
        }
        await _localRepository.deleteDependenciesForTask(taskId);
        if (notify) await _processLocalData();
      } else {
        _dependencies.removeWhere((d) => d.predecessorTaskId == taskId || d.successorTaskId == taskId);
        if (notify) notifyListeners();
      }
    } else if (op.type == 'INSERT_RESOURCE' || op.type == 'UPDATE_RESOURCE') {
      var data = op.data;
      if (data.containsKey('data') && data['data'] is Map) {
        data = data['data'] as Map<String, dynamic>;
      }

      final resource = LocalResource(
        id: data['id'],
        name: data['name'],
        parentId: data['parent_id'] ?? data['parentId'],
        isExpanded: data['isExpanded'] == true || data['is_expanded'] == true,
      );

      if (_useLocalDatabase) {
        if (batchResources != null) {
          batchResources.add(resource);
        } else {
          await _localRepository.insertOrUpdateResource(resource);
        }
      }

      final index = _localResources.indexWhere((r) => r.id == resource.id);
      if (index != -1) {
        _localResources[index] = resource;
      } else {
        _localResources = List.from(_localResources)..add(resource);
      }

      if (notify) await _processLocalData();
    } else if (op.type == 'DELETE_RESOURCE') {
      final id = op.data['id'];
      if (id != null) {
        if (_useLocalDatabase) {
          if (batchResources != null && batchResources.isNotEmpty) {
            await _localRepository.insertResources(batchResources);
            batchResources.clear();
          }
          await _localRepository.deleteResource(id);
        }
        _localResources.removeWhere((r) => r.id == id);
        if (notify) await _processLocalData();
      }
    } else if (op.type == 'RESET_DATA') {
      await _localRepository.deleteAllDependencies();
      await _localRepository.deleteAllTasks();
      await _localRepository.deleteAllResources();

      batchTasks?.clear();
      batchDependencies?.clear();
      batchResources?.clear();

      _dependencies.clear();
      _ganttTasks.clear();
      _allGanttTasks.clear();
      _gridData.clear();
      _cachedFlatGridData = null;
      _conflictIndicators.clear();

      if (notify) notifyListeners();
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

  /// A callback from the Gantt chart widget when a task has been moved or resized by the user.
  /// It updates the task in the local list and then recalculates the stacking for all tasks.
  Future<void> handleTaskUpdate(LegacyGanttTask task, DateTime newStart, DateTime newEnd) async {
    if (_useLocalDatabase) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedTask = task.copyWith(start: newStart, end: newEnd, lastUpdated: now);
      await _localRepository.insertOrUpdateTask(updatedTask);

      final index = _allGanttTasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _allGanttTasks[index] = updatedTask;

        if (_apiResponse != null) {
          final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService
              .publicCalculateTaskStacking(_allGanttTasks, _apiResponse!, showConflicts: _showConflicts);
          _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
        }
      }
    } else if (_apiResponse != null) {
      final parentResource =
          _apiResponse?.resourcesData.firstWhereOrNull((r) => r.children.any((c) => c.id == task.rowId));
      if (parentResource != null) {
        final jobIndex = parentResource.children.indexWhere((j) => j.id == task.rowId);
        if (jobIndex != -1) {
          final assignment = _apiResponse?.assignmentsData.firstWhereOrNull((a) => a.id == task.id);
          if (assignment != null) {
            final eventIndex = _apiResponse!.eventsData.indexWhere((e) => e.id == assignment.event);
            if (eventIndex != -1) {
              final oldEvent = _apiResponse!.eventsData[eventIndex];
              _apiResponse!.eventsData[eventIndex] = GanttEventData(
                id: oldEvent.id,
                name: oldEvent.name,
                utcStartDate: newStart.toIso8601String(),
                utcEndDate: newEnd.toIso8601String(),
                referenceData: oldEvent.referenceData,
                resourceId: oldEvent.resourceId,
              );
            }
          }
        }
      }
    }

    if (!_useLocalDatabase) {
      final index = _allGanttTasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _allGanttTasks[index] = _allGanttTasks[index].copyWith(start: newStart, end: newEnd);

        if (_apiResponse != null) {
          final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService
              .publicCalculateTaskStacking(_allGanttTasks, _apiResponse!, showConflicts: _showConflicts);
          _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
        }
      }
    }
  }

  Future<void> handleBatchTaskUpdate(List<(LegacyGanttTask, DateTime, DateTime)> updates) async {
    debugPrint(
        '${DateTime.now().toIso8601String()} GanttViewModel: handleBatchTaskUpdate received ${updates.length} updates');
    final now = DateTime.now().millisecondsSinceEpoch;
    bool needsCalculations = false;
    final List<LegacyGanttTask> dbUpdates = [];

    for (final update in updates) {
      final task = update.$1;
      final newStart = update.$2;
      final newEnd = update.$3;

      if (_useLocalDatabase) {
        final updatedTask = task.copyWith(start: newStart, end: newEnd, lastUpdated: now);

        final index = _allGanttTasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _allGanttTasks[index] = updatedTask;
          needsCalculations = true;
        }

        dbUpdates.add(updatedTask);
      } else if (_apiResponse != null) {
        final parentResource =
            _apiResponse?.resourcesData.firstWhereOrNull((r) => r.children.any((c) => c.id == task.rowId));
        if (parentResource != null) {
          final jobIndex = parentResource.children.indexWhere((j) => j.id == task.rowId);
          if (jobIndex != -1) {
            final assignment = _apiResponse?.assignmentsData.firstWhereOrNull((a) => a.id == task.id);
            if (assignment != null) {
              final eventIndex = _apiResponse!.eventsData.indexWhere((e) => e.id == assignment.event);
              if (eventIndex != -1) {
                final oldEvent = _apiResponse!.eventsData[eventIndex];
                _apiResponse!.eventsData[eventIndex] = GanttEventData(
                  id: oldEvent.id,
                  name: oldEvent.name,
                  utcStartDate: newStart.toIso8601String(),
                  utcEndDate: newEnd.toIso8601String(),
                  referenceData: oldEvent.referenceData,
                  resourceId: oldEvent.resourceId,
                );
              }
            }
          }
        }

        final index = _allGanttTasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _allGanttTasks[index] = _allGanttTasks[index].copyWith(start: newStart, end: newEnd);
          needsCalculations = true;
        }
      }
    }

    if (needsCalculations && _apiResponse != null) {
      final (recalculatedTasks, newMaxDepth, newConflictIndicators) =
          _scheduleService.publicCalculateTaskStacking(_allGanttTasks, _apiResponse!, showConflicts: _showConflicts);
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
    }

    if (_useLocalDatabase && dbUpdates.isNotEmpty) {
      await _localRepository.insertTasks(dbUpdates);
    }
  }

  /// A callback from the Gantt chart widget when the user clicks on an empty
  /// space in a row. This method shows a dialog to create a new task.

  Future<void> handleEmptySpaceClick(BuildContext context, String rowId, DateTime time) async {
    if (!_createTasksEnabled) return;

    String resourceName = 'Unknown';
    final resource = _localResources.firstWhereOrNull((r) => r.id == rowId);
    if (resource != null) {
      resourceName = resource.name ?? 'Unknown';
    } else {
      final flatNode = _cachedFlatGridData?.firstWhereOrNull((n) => n['id'] == rowId);
      if (flatNode != null) {
        resourceName = flatNode['name'] ?? 'Unknown';
      } else {}
    }

    await showDialog(
      context: context,
      builder: (context) => TaskDialog(
        initialTime: time,
        resourceName: resourceName,
        rowId: rowId,
        defaultStartTime: _defaultStartTime,
        defaultEndTime: _defaultEndTime,
        onSubmit: (newTask) {
          _createTask(newTask.copyWith(usesWorkCalendar: _enableWorkCalendar));
        },
      ),
    );
  }

  /// A callback from the Gantt chart widget when the user draws a new task.
  Future<void> handleTaskDrawEnd(DateTime start, DateTime end, String rowId) async {
    if (!_createTasksEnabled) return;

    final newTask = LegacyGanttTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      rowId: rowId,
      name: 'New Task',
      start: start,
      end: end,
      color: Colors.blue, // Default color
      isSummary: false,
      usesWorkCalendar: _enableWorkCalendar,
    );

    await _createTask(newTask);
  }

  /// Helper method to add a new task, handle persistence, and update UI.
  Future<void> _createTask(LegacyGanttTask newTask) async {
    _allGanttTasks.add(newTask);
    _recalculateStackingAndNotify();

    if (_useLocalDatabase) {
      await _localRepository.insertOrUpdateTask(newTask);
    }

    if (_syncClient != null && (_isSyncConnected || _syncClient is OfflineGanttSyncClient)) {
      _syncClient!.sendOperation(Operation(
        type: 'INSERT_TASK', // Use INSERT_TASK for clarity
        data: {
          'id': newTask.id,
          'color': newTask.color?.toARGB32().toRadixString(16),
          'text_color': newTask.textColor?.toARGB32().toRadixString(16),
          'name': newTask.name,
          'start_date': newTask.start.millisecondsSinceEpoch,
          'end_date': newTask.end.millisecondsSinceEpoch,
          'rowId': newTask.rowId,
          'is_summary': newTask.isSummary,
          'uses_work_calendar': newTask.usesWorkCalendar,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }
  }

  /// A generic helper to show a dialog with a single text input field.
  Future<String?> _showTextInputDialog({
    required BuildContext context,
    required String title,
    required String label,
    String? initialValue,
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('textInputDialog'),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Handles the "Add Contact" action from the grid UI.
  Future<void> addContact(BuildContext context) async {
    final newContactName = await _showTextInputDialog(
      context: context,
      title: 'Add New Contact',
      label: 'Contact Name',
    );

    if (newContactName != null && newContactName.isNotEmpty) {
      final newResourceId = 'person_${DateTime.now().millisecondsSinceEpoch}';

      final newResource = GanttResourceData(
        id: newResourceId,
        name: newContactName,
        taskName: 'Summary for $newContactName', // Ensure taskName is set
        children: [],
      );
      final newGridItem =
          GanttGridData(id: newResourceId, name: newContactName, isParent: true, isExpanded: true, children: []);

      _apiResponse?.resourcesData.add(newResource);
      _gridData.add(newGridItem);
      _cachedFlatGridData = null;
      notifyListeners();
    }
  }

  /// Handles the "Add Line Item" action from the grid UI.
  Future<void> addLineItem(BuildContext context, String parentId) async {
    final parentGridItem = _gridData.firstWhere((g) => g.id == parentId);
    final newLineItemName = await _showTextInputDialog(
      context: context,
      title: 'Add New Line Item for ${parentGridItem.name}',
      label: 'Line Item Name',
    );

    if (newLineItemName != null && newLineItemName.isNotEmpty) {
      final newJobId = 'job_${DateTime.now().millisecondsSinceEpoch}';

      final newJob = GanttJobData(
          id: newJobId, name: newLineItemName, taskName: null, status: 'New', taskColor: '9E9E9E', completion: 0.0);
      final newGridItem = GanttGridData.fromJob(newJob);

      final parentResource = _apiResponse?.resourcesData.firstWhere((r) => r.id == parentId);
      parentResource?.children.add(newJob);
      parentGridItem.children.add(newGridItem);
      _cachedFlatGridData = null;
      notifyListeners();
    }
  }

  /// Toggles whether a parent row is rendered as a summary task.
  ///
  /// If `isSummary` is true, it either finds and marks an existing task as a summary
  /// or creates a new summary task that spans the duration of its children.
  void setParentTaskType(String parentId, bool isSummary) {
    if (_apiResponse == null) return;

    List<LegacyGanttTask> nextTasks = _ganttTasks;
    List<LegacyGanttTaskDependency> nextDependencies = _dependencies;

    final parentTaskIndex = nextTasks.indexWhere(
      (t) => t.rowId == parentId && !t.isTimeRangeHighlight,
    );

    if (isSummary) {
      if (parentTaskIndex != -1) {
        final existingTask = nextTasks[parentTaskIndex];
        nextTasks = List.from(nextTasks)..[parentTaskIndex] = existingTask.copyWith(isSummary: true);
      } else {
        final parentGridItem = _gridData.firstWhere((g) => g.id == parentId);
        final childIds = parentGridItem.children.map((c) => c.id).toSet();
        final childrenTasks = nextTasks.where((t) => childIds.contains(t.rowId)).toList();

        if (childrenTasks.isNotEmpty) {
          DateTime minStart = childrenTasks.first.start;
          DateTime maxEnd = childrenTasks.first.end;
          for (final task in childrenTasks) {
            if (task.start.isBefore(minStart)) {
              minStart = task.start;
            }
            if (task.end.isAfter(maxEnd)) {
              maxEnd = task.end;
            }
          }

          final newTask = LegacyGanttTask(
            id: 'summary-task-$parentId',
            rowId: parentId,
            name: parentGridItem.name,
            start: minStart,
            end: maxEnd,
            isSummary: true,
          );
          nextTasks = [...nextTasks, newTask];
        }
      }

      final hasDependency =
          nextDependencies.any((d) => d.predecessorTaskId == parentId && d.type == DependencyType.contained);
      if (!hasDependency && nextTasks.isNotEmpty) {
        final successorForContainedDemo = nextTasks.firstWhere(
          (t) => !t.isSummary && !t.isTimeRangeHighlight,
          orElse: () => nextTasks.first,
        );
        final newDependency = LegacyGanttTaskDependency(
          predecessorTaskId: parentId,
          successorTaskId: successorForContainedDemo.id,
          type: DependencyType.contained,
        );
        nextDependencies = [...nextDependencies, newDependency];
      }
    } else {
      if (parentTaskIndex != -1) {
        final existingTask = nextTasks[parentTaskIndex];
        if (existingTask.id.startsWith('summary-task-')) {
          nextTasks = nextTasks.where((t) => t.id != existingTask.id).toList();
        } else {
          nextTasks = List.from(nextTasks)..[parentTaskIndex] = existingTask.copyWith(isSummary: false);
        }
      }
      nextDependencies = nextDependencies
          .where((d) => !(d.predecessorTaskId == parentId && d.type == DependencyType.contained))
          .toList();
    }

    final (recalculatedTasks, newMaxDepth, newConflictIndicators) =
        _scheduleService.publicCalculateTaskStacking(nextTasks, _apiResponse!, showConflicts: _showConflicts);
    _dependencies = nextDependencies;
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
  }

  /// Calculates the total width of the Gantt chart's content area based on the
  /// total duration of all data and the duration of the currently visible window.
  /// This determines the scrollable width of the chart.
  double calculateGanttWidth(double screenWidth) {
    if (effectiveTotalStartDate == null ||
        effectiveTotalEndDate == null ||
        _visibleStartDate == null ||
        _visibleEndDate == null) {
      return screenWidth;
    }
    final totalDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    final visibleDuration = _visibleEndDate!.difference(_visibleStartDate!).inMilliseconds;

    if (visibleDuration <= 0) return screenWidth;

    final zoomFactor = totalDuration / visibleDuration;
    return screenWidth * zoomFactor;
  }

  /// Toggles the expanded/collapsed state of a parent row in the grid.
  void toggleExpansion(String id) {
    final item = _gridData.firstWhereOrNull((element) => element.id == id);
    if (item == null || !_gridScrollController.hasClients) return;

    final currentOffset = _gridScrollController.offset;
    final currentMaxScroll = _gridScrollController.position.maxScrollExtent;

    final visibleRowsBefore = visibleGanttRows;
    final rowIndex = visibleRowsBefore.indexWhere((r) => r.id == id);
    double childrenHeight = 0;
    if (item.isParent && item.children.isNotEmpty) {
      childrenHeight = item.children.fold<double>(0.0, (prev, child) {
        final stackDepth = _rowMaxStackDepth[child.id] ?? 1;
        return prev + (stackDepth * rowHeight);
      });
    }

    if (!item.isExpanded && ganttScrollController.hasClients) {
      final predictedNewMaxScroll = currentMaxScroll - childrenHeight;
      if (currentOffset >= predictedNewMaxScroll) {
        _gridScrollController.jumpTo(predictedNewMaxScroll);
        _ganttScrollController.jumpTo(predictedNewMaxScroll);
        item.isExpanded = !item.isExpanded;
        if (_useLocalDatabase) {
          _localRepository.updateResourceExpansion(item.id, item.isExpanded);
        }
        if (_syncClient != null) {
          final resource = _localResources.firstWhereOrNull((r) => r.id == item.id);
          final data = <String, dynamic>{
            'id': item.id,
            'is_expanded': item.isExpanded,
          };
          if (resource != null) {
            data['name'] = resource.name;
            data['parentId'] = resource.parentId;
          }

          _syncClient!.sendOperation(Operation(
            type: 'INSERT_RESOURCE',
            data: data,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            actorId: 'local-user',
          ));
        }
        _recalculateStackingAndNotify();
        return;
      }
    }

    item.isExpanded = !item.isExpanded;

    if (_useLocalDatabase) {
      _localRepository.updateResourceExpansion(item.id, item.isExpanded);
    }
    if (_syncClient != null) {
      final resource = _localResources.firstWhereOrNull((r) => r.id == item.id);
      final data = <String, dynamic>{
        'id': item.id,
        'is_expanded': item.isExpanded,
      };
      if (resource != null) {
        data['name'] = resource.name;
        data['parentId'] = resource.parentId;
      }

      _syncClient!.sendOperation(Operation(
        type: 'INSERT_RESOURCE',
        data: data,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }

    if (_apiResponse != null) {
      final visibleRowIds = visibleGanttRows.map((r) => r.id).toSet();
      final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
        _ganttTasks,
        _apiResponse!,
        showConflicts: _showConflicts,
        visibleRowIds: visibleRowIds,
      );
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);

      if (rowIndex != -1 && !item.isExpanded) {
        double rowTop = 0;
        for (int i = 0; i < rowIndex; i++) {
          rowTop += (_rowMaxStackDepth[visibleRowsBefore[i].id] ?? 1) * rowHeight;
        }
        if (rowTop < currentOffset) {
          _gridScrollController.jumpTo(currentOffset - childrenHeight);
        }
      }
    } else {
      notifyListeners();
    }
  }

  /// Helper to centralize the logic for recalculating stacking and notifying listeners.
  void _recalculateStackingAndNotify() {
    final response = _apiResponse ??
        GanttResponse(
          success: true,
          resourcesData: [],
          eventsData: [],
          assignmentsData: [],
          resourceTimeRangesData: [],
        );

    final visibleRowIds = visibleGanttRows.map((r) => r.id).toSet();
    final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
      _allGanttTasks,
      response,
      showConflicts: _showConflicts,
      visibleRowIds: visibleRowIds,
    );
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
  }

  /// Ensures that a given row is visible by expanding its parent if necessary.
  /// This is called by the Gantt chart when a hidden task is focused.
  void ensureRowIsVisible(String rowId) {
    final parent = _gridData.firstWhereOrNull((p) => p.children.any((c) => c.id == rowId));

    if (parent != null && !parent.isExpanded) {
      toggleExpansion(parent.id);
    }
  }

  /// Handles the "Copy Task" action from the context menu.
  void handleCopyTask(LegacyGanttTask task) {
    if (_apiResponse == null) return;

    final newTask = task.copyWith(
      id: 'copy_${task.id}_${DateTime.now().millisecondsSinceEpoch}',
      start: task.start.add(const Duration(days: 1)),
      end: task.end.add(const Duration(days: 1)),
    );

    if (_useLocalDatabase) {
      _localRepository.insertOrUpdateTask(newTask);
    } else {
      final newTasks = [..._ganttTasks, newTask];
      final (recalculatedTasks, newMaxDepth, newConflictIndicators) =
          _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
    }

    if (_syncClient != null) {
      _syncClient!.sendOperation(Operation(
        type: 'INSERT',
        data: {
          'id': newTask.id,
          'name': newTask.name,
          'start_date': newTask.start.millisecondsSinceEpoch,
          'end_date': newTask.end.millisecondsSinceEpoch,
          'rowId': newTask.rowId,
          'is_summary': newTask.isSummary,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }
  }

  /// Handles the "Delete Task" action from the context menu.
  void handleDeleteTask(LegacyGanttTask task) {
    if (_apiResponse == null) return;

    if (_useLocalDatabase) {
      _localRepository.deleteTask(task.id);
    } else {
      final newTasks = _ganttTasks.where((t) => t.id != task.id).toList();
      final newDependencies =
          _dependencies.where((d) => d.predecessorTaskId != task.id && d.successorTaskId != task.id).toList();

      final (recalculatedTasks, newMaxDepth, newConflictIndicators) =
          _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
      _dependencies = newDependencies;
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
    }

    if (_syncClient != null) {
      _syncClient!.sendOperation(Operation(
        type: 'DELETE',
        data: {
          'id': task.id,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }

    final remainingTasksInRow = _allGanttTasks.where((t) => t.rowId == task.rowId && t.id != task.id).length;
    if (remainingTasksInRow == 0 && !_showEmptyParentRows) {
      if (_useLocalDatabase) {
        _localRepository.deleteResource(task.rowId);
      }
      if (_syncClient != null) {
        _syncClient!.sendOperation(Operation(
          type: 'DELETE_RESOURCE',
          data: {'id': task.rowId},
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }
      if (_useLocalDatabase) {
        _localRepository.deleteResource(task.rowId);
      }
    }

    if (_useLocalDatabase) {
      _localRepository.deleteTask(task.id);
    } else {
      final newTasks = _ganttTasks.where((t) => t.id != task.id).toList();
      final newDependencies =
          _dependencies.where((d) => d.predecessorTaskId != task.id && d.successorTaskId != task.id).toList();

      final (recalculatedTasks, newMaxDepth, newConflictIndicators) =
          _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
      _dependencies = newDependencies;
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
    }

    if (_syncClient != null) {
      _syncClient!.sendOperation(Operation(
        type: 'DELETE',
        data: {
          'id': task.id,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }
  }

  /// Shows a dialog to edit all parent summary tasks at once.
  Future<void> editAllParentTasks(BuildContext context) async {
    final parentRowIds = _gridData.where((g) => g.isParent).map((g) => g.id).toSet();
    final parentSummaryTasks =
        _ganttTasks.where((t) => t.isSummary && parentRowIds.contains(t.rowId) && !t.isOverlapIndicator).toList();

    if (parentSummaryTasks.isEmpty) return;

    final updatedTasks = await showDialog<List<LegacyGanttTask>>(
      context: context,
      builder: (context) => _EditTasksInRowDialog(tasks: parentSummaryTasks),
    );

    if (updatedTasks != null) {
      _updateMultipleTasks(updatedTasks);
    }
  }

  /// Shows a dialog to edit all child tasks belonging to a specific parent.
  Future<void> editDependentTasks(BuildContext context, String parentId) async {
    final parentData = _gridData.firstWhereOrNull((p) => p.id == parentId);
    if (parentData == null || parentData.children.isEmpty) return;

    final childRowIds = parentData.children.map((c) => c.id).toSet();
    final dependentTasks = _ganttTasks
        .where((t) => childRowIds.contains(t.rowId) && !t.isSummary && !t.isTimeRangeHighlight && !t.isOverlapIndicator)
        .toList();

    if (dependentTasks.isEmpty) return;

    final updatedTasks = await showDialog<List<LegacyGanttTask>>(
      context: context,
      builder: (context) => _EditTasksInRowDialog(tasks: dependentTasks),
    );

    if (updatedTasks != null) {
      _updateMultipleTasks(updatedTasks);
    }
  }

  /// Shows a dialog to edit a single parent (summary) task.
  Future<void> editParentTask(BuildContext context, String rowId) async {
    final parentData = _gridData.firstWhereOrNull((p) => p.id == rowId);
    if (parentData != null && parentData.isParent) {
      final task = _ganttTasks.firstWhereOrNull((t) => t.rowId == rowId && t.isSummary);
      if (task != null) {
        _editTask(context, task);
      }
    } else {
      await editChildTask(context, rowId);
    }
  }

  /// Shows a dialog to edit a child task. If multiple tasks exist in the row, it lets the user choose which one to edit.
  Future<void> editChildTask(BuildContext context, String rowId) async {
    final tasksInRow = _ganttTasks
        .where((t) => t.rowId == rowId && !t.isTimeRangeHighlight && !t.isSummary && !t.isOverlapIndicator)
        .toList();
    if (tasksInRow.isEmpty) return;

    if (tasksInRow.length == 1) {
      await _editTask(context, tasksInRow.first);
    } else {
      final updatedTasks = await showDialog<List<LegacyGanttTask>>(
        context: context,
        builder: (context) => _EditTasksInRowDialog(tasks: tasksInRow),
      );

      if (updatedTasks != null) {
        _updateMultipleTasks(updatedTasks);
      }
    }
  }

  /// Shows the dialog to edit a specific task's start and end times.
  Future<void> _editTask(BuildContext context, LegacyGanttTask task) async {
    final updatedTaskData = await showDialog<({String name, DateTime start, DateTime end, double completion})>(
      context: context,
      builder: (context) => _EditTaskAlertDialog(task: task),
    );

    if (updatedTaskData != null) {
      final updatedTask = task.copyWith(
        name: updatedTaskData.name,
        start: updatedTaskData.start,
        end: updatedTaskData.end,
        completion: updatedTaskData.completion,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      );
      await _updateMultipleTasks([updatedTask]);
    }
  }

  /// Updates multiple tasks at once and recalculates stacking.
  Future<void> _updateMultipleTasks(List<LegacyGanttTask> updatedTasks) async {
    if (_apiResponse == null) return;

    final newTasks = List<LegacyGanttTask>.from(_allGanttTasks);
    for (final updatedTask in updatedTasks) {
      final index = newTasks.indexWhere((t) => t.id == updatedTask.id);
      if (index != -1) {
        final originalTask = newTasks[index];
        final now = DateTime.now().millisecondsSinceEpoch;
        newTasks[index] = originalTask.copyWith(
          name: updatedTask.name,
          start: updatedTask.start,
          end: updatedTask.end,
          completion: updatedTask.completion,
          lastUpdated: updatedTask.lastUpdated ?? now,
        );
        final parentResource =
            _apiResponse?.resourcesData.firstWhereOrNull((r) => r.children.any((c) => c.id == originalTask.rowId));
        if (parentResource != null) {
          final jobIndex = parentResource.children.indexWhere((j) => j.id == originalTask.rowId);
          if (jobIndex != -1) {
            final oldJob = parentResource.children[jobIndex];
            parentResource.children[jobIndex] = oldJob.copyWith(
              name: updatedTask.name,
              taskName: updatedTask.name,
              completion: updatedTask.completion,
            );
          }
        }
      }
    }
    await _reprocessDataFromApiResponse();
  }

  /// Deletes a row from the grid and all associated tasks from the Gantt chart.
  void deleteRow(String rowId) {
    if (_apiResponse == null) return;

    final resourcesToDelete = <String>{};
    final parentData = _gridData.firstWhereOrNull((p) => p.children.any((c) => c.id == rowId));

    if (parentData != null) {
      resourcesToDelete.add(rowId);
    } else {
      final parentToDelete = _gridData.firstWhereOrNull((p) => p.id == rowId);
      if (parentToDelete != null) {
        resourcesToDelete.add(rowId);
        resourcesToDelete.addAll(parentToDelete.children.map((c) => c.id));
      }
    }

    if (resourcesToDelete.isEmpty) return; // Should not happen if rowId is valid
    final tasksToDelete = _allGanttTasks.where((t) => resourcesToDelete.contains(t.rowId)).toList();
    if (_useLocalDatabase) {
      for (final task in tasksToDelete) {
        _localRepository.deleteTask(task.id);
      }
      resourcesToDelete.forEach(_localRepository.deleteResource);
    }

    if (_syncClient != null) {
      for (final task in tasksToDelete) {
        _syncClient!.sendOperation(Operation(
          type: 'DELETE',
          data: {'id': task.id},
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }
      for (final resId in resourcesToDelete) {
        _syncClient!.sendOperation(Operation(
          type: 'DELETE_RESOURCE',
          data: {'id': resId},
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }
    }

    if (!_useLocalDatabase) {
      final nextTasks = _allGanttTasks.where((task) => !tasksToDelete.contains(task)).toList();

      if (parentData != null) {
        parentData.children.removeWhere((child) => child.id == rowId);
        final parentResource = _apiResponse?.resourcesData.firstWhereOrNull((r) => r.id == parentData.id);
        parentResource?.children.removeWhere((job) => job.id == rowId);
      } else {
        _gridData.removeWhere((p) => p.id == rowId);
        _apiResponse?.resourcesData.removeWhere((r) => r.id == rowId);
      }
      _cachedFlatGridData = null;

      final (recalculatedTasks, newMaxDepth, newConflictIndicators) =
          _scheduleService.publicCalculateTaskStacking(nextTasks, _apiResponse!, showConflicts: _showConflicts);
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
    }
  }

  /// A helper to find the parent ID for any given row ID (child or parent).
  String? _getParentId(String rowId) {
    for (final parent in _gridData) {
      if (parent.id == rowId) {
        return parent.id; // It's a parent row
      }
      for (final child in parent.children) {
        if (child.id == rowId) {
          return parent.id; // It's a child row, return its parent's id
        }
      }
    }
    return null;
  }

  /// Re-processes the current `_apiResponse` to rebuild all UI-facing data models.
  /// This is the most reliable way to ensure data consistency after a mutation.
  Future<void> _reprocessDataFromApiResponse() async {
    if (_apiResponse == null) {
      await fetchScheduleData();
      return;
    }

    final expansionStates = {for (var item in _gridData) item.id: item.isExpanded};
    final processedData = await _scheduleService.processGanttResponse(
      _apiResponse!,
      startDate: _startDate,
      range: _range,
      showConflicts: _showConflicts,
      showEmptyParentRows: _showEmptyParentRows,
    );
    for (var newItem in processedData.gridData) {
      if (expansionStates.containsKey(newItem.id)) {
        newItem.isExpanded = expansionStates[newItem.id]!;
      }
    }

    _ganttTasks = processedData.ganttTasks;
    _conflictIndicators = processedData.conflictIndicators;
    _gridData = processedData.gridData;
    _cachedFlatGridData = null;
    _rowMaxStackDepth = processedData.rowMaxStackDepth;
    _eventMap = processedData.eventMap;

    if (_ganttTasks.isNotEmpty) {
      DateTime minStart = _ganttTasks.first.start;
      DateTime maxEnd = _ganttTasks.first.end;
      for (final task in _ganttTasks) {
        if (task.start.isBefore(minStart)) minStart = task.start;
        if (task.end.isAfter(maxEnd)) maxEnd = task.end;
      }
      _totalStartDate = minStart;
      _totalEndDate = maxEnd;
    } else {
      _totalStartDate = _startDate;
      _totalEndDate = _startDate.add(Duration(days: _range));
    }

    if (_visibleStartDate == null || _visibleEndDate == null) _setInitialVisibleWindow();

    notifyListeners();
  }

  /// Returns a list of tasks that are valid targets for a dependency relationship
  /// with the `sourceTask`. In this example, it restricts targets to tasks
  /// under the same parent resource.
  /// Returns a list of tasks that can be selected as a predecessor or successor.
  List<LegacyGanttTask> getValidDependencyTasks(LegacyGanttTask sourceTask) {
    final sourceParentId = _getParentId(sourceTask.rowId);
    if (sourceParentId == null) return [];

    final parentGridItem = _gridData.firstWhere((g) => g.id == sourceParentId,
        orElse: () => GanttGridData(id: '', name: '', isParent: false, children: []));
    if (parentGridItem.id.isEmpty) return [];

    final allRowIdsForParent = <String>{parentGridItem.id, ...parentGridItem.children.map((c) => c.id)};

    return ganttTasks
        .where((task) =>
            !task.isSummary &&
            !task.isTimeRangeHighlight &&
            !task.isOverlapIndicator &&
            task.id != sourceTask.id &&
            allRowIdsForParent.contains(task.rowId))
        .toList();
  }

  /// Adds a new dependency object directly.
  void addDependencyObject(LegacyGanttTaskDependency newDependency) {
    if (!_dependencies.any((d) =>
        d.predecessorTaskId == newDependency.predecessorTaskId && d.successorTaskId == newDependency.successorTaskId)) {
      if (_syncClient != null) {
        _syncClient!.sendOperation(Operation(
          type: 'INSERT_DEPENDENCY',
          data: {
            'predecessorTaskId': newDependency.predecessorTaskId,
            'successorTaskId': newDependency.successorTaskId,
            'type': newDependency.type.name,
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }

      if (_useLocalDatabase) {
        _localRepository.insertOrUpdateDependency(newDependency).then((_) => notifyListeners());
      } else {
        _dependencies = List.from(_dependencies)..add(newDependency);
        notifyListeners();
      }
    }
  }

  /// Adds a new dependency between two tasks.
  void addDependency(String fromTaskId, String toTaskId) {
    final newDependency = LegacyGanttTaskDependency(
      predecessorTaskId: fromTaskId,
      successorTaskId: toTaskId,
      type: DependencyType.finishToStart,
    );
    addDependencyObject(newDependency);
  }

  /// Returns a list of dependencies where the given task is either a predecessor or a successor.
  List<LegacyGanttTaskDependency> getDependenciesForTask(LegacyGanttTask task) =>
      _dependencies.where((d) => d.predecessorTaskId == task.id || d.successorTaskId == task.id).toList();

  /// Removes a specific dependency.
  void removeDependency(LegacyGanttTaskDependency dependency) {
    final initialCount = _dependencies.length;
    final newList = _dependencies.where((d) => d != dependency).toList();

    if (newList.length < initialCount) {
      if (_syncClient != null) {
        _syncClient!.sendOperation(Operation(
          type: 'DELETE_DEPENDENCY',
          data: {
            'predecessorTaskId': dependency.predecessorTaskId,
            'successorTaskId': dependency.successorTaskId,
          },
          timestamp: DateTime.now().millisecondsSinceEpoch,
          actorId: 'local-user',
        ));
      }

      if (_useLocalDatabase) {
        _localRepository
            .deleteDependency(dependency.predecessorTaskId, dependency.successorTaskId)
            .then((_) => notifyListeners());
      } else {
        _dependencies = newList;
        notifyListeners();
      }
    }
  }

  /// Removes all dependencies associated with a given task.
  void clearDependenciesForTask(LegacyGanttTask task) {
    if (_syncClient != null) {
      _syncClient!.sendOperation(Operation(
        type: 'CLEAR_DEPENDENCIES',
        data: {'taskId': task.id},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }

    if (_useLocalDatabase) {
      _localRepository.deleteDependenciesForTask(task.id).then((_) => notifyListeners());
    } else {
      final initialCount = _dependencies.length;
      final newList =
          _dependencies.where((d) => d.predecessorTaskId != task.id && d.successorTaskId != task.id).toList();

      if (newList.length < initialCount) {
        _dependencies = newList;
        notifyListeners();
      }
    }
  }

  /// Returns a date formatting function for the tooltip based on the selected timeline axis format.
  String Function(DateTime) _getTooltipDateFormat() {
    switch (_selectedAxisFormat) {
      case TimelineAxisFormat.auto:
        return (date) => DateFormat.yMd(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.dayOfMonth:
        return (date) => DateFormat.yMd(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.dayAndMonth:
        return (date) => DateFormat.MMMd(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.monthAndYear:
        return (date) => DateFormat.yMMM(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.dayOfWeek:
        return (date) => DateFormat.E(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.custom:
        return (date) => DateFormat.yMd(_selectedLocale).add_jm().format(date);
    }
  }

  /// Sends a request to the server to optimize the schedule.
  Future<void> optimizeSchedule() async {
    if (_syncClient != null) {
      await _syncClient!.sendOperation(Operation(
        type: 'OPTIMIZE_SCHEDULE',
        data: {}, // No payload needed, server fetches tasks
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'local-user',
      ));
    }
  }
}

/// A dialog for editing the properties of a single task.
class _EditTaskAlertDialog extends StatefulWidget {
  final LegacyGanttTask task;

  const _EditTaskAlertDialog({required this.task});

  @override
  State<_EditTaskAlertDialog> createState() => _EditTaskAlertDialogState();
}

class _EditTaskAlertDialogState extends State<_EditTaskAlertDialog> {
  late final TextEditingController _nameController;
  late DateTime _startDate;
  late DateTime _endDate;
  late double _completion;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task.name);
    _startDate = widget.task.start;
    _endDate = widget.task.end;
    _completion = widget.task.completion;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.isNotEmpty) {
      Navigator.pop(context, (name: _nameController.text, start: _startDate, end: _endDate, completion: _completion));
    }
  }

  Future<void> _selectDateTime(BuildContext context, bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );

    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (pickedTime == null) return;

    setState(() {
      final newDateTime =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
      if (isStart) {
        _startDate = newDateTime;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 1));
        }
      } else {
        _endDate = newDateTime;
        if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate.subtract(const Duration(hours: 1));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('editTaskDialog'),
        title: const Text('Edit Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Task Name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Start:'),
                TextButton(
                    onPressed: () => _selectDateTime(context, true),
                    child: Text(DateFormat.yMd().add_jm().format(_startDate)))
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('End:'),
                TextButton(
                    onPressed: () => _selectDateTime(context, false),
                    child: Text(DateFormat.yMd().add_jm().format(_endDate)))
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Completion:'),
                Expanded(
                  child: Slider(
                    value: _completion,
                    onChanged: (value) => setState(() => _completion = value),
                    label: '${(_completion * 100).round()}%',
                    divisions: 100,
                  ),
                ),
                Text('${(_completion * 100).round()}%'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}

/// A dialog that displays a list of tasks in a `DataTable` and allows editing their names and dates.
class _EditTasksInRowDialog extends StatefulWidget {
  final List<LegacyGanttTask> tasks;

  const _EditTasksInRowDialog({required this.tasks});

  @override
  State<_EditTasksInRowDialog> createState() => _EditTasksInRowDialogState();
}

class _EditTasksInRowDialogState extends State<_EditTasksInRowDialog> {
  late List<LegacyGanttTask> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = widget.tasks.map((t) => t.copyWith()).toList();
  }

  Future<void> _editName(LegacyGanttTask task) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _EditNameDialog(initialName: task.name),
    );

    if (newName != null && newName.isNotEmpty) {
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = _tasks[index].copyWith(name: newName);
        }
      });
    }
  }

  Future<void> _editDate(LegacyGanttTask task, bool isStart) async {
    final initialDate = isStart ? task.start : task.end;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate));
    if (pickedTime == null) return;

    setState(() {
      final newDateTime =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        var tempTask = _tasks[index];
        if (isStart) {
          tempTask = tempTask.copyWith(start: newDateTime);
          if (tempTask.end.isBefore(tempTask.start)) {
            tempTask = tempTask.copyWith(end: tempTask.start.add(const Duration(hours: 1)));
          }
        } else {
          tempTask = tempTask.copyWith(end: newDateTime);
          if (tempTask.start.isAfter(tempTask.end)) {
            tempTask = tempTask.copyWith(start: tempTask.end.subtract(const Duration(hours: 1)));
          }
        }
        _tasks[index] = tempTask;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('editTasksInRowDialog'),
        title: const Text('Edit Tasks'),
        scrollable: true,
        content: SizedBox(
          width: 500, // Give it a reasonable width
          child: DataTable(
            columnSpacing: 16,
            columns: const [
              DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Start', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              DataColumn(label: Text('End', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            ],
            rows: _tasks
                .map((task) => DataRow(
                      cells: [
                        DataCell(
                          Text(task.name ?? 'Unnamed Task', overflow: TextOverflow.ellipsis),
                          onTap: () => _editName(task),
                        ),
                        DataCell(
                          Text(DateFormat.yMd().add_jm().format(task.start)),
                          onTap: () => _editDate(task, true),
                        ),
                        DataCell(
                          Text(DateFormat.yMd().add_jm().format(task.end)),
                          onTap: () => _editDate(task, false),
                        ),
                      ],
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, _tasks),
            child: const Text('Save'),
          ),
        ],
      );
}

/// A small dialog specifically for editing a task's name.
class _EditNameDialog extends StatefulWidget {
  final String? initialName;

  const _EditNameDialog({this.initialName});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('editNameDialog'),
        title: const Text('Edit Task Name'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
