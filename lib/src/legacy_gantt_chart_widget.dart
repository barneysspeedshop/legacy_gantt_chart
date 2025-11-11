// packages/gantt_chart/lib/src/gantt_chart_widget.dart
import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'models/legacy_gantt_task.dart';
import 'models/legacy_gantt_theme.dart';
import 'models/legacy_gantt_row.dart';
import 'axis_painter.dart';
import 'legacy_gantt_controller.dart';
import 'legacy_gantt_view_model.dart';
import 'bars_collection_painter.dart';

/// The main widget for displaying a Gantt chart.
///
/// This widget is responsible for rendering the timeline, task bars, and dependencies.
/// It handles user interactions such as dragging, resizing, and creating tasks and dependencies.
///
/// It can be used with a static list of data or dynamically with a [LegacyGanttController].
class LegacyGanttChartWidget extends StatefulWidget {
  /// The list of [LegacyGanttTask] objects to display on the chart.
  /// This is ignored if a [controller] or [tasksFuture] is provided.
  final List<LegacyGanttTask>? data;

  /// A list of dependencies to draw between tasks.
  /// This is ignored if a [controller] is provided.
  final List<LegacyGanttTaskDependency>? dependencies;

  /// A list of tasks to be rendered as background highlights, such as holidays
  /// or weekends. These tasks should have `isTimeRangeHighlight` set to `true`.
  /// This is ignored if a [controller] is provided.
  final List<LegacyGanttTask>? holidays;

  /// The list of [LegacyGanttRow]s that are currently visible in the chart's viewport.
  /// This is used to determine which rows to render.
  final List<LegacyGanttRow> visibleRows;

  /// A callback function invoked when the user's cursor hovers over a task.
  ///
  /// Provides the [LegacyGanttTask] being hovered and the global position of the cursor.
  /// Useful for showing custom tooltips or hover effects.
  final Function(LegacyGanttTask?, Offset globalPosition)? onTaskHover;

  /// A scroll controller for the vertical scrolling of the Gantt chart.
  ///
  /// This should be the same controller used by an accompanying data grid (e.g., `GanttGrid`)
  /// to ensure that the chart and the grid scroll in sync.
  final ScrollController? scrollController;

  /// The height of the timeline axis header at the top of the chart.
  final double? axisHeight;

  /// A map from a row ID to the maximum number of tasks that can be stacked vertically
  /// in that row. If the number of overlapping tasks exceeds this value, a
  /// conflict indicator will be shown.
  final Map<String, int> rowMaxStackDepth;

  /// The height of a single task bar lane within a row. The total height of a
  /// [LegacyGanttRow] is `rowHeight * stackDepth`.
  final double rowHeight;

  /// The theme data that defines the colors and styles for the chart's elements.
  /// If not provided, a default theme is derived from the ambient [ThemeData].
  final LegacyGanttTheme? theme;

  /// The start of the visible date range, expressed as milliseconds since the Unix epoch.
  /// This is ignored if a [controller] is provided.
  final double? gridMin; // Unix timestamp or milliseconds since epoch

  /// The end of the visible date range, expressed as milliseconds since the Unix epoch.
  /// This is ignored if a [controller] is provided.
  final double? gridMax; // Unix timestamp or milliseconds since epoch

  /// The absolute start of the entire possible date range for the chart.
  /// This is used by the timeline axis to determine its overall width.
  final double? totalGridMin; // The start of the entire dataset's time range

  /// The absolute end of the entire possible date range for the chart.
  final double? totalGridMax; // The end of the entire dataset's time range

  /// A callback function invoked when a user taps or clicks on a task bar.
  final Function(LegacyGanttTask)? onPressTask;

  /// Enables or disables the ability to drag and drop tasks to change their time or row.
  final bool enableDragAndDrop;

  /// Enables or disables the ability to resize tasks by dragging their start or end handles.
  final bool enableResize;

  /// A future that resolves to the list of tasks to display.
  /// This is ignored if a [controller] is provided.
  final Future<List<LegacyGanttTask>>? tasksFuture;

  /// A future that resolves to a list of holiday/highlight tasks.
  /// This is ignored if a [controller] is provided.
  final Future<List<LegacyGanttTask>>? holidaysFuture;

