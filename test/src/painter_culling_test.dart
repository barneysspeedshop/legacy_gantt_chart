import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';

class MockCanvas extends Fake implements Canvas {
  int drawRRectCalls = 0;

  @override
  void drawRRect(RRect rrect, Paint paint) {
    drawRRectCalls++;
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void translate(double dx, double dy) {}

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {}

  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) {}

  @override
  void drawPath(Path path, Paint paint) {}

  // Stub other methods that might be called
  @override
  void noSuchMethod(Invocation invocation) {
    // silently ignore
  }
}

void main() {
  test('BarsCollectionPainter culls off-screen rows', () {
    // Setup 100 rows
    final rows = List.generate(100, (i) => LegacyGanttRow(id: 'row_$i', label: 'Row $i'));
    // Setup 1 task per row
    final tasks = List.generate(
        100,
        (i) => LegacyGanttTask(
              id: 'task_$i',
              rowId: 'row_$i',
              start: DateTime(2023),
              end: DateTime(2024),
              name: 'Task $i',
            ));

    final theme = LegacyGanttTheme(
      backgroundColor: Colors.white,
      barColorPrimary: Colors.blue,
      barColorSecondary: Colors.lightBlue,
      textColor: Colors.black,
      taskTextStyle: const TextStyle(color: Colors.black),
      gridColor: Colors.grey,
      axisTextStyle: const TextStyle(color: Colors.black, fontSize: 10),
    );

    // Case 1: All visible
    var painter = BarsCollectionPainter(
      tasksByRow: {},
      conflictIndicators: [],
      data: tasks,
      domain: [DateTime(2023), DateTime(2024)],
      visibleRows: rows, // 100 rows
      rowMaxStackDepth: {},
      scale: (d) => d.year == 2023 ? 100.0 : 200.0, // Start 100, End 200
      rowHeight: 30.0,
      theme: theme,
      translateY: 0.0, // Scrolled at top
    );

    var canvas = MockCanvas();
    // 100 rows * 30 = 3000px height. Frame size 3000.
    painter.paint(canvas, const Size(1000, 3000));
    expect(canvas.drawRRectCalls, 100, reason: 'Should draw all 100 tasks when fully visible');

    // Case 2: Vertical Culling
    // Viewport 300px (10 rows). Scrolled down 1500px (rows 50-60).
    // translateY is negative of scroll offset?
    // In code: translateY = -scrollController!.offset.
    // So if Scrolled 1500px down, translateY = -1500.

    painter = BarsCollectionPainter(
      tasksByRow: {},
      conflictIndicators: [],
      data: tasks,
      domain: [DateTime(2023), DateTime(2024)],
      visibleRows: rows,
      rowMaxStackDepth: {},
      scale: (d) => d.year == 2023 ? 100.0 : 200.0,
      rowHeight: 30.0,
      theme: theme,
      translateY: -1500.0,
    );

    canvas = MockCanvas(); // Reset
    // Viewport height 300 (10 rows)
    painter.paint(canvas, const Size(1000, 300));

    // Rows 0-49 should be skipped (above -1500).
    // Rows 50-59 (0 to 300 relative to 1500) should be drawn.
    // Rows 60+ should be broken.
    // Ideally ~10-11 drawn.

    expect(canvas.drawRRectCalls, greaterThanOrEqualTo(9));
    expect(canvas.drawRRectCalls, lessThanOrEqualTo(15));
  });
}
