import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LegacyGanttViewModel Cycle Detection', () {
    late LegacyGanttViewModel viewModel;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');
    const row2 = LegacyGanttRow(id: 'r2', label: 'Row 2');
    const row3 = LegacyGanttRow(id: 'r3', label: 'Row 3');

    final taskA = LegacyGanttTask(
      id: 'A',
      rowId: 'r1',
      start: DateTime(2023, 1, 1, 8),
      end: DateTime(2023, 1, 1, 9),
      name: 'Task A',
    );
    final taskB = LegacyGanttTask(
      id: 'B',
      rowId: 'r2',
      start: DateTime(2023, 1, 1, 9),
      end: DateTime(2023, 1, 1, 10),
      name: 'Task B',
    );
    final taskC = LegacyGanttTask(
      id: 'C',
      rowId: 'r3',
      start: DateTime(2023, 1, 1, 10),
      end: DateTime(2023, 1, 1, 11),
      name: 'Task C',
    );

    // Dependencies: A -> B, B -> C
    const depAB =
        LegacyGanttTaskDependency(predecessorTaskId: 'A', successorTaskId: 'B', type: DependencyType.finishToStart);
    const depBC =
        LegacyGanttTaskDependency(predecessorTaskId: 'B', successorTaskId: 'C', type: DependencyType.finishToStart);

    setUp(() {
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [taskA, taskB, taskC],
        dependencies: [depAB, depBC],
        visibleRows: [row1, row2, row3],
        rowMaxStackDepth: {'r1': 1, 'r2': 1, 'r3': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
        enableResize: true,
      );

      // Setup layout: 1000px width, 500px height
      viewModel.updateLayout(1000, 500);

      // Grid Range: 8:00 to 12:00 (4 hours) -> 250px/hour
      // Scale:
      // 8:00 -> 0px
      // 9:00 -> 250px
      // 10:00 -> 500px
      // 11:00 -> 750px
      // 12:00 -> 1000px
      viewModel.gridMin = DateTime(2023, 1, 1, 8).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 12).millisecondsSinceEpoch.toDouble();

      // Rows:
      // Row 1 (A): y=50..100 (Axis is 50)
      // Row 2 (B): y=100..150
      // Row 3 (C): y=150..200
    });

    test('rejects dependency that creates a cycle (C -> A)', () {
      // Current: A -> B -> C
      // Attempt: C -> A
      // Cycle: A -> B -> C -> A

      viewModel.setTool(GanttTool.drawDependencies);

      // 1. Pan Start on Task C End Handle
      // Task C: 10:00-11:00 -> 500px-750px.
      // End Handle is at 750px.
      // Row 3 y: 150..200. Center y: 175.

      // We aim for exactly the handle.
      // ViewModel uses `_getTaskPartAtPosition`. It checks handles which are typically at the edges.
      // Let's assume hitting the right edge of C works.
      const startPos = Offset(749, 175);

      viewModel.onPanStart(DragStartDetails(globalPosition: startPos, localPosition: startPos));

      // 2. Pan to Task A Start Handle
      // Task A: 8:00-9:00 -> 0px-250px.
      // Start Handle is at 0px.
      // Row 1 y: 50..100. Center y: 75.
      const endPos = Offset(1, 75); // Slightly inside

      // Using `onPanUpdate` to update current drag position
      viewModel.onPanUpdate(DragUpdateDetails(
        globalPosition: endPos,
        localPosition: endPos,
        delta: endPos - startPos,
      ));

      // Expect dependency creation attempt
      // But we verify results after Pan End

      viewModel.onPanEnd(DragEndDetails());

      // Check dependencies
      expect(viewModel.dependencies.length, 2, reason: 'Should not create new dependency');
      expect(viewModel.dependencies.any((d) => d.predecessorTaskId == 'C' && d.successorTaskId == 'A'), isFalse);
    });

    test('rejects dependency that creates a cycle (C -> B)', () {
      // Current: A -> B -> C
      // Attempt: C -> B
      // Cycle: B -> C -> B

      viewModel.setTool(GanttTool.drawDependencies);

      // C End Handle (749, 175) to B Start Handle (251, 125) (B is 9:00-10:00 -> 250-500)
      const startPos = Offset(749, 175);
      const endPos = Offset(251, 125);

      viewModel.onPanStart(DragStartDetails(globalPosition: startPos, localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(globalPosition: endPos, localPosition: endPos, delta: endPos - startPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.length, 2);
      expect(viewModel.dependencies.any((d) => d.predecessorTaskId == 'C' && d.successorTaskId == 'B'), isFalse);
    });

    test('should allow valid non-cyclic dependency (A -> C)', () {
      // Current: A -> B -> C
      // Attempt: A -> C (Redundant but valid DAG)

      viewModel.setTool(GanttTool.drawDependencies);

      // A End Handle (249, 75) to C Start Handle (501, 175)
      const startPos = Offset(249, 75);
      const endPos = Offset(501, 175);

      viewModel.onPanStart(DragStartDetails(globalPosition: startPos, localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(globalPosition: endPos, localPosition: endPos, delta: endPos - startPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.length, 3);
      expect(viewModel.dependencies.any((d) => d.predecessorTaskId == 'A' && d.successorTaskId == 'C'), isTrue);
    });
  });
}
