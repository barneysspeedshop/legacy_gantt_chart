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
## 3. Local Databases & CRDTs (Offline-First)

For applications requiring offline capabilities or real-time collaboration, `legacy_gantt_chart` supports a local database mode backed by `sqlite_crdt`.

### Key Benefits
-   **Offline Persistence**: Data is stored locally on the device (SQLite).
-   **Conflict-Free**: Uses Conflict-Free Replicated Data Types (CRDTs) to handle data synchronization, allowing multiple users or devices to edit the same schedule without write conflicts.
-   **Reactive Updates**: The UI listens to database streams, ensuring that changes (local or remote) are reflected immediately.

### Implementation Pattern

1.  **Repository**: Use `LocalGanttRepository` to mediate between the UI (ViewModel) and the Database.
2.  **Source vs. View**: Maintain a clear separation between your source data (the full dataset from the DB) and the view data (filtered list for the UI).
    -   **Source (`_allGanttTasks`)**: The authoritative list from the repository stream. All mutations (add, update, delete) must operate on this list.
    -   **View (`_ganttTasks`)**: The filtered subset passed to the `LegacyGanttChartWidget`. This list mirrors the source but excludes hidden rows or filtered items.


## 4. Work Calendars

The `WorkCalendar` feature allows you to define working days (e.g., Mon-Fri) and holidays. When a task has `usesWorkCalendar` set to `true`, its duration and end date are calculated by skipping non-working days.

```dart
LegacyGanttChartWidget(
  workCalendar: WorkCalendar(
    weekendDays: [DateTime.saturday, DateTime.sunday],
    holidays: [DateTime(2024, 12, 25)],
  ),
  // ...
)
```

## 5. Auto-Scheduling

Auto-scheduling ensures that task dependencies are respected. When you move a parent task or a predecessor, linked tasks are automatically shifted.
-   **Global Toggle**: `LegacyGanttViewModel(enableAutoScheduling: true)`
-   **Per-Task Toggle**: `LegacyGanttTask(isAutoScheduled: false)`

## 6. Resource Management (Histogram)

To visualize resource usage, you can enable the resource histogram. This aggregates the `load` of all tasks assigned to a `resourceId` across time buckets.

```dart
LegacyGanttChartWidget(
  showResourceHistogram: true,
  // ...
)
```


## Understanding Stacking

The `rowMaxStackDepth` map is critical for the chart's layout. It tells the chart how tall each row needs to be to accommodate overlapping tasks, preventing them from drawing on top of each other.

-   **Key**: The `id` of a `LegacyGanttRow`.
-   **Value**: An integer representing the maximum number of tasks that can be "stacked" vertically in that row at any given time (e.g., `1` for no overlap, `3` for three concurrent tasks).

The total height of a row is calculated as `rowHeight * rowMaxStackDepth[rowId]`.

> **Note**: If the actual number of overlapping tasks in a row exceeds the value you provide in `rowMaxStackDepth`, a "Conflict Indicator" (a red, angled pattern) will be drawn to highlight the over-allocation. This behavior can be disabled by setting `showConflicts` to `false` in your data processing logic.