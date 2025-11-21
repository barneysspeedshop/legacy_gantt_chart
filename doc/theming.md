# Theming the Chart

The `LegacyGanttTheme` class controls the color palette and text styles for all elements in the chart. You can create a theme from scratch or, more commonly, derive it from your application's `ThemeData` and customize it.

```dart
final ganttTheme = LegacyGanttTheme.fromTheme(Theme.of(context)).copyWith(
  barColorPrimary: Colors.green.shade800,
  // ... other properties
);
```

| Property                             | Description                                                                                             |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `barColorPrimary`                    | The main background color of standard task bars.                                                        |
| `barColorSecondary`                  | The color of the overlay that indicates the task's completion percentage.                               |
| `summaryBarColor`                    | The color of the angled stripes drawn on top of Summary tasks.                                          |
| `conflictBarColor`                   | The color of the angled pattern used for the "Over-capacity" or conflict indicator.                     |
| `ghostBarColor`                      | The semi-transparent color of the task bar preview shown while dragging or resizing a task.             |
| `timeRangeHighlightColor`            | The background color for special time ranges like weekends or holidays (for tasks with `isTimeRangeHighlight: true`). |
| `containedDependencyBackgroundColor` | The background color that visually links a Summary task to its child rows when using a `contained` dependency. |
| `dependencyLineColor`                | The color of the lines drawn between dependent tasks.                                                   |
| `taskTextStyle`                      | The `TextStyle` for the name displayed inside a task bar.                                               |
| `axisTextStyle`                      | The `TextStyle` for the labels on the timeline axis.                                                    |
| `backgroundColor`                    | The overall background color of the chart area.                                                         |