import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  test('LegacyGanttViewModel Smart Duration drag logic', () {
    // defaults: Sat, Sun are weekends
    const calendar = WorkCalendar();

    // Friday Oct 27, 2023
    final start = DateTime(2023, 10, 27);
    // Tuesday Oct 31, 2023 (covers Fri, Sat, Sun, Mon) -> 2 working days
    final end = DateTime(2023, 10, 31);

    final task = LegacyGanttTask(
      id: '1',
      rowId: 'row1',
      start: start,
      end: end,
      name: 'Task 1',
    );

    final vm = LegacyGanttViewModel(
      data: [task],
      visibleRows: [const LegacyGanttRow(id: 'row1', label: 'Row 1')],
      rowMaxStackDepth: {'row1': 1},
      conflictIndicators: [],
      dependencies: [],
      rowHeight: 30,
      totalGridMin: DateTime(2023, 10, 1).millisecondsSinceEpoch.toDouble(),
      totalGridMax: DateTime(2023, 11, 30).millisecondsSinceEpoch.toDouble(),
      enableDragAndDrop: true,
      workCalendar: calendar,
    );

    // Setup layout/scale
    vm.updateLayout(1000, 500);
    // Simulate domain calc
    vm.updateVisibleRange(DateTime(2023, 10, 20).millisecondsSinceEpoch.toDouble(),
        DateTime(2023, 11, 10).millisecondsSinceEpoch.toDouble());

    // Get coordinates for task body
    // We need to know where the task is to tap on it.
    // _getTaskPartAtPosition uses local coordinates relative to chart content.
    // Verify totalScale works
    final startX = vm.totalScale(start);
    final endX = vm.totalScale(end);

    // We can just spy or manually calculate.
    final taskCenterX = (startX + endX) / 2; // Middle of task (Fri-Tue)
    // Actually dragging from middle might be safer.

    // rowTop depends on scroll. Default 0.
    final taskCenterY = vm.timeAxisHeight + 15; // Middle of row (rowHeight=30)

    // 1. Pan Start
    vm.onPanStart(DragStartDetails(
      globalPosition: Offset(taskCenterX, taskCenterY),
      localPosition: Offset(taskCenterX, taskCenterY),
    ));

    // 2. Pan Update: First move triggers the lock
    // We need to calculate how many pixels is 1 day.
    final dayWidth = (vm.totalScale(start.add(const Duration(days: 1))) - vm.totalScale(start)).abs();

    vm.onPanUpdate(DragUpdateDetails(
      globalPosition: Offset(taskCenterX + dayWidth, taskCenterY),
      localPosition: Offset(taskCenterX + dayWidth, taskCenterY),
      delta: Offset(dayWidth, 0),
    ));

    // Verify we grabbed the task
    expect(vm.draggedTask, isNotNull, reason: 'Dragged task should be set after pan update');
    expect(vm.draggedTask!.id, '1');

    // 3. Verification
    // Dragged to Saturday Oct 28.
    // Logic should snap start to Monday Oct 30.
    // Logic should calc end based on 2 working days -> Wed Nov 1.

    expect(vm.ghostTaskStart, DateTime(2023, 10, 30));
    expect(vm.ghostTaskEnd, DateTime(2023, 11, 1));
  });
}
