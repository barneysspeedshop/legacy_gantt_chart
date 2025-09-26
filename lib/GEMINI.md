# Legacy Gantt Chart

A flexible and performant Gantt chart widget for Flutter, designed for easy integration and customization. It supports dynamic data loading, interactive task manipulation (drag & drop, resize), and extensive theming.

## Features

-   **Performant Rendering:** Uses `CustomPainter` for efficient rendering of a large number of tasks and grid lines.
-   **Dynamic Data Loading:** Fetch tasks asynchronously for the visible date range using a `LegacyGanttController`.
-   **Interactive Tasks:** Built-in support for dragging, dropping, resizing, and deleting tasks.
-   **Task Stacking:** Automatically stacks overlapping tasks within the same row.
-   **Customization:**
    -   Extensive theming support via `LegacyGanttTheme`.
    -   Use custom builders (`taskBarBuilder`, `taskContentBuilder`) to render completely unique task widgets.
-   **Timeline Navigation:** Includes a `LegacyGanttTimelineScrubber` widget for an intuitive overview and navigation of the entire timeline.
-   **Special Task Types:** Support for summary bars, background highlights (e.g., for holidays), and conflict indicators.

## Getting Started

To get started, add the package to your `pubspec.yaml` and import it. Here is a minimal example of a static Gantt chart.

```dart
import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

class MyGanttChartPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 1. Define your rows
    final rows = [
      LegacyGanttRow(id: 'row1', name: 'Development'),
      LegacyGanttRow(id: 'row2', name: 'QA'),
    ];

    // 2. Define your tasks
    final tasks = [
      LegacyGanttTask(
        id: 'task1',
        rowId: 'row1',
        name: 'Implement Feature A',
        start: DateTime.now().subtract(const Duration(days: 5)),
        end: DateTime.now().add(const Duration(days: 2)),
      ),
      LegacyGanttTask(
        id: 'task2',
        rowId: 'row1',
        name: 'Implement Feature B',
        start: DateTime.now().add(const Duration(days: 3)),
        end: DateTime.now().add(const Duration(days: 8)),
      ),
      LegacyGanttTask(
        id: 'task3',
        rowId: 'row2',
        name: 'Test Feature A',
        start: DateTime.now().add(const Duration(days: 2)),
        end: DateTime.now().add(const Duration(days: 4)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Simple Gantt Chart')),
      body: LegacyGanttChartWidget(
        data: tasks,
        visibleRows: rows,
        rowMaxStackDepth: const {'row1': 1, 'row2': 1}, // Max overlapping tasks per row
        gridMin: DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch.toDouble(),
        gridMax: DateTime.now().add(const Duration(days: 15)).millisecondsSinceEpoch.toDouble(),
      ),
    );
  }
}
```

## Stop creating linter warnings
```'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss.\nTry replacing the use of the deprecated member with the replacement."
We want to use withValues(aplha: ##) instead, in all cases. withOpacity should NEVER be used.
We must also never use block function bodies unnecessarily. We should use expression body instead.
```

## Advanced Usage

### Dynamic Data Loading with `LegacyGanttController`

For real-world applications, you'll often need to load data from a server based on the visible date range. The `LegacyGanttController` is designed for this purpose.

1.  **Create a `LegacyGanttController`:** Provide it with async callbacks (`tasksAsync`, `holidaysAsync`) to fetch data.
2.  **Link the Controller:** Pass the controller to the `LegacyGanttChartWidget`. The widget will automatically listen for changes and rebuild.
3.  **Control the Timeline:** Use the controller to programmatically change the visible date range.

