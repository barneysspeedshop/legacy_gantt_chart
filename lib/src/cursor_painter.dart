import 'package:flutter/material.dart';
import 'models/legacy_gantt_row.dart';
import 'models/remote_cursor.dart';

class CursorPainter extends CustomPainter {
  final Map<String, RemoteCursor> remoteCursors;
  final double Function(DateTime) totalScale;
  final List<LegacyGanttRow> visibleRows;
  final Map<String, int> rowMaxStackDepth;
  final double rowHeight;
  final double translateY;

  CursorPainter({
    required this.remoteCursors,
    required this.totalScale,
    required this.visibleRows,
    required this.rowMaxStackDepth,
    required this.rowHeight,
    required this.translateY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (remoteCursors.isEmpty) return;

    // Cache row Y positions
    final Map<String, double> rowYPositions = {};
    double currentTop = 0.0;
    for (final row in visibleRows) {
      rowYPositions[row.id] = currentTop;
      final int stackDepth = rowMaxStackDepth[row.id] ?? 1;
      currentTop += rowHeight * stackDepth;
    }

    // Paint each cursor
    for (final cursor in remoteCursors.values) {
      final x = totalScale(cursor.time);
      final rowY = rowYPositions[cursor.rowId];

      if (rowY != null) {
        final y = rowY + (rowHeight / 2) + translateY;

        // Only draw if within vertical visible bounds roughly
        // (Optional optimization: if (y < -50 || y > size.height + 50) continue;)

        _drawCursor(canvas, Offset(x, y), cursor.color, cursor.userId);
      }
    }
  }

  void _drawCursor(Canvas canvas, Offset position, Color color, String label) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw a simple pointer arrow
    final path = Path();
    path.moveTo(position.dx, position.dy);
    path.lineTo(position.dx + 5, position.dy + 14);
    path.lineTo(position.dx + 8, position.dy + 14); // slightly wider tail
    path.lineTo(position.dx + 12, position.dy + 20); // extended tail
    path.lineTo(position.dx + 15, position.dy + 18); // tick
    path.lineTo(position.dx + 11, position.dy + 12); // back to arrow
    path.lineTo(position.dx + 16, position.dy + 12); // arrow right wing
    path.close();

    // Simplified Arrow:
    final simplePath = Path();
    simplePath.moveTo(position.dx, position.dy);
    simplePath.lineTo(position.dx + 6, position.dy + 16);
    simplePath.lineTo(position.dx + 16, position.dy + 10);
    simplePath.close();

    canvas.drawPath(simplePath, paint);

    // Draw shadow/outline for visibility
    canvas.drawPath(
      simplePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Draw Label (User ID)
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        backgroundColor: color.withValues(alpha: 0.8),
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position.translate(10, 10));
  }

  @override
  bool shouldRepaint(covariant CursorPainter oldDelegate) {
    // Ideally compare maps deeply, but for now simple check or optimization
    return oldDelegate.translateY != translateY ||
        oldDelegate.totalScale != totalScale ||
        oldDelegate.remoteCursors != remoteCursors; // Map ref check (VM creates new map?)
    // VM uses simple map, mutation might not trigger.
    // We need to ensure VM calls notifyListeners when cursors change.
  }
}
