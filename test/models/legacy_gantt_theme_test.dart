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

    test('copyWith works', () {
      final theme = LegacyGanttTheme(
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.lightBlue,
        textColor: Colors.black,
        backgroundColor: Colors.white,
      );

      final updated = theme.copyWith(
        barColorPrimary: Colors.red,
        barHeightRatio: 0.8,
      );

      expect(updated.barColorPrimary, Colors.red);
      expect(updated.barHeightRatio, 0.8);
      expect(updated.backgroundColor, Colors.white); // Preserved
    });
  });
}
