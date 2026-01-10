import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/bars_collection_painter.dart';
import 'dart:ui'; // Use explicit import for Canvas

class MockCanvas extends Fake implements Canvas {
  final List<RecordedCall> calls = [];

  @override
  void drawRect(Rect rect, Paint paint) {
    calls.add(RecordedCall('drawRect', rect, paint.color));
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    calls.add(RecordedCall('drawRRect', rrect.outerRect, paint.color));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void translate(double dx, double dy) {}

  @override
  void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true}) {}

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {
    // No-op for mock, or record it if needed
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    calls.add(RecordedCall('drawLine', Rect.fromPoints(p1, p2), paint.color));
  }

  @override
  void drawPath(Path path, Paint paint) {}

  @override
  void drawCircle(Offset c, double radius, Paint paint) {}

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {
    // Record text drawing
    // Paragraph doesn't easily expose text in test, but we can record the call
    calls.add(RecordedCall('drawParagraph', Rect.fromLTWH(offset.dx, offset.dy, 0, 0), null));
  }
}

class RecordedCall {
  final String method;
  final Rect rect;
  final Color? color;

  RecordedCall(this.method, this.rect, this.color);

  @override
  String toString() => '$method $rect $color';
}

void main() {
  test('BarsCollectionPainter should paint contained dependency background', () {
    final theme = LegacyGanttTheme(
      containedDependencyBackgroundColor: const Color(0xFFFF0000),
      barColorPrimary: Colors.blue,
      backgroundColor: Colors.white,
      textColor: Colors.black,
      barColorSecondary: Colors.blueAccent,
    );

    final summaryTask = LegacyGanttTask(
      id: 'summary1',
      rowId: 'row1',
      start: DateTime(2023, 1, 1),
      end: DateTime(2023, 1, 10),
      isSummary: true,
      name: 'Summary Task',
      completion: 0.0,
    );

    final childTask = LegacyGanttTask(
      id: 'child1',
      rowId: 'row2',
      start: DateTime(2023, 1, 2),
      end: DateTime(2023, 1, 5),
      name: 'Child Task',
      completion: 0.0,
    );

    const dependency = LegacyGanttTaskDependency(
      predecessorTaskId: 'summary1',
      successorTaskId: 'child1',
      type: DependencyType.contained,
    );

    const row1 = LegacyGanttRow(id: 'row1');
    const row2 = LegacyGanttRow(id: 'row2');

    final painter = BarsCollectionPainter(
      tasksByRow: {},
      data: [summaryTask, childTask],
      conflictIndicators: [],
      // Ensure visibleRows includes both rows continuously
      visibleRows: [row1, row2],
      rowMaxStackDepth: {'row1': 1, 'row2': 1},
      scale: (date) => date.difference(DateTime(2023, 1, 1)).inDays * 100.0,
      rowHeight: 30.0,
      theme: theme,
      dependencies: [dependency],
      domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 20)],
    );

    final canvas = MockCanvas();
    painter.paint(canvas, const Size(800, 600));

    // Verify
    print('Calls:');
    canvas.calls.forEach(print);

    bool found = canvas.calls.any((call) => call.method == 'drawRect' && call.color == const Color(0xFFFF0000));

    expect(found, isTrue, reason: 'Should have painted contained dependency background (Color(0xFFFF0000))');
  });
}
