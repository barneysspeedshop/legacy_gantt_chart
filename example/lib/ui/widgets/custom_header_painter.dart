import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:intl/intl.dart';

class CustomHeaderPainter extends CustomPainter {
  final double Function(DateTime) scale;
  final List<DateTime> visibleDomain;
  final List<DateTime> totalDomain;
  final LegacyGanttTheme theme;
  final String selectedLocale;

  CustomHeaderPainter({
    required this.scale,
    required this.visibleDomain,
    required this.totalDomain,
    required this.theme,
    required this.selectedLocale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDomain.isEmpty || visibleDomain.isEmpty) {
      return;
    }
    final visibleDuration = visibleDomain.last.difference(visibleDomain.first);
    final monthTextStyle = theme.axisTextStyle.copyWith(fontWeight: FontWeight.bold);
    final dayTextStyle = theme.axisTextStyle.copyWith(fontSize: 10);

    // Determine the tick interval based on the visible duration.
    Duration tickInterval;
    if (visibleDuration.inDays > 60) {
      tickInterval = const Duration(days: 7);
    } else if (visibleDuration.inDays > 14) {
      tickInterval = const Duration(days: 2);
    } else {
      tickInterval = const Duration(days: 1);
    }

    DateTime current = totalDomain.first;
    String? lastMonth;
    while (current.isBefore(totalDomain.last)) {
      final next = current.add(tickInterval);
      final monthFormat = DateFormat('MMMM yyyy', selectedLocale);
      final dayFormat = DateFormat('d', selectedLocale);

      // Month label
      final monthStr = monthFormat.format(current);
      if (monthStr != lastMonth) {
        lastMonth = monthStr;
        final monthStart = DateTime(current.year, current.month, 1);
        final monthEnd = DateTime(current.year, current.month + 1, 0);
        final startX = scale(monthStart.isBefore(visibleDomain.first) ? visibleDomain.first : monthStart);
        final endX = scale(monthEnd.isAfter(visibleDomain.last) ? visibleDomain.last : monthEnd);

        final textSpan = TextSpan(text: monthStr, style: monthTextStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        if (endX > startX) {
          textPainter.paint(
            canvas,
            Offset(startX + (endX - startX) / 2 - textPainter.width / 2, 0),
          );
        }
      }

      // Day label
      final dayX = scale(current);
      final dayText = dayFormat.format(current);
      final textSpan = TextSpan(text: dayText, style: dayTextStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(dayX - textPainter.width / 2, 20),
      );

      current = next;
    }
  }

  @override
  bool shouldRepaint(covariant CustomHeaderPainter oldDelegate) =>
      oldDelegate.scale != scale ||
      !listEquals(oldDelegate.visibleDomain, visibleDomain) ||
      !listEquals(oldDelegate.totalDomain, totalDomain) ||
      oldDelegate.theme != theme ||
      oldDelegate.selectedLocale != selectedLocale;
}
