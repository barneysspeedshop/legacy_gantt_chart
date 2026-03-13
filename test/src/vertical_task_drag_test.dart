import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('vertical task drag', () {
    LegacyGanttViewModel createViewModel({
      required bool enableVerticalTaskDrag,
      void Function(LegacyGanttTask task, DateTime start, DateTime end, String rowId)? onTaskMove,
      void Function(LegacyGanttTask task, DateTime start, DateTime end)? onTaskUpdate,
    }) {
      final rows = const [
        LegacyGanttRow(id: 'row-1', label: 'Row 1'),
        LegacyGanttRow(id: 'row-2', label: 'Row 2'),
      ];
      final task = LegacyGanttTask(
        id: 'task-1',
        rowId: 'row-1',
        start: DateTime(2024, 1, 1, 8),
        end: DateTime(2024, 1, 1, 10),
        name: 'Task 1',
      );

      final vm = LegacyGanttViewModel(
        data: [task],
        conflictIndicators: const [],
        dependencies: const [],
        visibleRows: rows,
        rowMaxStackDepth: const {'row-1': 1, 'row-2': 1},
        rowHeight: 20,
        enableDragAndDrop: true,
        enableVerticalTaskDrag: enableVerticalTaskDrag,
        onTaskMove: onTaskMove,
        onTaskUpdate: onTaskUpdate,
      );
      vm.updateLayout(400, 200);
      return vm;
    }

    test('emits onTaskMove with the target row when vertical dragging is enabled', () {
      (LegacyGanttTask, DateTime, DateTime, String)? moveEvent;
      var updateCalls = 0;

      final vm = createViewModel(
        enableVerticalTaskDrag: true,
        onTaskMove: (task, start, end, rowId) => moveEvent = (task, start, end, rowId),
        onTaskUpdate: (_, __, ___) => updateCalls++,
      );

      final draggedTask = vm.data.single;
      final secondRowY = vm.timeAxisHeight + vm.rowHeight + 5;

      vm.onPanStart(
        DragStartDetails(
          globalPosition: Offset.zero,
          localPosition: Offset(10, 25),
        ),
        overrideTask: draggedTask,
        overridePart: TaskPart.body,
      );
      vm.onPanUpdate(
        DragUpdateDetails(
          globalPosition: Offset.zero,
          localPosition: Offset(10, secondRowY),
          delta: Offset.zero,
          primaryDelta: 0,
        ),
      );
      vm.onPanEnd(DragEndDetails(primaryVelocity: 0, velocity: Velocity.zero));

      expect(moveEvent, isNotNull);
      expect(moveEvent!.$1.id, draggedTask.id);
      expect(moveEvent!.$4, 'row-2');
      expect(updateCalls, 0);
    });

    test('keeps the task on its original row when vertical dragging is disabled', () {
      (LegacyGanttTask, DateTime, DateTime, String)? moveEvent;
      (LegacyGanttTask, DateTime, DateTime)? updateEvent;

      final vm = createViewModel(
        enableVerticalTaskDrag: false,
        onTaskMove: (task, start, end, rowId) => moveEvent = (task, start, end, rowId),
        onTaskUpdate: (task, start, end) => updateEvent = (task, start, end),
      );

      final draggedTask = vm.data.single;
      final secondRowY = vm.timeAxisHeight + vm.rowHeight + 5;

      vm.onPanStart(
        DragStartDetails(
          globalPosition: Offset.zero,
          localPosition: Offset(10, 25),
        ),
        overrideTask: draggedTask,
        overridePart: TaskPart.body,
      );
      vm.onPanUpdate(
        DragUpdateDetails(
          globalPosition: Offset.zero,
          localPosition: Offset(10, secondRowY),
          delta: Offset.zero,
          primaryDelta: 0,
        ),
      );
      vm.onPanEnd(DragEndDetails(primaryVelocity: 0, velocity: Velocity.zero));

      expect(moveEvent, isNull);
      expect(updateEvent, isNotNull);
      expect(vm.data.single.rowId, 'row-1');
    });

    test('starts task dragging from an initial downward movement when vertical dragging is enabled', () {
      (LegacyGanttTask, DateTime, DateTime, String)? moveEvent;

      final vm = createViewModel(
        enableVerticalTaskDrag: true,
        onTaskMove: (task, start, end, rowId) => moveEvent = (task, start, end, rowId),
      );

      final secondRowY = vm.timeAxisHeight + vm.rowHeight + 5;

      vm.onPointerEvent(const PointerDownEvent(buttons: kPrimaryMouseButton));
      vm.onPanStart(
        DragStartDetails(
          globalPosition: const Offset(10, 25),
          localPosition: const Offset(10, 25),
        ),
      );
      vm.onPanUpdate(
        DragUpdateDetails(
          globalPosition: Offset(10, secondRowY),
          localPosition: Offset(10, secondRowY),
          delta: const Offset(0, 20),
          primaryDelta: 20,
        ),
      );
      vm.onPanEnd(DragEndDetails(primaryVelocity: 0, velocity: Velocity.zero));
      vm.onPointerEvent(const PointerUpEvent());

      expect(moveEvent, isNotNull);
      expect(moveEvent!.$4, 'row-2');
    });
  });
}




