import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'models/legacy_gantt_dependency.dart';
import 'models/legacy_gantt_row.dart';
import 'models/legacy_gantt_task.dart';

enum DragMode { none, move, resizeStart, resizeEnd }

enum PanType { none, vertical, horizontal }

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
  final List<LegacyGanttTask> data;

  /// The list of dependencies between tasks.
  final List<LegacyGanttTaskDependency> dependencies;

  /// The list of rows currently visible in the viewport.
  final List<LegacyGanttRow> visibleRows;

  /// A map defining the maximum number of overlapping tasks for each row.
  final Map<String, int> rowMaxStackDepth;

  /// The height of a single task lane.
  final double rowHeight;

  /// The height of the time axis header.
  final double? axisHeight;

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

  /// A callback invoked when an empty space on the chart is clicked.
  final Function(String rowId, DateTime time)? onEmptySpaceClick;

  /// A function to format the date/time shown in the resize/drag tooltip.
  String Function(DateTime)? resizeTooltipDateFormat;

  /// A builder for creating a completely custom task bar widget.
  final Widget Function(LegacyGanttTask task)? taskBarBuilder;

  /// A callback for when the mouse hovers over a task or empty space.
  final Function(LegacyGanttTask?, Offset globalPosition)? onTaskHover;

  /// The width of the resize handles at the start and end of a task bar.
  final double resizeHandleWidth;

  /// Creates an instance of [LegacyGanttViewModel].
  ///
  /// This constructor takes all the relevant properties from the
  /// [LegacyGanttChartWidget] to initialize its state. It also adds a listener
  /// to the [scrollController] if one is provided, to synchronize vertical scrolling.
  LegacyGanttViewModel({
    required this.data,
    required this.dependencies,
    required this.visibleRows,
    required this.rowMaxStackDepth,
    required this.rowHeight,
    this.axisHeight,
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
    this.onPressTask,
    this.scrollController,
    this.taskBarBuilder,
    this.resizeTooltipDateFormat,
    this.onTaskHover,
    this.resizeHandleWidth = 10.0,
  }) {
    if (scrollController != null && scrollController!.hasClients) {
      _translateY = -scrollController!.offset;
    }
    scrollController?.addListener(_onExternalScroll);
  }

  void updateResizeTooltipDateFormat(String Function(DateTime)? newFormat) {
    if (resizeTooltipDateFormat != newFormat) {
      resizeTooltipDateFormat = newFormat;
      notifyListeners();
    }
  }

  // Internal State
  double _height = 0;
  double _width = 0;
  double _translateY = 0;
  double _initialTranslateY = 0;
  double _initialTouchY = 0;
  bool _isScrollingInternally = false;
  String? _lastHoveredTaskId;
  double Function(DateTime) _totalScale = (DateTime date) => 0.0;
  List<DateTime> _totalDomain = [];
  List<DateTime> _visibleExtent = [];
  LegacyGanttTask? _draggedTask;
  DateTime? _ghostTaskStart;
  DateTime? _ghostTaskEnd;
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
  double get timeAxisHeight => axisHeight ?? _height * 0.1;

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

  /// Called by the widget to inform the view model of its available dimensions.
  /// This is crucial for calculating the time scale.
  void updateLayout(double width, double height) {
    if (_width != width || _height != height) {
      _width = width;
      _height = height;
      _calculateDomains();
    }
  }

  /// Manually sets the vertical scroll offset.
  void setTranslateY(double newTranslateY) {
    if (_translateY != newTranslateY) {
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
      notifyListeners();
    }
  }

  @override
  void dispose() {
    scrollController?.removeListener(_onExternalScroll);
    super.dispose();
  }

  void _onExternalScroll() {
    if (_isScrollingInternally) {
      return;
    }

    final newTranslateY = -scrollController!.offset;
    setTranslateY(newTranslateY);
  }

  void _calculateDomains() {
    if (gridMin != null && gridMax != null) {
      _visibleExtent = [
        DateTime.fromMillisecondsSinceEpoch(gridMin!.toInt()),
        DateTime.fromMillisecondsSinceEpoch(gridMax!.toInt()),
      ];
    } else {
      if (data.isEmpty) {
        final now = DateTime.now();
        _visibleExtent = [now.subtract(const Duration(days: 30)), now.add(const Duration(days: 30))];
      } else {
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

    // The width provided to the ViewModel is the total width of the scrollable area,
    // as calculated by the parent widget (e.g., the example app's `_calculateGanttWidth`).
    final double totalContentWidth = _width;

    if (totalDomainDurationMs > 0) {
      _totalScale = (DateTime date) {
        final double value = (date.millisecondsSinceEpoch - _totalDomain[0].millisecondsSinceEpoch).toDouble();
        return (value / totalDomainDurationMs) * totalContentWidth;
      };
    } else {
      _totalScale = (date) => 0.0;
    }
  }

  /// Gesture handler for the start of a pan gesture. Determines if the pan is
  /// for vertical scrolling, moving a task, or resizing a task.
  void onPanStart(DragStartDetails details) {
    _panType = PanType.none;
    _initialTranslateY = _translateY;
    _initialTouchY = details.globalPosition.dy;
    _dragStartGlobalX = details.globalPosition.dx;

    if (!enableDragAndDrop && !enableResize) {
      return;
    }

    final hit = _getTaskPartAtPosition(details.localPosition);
    if (hit != null) {
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
      notifyListeners();
    }
  }

  /// Gesture handler for an update to a pan gesture. Dispatches to either
  /// vertical or horizontal pan handling logic.
  void onPanUpdate(DragUpdateDetails details) {
    if (_panType == PanType.none) {
      if (_draggedTask != null && details.delta.dx.abs() > details.delta.dy.abs()) {
        _panType = PanType.horizontal;
      } else {
        _panType = PanType.vertical;
        _draggedTask = null;
        _dragMode = DragMode.none;
      }
    }

    if (_panType == PanType.vertical) {
      _handleVerticalPan(details);
    } else if (_panType == PanType.horizontal && _draggedTask != null) {
      _handleHorizontalPan(details);
    }
  }

  /// Gesture handler for the end of a pan gesture. If a task was being
  /// modified, it calls the `onTaskUpdate` callback and resets the drag state.
  void onPanEnd(DragEndDetails details) {
    if (_panType == PanType.horizontal && _draggedTask != null && _ghostTaskStart != null && _ghostTaskEnd != null) {
      onTaskUpdate?.call(_draggedTask!, _ghostTaskStart!, _ghostTaskEnd!);
    }
    _draggedTask = null;
    _ghostTaskStart = null;
    _ghostTaskEnd = null;
    _dragMode = DragMode.none;
    _panType = PanType.none;
    _showResizeTooltip = false;
    notifyListeners();
  }

  /// Gesture handler for a tap gesture. Determines if a task or empty space
  /// was tapped and invokes the appropriate callback.
  void onTapUp(TapUpDetails details) {
    final hit = _getTaskPartAtPosition(details.localPosition);
    if (hit != null) {
      onPressTask?.call(hit.task);
      return; // Don't process empty space click if a task was hit
    }

    if (onEmptySpaceClick != null) {
      final (rowId, time) = _getRowAndTimeAtPosition(details.localPosition);
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

  /// Mouse hover handler. Updates the cursor, manages tooltips, and detects
  /// hovering over empty space for task creation.
  void onHover(PointerHoverEvent details) {
    final hit = _getTaskPartAtPosition(details.localPosition);
    final hoveredTask = hit?.task;

    MouseCursor newCursor = SystemMouseCursors.basic;
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
          notifyListeners();
        }
      } else {
        // Hovering over dead space or feature is disabled
        _clearEmptySpaceHover();
      }
    } else {
      _clearEmptySpaceHover();
    }

    if (_cursor != newCursor) {
      _cursor = newCursor;
      notifyListeners();
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
      notifyListeners();
    }
  }

  /// Converts a pixel offset on the canvas to a row ID and a precise DateTime.
  /// Returns `(null, null)` if the position is outside the valid row area.
  (String?, DateTime?) _getRowAndTimeAtPosition(Offset localPosition) {
    if (localPosition.dy < timeAxisHeight) {
      return (null, null);
    }
    final pointerYRelativeToBarsArea = localPosition.dy - timeAxisHeight - _translateY;

    // Find row
    String? rowId;
    double cumulativeHeight = 0;
    for (final row in visibleRows) {
      final int stackDepth = rowMaxStackDepth[row.id] ?? 1;
      final double currentRowHeight = rowHeight * stackDepth;
      if (pointerYRelativeToBarsArea >= cumulativeHeight &&
          pointerYRelativeToBarsArea < cumulativeHeight + currentRowHeight) {
        rowId = row.id;
        break;
      }
      cumulativeHeight += currentRowHeight;
    }

    if (rowId == null) return (null, null);

    // Find time by inverting the scale function
    final totalDomainDurationMs =
        (_totalDomain.last.millisecondsSinceEpoch - _totalDomain.first.millisecondsSinceEpoch).toDouble();
    if (totalDomainDurationMs <= 0 || _width <= 0) return (rowId, null);

    final timeRatio = localPosition.dx / _width;
    final timeMs = _totalDomain.first.millisecondsSinceEpoch + (totalDomainDurationMs * timeRatio);
    final time = DateTime.fromMillisecondsSinceEpoch(timeMs.round());

    return (rowId, time);
  }

  /// Determines which part of which task is at a given local position.
  ///
  /// It checks for the start handle, end handle, or body of a task, respecting
  /// stacking order.
  ({LegacyGanttTask task, TaskPart part})? _getTaskPartAtPosition(Offset localPosition) {
    if (localPosition.dy < timeAxisHeight) {
      return null;
    }
    final pointerYRelativeToBarsArea = localPosition.dy - timeAxisHeight - _translateY;
    final pointerXOnTotalContent = localPosition.dx;

    double cumulativeHeight = 0;
    for (final row in visibleRows) {
      final int stackDepth = rowMaxStackDepth[row.id] ?? 1;
      final double currentRowHeight = rowHeight * stackDepth;
      if (pointerYRelativeToBarsArea >= cumulativeHeight &&
          pointerYRelativeToBarsArea < cumulativeHeight + currentRowHeight) {
        final pointerYWithinRow = pointerYRelativeToBarsArea - cumulativeHeight;
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
          if (pointerXOnTotalContent >= barStartX && pointerXOnTotalContent <= barEndX) {
            if (enableResize) {
              if (pointerXOnTotalContent < barStartX + resizeHandleWidth) {
                return (task: task, part: TaskPart.startHandle);
              }
              if (pointerXOnTotalContent > barEndX - resizeHandleWidth) {
                return (task: task, part: TaskPart.endHandle);
              }
            }
            return (task: task, part: TaskPart.body);
          }
        }
        return null;
      }
      cumulativeHeight += currentRowHeight;
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
        newEnd = _originalTaskEnd!.add(durationDelta);
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
    notifyListeners();
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
    notifyListeners();
  }
}
