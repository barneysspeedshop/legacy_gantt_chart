import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_controller.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LegacyGanttViewModel Draw Dependencies', () {
    late LegacyGanttViewModel viewModel;
    late List<LegacyGanttTask> tasks;
    late List<LegacyGanttRow> visibleRows;

    const double layoutWidth = 1000.0;
    const double layoutHeight = 500.0;
    const double testAxisHeight = 50.0;
    const double testRowHeight = 30.0;
    const double handleWidth = 10.0;

    final now = DateTime.now();

    setUp(() {
      tasks = [
        LegacyGanttTask(
          id: '1',
          rowId: 'row1',
          name: 'Task 1',
          start: now,
          end: now.add(const Duration(days: 1)),
        ),
        LegacyGanttTask(
          id: '2',
          rowId: 'row2',
          name: 'Task 2',
          start: now.add(const Duration(days: 2)),
          end: now.add(const Duration(days: 3)),
        ),
        LegacyGanttTask(
          id: '3',
          rowId: 'row3',
          name: 'Task 3',
          start: now.add(const Duration(days: 4)),
          end: now.add(const Duration(days: 5)),
        ),
      ];
      visibleRows = [
        const LegacyGanttRow(id: 'row1', label: 'Row 1'),
        const LegacyGanttRow(id: 'row2', label: 'Row 2'),
        const LegacyGanttRow(id: 'row3', label: 'Row 3'),
      ];

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: tasks,
        dependencies: [],
        visibleRows: visibleRows,
        rowMaxStackDepth: {'row1': 1, 'row2': 1, 'row3': 1},
        rowHeight: testRowHeight,
        axisHeight: testAxisHeight,
        enableDragAndDrop: true,
        enableResize: true,
        resizeHandleWidth: handleWidth,
      );

      viewModel.updateLayout(layoutWidth, layoutHeight);
      viewModel.setTool(GanttTool.drawDependencies);
    });

    Offset findHandle(String taskId, TaskPart targetPart) {
      final task = tasks.firstWhere((t) => t.id == taskId);
      final rowIdx = visibleRows.indexWhere((r) => r.id == task.rowId);
      final y = testAxisHeight + (rowIdx * testRowHeight) + (testRowHeight / 2);

      // Look for the specific handle
      for (double x = 0; x < layoutWidth; x += 1.0) {
        final pos = Offset(x, y);
        final hit = viewModel.getTaskPartAt(pos);
        if (hit != null) {
          // print('Hit at $x: ${hit.task.name} ${hit.part}'); // Debug print
          if (hit.task.id == taskId && hit.part == targetPart) {
            return pos;
          }
        }
      }
      // If we are here, we failed. Let's print what we found for this task
      for (double x = 0; x < layoutWidth; x += 5.0) {
        // Coarser scan for debug
        final pos = Offset(x, y);
        final hit = viewModel.getTaskPartAt(pos);
        if (hit != null && hit.task.id == taskId) {
          print('DEBUG: Found ${hit.task.name} part ${hit.part} at X=$x');
        }
      }
      fail('Could not find $targetPart for task $taskId');
    }

    test('should add FinishToStart dependency', () {
      final startPos = findHandle('1', TaskPart.endHandle);
      final endPos = findHandle('2', TaskPart.startHandle);

      viewModel.onPanStart(DragStartDetails(localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(localPosition: endPos, globalPosition: endPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.length, 1);
      final dep = viewModel.dependencies.first;
      expect(dep.predecessorTaskId, '1');
      expect(dep.successorTaskId, '2');
      expect(dep.type, DependencyType.finishToStart);
    });

    test('should prevent self-dependency loop', () {
      final startPos = findHandle('1', TaskPart.endHandle);
      final endPos = findHandle('1', TaskPart.startHandle);

      viewModel.onPanStart(DragStartDetails(localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(localPosition: endPos, globalPosition: endPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.isEmpty, true);
    });

    test('should prevent cyclic dependency', () {
      // 1. Create 1 -> 2
      viewModel.addDependency(const LegacyGanttTaskDependency(
          predecessorTaskId: '1', successorTaskId: '2', type: DependencyType.finishToStart));
      expect(viewModel.dependencies.length, 1);

      // 2. Try to create 2 -> 1
      final startPos = findHandle('2', TaskPart.endHandle);
      final endPos = findHandle('1', TaskPart.startHandle);

      viewModel.onPanStart(DragStartDetails(localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(localPosition: endPos, globalPosition: endPos));
      viewModel.onPanEnd(DragEndDetails());

      // Should still be 1 (cycle rejected)
      expect(viewModel.dependencies.length, 1);
    });

    test('should add StartToFinish dependency', () {
      final startPos = findHandle('1', TaskPart.startHandle);
      final endPos = findHandle('2', TaskPart.endHandle);

      viewModel.onPanStart(DragStartDetails(localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(localPosition: endPos, globalPosition: endPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.length, 1);
      final dep = viewModel.dependencies.first;
      expect(dep.type, DependencyType.startToFinish);
    });

    test('should add StartToStart dependency', () {
      final startPos = findHandle('1', TaskPart.startHandle);
      final endPos = findHandle('2', TaskPart.startHandle);

      viewModel.onPanStart(DragStartDetails(localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(localPosition: endPos, globalPosition: endPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.length, 1);
      final dep = viewModel.dependencies.first;
      expect(dep.type, DependencyType.startToStart);
    });

    test('should add FinishToFinish dependency', () {
      final startPos = findHandle('1', TaskPart.endHandle);
      final endPos = findHandle('2', TaskPart.endHandle);

      viewModel.onPanStart(DragStartDetails(localPosition: startPos));
      viewModel.onPanUpdate(DragUpdateDetails(localPosition: endPos, globalPosition: endPos));
      viewModel.onPanEnd(DragEndDetails());

      expect(viewModel.dependencies.length, 1);
      final dep = viewModel.dependencies.first;
      expect(dep.type, DependencyType.finishToFinish);
    });
  });
}