  /// A controller to programmatically manage the Gantt chart's state, including
  /// the visible date range and dynamically loaded data. When a controller is
  /// provided, properties like `data`, `holidays`, `gridMin`, and `gridMax` are
  /// ignored as they are managed by the controller.
  final LegacyGanttController? controller;

  /// A builder function to create a completely custom widget for a task bar.
  ///
  /// If this is provided, the default task bar painting is skipped, and this widget is
  /// rendered instead. This gives full control over the appearance and behavior of a task.
  /// This cannot be used simultaneously with [taskContentBuilder].
  final Widget Function(LegacyGanttTask task)? taskBarBuilder;

  /// A builder to create custom content *inside* the default task bar.
  ///
  /// This is useful for adding custom icons, text, or progress indicators while
  /// retaining the default bar's shape, color, and drag/resize handles.
  /// This cannot be used simultaneously with [taskBarBuilder].
  final Widget Function(LegacyGanttTask task)? taskContentBuilder;

  /// A callback function that is invoked when a task is updated through dragging or resizing.
  ///
  /// Provides the updated [LegacyGanttTask] and its new `start` and `end` times.
  final Function(LegacyGanttTask task, DateTime newStart, DateTime newEnd)? onTaskUpdate;

  /// A callback function invoked when a user double-taps or double-clicks on a task bar.
  ///
  /// Provides the [LegacyGanttTask] that was double-tapped.
  final Function(LegacyGanttTask task)? onTaskDoubleClick;

  /// A callback function that is invoked when a task is deleted.
  final Function(LegacyGanttTask task)? onTaskDelete;

  /// A function to format the date/time shown in the tooltip when resizing a task.
  final String Function(DateTime)? resizeTooltipDateFormat;

  /// A callback that is triggered when a user clicks on an empty space in the
  /// chart. This can be used to initiate the creation of a new task.
  final Function(String rowId, DateTime time)? onEmptySpaceClick;

  /// The background color of the tooltip that appears during drag or resize operations.
  /// If not provided, it defaults to the theme's `barColorPrimary`.
  final Color? resizeTooltipBackgroundColor;

  /// The font color of the tooltip that appears during drag or resize operations.
  /// If not provided, it's automatically determined for contrast against the
  /// tooltip's background color.
  final Color? resizeTooltipFontColor;

  /// The width of the resize handles at the start and end of a task bar.
  final double resizeHandleWidth;

  /// A builder function to customize the labels displayed on the timeline axis.
  ///
  /// This function is called for each label on the timeline and provides the
  /// [DateTime] of the label and the current [Duration] of the tick interval.
  /// This allows for flexible formatting, such as displaying month names,
  /// fiscal year quarters, or any other custom representation.
  ///
  /// Example:
  /// ```dart
  /// timelineAxisLabelBuilder: (DateTime date, Duration interval) {
  ///   if (interval.inDays > 20) {
  ///     return DateFormat('MMM yyyy').format(date); // Display month and year
  ///   } else {
  ///     return DateFormat('d MMM').format(date); // Display day and month
  ///   }
  /// }
  /// ```
  final String Function(DateTime, Duration)? timelineAxisLabelBuilder;

  /// A builder function to create a completely custom widget for the timeline header.
  ///
  /// If this is provided, the default timeline header painting is skipped, and this
  /// widget is rendered instead. This gives you full control over the appearance
  /// and behavior of the timeline header.
  ///
  /// The builder provides the following arguments:
  /// - `context`: The build context.
  /// - `scale`: A function that converts a `DateTime` to its corresponding horizontal (x-axis) pixel value.
  /// - `visibleDomain`: The currently visible date range.
  /// - `totalDomain`: The total date range of the entire chart.
  /// - `theme`: The current Gantt chart theme.
  /// - `totalContentWidth`: The total width of the chart's content area.
  final Widget Function(
    BuildContext context,
    double Function(DateTime) scale,
    List<DateTime> visibleDomain,
    List<DateTime> totalDomain,
    LegacyGanttTheme theme,
    double totalContentWidth,
  )? timelineAxisHeaderBuilder;

