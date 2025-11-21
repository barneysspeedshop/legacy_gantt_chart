# Managing Data and State

There are two primary ways to provide data to the `LegacyGanttChartWidget`: static lists for simple cases and the `LegacyGanttController` for dynamic, large-scale applications.

## 1. Static Mode (Simple)

For small, fixed datasets that don't require lazy loading, you can pass your lists of tasks and dependencies directly to the widget's constructor. This is the simplest way to get started.

```dart
LegacyGanttChartWidget(
  data: myTasks,
  dependencies: myDependencies,
  visibleRows: myRows,
  rowMaxStackDepth: myStackDepths,
  gridMin: myStartDate.millisecondsSinceEpoch.toDouble(),
  gridMax: myEndDate.millisecondsSinceEpoch.toDouble(),
  // ... other properties
)
```

## 2. Controller Mode (Dynamic)

For large datasets, pagination, or lazy loading from an API, use the `LegacyGanttController`. The controller manages the visible date range and fetches only the data needed for that window.

Key properties and methods of `LegacyGanttController`:

-   **`tasksAsync`**: A callback that fires whenever the user scrolls or zooms to a new date range. You should return a `Future<List<LegacyGanttTask>>` containing the tasks for the requested `start` and `end` dates.

-   **`setVisibleRange(start, end)`**: A method to programmatically jump the chart's viewport to a specific date range. This is useful for connecting to external navigation controls like the `LegacyGanttTimelineScrubber`.

### Customizing the Loading Indicator

When using `LegacyGanttController` with an asynchronous data source, the chart will display a loading indicator while fetching new data. You can customize its appearance using properties on the `LegacyGanttChartWidget`.

-   **`loadingIndicatorType`**: Determines the style of the indicator.
    -   `GanttLoadingIndicatorType.circular` (default): Shows a `CircularProgressIndicator` in the center of the chart.
    -   `GanttLoadingIndicatorType.linear`: Shows a `LinearProgressIndicator`.

-   **`loadingIndicatorPosition`**: If using the `linear` type, this positions the indicator at the `top` (default) or `bottom` of the chart.

-   **`loadingIndicatorHeight`**: Controls the height of the `linear` indicator.

```dart
LegacyGanttChartWidget(
  controller: _controller,
  loadingIndicatorType: GanttLoadingIndicatorType.linear,
  loadingIndicatorPosition: GanttLoadingIndicatorPosition.bottom,
  loadingIndicatorHeight: 8.0,
  // ... other properties
)
```

## Understanding Stacking

The `rowMaxStackDepth` map is critical for the chart's layout. It tells the chart how tall each row needs to be to accommodate overlapping tasks, preventing them from drawing on top of each other.

-   **Key**: The `id` of a `LegacyGanttRow`.
-   **Value**: An integer representing the maximum number of tasks that can be "stacked" vertically in that row at any given time (e.g., `1` for no overlap, `3` for three concurrent tasks).

The total height of a row is calculated as `rowHeight * rowMaxStackDepth[rowId]`.

> **Note**: If the actual number of overlapping tasks in a row exceeds the value you provide in `rowMaxStackDepth`, a "Conflict Indicator" (a red, angled pattern) will be drawn to highlight the over-allocation. This behavior can be disabled by setting `showConflicts` to `false` in your data processing logic.