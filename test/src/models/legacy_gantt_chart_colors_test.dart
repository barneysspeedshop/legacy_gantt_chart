import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_chart_colors.dart';

void main() {
  group('LegacyGanttChartColors', () {
    test('instantiation', () {
      const colors = LegacyGanttChartColors(
        barColorPrimary: Colors.blue,
        barColorSecondary: Colors.green,
        textColor: Colors.black,
        backgroundColor: Colors.white,
      );

      expect(colors.barColorPrimary, Colors.blue);
      expect(colors.barColorSecondary, Colors.green);
      expect(colors.textColor, Colors.black);
      expect(colors.backgroundColor, Colors.white);
    });
  });
}