  const LegacyGanttChartWidget({
    super.key, // Use super.key
    this.data,
    this.dependencies,
    this.holidays,
    required this.visibleRows,
    required this.rowMaxStackDepth,
    this.onTaskHover,
    this.scrollController,
    this.axisHeight,
    this.rowHeight = 27.0,
    this.onPressTask,
    this.theme,
    this.gridMin,
    this.gridMax,
    this.totalGridMin,
    this.totalGridMax,
    this.enableDragAndDrop = false,
    this.enableResize = false,
    this.tasksFuture,
    this.holidaysFuture,
    this.controller,
    this.taskBarBuilder,
    this.taskContentBuilder,
    this.onTaskUpdate,
    this.onTaskDoubleClick,
    this.onTaskDelete,
    this.resizeTooltipDateFormat,
    this.onEmptySpaceClick,
    this.resizeTooltipBackgroundColor,
    this.resizeTooltipFontColor,
    this.resizeHandleWidth = 10.0,
    this.timelineAxisLabelBuilder,
    this.timelineAxisHeaderBuilder,
  })  : assert(controller != null || ((data != null && tasksFuture == null) || (data == null && tasksFuture != null))),
        assert(controller == null || dependencies == null),
        assert(taskBarBuilder == null || taskContentBuilder == null),
        assert(controller == null ||
            (data == null &&
                tasksFuture == null &&
                holidays == null &&
                holidaysFuture == null &&
                gridMin == null &&
                gridMax == null));

  @override
  State<LegacyGanttChartWidget> createState() => _LegacyGanttChartWidgetState();
}

