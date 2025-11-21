# Customizing the Chart Appearance

The `LegacyGanttChartWidget` offers several builders to override its default rendering and provide a custom look and feel.

## 1. Custom Task Content (`taskContentBuilder`)

Use this builder when you want to keep the standard bar shape, color, and interactive handles (for dragging and resizing) but need to change what is drawn *inside* the bar. This is perfect for adding icons, custom text layouts, or progress indicators.

```dart
taskContentBuilder: (task) {
  // Assumes a `ganttTheme` variable is in scope. You can create one by using
  // `final ganttTheme = LegacyGanttTheme.fromTheme(Theme.of(context));`
  // which derives colors from your app's overall theme.
  // Determine text color based on the bar's background color for contrast.
  final barColor = task.color ?? ganttTheme.barColorPrimary;
  final textColor = ThemeData.estimateBrightnessForColor(barColor) == Brightness.dark
      ? Colors.white
      : Colors.black;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8.0),
    child: Row(
      children: [
        Icon(Icons.task_alt, size: 16, color: textColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            task.name ?? '',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor),
          ),
        ),
      ],
    ),
  );
}
```

## 2. Full Task Replacement (`taskBarBuilder`)

Use this builder to completely replace the default painted bar with your own custom widget. This gives you maximum control over the appearance of a task.

**Note:** When you use `taskBarBuilder`, you are responsible for drawing everything. The default drag handles, resize handles, and background painting are skipped. This is useful for highly stylized tasks but means you lose the built-in interactive features for that task unless you implement them yourself.

## 3. Custom Timeline Header (`timelineAxisHeaderBuilder`)

This builder allows you to replace the entire default time scale header at the top of the chart with a custom widget. It's a powerful feature for creating complex timeline visualizations, such as multi-level headers (e.g., Month over Day).

The builder provides you with the `scale` function, which is essential for converting a `DateTime` into its corresponding horizontal pixel position.

### Example: Drawing a simple day list

The most effective way to use this builder is with a `CustomPaint` widget, as it provides the best performance for drawing complex, scalable timelines. You can see a complete implementation of a custom header painter in the example application's `main.dart` file (`_CustomHeaderPainter`).

## 4. Custom Timeline Labels (`timelineAxisLabelBuilder`)

Use this builder to customize the format of the labels drawn on the timeline axis. This gives you fine-grained control over how dates are displayed, which is useful for adapting to different zoom levels or localization requirements.

The builder provides the `DateTime` for the label and the `Duration` of the current tick interval, allowing you to format the label differently based on the zoom level.

```dart
import 'package:intl/intl.dart';

timelineAxisLabelBuilder: (date, interval) {
  // If the zoom level is wide (e.g., > 20 days between ticks), show month and year.
  if (interval.inDays > 20) {
    return DateFormat('MMM yyyy').format(date);
  }
  // Otherwise, show the day of the month.
  else {
    return DateFormat('d').format(date);
  }
},
```