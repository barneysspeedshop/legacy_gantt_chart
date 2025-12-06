import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';

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
      expect(theme.barHeightRatio, 0.7); // default
    });

    test('fromTheme factory', () {
      final themeData = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Colors.purple,
          secondary: Colors.amber,
          surface: Colors.grey,
          onSurface: Colors.black,
        ),
      );
      final ganttTheme = LegacyGanttTheme.fromTheme(themeData);
      expect(ganttTheme.barColorPrimary, Colors.purple);
      expect(ganttTheme.barColorSecondary, Colors.amber);
      expect(ganttTheme.backgroundColor, Colors.grey);
    });

    test('copyWith', () {
      final theme = LegacyGanttTheme(
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.lightBlue,
        textColor: Colors.black,
        backgroundColor: Colors.white,
      );

      final newTheme = theme.copyWith(barColorPrimary: Colors.red);
      expect(newTheme.barColorPrimary, Colors.red);
      expect(newTheme.barColorSecondary, Colors.lightBlue);
    });
  });
}
