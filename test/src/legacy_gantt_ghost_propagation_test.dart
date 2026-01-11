import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Ghost Propagation', () {
    test('Dragging a summary task should show ghost bars for children', () {
      final parent = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        isSummary: true,
        propagatesMoveToChildren: true,
      );
      final child = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        parentId: 'parent',
      );

      final viewModel = LegacyGanttViewModel(
        data: [parent, child],
        conflictIndicators: [],
        dependencies: [],
        visibleRows: [
          const LegacyGanttRow(id: 'r1', label: 'R1'),
          const LegacyGanttRow(id: 'r2', label: 'R2'),
        ],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableAutoScheduling: true,
        enableDragAndDrop: true,
      );

      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 24).millisecondsSinceEpoch.toDouble();

      // Start drag of parent
      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(333, 0)), // ~8:00
        overrideTask: parent,
        overridePart: TaskPart.body,
      );

      // Drag +1 hour
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(375, 0),
        delta: const Offset(42, 0),
      ));

      // Check if child has a ghost
      expect(viewModel.bulkGhostTasks.containsKey('child'), isTrue,
          reason: 'Child should have a ghost task during drag');

      final (cStart, cEnd) = viewModel.bulkGhostTasks['child']!;
      expect(cStart.hour, 10, reason: 'Child ghost should be shifted by 1 hour');
    });

    test('Dragging a task should show ghost bars for successors', () {
      final pred = LegacyGanttTask(
        id: 'pred',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 10),
      );
      final succ = LegacyGanttTask(
        id: 'succ',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 12),
        isAutoScheduled: true,
      );

      const dep = LegacyGanttTaskDependency(
        predecessorTaskId: 'pred',
        successorTaskId: 'succ',
        type: DependencyType.finishToStart,
      );

      final viewModel = LegacyGanttViewModel(
        data: [pred, succ],
        conflictIndicators: [],
        dependencies: [dep],
        visibleRows: [
          const LegacyGanttRow(id: 'r1', label: 'R1'),
          const LegacyGanttRow(id: 'r2', label: 'R2'),
        ],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableAutoScheduling: true,
        enableDragAndDrop: true,
      );

      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 24).millisecondsSinceEpoch.toDouble();

      // Start drag of pred
      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(333, 0)),
        overrideTask: pred,
        overridePart: TaskPart.body,
      );

      // Drag +1 hour
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(375, 0),
        delta: const Offset(42, 0),
      ));

      // Check if succ has a ghost
      expect(viewModel.bulkGhostTasks.containsKey('succ'), isTrue,
          reason: 'Successor should have a ghost task during drag');

      final (sStart, _) = viewModel.bulkGhostTasks['succ']!;
      // Pred new end is 11:00. Succ must start >= 11:00.
      expect(sStart.hour, 11, reason: 'Successor ghost should be pushed by 1 hour');
    });
  });
}
