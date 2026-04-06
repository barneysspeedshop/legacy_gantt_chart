import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'models/legacy_gantt_row.dart';
import 'models/legacy_gantt_task.dart';
import 'models/legacy_gantt_dependency.dart';
import 'models/legacy_gantt_theme.dart';
import 'models/remote_ghost.dart';
import 'models/work_calendar.dart';
import 'models/dependency_drag_status.dart';
import 'utils/critical_path_calculator.dart';

/// A [CustomPainter] responsible for drawing all the task bars, dependency lines,
/// and other visual elements onto the main Gantt chart grid area.
///
/// This painter is optimized to handle a large number of tasks and dependencies
/// by painting them in a single, efficient operation. It handles task stacking,
/// different task types (summary, highlight, conflict), and interactive states
/// like dragging and creating dependencies.
class BarsCollectionPainter extends CustomPainter {
  /// The complete list of [LegacyGanttTask] objects to be potentially drawn.
  final List<LegacyGanttTask> data;

  /// The list of conflict indicators to be drawn.
  final List<LegacyGanttTask> conflictIndicators;

  /// The list of [LegacyGanttRow]s currently visible in the viewport.
  /// This is used to determine which tasks to draw and where.
  final List<LegacyGanttRow> visibleRows;

  /// The visible date range, where `domain[0]` is the start date and `domain[1]` is the end date.
  final List<DateTime> domain;

  /// A map from a row ID to the maximum number of overlapping tasks allowed in that row.
  final Map<String, int> rowMaxStackDepth;

  /// A function that converts a [DateTime] to its corresponding horizontal (x-axis) pixel value.
  final double Function(DateTime) scale;

  /// The height of a single row. The total height for a `GanttRow` is `rowHeight * stackDepth`.
  final double rowHeight;

  /// The ID of the task currently being dragged. Used to apply a different style to the dragged task.
  final String? draggedTaskId;

  /// The projected start date of the task being dragged.
  final DateTime? ghostTaskStart;

  /// The projected end date of the task being dragged.
  final DateTime? ghostTaskEnd;

  /// The projected row ID of the task being dragged.
  final String? ghostTaskRowId;

  /// The temporary task being drawn interactively (e.g. via Draw Tool).
  final LegacyGanttTask? drawingTask;

  /// Map of remote ghosts from other users (keyed by user ID).
  final Map<String, RemoteGhost> remoteGhosts;

  /// The theme data that defines the colors and styles for the chart elements.
  final LegacyGanttTheme theme;

  /// A list of all dependencies to be drawn as connector lines or backgrounds.
  final List<LegacyGanttTaskDependency> dependencies;

  /// The ID of the row currently being hovered over, used for highlighting empty space for task creation.
  final String? hoveredRowId;

  /// The date currently being hovered over, used for highlighting empty space for task creation.
  final DateTime? hoveredDate;

  /// A flag indicating if a custom `taskBarBuilder` is being used, which affects whether this painter draws the bars.
  final bool hasCustomTaskBuilder;

  /// A flag indicating if a custom `taskContentBuilder` is being used, which affects whether this painter draws the task's inner content.
  final bool hasCustomTaskContentBuilder;

  /// Whether the feature to interactively create dependencies is enabled.
  final bool enableDependencyCreation;

  /// The current vertical scroll offset of the chart content.
  final double translateY;

  /// The ID of the task where a new dependency drag was initiated.
  final String? dependencyDragStartTaskId;

  /// If true, the dependency drag started from the task's start handle; otherwise, from the end handle.
  final bool? dependencyDragStartIsFromStart;

  /// The current screen position of the cursor during a dependency drag operation.
  final Offset? dependencyDragCurrentPosition;

  /// The ID of the task being hovered over as a potential target for a new dependency.
  final String? hoveredTaskForDependency;
  final Set<String> selectedTaskIds;
  final Map<String, (DateTime, DateTime)> bulkGhostTasks;
  final Set<String> criticalTaskIds;
  final Set<LegacyGanttTaskDependency> criticalDependencies;
  final Map<String, List<LegacyGanttTask>> tasksByRow;
  final List<double>? rowVerticalOffsets; // Optional for tests
  final WorkCalendar? workCalendar;
  final bool rollUpMilestones;
  final bool showNowLine;

  final DateTime? nowLineDate;
  final bool showSlack;
  final Map<String, CpmTaskStats> cpmStats;
  final DependencyDragStatus dependencyDragStatus;
  final int? dependencyDragDelayAmount;
  final bool isSecondaryHovered;
  final Offset? secondaryHoverPosition;

