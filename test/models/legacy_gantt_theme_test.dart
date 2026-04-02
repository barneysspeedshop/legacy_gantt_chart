import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('LegacyGanttTheme', () {
    test('instantiation with defaults', () {
      final theme = LegacyGanttTheme(
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.lightBlue,
        textColor: Colors.black,
        backgroundColor: Colors.white,
      );

      expect(theme.barColorPrimary, Colors.blue);
      expect(theme.barHeightRatio, 0.7); // Default
    });

    test('fromTheme factory', () {
      final themeData = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Colors.purple,
          secondary: Colors.amber,
          surface: Colors.grey,
        ),
      );

      final ganttTheme = LegacyGanttTheme.fromTheme(themeData);

      expect(ganttTheme.barColorPrimary, Colors.purple);
      expect(ganttTheme.barColorSecondary, Colors.amber);
      expect(ganttTheme.backgroundColor, Colors.grey);
    });

    test('fromTheme handles dark mode components', () {
      final themeData = ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.blue,
          secondary: Colors.teal,
        ),
      );

      final ganttTheme = LegacyGanttTheme.fromTheme(themeData);

      expect(ganttTheme.nowLineColor, equals(Colors.redAccent));
    });

    test('copyWith works for all style components', () {
      final theme = LegacyGanttTheme(
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.lightBlue,
        textColor: Colors.black,
        backgroundColor: Colors.white,
      );

      final updated = theme.copyWith(
        barColorPrimary: Colors.red,
        barHeightRatio: 0.8,
        gridColor: Colors.black12,
        summaryBarColor: Colors.black,
        conflictBarColor: Colors.redAccent,
        ghostBarColor: Colors.blueAccent,
        axisTextStyle: const TextStyle(fontSize: 14),
        taskTextStyle: const TextStyle(fontSize: 10),
        dependencyLineColor: Colors.black54,
        timeRangeHighlightColor: Colors.grey,
        containedDependencyBackgroundColor: Colors.grey,
        emptySpaceHighlightColor: Colors.blue,
        emptySpaceAddIconColor: Colors.blue,
        barCornerRadius: const Radius.circular(8.0),
        showRowBorders: true,
        rowBorderColor: Colors.black,
        weekendColor: Colors.grey,
        criticalPathColor: Colors.yellow,
        nowLineColor: Colors.orange,
        slackBarColor: Colors.cyan,
        resizeTooltipBackgroundColor: Colors.black,
        resizeTooltipFontColor: Colors.white,
        resizeTooltipDateFormat: 'yyyy-MM-dd',
      );

      expect(updated.barColorPrimary, Colors.red);
      expect(updated.barHeightRatio, 0.8);
      expect(updated.gridColor, Colors.black12);
      expect(updated.resizeTooltipDateFormat, 'yyyy-MM-dd');
      expect(updated.backgroundColor, Colors.white); // Preserved
    });
  });
}
