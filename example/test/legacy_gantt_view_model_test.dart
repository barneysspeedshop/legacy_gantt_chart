import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LegacyGanttViewModel', () {
    // setup test data
    final rows = [
      const LegacyGanttRow(id: 'row1'),
      const LegacyGanttRow(id: 'row2'),
    ];
    final tasks = [
      LegacyGanttTask(
        id: 'task1',
        rowId: 'row1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5),
      ),
      LegacyGanttTask(
        id: 'task2',
        rowId: 'row2',
        start: DateTime(2023, 1, 6),
        end: DateTime(2023, 1, 10),
      ),
    ];
    final rowMaxStackDepth = {'row1': 1, 'row2': 1};

    late LegacyGanttViewModel viewModel;

    setUp(() {
      viewModel = LegacyGanttViewModel(
        data: tasks,
        dependencies: [],
        visibleRows: rows,
        rowMaxStackDepth: rowMaxStackDepth,
        rowHeight: 30,
        gridMin: DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble(),
        gridMax: DateTime(2023, 1, 31).millisecondsSinceEpoch.toDouble(),
        totalGridMin: DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble(),
        totalGridMax: DateTime(2023, 1, 31).millisecondsSinceEpoch.toDouble(),
        enableDragAndDrop: true,
        enableResize: true,
        resizeHandleWidth: 10.0,
      );
      viewModel.updateLayout(1000, 600); // Provide layout dimensions
    });

    test('initialization calculates domains and scale correctly', () {
      expect(viewModel.totalDomain.length, 2);
      expect(viewModel.totalDomain[0], DateTime(2023, 1, 1));
      expect(viewModel.totalDomain[1], DateTime(2023, 1, 31));
      expect(viewModel.totalScale, isA<Function(DateTime)>());
      // At the start of the domain, scale should be 0
      expect(viewModel.totalScale(DateTime(2023, 1, 1)), 0.0);
      // At the end, it should be the width
      expect(viewModel.totalScale(DateTime(2023, 1, 31)), 1000.0);
    });

    test('onPanUpdate with vertical drag updates translateY', () {
      // Content is not tall enough to scroll, so translateY should remain 0.
      viewModel.onPanStart(DragStartDetails(globalPosition: const Offset(100, 100)));
      viewModel.onPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(100, 120),
        delta: const Offset(0, 20),
      ));
      expect(viewModel.translateY, 0);

      // Let's make content taller than viewport to enable scrolling.
      final manyRows = List.generate(30, (index) => LegacyGanttRow(id: 'row$index'));
      final tallViewModel = LegacyGanttViewModel(
        data: [],
        dependencies: [],
        visibleRows: manyRows,
        rowMaxStackDepth: {for (var row in manyRows) row.id: 1},
        rowHeight: 30,
      );
      tallViewModel.updateLayout(1000, 600); // 30*30=900px content height

      tallViewModel.onPanStart(DragStartDetails(globalPosition: const Offset(100, 100)));
      tallViewModel.onPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(100, 80),
        delta: const Offset(0, -20),
      ));
      expect(tallViewModel.translateY, -20);
      tallViewModel.onPanEnd(DragEndDetails());
    });

    test('onPanUpdate with horizontal drag updates ghost task', () {
      // Simulate a drag on task1
      final task1StartX = viewModel.totalScale(tasks[0].start);
      final task1CenterY = viewModel.timeAxisHeight + viewModel.rowHeight / 2;

      // Start pan on the task body
      viewModel.onPanStart(DragStartDetails(
        globalPosition: Offset(task1StartX + 20, task1CenterY), // +20 to be away from resize handles
        localPosition: Offset(task1StartX + 20, task1CenterY),
      ));

      // It should detect a horizontal pan and set the drag mode.
      viewModel.onPanUpdate(DragUpdateDetails(
        globalPosition: Offset(task1StartX + 30, task1CenterY),
        delta: const Offset(10, 0),
      ));

      expect(viewModel.draggedTask, isNotNull);
      expect(viewModel.draggedTask!.id, 'task1');
      expect(viewModel.ghostTaskStart, isNotNull);
      expect(viewModel.ghostTaskEnd, isNotNull);

      // The drag was 10 pixels. We need to convert this back to a duration.
      final totalDomainDurationMs =
          viewModel.totalDomain.last.millisecondsSinceEpoch - viewModel.totalDomain.first.millisecondsSinceEpoch;
      final durationMs = (10 / 1000) * totalDomainDurationMs;
      final durationDelta = Duration(milliseconds: durationMs.round());

      expect(viewModel.ghostTaskStart, tasks[0].start.add(durationDelta));
      expect(viewModel.ghostTaskEnd, tasks[0].end.add(durationDelta));

      viewModel.onPanEnd(DragEndDetails());
      expect(viewModel.draggedTask, isNull);
    });

    test('onPanUpdate with resizeStart updates ghost task', () {
      final task1StartX = viewModel.totalScale(tasks[0].start);
      final task1CenterY = viewModel.timeAxisHeight + viewModel.rowHeight / 2;

      // Start pan on the start handle of the task (within 10px of the start)
      viewModel.onPanStart(DragStartDetails(
        globalPosition: Offset(task1StartX + 2, task1CenterY),
        localPosition: Offset(task1StartX + 2, task1CenterY),
      ));

      // It should detect a horizontal pan and set the drag mode to resizeStart.
      viewModel.onPanUpdate(DragUpdateDetails(
        globalPosition: Offset(task1StartX + 12, task1CenterY),
        delta: const Offset(10, 0),
      ));

      expect(viewModel.draggedTask, isNotNull);
      expect(viewModel.draggedTask!.id, 'task1');
      expect(viewModel.ghostTaskStart, isNotNull);
      expect(viewModel.ghostTaskEnd, tasks[0].end); // End should not change

      final totalDomainDurationMs =
          viewModel.totalDomain.last.millisecondsSinceEpoch - viewModel.totalDomain.first.millisecondsSinceEpoch;
      final durationMs = (10 / 1000) * totalDomainDurationMs;
      final durationDelta = Duration(milliseconds: durationMs.round());

      expect(viewModel.ghostTaskStart, tasks[0].start.add(durationDelta));

      viewModel.onPanEnd(DragEndDetails());
    });

    test('onPanUpdate with resizeStart and minor vertical drift still resizes', () {
      final task1StartX = viewModel.totalScale(tasks[0].start);
      final task1CenterY = viewModel.timeAxisHeight + viewModel.rowHeight / 2;

      // Start pan on the start handle
      viewModel.onPanStart(DragStartDetails(
        globalPosition: Offset(task1StartX + 2, task1CenterY),
        localPosition: Offset(task1StartX + 2, task1CenterY),
      ));

      // Pan horizontally with a small vertical drift
      viewModel.onPanUpdate(DragUpdateDetails(
        globalPosition: Offset(task1StartX + 12, task1CenterY + 5),
        delta: const Offset(10, 5), // dx > dy
      ));

      // With the fix, this should be treated as a horizontal pan
      expect(viewModel.draggedTask, isNotNull, reason: 'Dragged task should not be null');
      expect(viewModel.ghostTaskStart, isNotNull);
      expect(viewModel.ghostTaskEnd, tasks[0].end, reason: 'End of task should not change on resizeStart');

      final totalDomainDurationMs =
          viewModel.totalDomain.last.millisecondsSinceEpoch - viewModel.totalDomain.first.millisecondsSinceEpoch;
      final durationMs = (10 / 1000) * totalDomainDurationMs;
      final durationDelta = Duration(milliseconds: durationMs.round());

      expect(viewModel.ghostTaskStart, tasks[0].start.add(durationDelta));

      viewModel.onPanEnd(DragEndDetails());
    });
  });
}