  BarsCollectionPainter({
    required this.data,
    required this.tasksByRow,
    this.rowVerticalOffsets, // Optional
    required this.conflictIndicators,
    required this.visibleRows,
    required this.domain,
    required this.rowMaxStackDepth,
    required this.scale,
    required this.rowHeight,
    this.draggedTaskId,
    this.ghostTaskStart,
    this.ghostTaskEnd,
    this.ghostTaskRowId,
    this.drawingTask,
    this.remoteGhosts = const {},
    required this.theme,
    this.dependencies = const [],
    this.hoveredRowId,
    this.hoveredDate,
    this.hasCustomTaskBuilder = false,
    this.hasCustomTaskContentBuilder = false,
    this.enableDependencyCreation = false,
    this.translateY = 0.0,
    this.dependencyDragStartTaskId,
    this.dependencyDragStartIsFromStart,
    this.dependencyDragCurrentPosition,
    this.hoveredTaskForDependency,
    this.selectedTaskIds = const {},
    this.bulkGhostTasks = const {},
    this.criticalTaskIds = const {},
    this.criticalDependencies = const {},
    this.workCalendar,
    this.rollUpMilestones = false,
    this.showNowLine = false,
    this.nowLineDate,
    this.showSlack = false,
    this.cpmStats = const {},
    this.dependencyDragStatus = DependencyDragStatus.none,
    this.dependencyDragDelayAmount,
    this.isSecondaryHovered = false,
    this.secondaryHoverPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paint(canvas, size);
  }

  /// A helper to get the pre-calculated offsets or fall back to cumulative calculation.
  /// (Fallback is mainly for backward compatibility in tests).
  List<double> get _effectiveRowOffsets {
    if (rowVerticalOffsets != null) return rowVerticalOffsets!;

    final offsets = <double>[0.0];
    double current = 0.0;
    for (final row in visibleRows) {
      final depth = rowMaxStackDepth[row.id] ?? 1;
      current += rowHeight * depth;
      offsets.add(current);
    }
    return offsets;
  }

  void _paint(Canvas canvas, Size size) {
    final rowOffsets = _effectiveRowOffsets; // Use the helper
    canvas.save();
    canvas.translate(0, translateY);
    _drawDependencyBackgrounds(canvas, size);
    _drawEmptySpaceHighlight(canvas, size);

    if (bulkGhostTasks.isNotEmpty) {
      final Paint ghostPaint = Paint()
        ..color = theme.ghostBarColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;
      final Paint ghostBorderPaint = Paint()
        ..color = theme.ghostBarColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final Map<String, List<({LegacyGanttTask task, DateTime start, DateTime end})>> ghostsByRow = {};

      for (final entry in bulkGhostTasks.entries) {
        final taskId = entry.key;
        final times = entry.value;
        try {
          final task = data.firstWhere((t) => t.id == taskId);
          ghostsByRow.putIfAbsent(task.rowId, () => []);
          ghostsByRow[task.rowId]!.add((task: task, start: times.$1, end: times.$2));
        } catch (_) {}
      }

      for (int i = 0; i < visibleRows.length; i++) {
        final rowData = visibleRows[i];
        final ghostsInThisRow = ghostsByRow[rowData.id];
        final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
        final double dynamicRowHeight = rowHeight * stackDepth;
        final double rowTop = rowOffsets[i];
        final double rowBottom = rowTop + dynamicRowHeight;

        if (ghostsInThisRow == null || ghostsInThisRow.isEmpty) continue;
        if (rowBottom < -translateY || rowTop > -translateY + size.height) continue;

        for (final ghost in ghostsInThisRow) {
          final task = ghost.task;
          final double barStartX = scale(ghost.start);
          final double barEndX = scale(ghost.end);

          if (barEndX < 0 || barStartX > size.width) continue;

          final double barTop = rowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;

          if (task.isMilestone) {
            final double milestoneX = barStartX;
            final double milestoneY = barTop + barVerticalCenterOffset;
            _drawMilestone(canvas, task, milestoneX, milestoneY, barHeight, true);
          } else {
            final double barWidth = max(0, barEndX - barStartX);
            final RRect barRRect = RRect.fromRectAndRadius(
              Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barWidth, barHeight),
              theme.barCornerRadius,
            );

            canvas.drawRRect(barRRect, ghostPaint);
            canvas.drawRRect(barRRect, ghostBorderPaint);

            if (task.isSummary) {
              _drawAngledPattern(canvas, barRRect, theme.summaryBarColor.withValues(alpha: 1.0), 1.5);
            }
          }
        }
      }
    }

    final Map<String, List<LegacyGanttTask>> milestonesByParent = {};
    if (rollUpMilestones) {
      for (final task in data) {
        if (task.isMilestone && task.parentId != null) {
          milestonesByParent.putIfAbsent(task.parentId!, () => []).add(task);
        }
      }
    }

    final visibleContentTop = -translateY;
    final visibleContentBottom = -translateY + size.height;

    LegacyGanttTask? draggedSummaryTask;
    Set<String> summaryChildRowIds = {};
    if (draggedTaskId != null && ghostTaskStart != null && ghostTaskEnd != null) {
      final task = data.firstWhere((t) => t.id == draggedTaskId, orElse: () => LegacyGanttTask.empty());
      if (task.id.isNotEmpty && task.isSummary) {
        draggedSummaryTask = task;
        summaryChildRowIds = data.where((t) => t.parentId == task.id).map((t) => t.rowId).toSet();
      }
    }

    for (int i = 0; i < visibleRows.length; i++) {
      final rowData = visibleRows[i];
      final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
      final double dynamicRowHeight = rowHeight * stackDepth;
      final double rowTop = rowOffsets[i];
      final double rowBottom = rowTop + dynamicRowHeight;

      if (rowBottom < visibleContentTop) continue;
      if (rowTop > visibleContentBottom) break;

      final tasksInThisRow = tasksByRow[rowData.id] ?? [];

      if (draggedSummaryTask != null && summaryChildRowIds.contains(rowData.id)) {
        final double gStart = scale(ghostTaskStart!);
        final double gEnd = scale(ghostTaskEnd!);
        final double barStartX = min(gStart, gEnd);
        final double barEndX = max(gStart, gEnd);
        final double barWidth = max(0, barEndX - barStartX);

        if (barWidth > 0 && barStartX < size.width) {
          final rect = Rect.fromLTWH(barStartX, rowTop, barWidth, dynamicRowHeight);
          final paint = Paint()..color = theme.summaryBarColor.withValues(alpha: 0.2);
          canvas.drawRect(rect, paint);
        }
      }

      for (final task in tasksInThisRow.where((t) => t.isTimeRangeHighlight)) {
        final double barStartX = scale(task.start);
        final double barEndX = scale(task.end);

        if (barEndX < 0) continue;
        if (barStartX > size.width) break;

        final double barWidth = max(0, barEndX - barStartX);
        final rect = Rect.fromLTWH(barStartX, rowTop, barWidth, dynamicRowHeight);
        final paint = Paint()..color = task.color ?? theme.timeRangeHighlightColor;
        canvas.drawRect(rect, paint);
      }

      if (!hasCustomTaskBuilder) {
        if (showSlack) {
          for (final task in tasksInThisRow.where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)) {
            if (task.cellBuilder != null || task.isMilestone) continue;

            final stats = cpmStats[task.id];
            if (stats != null && stats.float > 0) {
              final double taskEndX = scale(task.end);
              final double slackStartX = taskEndX;
              final double slackEndX = scale(task.end.add(Duration(minutes: stats.float)));

              if (slackEndX > slackStartX && slackEndX > 0 && slackStartX < size.width) {
                final double barTop = rowTop + (task.stackIndex * rowHeight);
                final double barHeight = rowHeight * theme.barHeightRatio;
                final double slackHeight = barHeight * 0.6;
                final double slackVerticalCenterOffset = (rowHeight - slackHeight) / 2;

                final RRect slackRRect = RRect.fromRectAndRadius(
                  Rect.fromLTWH(slackStartX, barTop + slackVerticalCenterOffset, slackEndX - slackStartX, slackHeight),
                  const Radius.circular(2.0),
                );

                final Paint slackPaint = Paint()
                  ..color = theme.slackBarColor
                  ..style = PaintingStyle.fill;

                canvas.drawRRect(slackRRect, slackPaint);
                _drawAngledPattern(canvas, slackRRect, theme.slackBarColor.withValues(alpha: 0.5), 1.0);
              }
            }
          }
        }

        for (final task in tasksInThisRow.where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)) {
          if (task.cellBuilder != null) continue;

          final double taskStartX = scale(task.start);
          final double taskEndX = scale(task.end);
          if (taskEndX < 0) continue;
          if (taskStartX > size.width) break;

          final isBeingDragged = task.id == draggedTaskId;
          final double barTop = rowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;
          final bool hasSegments = task.segments != null && task.segments!.isNotEmpty;

          if (task.isMilestone) {
            _drawMilestone(canvas, task, taskStartX, barTop + barVerticalCenterOffset, barHeight, isBeingDragged);
            continue;
          }

          final RRect barRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(taskStartX, barTop + barVerticalCenterOffset, taskEndX - taskStartX, barHeight),
            theme.barCornerRadius,
          );

          if (taskEndX <= taskStartX) continue;

          if (hasSegments) {
            for (final segment in task.segments!) {
              final double barStartX = scale(segment.start);
              final double barEndX = scale(segment.end);
              if (barEndX <= barStartX) continue;
              if (barEndX < 0 || barStartX > size.width) continue;

              final RRect segmentRRect = RRect.fromRectAndRadius(
                Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barEndX - barStartX, barHeight),
                theme.barCornerRadius,
              );

              final barPaint = Paint()
                ..color = (segment.color ?? task.color ?? theme.barColorPrimary)
                    .withValues(alpha: isBeingDragged ? 0.3 : 1.0);
              canvas.drawRRect(segmentRRect, barPaint);

              if (task.usesWorkCalendar) {
                _drawNonWorkingShading(canvas, segmentRRect, segment.start, segment.end);
              }
            }
          } else {
            final barPaint = Paint()
              ..color = (task.color ?? theme.barColorPrimary).withValues(alpha: isBeingDragged ? 0.3 : 1.0);
            canvas.drawRRect(barRRect, barPaint);

            if (task.usesWorkCalendar) {
              _drawNonWorkingShading(canvas, barRRect, task.start, task.end);
            }

            if (task.completion > 0.0) {
              final double progressWidth = barRRect.width * task.completion.clamp(0.0, 1.0);
              if (progressWidth > 0) {
                final RRect progressRRect = RRect.fromRectAndRadius(
                  Rect.fromLTWH(barRRect.left, barRRect.top, progressWidth, barRRect.height),
                  theme.barCornerRadius,
                );
                final progressPaint = Paint()
                  ..color = (task.color ?? theme.barColorSecondary).withValues(alpha: isBeingDragged ? 0.5 : 1.0);
                canvas.drawRRect(progressRRect, progressPaint);
              }
            }

            if (task.isSummary) {
              _drawSummaryPattern(canvas, barRRect);

              if (rollUpMilestones) {
                final childMilestones = milestonesByParent[task.id];
                if (childMilestones != null) {
                  for (final milestone in childMilestones) {
                    final double mStartX = scale(milestone.start);
                    if (mStartX + barHeight < 0 || mStartX > size.width) continue;


                    _drawMilestone(
                      canvas,
                      milestone,
                      mStartX,
                      barTop + barVerticalCenterOffset,
                      barHeight,
                      isBeingDragged,
                    );
                  }
                }
              }
            }

            if (task.baselineStart != null && task.baselineEnd != null) {
              final double baselineStartX = scale(task.baselineStart!);
              final double baselineEndX = scale(task.baselineEnd!);

              if (baselineEndX > 0 && baselineStartX < size.width && baselineEndX > baselineStartX) {
                final double baselineTop = barRRect.bottom + 2;
                final double baselineHeight = barHeight * 0.3;

                final RRect baselineRRect = RRect.fromRectAndRadius(
                  Rect.fromLTWH(baselineStartX, baselineTop, baselineEndX - baselineStartX, baselineHeight),
                  const Radius.circular(2.0),
                );

                final baselinePaint = Paint()
                  ..color = Colors.grey.withValues(alpha: 0.6)
                  ..style = PaintingStyle.fill;

                canvas.drawRRect(baselineRRect, baselinePaint);
              }
            }
          }
        }
      }

      if (!hasCustomTaskBuilder) {
        for (final task in conflictIndicators.where((c) => c.rowId == rowData.id)) {
          final double barStartX = scale(task.start);
          final double barEndX = scale(task.end);

          if (barEndX < 0 || barStartX > size.width) continue;

          final double barTop = rowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;

          final RRect barRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barEndX - barStartX, barHeight),
            theme.barCornerRadius,
          );

          final isSummaryConflict = data.any(
              (t) => t.rowId == task.rowId && t.isSummary && t.start.isBefore(task.end) && t.end.isAfter(task.start));

          _drawConflictIndicator(canvas, barRRect, isSummaryConflict);
        }
      }

      if (!hasCustomTaskBuilder) {
        for (final task in tasksInThisRow.where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)) {
          final double taskStartX = scale(task.start);
          final double taskEndX = scale(task.end);
          if (taskEndX < 0 || taskStartX > size.width || (taskEndX <= taskStartX && !task.isMilestone)) continue;

          final double barTop = rowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;
          final RRect barRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(taskStartX, barTop + barVerticalCenterOffset, taskEndX - taskStartX, barHeight),
            theme.barCornerRadius,
          );

          if (selectedTaskIds.contains(task.id)) {
            final Paint selectionPaint = Paint()
              ..color = Colors.blue
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
            canvas.drawRRect(barRRect.inflate(1.0), selectionPaint);
          } else if (criticalTaskIds.contains(task.id)) {
            final Paint criticalPaint = Paint()
              ..color = theme.criticalPathColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
            canvas.drawRRect(barRRect, criticalPaint);
          }

          if (enableDependencyCreation) {
            _drawDependencyHandles(canvas, barRRect, task, task.id == draggedTaskId, task.isMilestone);
          }

          if (task.name != null && task.name!.isNotEmpty && !hasCustomTaskBuilder && !hasCustomTaskContentBuilder) {
            final overlappingConflicts = conflictIndicators
                .where(
                  (indicator) =>
                      indicator.rowId == task.rowId &&
                      indicator.stackIndex == task.stackIndex &&
                      indicator.start.isBefore(task.end) &&
                      indicator.end.isAfter(task.start),
                )
                .toList();

            final double overallWidth = max(0, taskEndX - taskStartX);
            final textSpan = TextSpan(text: task.name, style: theme.taskTextStyle);
            final textPainter = TextPainter(
                text: textSpan,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                ellipsis: '...');
            textPainter.layout(minWidth: 0, maxWidth: max(0, overallWidth - 8));

            final textOffset = Offset(taskStartX + 4, barTop + (rowHeight - textPainter.height) / 2);

            canvas.save();
            canvas.clipRect(Rect.fromLTWH(taskStartX, barTop, overallWidth, rowHeight));
            textPainter.paint(canvas, textOffset);
            canvas.restore();

            if (overlappingConflicts.isNotEmpty) {
              final whiteTextStyle = theme.taskTextStyle.copyWith(color: Colors.white);
              final whiteTextSpan = TextSpan(text: task.name, style: whiteTextStyle);
              final whiteTextPainter = TextPainter(
                  text: whiteTextSpan,
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  ellipsis: '...');
              whiteTextPainter.layout(minWidth: 0, maxWidth: max(0, overallWidth - 8));

              for (final conflict in overlappingConflicts) {
                final conflictStartX = max(taskStartX, scale(conflict.start));
                final conflictEndX = min(taskEndX, scale(conflict.end));
                final conflictWidth = max(0.0, conflictEndX - conflictStartX);

                if (conflictWidth > 0) {
                  final indicatorHeight = barHeight * 0.4;
                  final conflictTop = barTop + barVerticalCenterOffset + barHeight - indicatorHeight;

                  canvas.save();
                  canvas.clipRect(Rect.fromLTWH(conflictStartX, conflictTop, conflictWidth, indicatorHeight));
                  whiteTextPainter.paint(canvas, textOffset);
                  canvas.restore();
                }
              }
            }
          }
        }
      }

      if (theme.showRowBorders) {
        final y = rowOffsets[i] + dynamicRowHeight - 0.5;
        final borderPaint = Paint()
          ..color = theme.rowBorderColor ?? theme.gridColor
          ..strokeWidth = 1.0;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), borderPaint);
      }
    }

    _drawDependencyLines(canvas, size);
    _drawInprogressDependencyLine(canvas, size);

    if ((draggedTaskId != null || drawingTask != null) && ghostTaskStart != null && ghostTaskEnd != null) {
      final LegacyGanttTask originalTask = drawingTask ?? data.firstWhere((t) => t.id == draggedTaskId, orElse: () => LegacyGanttTask.empty());

      if (originalTask.id.isNotEmpty) {
        int rowIndex = visibleRows.indexWhere((r) => r.id == (ghostTaskRowId ?? originalTask.rowId));
        if (rowIndex != -1) {
          final double barTop = rowOffsets[rowIndex] + (originalTask.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;

          if (originalTask.isMilestone) {
            _drawMilestone(canvas, originalTask, scale(ghostTaskStart!), barTop + barVerticalCenterOffset, barHeight, true);
          } else {
            final double startX = scale(ghostTaskStart!);
            final double endX = scale(ghostTaskEnd!);
            final RRect barRRect = RRect.fromRectAndRadius(
              Rect.fromLTWH(min(startX, endX), barTop + barVerticalCenterOffset, max(0, (endX - startX).abs()), barHeight),
              theme.barCornerRadius,
            );
            final barPaint = Paint()..color = (originalTask.color ?? theme.ghostBarColor).withValues(alpha: 0.7);
            canvas.drawRRect(barRRect, barPaint);
            if (originalTask.isSummary) _drawAngledPattern(canvas, barRRect, theme.summaryBarColor.withValues(alpha: 1.0), 1.5);
          }
        }
      }
    }

    for (final ghost in remoteGhosts.values) {
      if (ghost.tasks.isEmpty && ghost.taskId.isEmpty) continue;
      final Iterable<({String taskId, DateTime start, DateTime end})> ghostItems = ghost.tasks.isNotEmpty
          ? ghost.tasks.entries.map((e) => (taskId: e.key, start: e.value.start, end: e.value.end))
          : [(taskId: ghost.taskId, start: ghost.start!, end: ghost.end!)];

      for (final item in ghostItems) {
        final originalTask = data.firstWhere((t) => t.id == item.taskId, orElse: () => LegacyGanttTask.empty());
        if (originalTask.id.isEmpty) continue;

        if (originalTask.isSummary) {
          final summaryChildRowIds = data.where((t) => t.parentId == originalTask.id).map((t) => t.rowId).toSet();
          for (int i = 0; i < visibleRows.length; i++) {
            if (summaryChildRowIds.contains(visibleRows[i].id)) {
              final double barStartX = scale(item.start);
              final double barEndX = scale(item.end);
              final double rectX = min(barStartX, barEndX);
              final double rectW = max(0, max(barStartX, barEndX) - rectX);
              if (rectW > 0 && rectX < size.width) {
                canvas.drawRect(Rect.fromLTWH(rectX, rowOffsets[i], rectW, rowHeight * (rowMaxStackDepth[visibleRows[i].id] ?? 1)), Paint()..color = theme.summaryBarColor.withValues(alpha: 0.2));
              }
            }
          }
        }

        int rowIndex = visibleRows.indexWhere((r) => r.id == originalTask.rowId);
        if (rowIndex != -1) {
          final double barTop = rowOffsets[rowIndex] + (originalTask.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;
          final double barStartX = scale(item.start);
          final double barEndX = scale(item.end);
          final RRect barRRect = RRect.fromRectAndRadius(Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, max(0, barEndX - barStartX), barHeight), theme.barCornerRadius);
          final userColor = ghost.userColor != null ? (Color(int.parse(ghost.userColor!.replaceAll('#', '0xff')))) : Colors.primaries[ghost.userId.hashCode % Colors.primaries.length];

          if (originalTask.isMilestone) {
            final path = Path();
            path.moveTo(barStartX, barTop + barVerticalCenterOffset + barHeight / 2);
            path.lineTo(barStartX + barHeight / 2, barTop + barVerticalCenterOffset);
            path.lineTo(barStartX + barHeight, barTop + barVerticalCenterOffset + barHeight / 2);
            path.lineTo(barStartX + barHeight / 2, barTop + barVerticalCenterOffset + barHeight);
            path.close();
            canvas.drawPath(path, Paint()..color = userColor.withValues(alpha: 0.5));
          } else {
            canvas.drawRRect(barRRect, Paint()..color = userColor.withValues(alpha: 0.5));
            if (originalTask.isSummary) _drawAngledPattern(canvas, barRRect, theme.summaryBarColor.withValues(alpha: 1.0), 1.5);
          }
        }
      }
    }
    _drawNowLine(canvas, size);
    canvas.restore();
  }

  void _drawNowLine(Canvas canvas, Size size) {
    if (!showNowLine) return;
    final now = nowLineDate ?? DateTime.now();
    final double x = scale(now);
    if (x < 0 || x > size.width) return;
    final paint = Paint()..color = theme.nowLineColor..strokeWidth = 2.0..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    final path = Path();
    path.moveTo(x - 6.0, 0);
    path.lineTo(x + 6.0, 0);
    path.lineTo(x, 6.0);
    path.close();
    canvas.drawPath(path, Paint()..color = theme.nowLineColor);
  }

  void _drawAngledPattern(Canvas canvas, RRect rrect, Color color, double strokeWidth) {
    final patternPaint = Paint()..color = color..strokeWidth = strokeWidth..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRRect(rrect);
    for (double i = -rrect.height; i < rrect.width; i += 8.0) {
      canvas.drawLine(Offset(rrect.left + i, rrect.top), Offset(rrect.left + i + rrect.height, rrect.bottom), patternPaint);
    }
    canvas.restore();
  }

  void _drawSummaryPattern(Canvas canvas, RRect rrect) => _drawAngledPattern(canvas, rrect, theme.summaryBarColor, 1.5);

  void _drawConflictIndicator(Canvas canvas, RRect rrect, bool isSummaryConflict) {
    final indicatorHeight = rrect.height * 0.4;
    final indicatorRRect = RRect.fromRectAndRadius(Rect.fromLTWH(rrect.left, rrect.bottom - indicatorHeight, rrect.width, indicatorHeight), theme.barCornerRadius);
    canvas.drawRRect(indicatorRRect, Paint()..color = theme.backgroundColor);
    canvas.drawRRect(indicatorRRect, Paint()..color = theme.conflictBarColor.withValues(alpha: 0.4));
    _drawAngledPattern(canvas, indicatorRRect, theme.conflictBarColor, 1.0);
  }

  void _drawMilestone(Canvas canvas, LegacyGanttTask task, double x, double y, double height, bool isBeingDragged) {
    final paint = Paint()..color = (task.color ?? theme.barColorPrimary).withValues(alpha: isBeingDragged ? 0.5 : 1.0);
    final path = Path();
    path.moveTo(x, y + height / 2);
    path.lineTo(x + height / 2, y);
    path.lineTo(x + height, y + height / 2);
    path.lineTo(x + height / 2, y + height);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawDependencyHandles(Canvas canvas, RRect rrect, LegacyGanttTask task, bool isBeingDragged, bool isMilestone) {
    if (isBeingDragged || task.isSummary) return;
    final handlePaint = Paint()..color = theme.dependencyLineColor.withValues(alpha: 0.8);
    if (isMilestone) {
      canvas.drawCircle(Offset(rrect.center.dx + (rrect.height / 2), rrect.center.dy), 4.0, handlePaint);
    } else {
      canvas.drawCircle(Offset(rrect.left, rrect.center.dy), 4.0, handlePaint);
      canvas.drawCircle(Offset(rrect.right, rrect.center.dy), 4.0, handlePaint);
    }
    if (task.id == hoveredTaskForDependency) {
      canvas.drawRRect(rrect.inflate(2.0), Paint()..color = theme.dependencyLineColor..strokeWidth = 2.0..style = PaintingStyle.stroke);
    }
  }

  void _drawDependencyBackgrounds(Canvas canvas, Size size) {
    if (dependencies.isEmpty) return;
    final processed = <String>{};
    for (final dependency in dependencies) {
      if (dependency.type == DependencyType.contained && processed.add(dependency.predecessorTaskId)) {
        _drawContainedDependency(canvas, dependency);
      }
    }
  }

  void _drawInprogressDependencyLine(Canvas canvas, Size size) {
    if (dependencyDragStartTaskId == null || dependencyDragCurrentPosition == null) return;
    final startTaskRect = _findTaskRect(dependencyDragStartTaskId!);
    if (startTaskRect == null) return;
    final startX = (dependencyDragStartIsFromStart ?? false) ? startTaskRect.left : startTaskRect.right;
    final startY = startTaskRect.center.dy;
    final endX = dependencyDragCurrentPosition!.dx;
    final endY = dependencyDragCurrentPosition!.dy;
    Color lineColor = dependencyDragStatus == DependencyDragStatus.cycle ? Colors.red : (dependencyDragStatus == DependencyDragStatus.inadmissible ? Colors.orange : (dependencyDragStatus == DependencyDragStatus.admissible ? Colors.green : theme.dependencyLineColor));
    final paint = Paint()..color = lineColor..strokeWidth = 2.0..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    final arrowPath = Path();
    arrowPath.moveTo(endX - 6.0, endY - 3.0);
    arrowPath.lineTo(endX, endY);
    arrowPath.lineTo(endX - 6.0, endY + 3.0);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawDependencyLines(Canvas canvas, Size size) {
    for (final dependency in dependencies) {
      switch (dependency.type) {
        case DependencyType.finishToStart: _drawFinishToStartDependency(canvas, dependency); break;
        case DependencyType.startToStart: _drawStartToStartDependency(canvas, dependency); break;
        case DependencyType.finishToFinish: _drawFinishToFinishDependency(canvas, dependency); break;
        case DependencyType.startToFinish: _drawStartToFinishDependency(canvas, dependency); break;
        case DependencyType.contained: break;
      }
    }
  }

  void _drawFinishToStartDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final p = _findTaskRect(dependency.predecessorTaskId);
    final s = _findTaskRect(dependency.successorTaskId);
    if (p == null || s == null) return;
    final path = Path()..moveTo(p.right, p.center.dy);
    if (s.left > p.right + 10) {
      path.lineTo(p.right + 10, p.center.dy);
      path.lineTo(p.right + 10, s.center.dy);
    } else {
      final midY = p.center.dy < s.center.dy ? s.top - 10 : s.bottom + 10;
      path.lineTo(p.right + 10, p.center.dy);
      path.lineTo(p.right + 10, midY);
      path.lineTo(s.left - 10, midY);
      path.lineTo(s.left - 10, s.center.dy);
    }
    path.lineTo(s.left, s.center.dy);
    canvas.drawPath(path, Paint()..color = theme.dependencyLineColor..strokeWidth = 1.5..style = PaintingStyle.stroke);
  }

  void _drawStartToStartDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final p = _findTaskRect(dependency.predecessorTaskId);
    final s = _findTaskRect(dependency.successorTaskId);
    if (p == null || s == null) return;
    final path = Path()..moveTo(p.left, p.center.dy)..lineTo(p.left - 10, p.center.dy)..lineTo(p.left - 10, s.center.dy)..lineTo(s.left, s.center.dy);
    canvas.drawPath(path, Paint()..color = criticalDependencies.contains(dependency) ? theme.criticalPathColor : theme.dependencyLineColor..strokeWidth = criticalDependencies.contains(dependency) ? 2.0 : 1.5..style = PaintingStyle.stroke);
  }

  void _drawFinishToFinishDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final p = _findTaskRect(dependency.predecessorTaskId);
    final s = _findTaskRect(dependency.successorTaskId);
    if (p == null || s == null) return;
    final path = Path()..moveTo(p.right, p.center.dy)..lineTo(p.right + 10, p.center.dy)..lineTo(p.right + 10, s.center.dy)..lineTo(s.right, s.center.dy);
    canvas.drawPath(path, Paint()..color = theme.dependencyLineColor..strokeWidth = 1.5..style = PaintingStyle.stroke);
  }

  void _drawStartToFinishDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final p = _findTaskRect(dependency.predecessorTaskId);
    final s = _findTaskRect(dependency.successorTaskId);
    if (p == null || s == null) return;
    final path = Path()..moveTo(p.left, p.center.dy);
    if (s.right < p.left - 10) {
      path.lineTo(p.left - 10, p.center.dy);
      path.lineTo(p.left - 10, s.center.dy);
    } else {
      final midY = p.center.dy < s.center.dy ? s.top - 10 : s.bottom + 10;
      path.lineTo(p.left - 10, p.center.dy);
      path.lineTo(p.left - 10, midY);
      path.lineTo(s.right + 10, midY);
      path.lineTo(s.right + 10, s.center.dy);
    }
    path.lineTo(s.right, s.center.dy);
    canvas.drawPath(path, Paint()..color = theme.dependencyLineColor..strokeWidth = 1.5..style = PaintingStyle.stroke);
  }

  void _drawContainedDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final predecessorTask = _findTaskById(dependency.predecessorTaskId);
    if (predecessorTask == null || !predecessorTask.isSummary) return;
    double? groupStartY, groupEndY;
    bool inGroup = false;
    final rowOffsetsLocal = _effectiveRowOffsets;
    for (int i = 0; i < visibleRows.length; i++) {
      final row = visibleRows[i];
      final rowTop = rowOffsetsLocal[i] + translateY;
      final stackDepth = rowMaxStackDepth[row.id] ?? 1;
      final rowHeightFull = rowHeight * stackDepth;

      if (inGroup) {
        final bool isNewSummary = tasksByRow[row.id]?.any((task) => task.isSummary) ?? false;
        if (isNewSummary) {
          inGroup = false; 
        } else {
          groupEndY = rowTop + rowHeightFull;
        }
      }

      if (row.id == predecessorTask.rowId) {
        inGroup = true;
        groupStartY = rowTop;
        groupEndY = rowTop + rowHeightFull;
      }
    }

    if (groupStartY == null || groupEndY == null) return;

    final predecessorStartX = scale(predecessorTask.start);
    final predecessorEndX = scale(predecessorTask.end);

    final backgroundRect = Rect.fromLTRB(predecessorStartX, groupStartY, predecessorEndX, groupEndY);
    final paint = Paint()..color = theme.containedDependencyBackgroundColor;
    canvas.drawRect(backgroundRect, paint);
  }

  void _drawEmptySpaceHighlight(Canvas canvas, Size size) {
    if (hoveredRowId == null || hoveredDate == null) {
      return;
    }

    double? rowTop;
    double cumulativeRowTop = 0;
    for (final rowData in visibleRows) {
      if (rowData.id == hoveredRowId) {
        rowTop = cumulativeRowTop;
        break;
      }
      final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
      cumulativeRowTop += rowHeight * stackDepth;
    }

    if (rowTop == null) return;

    final dayStart = DateTime(hoveredDate!.year, hoveredDate!.month, hoveredDate!.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final startX = scale(dayStart);
    final endX = scale(dayEnd);

    final highlightRect = Rect.fromLTWH(startX, rowTop, endX - startX, rowHeight);

    final highlightPaint = Paint()..color = theme.emptySpaceHighlightColor;
    canvas.drawRect(highlightRect, highlightPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '+',
        style: TextStyle(color: theme.emptySpaceAddIconColor, fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final iconOffset =
        Offset(highlightRect.center.dx - textPainter.width / 2, highlightRect.center.dy - textPainter.height / 2);
    textPainter.paint(canvas, iconOffset);
  }

  LegacyGanttTask? _findTaskById(String taskId) {
    try {
      return data.firstWhere((task) => task.id == taskId);
    } catch (e) {
      return null;
    }
  }

  Rect? _findTaskRect(String taskId) {
    final task = _findTaskById(taskId);
    if (task == null) return null;

    double cumulativeRowTop = 0;
    for (var rowData in visibleRows) {
      if (rowData.id == task.rowId) {
        final double barTop = cumulativeRowTop + (task.stackIndex * rowHeight);
        final double barHeight = rowHeight * theme.barHeightRatio;
        final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;
        final double barStartX = scale(task.start);
        final double barEndX = scale(task.end);
        return Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barEndX - barStartX, barHeight);
      }
      final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
      cumulativeRowTop += rowHeight * stackDepth;
    }
    return null;
  }

  void _drawNonWorkingShading(Canvas canvas, RRect clipRRect, DateTime start, DateTime end) {
    if (workCalendar == null) return;

    final ranges = workCalendar!.getNonWorkingRanges(start, end);
    if (ranges.isEmpty) return;

    final patternColor = theme.backgroundColor.withValues(alpha: 0.6);

    canvas.save();
    canvas.clipRRect(clipRRect);

    for (final range in ranges) {
      if (range.$1.isAfter(range.$2)) continue;

      final rStart = scale(range.$1);
      final rEnd = scale(range.$2);

      if (rEnd <= rStart) continue;

      final rect = Rect.fromLTRB(rStart, clipRRect.top, rEnd, clipRRect.bottom);
      final rrect = RRect.fromRectAndRadius(rect, Radius.zero);

      _drawAngledPattern(canvas, rrect, patternColor, 2.0);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BarsCollectionPainter oldDelegate) =>
      !listEquals(oldDelegate.data, data) ||
      !listEquals(oldDelegate.conflictIndicators, conflictIndicators) ||
      !listEquals(oldDelegate.visibleRows, visibleRows) ||
      !mapEquals(oldDelegate.rowMaxStackDepth, rowMaxStackDepth) ||
      !listEquals(oldDelegate.dependencies, dependencies) ||
      oldDelegate.hoveredRowId != hoveredRowId ||
      oldDelegate.hoveredDate != hoveredDate ||
      !listEquals(oldDelegate.domain, domain) ||
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.draggedTaskId != draggedTaskId ||
      oldDelegate.drawingTask != drawingTask ||
      oldDelegate.ghostTaskStart != ghostTaskStart ||
      oldDelegate.ghostTaskEnd != ghostTaskEnd ||
      oldDelegate.ghostTaskRowId != ghostTaskRowId ||
      oldDelegate.theme != theme ||
      oldDelegate.enableDependencyCreation != enableDependencyCreation ||
      oldDelegate.dependencyDragStartTaskId != dependencyDragStartTaskId ||
      oldDelegate.dependencyDragStartIsFromStart != dependencyDragStartIsFromStart ||
      oldDelegate.dependencyDragCurrentPosition != dependencyDragCurrentPosition ||
      oldDelegate.hoveredTaskForDependency != hoveredTaskForDependency ||
      oldDelegate.hasCustomTaskBuilder != hasCustomTaskBuilder ||
      oldDelegate.hasCustomTaskContentBuilder != hasCustomTaskContentBuilder ||
      oldDelegate.workCalendar != workCalendar ||
      oldDelegate.translateY != translateY;
}
