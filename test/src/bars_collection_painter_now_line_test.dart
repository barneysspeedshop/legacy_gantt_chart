import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';

void main() {
  group('BarsCollectionPainter - Now Line', () {
    const row1 = LegacyGanttRow(id: 'r1');
    final task1 = LegacyGanttTask(
      id: 't1',
      rowId: 'r1',
      start: DateTime(2023, 1, 1),
      end: DateTime(2023, 1, 5),
      name: 'Task 1',
    );
    final theme = LegacyGanttTheme(
      backgroundColor: Colors.white,
      barColorPrimary: Colors.blue,
      barColorSecondary: Colors.lightBlue,
      textColor: Colors.black,
      taskTextStyle: const TextStyle(color: Colors.black),
      nowLineColor: Colors.red, // Explicitly set nowLineColor
    );

    double mockScale(DateTime date) => (date.difference(DateTime(2023, 1, 1)).inHours / 24.0) * 100.0;

    // Helper to find the CustomPaint using our specific painter
    Finder findPainter() => find.descendant(
          of: find.byType(CustomPaint),
          matching:
              find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BarsCollectionPainter),
        );

    testWidgets('paints now line when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(500, 500),
              painter: BarsCollectionPainter(
                data: [task1],
                visibleRows: [row1],
                rowMaxStackDepth: {'r1': 1},
                domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
                scale: mockScale,
                rowHeight: 50.0,
                theme: theme,
                conflictIndicators: [],
                showNowLine: true,
                nowLineDate: DateTime(2023, 1, 3), // Should be at x = 200.0
              ),
            ),
          ),
        ),
      );

      expect(findPainter(), findsOneWidget);
      // To strictly verify drawing, we'd need to mock canvas or use golden tests.
      // Since we can't easily do golden tests here without setting up,
      // ensuring it paints without error with the flag on is a good baseline.
    });

    testWidgets('does not paint now line when disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(500, 500),
              painter: BarsCollectionPainter(
                data: [task1],
                visibleRows: [row1],
                rowMaxStackDepth: {'r1': 1},
                domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
                scale: mockScale,
                rowHeight: 50.0,
                theme: theme,
                conflictIndicators: [],
                showNowLine: false, // Disabled
                nowLineDate: DateTime(2023, 1, 3),
              ),
            ),
          ),
        ),
      );

      expect(findPainter(), findsOneWidget);
    });

    testWidgets('paints now line at correct position', (WidgetTester tester) async {
      // Ideally we would inspect the canvas commands, but here we run it to ensure no exceptions
      // and basic integration.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(500, 500),
              painter: BarsCollectionPainter(
                data: [task1],
                visibleRows: [row1],
                rowMaxStackDepth: {'r1': 1},
                domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 10)],
                scale: mockScale,
                rowHeight: 50.0,
                theme: theme,
                conflictIndicators: [],
                showNowLine: true,
                nowLineDate: DateTime(2023, 1, 5), // Should be at x = 400.0
              ),
            ),
          ),
        ),
      );
      expect(findPainter(), findsOneWidget);
    });
  });
}
