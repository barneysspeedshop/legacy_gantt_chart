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

    // Optimization: Skip loop if we know we are past visible area?
    // Actually we need to build the map, but we can stop populating if we go way past?
    // But valid rows are needed. Let's just iterate, it's cheap compared to painting.
    for (final row in visibleRows) {
      final int stackDepth = rowMaxStackDepth[row.id] ?? 1;
      final double rowHeightTotal = rowHeight * stackDepth;

      // Store center Y
      rowYPositions[row.id] = currentTop + (rowHeight / 2);

      currentTop += rowHeightTotal;
    }

    // Paint each cursor
    for (final cursor in remoteCursors.values) {
      final rowCenterY = rowYPositions[cursor.rowId];

      if (rowCenterY != null) {
        final y = rowCenterY + translateY; // Apply scroll translation

        // Vertical Culling
        // Check if the cursor is roughly on screen (allow some buffer for label/arrow size)
        if (y < -50 || y > size.height + 50) {
          continue;
        }

        final x = totalScale(cursor.time);
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
  bool shouldRepaint(covariant CursorPainter oldDelegate) =>
      oldDelegate.translateY != translateY ||
      oldDelegate.totalScale != totalScale ||
      oldDelegate.remoteCursors != remoteCursors; // Map ref check (VM creates new map?)
  // VM uses simple map, mutation might not trigger.
  // We need to ensure VM calls notifyListeners when cursors change.
}
