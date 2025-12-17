import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/widgets/resource_histogram.dart';

void main() {
  testWidgets('ResourceHistogramWidget renders bars for tasks with resources', (tester) async {
    final start = DateTime(2023, 1, 1);
    final end = DateTime(2023, 1, 10);
    final task1 = LegacyGanttTask(
      id: '1',
      rowId: 'row1',
      start: DateTime(2023, 1, 2),
      end: DateTime(2023, 1, 5),
      name: 'Task 1',
      resourceId: 'User A',
    );
    final task2 = LegacyGanttTask(
      id: '2',
      rowId: 'row2',
      start: DateTime(2023, 1, 3),
      end: DateTime(2023, 1, 6),
      name: 'Task 2',
      resourceId: 'User B',
    );

    final vm = LegacyGanttViewModel(
      data: [task1, task2],
      visibleRows: [],
      rowMaxStackDepth: {},
      conflictIndicators: [],
      dependencies: [],
      rowHeight: 30,
      totalGridMin: start.millisecondsSinceEpoch.toDouble(),
      totalGridMax: end.millisecondsSinceEpoch.toDouble(),
    );
    // Simulate domain calculation
    vm.updateVisibleRange(start.millisecondsSinceEpoch.toDouble(), end.millisecondsSinceEpoch.toDouble());
    vm.updateLayout(800, 600);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResourceHistogramWidget(viewModel: vm),
      ),
    ));

    expect(find.text('Resource Usage'), findsOneWidget);
    expect(find.text('User A'), findsOneWidget);
    expect(find.text('User B'), findsOneWidget);

    // To verify the painter, we can look for CustomPaint
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(2)); // One per row
  });

  testWidgets('ResourceHistogramWidget renders "No resources" when empty', (tester) async {
    final start = DateTime(2023, 1, 1);
    final end = DateTime(2023, 1, 10);

    final vm = LegacyGanttViewModel(
      data: [], // No tasks
      visibleRows: [],
      rowMaxStackDepth: {},
      conflictIndicators: [],
      dependencies: [],
      rowHeight: 30,
      totalGridMin: start.millisecondsSinceEpoch.toDouble(),
      totalGridMax: end.millisecondsSinceEpoch.toDouble(),
    );
    vm.updateVisibleRange(start.millisecondsSinceEpoch.toDouble(), end.millisecondsSinceEpoch.toDouble());
    vm.updateLayout(800, 600);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResourceHistogramWidget(viewModel: vm),
      ),
    ));

    expect(find.byType(ResourceHistogramWidget), findsOneWidget);
    // Should show "No resources" text path
    expect(find.text('No resources'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });
}
