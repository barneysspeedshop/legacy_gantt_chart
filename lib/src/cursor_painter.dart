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
  final List<double>? rowVerticalOffsets;

  CursorPainter({
    required this.remoteCursors,
    required this.totalScale,
    required this.visibleRows,
    required this.rowMaxStackDepth,
    required this.rowHeight,
    required this.translateY,
    this.rowVerticalOffsets,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (remoteCursors.isEmpty) return;

    final offsets = rowVerticalOffsets;
    if (offsets == null) return;

    for (final cursor in remoteCursors.values) {
      final int rowIndex = visibleRows.indexWhere((r) => r.id == cursor.rowId);
      if (rowIndex != -1) {
        final double rowTop = offsets[rowIndex];
        final double y = rowTop + (rowHeight / 2) + translateY;

        if (y < -50 || y > size.height + 50) continue;

        final x = totalScale(cursor.time);
        _drawCursor(canvas, Offset(x, y), cursor.color, cursor.userId);
      }
    }
  }

  void _drawCursor(Canvas canvas, Offset position, Color color, String label) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final simplePath = Path();
    simplePath.moveTo(position.dx, position.dy);
    simplePath.lineTo(position.dx + 6, position.dy + 16);
    simplePath.lineTo(position.dx + 16, position.dy + 10);
    simplePath.close();

    canvas.drawPath(simplePath, paint);

    canvas.drawPath(
      simplePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

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
      oldDelegate.remoteCursors != remoteCursors ||
      oldDelegate.rowVerticalOffsets != rowVerticalOffsets;
}
