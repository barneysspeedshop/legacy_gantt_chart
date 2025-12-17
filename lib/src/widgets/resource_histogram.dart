import 'package:flutter/material.dart';

import '../models/legacy_gantt_theme.dart';
import '../legacy_gantt_view_model.dart';

class ResourceHistogramWidget extends StatelessWidget {
  final LegacyGanttViewModel viewModel;
  final double height;
  final LegacyGanttTheme? theme;

  const ResourceHistogramWidget({
    super.key,
    required this.viewModel,
    this.height = 150,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Identify all unique resources
    final tasksWithResources = viewModel.data.where((t) => t.resourceId != null).toList();
    if (tasksWithResources.isEmpty) return const SizedBox.shrink();

    final resources = tasksWithResources.map((t) => t.resourceId!).toSet().toList()..sort();

    // 2. Calculate daily load for each resource
    // Map<ResourceId, Map<Day, Count>>
    final Map<String, Map<DateTime, int>> resourceUsage = {};

    for (final task in tasksWithResources) {
      // Iterate days from start to end
      DateTime current = task.start;
      // Truncate to day
      current = DateTime(current.year, current.month, current.day);
      final endDay = DateTime(task.end.year, task.end.month, task.end.day);

      while (current.isBefore(endDay) || current.isAtSameMomentAs(endDay)) {
        if (!resourceUsage.containsKey(task.resourceId)) {
          resourceUsage[task.resourceId!] = {};
        }
        final usage = resourceUsage[task.resourceId!]!;
        usage[current] = (usage[current] ?? 0) + 1;

        current = current.add(const Duration(days: 1));
      }
    }

    return Container(
      height: height,
      color: theme?.backgroundColor ?? Theme.of(context).cardColor,
      child: Column(
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(
              'Resource Usage',
              style: (theme?.axisTextStyle ?? Theme.of(context).textTheme.labelSmall)
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: resources.length,
              itemBuilder: (context, index) {
                final resourceId = resources[index];
                final usage = resourceUsage[resourceId] ?? {};
                return SizedBox(
                  height: 30, // Fixed row height
                  child: Row(
                    children: [
                      // Resource Label
                      SizedBox(
                        width: 100,
                        child: Text(
                          resourceId,
                          overflow: TextOverflow.ellipsis,
                          style: theme?.axisTextStyle ?? const TextStyle(fontSize: 10),
                        ),
                      ),
                      // Bar Chart synced with Gantt
                      Expanded(
                        child: CustomPaint(
                          painter: _ResourceRowPainter(
                            usage: usage,
                            visibleExtent: viewModel.visibleExtent,
                            viewModel: viewModel,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceRowPainter extends CustomPainter {
  final Map<DateTime, int> usage;
  final List<DateTime> visibleExtent;
  final LegacyGanttViewModel viewModel;

  _ResourceRowPainter({
    required this.usage,
    required this.visibleExtent,
    required this.viewModel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (visibleExtent.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final totalScale = viewModel.totalScale;

    // Better: Calculate width of 1 day in pixels
    // Use the updated totalScale from the view model
    final p1 = totalScale(visibleExtent.first);
    final p2 = totalScale(visibleExtent.first.add(const Duration(days: 1)));
    final oneDayWidth = (p2 - p1).abs();

    final startOffset = p1;

    // Draw bars
    usage.forEach((day, count) {
      final globalX = totalScale(day);
      final x = globalX - startOffset;

      // Determine color: Green if <= 1, Red if > 1
      paint.color = count > 1 ? Colors.red.withOpacity(0.7) : Colors.green.withOpacity(0.5);

      // Determine height relative to max? Or just distinct block?
      // Simple visualization: Full height for overage, half height for normal?
      final double barHeight = size.height * (count > 1 ? 0.9 : 0.6);

      canvas.drawRect(
        Rect.fromLTWH(x, size.height - barHeight, oneDayWidth, barHeight),
        paint,
      );
    });
  }

  @override
  bool shouldRepaint(covariant _ResourceRowPainter oldDelegate) =>
      oldDelegate.usage != usage || oldDelegate.visibleExtent != visibleExtent || oldDelegate.viewModel != viewModel;
}
