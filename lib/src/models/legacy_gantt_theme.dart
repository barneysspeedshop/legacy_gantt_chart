import 'package:flutter/material.dart';

/// Defines the theme for the [LegacyGanttChartWidget].
///
/// This class encapsulates all the visual styling for the chart, including
/// colors, text styles, and dimensions.
@immutable
class LegacyGanttTheme {
  /// The primary color of the task bars.
  final Color barColorPrimary;

  /// The secondary color of the task bars (e.g., for gradients or borders).
  final Color barColorSecondary;

  /// The default color for text within the chart.
  final Color textColor;

  /// The background color of the chart area.
  final Color backgroundColor;

  /// The color of the vertical and horizontal grid lines.
  final Color gridColor;

  /// The color used for summary task bars.
  final Color summaryBarColor;

  /// The color used for conflict indicator bars (usually red).
  final Color conflictBarColor;

  /// The color used for the "ghost" bar during drag operations.
  final Color ghostBarColor;

  /// The text style for the time axis labels.
  final TextStyle axisTextStyle;

  /// The text style for labels inside task bars.
  final TextStyle taskTextStyle;

  /// The color of the lines drawn to represent task dependencies.
  final Color dependencyLineColor;

  /// The color for background highlights, such as holidays or weekends.
  /// This is used for tasks where `isTimeRangeHighlight` is true.
  final Color timeRangeHighlightColor;

  /// The background color for a task that is contained within another.
  final Color containedDependencyBackgroundColor;

  /// The background color for the highlight that appears when hovering over
  /// empty space in a row, indicating a new task can be created.
  final Color emptySpaceHighlightColor;

  /// The color of the add icon (+) that appears in the empty space highlight.
  final Color emptySpaceAddIconColor;

  /// The ratio of the task bar height to the row height (0.0 to 1.0).
  final double barHeightRatio;

  /// The corner radius for task bars.
  final Radius barCornerRadius;

  /// The background color used to highlight weekends.
  final Color weekendColor;

  /// Whether to draw horizontal borders between rows.
  final bool showRowBorders;

  /// The color of the row borders, if enabled.
  final Color? rowBorderColor;

  /// The color used to highlight tasks and dependencies on the critical path.
  final Color criticalPathColor;

  /// The color of the "now" line indicator.
  final Color nowLineColor;

  /// The color of the slack (float) bar.
  final Color slackBarColor;

  LegacyGanttTheme({
    required this.barColorPrimary,
    required this.barColorSecondary,
    required this.textColor,
    required this.backgroundColor,
    this.gridColor = const Color.fromRGBO(136, 136, 136, 0.2), // Colors.grey.withAlpha(0.2)
    this.summaryBarColor = const Color.fromRGBO(0, 0, 0, 0.2), // Colors.black.withAlpha(0.2)
    this.conflictBarColor = const Color.fromRGBO(244, 67, 54, 0.5), // Colors.red.withAlpha(0.5)
    this.ghostBarColor = const Color.fromRGBO(33, 150, 243, 0.7), // Colors.blue.withAlpha(0.7)
    TextStyle? axisTextStyle,
    this.taskTextStyle = const TextStyle(fontSize: 12, color: Colors.white),
    this.showRowBorders = false,
    this.rowBorderColor,
    this.dependencyLineColor = const Color.fromRGBO(97, 97, 97, 1), // Colors.grey[700]
    this.timeRangeHighlightColor = const Color.fromRGBO(0, 0, 0, 0.05), // Colors.black.withAlpha(0.05)
    this.containedDependencyBackgroundColor = const Color.fromRGBO(0, 0, 0, 0.1), // Colors.black.withAlpha(0.1)
    this.emptySpaceHighlightColor = const Color.fromRGBO(33, 150, 243, 0.06), // Colors.blue.withAlpha(0.06)
    this.emptySpaceAddIconColor = const Color.fromRGBO(33, 150, 243, 1), // Colors.blue
    this.weekendColor = const Color.fromRGBO(0, 0, 0, 0.04), // Colors.black.withAlpha(0.04)
    this.barHeightRatio = 0.7,
    this.barCornerRadius = const Radius.circular(4.0),
    this.criticalPathColor = const Color.fromRGBO(244, 67, 54, 1.0), // Colors.red
    this.nowLineColor = const Color.fromRGBO(244, 67, 54, 0.8), // Colors.red.withAlpha(0.8)
    this.slackBarColor = const Color.fromRGBO(0, 0, 0, 0.4), // Colors.black.withAlpha(0.4)
  }) : axisTextStyle = axisTextStyle ?? TextStyle(fontSize: 12, color: textColor);

