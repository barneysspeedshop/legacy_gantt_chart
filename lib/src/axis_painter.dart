// packages/gantt_chart/lib/src/axis_painter.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import 'models/legacy_gantt_theme.dart';

/// A [CustomPainter] that draws the time axis and vertical grid lines for the Gantt chart.
///
/// This painter is versatile and can be used to draw both the main background grid
/// and the timeline header at the top of the chart. It dynamically adjusts the
/// density of the grid lines and the format of the labels based on the visible
/// time duration, providing a clear and readable scale at any zoom level.
class AxisPainter extends CustomPainter {
  /// The starting x-coordinate for painting.
  final double x;

  /// The vertical position where the axis line is drawn. For the header, this is
  /// typically the vertical center. For the background grid, it's the top edge.
  final double y;

  /// The total width of the area to be painted.
  final double width;

  /// The total height of the area to be painted. This is used to draw the vertical
  /// grid lines across the entire height of the chart content area.
  final double height;

  /// A function that converts a [DateTime] to its corresponding horizontal (x-axis) pixel value.
  final double Function(DateTime) scale;

  /// The total date range of the entire chart, from the earliest start date to the
  /// latest end date. This is used to generate all possible tick marks.
  final List<DateTime> domain;

  /// The currently visible date range. This is used to determine the appropriate
  /// interval and format for the tick marks and labels (e.g., days, hours, minutes).
  final List<DateTime> visibleDomain;

  /// The theme data that defines the colors and styles for the grid lines and labels.
  final LegacyGanttTheme theme;

  /// An optional builder function to customize the labels on the timeline axis.
  final String Function(DateTime, Duration)? timelineAxisLabelBuilder;

  /// The color to use for highlighting weekend days.
  final Color? weekendColor;

  /// A list of integers representing the days of the week to be highlighted as weekends.
  final List<int>? weekendDays;

  /// Whether to draw the vertical grid lines (ticks).
  final bool showGridLines;

  /// Whether to vertically center the labels within the [height] of the painter area.
  /// If false, labels are drawn just above the [y] line.
  final bool verticallyCenterLabels;