class _LegacyGanttChartWidgetState extends State<LegacyGanttChartWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final LegacyGanttTheme effectiveTheme = widget.theme ?? LegacyGanttTheme.fromTheme(theme);

    if (widget.controller != null) {
      return AnimatedBuilder(
        animation: widget.controller!,
        builder: (context, child) {
          final controller = widget.controller!;
          final tasks = controller.tasks;
          final holidays = controller.holidays;
          final dependencies = controller.dependencies;
          final allItems = [...tasks, ...holidays];

          if (controller.isOverallLoading && allItems.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (allItems.isEmpty && !controller.isOverallLoading) {
            return Center(
              child: Text('No data to display.', style: TextStyle(color: effectiveTheme.textColor)),
            );
          }

          return Stack(
            children: [
              _buildChart(
                context,
                allItems,
                dependencies,
                effectiveTheme,
                gridMin: controller.visibleStartDate.millisecondsSinceEpoch.toDouble(),
                gridMax: controller.visibleEndDate.millisecondsSinceEpoch.toDouble(),
              ),
              if (controller.isLoading)
                Container(
                  color: effectiveTheme.backgroundColor.withValues(alpha: 0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      );
    }

    if (widget.tasksFuture != null || widget.holidaysFuture != null) {
      return FutureBuilder<List<dynamic>>(
        future: Future.wait([
          widget.tasksFuture ?? Future.value(<LegacyGanttTask>[]),
          widget.holidaysFuture ?? Future.value(<LegacyGanttTask>[])
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final tasks = (snapshot.data?[0] as List<LegacyGanttTask>?) ?? [];
          final holidays = (snapshot.data?[1] as List<LegacyGanttTask>?) ?? [];
          final allItems = [...tasks, ...holidays];

          if (allItems.isEmpty) {
            return Center(
              child: Text('No data to display.', style: TextStyle(color: effectiveTheme.textColor)),
            );
          }
          return _buildChart(context, allItems, widget.dependencies ?? [], effectiveTheme);
        },
      );
    } else {
      final tasks = widget.data ?? [];
      final holidays = widget.holidays ?? [];
      final allItems = [...tasks, ...holidays];
      if (allItems.isEmpty) {
        return Center(
          child: Text('No data to display.', style: TextStyle(color: effectiveTheme.textColor)),
        );
      }
      return _buildChart(context, allItems, widget.dependencies ?? [], effectiveTheme);
    }
  }

  Widget _buildChart(BuildContext context, List<LegacyGanttTask> tasks, List<LegacyGanttTaskDependency> dependencies,
          LegacyGanttTheme effectiveTheme,
          {double? gridMin, double? gridMax}) =>
      ChangeNotifierProvider(
        key: ValueKey(
          Object.hash(
            tasks.length,
            // The hashCode of individual list elements (tasks/dependencies/rows) is unstable
            // if they contain closures (like cellBuilder) or are recreated on parent rebuilds.
            // Rely only on lengths and the stable hash of the immutable map.
            dependencies.length,
            widget.visibleRows.length,
            widget.rowMaxStackDepth,
            widget.axisHeight,
          ),
        ),
        create: (_) => LegacyGanttViewModel(
          data: tasks,
          dependencies: dependencies,
          visibleRows: widget.visibleRows,
          rowMaxStackDepth: widget.rowMaxStackDepth,
          rowHeight: widget.rowHeight,
          axisHeight: widget.axisHeight,
          gridMin: gridMin ?? widget.gridMin,
          gridMax: gridMax ?? widget.gridMax,
          totalGridMin: widget.totalGridMin,
          totalGridMax: widget.totalGridMax,
          enableDragAndDrop: widget.enableDragAndDrop,
          enableResize: widget.enableResize,
          onTaskUpdate: widget.onTaskUpdate,
          onTaskDoubleClick: widget.onTaskDoubleClick,
          onTaskDelete: widget.onTaskDelete,
          onEmptySpaceClick: widget.onEmptySpaceClick,
          onPressTask: widget.onPressTask,
          onTaskHover: widget.onTaskHover,
          taskBarBuilder: widget.taskBarBuilder,
          resizeTooltipDateFormat: widget.resizeTooltipDateFormat,
          scrollController: widget.scrollController,
          resizeHandleWidth: widget.resizeHandleWidth,
        ),
        child: Consumer<LegacyGanttViewModel>(
          builder: (context, vm, child) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              vm.updateVisibleRange(gridMin ?? widget.gridMin, gridMax ?? widget.gridMax);
              vm.updateResizeTooltipDateFormat(widget.resizeTooltipDateFormat); // Call the new method here
            });

            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (constraints.maxWidth == 0 || constraints.maxHeight == 0) {
                  return const SizedBox.shrink();
                }

                vm.updateLayout(constraints.maxWidth, constraints.maxHeight);

                final double totalContentWidth = vm.totalDomain.isEmpty ? 0 : vm.totalScale(vm.totalDomain.last);

                final allRowIds = tasks.map((task) => task.rowId).toSet();
                if (widget.visibleRows.length > allRowIds.length) {
                  for (var row in widget.visibleRows) {
                    allRowIds.add(row.id);
                  }
                }
                final double totalContentHeight = allRowIds.fold<double>(
                  0.0,
                  (prev, rowId) => prev + widget.rowHeight * (widget.rowMaxStackDepth[rowId] ?? 1),
                );

                return MouseRegion(
                  cursor: vm.cursor,
                  onHover: vm.onHover,
                  onExit: vm.onHoverExit,
                  child: GestureDetector(
                    onPanStart: vm.onPanStart,
                    onPanUpdate: vm.onPanUpdate,
                    onPanEnd: vm.onPanEnd,
                    onTapUp: vm.onTapUp,
                    onDoubleTapDown: (details) => vm.onDoubleTap(details.localPosition),
                    child: Container(
                      color: effectiveTheme.backgroundColor,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: AxisPainter(
                                x: 0,
                                y: vm.timeAxisHeight,
                                width: totalContentWidth,
                                height: constraints.maxHeight,
                                scale: vm.totalScale,
                                domain: vm.totalDomain,
                                visibleDomain: vm.visibleExtent,
                                theme:
                                    effectiveTheme.copyWith(axisTextStyle: const TextStyle(color: Colors.transparent)),
                              ),
                            ),
                          ),
                          Positioned(
                            top: vm.timeAxisHeight,
                            left: 0,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight - vm.timeAxisHeight,
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: BarsCollectionPainter(
                                      dependencies: vm.dependencies,
                                      data: tasks,
                                      domain: vm.totalDomain,
                                      visibleRows: widget.visibleRows,
                                      rowMaxStackDepth: widget.rowMaxStackDepth,
                                      scale: vm.totalScale,
                                      rowHeight: widget.rowHeight,
                                      draggedTaskId: vm.draggedTask?.id,
                                      ghostTaskStart: vm.ghostTaskStart,
                                      ghostTaskEnd: vm.ghostTaskEnd,
                                      theme: effectiveTheme,
                                      hoveredRowId: vm.hoveredRowId,
                                      hoveredDate: vm.hoveredDate,
                                      hasCustomTaskBuilder: widget.taskBarBuilder != null,
                                      hasCustomTaskContentBuilder: false, // Let the widget layer handle this
                                      translateY: vm.translateY,
                                    ),
                                    size: Size(totalContentWidth, totalContentHeight),
                                  ),
                                  ..._buildTaskWidgets(vm, tasks, effectiveTheme),
                                  ..._buildCustomCellWidgets(vm, tasks),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            width: totalContentWidth,
                            height: vm.timeAxisHeight,
                            child: ClipRect(
                              child: Container(
                                color: effectiveTheme.backgroundColor,
                                child: widget.timelineAxisHeaderBuilder != null
                                    ? widget.timelineAxisHeaderBuilder!(
                                        context,
                                        vm.totalScale,
                                        vm.visibleExtent,
                                        vm.totalDomain,
                                        effectiveTheme,
                                        totalContentWidth,
                                      )
                                    : CustomPaint(
                                        size: Size(totalContentWidth, vm.timeAxisHeight),
                                        painter: AxisPainter(
                                          x: 0,
                                          y: vm.timeAxisHeight / 2,
                                          width: totalContentWidth,
                                          height: 0,
                                          scale: vm.totalScale,
                                          domain: vm.totalDomain,
                                          visibleDomain: vm.visibleExtent,
                                          theme: effectiveTheme,
                                          timelineAxisLabelBuilder: widget.timelineAxisLabelBuilder,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if (vm.showResizeTooltip)
                            Positioned(
                              left: vm.resizeTooltipPosition.dx + 15,
                              top: vm.resizeTooltipPosition.dy + 15,
                              child: _buildResizeTooltip(context, vm.resizeTooltipText, effectiveTheme),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );

  Widget _buildResizeTooltip(BuildContext context, String text, LegacyGanttTheme theme) {
    final tooltipBackgroundColor = widget.resizeTooltipBackgroundColor ?? theme.barColorPrimary;
    final tooltipFontColor = widget.resizeTooltipFontColor ??
        (ThemeData.estimateBrightnessForColor(tooltipBackgroundColor) == Brightness.dark ? Colors.white : Colors.black);

    return Material(
      elevation: 4.0,
      borderRadius: BorderRadius.circular(4),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(color: tooltipBackgroundColor, borderRadius: BorderRadius.circular(4)),
        child: Text(
          text,
          style: theme.axisTextStyle.copyWith(color: tooltipFontColor),
        ),
      ),
    );
  }

  List<Widget> _buildTaskWidgets(LegacyGanttViewModel vm, List<LegacyGanttTask> tasks, LegacyGanttTheme theme) {
    final List<Widget> taskWidgets = [];
    double cumulativeRowTop = 0;

    final Map<String, List<LegacyGanttTask>> tasksByRow = {};
    final visibleRowIds = vm.visibleRows.map((r) => r.id).toSet();
    for (final task in tasks) {
      if (visibleRowIds.contains(task.rowId) && !task.isTimeRangeHighlight) {
        tasksByRow.putIfAbsent(task.rowId, () => []).add(task);
      }
    }

    for (final rowData in vm.visibleRows) {
      final tasksInThisRow = tasksByRow[rowData.id] ?? [];
      for (final task in tasksInThisRow) {
        final startX = vm.totalScale(task.start);
        final endX = vm.totalScale(task.end);
        final width = endX - startX;

        if (width <= 0) {
          continue;
        }

        final top = cumulativeRowTop + (task.stackIndex * vm.rowHeight) + vm.translateY;

        Widget taskWidget;
        if (task.isOverlapIndicator) {
          taskWidget = _OverlapIndicatorBar(theme: theme);
        } else if (widget.taskBarBuilder != null) {
          taskWidget = widget.taskBarBuilder!(task);
        } else {
          taskWidget = _DefaultTaskBar(
            task: task,
            vm: vm,
            theme: theme,
            content: widget.taskContentBuilder != null ? widget.taskContentBuilder!(task) : null,
          );
        }

        taskWidgets.add(Positioned(
          left: startX,
          top: top,
          width: width,
          height: vm.rowHeight,
          child: taskWidget,
        ));
      }
      final stackDepth = vm.rowMaxStackDepth[rowData.id] ?? 1;
      cumulativeRowTop += vm.rowHeight * stackDepth;
    }
    return taskWidgets;
  }

  List<Widget> _buildCustomCellWidgets(LegacyGanttViewModel vm, List<LegacyGanttTask> tasks) {
    final List<Widget> customCells = [];
    double cumulativeRowTop = 0;

    final Map<String, List<LegacyGanttTask>> tasksByRow = {};
    final visibleRowIds = vm.visibleRows.map((r) => r.id).toSet();
    for (final task in tasks) {
      if (visibleRowIds.contains(task.rowId) && task.cellBuilder != null) {
        tasksByRow.putIfAbsent(task.rowId, () => []).add(task);
      }
    }

    for (final rowData in vm.visibleRows) {
      final tasksInThisRow = tasksByRow[rowData.id] ?? [];
      for (final task in tasksInThisRow) {
        final taskStart = task.start;
        final taskEnd = task.end;

        var currentDate = DateTime(taskStart.year, taskStart.month, taskStart.day);
        while (currentDate.isBefore(taskEnd)) {
          final segmentStart = taskStart.isAfter(currentDate) ? taskStart : currentDate;
          final nextDay = currentDate.add(const Duration(days: 1));
          final segmentEnd = taskEnd.isBefore(nextDay) ? taskEnd : nextDay;

          final startX = vm.totalScale(segmentStart);
          final endX = vm.totalScale(segmentEnd);
          final width = endX - startX;

          if (width > 0) {
            final top = cumulativeRowTop + (task.stackIndex * vm.rowHeight) + vm.translateY;
            customCells.add(Positioned(
                left: startX, top: top, width: width, height: vm.rowHeight, child: task.cellBuilder!(currentDate)));
          }
          currentDate = nextDay;
        }
      }
      final stackDepth = vm.rowMaxStackDepth[rowData.id] ?? 1;
      cumulativeRowTop += vm.rowHeight * stackDepth;
    }
    return customCells;
  }
}

class _DefaultTaskBar extends StatefulWidget {
  final LegacyGanttTask task;
  final LegacyGanttViewModel vm;
  final LegacyGanttTheme theme;
  final Widget? content;

  const _DefaultTaskBar({
    required this.task,
    required this.vm,
    required this.theme,
    this.content,
  });

  @override
  _DefaultTaskBarState createState() => _DefaultTaskBarState();
}

class _DefaultTaskBarState extends State<_DefaultTaskBar> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = widget.theme;
    final vm = widget.vm;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: task.color ?? theme.barColorPrimary,
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.content != null)
              widget.content!
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    task.name ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: theme.taskTextStyle,
                  ),
                ),
              ),
            if (_isHovered && vm.onTaskDelete != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: theme.taskTextStyle.color,
                  onPressed: () => vm.deleteTask(task),
                  splashRadius: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A widget that uses a [CustomPainter] to draw the conflict/overlap pattern.
class _OverlapIndicatorBar extends StatelessWidget {
  final LegacyGanttTheme theme;

  const _OverlapIndicatorBar({required this.theme});

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _OverlapPainter(theme: theme),
        child: Container(),
      );
}

/// The actual painter for the conflict/overlap pattern.
class _OverlapPainter extends CustomPainter {
  final LegacyGanttTheme theme;

  _OverlapPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height * theme.barHeightRatio;
    final barVerticalCenterOffset = (size.height - barHeight) / 2;
    final rect = Rect.fromLTWH(0, barVerticalCenterOffset, size.width, barHeight);
    final rrect = RRect.fromRectAndRadius(rect, theme.barCornerRadius);

    // To ensure the conflict pattern is clear and not blended with underlying bars,
    // we first "erase" the area by drawing a solid block of the chart's background color.
    canvas.drawRRect(rrect, Paint()..color = theme.backgroundColor);

    // Next, draw the semi-transparent red background for the conflict area.
    final backgroundPaint = Paint()..color = theme.conflictBarColor.withValues(alpha: 0.4);
    canvas.drawRRect(rrect, backgroundPaint);

    // Then, draw the angled lines on top of that new background.
    _drawAngledPattern(canvas, rrect, theme.conflictBarColor, 1.0);
  }

  void _drawAngledPattern(Canvas canvas, RRect rrect, Color color, double strokeWidth) {
    final patternPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRRect(rrect);

    const double lineSpacing = 8.0;
    for (double i = -rrect.height; i < rrect.width; i += lineSpacing) {
      canvas.drawLine(
          Offset(rrect.left + i, rrect.top), Offset(rrect.left + i + rrect.height, rrect.bottom), patternPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OverlapPainter oldDelegate) => oldDelegate.theme != theme;
}
