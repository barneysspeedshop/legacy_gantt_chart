import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/axis_painter.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';

void main() {
  // Test data
  final rows = [
    const LegacyGanttRow(id: 'row1'),
    const LegacyGanttRow(id: 'row2'),
  ];

  final tasks = [
    LegacyGanttTask(
      id: 'task1',
      rowId: 'row1',
      name: 'Task 1',
      start: DateTime(2023, 1, 1),
      end: DateTime(2023, 1, 5),
    ),
    LegacyGanttTask(
      id: 'task2',
      rowId: 'row2',
      name: 'Task 2',
      start: DateTime(2023, 1, 6),
      end: DateTime(2023, 1, 10),
    ),
  ];

  final rowMaxStackDepth = {'row1': 1, 'row2': 1};
  final gridMin = DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble();
  final gridMax = DateTime(2023, 1, 31).millisecondsSinceEpoch.toDouble();

  Widget buildTestableWidget(Widget child) => MaterialApp(
        home: Scaffold(
          body: child,
        ),
      );

  group('LegacyGanttChartWidget', () {
    testWidgets('renders correctly with basic data', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(
        LegacyGanttChartWidget(
          data: tasks,
          visibleRows: rows,
          rowMaxStackDepth: rowMaxStackDepth,
          gridMin: gridMin,
          gridMax: gridMax,
        ),
      ));

      // Let the widget build and paint
      await tester.pumpAndSettle();

      // It should find the main widget
      expect(find.byType(LegacyGanttChartWidget), findsOneWidget);

      // The painters for the axis and bars should be present
      final axisPainters = find.byType(CustomPaint).evaluate().where((element) {
        final painter = (element.widget as CustomPaint).painter;
        return painter is AxisPainter;
      });
      expect(axisPainters.length, 2); // One for grid, one for header

      final barPainters = find.byType(CustomPaint).evaluate().where((element) {
        final painter = (element.widget as CustomPaint).painter;
        return painter is BarsCollectionPainter;
      });
      expect(barPainters.length, 1);
    });

    testWidgets('renders custom task bars with taskBarBuilder', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(
        LegacyGanttChartWidget(
          data: tasks,
          visibleRows: rows,
          rowMaxStackDepth: rowMaxStackDepth,
          gridMin: gridMin,
          gridMax: gridMax,
          taskBarBuilder: (task) => Container(
            key: Key('custom_task_bar_${task.id}'),
            color: Colors.purple,
            child: Text('Custom: ${task.name}'),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // It should find the custom widgets we built
      expect(find.byKey(const Key('custom_task_bar_task1')), findsOneWidget);
      expect(find.byKey(const Key('custom_task_bar_task2')), findsOneWidget);
      expect(find.text('Custom: Task 1'), findsOneWidget);
    });

    testWidgets('renders custom task content with taskContentBuilder', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(
        LegacyGanttChartWidget(
          data: tasks,
          visibleRows: rows,
          rowMaxStackDepth: rowMaxStackDepth,
          gridMin: gridMin,
          gridMax: gridMax,
          taskContentBuilder: (task) => Container(
            key: Key('custom_task_content_${task.id}'),
            child: Text('Content: ${task.name}'),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // It should find the custom content widgets we built
      expect(find.byKey(const Key('custom_task_content_task1')), findsOneWidget);
      expect(find.byKey(const Key('custom_task_content_task2')), findsOneWidget);
      expect(find.text('Content: Task 1'), findsOneWidget);
    });
  });
}
