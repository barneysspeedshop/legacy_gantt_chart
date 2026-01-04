// packages/gantt_chart/lib/src/models/gantt_chart_colors.dart
import 'package:flutter/material.dart';

/// Defines the color scheme for the Gantt chart.
@immutable
class LegacyGanttChartColors {
  /// The primary color of the task bars.
  final Color barColorPrimary;

  /// The secondary color of the task bars.
  final Color barColorSecondary;

  /// The default color for text within the chart.
  final Color textColor;

  /// The background color of the chart area.
  final Color backgroundColor;

  const LegacyGanttChartColors({
    required this.barColorPrimary,
    required this.barColorSecondary,
    required this.textColor,
    required this.backgroundColor,
  });
}
