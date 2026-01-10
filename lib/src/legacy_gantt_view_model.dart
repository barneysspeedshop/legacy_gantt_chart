import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'models/legacy_gantt_dependency.dart';
import 'models/legacy_gantt_row.dart';
import 'models/legacy_gantt_task.dart';
import 'models/remote_cursor.dart';
import 'models/remote_ghost.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

import 'legacy_gantt_controller.dart';
import 'models/work_calendar.dart';
import 'utils/legacy_gantt_conflict_detector.dart';
import 'utils/critical_path_calculator.dart';
import 'package:legacy_gantt_chart/src/models/resource_bucket.dart';
import 'package:legacy_gantt_chart/src/utils/resource_load_aggregator.dart';
import 'sync/websocket_gantt_sync_client.dart';
import 'models/dependency_drag_status.dart';

enum DragMode { none, move, resizeStart, resizeEnd }

enum PanType { none, vertical, horizontal, selection, draw, dependency }

enum TaskPart { body, startHandle, endHandle }

/// A [ChangeNotifier] that manages the state and interaction logic for the
/// [LegacyGanttChartWidget].
///
/// This is an internal class that translates user gestures (pans, taps, hovers)
/// into state changes, such as dragging tasks, resizing them, or scrolling the
/// view. It calculates the necessary scales and positions for rendering the
/// chart elements and notifies its listeners when the state changes, causing the
/// UI to rebuild.
class LegacyGanttViewModel extends ChangeNotifier {
  /// The raw list of all tasks to be displayed.
  /// If [syncClient] is provided, this list is mutable and managed by the [CRDTEngine].
  List<LegacyGanttTask> _tasks;

  /// The public getter for the task list.
  List<LegacyGanttTask> get data => _tasks;

  Map<String, List<LegacyGanttTask>> _tasksByRow = {};
  Map<String, List<LegacyGanttTask>> get tasksByRow => _tasksByRow;

  /// The list of conflict indicators to be displayed.
  List<LegacyGanttTask> conflictIndicators;

  /// The list of dependencies between tasks.
  List<LegacyGanttTaskDependency> dependencies;

  /// The list of rows currently visible in the viewport.
  List<LegacyGanttRow> visibleRows;

  /// A map defining the maximum number of overlapping tasks for each row.
  Map<String, int> rowMaxStackDepth;

  /// The height of a single task lane.
  final double rowHeight;

  /// The height of the time axis header.
  double? _axisHeight;

  /// The public getter for the axis height.
  double? get axisHeight => _axisHeight;

  /// Updates the axis height and notifies listeners.
  void updateAxisHeight(double? newHeight) {
    if (_axisHeight != newHeight) {
      if (isDisposed) return;
      _axisHeight = newHeight;
      notifyListeners();
    }
  }

  /// The start of the visible time range in milliseconds since epoch.
  double? _gridMin;

  /// Public getter for the grid start.
  double? get gridMin => _gridMin;

  /// The end of the visible time range in milliseconds since epoch.
  double? _gridMax;

  /// Public getter for the grid end.
  double? get gridMax => _gridMax;

  /// The start of the total time range in milliseconds since epoch.
  double? _totalGridMin;

  /// Public getter for the total grid start.
  double? get totalGridMin => _totalGridMin;

  /// The end of the total time range in milliseconds since epoch.
  double? _totalGridMax;

  /// Public getter for the total grid end.
  double? get totalGridMax => _totalGridMax;

  set gridMin(double? value) {
    if (_gridMin != value) {
      _gridMin = value;
      _calculateDomains();
      notifyListeners();
    }
  }

  set gridMax(double? value) {
    if (_gridMax != value) {
      _gridMax = value;
      _calculateDomains();
      notifyListeners();
    }
  }

  set totalGridMin(double? value) {
    updateTotalGridRange(value, _totalGridMax);
  }

  set totalGridMax(double? value) {
    updateTotalGridRange(_totalGridMin, value);
  }

  /// Whether tasks can be moved by dragging.
  final bool enableDragAndDrop;

  /// Whether tasks can be resized from their start or end handles.
  final bool enableResize;

  /// Whether auto-scheduling is enabled globally.
  bool enableAutoScheduling;

  /// A callback invoked when a task is successfully moved or resized.
  final Function(LegacyGanttTask task, DateTime newStart, DateTime newEnd)? onTaskUpdate;

  /// A callback invoked when a task is double-tapped.
  final Function(LegacyGanttTask task)? onTaskDoubleClick;

  /// A callback invoked when a task is deleted.
  final Function(LegacyGanttTask task)? onTaskDelete;

  /// A callback invoked when a task is tapped.
  final Function(LegacyGanttTask)? onPressTask;

  /// An external scroll controller to sync vertical scrolling with another widget (e.g., a data grid).
  final ScrollController? scrollController;

  /// An external scroll controller to sync horizontal scrolling.
  final ScrollController? ganttHorizontalScrollController;

  /// A callback invoked when an empty space on the chart is clicked.
  final Function(String rowId, DateTime time)? onEmptySpaceClick;

  /// A callback invoked when a batch of tasks are updated (e.g. via drag and drop of a summary task).
  /// If provided, this is called INSTEAD OF [onTaskUpdate] for batch operations.
  Function(List<(LegacyGanttTask, DateTime, DateTime)>)? onBulkTaskUpdate;

  /// A callback invoked when a user completes a draw action for a new task.
  final Function(DateTime start, DateTime end, String rowId)? onTaskDrawEnd;

  /// A function to format the date/time shown in the resize/drag tooltip.
  String Function(DateTime)? resizeTooltipDateFormat;

  /// A builder for creating a completely custom task bar widget.
  final Widget Function(LegacyGanttTask task)? taskBarBuilder;

  /// A callback for when the mouse hovers over a task or empty space.
  Function(LegacyGanttTask?, Offset globalPosition)? onTaskHover;

  /// A callback invoked when a task is secondary tapped.
  Function(LegacyGanttTask task, Offset globalPosition)? onTaskSecondaryTap;

  /// A callback invoked when a task is long pressed.
  Function(LegacyGanttTask task, Offset globalPosition)? onTaskLongPress;

  /// A callback invoked when an action (like focusing a task) requires a row to become visible.
  final Function(String rowId)? onRowRequestVisible;

  /// The ID of the task that should initially have focus.
  final String? initialFocusedTaskId;

  /// A callback invoked when the focused task changes.
  final Function(String? taskId)? onFocusChange;

  /// The width of the resize handles at the start and end of a task bar.
  final double resizeHandleWidth;

  /// The timezone abbreviation for the project (e.g., "EST", "UTC").
  String? projectTimezoneAbbreviation;

  /// The offset of the project timezone from UTC.
  Duration? projectTimezoneOffset;

  /// The synchronization client for multiplayer features.
  final GanttSyncClient? syncClient;

  /// The CRDT engine for merging operations.
  final CRDTEngine _crdtEngine = CRDTEngine();

  /// A function to group tasks for conflict detection.
  /// If provided, conflict detection will be run when tasks are updated via sync.
  final Object? Function(LegacyGanttTask task)? taskGrouper;

  /// Whether to roll up milestones to summary tasks.
  bool _rollUpMilestones;
  bool get rollUpMilestones => _rollUpMilestones;
  set rollUpMilestones(bool value) {
    if (_rollUpMilestones != value) {
      _rollUpMilestones = value;
      notifyListeners();
    }
  }

  /// Whether to show the slack (float) for each task.
  bool _showSlack;
  bool get showSlack => _showSlack;
  set showSlack(bool value) {
    if (_showSlack != value) {
      _showSlack = value;
      _recalculateCriticalPath();
      notifyListeners();
    }
  }

  WorkCalendar? _workCalendar;
  WorkCalendar? get workCalendar => _workCalendar;
  set workCalendar(WorkCalendar? value) {
    if (_workCalendar != value) {
      _workCalendar = value;
      notifyListeners();
    }
  }

  StreamSubscription<Operation>? _syncSubscription;

  final Map<String, RemoteCursor> _remoteCursors = {};

  /// A map of active remote cursors, keyed by user ID.
  Map<String, RemoteCursor> get remoteCursors => Map.unmodifiable(_remoteCursors);

  bool _showRemoteCursors = true;
  bool get showRemoteCursors => _showRemoteCursors;
  set showRemoteCursors(bool value) {
    if (_showRemoteCursors != value) {
      if (isDisposed) return;
      _showRemoteCursors = value;
      notifyListeners();
    }
  }

  final Map<String, RemoteGhost> _remoteGhosts = {};

  /// A map of active remote ghosts (drag previews), keyed by user ID.
  Map<String, RemoteGhost> get remoteGhosts => Map.unmodifiable(_remoteGhosts);

  Timer? _ghostUpdateThrottle;
  static const Duration _ghostThrottleDuration = Duration(milliseconds: 50);

  Hlc get _currentTimestamp {
    if (syncClient != null && syncClient is WebSocketGanttSyncClient) {
      return (syncClient as WebSocketGanttSyncClient).currentHlc;
    }
    return Hlc(millis: DateTime.now().millisecondsSinceEpoch, counter: 0, nodeId: 'local-vm');
  }

  void _sendGhostUpdate(String taskId, DateTime start, DateTime end) {
    if (syncClient == null) return;
    if (_ghostUpdateThrottle?.isActive ?? false) return;

    final Map<String, dynamic> payload = {};

    payload['taskId'] = taskId;
    payload['start'] = start.millisecondsSinceEpoch;
    payload['end'] = end.millisecondsSinceEpoch;

    if (_bulkGhostTasks.isNotEmpty) {
      payload['ghosts'] = _bulkGhostTasks.entries
          .map((e) => {
                'taskId': e.key,
                'start': e.value.$1.millisecondsSinceEpoch,
                'end': e.value.$2.millisecondsSinceEpoch,
              })
          .toList();
    }

    _ghostUpdateThrottle = Timer(_ghostThrottleDuration, () {
      syncClient!.sendOperation(Operation(
        type: 'GHOST_UPDATE',
        data: payload,
        timestamp: _currentTimestamp,
        actorId: 'me',
      ));
    });
  }

  void _clearGhostUpdate(String taskId) {
    _ghostUpdateThrottle?.cancel();
    if (syncClient != null) {
      syncClient!.sendOperation(Operation(
        type: 'GHOST_UPDATE',
        data: {
          'taskId': taskId,
          'start': null,
          'end': null,
        },
        timestamp: _currentTimestamp,
        actorId: 'me',
      ));
    }
  }

  void _handleRemoteGhostUpdate(Map<String, dynamic> data, String actorId) {
    final actualData = data.containsKey('data') && data['data'] is Map ? data['data'] : data;

    final taskId = actualData['taskId'] as String?;
    final start = _parseDate(actualData['start']);
    final end = _parseDate(actualData['end']);

    final Map<String, ({DateTime start, DateTime end})> tasks = {};
    if (actualData.containsKey('ghosts') && actualData['ghosts'] is List) {
      for (final item in actualData['ghosts']) {
        if (item is Map) {
          final tId = item['taskId'] as String?;
          final s = _parseDate(item['start']);
          final e = _parseDate(item['end']);
          if (tId != null && s != null && e != null) {
            tasks[tId] = (start: s, end: e);
          }
        }
      }
    }

    if (taskId != null && start != null && end != null) {
      if (!tasks.containsKey(taskId)) {
        tasks[taskId] = (start: start, end: end);
      }
    }

    if (tasks.isNotEmpty) {
      final existing = _remoteGhosts[actorId];
      _remoteGhosts[actorId] = RemoteGhost(
        userId: actorId,
        taskId: taskId ?? tasks.keys.first, // Keep generic reference
        start: tasks.values.first.start,
        end: tasks.values.first.end,
        lastUpdated: DateTime.now(),
        viewportStart: existing?.viewportStart,
        viewportEnd: existing?.viewportEnd,
        verticalScrollOffset: existing?.verticalScrollOffset,
        userName: existing?.userName,
        userColor: existing?.userColor,
        tasks: tasks,
      );
    } else {
      if (_remoteGhosts.containsKey(actorId)) {
        final existing = _remoteGhosts[actorId]!;
        _remoteGhosts[actorId] = RemoteGhost(
          userId: actorId,
          taskId: '', // Clear dragging
          lastUpdated: DateTime.now(),
          viewportStart: existing.viewportStart,
          viewportEnd: existing.viewportEnd,
          verticalScrollOffset: existing.verticalScrollOffset,
          userName: existing.userName,
          userColor: existing.userColor,
          tasks: {},
        );
      }
    }

    if (!isDisposed) notifyListeners();
  }

