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
import 'sync/gantt_sync_client.dart';
import 'sync/crdt_engine.dart';
import 'utils/legacy_gantt_conflict_detector.dart';
import 'utils/critical_path_calculator.dart';
import 'legacy_gantt_controller.dart';

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
  List<LegacyGanttTask> get data => _tasks;

  /// The list of conflict indicators to be displayed.
  /// The list of conflict indicators to be displayed.
  List<LegacyGanttTask> conflictIndicators;

  /// The list of dependencies between tasks.
  List<LegacyGanttTaskDependency> dependencies;

  /// The list of rows currently visible in the viewport.
  /// The list of rows currently visible in the viewport.
  List<LegacyGanttRow> visibleRows;

  /// A map defining the maximum number of overlapping tasks for each row.
  /// A map defining the maximum number of overlapping tasks for each row.
  Map<String, int> rowMaxStackDepth;

  /// The height of a single task lane.
  final double rowHeight;

  /// The height of the time axis header.
  double? _axisHeight;
  double? get axisHeight => _axisHeight;

  void updateAxisHeight(double? newHeight) {
    if (_axisHeight != newHeight) {
      if (isDisposed) return;
      _axisHeight = newHeight;
      notifyListeners();
    }
  }

  /// The start of the visible time range in milliseconds since epoch.
  double? gridMin;

  /// The end of the visible time range in milliseconds since epoch.
  double? gridMax;

  /// The start of the total time range in milliseconds since epoch.
  final double? totalGridMin;

  /// The end of the total time range in milliseconds since epoch.
  final double? totalGridMax;

  /// Whether tasks can be moved by dragging.
  final bool enableDragAndDrop;

  /// Whether tasks can be resized from their start or end handles.
  final bool enableResize;

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

  /// The synchronization client for multiplayer features.
  final GanttSyncClient? syncClient;

  /// The CRDT engine for merging operations.
  final CRDTEngine _crdtEngine = CRDTEngine();

  /// A function to group tasks for conflict detection.
  /// If provided, conflict detection will be run when tasks are updated via sync.
  final Object? Function(LegacyGanttTask task)? taskGrouper;

  StreamSubscription<Operation>? _syncSubscription;

  // --- Remote Cursor State ---
  final Map<String, RemoteCursor> _remoteCursors = {};
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

  // --- Remote Ghost State ---
  final Map<String, RemoteGhost> _remoteGhosts = {};
  Map<String, RemoteGhost> get remoteGhosts => Map.unmodifiable(_remoteGhosts);

  Timer? _ghostUpdateThrottle;
  static const Duration _ghostThrottleDuration = Duration(milliseconds: 50);

  void _sendGhostUpdate(String taskId, DateTime start, DateTime end) {
    if (syncClient == null) return;
    if (_ghostUpdateThrottle?.isActive ?? false) return;

    _ghostUpdateThrottle = Timer(_ghostThrottleDuration, () {
      syncClient!.sendOperation(Operation(
        type: 'GHOST_UPDATE',
        data: {
          'taskId': taskId,
          'start': start.millisecondsSinceEpoch,
          'end': end.millisecondsSinceEpoch,
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'me', // SyncClient will likely overwrite this, but good to have
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
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'me',
      ));
    }
  }

  void _handleRemoteGhostUpdate(Map<String, dynamic> data, String actorId) {
    final actualData = data.containsKey('data') && data['data'] is Map ? data['data'] : data;
    final taskId = actualData['taskId'] as String?;
    final startMs = actualData['start'] as int?;
    final endMs = actualData['end'] as int?;

    if (taskId != null) {
      if (startMs == null || endMs == null) {
        // Clear task drag part of ghost, but keep presence
        if (_remoteGhosts.containsKey(actorId)) {
          final existing = _remoteGhosts[actorId]!;
          _remoteGhosts[actorId] = RemoteGhost(
            userId: actorId,
            taskId: '',
            lastUpdated: DateTime.now(),
            viewportStart: existing.viewportStart,
            viewportEnd: existing.viewportEnd,
            verticalScrollOffset: existing.verticalScrollOffset,
            userName: existing.userName,
            userColor: existing.userColor,
          );
        }
      } else {
        // Update ghost with drag info
        final existing = _remoteGhosts[actorId];
        _remoteGhosts[actorId] = RemoteGhost(
          userId: actorId,
          taskId: taskId,
          start: DateTime.fromMillisecondsSinceEpoch(startMs),
          end: DateTime.fromMillisecondsSinceEpoch(endMs),
          lastUpdated: DateTime.now(),
          viewportStart: existing?.viewportStart,
          viewportEnd: existing?.viewportEnd,
          verticalScrollOffset: existing?.verticalScrollOffset,
          userName: existing?.userName,
          userColor: existing?.userColor,
        );
      }

      if (!isDisposed) notifyListeners();
    }
  }

  void _handlePresenceUpdate(Map<String, dynamic> data, String actorId) {
    if (isDisposed) return;
    final actualData = data.containsKey('data') && data['data'] is Map ? data['data'] : data;
    final viewportStartMs = actualData['viewportStart'] as int?;
    final viewportEndMs = actualData['viewportEnd'] as int?;
    final scrollOffset = (actualData['verticalScrollOffset'] as num?)?.toDouble();
    final name = actualData['userName'] as String?;
    final color = actualData['userColor'] as String?;

    final existing = _remoteGhosts[actorId];
    _remoteGhosts[actorId] = RemoteGhost(
      userId: actorId,
      taskId: existing?.taskId ?? '',
      start: existing?.start,
      end: existing?.end,
      lastUpdated: DateTime.now(),
      viewportStart:
          viewportStartMs != null ? DateTime.fromMillisecondsSinceEpoch(viewportStartMs) : existing?.viewportStart,
      viewportEnd: viewportEndMs != null ? DateTime.fromMillisecondsSinceEpoch(viewportEndMs) : existing?.viewportEnd,
      verticalScrollOffset: scrollOffset ?? existing?.verticalScrollOffset,
      userName: name ?? existing?.userName,
      userColor: color ?? existing?.userColor,
    );
    notifyListeners();
  }

  void _handleRemoteCursorMove(Map<String, dynamic> data, String actorId) {
    final actualData = data.containsKey('data') && data['data'] is Map ? data['data'] : data;
    final timeMs = actualData['time'] as int?;
    final rowId = actualData['rowId'] as String?;

    if (timeMs != null && rowId != null) {
      final time = DateTime.fromMillisecondsSinceEpoch(timeMs);
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
    this.gridMin,
    this.gridMax,
    this.totalGridMin,
    this.totalGridMax,
    this.enableDragAndDrop = false,
    this.enableResize = false,
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
  })  : _tasks = List.from(data),
        _axisHeight = axisHeight {
    // 1. Pre-calculate row offsets immediately
    _focusedTaskId = initialFocusedTaskId;
    _calculateRowOffsets();

    if (scrollController != null && scrollController!.hasClients) {
      _translateY = -scrollController!.offset;
    }
    scrollController?.addListener(_onExternalScroll);
    ganttHorizontalScrollController?.addListener(_onHorizontalScrollControllerUpdate);

    if (syncClient != null) {
      _syncSubscription = syncClient!.operationStream.listen((op) {
        if (isDisposed) return;
        if (op.type == 'INSERT_DEPENDENCY') {
          final data = op.data;
          final typeStr = data['type'] as String? ?? 'finishToStart';
          final depType =
              DependencyType.values.firstWhere((e) => e.name == typeStr, orElse: () => DependencyType.finishToStart);
          final newDep = LegacyGanttTaskDependency(
            predecessorTaskId: data['predecessorTaskId'],
            successorTaskId: data['successorTaskId'],
            type: depType,
          );
          if (!dependencies.contains(newDep)) {
            dependencies = List.from(dependencies)..add(newDep);
            onDependencyAdd?.call(newDep);
            _recalculateCriticalPath();
            notifyListeners();
          }
        } else if (op.type == 'DELETE_DEPENDENCY') {
          final data = op.data;
          final pred = data['predecessorTaskId'];
          final succ = data['successorTaskId'];
          final initialLen = dependencies.length;
          dependencies =
              dependencies.where((d) => !(d.predecessorTaskId == pred && d.successorTaskId == succ)).toList();
          if (dependencies.length != initialLen) {
            notifyListeners();
          }
        } else if (op.type == 'CLEAR_DEPENDENCIES') {
          final taskId = op.data['taskId'];
          if (taskId != null) {
            final initialLen = dependencies.length;
            dependencies =
                dependencies.where((d) => d.predecessorTaskId != taskId && d.successorTaskId != taskId).toList();
            if (dependencies.length != initialLen) {
              notifyListeners();
            }
          }
        } else if (op.type == 'RESET_DATA') {
          dependencies = [];
          _tasks.clear();
          conflictIndicators = [];
          // Force repaint/recalculate
          _calculateDomains();
          notifyListeners();
        } else if (op.type == 'CURSOR_MOVE') {
          _handleRemoteCursorMove(op.data, op.actorId);
        } else if (op.type == 'GHOST_UPDATE') {
          _handleRemoteGhostUpdate(op.data, op.actorId);
        } else if (op.type == 'PRESENCE_UPDATE') {
          _handlePresenceUpdate(op.data, op.actorId);
        } else {
          _tasks = _crdtEngine.mergeTasks(_tasks, [op]);
          if (taskGrouper != null) {
            final conflicts = LegacyGanttConflictDetector().run(
              tasks: _tasks,
              taskGrouper: taskGrouper!,
            );
            conflictIndicators = conflicts;
          }
          _calculateDomains(); // Recalculate domains as data changed
          _recalculateCriticalPath();
          notifyListeners();
        }
      });
    }
  }

  // Internal State

  void updateResizeTooltipDateFormat(String Function(DateTime)? newFormat) {
    if (resizeTooltipDateFormat != newFormat) {
      resizeTooltipDateFormat = newFormat;
      if (!isDisposed) notifyListeners();
    }
  }

  /// Updates the list of dependencies and notifies listeners to trigger a repaint.
  void updateData(List<LegacyGanttTask> data) {
    if (!listEquals(_tasks, data)) {
      if (isDisposed) return;
      _tasks = data;
      // Recalculate domains as data changed
      _calculateDomains();
      _recalculateCriticalPath();
      notifyListeners();
    }
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
      // updateDependencies is intended to reflect external state changes (e.g. from DB)
      // It should NOT automatically generate sync operations, as that leads to feedback loops.
      // Operations are generated by explicit user actions (addDependency, removeDependency).

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
      // Send single operation
      syncClient!.sendOperation(Operation(
        type: 'CLEAR_DEPENDENCIES',
        data: {'taskId': task.id},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'user',
      ));
    }

    if (changed) {
      _recalculateCriticalPath();
      notifyListeners();
    }
  }

  void _sendCursorMove(DateTime time, String rowId) {
    if (syncClient == null) return;

    // THROTTLING: Only send updates every 100ms to allow GC to keep up and reduce network traffic
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
      timestamp: DateTime.now().millisecondsSinceEpoch,
      actorId: 'user',
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
      },
      timestamp: DateTime.now().millisecondsSinceEpoch,
      actorId: 'user',
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
  Map<String, (DateTime, DateTime)> get bulkGhostTasks => _bulkGhostTasks;
  DragMode _dragMode = DragMode.none;
  PanType _panType = PanType.none;
  double _dragStartGlobalX = 0.0;
  DateTime? _originalTaskStart;
  DateTime? _originalTaskEnd;
  MouseCursor _cursor = SystemMouseCursors.basic;
  // New state for resize tooltip
  bool _showResizeTooltip = false;
  String _resizeTooltipText = '';
  Offset _resizeTooltipPosition = Offset.zero;
  String? _hoveredRowId;
  DateTime? _hoveredDate;
  String? _focusedTaskId;

  // Dependency Drawing State
  String? _dependencyStartTaskId;
  TaskPart? _dependencyStartSide;
  Offset? _currentDragPosition;
  String? _dependencyHoveredTaskId;

  String? get dependencyStartTaskId => _dependencyStartTaskId;
  TaskPart? get dependencyStartSide => _dependencyStartSide;
  Offset? get currentDragPosition => _currentDragPosition;
  String? get dependencyHoveredTaskId => _dependencyHoveredTaskId;

  // Add this list to your class properties to cache row positions
  List<double> _rowVerticalOffsets = [];
  double _totalContentHeight = 0;

  // Critical Path State
  bool _showCriticalPath = false;
  Set<String> _criticalTaskIds = {};
  Set<LegacyGanttTaskDependency> _criticalDependencies = {};
  Map<String, CpmTaskStats> _cpmStats = {};

  bool get showCriticalPath => _showCriticalPath;
  Set<String> get criticalTaskIds => _criticalTaskIds;
  Set<LegacyGanttTaskDependency> get criticalDependencies => _criticalDependencies;
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
    if (!_showCriticalPath) return;

    // Run calculation in a microtask or compute isolate if needed for performance.
    // For now, run synchronously.
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
  Rect? get selectionRect => _selectionRect;

  /// The IDs of the currently selected tasks.
  final Set<String> _selectedTaskIds = {};
  Set<String> get selectedTaskIds => Set.unmodifiable(_selectedTaskIds);

  /// Sets the current tool.
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

    // The rect is in local widget coordinates. We need to convert it to "content" coordinates
    // used by the tasks (which are laid out relative to timeAxisHeight).
    // Also consider the scroll offset (_translateY).
    // Content Y = 0 matches Screen Y = timeAxisHeight + _translateY.
    // Screen Y = Content Y + timeAxisHeight + _translateY.
    // Content Y = Screen Y - timeAxisHeight - _translateY.
    final contentRect = rect.shift(Offset(0, -timeAxisHeight - _translateY));

    // Optimize: Pre-calculate map if needed, but linear scan is fine for typical N.
    // We only check tasks in visible rows to be safe? Or all?
    // "Select" usually means "visual selection", so selecting visible is prioritized.
    // But if we want to select *everything* in the box even if hidden?
    // No, if they are hidden (collapsed parent), they have no Y position.
    // So we iterate `visibleRows`.

    final visibleRowIndices = {for (var i = 0; i < visibleRows.length; i++) visibleRows[i].id: i};

    for (final task in data) {
      final rowIndex = visibleRowIndices[task.rowId];
      if (rowIndex == null) continue;

      // Check task intersection
      final rowTop = _rowVerticalOffsets[rowIndex];
      final top = rowTop + (task.stackIndex * rowHeight);
      final bottom = top + rowHeight;

      // Optimization: Check Y overlap first
      if (contentRect.top > bottom || contentRect.bottom < top) continue;

      final startX = _totalScale(task.start);
      final endX = _totalScale(task.end);

      final taskRect = Rect.fromLTRB(startX, top, endX, bottom);

      if (contentRect.overlaps(taskRect)) {
        _selectedTaskIds.add(task.id);
      }
    }
  }

  // Let's defer exact selection logic to the View or Helper, or implement basic time-range overlap here.
  // 1. Calculate time range from rect.left / rect.right
  // 2. Calculate row range from rect.top / rect.bottom

  // Actually, we can do this in the `onPanUpdate` equivalent for selection later.
  // For now just storing the rect.

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
    }

    // Fix for scroll synchronization issue:
    // When the grid collapses rows, the scroll controller's offset might change (clamped by the new smaller extent).
    // However, this view model might not receive the notification immediately if the listener hasn't fired yet
    // or if the timing is off. We force a check here.
    if (scrollController != null && scrollController!.hasClients) {
      // Safely get the offset. If attached to multiple views (e.g. during transition or complex grids),
      // pick the first one or avoid throwing.
      double? currentControllerOffset;
      if (scrollController!.positions.length == 1) {
        currentControllerOffset = scrollController!.offset;
      } else if (scrollController!.positions.isNotEmpty) {
        currentControllerOffset = scrollController!.positions.first.pixels;
      }

      if (currentControllerOffset != null) {
        // _translateY should be negative of the scroll offset.
        // We use a small epsilon for float comparison.
        if ((_translateY - (-currentControllerOffset)).abs() > 0.1) {
          // Schedule the update to avoid "setState during build" or similar issues,
          // although setTranslateY just notifies listeners.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController != null && scrollController!.hasClients) {
              // Re-check safely inside the callback
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
      // Recalculate domains and scales based on the new visible range.
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
    // Store the final bottom edge as the last element
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
    // Check if the found index is correct
    if (result != -1 && y >= _rowVerticalOffsets[result] && y < _rowVerticalOffsets[result + 1]) {
      return result;
    }
    // Fallback for edge cases, though the above should be sufficient.
    // A simple binary search for the insertion point is also an option.
    // For now, let's refine the loop.
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

    // Calculate start time based on scroll offset
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
    if (gridMin != null && gridMax != null) {
      _visibleExtent = [
        DateTime.fromMillisecondsSinceEpoch(gridMin!.toInt()),
        DateTime.fromMillisecondsSinceEpoch(gridMax!.toInt()),
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

    // Override visibleExtent if using horizontal scroll controller
    if (ganttHorizontalScrollController != null && ganttHorizontalScrollController!.hasClients) {
      _updateVisibleExtentFromScroll();
    }
  }

  /// Gesture handler for the start of a pan gesture. Determines if the pan is
  /// for vertical scrolling, moving a task, or resizing a task.
  // --- Single Axis Gesture Handlers (Preferred) ---

  void onHorizontalPanStart(DragStartDetails details) {
    if (_panType != PanType.none) return;

    // Perform hit test for task
    final hit = _getTaskPartAtPosition(details.localPosition);
    if (hit != null) {
      _panType = PanType.horizontal;
      _initialTranslateY = _translateY;
      _initialTouchY = details.globalPosition.dy;
      _dragStartGlobalX = details.globalPosition.dx;

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
      // If we didn't hit a task, we can still pan the chart horizontally
      _panType = PanType.horizontal;
      _initialTranslateY = _translateY;
      _initialTouchY = details.globalPosition.dy;
      _dragStartGlobalX = details.globalPosition.dx;
      _dragMode = DragMode.none;
      // We don't sent _draggedTask, so we know it's a pan operation
      if (!isDisposed) notifyListeners();
    }
  }

  void onHorizontalPanUpdate(DragUpdateDetails details) {
    if (_panType == PanType.vertical) return;
    // If we haven't locked yet (e.g. somehow skipped start), try to lock if we have a task or just pan
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
        // Panning the view (scrolling)
        // Delta is purely from the update event for smoother scrolling if we accumulate,
        // but here we are using delta from start.
        // Better to use details.delta for incremental updates to avoid state management issues
        // with "start position". OR strictly use the diff from drag start.
        // Existing logic for tasks uses start position. Let's stick to details.delta for panning view
        // as it is more continuous.
        _handleHorizontalScroll(-details.delta.dx);
      }
    }
  }

  void onHorizontalPanEnd(DragEndDetails details) {
    if (_panType == PanType.horizontal) {
      // Execute existing finish logic
      if (_draggedTask != null) {
        _clearGhostUpdate(_draggedTask!.id);
      }
      if (_draggedTask != null && _ghostTaskStart != null && _ghostTaskEnd != null) {
        if (syncClient != null) {
          final op = Operation(
            type: 'UPDATE_TASK',
            data: {
              'id': _draggedTask!.id,
              'start': _ghostTaskStart!.toIso8601String(),
              'end': _ghostTaskEnd!.toIso8601String(),
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            actorId: 'user',
          );

          syncClient!.sendOperation(op);
          _tasks = _crdtEngine.mergeTasks(_tasks, [op]);

          if (taskGrouper != null) {
            final conflicts = LegacyGanttConflictDetector().run(
              tasks: _tasks,
              taskGrouper: taskGrouper!,
            );
            conflictIndicators = conflicts;
            if (!isDisposed) notifyListeners();
          }

          // Always notify parent app of updates, even in sync mode.
          // This allows for local persistence or other side effects.
          onTaskUpdate?.call(_draggedTask!, _ghostTaskStart!, _ghostTaskEnd!);
        } else {
          // Local mode: Optimistically update internal state to prevent "snap back"
          final updatedTask = _draggedTask!.copyWith(
            start: _ghostTaskStart,
            end: _ghostTaskEnd,
          );

          final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
          if (index != -1) {
            _tasks[index] = updatedTask;

            // Recalculate conflicts locally if needed
            if (taskGrouper != null) {
              final conflicts = LegacyGanttConflictDetector().run(
                tasks: _tasks,
                taskGrouper: taskGrouper!,
              );
              conflictIndicators = conflicts;
            }
            // Notify listeners to show the change immediately
            notifyListeners();
          }

          // Then persist the change via callback
          onTaskUpdate?.call(_draggedTask!, _ghostTaskStart!, _ghostTaskEnd!);
        }
      }
    }
    _commitBulkUpdates();
    _resetDragState();
  }

  void _commitBulkUpdates() {
    if (_bulkGhostTasks.isEmpty) return;

    bool localStateChanged = false;

    for (final entry in _bulkGhostTasks.entries) {
      final taskId = entry.key;
      final (newStart, newEnd) = entry.value;
      // Use _allGanttTasks or data to find the current state of the task
      final task = data.firstWhere((t) => t.id == taskId, orElse: () => LegacyGanttTask.empty());
      if (task.id.isEmpty) continue;

      if (syncClient != null) {
        final op = Operation(
            type: 'UPDATE_TASK',
            data: {
              'id': taskId,
              'start': newStart.toIso8601String(),
              'end': newEnd.toIso8601String(),
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
            actorId: 'user');
        syncClient!.sendOperation(op);
        _tasks = _crdtEngine.mergeTasks(_tasks, [op]);
      } else {
        final updatedTask = task.copyWith(start: newStart, end: newEnd);
        final index = _tasks.indexWhere((t) => t.id == taskId);
        if (index != -1) {
          _tasks[index] = updatedTask;
          localStateChanged = true;
        }
      }
      // Notify parent app
      onTaskUpdate?.call(task, newStart, newEnd);
    }

    // Recalculate conflicts if needed (mainly for local mode)
    if (localStateChanged && taskGrouper != null) {
      final conflicts = LegacyGanttConflictDetector().run(tasks: _tasks, taskGrouper: taskGrouper!);
      conflictIndicators = conflicts;
      notifyListeners();
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
    if (_panType == PanType.vertical) {
      // Momentum logic could go here
    }
    _resetDragState();
  }

  void onVerticalPanCancel() {
    _resetDragState();
  }

  void _resetDragState() {
    _draggedTask = null;
    _ghostTaskStart = null;
    _ghostTaskEnd = null;
    _bulkGhostTasks.clear(); // Clear bulk ghost tasks on reset
    _dragMode = DragMode.none;
    _panType = PanType.none;
    _showResizeTooltip = false;
    notifyListeners();
  }

  // --- Unified Handlers (Restored for backward compatibility if needed, but delegated) ---

  void onPanStart(
    DragStartDetails details, {
    LegacyGanttTask? overrideTask,
    TaskPart? overridePart,
  }) {
    // If overrides are present, this is a programmatic start (not gesture), so force horizontal logic
    if (overrideTask != null) {
      _panType = PanType.horizontal;
      _initialTranslateY = _translateY;
      _initialTouchY = details.globalPosition.dy;
      _dragStartGlobalX = details.globalPosition.dx;
      _draggedTask = overrideTask;
      _originalTaskStart = overrideTask.start;
      _originalTaskEnd = overrideTask.end;
      // Assuming move for override default
      _dragMode = DragMode.move;
      if (!isDisposed) notifyListeners();
      return;
    }

    if (_currentTool == GanttTool.select) {
      _panType = PanType.selection;
      // Adjust for header height
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
        notifyListeners();
      }
      return;
    }

    if (_currentTool == GanttTool.draw) {
      // Find row at position
      final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);
      if (rowId != null && time != null) {
        _panType = PanType.draw;
        _hoveredRowId = rowId;
        _ghostTaskStart = time;
        _ghostTaskEnd = time;
        _dragStartGlobalX = details.globalPosition.dx;
        // Optionally create a temporary "ghost" task to visualize drawing immediately?
        // For now, _ghostTaskStart/End might be enough if passed to painter.
        // But painter needs a task ID to draw ghost? Or just start/end?
        // Painter uses `draggedTaskId` + `ghostTaskStart/End`.
        // If we don't have a task ID, we might need a dummy one or update painter.
        // Let's create a dummy task for visualization if needed, or just rely on selection box style?
        // Re-using ghost bar logic requires `draggedTaskId`.
        // Let's rely on a new `drawGhost` state or just selection box logic?
        // The request says "drag to draw a task".
        // Let's try to set `_draggedTask` to a temporary dummy task.
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

    // Otherwise heuristic based - this is risky with conflicting recognizers.
    // We'll leave it simple:
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
        // Create rect from initial point to current point
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
      // Only highlight if it's a valid target (start/end handle of DIFFERENT task)
      if (hit != null &&
          hit.task.id != _dependencyStartTaskId &&
          (hit.part == TaskPart.startHandle || hit.part == TaskPart.endHandle)) {
        _dependencyHoveredTaskId = hit.task.id;
      } else {
        _dependencyHoveredTaskId = null;
      }
      notifyListeners();
    } else if (_panType == PanType.vertical) {
      onVerticalPanUpdate(details);
    } else {
      // Heuristic
      if (details.delta.dx.abs() > details.delta.dy.abs()) {
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
          // Determine dependency type
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

          // TODO: Add cycle detection here

          if (!_wouldCreateCycle(_dependencyStartTaskId!, hit.task.id)) {
            final newDep = LegacyGanttTaskDependency(
              predecessorTaskId: _dependencyStartTaskId!,
              successorTaskId: hit.task.id,
              type: type,
            );
            // Notify listener (if provided) or update local list?
            // The logic from `addDependency` was:
            // if (onDependencyAdd != null) onDependencyAdd!(newDep);
            // else _dependencies.add(newDep); notifyListeners();
            //
            // But existing addDependency call does:
            // addDependency(newDep); (Method on VM?)
            // Yes, I verified LegacyGanttViewModel has addDependency.
            addDependency(newDep);
          }
        }
      }
      _panType = PanType.none;
      _dependencyStartTaskId = null;
      _dependencyStartSide = null;
      _currentDragPosition = null;
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

    // If in select mode, handle selection logic
    if (_currentTool == GanttTool.select) {
      final hit = _getTaskPartAtPosition(localPosition);
      if (hit != null) {
        // Toggle selection for this task
        if (_selectedTaskIds.contains(hit.task.id)) {
          _selectedTaskIds.remove(hit.task.id);
        } else {
          _selectedTaskIds.add(hit.task.id);
        }
        notifyListeners();
        // Also notify listener if needed?
        // For now, internal selection state is what prevents drag,
        // but external controller might want to know.
        // There is no `onSelectionChanged` callback exposed to VM yet?
        // The controller has `selectedTaskIds` getter.
        // We might need to sync back to Validatable or just rely on Controller polling?
        // Actually, the widget syncs selection FROM controller? No, controller has `selectedTaskIds`.
        // The VM has `_selectedTaskIds`. They need to sync.
        // But `LegacyGanttChartWidget` doesn't seem to sync selection change UP to controller?
        // Let's look at `LegacyGanttContent`.

        // Actually, let's just NOT trigger onEmptySpaceClick if select mode.
        // Notify listener if available
        onSelectionChanged?.call(_selectedTaskIds);
      } else {
        // Clicked empty space in select mode -> Clear selection
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
    // Sync cursor position
    if (syncClient != null && _showRemoteCursors) {
      final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);
      if (rowId != null && time != null) {
        _sendCursorMove(time, rowId);
      }
    }

    final hit = _getTaskPartAtPosition(details.localPosition);
    final hoveredTask = hit?.task;

    MouseCursor newCursor = SystemMouseCursors.basic;

    // DIFFERENT LOGIC FOR SELECTION TOOL
    if (_currentTool == GanttTool.select) {
      newCursor = SystemMouseCursors.cell; // Use cell cursor for selection mode

      // If hovering a task, show click to indicate selectable
      if (hit != null) {
        newCursor = SystemMouseCursors.click;
      }

      // Clear any empty space hover highlight from move mode
      _clearEmptySpaceHover();
    } else if (_currentTool == GanttTool.draw) {
      newCursor = SystemMouseCursors.precise; // Pencil-like cursor
      if (onEmptySpaceClick != null || onTaskDrawEnd != null) {
        // We still want to identify row for potential drawing, but suppress the visual "+" icon?
        // The user request said "prevent the emptySpaceIcon from being populated".
        // We can do this by NOT setting _hoveredRowId/_hoveredDate for the purpose of the icon,
        // OR by updating the painter to check the tool.
        // Clearing it here is safest for "no icon".
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
        // No task was hit, check for empty space.
        final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);

        if (rowId != null && time != null) {
          // Snap time to the start of the day for the highlight box
          final day = DateTime(time.year, time.month, time.day);
          if (_hoveredRowId != rowId || _hoveredDate != day) {
            _hoveredRowId = rowId;
            _hoveredDate = day;
            newCursor = SystemMouseCursors.click;
            if (!isDisposed) notifyListeners();
          }
        } else {
          // Hovering over dead space or feature is disabled
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

    // Adjust Y to be relative to the scrollable content
    final pointerYRelativeToBarsArea = localPosition.dy - timeAxisHeight - _translateY;

    // FAST LOOKUP: Use binary search instead of iterating
    final rowIndex = _findRowIndex(pointerYRelativeToBarsArea);

    if (rowIndex == -1) return (null, null);

    final rowId = visibleRows[rowIndex].id;

    // Find time by inverting the scale function (Unchanged logic)
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

      // Check if row vertically intersects the selection rect
      if (rect.top < rowBottom && rect.bottom > rowTop) {
        // Row is involved. Check its tasks.
        final tasksInRow =
            data.where((t) => t.rowId == row.id && !t.isTimeRangeHighlight && !t.isOverlapIndicator && !t.isSummary);

        for (final task in tasksInRow) {
          // Calculate task geometry
          final double taskLeft = _totalScale(task.start);
          final double taskRight = _totalScale(task.end);
          final double taskTop = rowTop + (task.stackIndex * rowHeight);
          final double taskBottom = taskTop + rowHeight;

          // Check intersection
          // Note: rect.left/right are X coordinates.
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
      // Notify controller if needed
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

    // Check if the task's row is currently visible. If not, its parent is collapsed.
    final isRowVisible = visibleRows.any((r) => r.id == focusedTask.rowId);
    if (!isRowVisible) {
      // Request the parent widget to make this row visible by expanding its parent.
      onRowRequestVisible?.call(focusedTask.rowId);
      return; // Stop here. Scrolling will happen on the next frame after rebuild.
    }
    // --- Vertical Scrolling ---
    if (scrollController != null && scrollController!.hasClients) {
      final rowIndex = visibleRows.indexWhere((r) => r.id == focusedTask.rowId);
      if (rowIndex != -1) {
        final rowTop = _rowVerticalOffsets[rowIndex];
        final rowBottom = _rowVerticalOffsets[rowIndex + 1];
        final viewportHeight = scrollController!.position.viewportDimension;
        final currentOffset = scrollController!.offset;

        if (rowTop < currentOffset) {
          // Row is above the viewport, scroll up.
          scrollController!.animateTo(rowTop, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        } else if (rowBottom > currentOffset + viewportHeight) {
          // Row is below the viewport, scroll down.
          scrollController!.animateTo(rowBottom - viewportHeight,
              duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      }
    }

    // --- Horizontal Scrolling ---
    if (ganttHorizontalScrollController != null && ganttHorizontalScrollController!.hasClients) {
      final taskStartPx = _totalScale(focusedTask.start);
      final taskEndPx = _totalScale(focusedTask.end);

      final position = ganttHorizontalScrollController!.position;
      final viewportWidth = position.viewportDimension;
      final currentOffset = position.pixels;
      final maxScroll = position.maxScrollExtent;

      double targetOffset = currentOffset;

      if (taskStartPx < currentOffset) {
        // Task starts before the visible area, scroll left.
        targetOffset = taskStartPx - 20; // Add some padding
      } else if (taskEndPx > currentOffset + viewportWidth) {
        // Task ends after the visible area, scroll right.
        targetOffset = taskEndPx - viewportWidth + 20; // Add some padding
      }

      // Clamp the target offset to valid scroll bounds.
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

      // If this task is focused, the hit area for its handles should be larger
      // to account for the externally drawn handles.
      final double effectiveHandleWidth = task.id == _focusedTaskId ? resizeHandleWidth * 2 : resizeHandleWidth;
      if (task.isMilestone) {
        final double diamondSize = rowHeight * 0.8; // Matches painter's barHeightRatio
        if (pointerXOnTotalContent >= barStartX && pointerXOnTotalContent <= barStartX + diamondSize) {
          return (task: task, part: TaskPart.body);
        }
      }
      // Check if the pointer is within the task's bounds, including the potentially larger handle areas.
      if (pointerXOnTotalContent >= barStartX - effectiveHandleWidth &&
          pointerXOnTotalContent <= barEndX + effectiveHandleWidth) {
        if (enableResize) {
          final bool onStartHandle = pointerXOnTotalContent < barStartX + effectiveHandleWidth;
          final bool onEndHandle = pointerXOnTotalContent > barEndX - effectiveHandleWidth;

          if (onStartHandle && onEndHandle && !task.isMilestone) {
            // Overlapping handles (short task), pick the closest one.
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
        if (_draggedTask?.isMilestone ?? false) {
          newEnd = newStart;
        } else {
          newEnd = _originalTaskEnd!.add(durationDelta);
        }

        if (resizeTooltipDateFormat != null) {
          final startStr = resizeTooltipDateFormat!(newStart).replaceAll(' ', '\u00A0');
          final endStr = resizeTooltipDateFormat!(newEnd).replaceAll(' ', '\u00A0');
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
        tooltipText = (resizeTooltipDateFormat != null
                ? resizeTooltipDateFormat!(newStart)
                : newStart.toLocal().toIso8601String().substring(0, 16))
            .replaceAll(' ', '\u00A0');
        showTooltip = true;
        break;
      case DragMode.resizeEnd:
        newEnd = _originalTaskEnd!.add(durationDelta);
        if (newEnd.isBefore(newStart.add(const Duration(minutes: 1)))) {
          newEnd = newStart.add(const Duration(minutes: 1));
        }
        tooltipText = (resizeTooltipDateFormat != null
                ? resizeTooltipDateFormat!(newEnd)
                : newEnd.toLocal().toIso8601String().substring(0, 16))
            .replaceAll(' ', '\u00A0');
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
      // Offset the tooltip to appear slightly above the cursor.
      if (_dragMode == DragMode.move) {
        // For move operations, position the tooltip higher to be distinct
        // from the resize tooltips and less likely to obscure other bars.
        _resizeTooltipPosition = details.localPosition.translate(0, -60);
      } else {
        // For resize operations.
        _resizeTooltipPosition = details.localPosition.translate(0, -40);
      }
    }

    // Bulk Move Logic
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
    // If delta is positive (drag left / wheel right), we move forward in time.
    // If delta is negative (drag right / wheel left), we move backward in time.

    if (totalDomain.isEmpty || _width <= 0) return;

    final durationDelta = _pixelToDuration(deltaPixels);

    // If we update gridMin/gridMax, we effectively scroll.
    // gridMin/Max are the start/end of the visible range.

    if (gridMin == null || gridMax == null) {
      // If we are in "fit fit" mode or auto-mode (nulls), setting them
      // switches to manual control.
      gridMin = _visibleExtent.first.millisecondsSinceEpoch.toDouble();
      gridMax = _visibleExtent.last.millisecondsSinceEpoch.toDouble();
    }

    double newGridMin = gridMin! + durationDelta.inMilliseconds;
    double newGridMax = gridMax! + durationDelta.inMilliseconds;

    // Optional: Clamp to totalDomain if desired, or allow infinite scroll.
    // Usually infinite scroll or clamped to totalGridMin/Max if they are strict bounds.
    // Let's clamp if totalGridMin/Max are provided.

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
}
