import 'package:material_ui/material_ui.dart';

import 'dart:math' as math;

import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/offline_sync.dart';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import 'dart:async';
import 'dart:convert';

import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:synchronized/synchronized.dart';
import 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart' as scrubber;

import '../data/models.dart';
import '../data/local/local_gantt_repository.dart';
import '../services/gantt_schedule_service.dart';
import '../ui/dialogs/create_task_dialog.dart';
import '../ui/gantt_grid_data.dart';
import '../data/local/gantt_db.dart';
import '../data/local/protocol_state_store.dart';
import '../data/local/persisted_gantt_sync_client.dart';
import '../data/local/presence_gantt_sync_client.dart';
import '../data/local/legacy_projection_migration.dart';

/// An enum to manage the different theme presets demonstrated in the example.
enum ThemePreset { standard, forest, midnight }

enum TimelineAxisFormat { auto, dayOfMonth, dayAndMonth, monthAndYear, dayOfWeek, custom }

class GanttViewModel extends ChangeNotifier {
  final Future<SqliteCrdt> _database;
  final _localMutations = Lock();
  late final LocalGanttRepository _localRepository = LocalGanttRepository(database: _database);
  Future<void> _initialized = Future.value();
  Future<void> get initialized => _initialized;
  StreamSubscription<ProtocolSnapshot>? _stateSubscription;
  ProtocolStateStore? _canonicalState;
  int _syncGeneration = 0;
  int _connectionAttempt = 0;
  String? _boundScope;
  bool _disposed = false;
  Future<void> _incomingOperationChain = Future.value();
  ProtocolStateStore get _protocolState => _canonicalState ??= ProtocolStateStore(_database, scope: 'local');

  Future<void> _bindProtocolScope(String scope) async {
    _syncGeneration++;
    await _syncOperationsSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    if (_syncClient is OfflineGanttSyncClient) {
      await (_syncClient as OfflineGanttSyncClient).removeInnerClient();
    }
    await _incomingOperationChain;
    _isMerkleSyncing = false;
    _initialSyncExpected = 0;
    _initialSyncReceived = 0;
    final db = await _database;
    final rows = await db.query(
      "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
    );
    final previousScope = rows.firstOrNull?['meta_value'];
    final pending = await db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id');
    if (previousScope != null && previousScope != scope && pending.isNotEmpty) {
      throw StateError('Synchronize pending changes with their original tenant before switching servers or tenants.');
    }
    if (previousScope != scope && pending.isEmpty) {
      await db.transaction((transaction) async {
        await transaction.execute('DELETE FROM dependencies');
        await transaction.execute('DELETE FROM tasks');
        await transaction.execute('DELETE FROM resources');
        await transaction.execute("DELETE FROM sync_metadata WHERE meta_key = 'last_server_sync'");
      });
      _isMerkleSyncing = false;
      _initialSyncExpected = 0;
      _initialSyncReceived = 0;
      _dependencies.clear();
      _ganttTasks.clear();
      _allGanttTasks.clear();
      _localResources.clear();
      _gridData.clear();
      _rowMaxStackDepth.clear();
      _connectedUsers.clear();
      _eventMap.clear();
      _apiResponse = null;
      _cachedFlatGridData = null;
      _cachedVisibleFlatGridData = null;
      _conflictIndicators.clear();
      _syncToController();
      notifyListeners();
    }
    final state = ProtocolStateStore(_database, scope: scope);
    await state.applyOperations(
      pending
          .map(
            (row) => Operation(
              type: row['type'] as String,
              data: jsonDecode(row['data'] as String) as Map<String, dynamic>,
              timestamp: Hlc.parse(row['timestamp'] as String),
              actorId: row['actor_id'] as String,
            ),
          )
          .toList(),
      local: true,
      bindScope: true,
    );
    await _stateSubscription?.cancel();
    await _canonicalState?.close();
    _canonicalState = state;
    _boundScope = scope;
    _isLocalPreview = false;
    await _subscribeToState();
    await state.restoreProjection();
    _acceptSnapshot(await state.readState(), force: true);
  }

  bool _useLocalDatabase = false;
  bool _isLocalPreview = false;

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
  List<LocalResource> get localResources => UnmodifiableListView(_localResources);
  List<LegacyGanttTask> get allTasks => UnmodifiableListView(_allGanttTasks);

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
      unawaited(updateTasksBulk(updatedTasks));

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

  /// Scroll controllers to synchronize the vertical scroll of the grid and chart,
  /// and to manage the horizontal scroll of the chart.
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _ganttScrollController = ScrollController();
  final ScrollController _ganttHorizontalScrollController = ScrollController();

  bool _areScrollListenersAttached = false;

  /// The controller for the Gantt chart.
  late final LegacyGanttController controller;

  /// A flag to prevent a feedback loop between the timeline scrubber and the horizontal scroll controller.
  bool _isScrubberUpdating = false; // Prevents feedback loop between scroller and scrubber

  bool _isSyncingGridScroll = false;
  bool _isSyncingGanttScroll = false;

  /// A flag to indicate when data is being fetched.
  bool _isLoading = true;

  void _setLoading(bool vars) {
    _isLoading = vars;
    // ignore: invalid_use_of_protected_member
    controller.setIsLoading(vars);
  }

  /// The ID of the task that currently has keyboard focus.
  String? _focusedTaskId;
  int _seedVersion = 0;
  int get seedVersion => _seedVersion;
  bool _pendingSeedReset = false;

  OverlayEntry? _tooltipOverlay;
  String? _hoveredTaskId;

  List<Map<String, dynamic>>? _cachedVisibleFlatGridData;

  /// The result of the hit-testing performed by legacy_tree_grid is now
  /// handled via the onNest and onReorder callbacks.

  final GanttScheduleService _scheduleService = GanttScheduleService();
  GanttResponse? get apiResponse => _apiResponse;

  bool get useLocalDatabase => _useLocalDatabase;

  Future<void> setUseLocalDatabase(bool value) {
    final transition = _initialized.then((_) async {
      if (_useLocalDatabase == value) return;
      _useLocalDatabase = value;
      notifyListeners();
      if (value) {
        await _initLocalMode();
      } else {
        await _exitLocalMode();
      }
    });
    _initialized = transition;
    return transition;
  }

  Future<void> _initLocalMode() async {
    _setLoading(true);
    await _localRepository.init();
    final db = await _database;
    final scopeRows = await db.query(
      "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
    );
    final pending = await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0 LIMIT 1');
    final scope = scopeRows.firstOrNull?['meta_value'] as String?;
    _boundScope = scope;
    _isLocalPreview = scope == null && pending.isEmpty;
    _canonicalState = ProtocolStateStore(_database, scope: scope ?? (_isLocalPreview ? 'preview' : 'local'));
    _syncClient ??= PersistedGanttSyncClient(_database, protocolState: () => _protocolState);
    controller.setSyncClient(_syncClient!);

    final legacyTasks = await _localRepository.getAllTasks();
    final legacyResources = await _localRepository.getAllResources();
    final legacyDependencies = await _localRepository.getAllDependencies();
    var snapshot = await _protocolState.readState();
    if (_isLocalPreview &&
        !snapshot.hasState &&
        (legacyTasks.isNotEmpty || legacyResources.isNotEmpty || legacyDependencies.isNotEmpty)) {
      // Existing unclassified local rows belong to the user, not the generated preview.
      _isLocalPreview = false;
      await _canonicalState?.close();
      _canonicalState = ProtocolStateStore(_database, scope: 'local');
    }
    await migrateLegacyProjection(database: db, state: _protocolState, enqueue: !_isLocalPreview);
    snapshot = await _protocolState.readState();
    await _subscribeToState();
    if (!snapshot.hasState && _isLocalPreview && legacyTasks.isEmpty && legacyResources.isEmpty) {
      await seedLocalDatabase(synchronize: false);
    } else {
      await _protocolState.restoreProjection();
      _acceptSnapshot(await _protocolState.readState(), force: true);
    }
    _pendingSeedReset = true;
  }

  Future<void> _subscribeToState() async {
    await _stateSubscription?.cancel();
    _stateSubscription = _protocolState.snapshots.listen(_acceptSnapshot);
    final snapshot = await _protocolState.readState();
    if (_syncClient case final OfflineGanttSyncClient client) {
      await client.ready;
      if (snapshot.latestClock != null) client.observeClock(snapshot.latestClock!);
    }
  }

  void _acceptSnapshot(ProtocolSnapshot snapshot, {bool force = false}) {
    if (_disposed) return;
    if (_syncClient case final OfflineGanttSyncClient client) {
      if (snapshot.latestClock != null) client.observeClock(snapshot.latestClock!);
    }
    if (!force && (_isMerkleSyncing || _isInitialSyncing)) return;
    _allGanttTasks = List.of(snapshot.tasks);
    _localResources = List.of(snapshot.resources);
    _dependencies = List.of(snapshot.dependencies);
    _cachedFlatGridData = null;
    _cachedVisibleFlatGridData = null;
    unawaited(_processLocalData());
  }