  void _handlePresenceUpdate(Map<String, dynamic> data, String actorId) {
    if (isDisposed) return;
    final actualData = data.containsKey('data') && data['data'] is Map ? data['data'] : data;
    final viewportStart = _parseDate(actualData['viewportStart']);
    final viewportEnd = _parseDate(actualData['viewportEnd']);
    final verticalScrollOffset = (actualData['verticalScrollOffset'] as num?)?.toDouble();
    final name = actualData['userName'] as String?;
    final color = actualData['userColor'] as String?;

    final existing = _remoteGhosts[actorId];
    _remoteGhosts[actorId] = RemoteGhost(
      userId: actorId,
      taskId: existing?.taskId ?? '',
      start: existing?.start,
      end: existing?.end,
      lastUpdated: DateTime.now(),
      viewportStart: viewportStart ?? existing?.viewportStart,
      viewportEnd: viewportEnd ?? existing?.viewportEnd,
      verticalScrollOffset: verticalScrollOffset ?? existing?.verticalScrollOffset,
      userName: name ?? existing?.userName,
      userColor: color ?? existing?.userColor,
    );
    notifyListeners();
  }

  void _handleRemoteCursorMove(Map<String, dynamic> data, String actorId) {
    final actualData = data.containsKey('data') && data['data'] is Map ? data['data'] : data;
    final time = _parseDate(actualData['time']);
    final rowId = actualData['rowId'] as String?;

    if (time != null && rowId != null) {
      _remoteCursors[actorId] = RemoteCursor(
        userId: actorId,
        time: time,
        rowId: rowId,
        color: Colors.primaries[actorId.hashCode % Colors.primaries.length],
        lastUpdated: DateTime.now(),
      );

      if (!isDisposed) notifyListeners();
    }
  }

  /// A callback invoked when the visible date range changes.
  final Function(DateTime start, DateTime end)? onVisibleRangeChanged;

  /// A callback invoked when simple selection changes.
  final Function(Set<String>)? onSelectionChanged;

  /// Creates an instance of [LegacyGanttViewModel].
  ///
  /// This constructor takes all the relevant properties from the
  /// [LegacyGanttChartWidget] to initialize its state. It also adds a listener
  /// to the [scrollController] if one is provided, to synchronize vertical scrolling.
  /// A callback that is invoked when a new dependency is created via the Draw Dependencies tool.
  final Function(LegacyGanttTaskDependency dependency)? onDependencyAdd;

  LegacyGanttViewModel({
    required this.conflictIndicators,
    required List<LegacyGanttTask> data,
    required this.dependencies,
    required this.visibleRows,
    required this.rowMaxStackDepth,
    this.onDependencyAdd,
    required this.rowHeight,
    double? axisHeight,
    double? gridMin,
    double? gridMax,
    double? totalGridMin,
    double? totalGridMax,
    this.enableDragAndDrop = false,
    this.enableResize = false,
    this.enableAutoScheduling = true,
    this.onTaskUpdate,
    this.onTaskDoubleClick,
    this.onTaskDelete,
    this.onEmptySpaceClick,
    this.onTaskDrawEnd,
    this.onPressTask,
    this.scrollController,
    this.ganttHorizontalScrollController,
    this.taskBarBuilder,
    this.resizeTooltipDateFormat,
    this.onTaskHover,
    this.onTaskSecondaryTap,
    this.onTaskLongPress,
    this.onRowRequestVisible,
    this.initialFocusedTaskId,
    this.onFocusChange,
    this.onVisibleRangeChanged,
    this.resizeHandleWidth = 10.0,
    this.syncClient,
    this.taskGrouper,
    this.onSelectionChanged,
    this.onBulkTaskUpdate,
    WorkCalendar? workCalendar,
    bool rollUpMilestones = false,
    bool showSlack = false,
    this.projectTimezoneAbbreviation,
    this.projectTimezoneOffset,
  })  : _tasks = List.from(data),
        _rollUpMilestones = rollUpMilestones,
        _showSlack = showSlack,
        _workCalendar = workCalendar,
        _gridMin = gridMin,
        _gridMax = gridMax,
        _totalGridMin = totalGridMin,
        _totalGridMax = totalGridMax,
        _axisHeight = axisHeight {
    _baseResourceBuckets = aggregateResourceLoad(_tasks, workCalendar: _workCalendar);

    _focusedTaskId = initialFocusedTaskId;
    _calculateRowOffsets();

    if (scrollController != null && scrollController!.hasClients) {
      _translateY = -scrollController!.offset;
    }
    scrollController?.addListener(_onExternalScroll);
    ganttHorizontalScrollController?.addListener(_onHorizontalScrollControllerUpdate);

    if (syncClient != null) {
      _syncSubscription = syncClient!.operationStream.listen(_handleIncomingOperation);
    }
    _rebuildTasksByRow();
  }

  void _handleIncomingOperation(Operation op) {
    if (isDisposed) return;

    final List<Operation> taskOps = [];
    _processOperation(op, taskOps);

    if (taskOps.isNotEmpty) {
      _safeMergeTasks(taskOps);

      if (taskGrouper != null) {
        final conflicts = LegacyGanttConflictDetector().run(
          tasks: _tasks,
          taskGrouper: taskGrouper!,
        );
        conflictIndicators = conflicts;
      }
      _rebuildTasksByRow();
      _calculateDomains(); // Recalculate domains as data changed
      _recalculateCriticalPath();
      notifyListeners();
    }
  }

  void _processOperation(Operation op, List<Operation> taskOps) {
    if (op.type == 'BATCH_UPDATE') {
      final operations = op.data['operations'] as List;
      for (final rawOp in operations) {
        if (rawOp is Map<String, dynamic>) {
          try {
            final subOp = Operation.fromJson(rawOp);
            _processOperation(subOp, taskOps);
          } catch (e) {
            debugPrint('Error parsing batch operation: $e');
          }
        }
      }
      return;
    }

    if (op.type == 'INSERT_DEPENDENCY') {
      _handleInsertDependency(op.data);
    } else if (op.type == 'DELETE_DEPENDENCY') {
      _handleDeleteDependency(op.data);
    } else if (op.type == 'CLEAR_DEPENDENCIES') {
      _handleClearDependencies(op.data);
    } else if (op.type == 'RESET_DATA') {
      debugPrint('WARNING: RESET_DATA received. This operation is deprecated for normal syncing.');
      debugPrint('Please use BATCH_UPDATE with the full state for seeding to ensure CRDT convergence.');
      debugPrint('Proceeding with destructive wipe (Emergency Admin Action)...');
      dependencies = [];
      _tasks.clear();
      conflictIndicators = [];
      _rebuildTasksByRow();
      _calculateDomains();
      notifyListeners();
    } else if (op.type == 'CURSOR_MOVE') {
      _handleRemoteCursorMove(op.data, op.actorId);
    } else if (op.type == 'GHOST_UPDATE') {
      _handleRemoteGhostUpdate(op.data, op.actorId);
    } else if (op.type == 'PRESENCE_UPDATE') {
      _handlePresenceUpdate(op.data, op.actorId);
    } else {
      taskOps.add(op);
    }
  }

  void _handleInsertDependency(Map<String, dynamic> data) {
    final typeStr = data['type'] as String? ?? 'finishToStart';
    final depType =
        DependencyType.values.firstWhere((e) => e.name == typeStr, orElse: () => DependencyType.finishToStart);
    final newDep = LegacyGanttTaskDependency(
      predecessorTaskId: data['predecessorTaskId'],
      successorTaskId: data['successorTaskId'],
      type: depType,
      lag: data['lag'] != null ? Duration(milliseconds: data['lag']) : null,
    );
    if (!dependencies.contains(newDep)) {
      dependencies = List.from(dependencies)..add(newDep);
      onDependencyAdd?.call(newDep);
      _recalculateCriticalPath();
      notifyListeners();
    }
  }

  void _handleDeleteDependency(Map<String, dynamic> data) {
    final pred = data['predecessorTaskId'];
    final succ = data['successorTaskId'];
    final initialLen = dependencies.length;
    dependencies = dependencies.where((d) => !(d.predecessorTaskId == pred && d.successorTaskId == succ)).toList();
    if (dependencies.length != initialLen) {
      notifyListeners();
    }
  }

  void _handleClearDependencies(Map<String, dynamic> data) {
    final taskId = data['taskId'];
    if (taskId != null) {
      final initialLen = dependencies.length;
      dependencies = dependencies.where((d) => d.predecessorTaskId != taskId && d.successorTaskId != taskId).toList();
      if (dependencies.length != initialLen) {
        notifyListeners();
      }
    }
  }

  /// Helper to merge tasks while preserving transient state (e.g. cellBuilder)
  void _safeMergeTasks(List<Operation> ops) {
    final taskMap = {for (var t in _tasks) t.id: t};
    final currentProtocolTasks = _tasks.map((t) => t.toProtocolTask()).toList();
    final mergedProtocolTasks = _crdtEngine.mergeTasks(currentProtocolTasks, ops);

    _tasks = mergedProtocolTasks.map((pt) {
      final original = taskMap[pt.id];
      if (original != null) {
        return original.copyWithProtocol(pt);
      } else {
        return LegacyGanttTask.fromProtocolTask(pt);
      }
    }).toList();
  }

  Map<String, List<ResourceBucket>> _baseResourceBuckets = {};