  AxisPainter({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.scale,
    required this.domain,
    required this.visibleDomain,
    required this.theme,
    this.timelineAxisLabelBuilder,
    this.weekendColor,
    this.weekendDays,
    this.showGridLines = true,
    this.verticallyCenterLabels = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1.0;

    if (domain.isEmpty || visibleDomain.isEmpty) return;

    if (weekendColor != null && weekendDays != null && weekendDays!.isNotEmpty) {
      final weekendPaint = Paint()..color = weekendColor!;
      DateTime currentDay = DateTime(visibleDomain.first.year, visibleDomain.first.month, visibleDomain.first.day);
      while (currentDay.isBefore(visibleDomain.last)) {
        if (weekendDays!.contains(currentDay.weekday)) {
          final startX = scale(currentDay);
          final endX = scale(currentDay.add(const Duration(days: 1)));
          if (endX > startX) {
            canvas.drawRect(Rect.fromLTWH(startX, y, endX - startX, height), weekendPaint);
          }
        }
        currentDay = currentDay.add(const Duration(days: 1));
      }
    }

    final visibleDuration = visibleDomain.last.difference(visibleDomain.first);
    final usableSteps = _tickSteps.where((s) => s.interval.inMilliseconds * 2 <= visibleDuration.inMilliseconds);

    _TickStep? selectedStep;

    for (final step in usableSteps) {
      final t1 = visibleDomain.first;
      final t2 = t1.add(step.interval);
      final pixelsPerTick = (scale(t2) - scale(t1)).abs();
      final testLabel = step.labelFormat(DateTime(2023, 1, 1, 10, 0)); // Sample date
      final textStyle = theme.axisTextStyle;
      final textSpan = TextSpan(text: testLabel, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();

      if (pixelsPerTick > textPainter.width + 8) {
        selectedStep = step;
        break;
      }
    }

    selectedStep ??= usableSteps.isNotEmpty ? usableSteps.last : _tickSteps.last;

    final Duration tickInterval = selectedStep.interval;
    final String Function(DateTime) labelFormat = selectedStep.labelFormat;

    final List<MapEntry<double, DateTime>> tickPositions = [];

    if (visibleDomain.isNotEmpty && domain.first.isBefore(domain.last)) {
      DateTime currentTick = _roundDownTo(visibleDomain.first, tickInterval);

      if (currentTick.isBefore(domain.first)) {
        currentTick = _roundDownTo(domain.first, tickInterval);
        if (currentTick.isBefore(domain.first)) {
          currentTick = currentTick.add(tickInterval);
        }
      }

      final effectiveEnd = visibleDomain.last.isBefore(domain.last) ? visibleDomain.last : domain.last;
      final loopEnd = effectiveEnd.add(tickInterval);

      while (currentTick.isBefore(loopEnd) &&
          (currentTick.isBefore(domain.last) || currentTick.isAtSameMomentAs(domain.last))) {
        tickPositions.add(MapEntry(scale(currentTick), currentTick));
        currentTick = currentTick.add(tickInterval);
      }
    }

    bool isFirstVisibleTickFound = false;
    DateTime? previousTickTime;
    double lastLabelRightEdge = double.negativeInfinity;

    for (final entry in tickPositions) {
      final tickX = entry.key;
      final tickTime = entry.value;

      String label;
      final bool isSubDaily = tickInterval.inHours < 24 && tickInterval.inDays < 1;
      final bool isNewDay = previousTickTime != null && tickTime.day != previousTickTime.day;
      final bool isVisible = tickX >= x;

      if (isSubDaily && ((isVisible && !isFirstVisibleTickFound) || isNewDay)) {
        label = DateFormat('MMM d').format(tickTime);
        if (isVisible) {
          isFirstVisibleTickFound = true;
        }
      } else {
        label = timelineAxisLabelBuilder != null
            ? timelineAxisLabelBuilder!(tickTime, tickInterval)
            : labelFormat(tickTime);
      }

      previousTickTime = tickTime;

      if (showGridLines) {
        canvas.drawLine(
          Offset(tickX, y),
          Offset(tickX, y + height),
          paint,
        );
      }

      final textStyle = theme.axisTextStyle;
      if (textStyle.color != Colors.transparent) {
        final textSpan = TextSpan(text: label, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();

        final double labelWidth = textPainter.width;
        final double labelX = tickX - (labelWidth / 2);

        // Check for collision with the previously drawn label
        // We add a small padding (8.0) to ensure readability
        if (labelX >= lastLabelRightEdge + 8.0) {
          double textY;
          if (verticallyCenterLabels) {
            textY = y + (height - textPainter.height) / 2;
          } else {
            textY = y - textPainter.height;
          }

          textPainter.paint(
            canvas,
            Offset(labelX, textY),
          );

          lastLabelRightEdge = labelX + labelWidth;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant AxisPainter oldDelegate) =>
      theme != oldDelegate.theme ||
      width != oldDelegate.width ||
      height != oldDelegate.height ||
      showGridLines != oldDelegate.showGridLines ||
      verticallyCenterLabels != oldDelegate.verticallyCenterLabels ||
      !listEquals(domain, oldDelegate.domain) ||
      (visibleDomain.isNotEmpty && oldDelegate.visibleDomain.isNotEmpty
          ? visibleDomain.first != oldDelegate.visibleDomain.first ||
              visibleDomain.last != oldDelegate.visibleDomain.last
          : listEquals(visibleDomain, oldDelegate.visibleDomain));

  DateTime _roundDownTo(DateTime dt, Duration delta) {
    if (delta.inDays >= 7) {}
    final int ms = dt.millisecondsSinceEpoch;
    final int deltaMs = delta.inMilliseconds;
    final int offset = dt.timeZoneOffset.inMilliseconds;
    final int localMs = ms + offset;
    final int roundedLocalMs = (localMs ~/ deltaMs) * deltaMs;
    final int resultMs = roundedLocalMs - offset;

    return DateTime.fromMillisecondsSinceEpoch(
      resultMs,
      isUtc: dt.isUtc,
    );
  }
}

class _TickStep {
  final Duration interval;
  final String Function(DateTime) labelFormat;

  const _TickStep(this.interval, this.labelFormat);
}

final List<_TickStep> _tickSteps = [
  _TickStep(const Duration(minutes: 1), (dt) => DateFormat('h:mm:ss').format(dt)),
  _TickStep(const Duration(minutes: 5), (dt) => DateFormat('h:mm').format(dt)),
  _TickStep(const Duration(minutes: 15), (dt) => DateFormat('h:mm a').format(dt)),
  _TickStep(const Duration(minutes: 30), (dt) => DateFormat('h:mm a').format(dt)),
  _TickStep(const Duration(hours: 1), (dt) => DateFormat('h:mm a').format(dt)),
  _TickStep(const Duration(hours: 2), (dt) => DateFormat('h a').format(dt)),
  _TickStep(const Duration(hours: 6), (dt) => DateFormat('h a').format(dt)),
  _TickStep(const Duration(hours: 12), (dt) => DateFormat('ha').format(dt)),
  _TickStep(const Duration(days: 1), (dt) => DateFormat('EEE d').format(dt)),
  _TickStep(const Duration(days: 2), (dt) => DateFormat('d MMM').format(dt)),
  _TickStep(const Duration(days: 7), (dt) => 'Week ${_weekNumber(dt)}'),
  _TickStep(const Duration(days: 30), (dt) => DateFormat('MMM yyyy').format(dt)),
  _TickStep(const Duration(days: 365), (dt) => DateFormat('yyyy').format(dt)),
];

int _weekNumber(DateTime date) {
  final dayOfYear = int.parse(DateFormat('D').format(date));
  final woy = ((dayOfYear - date.weekday + 10) / 7).floor();
  if (woy < 1) return 52;
  if (woy > 52) return 52;
  return woy;
}
