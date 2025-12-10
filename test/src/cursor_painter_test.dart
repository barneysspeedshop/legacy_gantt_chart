import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/cursor_painter.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/remote_cursor.dart';

void main() {
  group('CursorPainter', () {
    test('shouldRepaint returns true when properties change', () {
      final cursors1 = {
        'user1': RemoteCursor(
            userId: 'user1', rowId: 'row1', time: DateTime(2023), color: Colors.blue, lastUpdated: DateTime.now())
      };
      final cursors2 = {
        'user1': RemoteCursor(
            userId: 'user1', rowId: 'row1', time: DateTime(2023, 1, 2), color: Colors.blue, lastUpdated: DateTime.now())
      };

      final painter1 = CursorPainter(
        remoteCursors: cursors1,
        totalScale: (dt) => 0.0,
        visibleRows: [],
        rowMaxStackDepth: {},
        rowHeight: 30.0,
        translateY: 0.0,
      );

      final painter2 = CursorPainter(
        remoteCursors: cursors1, // Same cursors
        totalScale: (dt) => 0.0,
        visibleRows: [],
        rowMaxStackDepth: {},
        rowHeight: 30.0,
        translateY: 10.0, // Different translateY
      );

      final painter3 = CursorPainter(
        remoteCursors: cursors2, // Different cursors
        totalScale: (dt) => 0.0,
        visibleRows: [],
        rowMaxStackDepth: {},
        rowHeight: 30.0,
        translateY: 0.0,
      );

      expect(painter1.shouldRepaint(painter2), isTrue); // translateY changed
      expect(painter1.shouldRepaint(painter3), isTrue); // cursors changed
      expect(painter1.shouldRepaint(painter1), isFalse); // self
    });

    test('paints without error', () {
      final cursors = {
        'user1': RemoteCursor(
            userId: 'user1', rowId: 'row1', time: DateTime(2023), color: Colors.blue, lastUpdated: DateTime.now())
      };
      final rows = [const LegacyGanttRow(id: 'row1', label: 'Row 1')];

      final painter = CursorPainter(
        remoteCursors: cursors,
        totalScale: (dt) => 100.0,
        visibleRows: rows,
        rowMaxStackDepth: {'row1': 1},
        rowHeight: 30.0,
        translateY: 0.0,
      );

      // This is a smoke test to ensure the painting logic doesn't crash
      expect(
        () => painter.paint(TestCanvas(), const Size(800, 600)),
        returnsNormally,
      );
    });
  });
}

class TestCanvas implements Canvas {
  @override
  void noSuchMethod(Invocation invocation) {
    // Mock canvas implementation that does nothing
  }
}