  /// Returns the resource buckets, potentially modified by the current drag operation.
  /// This ensures the histogram updates live as the user drags a task.
  Map<String, List<ResourceBucket>> get resourceBuckets {
    if (_draggedTask == null || _ghostTaskStart == null || _ghostTaskEnd == null) {
      return _baseResourceBuckets;
    }

    if (_draggedTask!.resourceId == null) {
      return _baseResourceBuckets;
    }

    final resourceId = _draggedTask!.resourceId!;

    final Map<String, List<ResourceBucket>> effectiveBuckets = Map.from(_baseResourceBuckets);
    final List<ResourceBucket> currentResourceBuckets = List.from(effectiveBuckets[resourceId] ?? []);

    final originalStart = _draggedTask!.start;
    final originalEnd = _draggedTask!.end;
    final load = _draggedTask!.load;

    DateTime current = DateTime(originalStart.year, originalStart.month, originalStart.day);
    final endDay = DateTime(originalEnd.year, originalEnd.month, originalEnd.day);

    while (current.isBefore(endDay) || current.isAtSameMomentAs(endDay)) {
      if (_draggedTask!.usesWorkCalendar && _workCalendar != null) {
        if (!_workCalendar!.isWorkingDay(current)) {
          current = current.add(const Duration(days: 1));
          continue;
        }
      }

      final index = currentResourceBuckets.indexWhere((b) => DateUtils.isSameDay(b.date, current));
      if (index != -1) {
        final b = currentResourceBuckets[index];
        final newLoad = b.totalLoad - load;
        currentResourceBuckets[index] = b.copyWith(totalLoad: max(0.0, newLoad));
      }
      current = current.add(const Duration(days: 1));
    }

    final ghostStart = _ghostTaskStart!;
    final ghostEnd = _ghostTaskEnd!;

    current = DateTime(ghostStart.year, ghostStart.month, ghostStart.day);
    final ghostEndDay = DateTime(ghostEnd.year, ghostEnd.month, ghostEnd.day);

    while (current.isBefore(ghostEndDay) || current.isAtSameMomentAs(ghostEndDay)) {
      if (_draggedTask!.usesWorkCalendar && _workCalendar != null) {
        final isWorking = _workCalendar!.isWorkingDay(current);
        if (!isWorking) {
          current = current.add(const Duration(days: 1));
          continue;
        }
      }

      final index = currentResourceBuckets.indexWhere((b) => DateUtils.isSameDay(b.date, current));
      if (index != -1) {
        final b = currentResourceBuckets[index];
        currentResourceBuckets[index] = b.copyWith(totalLoad: b.totalLoad + load);
      } else {
        currentResourceBuckets.add(ResourceBucket(date: current, resourceId: resourceId, totalLoad: load));
      }
      current = current.add(const Duration(days: 1));
    }

    currentResourceBuckets.sort((a, b) => a.date.compareTo(b.date));

    effectiveBuckets[resourceId] = currentResourceBuckets;
    return effectiveBuckets;
  }

  void updateResizeTooltipDateFormat(String Function(DateTime)? newFormat) {
    if (resizeTooltipDateFormat != newFormat) {
      resizeTooltipDateFormat = newFormat;
      if (!isDisposed) notifyListeners();
    }
  }

  /// Updates the list of dependencies and notifies listeners to trigger a repaint.
  void updateData(List<LegacyGanttTask> data) {
    if (_dragMode != DragMode.none && data.isEmpty && _tasks.isNotEmpty) {
      return;
    }

    final mergedData = data.map((incomingTask) {
      final localTask = _tasks.firstWhere((t) => t.id == incomingTask.id, orElse: () => LegacyGanttTask.empty());

      if (localTask.id.isNotEmpty) {
        final localProps = localTask.lastUpdated;
        final incomingProps = incomingTask.lastUpdated;

        if (localProps > incomingProps) {
          return localTask;
        }
      }
      return incomingTask;
    }).toList();

    if (!listEquals(_tasks, mergedData)) {
      if (mergedData.isNotEmpty) {}
      if (isDisposed) return;
      _tasks = mergedData;
      _calculateDomains();
      _recalculateCriticalPath();
      _baseResourceBuckets = aggregateResourceLoad(_tasks,
          start: _visibleExtent.isNotEmpty ? _visibleExtent.first : null,
          end: _visibleExtent.isNotEmpty ? _visibleExtent.last : null);
      _rebuildTasksByRow();
      notifyListeners();
    } else {}
  }

  void updateConflictIndicators(List<LegacyGanttTask> conflictIndicators) {
    if (!listEquals(this.conflictIndicators, conflictIndicators)) {
      if (isDisposed) return;
      this.conflictIndicators = conflictIndicators;
      notifyListeners();
    }
  }

  void updateVisibleRows(List<LegacyGanttRow> visibleRows) {
    if (!listEquals(this.visibleRows, visibleRows)) {
      if (isDisposed) return;
      this.visibleRows = visibleRows;
      _calculateRowOffsets();
      notifyListeners();
    }
  }

  void updateRowMaxStackDepth(Map<String, int> rowMaxStackDepth) {
    if (!mapEquals(this.rowMaxStackDepth, rowMaxStackDepth)) {
      if (isDisposed) return;
      this.rowMaxStackDepth = rowMaxStackDepth;
      _calculateRowOffsets();
      notifyListeners();
    }
  }

  void updateDependencies(List<LegacyGanttTaskDependency> newDependencies) {
    if (!listEquals(dependencies, newDependencies)) {
      dependencies = newDependencies;
      _recalculateCriticalPath();
      if (!isDisposed) notifyListeners();
    }
  }

  void addDependency(LegacyGanttTaskDependency dependency) {
    if (!dependencies.contains(dependency)) {
      dependencies = List.from(dependencies)..add(dependency);
      _sendDependencyOp('INSERT_DEPENDENCY', dependency);
      onDependencyAdd?.call(dependency);
      notifyListeners();
    }
  }

  void removeDependency(LegacyGanttTaskDependency dependency) {
    if (dependencies.contains(dependency)) {
      dependencies = List.from(dependencies)..remove(dependency);
      _sendDependencyOp('DELETE_DEPENDENCY', dependency);
      _recalculateCriticalPath();
      if (!isDisposed) notifyListeners();
    }
  }

  /// Removes all dependencies associated with a given task.
  /// Sends a single CLEAR_DEPENDENCIES operation if a sync client is connected.
  void clearDependenciesForTask(LegacyGanttTask task) {
    bool changed = false;
    final dependenciesToRemove =
        dependencies.where((d) => d.predecessorTaskId == task.id || d.successorTaskId == task.id).toList();

    if (dependenciesToRemove.isNotEmpty) {
      dependencies = List.from(dependencies)..removeWhere((d) => dependenciesToRemove.contains(d));
      changed = true;
    }

    if (syncClient != null) {
      syncClient!.sendOperation(Operation(
        type: 'CLEAR_DEPENDENCIES',
        data: {'taskId': task.id},
        timestamp: _currentTimestamp,
        actorId: syncClient?.actorId ?? 'user',
      ));
    }

    if (changed) {
      _recalculateCriticalPath();
      notifyListeners();
    }
  }

