import 'package:flutter/material.dart';

import '../models/legacy_gantt_theme.dart';
import '../legacy_gantt_view_model.dart';
import '../painters/histogram_painter.dart';

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
    // Access buckets from VM (handling live updates)
    final bucketsMap = viewModel.resourceBuckets;
    final resources = bucketsMap.keys.toList()..sort();

    // if (resources.isEmpty) return const SizedBox.shrink();

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
            child: resources.isEmpty
                ? Center(
                    child: Text(
                      'No resources',
                      style: theme?.axisTextStyle,
                    ),
                  )
                : ListView.builder(
                    itemExtent: 30.0,
                    itemCount: resources.length,
                    itemBuilder: (context, index) {
                      final resourceId = resources[index];
                      final buckets = bucketsMap[resourceId] ?? [];

                      return SizedBox(
                        height: 30, // Fixed row height
                        child: Stack(
                          children: [
                            // Bar Chart synced with Gantt (Full Width)
                            Positioned.fill(
                              child: ClipRect(
                                child: CustomPaint(
                                  painter: HistogramPainter(
                                    buckets: buckets,
                                    totalScale: viewModel.totalScale,
                                    visibleExtent: viewModel.visibleExtent,
                                    theme: theme ?? LegacyGanttTheme.fromTheme(Theme.of(context)),
                                  ),
                                ),
                              ),
                            ),

                            // Resource Label (Overlay on left)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 140, // Give it some width, maybe semi-transparent or just text
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                                // Optional: standard background to make text readable if bars slide under
                                color: (theme?.backgroundColor ?? Theme.of(context).cardColor).withValues(alpha: 0.8),
                                child: Text(
                                  resourceId,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme?.axisTextStyle ?? const TextStyle(fontSize: 10),
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
