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
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.gridColor
      ..strokeWidth = 1.0;

    if (domain.isEmpty || visibleDomain.isEmpty) return;

    final visibleDuration = visibleDomain.last.difference(visibleDomain.first);

    Duration tickInterval;
    String Function(DateTime) labelFormat;

    if (visibleDuration.inDays > 60) {
      tickInterval = const Duration(days: 7);
      labelFormat = (dt) => 'Week ${_weekNumber(dt)}';
    } else if (visibleDuration.inDays > 14) {
      tickInterval = const Duration(days: 2);
      labelFormat = (dt) => DateFormat('d MMM').format(dt);
    } else if (visibleDuration.inDays > 3) {
      tickInterval = const Duration(days: 1);
      labelFormat = (dt) => DateFormat('EEE d').format(dt);
    } else if (visibleDuration.inHours > 48) {
      tickInterval = const Duration(hours: 12);
      labelFormat = (dt) => DateFormat('ha').format(dt);
    } else if (visibleDuration.inHours > 24) {
      tickInterval = const Duration(hours: 6);
      labelFormat = (dt) => DateFormat('ha').format(dt);
    } else if (visibleDuration.inHours > 12) {
      tickInterval = const Duration(hours: 2);
      labelFormat = (dt) => DateFormat('h a').format(dt);
    } else if (visibleDuration.inHours > 6) {
      tickInterval = const Duration(hours: 1);
      labelFormat = (dt) => DateFormat('h:mm a').format(dt);
    } else if (visibleDuration.inHours > 3) {
      tickInterval = const Duration(minutes: 30);
      labelFormat = (dt) => DateFormat('h:mm a').format(dt);
    } else if (visibleDuration.inMinutes > 90) {
      tickInterval = const Duration(minutes: 15);
      labelFormat = (dt) => DateFormat('h:mm a').format(dt);
    } else if (visibleDuration.inMinutes > 30) {
      tickInterval = const Duration(minutes: 5);
      labelFormat = (dt) => DateFormat('h:mm').format(dt);
    } else {
      tickInterval = const Duration(minutes: 1);
      labelFormat = (dt) => DateFormat('h:mm:ss').format(dt);
    }

    final List<MapEntry<double, DateTime>> tickPositions = [];

    // Find the first tick position that is on or after the start of the total domain.
    // Round down to the nearest interval, then add intervals until we are in view.
    if (domain.first.isBefore(domain.last)) {
      DateTime currentTick = _roundDownTo(domain.first, tickInterval);
      if (currentTick.isBefore(domain.first)) {
        currentTick = currentTick.add(tickInterval);
      }

      // Generate ticks across the entire domain to ensure they are present when scrolling.
      while (currentTick.isBefore(domain.last)) {
        tickPositions.add(MapEntry(scale(currentTick), currentTick));
        currentTick = currentTick.add(tickInterval);
      }
    }

    for (final entry in tickPositions) {
      final tickX = entry.key;
      final tickTime = entry.value;
      final label = timelineAxisLabelBuilder != null
          ? timelineAxisLabelBuilder!(tickTime, tickInterval)
          : labelFormat(tickTime);

      canvas.drawLine(
        Offset(tickX, y),
        Offset(tickX, y + height),
        paint,
      );

      final textStyle = theme.axisTextStyle;
      if (textStyle.color != Colors.transparent) {
        final textSpan = TextSpan(text: label, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(tickX - (textPainter.width / 2), y - textPainter.height),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AxisPainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.scale != scale ||
      !listEquals(oldDelegate.visibleDomain, visibleDomain) ||
      oldDelegate.width != width ||
      oldDelegate.height != height;

  DateTime _roundDownTo(DateTime dt, Duration delta) {
    final ms = dt.millisecondsSinceEpoch;
    final deltaMs = delta.inMilliseconds;
    return DateTime.fromMillisecondsSinceEpoch(
      (ms ~/ deltaMs) * deltaMs,
      isUtc: dt.isUtc,
    );
  }

  int _weekNumber(DateTime date) {
    // A simple week number calculation.
    final dayOfYear = int.parse(DateFormat('D').format(date));
    final woy = ((dayOfYear - date.weekday + 10) / 7).floor();
    if (woy < 1) return 52; // Fallback for early days in the year.
    if (woy > 52) return 52; // Fallback for late days in the year.
    return woy;
  }
}