  void _sendCursorMove(DateTime time, String rowId) {
    if (syncClient == null) return;

    final now = DateTime.now();
    if (_lastCursorSync != null && now.difference(_lastCursorSync!) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastCursorSync = now;

    syncClient!.sendOperation(Operation(
      type: 'CURSOR_MOVE',
      data: {
        'time': time.millisecondsSinceEpoch,
        'rowId': rowId,
      },
      timestamp: _currentTimestamp,
      actorId: syncClient?.actorId ?? 'user',
    ));
  }

  void _sendDependencyOp(String type, LegacyGanttTaskDependency dep) {
    if (syncClient == null) return;
    syncClient!.sendOperation(Operation(
      type: type,
      data: {
        'predecessorTaskId': dep.predecessorTaskId,
        'successorTaskId': dep.successorTaskId,
        'type': dep.type.name,
        'lag': dep.lag?.inMilliseconds,
      },
      timestamp: _currentTimestamp,
      actorId: syncClient?.actorId ?? 'user',
    ));
  }

  void updateFocusedTask(String? newFocusedTaskId) {
    if (_focusedTaskId != newFocusedTaskId) {
      if (isDisposed) return;
      _focusedTaskId = newFocusedTaskId;
      notifyListeners();
    }
  }

  double _height = 0;
  double _width = 0;
  double _translateY = 0;
  double _initialTranslateY = 0;
  double _initialTouchY = 0;
  Offset _initialLocalPosition = Offset.zero;
  bool _isScrollingInternally = false;
  String? _lastHoveredTaskId;
  DateTime? _lastCursorSync; // Throttling timestamp
  double Function(DateTime) _totalScale = (DateTime date) => 0.0;
  List<DateTime> _totalDomain = [];
  List<DateTime> _visibleExtent = [];
  LegacyGanttTask? _draggedTask;
  DateTime? _ghostTaskStart;
  DateTime? _ghostTaskEnd;
  final Map<String, (DateTime, DateTime)> _bulkGhostTasks = {};

  /// Detailed ghost task positions during a bulk drag operation.
  /// Keys are task IDs, values are the temporary (start, end).
  Map<String, (DateTime, DateTime)> get bulkGhostTasks => _bulkGhostTasks;
  DragMode _dragMode = DragMode.none;
  PanType _panType = PanType.none;
  double _dragStartGlobalX = 0.0;
  DateTime? _originalTaskStart;
  DateTime? _originalTaskEnd;
  MouseCursor _cursor = SystemMouseCursors.basic;
  bool _showResizeTooltip = false;
  String _resizeTooltipText = '';
  Offset _resizeTooltipPosition = Offset.zero;
  String? _hoveredRowId;
  DateTime? _hoveredDate;
  String? _focusedTaskId;

  String? _dependencyStartTaskId;
  TaskPart? _dependencyStartSide;
  Offset? _currentDragPosition;
  String? _dependencyHoveredTaskId;

  /// The ID of the task where a dependency creation drag started.
  String? get dependencyStartTaskId => _dependencyStartTaskId;
  DependencyDragStatus _dependencyDragStatus = DependencyDragStatus.none;

  /// The current state of the dependency creation interaction.
  DependencyDragStatus get dependencyDragStatus => _dependencyDragStatus;

  int? _dependencyDragDelayAmount;

  /// The optional lag/lead time associated with the dependency being dragged.
  int? get dependencyDragDelayAmount => _dependencyDragDelayAmount;

  /// The side of the task (start/end) where the dependency drag started.
  TaskPart? get dependencyStartSide => _dependencyStartSide;

  /// The current global position of the dependency drag line end.
  Offset? get currentDragPosition => _currentDragPosition;

  /// The ID of the task currently being hovered during a dependency drag.
  String? get dependencyHoveredTaskId => _dependencyHoveredTaskId;

  List<double> _rowVerticalOffsets = [];
  double _totalContentHeight = 0;

  bool _showCriticalPath = false;
  Set<String> _criticalTaskIds = {};
  Set<LegacyGanttTaskDependency> _criticalDependencies = {};
  Map<String, CpmTaskStats> _cpmStats = {};

  bool get showCriticalPath => _showCriticalPath;

  /// The IDs of tasks that are part of the critical path.
  Set<String> get criticalTaskIds => _criticalTaskIds;

  /// The dependencies that are part of the critical path.
  Set<LegacyGanttTaskDependency> get criticalDependencies => _criticalDependencies;

  /// Detailed Critical Path Method (CPM) stats for each task (early/late start/finish, float).
  Map<String, CpmTaskStats> get cpmStats => _cpmStats;

  set showCriticalPath(bool value) {
    if (_showCriticalPath != value) {
      _showCriticalPath = value;
      if (_showCriticalPath) {
        _recalculateCriticalPath();
      } else {
        _criticalTaskIds.clear();
        _criticalDependencies.clear();
        _cpmStats.clear();
        notifyListeners();
      }
    }
  }

  void _recalculateCriticalPath() {
    if (!_showCriticalPath && !_showSlack && _dependencyDragStatus == DependencyDragStatus.none) {
      _criticalTaskIds = const {};
      _criticalDependencies = const {};
      _cpmStats = const {};
      return;
    }

    final calculator = CriticalPathCalculator();
    final result = calculator.calculate(tasks: _tasks, dependencies: dependencies);

    _criticalTaskIds = result.criticalTaskIds;
    _criticalDependencies = result.criticalDependencies;
    _cpmStats = result.taskStats;
    notifyListeners();
  }

  /// The currently active tool.
  GanttTool _currentTool = GanttTool.move;
  GanttTool get currentTool => _currentTool;

  /// The current selection rectangle in local coordinates (relative to the chart content).
  Rect? _selectionRect;

  /// Public getter for the selection rectangle.
  Rect? get selectionRect => _selectionRect;

  /// The IDs of the currently selected tasks.
  final Set<String> _selectedTaskIds = {};

  /// Public getter for the selected task IDs.
  Set<String> get selectedTaskIds => Set.unmodifiable(_selectedTaskIds);

  /// Sets the currently active tool.
  void setTool(GanttTool tool) {
    if (_currentTool != tool) {
      _currentTool = tool;
      _selectionRect = null;
      if (tool == GanttTool.select) {
        _clearEmptySpaceHover();
      }
      notifyListeners();
    }
  }

  /// Updates the selection rectangle and selects tasks within it.
  void updateSelection(Rect? rect) {
    _selectionRect = rect;
    if (rect != null) {
      _selectTasksInRect(rect);
    }
    notifyListeners();
  }

  /// Selects tasks that intersect with the given rectangle.
  /// Selects tasks that intersect with the given rectangle.
  void _selectTasksInRect(Rect rect) {
    _selectedTaskIds.clear();

    final contentRect = rect.shift(Offset(0, -timeAxisHeight - _translateY));

    final visibleRowIndices = {for (var i = 0; i < visibleRows.length; i++) visibleRows[i].id: i};

    for (final task in data) {
      final rowIndex = visibleRowIndices[task.rowId];
      if (rowIndex == null) continue;

      final rowTop = _rowVerticalOffsets[rowIndex];
      final top = rowTop + (task.stackIndex * rowHeight);
      final bottom = top + rowHeight;

      if (contentRect.top > bottom || contentRect.bottom < top) continue;

      final startX = _totalScale(task.start);
      final endX = _totalScale(task.end);

      final taskRect = Rect.fromLTRB(startX, top, endX, bottom);

      if (contentRect.overlaps(taskRect)) {
        _selectedTaskIds.add(task.id);
      }
    }
  }

  /// Clear the current selection.
  void clearSelection() {
    _selectedTaskIds.clear();
    _selectionRect = null;
    notifyListeners();
  }

  /// The current vertical scroll offset of the chart content.
  double get translateY => _translateY;

  /// The current mouse cursor to display based on the hover position and enabled features.
  MouseCursor get cursor => _cursor;

  /// The task currently being dragged or resized.
  LegacyGanttTask? get draggedTask => _draggedTask;

  /// The projected start time of the task being dragged/resized.
  DateTime? get ghostTaskStart => _ghostTaskStart;

  /// The projected end time of the task being dragged/resized.
  DateTime? get ghostTaskEnd => _ghostTaskEnd;

  /// The full date range of the chart, from `totalGridMin` to `totalGridMax`.
  List<DateTime> get totalDomain => _totalDomain;

  /// The currently visible date range of the chart, from `gridMin` to `gridMax`.
  List<DateTime> get visibleExtent => _visibleExtent;

  /// The function that converts a [DateTime] to a horizontal pixel value across the total width.
  double Function(DateTime) get totalScale => _totalScale;

  /// The calculated height of the time axis header.
  double get timeAxisHeight => axisHeight ?? (_height.isFinite ? _height * 0.1 : 30.0);

  /// Whether the resize/drag tooltip should be visible.
  bool get showResizeTooltip => _showResizeTooltip;

  /// The text content for the resize/drag tooltip.
  String get resizeTooltipText => _resizeTooltipText;

  /// The screen position for the resize/drag tooltip.
  Offset get resizeTooltipPosition => _resizeTooltipPosition;

  /// The ID of the row currently being hovered over for task creation.
  String? get hoveredRowId => _hoveredRowId;

  /// The date currently being hovered over for task creation.
  DateTime? get hoveredDate => _hoveredDate;

  /// The ID of the task that currently has focus.
  String? get focusedTaskId => _focusedTaskId;

  /// Gets the pre-calculated vertical offset for a given row index.
  double? getRowVerticalOffset(int rowIndex) {
    if (rowIndex >= 0 && rowIndex < _rowVerticalOffsets.length) return _rowVerticalOffsets[rowIndex];
    return null;
  }

  /// Called by the widget to inform the view model of its available dimensions.
  /// This is crucial for calculating the time scale.
  /// Called by the widget to inform the view model of its available dimensions.
  /// This is crucial for calculating the time scale.
  void updateLayout(double width, double height) {
    if (_width != width || _height != height) {
      _width = width;
      _height = height;
      _calculateDomains();
      _calculateRowOffsets(); // Recalculate if layout changes

      if (!isDisposed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!isDisposed) notifyListeners();
        });
      }
    }

    if (scrollController != null && scrollController!.hasClients) {
      double? currentControllerOffset;
      if (scrollController!.positions.length == 1) {
        currentControllerOffset = scrollController!.offset;
      } else if (scrollController!.positions.isNotEmpty) {
        currentControllerOffset = scrollController!.positions.first.pixels;
      }

      if (currentControllerOffset != null) {
        if ((_translateY - (-currentControllerOffset)).abs() > 0.1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController != null && scrollController!.hasClients) {
              double? callbackOffset;
              if (scrollController!.positions.length == 1) {
                callbackOffset = scrollController!.offset;
              } else if (scrollController!.positions.isNotEmpty) {
                callbackOffset = scrollController!.positions.first.pixels;
              }

              if (callbackOffset != null) {
                setTranslateY(-callbackOffset);
              }
            }
          });
        }
      }
    }
  }

  /// Manually sets the vertical scroll offset.
  void setTranslateY(double newTranslateY) {
    if (_translateY != newTranslateY) {
      if (isDisposed) return;
      _translateY = newTranslateY;
      notifyListeners();
    }
  }

  /// Updates the visible time range, typically called when using a [LegacyGanttController].
  void updateVisibleRange(double? newGridMin, double? newGridMax) {
    final bool changed = gridMin != newGridMin || gridMax != newGridMax;
    if (changed) {
      gridMin = newGridMin;
      gridMax = newGridMax;
      _calculateDomains();
      _calculateRowOffsets(); // Recalculate if visible rows could have changed
      _calculateDomains();
      _calculateRowOffsets(); // Recalculate if visible rows could have changed
      if (!isDisposed) notifyListeners();
    }
  }

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    _isDisposed = true;
    scrollController?.removeListener(_onExternalScroll);
    ganttHorizontalScrollController?.removeListener(_onHorizontalScrollControllerUpdate);
    _syncSubscription?.cancel();
    super.dispose();
  }

  /// 2. New Helper: Pre-calculates the Y position of every row.
  /// Call this in the constructor and if visibleRows/stackDepth ever changes.
  void _calculateRowOffsets() {
    _rowVerticalOffsets = List<double>.filled(visibleRows.length + 1, 0.0);
    double currentTop = 0.0;

    for (int i = 0; i < visibleRows.length; i++) {
      _rowVerticalOffsets[i] = currentTop;
      final rowId = visibleRows[i].id;
      final int stackDepth = rowMaxStackDepth[rowId] ?? 1;
      currentTop += rowHeight * stackDepth;
    }
    _rowVerticalOffsets[visibleRows.length] = currentTop;
    _totalContentHeight = currentTop;
  }

  /// 3. New Helper: O(log N) Binary Search to find the row index from a Y-coordinate.
  int _findRowIndex(double y) {
    if (_rowVerticalOffsets.isEmpty || y < 0 || y >= _totalContentHeight) {
      return -1;
    }
    int low = 0;
    int high = _rowVerticalOffsets.length - 2; // -2 because last index is total height
    int result = -1;
    while (low <= high) {
      int mid = low + ((high - low) >> 1);
      if (_rowVerticalOffsets[mid] <= y) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (result != -1 && y >= _rowVerticalOffsets[result] && y < _rowVerticalOffsets[result + 1]) {
      return result;
    }
    low = 0;
    high = _rowVerticalOffsets.length - 2;
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      double top = _rowVerticalOffsets[mid];
      double bottom = _rowVerticalOffsets[mid + 1];
      if (y >= top && y < bottom) {
        return mid;
      } else if (y < top) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return -1;
  }

  void _onExternalScroll() {
    if (_isScrollingInternally) {
      return;
    }

    final newTranslateY = -scrollController!.offset;
    setTranslateY(newTranslateY);
  }

  void _onHorizontalScrollControllerUpdate() {
    _updateVisibleExtentFromScroll();
    notifyListeners();
  }

  void _updateVisibleExtentFromScroll() {
    final controller = ganttHorizontalScrollController;
    if (controller == null || !controller.hasClients || _totalDomain.isEmpty) {
      return;
    }

    final position = controller.position;
    if (!position.hasViewportDimension || !position.hasPixels) {
      return;
    }

    final double viewportWidth = position.viewportDimension;
    final double scrollOffset = position.pixels;
    final double totalWidth = _width; // The total content width

    if (totalWidth <= 0) return;

    final double totalDurationMs =
        (_totalDomain.last.millisecondsSinceEpoch - _totalDomain.first.millisecondsSinceEpoch).toDouble();

    final double startOffsetMs = (scrollOffset / totalWidth) * totalDurationMs;
    final double visibleDurationMs = (viewportWidth / totalWidth) * totalDurationMs;

    final startMs = _totalDomain[0].millisecondsSinceEpoch + startOffsetMs;
    final endMs = startMs + visibleDurationMs;

    _visibleExtent = [
      DateTime.fromMillisecondsSinceEpoch(startMs.round()),
      DateTime.fromMillisecondsSinceEpoch(endMs.round()),
    ];
  }

  void _calculateDomains() {
    if (_gridMin != null && _gridMax != null) {
      _visibleExtent = [
        DateTime.fromMillisecondsSinceEpoch(_gridMin!.toInt()),
        DateTime.fromMillisecondsSinceEpoch(_gridMax!.toInt()),
      ];
    } else if (data.isEmpty) {
      final now = DateTime.now();
      _visibleExtent = [now.subtract(const Duration(days: 30)), now.add(const Duration(days: 30))];
    } else {
      if (data.isNotEmpty) {
        final dateTimes = data.expand((task) => [task.start, task.end]).map((d) => d.millisecondsSinceEpoch).toList();
        _visibleExtent = [
          DateTime.fromMillisecondsSinceEpoch(dateTimes.reduce(min)),
          DateTime.fromMillisecondsSinceEpoch(dateTimes.reduce(max)),
        ];
      }
    }

    _totalDomain = [
      DateTime.fromMillisecondsSinceEpoch(totalGridMin?.toInt() ?? _visibleExtent[0].millisecondsSinceEpoch),
      DateTime.fromMillisecondsSinceEpoch(totalGridMax?.toInt() ?? _visibleExtent[1].millisecondsSinceEpoch),
    ];

    final double totalDomainDurationMs =
        (_totalDomain.last.millisecondsSinceEpoch - _totalDomain.first.millisecondsSinceEpoch).toDouble();

    final double totalContentWidth = _width;

    if (totalDomainDurationMs > 0) {
      _totalScale = (DateTime date) {
        final double value = (date.millisecondsSinceEpoch - _totalDomain[0].millisecondsSinceEpoch).toDouble();
        return (value / totalDomainDurationMs) * totalContentWidth;
      };
    } else {
      _totalScale = (date) => 0.0;
    }

    if (ganttHorizontalScrollController != null && ganttHorizontalScrollController!.hasClients) {
      _updateVisibleExtentFromScroll();
    }
  }

  /// Gesture handler for the start of a pan gesture. Determines if the pan is
  /// for vertical scrolling, moving a task, or resizing a task.

  void onHorizontalPanStart(DragStartDetails details) {
    if (_panType != PanType.none) return;

    final hit = _getTaskPartAtPosition(details.localPosition);
    if (hit != null) {
      _panType = PanType.horizontal;
      _initialTranslateY = _translateY;
      _initialTouchY = details.globalPosition.dy;
      _dragStartGlobalX = details.globalPosition.dx;

      if (hit.task.isAutoScheduled == true && hit.task.isSummary && hit.part == TaskPart.body) {
        return;
      }

      _draggedTask = hit.task;
      _originalTaskStart = hit.task.start;
      _originalTaskEnd = hit.task.end;
      switch (hit.part) {
        case TaskPart.startHandle:
          _dragMode = DragMode.resizeStart;
          break;
        case TaskPart.endHandle:
          _dragMode = DragMode.resizeEnd;
          break;
        case TaskPart.body:
          _dragMode = DragMode.move;
          break;
      }
      if (!isDisposed) notifyListeners();
    } else {
      _panType = PanType.horizontal;
      _initialTranslateY = _translateY;
      _initialTouchY = details.globalPosition.dy;
      _dragStartGlobalX = details.globalPosition.dx;
      _dragMode = DragMode.none;
      if (!isDisposed) notifyListeners();
    }
  }

  void onHorizontalPanUpdate(DragUpdateDetails details) {
    if (_panType == PanType.vertical) return;
    if (_panType == PanType.none) {
      _panType = PanType.horizontal;
      _dragStartGlobalX = details.globalPosition.dx; // Re-sync start
    }

    if (_panType == PanType.horizontal) {
      if (_draggedTask != null) {
        _handleHorizontalPan(details);
        if (_ghostTaskStart != null && _ghostTaskEnd != null) {
          _sendGhostUpdate(_draggedTask!.id, _ghostTaskStart!, _ghostTaskEnd!);
        }
      } else {
        _handleHorizontalScroll(-details.delta.dx);
      }
    }
  }

  void onHorizontalPanEnd(DragEndDetails details) {
    if (_panType == PanType.horizontal) {
      if (_draggedTask != null && _ghostTaskStart != null) {
        final delta = _ghostTaskStart!.difference(_draggedTask!.start);
        if (delta.inSeconds != 0) {
          _propagateAutoSchedule(_draggedTask!, delta);
        }
      }

      if (_draggedTask != null) {
        _clearGhostUpdate(_draggedTask!.id);
      }
      if (_draggedTask != null && _ghostTaskStart != null && _ghostTaskEnd != null) {
        _bulkGhostTasks[_draggedTask!.id] = (_ghostTaskStart!, _ghostTaskEnd!);
      }
    }
    _commitBulkUpdates();
    _resetDragState();
  }

  void _commitBulkUpdates() {
    if (_bulkGhostTasks.isEmpty) return;

    bool localStateChanged = false;
    final Map<String, (DateTime, DateTime)> updates = Map.from(_bulkGhostTasks);
    final opsToSend = <Operation>[];
    final bulkUpdates = <(LegacyGanttTask, DateTime, DateTime)>[];

    for (final entry in updates.entries) {
      final taskId = entry.key;
      final (newStart, newEnd) = entry.value;

      final task = data.firstWhere((t) => t.id == taskId, orElse: () => LegacyGanttTask.empty());
      if (task.id.isEmpty) continue;

      final now = syncClient?.currentHlc ?? Hlc.fromDate(DateTime.now(), 'local');
      final updatedTask = task.copyWith(start: newStart, end: newEnd, lastUpdated: now);
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _tasks[index] = updatedTask;
        localStateChanged = true;
      }

      final op = Operation(
          type: 'UPDATE_TASK', data: updatedTask.toJson(), timestamp: now, actorId: syncClient?.actorId ?? 'user');
      if (onBulkTaskUpdate != null) {
        bulkUpdates.add((task, newStart, newEnd));
      } else {
        onTaskUpdate?.call(task, newStart, newEnd);
      }
      opsToSend.add(op);
    }

    if (bulkUpdates.isNotEmpty) {
      onBulkTaskUpdate!(List.from(bulkUpdates));
    }

    if (opsToSend.isNotEmpty && syncClient != null) {
      syncClient!.sendOperations(opsToSend);
      _safeMergeTasks(opsToSend);
    }

    if (localStateChanged && taskGrouper != null) {
      final conflicts = LegacyGanttConflictDetector().run(tasks: _tasks, taskGrouper: taskGrouper!);
      conflictIndicators = conflicts;
      notifyListeners();
    }
  }

  /// Propagates a time shift (delta) to all successor tasks and child tasks.
  /// This implements the auto-scheduling logic.
  void _propagateAutoSchedule(LegacyGanttTask originTask, Duration delta) {
    if (!enableAutoScheduling) return;

    final visited = <String>{originTask.id};
    final queue = <LegacyGanttTask>[originTask];

    final originNewStart = originTask.start.add(delta);
    final originNewEnd = originTask.end.add(delta);

    (DateTime, DateTime) getNewPosition(LegacyGanttTask t) {
      if (t.id == originTask.id) return (originNewStart, originNewEnd);
      if (_bulkGhostTasks.containsKey(t.id)) return _bulkGhostTasks[t.id]!;
      return (t.start, t.end);
    }

    int safetyCounter = 0;
    const maxIterations = 10000;

    while (queue.isNotEmpty) {
      if (safetyCounter++ > maxIterations) break;

      final currentTask = queue.removeAt(0);
      final (currentStart, currentEnd) = getNewPosition(currentTask);

      if (currentTask.propagatesMoveToChildren && _dragMode == DragMode.move) {
        final children = _tasks.where((t) => t.parentId == currentTask.id);
        final parentDelta = currentStart.difference(currentTask.start);

        for (final child in children) {
          if (visited.contains(child.id)) continue;
          if (child.isAutoScheduled == false) continue;

          final childNewStart = child.start.add(parentDelta);
          final childNewEnd = child.end.add(parentDelta);

          _bulkGhostTasks[child.id] = (childNewStart, childNewEnd);
          visited.add(child.id);
          queue.add(child);
        }
      }

      final forwardDeps = dependencies.where((d) => d.predecessorTaskId == currentTask.id).toList();
      for (final dep in forwardDeps) {
        final successor = _tasks.firstWhere((t) => t.id == dep.successorTaskId, orElse: () => LegacyGanttTask.empty());
        if (successor.id.isEmpty || successor.isAutoScheduled == false) continue;

        final (succStart, _) = getNewPosition(successor);
        final succDuration = successor.end.difference(successor.start);
        final lag = dep.lag ?? Duration.zero;

        DateTime? requiredMinStart;
        switch (dep.type) {
          case DependencyType.finishToStart:
            requiredMinStart = currentEnd.add(lag);
            break;
          case DependencyType.startToStart:
            requiredMinStart = currentStart.add(lag);
            break;
          case DependencyType.finishToFinish:
            requiredMinStart = currentEnd.add(lag).subtract(succDuration);
            break;
          case DependencyType.startToFinish:
            requiredMinStart = currentStart.add(lag).subtract(succDuration);
            break;
          case DependencyType.contained:
            break;
        }

        if (requiredMinStart != null && succStart.isBefore(requiredMinStart)) {
          _bulkGhostTasks[successor.id] = (requiredMinStart, requiredMinStart.add(succDuration));
          if (!queue.contains(successor)) queue.add(successor);
        }
      }

      final backwardDeps = dependencies.where((d) => d.successorTaskId == currentTask.id).toList();
      for (final dep in backwardDeps) {
        final predecessor =
            _tasks.firstWhere((t) => t.id == dep.predecessorTaskId, orElse: () => LegacyGanttTask.empty());
        if (predecessor.id.isEmpty || predecessor.isAutoScheduled == false) continue;

        final (_, predEnd) = getNewPosition(predecessor);
        final predDuration = predecessor.end.difference(predecessor.start);
        final lag = dep.lag ?? Duration.zero;

        DateTime? requiredMaxEnd;
        switch (dep.type) {
          case DependencyType.finishToStart:
            requiredMaxEnd = currentStart.subtract(lag);
            break;
          case DependencyType.startToStart:
            requiredMaxEnd = currentStart.subtract(lag).add(predDuration); // pred.start = currentStart - lag
            break;
          case DependencyType.finishToFinish:
            requiredMaxEnd = currentEnd.subtract(lag);
            break;
          case DependencyType.startToFinish:
            requiredMaxEnd = currentEnd.subtract(lag).add(predDuration);
            break;
          case DependencyType.contained:
            break;
        }

        if (requiredMaxEnd != null && predEnd.isAfter(requiredMaxEnd)) {
          _bulkGhostTasks[predecessor.id] = (requiredMaxEnd.subtract(predDuration), requiredMaxEnd);
          if (!queue.contains(predecessor)) queue.add(predecessor);
        }
      }
    }
  }

  void onHorizontalPanCancel() {
    if (_draggedTask != null) {
      _clearGhostUpdate(_draggedTask!.id);
    }
    _resetDragState();
  }

  void onVerticalPanStart(DragStartDetails details) {
    if (_panType != PanType.none) return;
    _panType = PanType.vertical;
    _initialTranslateY = _translateY;
    _initialTouchY = details.globalPosition.dy;
  }

  void onVerticalPanUpdate(DragUpdateDetails details) {
    if (_panType == PanType.horizontal) return;
    if (_panType == PanType.none) _panType = PanType.vertical;

    _handleVerticalPan(details);
  }

  void onVerticalPanEnd(DragEndDetails details) {
    if (_panType == PanType.vertical) {}
    _resetDragState();
  }

  void updateTotalGridRange(double? min, double? max) {
    if (_totalGridMin != min || _totalGridMax != max) {
      _totalGridMin = min;
      _totalGridMax = max;
      _calculateDomains();
      notifyListeners();
    }
  }

  void minMaxOverrides(double? min, double? max) {
    if (_gridMin != min || _gridMax != max) {
      _gridMin = min;
      _gridMax = max;
      _calculateDomains();
      notifyListeners();
    }
  }

  void onVerticalPanCancel() {
    if (_panType == PanType.vertical) {
      _translateY = _initialTranslateY;
      notifyListeners();
    }
    _resetDragState();
  }

  void _resetDragState() {
    _dragMode = DragMode.none;
    _panType = PanType.none;
    _draggedTask = null;
    _ghostTaskStart = null;
    _ghostTaskEnd = null;
    _bulkGhostTasks.clear();
    _initialTouchY = 0;
    _initialTranslateY = 0;
    _dragStartGlobalX = 0;
    _originalTaskStart = null;
    _originalTaskEnd = null;
    _hoveredRowId = null;
    _hoveredDate = null;
    _dependencyStartTaskId = null;
    _dependencyStartSide = null;
    _currentDragPosition = null;
    _dependencyDragStatus = DependencyDragStatus.none;
    _dependencyDragDelayAmount = null;
    _dependencyHoveredTaskId = null;
    if (!isDisposed) notifyListeners();
  }

  bool _isPrimaryButtonDown = false;

  void onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (event.buttons & kPrimaryMouseButton != 0) {
        _isPrimaryButtonDown = true;
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _isPrimaryButtonDown = false;
    }
  }

  void _rebuildTasksByRow() {
    _tasksByRow = {};
    final Map<String, int> calculatedMaxStackDepth = {};

    final Map<String, List<LegacyGanttTask>> rawGrouping = {};
    for (final task in _tasks) {
      if (task.isDeleted) continue;
      rawGrouping.putIfAbsent(task.rowId, () => []).add(task);
    }

    for (final entry in rawGrouping.entries) {
      final rowId = entry.key;
      final tasks = entry.value;

      tasks.sort((a, b) => a.start.compareTo(b.start));

      final List<LegacyGanttTask> layoutTasks = [];
      final List<DateTime> stackEndTimes = [];

      for (final task in tasks) {
        int assignedStackIndex = 0;
        bool placed = false;

        for (int i = 0; i < stackEndTimes.length; i++) {
          if (stackEndTimes[i].isBefore(task.start) || stackEndTimes[i].isAtSameMomentAs(task.start)) {
            assignedStackIndex = i;
            stackEndTimes[i] = task.end;
            placed = true;
            break;
          }
        }

        if (!placed) {
          assignedStackIndex = stackEndTimes.length;
          stackEndTimes.add(task.end);
        }

        layoutTasks.add(task.copyWith(stackIndex: assignedStackIndex));
      }

      _tasksByRow[rowId] = layoutTasks;
      calculatedMaxStackDepth[rowId] = stackEndTimes.length;
    }

    rowMaxStackDepth.clear();
    rowMaxStackDepth.addAll(calculatedMaxStackDepth);
  }

  void onPanStart(
    DragStartDetails details, {
    LegacyGanttTask? overrideTask,
    TaskPart? overridePart,
  }) {
    if (overrideTask != null) {
      if (overrideTask.isAutoScheduled == true && overrideTask.isSummary && overridePart == TaskPart.body) {
        return;
      }
      _panType = PanType.horizontal;
      _initialTranslateY = _translateY;
      _initialTouchY = details.globalPosition.dy;
      _dragStartGlobalX = details.globalPosition.dx;
      _draggedTask = overrideTask;
      _originalTaskStart = overrideTask.start;
      _originalTaskEnd = overrideTask.end;

      switch (overridePart ?? TaskPart.body) {
        case TaskPart.startHandle:
          _dragMode = DragMode.resizeStart;
          break;
        case TaskPart.endHandle:
          _dragMode = DragMode.resizeEnd;
          break;
        default:
          _dragMode = DragMode.move;
          break;
      }

      if (!isDisposed) notifyListeners();
      return;
    }

    if (_currentTool == GanttTool.select) {
      _panType = PanType.selection;
      final startY = max(0.0, details.localPosition.dy - timeAxisHeight);
      final startPoint = Offset(details.localPosition.dx, startY);
      _initialLocalPosition = startPoint;
      _selectionRect = Rect.fromPoints(startPoint, startPoint);
      _selectedTaskIds.clear(); // Start new selection
      notifyListeners();
      return;
    }

    if (_currentTool == GanttTool.drawDependencies) {
      final hit = _getTaskPartAtPosition(details.localPosition);
      if (hit != null && (hit.part == TaskPart.startHandle || hit.part == TaskPart.endHandle)) {
        _panType = PanType.dependency;
        _dependencyStartTaskId = hit.task.id;
        _dependencyStartSide = hit.part;
        _currentDragPosition = details.localPosition;
        _dependencyDragStatus = DependencyDragStatus.none;
        _dependencyDragDelayAmount = null;
        _recalculateCriticalPath();
        notifyListeners();
      }
      return;
    }

    if (_currentTool == GanttTool.draw) {
      final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);
      if (rowId != null && time != null) {
        _panType = PanType.draw;
        _hoveredRowId = rowId;
        _ghostTaskStart = time;
        _ghostTaskEnd = time;
        _dragStartGlobalX = details.globalPosition.dx;
        _draggedTask = LegacyGanttTask(
          id: 'drawing_ghost',
          rowId: rowId,
          start: time,
          end: time,
          name: 'New Task',
        );
        notifyListeners();
      }
      return;
    }

    _panType = PanType.none;
    _initialTranslateY = _translateY;
    _initialTouchY = details.globalPosition.dy;
    _initialLocalPosition = details.localPosition;
    _dragStartGlobalX = details.globalPosition.dx;
  }

  void onPanUpdate(DragUpdateDetails details) {
    if (_panType == PanType.horizontal) {
      onHorizontalPanUpdate(details);
    } else if (_panType == PanType.selection) {
      if (_selectionRect != null) {
        final currentY = max(0.0, details.localPosition.dy - timeAxisHeight);
        final currentPoint = Offset(details.localPosition.dx, currentY);
        final newRect = Rect.fromPoints(_initialLocalPosition, currentPoint);
        _selectionRect = newRect;
        _updateSelectionFromRect(newRect);
        notifyListeners();
      }
    } else if (_panType == PanType.draw) {
      final (_, time) = _getRowAndTimeAtPosition(details.localPosition);
      if (time != null && _ghostTaskStart != null) {
        _ghostTaskEnd = time;
        notifyListeners();
      }
    } else if (_panType == PanType.dependency) {
      _currentDragPosition = details.localPosition;
      final hit = _getTaskPartAtPosition(details.localPosition);
      _dependencyDragStatus = DependencyDragStatus.none;
      _dependencyDragDelayAmount = null;

      if (hit != null &&
          hit.task.id != _dependencyStartTaskId &&
          (hit.part == TaskPart.startHandle || hit.part == TaskPart.endHandle)) {
        _dependencyHoveredTaskId = hit.task.id;

        if (_wouldCreateCycle(_dependencyStartTaskId!, hit.task.id)) {
          _dependencyDragStatus = DependencyDragStatus.cycle;
        } else {
          final sourceStats = _cpmStats[_dependencyStartTaskId!];
          final targetStats = _cpmStats[hit.task.id];

          if (sourceStats != null && targetStats != null) {
            if (sourceStats.earlyFinish <= targetStats.lateStart) {
              _dependencyDragStatus = DependencyDragStatus.admissible;
            } else {
              _dependencyDragStatus = DependencyDragStatus.inadmissible;
              _dependencyDragDelayAmount = sourceStats.earlyFinish - targetStats.lateStart;
            }
          }
        }
      } else {
        _dependencyHoveredTaskId = null;
      }
      notifyListeners();
      onVerticalPanUpdate(details);
    } else {
      if (details.delta.dx.abs() > details.delta.dy.abs()) {
        if (_isPrimaryButtonDown) {
          final hit = _getTaskPartAtPosition(_initialLocalPosition);
          if (hit != null) {
            _panType = PanType.horizontal;
            _draggedTask = hit.task;
            _originalTaskStart = hit.task.start;
            _originalTaskEnd = hit.task.end;
            switch (hit.part) {
              case TaskPart.startHandle:
                _dragMode = DragMode.resizeStart;
                break;
              case TaskPart.endHandle:
                _dragMode = DragMode.resizeEnd;
                break;
              case TaskPart.body:
                _dragMode = DragMode.move;
                break;
            }
            onHorizontalPanUpdate(details);
          }
        }
      } else {
        _panType = PanType.vertical;
        onVerticalPanUpdate(details);
      }
    }
  }

  void onPanEnd(DragEndDetails details) {
    if (_panType == PanType.horizontal) {
      onHorizontalPanEnd(details);
    } else if (_panType == PanType.selection) {
      _panType = PanType.none;
      _selectionRect = null; // Hide box but keep selection
      notifyListeners();
    } else if (_panType == PanType.draw) {
      if (_ghostTaskStart != null && _ghostTaskEnd != null && _draggedTask != null) {
        final start = _ghostTaskStart!.isBefore(_ghostTaskEnd!) ? _ghostTaskStart! : _ghostTaskEnd!;
        final end = _ghostTaskStart!.isBefore(_ghostTaskEnd!) ? _ghostTaskEnd! : _ghostTaskStart!;
        if (start != end) {
          onTaskDrawEnd?.call(start, end, _draggedTask!.rowId);
        }
      }
      _panType = PanType.none;
      _draggedTask = null;
      _ghostTaskStart = null;
      _ghostTaskEnd = null;
      notifyListeners();
    } else if (_panType == PanType.dependency) {
      if (_dependencyStartTaskId != null && _dependencyStartSide != null && _currentDragPosition != null) {
        final hit = _getTaskPartAtPosition(_currentDragPosition!);
        if (hit != null &&
            hit.task.id != _dependencyStartTaskId &&
            (hit.part == TaskPart.startHandle || hit.part == TaskPart.endHandle)) {
          DependencyType type;
          if (_dependencyStartSide == TaskPart.endHandle && hit.part == TaskPart.startHandle) {
            type = DependencyType.finishToStart;
          } else if (_dependencyStartSide == TaskPart.startHandle && hit.part == TaskPart.startHandle) {
            type = DependencyType.startToStart;
          } else if (_dependencyStartSide == TaskPart.endHandle && hit.part == TaskPart.endHandle) {
            type = DependencyType.finishToFinish;
          } else {
            type = DependencyType.startToFinish;
          }

          if (!_wouldCreateCycle(_dependencyStartTaskId!, hit.task.id)) {
            final newDep = LegacyGanttTaskDependency(
              predecessorTaskId: _dependencyStartTaskId!,
              successorTaskId: hit.task.id,
              type: type,
            );
            addDependency(newDep);
          }
        }
      }
      _panType = PanType.none;
      _dependencyStartTaskId = null;
      _dependencyStartSide = null;
      _currentDragPosition = null;
      _dependencyDragStatus = DependencyDragStatus.none;
      _dependencyDragDelayAmount = null;
      _dependencyHoveredTaskId = null;
      notifyListeners();
    } else {
      onVerticalPanEnd(details);
    }
  }

  void onPanCancel() {
    if (_panType == PanType.horizontal) {
      onHorizontalPanCancel();
    } else {
      onVerticalPanCancel();
    }
  }

  Offset? _lastTapDownPosition;

  void onTapDown(TapDownDetails details) {
    _lastTapDownPosition = details.localPosition;
  }

  /// Gesture handler for a tap gesture. Determines if a task or empty space
  /// was tapped and invokes the appropriate callback.
  void onTap() {
    if (_lastTapDownPosition == null) return;
    final localPosition = _lastTapDownPosition!;

    if (_currentTool == GanttTool.select) {
      final hit = _getTaskPartAtPosition(localPosition);
      if (hit != null) {
        if (_selectedTaskIds.contains(hit.task.id)) {
          _selectedTaskIds.remove(hit.task.id);
        } else {
          _selectedTaskIds.add(hit.task.id);
        }
        notifyListeners();

        onSelectionChanged?.call(_selectedTaskIds);
      } else {
        if (_selectedTaskIds.isNotEmpty) {
          clearSelection();
        }
      }
      return;
    }

    final hit = _getTaskPartAtPosition(localPosition);
    if (hit != null) {
      onPressTask?.call(hit.task);
      return; // Don't process empty space click if a task was hit
    }

    if (onEmptySpaceClick != null) {
      final (rowId, time) = _getRowAndTimeAtPosition(localPosition);
      if (rowId != null && time != null) {
        onEmptySpaceClick!(rowId, time);
      }
    }
  }

  /// Gesture handler for a double-tap gesture. Determines if a task was tapped
  /// and invokes the `onTaskDoubleClick` callback.
  void onDoubleTap(Offset localPosition) {
    final hit = _getTaskPartAtPosition(localPosition);
    if (hit != null) {
      onTaskDoubleClick?.call(hit.task);
    }
  }

  void onSecondaryTap(Offset localPosition, Offset globalPosition) {
    final hit = _getTaskPartAtPosition(localPosition);
    if (hit != null) {
      onTaskSecondaryTap?.call(hit.task, globalPosition);
    }
  }

  void onLongPress(Offset localPosition, Offset globalPosition) {
    final hit = _getTaskPartAtPosition(localPosition);
    if (hit != null) {
      onTaskLongPress?.call(hit.task, globalPosition);
    }
  }

  /// Mouse hover handler. Updates the cursor, manages tooltips, and detects
  /// hovering over empty space for task creation.
  void onHover(PointerHoverEvent details) {
    if (syncClient != null && _showRemoteCursors) {
      final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);
      if (rowId != null && time != null) {
        _sendCursorMove(time, rowId);
      }
    }

    final hit = _getTaskPartAtPosition(details.localPosition);
    final hoveredTask = hit?.task;

    MouseCursor newCursor = SystemMouseCursors.basic;

    if (_currentTool == GanttTool.select) {
      newCursor = SystemMouseCursors.cell; // Use cell cursor for selection mode

      if (hit != null) {
        newCursor = SystemMouseCursors.click;
      }

      _clearEmptySpaceHover();
    } else if (_currentTool == GanttTool.draw) {
      newCursor = SystemMouseCursors.precise; // Pencil-like cursor
      if (onEmptySpaceClick != null || onTaskDrawEnd != null) {
        _clearEmptySpaceHover();
      }
    } else {
      if (hit != null) {
        switch (hit.part) {
          case TaskPart.startHandle:
          case TaskPart.endHandle:
            if (enableResize) newCursor = SystemMouseCursors.resizeLeftRight;
            break;
          case TaskPart.body:
            if (enableDragAndDrop) newCursor = SystemMouseCursors.move;
            break;
        }
      } else if (onEmptySpaceClick != null) {
        final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);

        if (rowId != null && time != null) {
          final day = DateTime(time.year, time.month, time.day);
          if (_hoveredRowId != rowId || _hoveredDate != day) {
            _hoveredRowId = rowId;
            _hoveredDate = day;
            newCursor = SystemMouseCursors.click;
            if (!isDisposed) notifyListeners();
          }
        } else {
          _clearEmptySpaceHover();
        }
      } else {
        _clearEmptySpaceHover();
      }
    }

    if (_cursor != newCursor) {
      _cursor = newCursor;
      if (!isDisposed) notifyListeners();
    }

    if (onTaskHover != null) {
      if (hoveredTask != null) {
        onTaskHover!(hoveredTask, details.position);
      } else if (_lastHoveredTaskId != null) {
        onTaskHover!(null, details.position);
      }
      _lastHoveredTaskId = hoveredTask?.id;
    }
  }

  /// Mouse exit handler. Resets hover state and cursor.
  void onHoverExit(PointerExitEvent event) {
    _clearEmptySpaceHover();
    if (_cursor != SystemMouseCursors.basic) {
      _cursor = SystemMouseCursors.basic;
      notifyListeners();
    }
    if (onTaskHover != null && _lastHoveredTaskId != null) {
      onTaskHover!(null, event.position);
      _lastHoveredTaskId = null;
    }
  }

  void _clearEmptySpaceHover() {
    if (_hoveredRowId != null || _hoveredDate != null) {
      _hoveredRowId = null;
      _hoveredDate = null;
      if (!isDisposed) notifyListeners();
    }
  }

  /// Sets the currently focused task and notifies listeners to rebuild.
  void setFocusedTask(String? taskId) {
    if (_focusedTaskId != taskId) {
      _focusedTaskId = taskId;
      onFocusChange?.call(taskId);
      _scrollToFocusedTask();
      if (!isDisposed) notifyListeners();
    }
  }

  /// Converts a pixel offset on the canvas to a row ID and a precise DateTime.
  /// Returns `(null, null)` if the position is outside the valid row area.
  (String?, DateTime?) _getRowAndTimeAtPosition(Offset localPosition) {
    if (localPosition.dy < timeAxisHeight) {
      return (null, null);
    }

    final pointerYRelativeToBarsArea = localPosition.dy - timeAxisHeight - _translateY;

    final rowIndex = _findRowIndex(pointerYRelativeToBarsArea);

    if (rowIndex == -1) return (null, null);

    final rowId = visibleRows[rowIndex].id;

    final totalDomainDurationMs =
        (_totalDomain.last.millisecondsSinceEpoch - _totalDomain.first.millisecondsSinceEpoch).toDouble();
    if (totalDomainDurationMs <= 0 || _width <= 0) return (rowId, null);

    final timeRatio = localPosition.dx / _width;
    final timeMs = _totalDomain.first.millisecondsSinceEpoch + (totalDomainDurationMs * timeRatio);
    final time = DateTime.fromMillisecondsSinceEpoch(timeMs.round());

    return (rowId, time);
  }

  void _updateSelectionFromRect(Rect rect) {
    if (visibleRows.isEmpty) return;

    final newSelection = <String>{};
    double currentTop = 0.0;

    for (final row in visibleRows) {
      final int stackDepth = rowMaxStackDepth[row.id] ?? 1;
      final double rowHeightTotal = rowHeight * stackDepth;
      final double rowTop = currentTop;
      final double rowBottom = rowTop + rowHeightTotal;

      if (rect.top < rowBottom && rect.bottom > rowTop) {
        final tasksInRow =
            data.where((t) => t.rowId == row.id && !t.isTimeRangeHighlight && !t.isOverlapIndicator && !t.isSummary);

        for (final task in tasksInRow) {
          final double taskLeft = _totalScale(task.start);
          final double taskRight = _totalScale(task.end);
          final double taskTop = rowTop + (task.stackIndex * rowHeight);
          final double taskBottom = taskTop + rowHeight;

          if (rect.left < taskRight && rect.right > taskLeft && rect.top < taskBottom && rect.bottom > taskTop) {
            newSelection.add(task.id);
          }
        }
      }

      currentTop += rowHeightTotal;
    }

    if (!_setEquals(_selectedTaskIds, newSelection)) {
      _selectedTaskIds.clear();
      _selectedTaskIds.addAll(newSelection);
      onSelectionChanged?.call(_selectedTaskIds);
    }
  }

  bool _setEquals(Set<Object> a, Set<Object> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  void _scrollToFocusedTask() {
    if (_focusedTaskId == null) return;

    final focusedTask = data.firstWhere((t) => t.id == _focusedTaskId, orElse: () => LegacyGanttTask.empty());
    if (focusedTask.id.isEmpty) return;

    final isRowVisible = visibleRows.any((r) => r.id == focusedTask.rowId);
    if (!isRowVisible) {
      onRowRequestVisible?.call(focusedTask.rowId);
      return; // Stop here. Scrolling will happen on the next frame after rebuild.
    }
    if (scrollController != null && scrollController!.hasClients) {
      final rowIndex = visibleRows.indexWhere((r) => r.id == focusedTask.rowId);
      if (rowIndex != -1) {
        final rowTop = _rowVerticalOffsets[rowIndex];
        final rowBottom = _rowVerticalOffsets[rowIndex + 1];
        final viewportHeight = scrollController!.position.viewportDimension;
        final currentOffset = scrollController!.offset;

        if (rowTop < currentOffset) {
          scrollController!.animateTo(rowTop, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        } else if (rowBottom > currentOffset + viewportHeight) {
          scrollController!.animateTo(rowBottom - viewportHeight,
              duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      }
    }

    if (ganttHorizontalScrollController != null && ganttHorizontalScrollController!.hasClients) {
      final taskStartPx = _totalScale(focusedTask.start);
      final taskEndPx = _totalScale(focusedTask.end);

      final position = ganttHorizontalScrollController!.position;
      final viewportWidth = position.viewportDimension;
      final currentOffset = position.pixels;
      final maxScroll = position.maxScrollExtent;

      double targetOffset = currentOffset;

      if (taskStartPx < currentOffset) {
        targetOffset = taskStartPx - 20; // Add some padding
      } else if (taskEndPx > currentOffset + viewportWidth) {
        targetOffset = taskEndPx - viewportWidth + 20; // Add some padding
      }

      final clampedOffset = targetOffset.clamp(0.0, maxScroll);

      if ((clampedOffset - currentOffset).abs() > 1.0) {
        ganttHorizontalScrollController!.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @visibleForTesting
  ({LegacyGanttTask task, TaskPart part})? getTaskPartAt(Offset localPosition) => _getTaskPartAtPosition(localPosition);

  /// Determines which part of which task is at a given local position.
  ///
  /// It checks for the start handle, end handle, or body of a task, respecting
  /// stacking order.
  ///
  /// This method iterates through the tasks in the tapped row and stack index, calculating
  /// their bounds and handle areas to determine if a hit occurred. It iterates in reverse
  /// order (drawing order) to ensure the topmost task is hit first.
  ///
  /// Returns a record containing the task and the part that was hit, or null if no task was hit.
  ///
  /// [localPosition] is the position of the pointer relative to the widget.
  ///
  /// Note: The visual drawing order determines which task is "on top" when checking for hits.
  /// Conflicts should ideally be resolved by z-index or a defined stacking order.
  ({LegacyGanttTask task, TaskPart part})? _getTaskPartAtPosition(Offset localPosition) {
    if (localPosition.dy < timeAxisHeight) {
      return null;
    }

    final pointerYRelativeToBarsArea = localPosition.dy - timeAxisHeight - _translateY;
    final rowIndex = _findRowIndex(pointerYRelativeToBarsArea);
    if (rowIndex == -1) return null;

    final row = visibleRows[rowIndex];
    final rowTopY = _rowVerticalOffsets[rowIndex];
    final pointerXOnTotalContent = localPosition.dx;
    final pointerYWithinRow = pointerYRelativeToBarsArea - rowTopY;
    final tappedStackIndex = max(0, (pointerYWithinRow / rowHeight).floor());
    final tasksInTappedStack = data
        .where((task) =>
            task.rowId == row.id &&
            task.stackIndex == tappedStackIndex &&
            !task.isTimeRangeHighlight &&
            !task.isOverlapIndicator)
        .toList()
        .reversed;

    for (final task in tasksInTappedStack) {
      final double barStartX = _totalScale(task.start);
      final double barEndX = _totalScale(task.end);

      if (task.isSummary && rollUpMilestones) {
        final childMilestones = data.where((t) => t.isMilestone && t.parentId == task.id);
        for (final milestone in childMilestones) {
          final double mStartX = _totalScale(milestone.start);
          final double diamondSize = rowHeight * 0.8;
          if (pointerXOnTotalContent >= mStartX && pointerXOnTotalContent <= mStartX + diamondSize) {
            return (task: milestone, part: TaskPart.body);
          }
        }
      }

      final double effectiveHandleWidth = task.id == _focusedTaskId ? resizeHandleWidth * 2 : resizeHandleWidth;
      if (task.isMilestone) {
        final double diamondSize = rowHeight * 0.8; // Matches painter's barHeightRatio
        if (pointerXOnTotalContent >= barStartX && pointerXOnTotalContent <= barStartX + diamondSize) {
          return (task: task, part: TaskPart.body);
        }
      }
      if (pointerXOnTotalContent >= barStartX - effectiveHandleWidth &&
          pointerXOnTotalContent <= barEndX + effectiveHandleWidth) {
        if (enableResize) {
          final bool onStartHandle = pointerXOnTotalContent < barStartX + effectiveHandleWidth;
          final bool onEndHandle = pointerXOnTotalContent > barEndX - effectiveHandleWidth;

          if (onStartHandle && onEndHandle && !task.isMilestone) {
            final distToStart = pointerXOnTotalContent - barStartX;
            final distToEnd = barEndX - pointerXOnTotalContent;
            return distToStart < distToEnd
                ? (task: task, part: TaskPart.startHandle)
                : (task: task, part: TaskPart.endHandle);
          } else if (onStartHandle) {
            if (!task.isMilestone) return (task: task, part: TaskPart.startHandle);
          } else if (onEndHandle) {
            if (!task.isMilestone) return (task: task, part: TaskPart.endHandle);
          }
        }
        return (task: task, part: TaskPart.body);
      }
    }
    return null;
  }

  void _handleVerticalPan(DragUpdateDetails details) {
    final newTranslateY = _initialTranslateY + (details.globalPosition.dy - _initialTouchY);
    final double contentHeight =
        visibleRows.fold<double>(0.0, (prev, row) => prev + rowHeight * (rowMaxStackDepth[row.id] ?? 1));
    final double availableHeightForBars = _height - timeAxisHeight;
    final double maxNegativeTranslateY = max(0.0, contentHeight - availableHeightForBars);
    final clampedTranslateY = min(0.0, max(-maxNegativeTranslateY, newTranslateY));

    if (_translateY == clampedTranslateY) {
      return;
    }

    setTranslateY(clampedTranslateY);
    _isScrollingInternally = true;
    scrollController?.jumpTo(-clampedTranslateY);
    WidgetsBinding.instance.addPostFrameCallback((_) => _isScrollingInternally = false);
  }

  void _handleHorizontalPan(DragUpdateDetails details) {
    final pixelDelta = details.globalPosition.dx - _dragStartGlobalX;
    final durationDelta = _pixelToDuration(pixelDelta);
    DateTime newStart = _originalTaskStart!;
    DateTime newEnd = _originalTaskEnd!;
    String tooltipText = '';
    bool showTooltip = false;

    switch (_dragMode) {
      case DragMode.move:
        newStart = _originalTaskStart!.add(durationDelta);

        if (_workCalendar != null) {
          final int workingDuration = _workCalendar!.getWorkingDuration(_originalTaskStart!, _originalTaskEnd!);

          while (!_workCalendar!.isWorkingDay(newStart)) {
            newStart = newStart.add(const Duration(days: 1));
          }

          newEnd = _workCalendar!.addWorkingDays(newStart, workingDuration);

          if (_draggedTask?.isMilestone ?? false) {
            newEnd = newStart;
          }
        } else {
          if (_draggedTask?.isMilestone ?? false) {
            newEnd = newStart;
          } else {
            newEnd = _originalTaskEnd!.add(durationDelta);
          }
        }

        if (resizeTooltipDateFormat != null || projectTimezoneOffset != null) {
          final startStr = _formatDateTimeWithTimezone(newStart);
          final endStr = _formatDateTimeWithTimezone(newEnd);
          tooltipText = 'Start:\u00A0$startStr\nEnd:\u00A0$endStr';
        } else {
          tooltipText =
              'Start:\u00A0${newStart.toLocal().toIso8601String().substring(0, 16)}\nEnd:\u00A0${newEnd.toLocal().toIso8601String().substring(0, 16)}';
        }
        showTooltip = true;
        break;
      case DragMode.resizeStart:
        newStart = _originalTaskStart!.add(durationDelta);
        if (newStart.isAfter(newEnd.subtract(const Duration(minutes: 1)))) {
          newStart = newEnd.subtract(const Duration(minutes: 1));
        }
        tooltipText = _formatDateTimeWithTimezone(newStart);
        showTooltip = true;
        break;
      case DragMode.resizeEnd:
        newEnd = _originalTaskEnd!.add(durationDelta);
        if (newEnd.isBefore(newStart.add(const Duration(minutes: 1)))) {
          newEnd = newStart.add(const Duration(minutes: 1));
        }
        tooltipText = _formatDateTimeWithTimezone(newEnd);
        showTooltip = true;
        break;
      case DragMode.none:
        break;
    }
    _ghostTaskStart = newStart;
    _ghostTaskEnd = newEnd;
    _resizeTooltipText = tooltipText;
    _showResizeTooltip = showTooltip;
    if (showTooltip) {
      if (_dragMode == DragMode.move) {
        _resizeTooltipPosition = details.localPosition.translate(0, -60);
      } else {
        _resizeTooltipPosition = details.localPosition.translate(0, -40);
      }
    }

    if (_dragMode == DragMode.move && _draggedTask != null && _selectedTaskIds.contains(_draggedTask!.id)) {
      _bulkGhostTasks.clear();
      for (final taskId in _selectedTaskIds) {
        if (taskId == _draggedTask!.id) continue;
        final task = data.firstWhere((t) => t.id == taskId, orElse: () => LegacyGanttTask.empty());
        if (task.id.isEmpty) continue;

        final taskNewStart = task.start.add(durationDelta);
        final taskNewEnd = task.isMilestone ? taskNewStart : task.end.add(durationDelta);
        _bulkGhostTasks[taskId] = (taskNewStart, taskNewEnd);
      }
    } else if (_dragMode == DragMode.move && _draggedTask != null) {
      if ((_draggedTask!.propagatesMoveToChildren || enableAutoScheduling) && _selectedTaskIds.isEmpty) {
        _bulkGhostTasks.clear();
        _propagateAutoSchedule(_draggedTask!, durationDelta);
      } else {
        _bulkGhostTasks.clear();
      }
    } else if ((_dragMode == DragMode.resizeStart || _dragMode == DragMode.resizeEnd) &&
        _draggedTask != null &&
        _draggedTask!.isSummary &&
        _draggedTask!.resizePolicy != ResizePolicy.none) {
      _bulkGhostTasks.clear();
      final policy = _draggedTask!.resizePolicy;
      final originalDuration = _originalTaskEnd!.difference(_originalTaskStart!).inMilliseconds.toDouble();
      final newDuration = newEnd.difference(newStart).inMilliseconds.toDouble();
      final children = data.where((t) => t.parentId == _draggedTask!.id);

      for (final child in children) {
        DateTime childNewStart = child.start;
        DateTime childNewEnd = child.end;

        if (policy == ResizePolicy.elastic && originalDuration > 0) {
          if (_workCalendar != null && child.usesWorkCalendar) {
            final originalParentWorkDays = _workCalendar!.getWorkingDuration(_originalTaskStart!, _originalTaskEnd!);
            final newParentWorkDays = _workCalendar!.getWorkingDuration(newStart, newEnd);

            if (originalParentWorkDays > 0) {
              final childStartWorkOffset = _workCalendar!.getWorkingDuration(_originalTaskStart!, child.start);
              final childEndWorkOffset = _workCalendar!.getWorkingDuration(_originalTaskStart!, child.end);

              final startRatio = (childStartWorkOffset / originalParentWorkDays).clamp(0.0, 1.0);
              final endRatio = (childEndWorkOffset / originalParentWorkDays).clamp(0.0, 1.0);

              final newChildStartOffset = (newParentWorkDays * startRatio).round();
              final newChildEndOffset = (newParentWorkDays * endRatio).round();

              childNewStart = _workCalendar!.addWorkingDays(newStart, newChildStartOffset);
              childNewEnd = _workCalendar!.addWorkingDays(newStart, newChildEndOffset);
            } else {
              final startRatio =
                  (child.start.difference(_originalTaskStart!).inMilliseconds.toDouble() / originalDuration)
                      .clamp(0.0, 1.0);
              final endRatio = (child.end.difference(_originalTaskStart!).inMilliseconds.toDouble() / originalDuration)
                  .clamp(0.0, 1.0);

              childNewStart = newStart.add(Duration(milliseconds: (newDuration * startRatio).round()));
              childNewEnd = newStart.add(Duration(milliseconds: (newDuration * endRatio).round()));
            }
          } else {
            final startRatio =
                (child.start.difference(_originalTaskStart!).inMilliseconds.toDouble() / originalDuration)
                    .clamp(0.0, 1.0);
            final endRatio = (child.end.difference(_originalTaskStart!).inMilliseconds.toDouble() / originalDuration)
                .clamp(0.0, 1.0);

            childNewStart = newStart.add(Duration(milliseconds: (newDuration * startRatio).round()));
            childNewEnd = newStart.add(Duration(milliseconds: (newDuration * endRatio).round()));
          }

          if (childNewStart.isBefore(newStart)) childNewStart = newStart;
          if (childNewEnd.isAfter(newEnd)) childNewEnd = newEnd;
          if (childNewEnd.isBefore(childNewStart)) childNewEnd = childNewStart;
        } else if (policy == ResizePolicy.constrain) {
          if (childNewStart.isBefore(newStart)) {
            final duration = childNewEnd.difference(childNewStart);
            childNewStart = newStart;
            childNewEnd = childNewStart.add(duration);
          }
          if (childNewEnd.isAfter(newEnd)) {
            final duration = childNewEnd.difference(childNewStart);
            childNewEnd = newEnd;
            childNewStart = childNewEnd.subtract(duration);
          }
          if (childNewStart.isBefore(newStart)) {
            childNewStart = newStart;
          }
        }
        _bulkGhostTasks[child.id] = (childNewStart, childNewEnd);
      }
    } else {
      _bulkGhostTasks.clear();
    }

    if (!isDisposed) notifyListeners();
  }

  Duration _pixelToDuration(double pixels) {
    final double totalContentWidth = _width;
    if (totalContentWidth <= 0) {
      return Duration.zero;
    }
    final totalDomainDurationMs =
        (_totalDomain.last.millisecondsSinceEpoch - _totalDomain.first.millisecondsSinceEpoch).toDouble();
    final durationMs = (pixels / totalContentWidth) * totalDomainDurationMs;
    return Duration(milliseconds: durationMs.round());
  }

  void deleteTask(LegacyGanttTask task) {
    onTaskDelete?.call(task);
    if (!isDisposed) notifyListeners();
  }

  void _handleHorizontalScroll(double deltaPixels) {
    if (totalDomain.isEmpty || _width <= 0) return;

    final durationDelta = _pixelToDuration(deltaPixels);

    if (gridMin == null || gridMax == null) {
      gridMin = _visibleExtent.first.millisecondsSinceEpoch.toDouble();
      gridMax = _visibleExtent.last.millisecondsSinceEpoch.toDouble();
    }

    double newGridMin = gridMin! + durationDelta.inMilliseconds;
    double newGridMax = gridMax! + durationDelta.inMilliseconds;

    if (totalGridMin != null && newGridMin < totalGridMin!) {
      final diff = totalGridMin! - newGridMin;
      newGridMin += diff;
      newGridMax += diff;
    }

    if (totalGridMax != null && newGridMax > totalGridMax!) {
      final diff = newGridMax - totalGridMax!;
      newGridMin -= diff;
      newGridMax -= diff;
    }

    gridMin = newGridMin;
    gridMax = newGridMax;

    _calculateDomains();
    _calculateRowOffsets();

    if (onVisibleRangeChanged != null && _visibleExtent.isNotEmpty) {
      onVisibleRangeChanged!(_visibleExtent.first, _visibleExtent.last);
    }

    if (!isDisposed) notifyListeners();
  }

  /// Handles horizontal scroll events, e.g., from a mouse wheel or trackpad.
  void onHorizontalScroll(double delta) {
    _handleHorizontalScroll(delta);
  }

  bool _wouldCreateCycle(String fromId, String toId) {
    if (fromId == toId) return true;

    final visited = <String>{};
    final queue = <String>[toId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == fromId) return true;

      if (visited.contains(current)) continue;
      visited.add(current);

      final nextSteps = dependencies.where((d) => d.predecessorTaskId == current).map((d) => d.successorTaskId);
      queue.addAll(nextSteps);
    }
    return false;
  }

  @visibleForTesting
  String formatDateTimeWithTimezoneForTest(DateTime dateTime) => _formatDateTimeWithTimezone(dateTime);

  String _formatDateTimeWithTimezone(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final localStr = resizeTooltipDateFormat != null
        ? resizeTooltipDateFormat!(localTime)
        : localTime.toIso8601String().substring(0, 16);

    if (projectTimezoneOffset != null) {
      final projectTime = dateTime.toUtc().add(projectTimezoneOffset!);
      final projectStr = resizeTooltipDateFormat != null
          ? resizeTooltipDateFormat!(projectTime)
          : projectTime.toIso8601String().substring(0, 16);

      final tzAbbr = projectTimezoneAbbreviation ?? 'Project';
      return "${localStr.replaceAll(' ', '\u00A0')}\u00A0(Local)\n${projectStr.replaceAll(' ', '\u00A0')}\u00A0($tzAbbr)";
    }

    return localStr.replaceAll(' ', '\u00A0');
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
}