  Operation _taskOperation(
    LegacyGanttTask task, {
    String type = 'INSERT_TASK',
    Hlc? timestamp,
    LegacyGanttTask? previous,
  }) {
    final clock = timestamp ?? _currentHlc;
    final actor = _syncClient?.actorId ?? 'local-user';
    final data = ProtobufMapper.taskToJson(task.copyWith(lastUpdated: clock, lastUpdatedBy: actor).toProtocolTask());
    final previousData = previous == null ? <String, dynamic>{} : ProtobufMapper.taskToJson(previous.toProtocolTask());
    const envelopeFields = {
      'id',
      'taskId',
      'lastUpdated',
      'lastUpdatedBy',
      'fieldTimestamps',
      'start_date',
      'end_date',
      'gantt_type',
    };
    data['fieldTimestamps'] = {
      for (final entry in data.entries)
        if (!envelopeFields.contains(entry.key))
          entry.key: previous != null && const DeepCollectionEquality().equals(previousData[entry.key], entry.value)
              ? (previous.fieldTimestamps[entry.key] ?? previous.lastUpdated).toString()
              : clock.toString(),
    };
    return Operation(type: type, data: data, timestamp: clock, actorId: actor);
  }

  Operation _resourceOperation(LocalResource resource, {Hlc? timestamp}) {
    final clock = timestamp ?? _currentHlc;
    return Operation(
      type: 'INSERT_RESOURCE',
      data: ProtobufMapper.resourceToJson(resource.copyWith(lastUpdated: clock).toProtocolResource()),
      timestamp: clock,
      actorId: _syncClient?.actorId ?? 'local-user',
    );
  }

  Operation _dependencyOperation(LegacyGanttTaskDependency dependency, {Hlc? timestamp}) {
    final clock = timestamp ?? _currentHlc;
    return Operation(
      type: 'INSERT_DEPENDENCY',
      data: {...ProtobufMapper.dependencyToJson(dependency.toProtocolDependency()), 'lastUpdated': clock.toString()},
      timestamp: clock,
      actorId: _syncClient?.actorId ?? 'local-user',
    );
  }

  Future<void> _commitOperations(List<Operation> operations) {
    if (_disposed) {
      return Future.error(StateError('The local client has been disposed.'));
    }
    final expectedScope = _boundScope;
    var committedOperations = operations;
    return _localMutations.synchronized(() async {
      await initialized;
      if (_boundScope != expectedScope) {
        throw StateError('The active tenant changed before this edit could be committed.');
      }
      if (committedOperations.isEmpty) return;
      if (_isLocalPreview) {
        final preview = await _protocolState.readState();
        committedOperations = [
          for (final resource in preview.resources)
            _resourceOperation(resource, timestamp: resource.lastUpdated ?? Hlc.zero),
          for (final task in preview.tasks) _taskOperation(task, timestamp: task.lastUpdated),
          for (final dep in preview.dependencies) _dependencyOperation(dep, timestamp: dep.lastUpdated),
          ...committedOperations,
        ];
        _isLocalPreview = false;
        await _stateSubscription?.cancel();
        await _canonicalState?.close();
        _canonicalState = ProtocolStateStore(_database, scope: 'local');
        await _subscribeToState();
      }
      final client = _syncClient;
      try {
        if (client is PersistedGanttSyncClient) {
          await client.sendOperations(committedOperations);
        } else {
          await _protocolState.applyOperations(committedOperations, local: true);
          await client?.sendOperations(committedOperations);
        }
      } catch (_) {
        _acceptSnapshot(await _protocolState.readState(), force: true);
        rethrow;
      }
      _acceptSnapshot(await _protocolState.readState(), force: true);
      committedOperations.forEach(controller.recordOperation);
    });
  }

  Hlc get _currentHlc {
    if (_syncClient != null) {
      return _syncClient!.currentHlc;
    }
    return Hlc.fromDate(DateTime.now(), 'local');
  }

