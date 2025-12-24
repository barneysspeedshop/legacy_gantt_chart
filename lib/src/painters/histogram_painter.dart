import 'package:flutter/material.dart';
import '../models/resource_bucket.dart';
import '../models/legacy_gantt_theme.dart';

class HistogramPainter extends CustomPainter {
  final List<ResourceBucket> buckets;
  final double Function(DateTime) totalScale;
  final List<DateTime> visibleExtent;
  final LegacyGanttTheme theme;

  HistogramPainter({
    required this.buckets,
    required this.totalScale,
    required this.visibleExtent,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final visibleDuration = visibleExtent.last.difference(visibleExtent.first).inMilliseconds;

    if (visibleDuration == 0) return;

    final pxPerMs = size.width / visibleDuration;
    final firstVisibleMs = visibleExtent.first.millisecondsSinceEpoch;

    for (final bucket in buckets) {
      final dateMs = bucket.date.millisecondsSinceEpoch;

      final startX = (dateMs - firstVisibleMs) * pxPerMs;
      final endX = (bucket.date.add(const Duration(days: 1)).millisecondsSinceEpoch - firstVisibleMs) * pxPerMs;
      final width = endX - startX;

      if (endX < 0 || startX > size.width) continue;

      final barHeight = (bucket.totalLoad * size.height * 0.8).clamp(0.0, size.height);

      if (bucket.isOverAllocated) {
        paint.color = theme.conflictBarColor.withValues(alpha: 0.7);
      } else {
        paint.color = theme.barColorPrimary.withValues(alpha: 0.5);
      }

      canvas.drawRect(
        Rect.fromLTWH(startX, size.height - barHeight, width, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant HistogramPainter oldDelegate) =>
      oldDelegate.buckets != buckets ||
      oldDelegate.totalScale != totalScale ||
      oldDelegate.visibleExtent != visibleExtent ||
      oldDelegate.theme != theme;
}
