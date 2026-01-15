import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';

void main() {
  testWidgets('LegacyGanttChartWidget respects visibleRows for height calculation', (tester) async {
    const row1 = LegacyGanttRow(id: 'row1', label: 'Row 1');
    const row2 = LegacyGanttRow(id: 'row2', label: 'Row 2');

    final task1 = LegacyGanttTask(
      id: 'task1',
      rowId: 'row1',
      name: 'Task 1',
      start: DateTime(2022, 1, 1),
      end: DateTime(2022, 1, 5),
    );
    final task2 = LegacyGanttTask(
      id: 'task2',
      rowId: 'row2',
      name: 'Task 2',
      start: DateTime(2022, 1, 6),
      end: DateTime(2022, 1, 10),
    );

    // Initial state: Both rows visible
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            width: 800,
            child: LegacyGanttChartWidget(
              data: [task1, task2],
              visibleRows: const [row1, row2],
              rowMaxStackDepth: const {'row1': 1, 'row2': 1},
              rowHeight: 30.0,
              axisHeight: 30.0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barsPainterFinder =
        find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BarsCollectionPainter);
    expect(barsPainterFinder, findsOneWidget);

    var customPaint = tester.widget<CustomPaint>(barsPainterFinder);
    var painter = customPaint.painter as BarsCollectionPainter;

    // Verify both rows are considered visible by the painter
    expect(painter.visibleRows.length, 2);

    // Let's update to show only 1 row.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            width: 800,
            child: LegacyGanttChartWidget(
              data: [task1, task2], // Both tasks still passed in data
              visibleRows: const [row1], // Only row1 is visible
              rowMaxStackDepth: const {'row1': 1, 'row2': 1},
              rowHeight: 30.0,
              axisHeight: 30.0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    customPaint = tester.widget<CustomPaint>(barsPainterFinder);
    painter = customPaint.painter as BarsCollectionPainter;

    // Verify only 1 row is visible
    expect(painter.visibleRows.length, 1);
    expect(painter.visibleRows.first.id, 'row1');
  });
}