  Future<void> _processLocalData() async {
    if (_allGanttTasks.isEmpty) {
      _setLoading(false);
      _conflictIndicators = [];
      _ganttTasks = [];
      _dependencies = [];
      _gridData = [];
      _rowMaxStackDepth = {};
      _totalStartDate = null;
      _totalEndDate = null;
      notifyListeners();
      return;
    }

    _gridData = _buildGridDataFromResources(_localResources, _allGanttTasks);
    _cachedFlatGridData = null; // Invalidate cache
    _cachedVisibleFlatGridData = null; // Invalidate visible cache

    if (_pendingSeedReset && (_localResources.isNotEmpty || !_useLocalDatabase)) {
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
          .map(
            (child) => GanttJobData(
              id: child.id,
              name: child.name ?? 'Unnamed', // Name defaults
              taskName: null,
              status: 'Open', // Dummy data
              taskColor: '888888', // Dummy data
              completion: 0,
            ),
          )
          .toList();

      resourcesData.add(
        GanttResourceData(id: parent.id, name: parent.name ?? 'Unnamed', taskName: null, children: children),
      );
    }

    final dummyResponse = GanttResponse(
      success: true,
      resourcesData: resourcesData,
      eventsData: [],
      assignmentsData: [],
      dependenciesData: [],
      resourceTimeRangesData: [],
    );
    _apiResponse = dummyResponse;

    final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
      _allGanttTasks,
      dummyResponse,
      showConflicts: _showConflicts,
      visibleRowIds: visibleRowIds,
    );

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
        _setInitialVisibleWindow();
      }
    }

    _setLoading(false);
    _syncToController();
    notifyListeners();
  }

  Future<void> convertTaskType(LegacyGanttTask task, String newType) async {
    LegacyGanttTask newTask = task;

    if (newType == 'milestone') {
      newTask = task.copyWith(isMilestone: true, isSummary: false, end: task.start);
    } else if (newType == 'summary') {
      DateTime newEnd = task.end;
      if (task.isMilestone && task.start == task.end) {
        newEnd = task.start.add(const Duration(days: 1));
      }
      newTask = task.copyWith(isMilestone: false, isSummary: true, end: newEnd);
    } else if (newType == 'task') {
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

    // Set last updated by
    newTask = newTask.copyWith(lastUpdated: _currentHlc, lastUpdatedBy: _currentUsername ?? 'local-user');

    await updateTask(newTask);
  }

  Future<void> addTask(LegacyGanttTask task) => addTasks([task]);

  Future<void> addResources(List<LocalResource> resources) =>
      _commitOperations(resources.map((resource) => _resourceOperation(resource)).toList());

  Future<void> addTasks(List<LegacyGanttTask> tasks) => _commitOperations(
    tasks.map((task) => _taskOperation(task.copyWith(lastUpdatedBy: _currentUsername ?? 'local-user'))).toList(),
  );

  Future<void> addDependencies(List<LegacyGanttTaskDependency> dependencies) =>
      _commitOperations(dependencies.map((dependency) => _dependencyOperation(dependency)).toList());

  Future<void> updateTask(LegacyGanttTask task) => updateTasksBulk([task]);

  Future<void> updateTasksBulk(List<LegacyGanttTask> tasks) async {
    final clock = _currentHlc;
    final actor = _currentUsername ?? 'local-user';
    final updates = tasks.map((task) => task.copyWith(lastUpdated: clock, lastUpdatedBy: actor)).toList();
    final originals = {for (final task in _allGanttTasks) task.id: task};
    final operations = updates
        .map((task) => _taskOperation(task, type: 'UPDATE_TASK', timestamp: clock, previous: originals[task.id]))
        .toList();
    final byId = {for (final task in updates) task.id: task};
    _allGanttTasks = _allGanttTasks.map((task) => byId[task.id] ?? task).toList();
    unawaited(_processLocalData());
    try {
      await _commitOperations(operations);
    } catch (_) {
      _acceptSnapshot(await _protocolState.readState(), force: true);
      rethrow;
    }
  }

  Future<void> deleteTasksBulk(List<LegacyGanttTask> tasks) async {
    final ids = tasks.map((task) => task.id).toSet();
    _allGanttTasks = _allGanttTasks.where((task) => !ids.contains(task.id)).toList();
    unawaited(_processLocalData());
    final operations = <Operation>[
      for (final dependency in _dependencies.where(
        (dep) => ids.contains(dep.predecessorTaskId) || ids.contains(dep.successorTaskId),
      ))
        Operation(
          type: 'DELETE_DEPENDENCY',
          data: {'predecessorTaskId': dependency.predecessorTaskId, 'successorTaskId': dependency.successorTaskId},
          timestamp: _currentHlc,
          actorId: _syncClient?.actorId ?? 'local-user',
        ),
      for (final id in ids)
        Operation(
          type: 'DELETE_TASK',
          data: {'id': id},
          timestamp: _currentHlc,
          actorId: _syncClient?.actorId ?? 'local-user',
        ),
    ];
    try {
      await _commitOperations(operations);
    } catch (_) {
      _acceptSnapshot(await _protocolState.readState(), force: true);
      rethrow;
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
        .map(
          (t) => GanttEventData(
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
          ),
        )
        .toList();

    final exportedResources = _localResources.where((r) => r.parentId == null).map((parent) {
      final children = _localResources
          .where((r) => r.parentId == parent.id)
          .map((child) => GanttJobData(id: child.id, name: child.name ?? 'Unnamed', status: 'Open'))
          .toList();
      return GanttResourceData(id: parent.id, name: parent.name ?? 'Unnamed', children: children);
    }).toList();

    final response = GanttResponse(
      success: true,
      eventsData: exportedEvents,
      resourcesData: exportedResources,
      assignmentsData: _ganttTasks
          .where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)
          .map((t) => GanttAssignmentData(id: 'assignment-${t.id}', event: t.id, resource: t.rowId))
          .toList(),
      dependenciesData: _dependencies
          .map(
            (d) => GanttDependencyData(
              id: 'dep-${d.predecessorTaskId}-${d.successorTaskId}',
              predecessorId: d.predecessorTaskId,
              successorId: d.successorTaskId,
              type: d.type.toString().split('.').last,
            ),
          )
          .toList(),
      resourceTimeRangesData: _apiResponse?.resourceTimeRangesData ?? [],
    );

    final json = response.toJson();
    json['conflictIndicators'] = _conflictIndicators
        .map((c) => {'id': c.id, 'rowId': c.rowId, 'start': c.start.toIso8601String(), 'end': c.end.toIso8601String()})
        .toList();

    return json;
  }

  Future<void>? _activeSeedingFuture;
  bool _activeSeedSynchronizes = false;

  Future<void> seedLocalDatabase({bool synchronize = true}) async {
    if (_activeSeedingFuture != null) {
      final preview = !_activeSeedSynchronizes;
      await _activeSeedingFuture;
      if (synchronize && preview) await seedLocalDatabase();
      return;
    }

    _activeSeedSynchronizes = synchronize;
    _activeSeedingFuture = _seedLocalDatabaseInternal(synchronize: synchronize);
    try {
      await _activeSeedingFuture;
    } finally {
      _activeSeedingFuture = null;
    }
  }

  Future<void>? _activeClearFuture;

  Future<void> clearDatabase() async {
    if (_activeClearFuture != null) {
      return _activeClearFuture;
    }

    _activeClearFuture = _clearDatabaseInternal();
    try {
      await _activeClearFuture;
    } finally {
      _activeClearFuture = null;
    }
  }

  Future<void> _clearDatabaseInternal() async {
    _pendingSeedReset = true;
    await _commitOperations([
      Operation(type: 'RESET_DATA', data: {}, timestamp: _currentHlc, actorId: _syncClient?.actorId ?? 'local-user'),
    ]);
  }

  Future<void> _seedLocalDatabaseInternal({required bool synchronize}) async {
    _pendingSeedReset = true;
    _setLoading(true);
    notifyListeners();

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
        color: null, // Default to theme
        parentId: parentTask?.id,
      );
      tasks.add(milestone);
    }
    final dependencies = processedData.dependencies.toList(); // Start with API dependencies

    // Contained dependencies (Parent -> Child) to support Gantt Chart logic/visuals
    // Now that IDs are aligned in MockApiService, this works correctly without breaking things.
    for (final task in tasks) {
      if (task.parentId != null) {
        dependencies.add(
          LegacyGanttTaskDependency(
            predecessorTaskId: task.parentId!,
            successorTaskId: task.id,
            type: DependencyType.contained,
          ),
        );
      }
    }

    // Explicitly set the last updated by for seeded tasks to 'local-user'
    // so the inspector doesn't show 'Unknown'
    final tasksWithUser = tasks
        .where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)
        .map((t) => t.copyWith(lastUpdated: _currentHlc, lastUpdatedBy: 'local-user'))
        .toList();

    final resourcesToInsert = <LocalResource>[];
    for (int i = 0; i < processedData.apiResponse.resourcesData.length; i++) {
      final resource = processedData.apiResponse.resourcesData[i];
      final isExpanded = i == 0; // Only expand the first one

      resourcesToInsert.add(
        LocalResource(id: resource.id, name: resource.name, parentId: null, isExpanded: isExpanded),
      );

      for (final child in resource.children) {
        resourcesToInsert.add(LocalResource(id: child.id, name: child.name, parentId: resource.id, isExpanded: true));
      }
    }
    final operations = <Operation>[
      Operation(type: 'RESET_DATA', data: {}, timestamp: _currentHlc, actorId: _syncClient?.actorId ?? 'local-user'),
      for (var index = 0; index < resourcesToInsert.length; index++)
        _resourceOperation(resourcesToInsert[index].copyWith(sortOrder: index.toDouble())),
      for (final task in tasksWithUser) _taskOperation(task),
      for (final dependency in dependencies) _dependencyOperation(dependency),
    ];
    if (synchronize) {
      await _commitOperations(operations);
    } else {
      final commit = await _protocolState.applyOperations(operations, local: true);
      _acceptSnapshot(commit.state, force: true);
    }
    _setLoading(false);
    notifyListeners();
  }

  Future<void> _exitLocalMode() async {
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
            final rowTasks = tasks
                .where((t) => t.rowId == child.id && !t.isTimeRangeHighlight && !t.isOverlapIndicator)
                .toList();
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

          nodes.add(
            GanttGridData(
              id: child.id,
              name: child.name ?? 'Unnamed',
              isParent: grandChildren.isNotEmpty,
              children: grandChildren,
              isExpanded: child.isExpanded,
              completion: completion,
              sortOrder: child.sortOrder,
            ),
          );
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
      grid.add(
        GanttGridData(
          id: key,
          name: tasks.firstWhereOrNull((t) => t.rowId == key)?.name ?? 'Row $key',
          isParent: false,
          children: [],
        ),
      );
    }
    return grid;
  }

  double? _gridWidth;
  double? _controlPanelWidth = 300.0;
  List<LegacyGanttTask> get ganttTasks => _ganttTasks;

  List<LegacyGanttTask> get conflictIndicators => _showConflicts ? _conflictIndicators : [];
  String Function(DateTime)? get resizeTooltipDateFormat => _resizeTooltipDateFormat;
  List<LegacyGanttTaskDependency> get dependencies => _showDependencies ? _presentationDependencies : [];

  List<LegacyGanttTaskDependency> get _presentationDependencies {
    final result = List<LegacyGanttTaskDependency>.of(_dependencies);
    final keys = _dependencies
        .where((dep) => dep.type == DependencyType.contained)
        .map((dep) => (dep.predecessorTaskId, dep.successorTaskId))
        .toSet();
    for (final task in _allGanttTasks) {
      if (task.parentId != null && keys.add((task.parentId!, task.id))) {
        result.add(
          LegacyGanttTaskDependency(
            predecessorTaskId: task.parentId!,
            successorTaskId: task.id,
            type: DependencyType.contained,
            lastUpdated: task.lastUpdated,
          ),
        );
      }
    }
    return result;
  }

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

    void collect(GanttGridData node, String? parentId) {
      flatList.add({
        'id': node.id,
        'name': node.name,
        'completion': node.completion,
        'parentId': parentId,
        'isExpanded': node.isExpanded,
        'sortOrder': node.sortOrder,
      });
      for (final child in node.children) {
        collect(child, node.id);
      }
    }

    for (final node in _gridData) {
      collect(node, null);
    }

    _cachedFlatGridData = flatList;
    return flatList;
  }

  /// Returns only the visible (expanded) rows for UI hit-testing.
  List<Map<String, dynamic>> get visibleFlatGridData {
    if (_cachedVisibleFlatGridData != null) return _cachedVisibleFlatGridData!;
    final List<Map<String, dynamic>> flatList = [];

    void collect(GanttGridData node, String? parentId) {
      flatList.add({
        'id': node.id,
        'name': node.name,
        'completion': node.completion,
        'parentId': parentId,
        'isExpanded': node.isExpanded,
        'sortOrder': node.sortOrder,
      });
      if (node.isExpanded) {
        for (final child in node.children) {
          collect(child, node.id);
        }
      }
    }

    for (final node in _gridData) {
      collect(node, null);
    }

    _cachedVisibleFlatGridData = flatList;
    return flatList;
  }

  Future<void> reorderResources(String draggedId, String? targetId, bool isAfter) async {
    if (!_useLocalDatabase) return;

    final flatList = flatGridData;
    final oldIndex = flatList.indexWhere((item) => item['id'] == draggedId);
    if (oldIndex < 0) return;

    int targetIndex = targetId != null ? flatList.indexWhere((item) => item['id'] == targetId) : -1;
    int effectiveNewIndex;
    if (targetId == null) {
      effectiveNewIndex = flatList.length;
    } else {
      effectiveNewIndex = isAfter ? targetIndex + 1 : targetIndex;
    }

    if (oldIndex < effectiveNewIndex) {
      effectiveNewIndex -= 1;
    }

    if (effectiveNewIndex < 0 || effectiveNewIndex >= flatList.length) return;

    final movedItem = flatList[oldIndex];
    final movedId = movedItem['id'] as String;

    // Simulate removal to find correct neighbors
    final simulatedList = List<Map<String, dynamic>>.from(flatList);
    simulatedList.removeAt(oldIndex);

    // Determine target index in simulated list
    if (effectiveNewIndex > simulatedList.length) effectiveNewIndex = simulatedList.length;

    final prevItem = effectiveNewIndex > 0 ? simulatedList[effectiveNewIndex - 1] : null;
    final nextItem = effectiveNewIndex < simulatedList.length ? simulatedList[effectiveNewIndex] : null;

    String? newParentId;
    if (targetId != null) {
      final targetItem = flatList.firstWhereOrNull((r) => r['id'] == targetId);
      newParentId = targetItem?['parentId'] as String?;
    } else {
      newParentId = prevItem?['parentId'] as String?;
    }

    // Sort order logic
    double? prevSortOrder;
    double? nextSortOrder;

    Future<double> ensureSortOrder(Map<String, dynamic> item, int listIndex) async {
      if (item['sortOrder'] != null) return item['sortOrder'] as double;
      final newOrder = listIndex * 10000.0;
      final resId = item['id'] as String;
      final resource = _localResources.firstWhereOrNull((r) => r.id == resId);
      if (resource != null) {
        await addResources([resource.copyWith(sortOrder: newOrder)]);
      }
      return newOrder;
    }

    if (effectiveNewIndex == 0) {
      if (nextItem != null) {
        nextSortOrder = await ensureSortOrder(nextItem, 0);
        prevSortOrder = nextSortOrder - 1000.0;
      } else {
        prevSortOrder = 0.0;
      }
    } else {
      prevSortOrder = await ensureSortOrder(prevItem!, effectiveNewIndex - 1);
      if (nextItem != null) {
        nextSortOrder = await ensureSortOrder(nextItem, effectiveNewIndex);
      }
    }

    final double finalSortOrder;
    if (nextSortOrder != null) {
      if (nextSortOrder <= prevSortOrder) {
        finalSortOrder = prevSortOrder + 1.0;
      } else {
        finalSortOrder = (prevSortOrder + nextSortOrder) / 2.0;
      }
    } else {
      finalSortOrder = prevSortOrder + 1.0;
    }

    final resource = _localResources.firstWhereOrNull((r) => r.id == movedId);
    if (resource != null) {
      final updatedResource = resource.copyWith(
        parentId: newParentId,
        clearParent: newParentId == null,
        sortOrder: finalSortOrder,
        lastUpdated: _currentHlc,
      );

      final index = _localResources.indexWhere((r) => r.id == movedId);
      if (index != -1) {
        _localResources[index] = updatedResource;
        _localResources.sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
      }

      await _processLocalData();
      await addResources([updatedResource]);
      notifyListeners();
    }
  }

  /// Nests a resource inside another resource.
  Future<void> nestResource(String draggedId, String targetId) async {
    if (!_useLocalDatabase) return;
    if (draggedId == targetId) return;

    final flatList = flatGridData;
    final movedItem = flatList.firstWhereOrNull((item) => item['id'] == draggedId);
    if (movedItem == null) return;

    // Prevent dropping a parent into its own descendants
    bool isDescendantOf(String potentialParentId, String potentialChildId) {
      final child = flatList.firstWhereOrNull((item) => item['id'] == potentialChildId);
      if (child == null) return false;
      String? currentParentId = child['parentId'] as String?;
      while (currentParentId != null) {
        if (currentParentId == potentialParentId) return true;
        final p = flatList.firstWhereOrNull((item) => item['id'] == currentParentId);
        currentParentId = p?['parentId'] as String?;
      }
      return false;
    }

    if (isDescendantOf(draggedId, targetId)) return;

    // Determine final sort order (place at the end of target's children)
    final siblings = _localResources.where((r) => r.parentId == targetId).toList();
    double finalSortOrder = 100.0;
    if (siblings.isNotEmpty) {
      finalSortOrder = siblings.map((s) => s.sortOrder ?? 0.0).reduce(math.max) + 100.0;
    }

    final resource = _localResources.firstWhereOrNull((r) => r.id == draggedId);
    if (resource != null) {
      final updatedResource = resource.copyWith(
        parentId: targetId,
        sortOrder: finalSortOrder,
        lastUpdated: _currentHlc,
      );
      await addResources([updatedResource]);
      await _processLocalData();
      notifyListeners();
    }
  }

  /// Calculates the list of `LegacyGanttRow`s that should be visible based on the
  /// expanded/collapsed state of the parent items in the `gridData`.
  /// This is passed to the `LegacyGanttChartWidget` to determine which rows to render.
  List<LegacyGanttRow> get visibleGanttRows {
    final List<LegacyGanttRow> rows = [];

    void collect(List<GanttGridData> items) {
      for (final item in items) {
        rows.add(LegacyGanttRow(id: item.id));
        if (item.isParent && item.isExpanded) {
          collect(item.children); // Recurse!
        }
      }
    }

    collect(visibleGridData);
    return rows;
  }

  /// Constructor initializes the locale and sets up a listener for horizontal scrolling.
  GanttViewModel({String? initialLocale, bool useLocalDatabase = false, Future<SqliteCrdt>? database})
    : _database = database ?? GanttDb.db {
    controller = LegacyGanttController(
      initialVisibleStartDate: _startDate,
      initialVisibleEndDate: _startDate.add(Duration(days: _range)),
    );
    if (_syncClient != null) {
      controller.setSyncClient(_syncClient!);
    }
    controller.setIsLoading(_isLoading);

    if (initialLocale != null) {
      _selectedLocale = initialLocale;
    }
    _ganttHorizontalScrollController.addListener(_onGanttScroll);

    if (useLocalDatabase) {
      _initialized = setUseLocalDatabase(true);
    } else {
      _initialized = fetchScheduleData();
    }
  }

  /// Adds a new resource as a child of the given parent.
  Future<void> addResource(String parentId, [String? parentName]) async {
    if (!_useLocalDatabase) return;

    // Create a new resource as a child
    final newId = 'res_${DateTime.now().millisecondsSinceEpoch}';
    final newResource = LocalResource(
      id: newId,
      name: 'New Item (under ${parentName ?? parentId})',
      parentId: parentId,
      isExpanded: false,
      sortOrder: (DateTime.now().millisecondsSinceEpoch % 1000000).toDouble(),
    );

    await addResources([newResource]);
    await _processLocalData();
    notifyListeners();
  }

  void setSelectedRowId(String? rowId) {
    // Selection logic handled via _focusedTaskId if we want it synced
    final task = _ganttTasks.firstWhereOrNull((t) => t.rowId == rowId);
    if (task != null) {
      setFocusedTaskId(task.id);
    }
    notifyListeners();
  }

  Future<void> handleCreateTask(String rowId, DateTime time) async {
    if (!_createTasksEnabled) return;
    final endTime = time.add(const Duration(hours: 1));
    final newTask = LegacyGanttTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      rowId: rowId,
      start: time,
      end: endTime,
      name: 'New Task',
    );
    await updateTask(newTask);
  }

  /// Deletes a resource and its associated tasks.
  Future<void> deleteResource(String id) async {
    if (!_useLocalDatabase) return;

    final tasks = _allGanttTasks.where((task) => task.rowId == id).toList();
    await deleteTasksBulk(tasks);
    await _commitOperations([
      Operation(
        type: 'DELETE_RESOURCE',
        data: {'id': id},
        timestamp: _currentHlc,
        actorId: _syncClient?.actorId ?? 'local-user',
      ),
    ]);
    await _processLocalData();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _closePersistence() async {
    try {
      await initialized;
      await _localMutations.synchronized(() async {});
      await _incomingOperationChain;
      if (_syncClient case final OfflineGanttSyncClient client) {
        await client.dispose();
      }
      if (_syncClient case final WebSocketGanttSyncClient client) {
        await client.dispose();
      }
      await _canonicalState?.close();
    } catch (error) {
      debugPrint('Error closing local synchronization: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionAttempt++;
    _syncGeneration++;
    unawaited(_closePersistence());
    _removeTooltip();
    _stateSubscription?.cancel();
    _syncOperationsSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _gridScrollController.removeListener(_syncGridScroll);
    _ganttScrollController.removeListener(_syncGanttScroll);
    _gridScrollController.dispose();
    _ganttScrollController.dispose();
    _ganttHorizontalScrollController.removeListener(_onGanttScroll);
    _ganttHorizontalScrollController.dispose();
    _presenceThrottle?.cancel();
    super.dispose();
  }

  /// Disposes of the view model and its resources asynchronously.
  /// This is preferred over [dispose] when using [OfflineGanttSyncClient], as it
  /// ensures that any active background flush operations are completed before
  /// the method returns.
  Future<void> disposeAsync() async {
    _disposed = true;
    _connectionAttempt++;
    _syncGeneration++;
    await initialized;
    await _localMutations.synchronized(() async {});
    _removeTooltip();
    if (_activeSeedingFuture != null) {
      try {
        await _activeSeedingFuture;
      } catch (e) {
        debugPrint('Error waiting for seeding during dispose: $e');
      }
    }

    await _stateSubscription?.cancel();
    await _syncOperationsSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _incomingOperationChain;
    await _canonicalState?.close();
    if (_syncClient is OfflineGanttSyncClient) {
      await (_syncClient as OfflineGanttSyncClient).dispose();
    } else if (_syncClient is WebSocketGanttSyncClient) {
      await (_syncClient as WebSocketGanttSyncClient).dispose();
    }
    _gridScrollController.removeListener(_broadcastPresence);
    _gridScrollController.dispose();
    _ganttScrollController.dispose();
    _ganttHorizontalScrollController.removeListener(_onGanttScroll);
    _ganttHorizontalScrollController.dispose();
    _presenceThrottle?.cancel();
    super.dispose();
  }

  Map<String, CpmTaskStats> get cpmStats => _cpmStats;

  void setShowCriticalPath(bool value) {
    if (_showCriticalPath == value) return;
    _showCriticalPath = value;
    _calculateCpm();
    notifyListeners();
  }

  /// Attaches the vertical scroll listeners. This should be called after the
  /// widgets using the controllers have been built.
  void attachScrollListeners() {
    if (_areScrollListenersAttached) return;
    _gridScrollController.addListener(_syncGridScroll);
    _ganttScrollController.addListener(_syncGanttScroll);
    _areScrollListenersAttached = true;
  }

  void _syncGanttScroll() {
    if (_isSyncingGanttScroll) return;
    if (!_ganttScrollController.hasClients || !_gridScrollController.hasClients) return;

    _isSyncingGridScroll = true;
    try {
      if (_ganttScrollController.offset != _gridScrollController.offset) {
        _gridScrollController.jumpTo(_ganttScrollController.offset);
      }
    } finally {
      _isSyncingGridScroll = false;
    }
    _broadcastPresence(); // Broadcast vertical scroll change
  }

  void _syncGridScroll() {
    if (_isSyncingGridScroll) return;
    if (!_ganttScrollController.hasClients || !_gridScrollController.hasClients) return;

    _isSyncingGanttScroll = true;
    try {
      if (_gridScrollController.offset != _ganttScrollController.offset) {
        _ganttScrollController.jumpTo(_gridScrollController.offset);
      }
    } finally {
      _isSyncingGanttScroll = false;
    }
    _broadcastPresence(); // Broadcast vertical scroll change
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

  void updateResizeTooltipDateFormat(String Function(DateTime) format) {
    _resizeTooltipDateFormat = format;
    notifyListeners();
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
    _setLoading(true);
    _conflictIndicators = [];
    _dependencies = [];
    _gridData = [];
    _rowMaxStackDepth = {};
    _totalStartDate = null;
    _totalEndDate = null;
    _visibleStartDate = null;
    _visibleEndDate = null;
    _cachedFlatGridData = null;
    _cachedVisibleFlatGridData = null;
    _seedVersion++;
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
          color: null,
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

      _seedVersion++;
      _setLoading(false);
      if (_visibleStartDate == null || _visibleEndDate == null) _setInitialVisibleWindow();

      notifyListeners();

      WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialScroll());
      _syncToController();
    } catch (e) {
      debugPrint('Error fetching schedule data: $e');
      _setLoading(false);
      notifyListeners();
    }
  }

  /// Sets an initial visible window based on data bounds, zooming into a sensible 4-week range.
  void _setInitialVisibleWindow() {
    if (_totalStartDate == null || _totalEndDate == null) {
      final now = DateTime.now();
      _totalStartDate = now.subtract(const Duration(days: 15));
      _totalEndDate = now.add(const Duration(days: 15));
    }

    if (effectiveTotalStartDate != null && effectiveTotalEndDate != null) {
      _visibleStartDate = effectiveTotalStartDate;
      final defaultVisibleEnd = _visibleStartDate!.add(const Duration(days: 28));
      _visibleEndDate = defaultVisibleEnd.isBefore(effectiveTotalEndDate!) ? defaultVisibleEnd : effectiveTotalEndDate;
    }
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
      _initialized = fetchScheduleData();
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
      _initialized = fetchScheduleData();
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
          effectiveTotalEndDate != null) {
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
    if (_isScrubberUpdating ||
        effectiveTotalStartDate == null ||
        effectiveTotalEndDate == null ||
        !_ganttHorizontalScrollController.hasClients) {
      return;
    }

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

        _ganttHorizontalScrollController.jumpTo(
          newScrollOffset.clamp(0.0, _ganttHorizontalScrollController.position.maxScrollExtent),
        );
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
                      decoration: BoxDecoration(color: taskColor, borderRadius: BorderRadius.circular(12)),
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
    List<LegacyGanttTask> tasks,
    Map<String, int> maxDepth,
    List<LegacyGanttTask> conflictIndicators,
  ) {
    _ganttTasks = tasks;
    _conflictIndicators = conflictIndicators;
    _rowMaxStackDepth = maxDepth;
    _syncToController();
    notifyListeners();
  }

  void _syncToController() {
    controller.setTasks(_ganttTasks);
    controller.setDependencies(_presentationDependencies);
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
          final op = Operation(
            type: 'PRESENCE_UPDATE',
            data: {
              'viewportStart': visibleStartDate!.millisecondsSinceEpoch,
              'viewportEnd': visibleEndDate!.millisecondsSinceEpoch,
              'verticalScrollOffset': verticalScroll,
              'userName': _currentUsername ?? 'User ${_syncClient?.hashCode ?? "Me"}',
              'userColor': '#FF0000',
            },
            timestamp: _currentHlc,
            actorId: 'me',
          );
          _syncClient?.sendOperation(op);
          // Don't record presence in audit log to keep it clean, unless debugging
          // controller.recordOperation(op);
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

  bool _isMerkleSyncing = false;

  /// Tracks the number of operations expected during initial server sync.
  /// Set when SYNC_METADATA arrives, reset when all ops have been processed.
  int _initialSyncExpected = 0;
  int _initialSyncReceived = 0;

  /// True when the client is in the middle of receiving initial sync data
  /// from the server. During this window, expensive recomputation
  /// (_processLocalData) is deferred until all batches arrive.
  bool get _isInitialSyncing => _initialSyncExpected > 0 && _initialSyncReceived < _initialSyncExpected;

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
    if (_disposed) return;
    final attempt = ++_connectionAttempt;
    bool isCurrent() => !_disposed && attempt == _connectionAttempt;
    try {
      await initialized;
      if (!isCurrent()) return;
      await _activeSeedingFuture;
      if (!isCurrent()) return;
      final parsedUri = Uri.parse(uri);
      final loginCall = loginFunction ?? WebSocketGanttSyncClient.login;
      final token = await loginCall(uri: parsedUri, username: username, password: password);

      if (!isCurrent()) return;
      await _localMutations.synchronized(() async {
        if (!isCurrent()) return;
        final wsUri = parsedUri.replace(scheme: parsedUri.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
        final scopeUri = Uri(
          scheme: wsUri.scheme,
          host: wsUri.host,
          port: wsUri.hasPort ? wsUri.port : null,
          path: wsUri.path,
        );
        await _bindProtocolScope(jsonEncode([scopeUri.toString(), tenantId]));
        if (!isCurrent()) return;
        _currentUsername = username;
        WebSocketGanttSyncClient? wsClientToConnect;

        if (syncClientFactory != null) {
          final client = syncClientFactory!(uri: wsUri, authToken: token);
          if (client is WebSocketGanttSyncClient) {
            wsClientToConnect = client;
            final offlineClient = PersistedGanttSyncClient(_database, protocolState: () => _protocolState);
            await offlineClient.setInnerClient(client);
            _syncClient = offlineClient;
          } else {
            _syncClient = client;
          }
        } else {
          final wsClient = WebSocketGanttSyncClient(uri: wsUri, authToken: token, userId: username);
          wsClientToConnect = wsClient;

          if (_syncClient is OfflineGanttSyncClient) {
            await (_syncClient as OfflineGanttSyncClient).setInnerClient(wsClient);
          } else {
            if (_syncClient is WebSocketGanttSyncClient) {
              await (_syncClient as WebSocketGanttSyncClient).dispose();
            }
            final offlineClient = PersistedGanttSyncClient(_database, protocolState: () => _protocolState);
            await offlineClient.setInnerClient(wsClient);
            _syncClient = offlineClient;
          }
        }

        if (!isCurrent()) {
          await _disconnectCurrentSync();
          return;
        }
        final generation = _syncGeneration;
        if (_syncClient != null) {
          controller.setSyncClient(_syncClient!);
        }

        _connectionStateSubscription?.cancel();
        _syncOperationsSubscription?.cancel();
        Stream<bool>? connectionStream;
        if (_syncClient is OfflineGanttSyncClient) {
          connectionStream = (_syncClient as OfflineGanttSyncClient).connectionStateStream;
        } else if (_syncClient is WebSocketGanttSyncClient) {
          connectionStream = (_syncClient as WebSocketGanttSyncClient).connectionStateStream;
        }

        if (connectionStream != null) {
          _connectionStateSubscription = connectionStream.listen((isConnected) {
            if (_disposed || generation != _syncGeneration) return;
            if (_isSyncConnected != isConnected) {
              _isSyncConnected = isConnected;
              notifyListeners();
              if (isConnected) {
                _performMerkleSync();
              }
            }
          });
        }

        _syncOperationsSubscription = _syncClient!.operationStream.listen((op) {
          if (_disposed || generation != _syncGeneration) return;
          _incomingOperationChain = _incomingOperationChain
              .then((_) async {
                if (!_disposed && generation == _syncGeneration) await _handleIncomingOperation(op);
              })
              .catchError((e) {
                print('Error processing operation in chain: $e');
              });
        });

        _isSyncConnected = true;
        _broadcastPresence();
        notifyListeners();

        final lastSyncedHlc = await _localRepository.getLastServerSyncTimestamp();
        if (!isCurrent()) {
          await _disconnectCurrentSync();
          return;
        }
        print('Connecting with lastSyncedHlc: $lastSyncedHlc');
        wsClientToConnect?.connect(tenantId, lastSyncedTimestamp: lastSyncedHlc);

        notifyListeners();
      });
    } catch (e) {
      if (!isCurrent()) return;
      print('Connection failed: $e');
      _isSyncConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _performMerkleSync() async {
    if (_syncClient == null) return;
    final generation = _syncGeneration;
    final client = _syncClient!;
    final state = _protocolState;
    print('Initiating Merkle Sync...');

    // We compute the local tree based on the currently loaded data
    // OR we could force a fresh fetch from DB if needed, but watch streams keep this up-to-date.
    try {
      final localTree = await state.computeMerkleTree();
      if (generation != _syncGeneration) return;

      print('Local Merkle Root is ${localTree.root.hash}');

      _isMerkleSyncing = true;

      try {
        await client.syncWithMerkle(localTree: localTree);
      } finally {
        if (generation == _syncGeneration) {
          await finalizeMerkleSync();
          _isMerkleSyncing = false;
        }
      }
    } catch (e) {
      print('Failed to perform Merkle Sync: $e');
      if (generation == _syncGeneration) _isMerkleSyncing = false;
    }
  }

  Future<void> finalizeMerkleSync() async {
    _acceptSnapshot(await _protocolState.readState(), force: true);
  }

  Future<void> disconnectSync() {
    _connectionAttempt++;
    _syncGeneration++;
    _isMerkleSyncing = false;
    return _localMutations.synchronized(_disconnectCurrentSync);
  }

  Future<void> _disconnectCurrentSync() async {
    await _syncOperationsSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _incomingOperationChain;

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
    _initialSyncExpected = 0;
    _initialSyncReceived = 0;
    notifyListeners();
  }

  Future<void> handleIncomingOperationForTesting(Operation op) => _handleIncomingOperation(op);

  Future<void> _handleIncomingOperation(Operation op) async {
    if (op.type == 'SYNC_METADATA') {
      _initialSyncExpected = (op.data['totalOperations'] as num?)?.toInt() ?? 0;
      _initialSyncReceived = 0;
      return;
    }
    if (op.type == 'PRESENCE_UPDATE') {
      final data = op.data;
      _connectedUsers[op.actorId] = RemoteGhost(
        userId: op.actorId,
        lastUpdated: DateTime.now(),
        viewportStart: data['viewportStart'] is num
            ? DateTime.fromMillisecondsSinceEpoch((data['viewportStart'] as num).toInt())
            : null,
        viewportEnd: data['viewportEnd'] is num
            ? DateTime.fromMillisecondsSinceEpoch((data['viewportEnd'] as num).toInt())
            : null,
        verticalScrollOffset: (data['verticalScrollOffset'] as num?)?.toDouble(),
        userName: data['userName'] as String?,
        userColor: data['userColor'] as String?,
      );
      if (followedUserId == op.actorId) _applyFollowedUserView(_connectedUsers[op.actorId]!);
      notifyListeners();
      return;
    }
    if (!const {
      'BATCH_UPDATE',
      'RESET_DATA',
      'INSERT_TASK',
      'UPDATE_TASK',
      'DELETE_TASK',
      'INSERT_RESOURCE',
      'UPDATE_RESOURCE',
      'DELETE_RESOURCE',
      'INSERT_DEPENDENCY',
      'UPDATE_DEPENDENCY',
      'DELETE_DEPENDENCY',
    }.contains(op.type)) {
      return;
    }
    if (op.type == 'BATCH_UPDATE') _initialSyncReceived += (op.data['operations'] as List? ?? []).length;
    final commit = await _protocolState.applyOperations([op]);
    if (commit.acceptedReset != null) {
      _initialSyncExpected = 0;
      _initialSyncReceived = 0;
      _pendingSeedReset = true;
    }
    _acceptSnapshot(commit.state, force: commit.acceptedReset != null);
    if (op.type == 'BATCH_UPDATE') await _localRepository.setLastServerSyncTimestamp(op.timestamp);
    if (!_isInitialSyncing) {
      _initialSyncExpected = 0;
      _initialSyncReceived = 0;
    }
  }

  /// A callback from the Gantt chart widget when a task has been moved or resized by the user.
  /// It updates the task in the local list and then recalculates the stacking for all tasks.
  Future<void> handleTaskUpdate(LegacyGanttTask task, DateTime newStart, DateTime newEnd) async {
    if (_useLocalDatabase) {
      await updateTask(task.copyWith(start: newStart, end: newEnd));
      return;
    } else if (_apiResponse != null) {
      final parentResource = _apiResponse?.resourcesData.firstWhereOrNull(
        (r) => r.children.any((c) => c.id == task.rowId),
      );
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
          final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
            _allGanttTasks,
            _apiResponse!,
            showConflicts: _showConflicts,
          );
          _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
        }
      }
    }
    if (_syncClient != null) {
      await _commitOperations([
        _taskOperation(
          task.copyWith(start: newStart, end: newEnd),
          type: 'UPDATE_TASK',
          previous: task,
        ),
      ]);
    }
  }

  Future<void> handleTaskMove(LegacyGanttTask task, DateTime newStart, DateTime newEnd, String newRowId) async {
    if (_useLocalDatabase) {
      await updateTask(task.copyWith(start: newStart, end: newEnd, rowId: newRowId));
      return;
    }

    if (!_useLocalDatabase) {
      final index = _allGanttTasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _allGanttTasks[index] = _allGanttTasks[index].copyWith(start: newStart, end: newEnd, rowId: newRowId);

        if (_apiResponse != null) {
          final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
            _allGanttTasks,
            _apiResponse!,
            showConflicts: _showConflicts,
          );
          _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
        }
      }
    }
    if (_syncClient != null) {
      await _commitOperations([
        _taskOperation(
          task.copyWith(start: newStart, end: newEnd, rowId: newRowId),
          type: 'UPDATE_TASK',
          previous: task,
        ),
      ]);
    }
  }

  void handleTaskTap(String taskId) {
    setFocusedTaskId(taskId);
  }

  void handleTaskDoubleTap(String taskId) {
    // Navigate or show dialog - handled by UI via listeners if needed
  }

  void handleEmptySpaceTap(String rowId, DateTime time) {
    if (_createTasksEnabled) {
      final newTask = LegacyGanttTask(
        id: 'new_${DateTime.now().millisecondsSinceEpoch}',
        rowId: rowId,
        name: 'New Task',
        start: time,
        end: time.add(const Duration(hours: 4)),
      );

      if (_useLocalDatabase) {
        unawaited(addTask(newTask));
        return;
      }

      if (_syncClient != null) {
        unawaited(_commitOperations([_taskOperation(newTask)]));
      }
      _allGanttTasks.add(newTask);
      _recalculateStackingAndNotify();
    }
  }

  void handleDependencyCreated(LegacyGanttTaskDependency dependency) {
    if (_dependencyCreationEnabled) {
      if (_useLocalDatabase) {
        unawaited(addDependencies([dependency]));
        return;
      }
      _dependencies.add(dependency);
      if (_syncClient != null) {
        unawaited(_commitOperations([_dependencyOperation(dependency)]));
      }
      _recalculateStackingAndNotify();
    }
  }

  Future<void> handleDependenciesSynced(List<LegacyGanttTaskDependency> dependencies) async {
    if (dependencies.isEmpty) return;
    if (_useLocalDatabase) {
      await addDependencies(dependencies);
      return;
    }
    _dependencies.addAll(dependencies);
    if (_syncClient != null) {
      await _commitOperations(dependencies.map(_dependencyOperation).toList());
    }
    _recalculateStackingAndNotify();
  }

  Future<void> handleBatchTaskUpdate(List<(LegacyGanttTask, DateTime, DateTime)> updates) async {
    debugPrint(
      '${DateTime.now().toIso8601String()} GanttViewModel: handleBatchTaskUpdate received ${updates.length} updates',
    );
    final now = _currentHlc;
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
        final parentResource = _apiResponse?.resourcesData.firstWhereOrNull(
          (r) => r.children.any((c) => c.id == task.rowId),
        );
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
      final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
        _allGanttTasks,
        _apiResponse!,
        showConflicts: _showConflicts,
      );
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth, newConflictIndicators);
    }

    if (_useLocalDatabase && dbUpdates.isNotEmpty) {
      await updateTasksBulk(dbUpdates);
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
      color: null, // Default color
      isSummary: false,
      usesWorkCalendar: _enableWorkCalendar,
    );

    await _createTask(newTask);
  }

  /// Helper method to add a new task, handle persistence, and update UI.
  Future<void> _createTask(LegacyGanttTask newTask) async {
    if (_useLocalDatabase) {
      await addTask(newTask);
      return;
    }
    _allGanttTasks.add(newTask);
    _recalculateStackingAndNotify();
    if (_syncClient != null) {
      await _commitOperations([_taskOperation(newTask)]);
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
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
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

      if (_useLocalDatabase) {
        await addResources([LocalResource(id: newResourceId, name: newContactName)]);
        return;
      }

      final newResource = GanttResourceData(
        id: newResourceId,
        name: newContactName,
        taskName: 'Summary for $newContactName', // Ensure taskName is set
        children: [],
      );
      final newGridItem = GanttGridData(
        id: newResourceId,
        name: newContactName,
        isParent: true,
        isExpanded: true,
        children: [],
      );

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

      if (_useLocalDatabase) {
        await addResources([LocalResource(id: newJobId, name: newLineItemName, parentId: parentId)]);
        return;
      }

      final newJob = GanttJobData(
        id: newJobId,
        name: newLineItemName,
        taskName: null,
        status: 'New',
        taskColor: '9E9E9E',
        completion: 0.0,
      );
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

    final previousTasks = List<LegacyGanttTask>.of(_ganttTasks);
    final previousDependencies = List<LegacyGanttTaskDependency>.of(_dependencies);
    List<LegacyGanttTask> nextTasks = _ganttTasks;
    List<LegacyGanttTaskDependency> nextDependencies = _dependencies;

    final parentTaskIndex = nextTasks.indexWhere((t) => t.rowId == parentId && !t.isTimeRangeHighlight);

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

      final summaryTask = nextTasks.firstWhereOrNull((task) => task.rowId == parentId && task.isSummary);
      final parentItem = _gridData.firstWhereOrNull((item) => item.id == parentId);
      final childRows = parentItem?.children.map((child) => child.id).toSet() ?? <String>{};
      final childTask = nextTasks.firstWhereOrNull(
        (task) =>
            childRows.contains(task.rowId) && !task.isSummary && !task.isTimeRangeHighlight && !task.isOverlapIndicator,
      );
      if (summaryTask != null &&
          childTask != null &&
          !nextDependencies.any(
            (dependency) =>
                dependency.predecessorTaskId == summaryTask.id &&
                dependency.successorTaskId == childTask.id &&
                dependency.type == DependencyType.contained,
          )) {
        nextDependencies = [
          ...nextDependencies,
          LegacyGanttTaskDependency(
            predecessorTaskId: summaryTask.id,
            successorTaskId: childTask.id,
            type: DependencyType.contained,
          ),
        ];
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
      final summaryIds = {parentId, ...previousTasks.where((task) => task.rowId == parentId).map((task) => task.id)};
      nextDependencies = nextDependencies
          .where((d) => !(summaryIds.contains(d.predecessorTaskId) && d.type == DependencyType.contained))
          .toList();
    }

    if (_useLocalDatabase || _syncClient != null) {
      final nextIds = nextTasks.map((task) => task.id).toSet();
      final operations = <Operation>[
        for (final task in nextTasks.where(
          (task) => task.rowId == parentId && !task.isTimeRangeHighlight && !task.isOverlapIndicator,
        ))
          _taskOperation(task, previous: previousTasks.where((previous) => previous.id == task.id).firstOrNull),
        for (final task in previousTasks.where((task) => task.rowId == parentId && !nextIds.contains(task.id)))
          Operation(
            type: 'DELETE_TASK',
            data: {'id': task.id},
            timestamp: _currentHlc,
            actorId: _syncClient?.actorId ?? 'local-user',
          ),
        for (final dependency in nextDependencies.where((dependency) => !previousDependencies.contains(dependency)))
          _dependencyOperation(dependency),
        for (final dependency in previousDependencies.where((dependency) => !nextDependencies.contains(dependency)))
          _deleteDependencyOperation(dependency),
      ];
      unawaited(_commitOperations(operations));
    }

    final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
      nextTasks,
      _apiResponse!,
      showConflicts: _showConflicts,
    );
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
  void toggleExpansion(String id, [bool? isExpanded]) {
    GanttGridData? findItem(List<GanttGridData> items) {
      final stack = [...items];
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (current.id == id) return current;
        if (current.children.isNotEmpty) {
          stack.addAll(current.children);
        }
      }
      return null;
    }

    final item = findItem(_gridData);
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
        item.isExpanded = isExpanded ?? !item.isExpanded;
        _cachedFlatGridData = null; // Invalidate
        _cachedVisibleFlatGridData = null; // Invalidate
        _persistExpansion(item);
        _recalculateStackingAndNotify();
        return;
      }
    }

    item.isExpanded = isExpanded ?? !item.isExpanded;
    _cachedFlatGridData = null; // Invalidate
    _cachedVisibleFlatGridData = null; // Invalidate

    _persistExpansion(item);

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
  void _persistExpansion(GanttGridData item) {
    final resource = _localResources.firstWhereOrNull((resource) => resource.id == item.id);
    if (resource != null && (_useLocalDatabase || _syncClient != null)) {
      unawaited(_commitOperations([_resourceOperation(resource.copyWith(isExpanded: item.isExpanded))]));
    }
  }

  void _recalculateStackingAndNotify() {
    final response =
        _apiResponse ??
        GanttResponse(
          success: true,
          resourcesData: [],
          eventsData: [],
          assignmentsData: [],
          dependenciesData: [],
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
    unawaited(_createTask(newTask));
  }

  /// Handles the "Delete Task" action from the context menu.

  void handleDeleteTask(LegacyGanttTask task) {
    if (_apiResponse == null) return;
    final operations = <Operation>[
      for (final dependency in getDependenciesForTask(task)) _deleteDependencyOperation(dependency),
      Operation(
        type: 'DELETE_TASK',
        data: {'id': task.id},
        timestamp: _currentHlc,
        actorId: _syncClient?.actorId ?? 'local-user',
      ),
    ];
    final remainingTasksInRow = _allGanttTasks.where((other) => other.rowId == task.rowId && other.id != task.id);
    if (remainingTasksInRow.isEmpty && !_showEmptyParentRows) {
      operations.add(
        Operation(
          type: 'DELETE_RESOURCE',
          data: {'id': task.rowId},
          timestamp: _currentHlc,
          actorId: _syncClient?.actorId ?? 'local-user',
        ),
      );
    }
    if (_useLocalDatabase) {
      _allGanttTasks.removeWhere((other) => other.id == task.id);
      _dependencies.removeWhere(
        (dependency) => dependency.predecessorTaskId == task.id || dependency.successorTaskId == task.id,
      );
      _recalculateStackingAndNotify();
      unawaited(_commitOperations(operations));
      return;
    }
    final remaining = _ganttTasks.where((other) => other.id != task.id).toList();
    _dependencies.removeWhere(
      (dependency) => dependency.predecessorTaskId == task.id || dependency.successorTaskId == task.id,
    );
    final (tasks, depth, conflicts) = _scheduleService.publicCalculateTaskStacking(
      remaining,
      _apiResponse!,
      showConflicts: _showConflicts,
    );
    _updateTasksAndStacking(tasks, depth, conflicts);
    if (_syncClient != null) {
      unawaited(_commitOperations(operations));
    }
  }

  /// Shows a dialog to edit all parent summary tasks at once.

  Future<void> editAllParentTasks(BuildContext context) async {
    final parentRowIds = _gridData.where((g) => g.isParent).map((g) => g.id).toSet();
    final parentSummaryTasks = _ganttTasks
        .where((t) => t.isSummary && parentRowIds.contains(t.rowId) && !t.isOverlapIndicator)
        .toList();

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
        lastUpdated: _currentHlc,
      );
      await _updateMultipleTasks([updatedTask]);
    }
  }

  /// Updates multiple tasks at once and recalculates stacking.
  Future<void> _updateMultipleTasks(List<LegacyGanttTask> updatedTasks) async {
    if (_useLocalDatabase) {
      await updateTasksBulk(updatedTasks);
      return;
    }
    if (_apiResponse == null) return;

    final newTasks = List<LegacyGanttTask>.from(_allGanttTasks);
    for (final updatedTask in updatedTasks) {
      final index = newTasks.indexWhere((t) => t.id == updatedTask.id);
      if (index != -1) {
        final originalTask = newTasks[index];

        newTasks[index] = originalTask.copyWith(
          name: updatedTask.name,
          start: updatedTask.start,
          end: updatedTask.end,
          completion: updatedTask.completion,
          lastUpdated: updatedTask.lastUpdated,
        );
        final parentResource = _apiResponse?.resourcesData.firstWhereOrNull(
          (r) => r.children.any((c) => c.id == originalTask.rowId),
        );
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
    print('DEBUG: deleteRow called for $rowId');
    if (_apiResponse == null) {
      print('DEBUG: apiResponse is null');
      return;
    }

    // Helper to recursively collect all descendant IDs
    void collectIds(GanttGridData node, Set<String> ids) {
      ids.add(node.id);
      for (final child in node.children) {
        collectIds(child, ids);
      }
    }

    // Helper to find node
    GanttGridData? findNode(List<GanttGridData> nodes, String id) {
      for (final node in nodes) {
        if (node.id == id) return node;
        final found = findNode(node.children, id);
        if (found != null) return found;
      }
      return null;
    }

    final resourcesToDelete = <String>{};
    final nodeToDelete = findNode(_gridData, rowId);

    if (nodeToDelete != null) {
      print('DEBUG: Found node $_gridData');
      collectIds(nodeToDelete, resourcesToDelete);
    } else {
      print('DEBUG: Row $rowId not found in gridData');
      return;
    }

    print('DEBUG: Deleting ${resourcesToDelete.length} resources');

    final tasksToDelete = _allGanttTasks.where((t) => resourcesToDelete.contains(t.rowId)).toList();
    final taskIds = tasksToDelete.map((task) => task.id).toSet();
    final operations = <Operation>[
      for (final dependency in _dependencies.where(
        (dependency) => taskIds.contains(dependency.predecessorTaskId) || taskIds.contains(dependency.successorTaskId),
      ))
        _deleteDependencyOperation(dependency),
      for (final task in tasksToDelete)
        Operation(
          type: 'DELETE_TASK',
          data: {'id': task.id},
          timestamp: _currentHlc,
          actorId: _syncClient?.actorId ?? 'local-user',
        ),
      for (final id in resourcesToDelete)
        Operation(
          type: 'DELETE_RESOURCE',
          data: {'id': id},
          timestamp: _currentHlc,
          actorId: _syncClient?.actorId ?? 'local-user',
        ),
    ];
    if (_useLocalDatabase || _syncClient != null) {
      unawaited(_commitOperations(operations));
    }

    if (!_useLocalDatabase) {
      final nextTasks = _allGanttTasks.where((task) => !tasksToDelete.contains(task)).toList();

      // Recursive remove from in-memory grid
      bool removeNode(List<GanttGridData> nodes, String id) {
        final index = nodes.indexWhere((n) => n.id == id);
        if (index != -1) {
          nodes.removeAt(index);
          return true;
        }
        for (final node in nodes) {
          if (removeNode(node.children, id)) return true;
        }
        return false;
      }

      removeNode(_gridData, rowId);

      // Also remove from apiResponse (if simplified structure)
      _apiResponse?.resourcesData.removeWhere((r) => r.id == rowId || resourcesToDelete.contains(r.id));
      // Deep removal in apiResponse is harder but for local/demo mode usually shallow or 2-level.
      _cachedFlatGridData = null;

      final (recalculatedTasks, newMaxDepth, newConflictIndicators) = _scheduleService.publicCalculateTaskStacking(
        nextTasks,
        _apiResponse!,
        showConflicts: _showConflicts,
      );
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
    _cachedVisibleFlatGridData = null;
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
    _seedVersion++;
    notifyListeners();
  }

  /// Returns a list of tasks that are valid targets for a dependency relationship
  /// with the `sourceTask`. In this example, it restricts targets to tasks
  /// under the same parent resource.
  /// Returns a list of tasks that can be selected as a predecessor or successor.
  List<LegacyGanttTask> getValidDependencyTasks(LegacyGanttTask sourceTask) {
    final sourceParentId = _getParentId(sourceTask.rowId);
    if (sourceParentId == null) return [];

    final parentGridItem = _gridData.firstWhere(
      (g) => g.id == sourceParentId,
      orElse: () => GanttGridData(id: '', name: '', isParent: false, children: []),
    );
    if (parentGridItem.id.isEmpty) return [];

    final allRowIdsForParent = <String>{parentGridItem.id, ...parentGridItem.children.map((c) => c.id)};

    return ganttTasks
        .where(
          (task) =>
              !task.isSummary &&
              !task.isTimeRangeHighlight &&
              !task.isOverlapIndicator &&
              task.id != sourceTask.id &&
              allRowIdsForParent.contains(task.rowId),
        )
        .toList();
  }

  /// Adds a new dependency object directly.
  void addDependencyObject(LegacyGanttTaskDependency newDependency) {
    if (_dependencies.any(
      (dependency) =>
          dependency.predecessorTaskId == newDependency.predecessorTaskId &&
          dependency.successorTaskId == newDependency.successorTaskId,
    )) {
      return;
    }
    if (_useLocalDatabase) {
      unawaited(addDependencies([newDependency]));
    } else {
      _dependencies = [..._dependencies, newDependency];
      notifyListeners();
      if (_syncClient != null) {
        unawaited(_commitOperations([_dependencyOperation(newDependency)]));
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
    if (!_dependencies.any(
      (other) =>
          other.predecessorTaskId == dependency.predecessorTaskId &&
          other.successorTaskId == dependency.successorTaskId,
    )) {
      return;
    }
    if (_useLocalDatabase || _syncClient != null) {
      unawaited(_commitOperations([_deleteDependencyOperation(dependency)]));
    }
    if (!_useLocalDatabase) {
      _dependencies.removeWhere(
        (other) =>
            other.predecessorTaskId == dependency.predecessorTaskId &&
            other.successorTaskId == dependency.successorTaskId,
      );
      notifyListeners();
    }
  }

  Operation _deleteDependencyOperation(LegacyGanttTaskDependency dependency) => Operation(
    type: 'DELETE_DEPENDENCY',
    data: {'predecessorTaskId': dependency.predecessorTaskId, 'successorTaskId': dependency.successorTaskId},
    timestamp: _currentHlc,
    actorId: _syncClient?.actorId ?? 'local-user',
  );

  /// Removes all dependencies associated with a given task.

  void clearDependenciesForTask(LegacyGanttTask task) {
    final dependencies = getDependenciesForTask(task);
    if (_useLocalDatabase || _syncClient != null) {
      unawaited(_commitOperations(dependencies.map(_deleteDependencyOperation).toList()));
    }
    if (!_useLocalDatabase) {
      _dependencies.removeWhere(
        (dependency) => dependency.predecessorTaskId == task.id || dependency.successorTaskId == task.id,
      );
      notifyListeners();
    }
  }

  PresenceGanttSyncClient? _presenceClient;
  GanttSyncClient? get presenceSyncClient {
    final client = _syncClient;
    if (client == null) return null;
    if (_presenceClient?.inner != client) _presenceClient = PresenceGanttSyncClient(client);
    return _presenceClient;
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
      await _syncClient!.sendOperation(
        Operation(
          type: 'OPTIMIZE_SCHEDULE',
          data: {}, // No payload needed, server fetches tasks
          timestamp: _currentHlc,
          actorId: 'local-user',
        ),
      );
    }
  }

  DateTime? parseDate(dynamic value) {
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

    final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate));

    if (pickedTime == null) return;

    setState(() {
      final newDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
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
              child: Text(DateFormat.yMd().add_jm().format(_startDate)),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('End:'),
            TextButton(
              onPressed: () => _selectDateTime(context, false),
              child: Text(DateFormat.yMd().add_jm().format(_endDate)),
            ),
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
      final newDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
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
          DataColumn(
            label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          DataColumn(
            label: Text('Start', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true,
          ),
          DataColumn(
            label: Text('End', style: TextStyle(fontWeight: FontWeight.bold)),
            numeric: true,
          ),
        ],
        rows: _tasks
            .map(
              (task) => DataRow(
                cells: [
                  DataCell(
                    Text(task.name ?? 'Unnamed Task', overflow: TextOverflow.ellipsis),
                    onTap: () => _editName(task),
                  ),
                  DataCell(Text(DateFormat.yMd().add_jm().format(task.start)), onTap: () => _editDate(task, true)),
                  DataCell(Text(DateFormat.yMd().add_jm().format(task.end)), onTap: () => _editDate(task, false)),
                ],
              ),
            )
            .toList(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _tasks), child: const Text('Save')),
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
    content: TextField(controller: _controller, autofocus: true, onSubmitted: (_) => _save()),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
