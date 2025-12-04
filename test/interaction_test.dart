import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

void main() {
  test('LegacyGanttViewModel hit testing works correctly', () {
    final now = DateTime.now();
    final task = LegacyGanttTask(
      id: 't1',
      rowId: 'r1',
      name: 'Task 1',
      start: now,
      end: now.add(const Duration(days: 1)),
      stackIndex: 0,
    );

    const row = LegacyGanttRow(id: 'r1');

    final vm = LegacyGanttViewModel(
      conflictIndicators: [],
      data: [task],
      dependencies: [],
      visibleRows: [row],
      rowMaxStackDepth: {'r1': 1},
      rowHeight: 30.0,
      axisHeight: 30.0,
      gridMin: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch.toDouble(),
      gridMax: now.add(const Duration(days: 2)).millisecondsSinceEpoch.toDouble(),
      enableDragAndDrop: true,
      enableResize: true,
    );

    // Layout width 1000, height 500
    vm.updateLayout(1000, 500);

    // Calculate expected X position
    final startX = vm.totalScale(task.start);
    final endX = vm.totalScale(task.end);
    const centerY = 30.0 + 15.0; // Axis height + half row height

    // Test hover on body
    final hoverPos = Offset((startX + endX) / 2, centerY);
    // PointerHoverEvent requires kind, position
    vm.onHover(PointerHoverEvent(
      position: hoverPos,
      kind: PointerDeviceKind.mouse,
    ));

    expect(vm.cursor, SystemMouseCursors.move);

    // Test hover on start handle
    final startHandlePos = Offset(startX + 2, centerY);
    vm.onHover(PointerHoverEvent(
      position: startHandlePos,
      kind: PointerDeviceKind.mouse,
    ));
    expect(vm.cursor, SystemMouseCursors.resizeLeftRight);
  });
}