```dart
class DynamicGanttChartPage extends StatefulWidget {
  @override
  _DynamicGanttChartPageState createState() => _DynamicGanttChartPageState();
}

class _DynamicGanttChartPageState extends State<DynamicGanttChartPage> {
  late final LegacyGanttController _controller;
  final List<LegacyGanttRow> _rows = [
    LegacyGanttRow(id: 'row1', name: 'Server Tasks')
  ];

  @override
  void initState() {
    super.initState();
    _controller = LegacyGanttController(
      initialVisibleStartDate: DateTime.now().subtract(const Duration(days: 15)),
      initialVisibleEndDate: DateTime.now().add(const Duration(days: 15)),
      tasksAsync: _fetchTasks, // Your data fetching function
    );
  }

  // Example data fetching function
  Future<List<LegacyGanttTask>> _fetchTasks(DateTime start, DateTime end) async {
    print('Fetching tasks from $start to $end...');
    // In a real app, you would make a network request here.
    await Future.delayed(const Duration(seconds: 1));
    return [
      LegacyGanttTask(
        id: 'server_task_1',
        rowId: 'row1',
        name: 'Database Migration',
        start: start.add(const Duration(days: 2)),
        end: start.add(const Duration(days: 5)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Gantt Chart')),
      body: LegacyGanttChartWidget(
        controller: _controller,
        visibleRows: _rows,
        rowMaxStackDepth: const {'row1': 1},
      ),
    );
  }
}
```

### Timeline Navigation with `LegacyGanttTimelineScrubber`

Combine the `LegacyGanttController` with the `LegacyGanttTimelineScrubber` to provide users with a powerful way to navigate the chart's timeline.

```dart
// In your widget build method:
Column(
  children: [
    Expanded(
      child: LegacyGanttChartWidget(
        controller: _controller,
        // ... other properties
      ),
    ),
    // The Scrubber
    LegacyGanttTimelineScrubber(
      totalStartDate: DateTime(2023, 1, 1),
      totalEndDate: DateTime(2024, 12, 31),
      visibleStartDate: _controller.visibleStartDate,
      visibleEndDate: _controller.visibleEndDate,
      tasks: _controller.tasks, // Show tasks in the scrubber overview
      onWindowChanged: (newStart, newEnd) {
        _controller.setVisibleRange(newStart, newEnd);
      },
    ),
  ],
)
```

### Interactive Tasks (Drag & Drop, Resize, Delete)

Enable interactivity and listen for updates using the `onTaskUpdate` and `onTaskDelete` callbacks.

```dart
LegacyGanttChartWidget(
  // ... other properties
  enableDragAndDrop: true,
  enableResize: true,
  onTaskUpdate: (task, newStart, newEnd) {
    print('Task ${task.id} updated!');
    print('New Start: $newStart, New End: $newEnd');
    // Here you would update your state and likely call an API
    // to persist the changes.
  },
  onTaskDelete: (task) {
    print('Task ${task.id} deleted!');
    // Here you would update your state and likely call an API
    // to persist the changes.
  },
)
```

### Custom Task Appearance

You have two options for customizing how tasks are rendered:

1.  **`taskContentBuilder`**: Replaces only the content *inside* the task bar. The bar itself is still drawn by the chart. This is useful for adding custom icons, text, or progress indicators.
2.  **`taskBarBuilder`**: Replaces the *entire* task bar widget. You get full control over the appearance and can add custom gestures.

**Example using `taskContentBuilder`:**

```dart
LegacyGanttChartWidget(
  // ... other properties
  taskContentBuilder: (task) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.yellow, size: 14),
          const SizedBox(width: 4),
          Text(
            task.name ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  },
)
```

### Custom Timeline Labels

You can provide a `timelineAxisLabelBuilder` to customize the labels on the timeline. This is useful for displaying months, quarters, or other custom formats.

```dart
LegacyGanttChartWidget(
  // ... other properties
  timelineAxisLabelBuilder: (date, interval) {
    if (interval.inDays > 14) {
      return DateFormat('MMM').format(date);
    } else {
      return DateFormat('d').format(date);
    }
  },
)
```

### Theming

Customize colors, text styles, and more by providing a `LegacyGanttTheme`. You can create one from scratch or modify the default theme derived from your app's `ThemeData`.

```dart
LegacyGanttChartWidget(
  // ... other properties
  theme: LegacyGanttTheme.fromTheme(Theme.of(context)).copyWith(
    barColorPrimary: Colors.green,
    gridColor: Colors.grey.shade800,
    backgroundColor: Colors.black,
    taskTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
  ),
)
```