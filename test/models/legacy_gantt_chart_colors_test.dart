import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_chart_colors.dart';

void main() {
  group('LegacyGanttChartColors', () {
    test('instantiates correctly with provided values', () {
      const barColorPrimary = Colors.blue;
      const barColorSecondary = Colors.red;
      const textColor = Colors.black;
      const backgroundColor = Colors.white;

      const colors = LegacyGanttChartColors(
        barColorPrimary: barColorPrimary,
        barColorSecondary: barColorSecondary,
        textColor: textColor,
        backgroundColor: backgroundColor,
      );

      expect(colors.barColorPrimary, barColorPrimary);
      expect(colors.barColorSecondary, barColorSecondary);
      expect(colors.textColor, textColor);
      expect(colors.backgroundColor, backgroundColor);
    });

    test('supports const constructor', () {
      const colors = LegacyGanttChartColors(
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.red,
        textColor: Colors.black,
        backgroundColor: Colors.white,
      );
      expect(colors, isA<LegacyGanttChartColors>());
    });
  });
}