  LegacyGanttTheme copyWith({
    Color? barColorPrimary,
    Color? barColorSecondary,
    Color? textColor,
    Color? backgroundColor,
    Color? gridColor,
    Color? summaryBarColor,
    Color? conflictBarColor,
    Color? ghostBarColor,
    TextStyle? axisTextStyle,
    TextStyle? taskTextStyle,
    Color? dependencyLineColor,
    Color? timeRangeHighlightColor,
    Color? containedDependencyBackgroundColor,
    Color? emptySpaceHighlightColor,
    Color? emptySpaceAddIconColor,
    double? barHeightRatio,
    Radius? barCornerRadius,
    bool? showRowBorders,
    Color? rowBorderColor,
    Color? weekendColor,
    Color? criticalPathColor,
    Color? nowLineColor,
    Color? slackBarColor,
  }) =>
      LegacyGanttTheme(
        barColorPrimary: barColorPrimary ?? this.barColorPrimary,
        barColorSecondary: barColorSecondary ?? this.barColorSecondary,
        textColor: textColor ?? this.textColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        gridColor: gridColor ?? this.gridColor,
        summaryBarColor: summaryBarColor ?? this.summaryBarColor,
        conflictBarColor: conflictBarColor ?? this.conflictBarColor,
        ghostBarColor: ghostBarColor ?? this.ghostBarColor,
        axisTextStyle: axisTextStyle ?? this.axisTextStyle,
        taskTextStyle: taskTextStyle ?? this.taskTextStyle,
        dependencyLineColor: dependencyLineColor ?? this.dependencyLineColor,
        timeRangeHighlightColor: timeRangeHighlightColor ?? this.timeRangeHighlightColor,
        containedDependencyBackgroundColor:
            containedDependencyBackgroundColor ?? this.containedDependencyBackgroundColor,
        emptySpaceHighlightColor: emptySpaceHighlightColor ?? this.emptySpaceHighlightColor,
        emptySpaceAddIconColor: emptySpaceAddIconColor ?? this.emptySpaceAddIconColor,
        barHeightRatio: barHeightRatio ?? this.barHeightRatio,
        barCornerRadius: barCornerRadius ?? this.barCornerRadius,
        showRowBorders: showRowBorders ?? this.showRowBorders,
        rowBorderColor: rowBorderColor ?? this.rowBorderColor,
        weekendColor: weekendColor ?? this.weekendColor,
        criticalPathColor: criticalPathColor ?? this.criticalPathColor,
        nowLineColor: nowLineColor ?? this.nowLineColor,
        slackBarColor: slackBarColor ?? this.slackBarColor,
      );

  /// Creates a default theme based on the application's [ThemeData].
  factory LegacyGanttTheme.fromTheme(ThemeData theme) => LegacyGanttTheme(
        barColorPrimary: theme.colorScheme.primary,
        barColorSecondary: theme.colorScheme.secondary,
        textColor: theme.colorScheme.onSurface,
        backgroundColor: theme.colorScheme.surface,
        gridColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        summaryBarColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        conflictBarColor: Colors.red.withValues(alpha: 0.5),
        ghostBarColor: theme.colorScheme.primary.withValues(alpha: 0.7),
        rowBorderColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        dependencyLineColor: theme.colorScheme.onSurface.withValues(alpha: 0.8),
        timeRangeHighlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        containedDependencyBackgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
        emptySpaceHighlightColor: theme.colorScheme.primary.withValues(alpha: 0.06),
        emptySpaceAddIconColor: theme.colorScheme.primary,
        weekendColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        axisTextStyle: theme.textTheme.bodySmall ?? TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
        taskTextStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary) ??
            const TextStyle(fontSize: 12, color: Colors.white),
        criticalPathColor: Colors.red, // Default critical path color
        nowLineColor: theme.brightness == Brightness.dark ? Colors.redAccent : theme.colorScheme.error,
        slackBarColor: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      );
}
