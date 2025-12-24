import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:flutter/material.dart';

void main() {
  group('Auto Schedule Bug Reproduction', () {
    late LegacyGanttViewModel viewModel;
    late LegacyGanttTask taskA;
    late LegacyGanttTask taskB;

    setUp(() {
      taskA = LegacyGanttTask(
        id: 'A',
        rowId: 'row1',
        name: 'Task A',
        start: DateTime(2023, 1, 1), // Jan 1 00:00 -> Jan 2 00:00
        end: DateTime(2023, 1, 2),
        isAutoScheduled: true,
      );
      taskB = LegacyGanttTask(
        id: 'B',
        rowId: 'row1',
        name: 'Task B',
        start: DateTime(2023, 1, 3),
        end: DateTime(2023, 1, 4),
        isAutoScheduled: true,
      );

      viewModel = LegacyGanttViewModel(
        data: [taskA, taskB],
        conflictIndicators: [],
        dependencies: [
          const LegacyGanttTaskDependency(
            predecessorTaskId: 'A',
            successorTaskId: 'B',
            type: DependencyType.finishToStart,
          )
        ],
        visibleRows: [const LegacyGanttRow(id: 'row1', label: 'Row 1')],
        rowMaxStackDepth: {'row1': 1},
        rowHeight: 30.0,
      );

      // Set up layout
      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 10).millisecondsSinceEpoch.toDouble();
    });

    test('Moving Task A backward should NOT move Task B', () {
      // Simulate drag start on Task A
      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(100, 100), localPosition: const Offset(100, 100)),
        overrideTask: taskA,
        overridePart: TaskPart.body,
      );

      // Simulate moving Task A backward -50 pixels
      const delta = Offset(-50, 0);

      viewModel.onPanUpdate(DragUpdateDetails(
        delta: delta,
        globalPosition: const Offset(50, 100), // 100 - 50 = 50
        localPosition: const Offset(50, 100),
      ));

      // End drag to commit
      viewModel.onPanEnd(DragEndDetails());

      final updatedA = viewModel.data.firstWhere((t) => t.id == 'A');
      final updatedB = viewModel.data.firstWhere((t) => t.id == 'B');

      // Verify A moved backwards (start time is before original)
      expect(updatedA.start.isBefore(taskA.start), isTrue, reason: 'Task A did not move backwards');

      // Verify B did not move (Desired behavior for Fix)
      // Check for current Buggy Behavior: B moves in tandem.
      // If buggy: updatedB.start < taskB.start

      // I assert EXPECTED (Fixed) behavior. If it fails (bugs exists), good.
      // The bug is that they move in tandem. So updatedB.start will be < taskB.start.

      // Asserting bug behavior to confirm reproduction:
      // expect(updatedB.start.isBefore(taskB.start), isTrue, reason: "Bug Reproduced: Task B moved backward");

      // Asserting CORRECT behavior to fail when bug is present:
      expect(updatedB.start, equals(taskB.start), reason: "Task B moved when it shouldn't have");
    });

    test('Moving Task A forward past Task B start SHOULD move Task B', () {
      viewModel.onPanCancel();
      viewModel.updateData([taskA, taskB]); // reset data

      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(100, 100), localPosition: const Offset(100, 100)),
        overrideTask: taskA,
        overridePart: TaskPart.body,
      );

      // Move forward +300
      const delta = Offset(300, 0);

      viewModel.onPanUpdate(DragUpdateDetails(
        delta: delta,
        globalPosition: const Offset(400, 100),
        localPosition: const Offset(400, 100),
      ));

      viewModel.onPanEnd(DragEndDetails());

      final updatedA = viewModel.data.firstWhere((t) => t.id == 'A');
      final updatedB = viewModel.data.firstWhere((t) => t.id == 'B');

      expect(updatedA.start.isAfter(taskA.start), isTrue, reason: 'Task A moved forward');
      expect(updatedB.start.isAfter(taskB.start), isTrue, reason: 'Task B should move later');
    });
  });
}
