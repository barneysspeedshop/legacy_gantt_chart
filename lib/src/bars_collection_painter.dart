import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'models/legacy_gantt_row.dart';
import 'models/legacy_gantt_task.dart';
import 'models/legacy_gantt_dependency.dart';
import 'models/legacy_gantt_theme.dart';

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

  BarsCollectionPainter({
    required this.data,
    required this.domain,
    required this.visibleRows,
    required this.rowMaxStackDepth,
    required this.scale,
    required this.rowHeight,
    this.draggedTaskId,
    this.ghostTaskStart,
    this.ghostTaskEnd,
    required this.theme,
    this.hoveredRowId,
    this.hoveredDate,
    this.dependencies = const [],
    this.hasCustomTaskBuilder = false,
    this.hasCustomTaskContentBuilder = false,
    this.enableDependencyCreation = false,
    this.translateY = 0.0,
    this.dependencyDragStartTaskId,
    this.dependencyDragStartIsFromStart,
    this.dependencyDragCurrentPosition,
    this.hoveredTaskForDependency,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, translateY);
    double cumulativeRowTop = 0;

    // Draw dependency backgrounds first, so they appear behind task bars.
    _drawDependencyBackgrounds(canvas, size);

    // Draw the empty space highlight for creating new tasks.
    _drawEmptySpaceHighlight(canvas, size);

    // Create a map for quick lookup of tasks by rowId for visible rows.
    // This is more efficient than filtering the entire dataset multiple times.
    final Map<String, List<LegacyGanttTask>> tasksByRow = {};
    final visibleRowIds = visibleRows.map((r) => r.id).toSet();
    for (final task in data) {
      if (visibleRowIds.contains(task.rowId)) {
        tasksByRow.putIfAbsent(task.rowId, () => []).add(task);
      }
    }

    for (var rowData in visibleRows) {
      final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
      final double dynamicRowHeight = rowHeight * stackDepth;

      final tasksInThisRow = tasksByRow[rowData.id] ?? [];

      // 1. Draw highlight bars first (background)
      for (final task in tasksInThisRow.where((t) => t.isTimeRangeHighlight)) {
        final double barStartX = scale(task.start);
        final double barEndX = scale(task.end);

        // Performance optimization: only draw if the bar is visible on screen.
        if (barEndX < 0 || barStartX > size.width) {
          continue;
        }

        final double barWidth = max(0, barEndX - barStartX);

        final rect = Rect.fromLTWH(barStartX, cumulativeRowTop, barWidth, dynamicRowHeight);
        final paint = Paint()..color = task.color ?? theme.timeRangeHighlightColor;
        canvas.drawRect(rect, paint);
      }

      // 2. Draw regular event bars (without text or handles)
      if (!hasCustomTaskBuilder) {
        for (final task in tasksInThisRow.where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)) {
          // If a cell builder is provided for this task, the widget will handle rendering it.
          if (task.cellBuilder != null) {
            continue;
          }

          // Performance optimization: Check if the task's overall time range is
          // visible at all. If not, we can skip all drawing for this task,
          // including segments and text.
          final double taskStartX = scale(task.start);
          final double taskEndX = scale(task.end);
          if (taskEndX < 0 || taskStartX > size.width) {
            continue;
          }

          // Don't draw zero-duration tasks.
          if (taskEndX <= taskStartX) {
            continue;
          }

          final isBeingDragged = task.id == draggedTaskId;

          final double barTop = cumulativeRowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;

          final bool hasSegments = task.segments != null && task.segments!.isNotEmpty;

          // Define the RRect for the whole task, used for dependency handles and non-segmented bars.
          final RRect barRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(taskStartX, barTop + barVerticalCenterOffset, taskEndX - taskStartX, barHeight),
            theme.barCornerRadius,
          );

          if (hasSegments) {
            // --- Draw Segmented Bar ---
            for (final segment in task.segments!) {
              final double barStartX = scale(segment.start);
              final double barEndX = scale(segment.end);
              if (barEndX <= barStartX) {
                continue;
              }

              // A segment-level check is still useful as the overall task might
              // be visible, but this specific segment may not be.
              if (barEndX < 0 || barStartX > size.width) {
                continue;
              }

              final RRect segmentRRect = RRect.fromRectAndRadius(
                Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barEndX - barStartX, barHeight),
                theme.barCornerRadius,
              );

              final barPaint = Paint()
                ..color = (segment.color ?? task.color ?? theme.barColorPrimary)
                    .withValues(alpha: isBeingDragged ? 0.3 : 1.0);
              canvas.drawRRect(segmentRRect, barPaint);
            }
          } else {
            // --- Draw Single Continuous Bar (existing logic) ---
            // We can reuse the start/end coordinates calculated earlier.
            // Draw the bar
            final barPaint = Paint()
              ..color = (task.color ?? theme.barColorPrimary).withValues(alpha: isBeingDragged ? 0.3 : 1.0);
            canvas.drawRRect(barRRect, barPaint);

            // Draw completion progress
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

            // Draw summary pattern if needed
            if (task.isSummary) {
              _drawSummaryPattern(canvas, barRRect);
            }
          }
        }
      }

      // 3. Draw conflict indicators on top of the bars but under the text
      if (!hasCustomTaskBuilder) {
        for (final task in tasksInThisRow.where((t) => t.isOverlapIndicator)) {
          final double barStartX = scale(task.start);
          final double barEndX = scale(task.end);

          if (barEndX < 0 || barStartX > size.width) continue;

          final double barTop = cumulativeRowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;

          final RRect barRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barEndX - barStartX, barHeight),
            theme.barCornerRadius,
          );

          // We pass the task itself to check if it's a summary conflict.
          final isSummaryConflict = data.any(
              (t) => t.rowId == task.rowId && t.isSummary && t.start.isBefore(task.end) && t.end.isAfter(task.start));

          _drawConflictIndicator(canvas, barRRect, isSummaryConflict);
        }
      }

      // 4. Draw text and dependency handles on top of everything
      if (!hasCustomTaskBuilder) {
        for (final task in tasksInThisRow.where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator)) {
          final double taskStartX = scale(task.start);
          final double taskEndX = scale(task.end);
          if (taskEndX < 0 || taskStartX > size.width || taskEndX <= taskStartX) {
            continue;
          }

          final isBeingDragged = task.id == draggedTaskId;
          final double barTop = cumulativeRowTop + (task.stackIndex * rowHeight);
          final double barHeight = rowHeight * theme.barHeightRatio;
          final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;
          final RRect barRRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(taskStartX, barTop + barVerticalCenterOffset, taskEndX - taskStartX, barHeight),
            theme.barCornerRadius,
          );

          // --- Draw dependency handles ---
          if (enableDependencyCreation) {
            _drawDependencyHandles(canvas, barRRect, task, isBeingDragged);
          }

          // --- Draw Text ---
          if (task.name != null && task.name!.isNotEmpty && !hasCustomTaskBuilder && !hasCustomTaskContentBuilder) {
            // A task is in conflict if there is an overlap indicator that shares the same row,
            // stack index, and has an overlapping time range.
            final bool isInConflict = data.any((indicator) =>
                indicator.isOverlapIndicator &&
                indicator.rowId == task.rowId &&
                indicator.stackIndex == task.stackIndex &&
                // Check for time overlap
                indicator.start.isBefore(task.end) &&
                indicator.end.isAfter(task.start));

            if (isInConflict) {
              continue; // Skip drawing text for conflicted tasks
            }

            final double overallWidth = max(0, taskEndX - taskStartX);
            final textSpan = TextSpan(text: task.name, style: theme.taskTextStyle);
            final textPainter = TextPainter(
                text: textSpan,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                ellipsis: '...');
            textPainter.layout(minWidth: 0, maxWidth: max(0, overallWidth - 8)); // 4px padding on each side

            final textOffset = Offset(taskStartX + 4, barTop + (rowHeight - textPainter.height) / 2);

            canvas.save();
            canvas.clipRect(Rect.fromLTWH(taskStartX, barTop, overallWidth, rowHeight));
            textPainter.paint(canvas, textOffset);
            canvas.restore();
          }
        }
      }

      // Draw row border line
      if (theme.showRowBorders) {
        final y = cumulativeRowTop + dynamicRowHeight - 0.5; // Center on the pixel line
        final borderPaint = Paint()
          ..color = theme.rowBorderColor ?? theme.gridColor
          ..strokeWidth = 1.0;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), borderPaint);
      }

      cumulativeRowTop += dynamicRowHeight;
    }

    // Draw dependency lines on top of tasks.
    _drawDependencyLines(canvas, size);

    // Draw the in-progress dependency line.
    _drawInprogressDependencyLine(canvas, size);

    // 4. Draw ghost bar on top of everything if a task is being dragged
    if (draggedTaskId != null && ghostTaskStart != null && ghostTaskEnd != null) {
      final originalTask = data.firstWhere((t) => t.id == draggedTaskId,
          orElse: () => LegacyGanttTask(id: '', rowId: '', start: DateTime.now(), end: DateTime.now()));
      // Should not happen, but a good safeguard.
      if (originalTask.id.isEmpty) return;

      // Find the y-offset for this task's row again.
      double ghostRowTop = 0;
      bool foundRow = false;
      for (var rowData in visibleRows) {
        if (rowData.id == originalTask.rowId) {
          foundRow = true;
          break;
        }
        final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
        ghostRowTop += rowHeight * stackDepth;
      }

      if (foundRow) {
        final double barTop = ghostRowTop + (originalTask.stackIndex * rowHeight);
        final double barHeight = rowHeight * theme.barHeightRatio;
        final double barVerticalCenterOffset = (rowHeight - barHeight) / 2;

        final double barStartX = scale(ghostTaskStart!);
        final double barEndX = scale(ghostTaskEnd!);
        final double barWidth = max(0, barEndX - barStartX);

        final RRect barRRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barStartX, barTop + barVerticalCenterOffset, barWidth, barHeight),
          theme.barCornerRadius,
        );

        // Draw the ghost bar
        final barPaint = Paint()..color = (originalTask.color ?? theme.ghostBarColor).withValues(alpha: 0.7);
        canvas.drawRRect(barRRect, barPaint);
        // Not drawing text on ghost bar for simplicity
      }
    }
    canvas.restore();
  }

  // Reusable helper to draw angled line patterns within a rounded rectangle.
  void _drawAngledPattern(Canvas canvas, RRect rrect, Color color, double strokeWidth) {
    final patternPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRRect(rrect);

    const double lineSpacing = 8.0;
    // The loop needs to cover the full diagonal length to ensure the pattern is drawn across the entire clipped area.
    for (double i = -rrect.height; i < rrect.width; i += lineSpacing) {
      canvas.drawLine(
        Offset(rrect.left + i, rrect.top),
        Offset(rrect.left + i + rrect.height, rrect.bottom),
        patternPaint,
      );
    }
    canvas.restore();
  }

  void _drawSummaryPattern(Canvas canvas, RRect rrect) {
    // A thick stroke can make the pattern look muddy. 1.5 is a good balance.
    _drawAngledPattern(canvas, rrect, theme.summaryBarColor, 1.5);
  }

  void _drawConflictIndicator(Canvas canvas, RRect rrect, bool isSummaryConflict) {
    // To ensure the conflict pattern is clear and not blended with underlying bars,
    // we no longer erase the background. Instead, we draw a semi-transparent overlay.

    // Deflate the indicator to only show on the bottom 30% of the bar

    // Next, draw the semi-transparent red background for the conflict area.
    // canvas.drawRRect(indicatorRRect, backgroundPaint);
    // _drawAngledPattern(canvas, indicatorRRect, theme.conflictBarColor.withValues(alpha: 0.85), 1.0);
  }

  void _drawDependencyHandles(Canvas canvas, RRect rrect, LegacyGanttTask task, bool isBeingDragged) {
    if (isBeingDragged || task.isSummary) return;

    final handlePaint = Paint()..color = theme.dependencyLineColor.withValues(alpha: 0.8);
    const handleRadius = 4.0;

    // Left handle
    final leftCenter = Offset(rrect.left, rrect.center.dy);
    canvas.drawCircle(leftCenter, handleRadius, handlePaint);

    // Right handle
    final rightCenter = Offset(rrect.right, rrect.center.dy);
    canvas.drawCircle(rightCenter, handleRadius, handlePaint);

    // Highlight task if it's being hovered over as a potential dependency target
    if (task.id == hoveredTaskForDependency) {
      final borderPaint = Paint()
        ..color = theme.dependencyLineColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(rrect.inflate(2.0), borderPaint);
    }
  }

  void _drawDependencyBackgrounds(Canvas canvas, Size size) {
    if (dependencies.isEmpty) return;
    for (final dependency in dependencies) {
      if (dependency.type == DependencyType.contained) {
        _drawContainedDependency(canvas, dependency);
      }
    }
  }

  void _drawInprogressDependencyLine(Canvas canvas, Size size) {
    if (dependencyDragStartTaskId == null || dependencyDragCurrentPosition == null) {
      return;
    }

    final startTaskRect = _findTaskRect(dependencyDragStartTaskId!);
    if (startTaskRect == null) return;

    final startX = (dependencyDragStartIsFromStart ?? false) ? startTaskRect.left : startTaskRect.right;
    final startY = startTaskRect.center.dy;

    final endX = dependencyDragCurrentPosition!.dx;
    final endY = dependencyDragCurrentPosition!.dy;

    final paint = Paint()
      ..color = theme.dependencyLineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

    // Draw arrowhead at the end
    final arrowPath = Path();
    const arrowSize = 5.0;
    arrowPath.moveTo(endX - arrowSize, endY - arrowSize / 2);
    arrowPath.lineTo(endX, endY);
    arrowPath.lineTo(endX - arrowSize, endY + arrowSize / 2);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawDependencyLines(Canvas canvas, Size size) {
    if (dependencies.isEmpty) return;
    for (final dependency in dependencies) {
      switch (dependency.type) {
        case DependencyType.finishToStart:
          _drawFinishToStartDependency(canvas, dependency);
          break;
        case DependencyType.startToStart:
          _drawStartToStartDependency(canvas, dependency);
          break;
        case DependencyType.finishToFinish:
          _drawFinishToFinishDependency(canvas, dependency);
          break;
        case DependencyType.startToFinish:
          _drawStartToFinishDependency(canvas, dependency);
          break;
        case DependencyType.contained:
          // Contained is a background, not a line.
          break;
      }
    }
  }

  void _drawFinishToStartDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final predecessorRect = _findTaskRect(dependency.predecessorTaskId);
    final successorRect = _findTaskRect(dependency.successorTaskId);

    if (predecessorRect == null || successorRect == null) return;

    final startX = predecessorRect.right;
    final startY = predecessorRect.center.dy;
    final endX = successorRect.left;
    final endY = successorRect.center.dy;

    final paint = Paint()
      ..color = theme.dependencyLineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(startX, startY);

    // Add a small horizontal segment before turning
    final controlXOffset = (endX - startX).abs() > 20 ? 10.0 : (endX - startX).abs() / 2;
    final controlX1 = startX + controlXOffset;
    final controlX2 = endX - controlXOffset;

    // Simple S-curve for vertical connections
    path.cubicTo(controlX1, startY, controlX2, endY, endX, endY);

    canvas.drawPath(path, paint);

    // Draw arrowhead
    final arrowPath = Path();
    const arrowSize = 5.0;
    arrowPath.moveTo(endX - arrowSize, endY - arrowSize / 2);
    arrowPath.lineTo(endX, endY);
    arrowPath.lineTo(endX - arrowSize, endY + arrowSize / 2);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawStartToStartDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final predecessorRect = _findTaskRect(dependency.predecessorTaskId);
    final successorRect = _findTaskRect(dependency.successorTaskId);

    if (predecessorRect == null || successorRect == null) return;

    final startX = predecessorRect.left;
    final startY = predecessorRect.center.dy;
    final endX = successorRect.left;
    final endY = successorRect.center.dy;

    final paint = Paint()
      ..color = theme.dependencyLineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(startX, startY);

    final controlXOffset = (endX - startX).abs() > 20 ? 10.0 : (endX - startX).abs() / 2;
    final controlX1 = startX - controlXOffset;
    final controlX2 = endX - controlXOffset;

    path.cubicTo(controlX1, startY, controlX2, endY, endX, endY);
    canvas.drawPath(path, paint);

    // Draw arrowhead (points right, towards successor task body)
    final arrowPath = Path();
    const arrowSize = 5.0;
    arrowPath.moveTo(endX - arrowSize, endY - arrowSize / 2);
    arrowPath.lineTo(endX, endY);
    arrowPath.lineTo(endX - arrowSize, endY + arrowSize / 2);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawFinishToFinishDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final predecessorRect = _findTaskRect(dependency.predecessorTaskId);
    final successorRect = _findTaskRect(dependency.successorTaskId);

    if (predecessorRect == null || successorRect == null) return;

    final startX = predecessorRect.right;
    final startY = predecessorRect.center.dy;
    final endX = successorRect.right;
    final endY = successorRect.center.dy;

    final paint = Paint()
      ..color = theme.dependencyLineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(startX, startY);

    final controlXOffset = (endX - startX).abs() > 20 ? 10.0 : (endX - startX).abs() / 2;
    final controlX1 = startX + controlXOffset;
    final controlX2 = endX + controlXOffset;

    path.cubicTo(controlX1, startY, controlX2, endY, endX, endY);
    canvas.drawPath(path, paint);

    // Draw arrowhead (points left, towards successor task body)
    final arrowPath = Path();
    const arrowSize = 5.0;
    arrowPath.moveTo(endX + arrowSize, endY - arrowSize / 2);
    arrowPath.lineTo(endX, endY);
    arrowPath.lineTo(endX + arrowSize, endY + arrowSize / 2);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawStartToFinishDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    final predecessorRect = _findTaskRect(dependency.predecessorTaskId);
    final successorRect = _findTaskRect(dependency.successorTaskId);

    if (predecessorRect == null || successorRect == null) return;

    final startX = predecessorRect.left;
    final startY = predecessorRect.center.dy;
    final endX = successorRect.right;
    final endY = successorRect.center.dy;

    final paint = Paint()
      ..color = theme.dependencyLineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // This can be a simple line as it's less common and less likely to need complex routing.
    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

    // Draw arrowhead (points left, towards successor task body)
    final arrowPath = Path();
    const arrowSize = 5.0;
    arrowPath.moveTo(endX + arrowSize, endY - arrowSize / 2);
    arrowPath.lineTo(endX, endY);
    arrowPath.lineTo(endX + arrowSize, endY + arrowSize / 2);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawContainedDependency(Canvas canvas, LegacyGanttTaskDependency dependency) {
    // This logic finds the full vertical span of a summary task's group.
    // It assumes child rows immediately follow their parent in `visibleRows`
    // and a new group is denoted by the next summary task.
    final predecessorTask = _findTaskById(dependency.predecessorTaskId);
    if (predecessorTask == null || !predecessorTask.isSummary) {
      return;
    }

    double? groupStartY;
    double? groupEndY;

    double currentY = 0;
    bool inGroup = false;

    for (final rowData in visibleRows) {
      final int stackDepth = rowMaxStackDepth[rowData.id] ?? 1;
      final double rowHeightWithStack = rowHeight * stackDepth;

      if (inGroup) {
        // Check if the current row starts a new summary group.
        final bool isNewGroup = data.any((task) => task.rowId == rowData.id && task.isSummary);
        if (isNewGroup) {
          inGroup = false; // The current group has ended.
        } else {
          // This is a child row, so extend the group's bottom boundary.
          groupEndY = currentY + rowHeightWithStack;
        }
      }

      if (rowData.id == predecessorTask.rowId) {
        inGroup = true;
        groupStartY = currentY;
        groupEndY = currentY + rowHeightWithStack;
      }

      currentY += rowHeightWithStack;
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

    // Find the Y position of the hovered row.
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

    // Calculate the start and end of the day.
    final dayStart = DateTime(hoveredDate!.year, hoveredDate!.month, hoveredDate!.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final startX = scale(dayStart);
    final endX = scale(dayEnd);

    final highlightRect = Rect.fromLTWH(startX, rowTop, endX - startX, rowHeight);

    // Draw the highlight box.
    final highlightPaint = Paint()..color = theme.emptySpaceHighlightColor;
    canvas.drawRect(highlightRect, highlightPaint);

    // Draw the plus icon in the center.
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

  @override
  bool shouldRepaint(covariant BarsCollectionPainter oldDelegate) =>
      !listEquals(oldDelegate.data, data) ||
      !listEquals(oldDelegate.visibleRows, visibleRows) ||
      !mapEquals(oldDelegate.rowMaxStackDepth, rowMaxStackDepth) ||
      !listEquals(oldDelegate.dependencies, dependencies) ||
      oldDelegate.hoveredRowId != hoveredRowId ||
      oldDelegate.hoveredDate != hoveredDate ||
      !listEquals(oldDelegate.domain, domain) ||
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.draggedTaskId != draggedTaskId ||
      oldDelegate.ghostTaskStart != ghostTaskStart ||
      oldDelegate.ghostTaskEnd != ghostTaskEnd ||
      oldDelegate.theme != theme ||
      oldDelegate.enableDependencyCreation != enableDependencyCreation ||
      oldDelegate.dependencyDragStartTaskId != dependencyDragStartTaskId ||
      oldDelegate.dependencyDragStartIsFromStart != dependencyDragStartIsFromStart ||
      oldDelegate.dependencyDragCurrentPosition != dependencyDragCurrentPosition ||
      oldDelegate.hoveredTaskForDependency != hoveredTaskForDependency ||
      oldDelegate.hasCustomTaskBuilder != hasCustomTaskBuilder ||
      oldDelegate.hasCustomTaskContentBuilder != hasCustomTaskContentBuilder ||
      oldDelegate.translateY != translateY;
}
