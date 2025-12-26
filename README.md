# Legacy Gantt Chart

[![Pub Version](https://img.shields.io/pub/v/legacy_gantt_chart)](https://pub.dev/packages/legacy_gantt_chart)
[![Live Demo](https://img.shields.io/badge/live-demo-brightgreen)](https://barneysspeedshop.github.io/legacy_gantt_chart/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A flexible and performant Gantt chart widget for Flutter. Supports interactive drag-and-drop, resizing, dynamic data loading, and extensive theming.

## Table of Contents

- [About the Name](#about-the-name)
- [Features](#features)
  - [Architecture & Platform](#architecture--platform)
  - [Data & Backend](#data--backend)
  - [Interactivity](#interactivity)
  - [Customization & Theming](#customization--theming)
  - [Timeline & Dependencies](#timeline--dependencies)
  - [Resource Management](#resource-management)
- [Installation](#installation)
- [Migration Guide](#migration-guide)
  - [Migrating to 3.0.0](#migrating-to-v300)
- [Quick Start](#quick-start)
- [Running the Example](#running-the-example)
- [API Documentation](#api-documentation)
- [Advanced Usage](#advanced-usage)
  - [Dynamic Data Loading with LegacyGanttController](#dynamic-data-loading-with-legacyganttcontroller)
  - [Timeline Navigation with LegacyGanttTimelineScrubber](#timeline-navigation-with-legacygantttimelinescrubber)
  - [Interactive Tasks (Drag & Drop, Resize)](#interactive-tasks-drag--drop-resize)
  - [Custom Task Appearance](#custom-task-appearance)
  - [Custom Timeline Labels](#custom-timeline-labels)
  - [Theming](#theming)
- [Experimental: Real-time Sync & Offline Support](#experimental-real-time-sync--offline-support)
- [Contributing](#contributing)
- [License](#license)

## About the Name

The name `legacy_gantt_chart` is a tribute to the package's author, Patrick Legacy. It does not imply that the package is outdated or unmaintained. In fact, it is a modern, actively developed, and highly capable solution for building production-ready Flutter applications.

[![Legacy Gantt Chart Example](https://github.com/barneysspeedshop/legacy_gantt_chart/raw/main/assets/example.png)](https://barneysspeedshop.github.io/legacy_gantt_chart/)

[![Legacy Gantt Chart Usage GIF](https://github.com/barneysspeedshop/legacy_gantt_chart/raw/main/assets/usage.gif)](https://barneysspeedshop.github.io/legacy_gantt_chart/)

[ ^ Table of Contents ^ ](#table-of-contents)

---

## Features

### Architecture & Platform
-   **Cross-Platform:** Built for Flutter, the chart runs on iOS, Android, Web, Windows, macOS, and Linux from a single codebase.
-   **Web Support:** When compiled for web, supports all modern browsers including Chrome, Firefox, Safari, and Edge.
-   **Scalability:** Highly performant rendering for projects with over 10,000 tasks.
-   **Performant Rendering:** Uses `CustomPainter` for efficient rendering of a large number of tasks and grid lines.
-   **State Management:** Managed via the robust `LegacyGanttController`.
-   **Example Architecture:** The accompanying example application showcases a scalable Model-View-ViewModel (MVVM) architecture, providing a clear blueprint for real-world use.
-   **Core Dependencies:** Built on the robust `provider` package for state management and `intl` for localization.
-   **Multi-Chart Support:** As a standard Flutter widget, you can display multiple Gantt charts on a single page.

### Data & Backend
-   **Backend Agnostic:** Connects to any backend (REST, GraphQL, etc.).
-   **JSON Data:** Designed to work with data from standard JSON APIs.
-   **Dynamic Data Loading:** Fetch tasks asynchronously for the visible date range using a `LegacyGanttController`.
-   **Real-time Updates:** Push data changes to the controller at any time for live updates.
-   **Full CRUD Support:** Create, read, update, and delete tasks with intuitive callbacks.
-   **Custom Data Fields:** Add custom data to your own models and display it using builders.
-   **Inactive Tasks:** Filter your data source or use custom styling to represent inactive tasks or dependencies.
-   **Sovereign Sync (CRDT & HLC):** Implements Hybrid Logical Clocks and Merkle-tree-like structures for robust, conflict-free offline editing.

### Interactivity
-   **Task Creation:** Create new tasks by clicking on empty chart space.
-   **Drag & Drop:** Move tasks along the timeline or between rows.
-   **Task Resizing:** Resize tasks by dragging their start or end handles.
-   **Touch Support:** All interactions work seamlessly on touch devices.
-   **Task Tooltips:** Tooltips appear when dragging or resizing tasks.
-   **Task Options Menu:** Right-click or tap a task's option icon to access actions like copy, delete, and dependency management.
-   **Interactive Dependency Creation:** Users can visually create dependencies by dragging a connector from one task to another.
-   **Read-Only Mode:** Easily disable all user interactions for a static, read-only view of the chart.

### Customization & Theming
-   **Fully Themeable:** Use `LegacyGanttTheme` to customize colors, text styles, and more.
-   **Multiple Themes:** Create and switch between your own custom theme objects.
-   **Custom Task Widgets:** Replace the default task bars with your own custom widgets using a `taskBarBuilder`.
-   **Custom Task Content:** Add custom content like icons or progress bars inside the default task bars using `taskContentBuilder`.
-   **Individual Task Styling:** Style tasks individually by setting a color in the data model or using logic in a builder.
-   **Flexible Layout:** The chart widget is decoupled from the data grid. While the example shows a grid on the left for task details, you are free to build your UI however you see fit, or not include a data grid at all. You can also configure the height of the timeline axis and individual task rows.
-   **Enhanced Localization**: Tooltips now fully respect locale settings for date and time formatting, providing a more natural user experience across different regions. The example application includes a locale selector to demonstrate this feature.
-   **Localization:** Built with localization in mind, allowing you to format dates and text for different locales.

### Timeline & Dependencies
-   **Unique Timeline Scrubber:** Navigate vast timelines with ease using the `LegacyGanttTimelineScrubber`. Inspired by professional audio/visual editing software, this powerful widget provides a high-level overview of the entire project. It features dynamic viewbox zooming, which intelligently frames the selected date range for enhanced precision. Fade indicators at the edges and a convenient "Reset Zoom" button appear when zoomed, ensuring you never lose track of your position or struggle to get back to the full view. This advanced navigation system is unique among Gantt libraries on pub.dev and sets this package apart.
-   **Task Dependencies:** Define and visualize relationships between tasks. Supports Finish-to-Start, Start-to-Start, Finish-to-Finish, Start-to-Finish, and Contained dependency types.
-   **Task Stacking:** Automatically stacks overlapping tasks within the same row.
-   **Special Task Types & Visual Cues:** The chart uses specific visual patterns to convey important information at a glance:
    -   **Summary Bars (Angled Pattern):** A summary bar depicts a resource's overall time allocation (e.g., a developer's work week). The angled pattern signifies it's a container for other tasks. Child rows underneath show the specific tasks that consume this allocated time, making it easy to see how the resource's time is being used and whether they have availability.
    -   **Conflict Indicators (Red Angled Pattern):** This pattern is used to raise awareness of contemporaneous activity that exceeds capacity. It typically appears when more tasks are scheduled in a row than the `rowMaxStackDepth` allows, highlighting over-allocation or scheduling issues.
    -   **Vertical Markers (Background Highlights):** Simple colored rectangles used to denote special time ranges like weekends, holidays, or periods of unavailability for a specific resource.
    -   **Automatic Conflict Detection:** The example application includes a `LegacyGanttConflictDetector` utility that automatically processes your task data. It identifies tasks within the same logical group (e.g., assigned to the same person) that overlap in time. When a conflict is found, the detector generates new, temporary `LegacyGanttTask` objects with the `isOverlapIndicator` flag set to `true`. These "extra" tasks are what get rendered as the red, angled conflict pattern on your chart. This is an opt-in feature; you have full control over whether and how to run conflict detection on your data before passing it to the widget.
-   **Task Behaviors:** Summary tasks can be configured with specialized behaviors to control how they interact with their children during moving and resizing:
    -   **Standard (Group):** The default behavior. The parent's date range is driven by its children. Moving the parent moves all children with it.
    -   **Static Bucket:** The parent acts as a fixed container. Moving the parent does *not* move the children. This is useful for defining fixed time buckets (sprints, quarters) where tasks are dropped in.
    -   **Constrain:** The parent acts as a boundary. Resizing the parent pushes or clamps children to ensure they stay strictly within the parent's date range.
    -   **Elastic:** Resizing the parent proportionally scales the duration and start/end times of all children. Stretching the parent stretches the entire schedule inside it.
-   **Customizable Zoom Levels:** Zoom from a multi-year overview down to the millisecond level.
-   **Auto-Scheduling:** Enable auto-scheduling to automatically adjust the start and end dates of dependent tasks when a predecessor or parent task is moved. This maintains the integrity of your project schedule. You can enable this globally or on a per-task basis.
-   **Work Calendar Support:** Define working days (e.g., Mon-Fri) and holidays. Tasks with `usesWorkCalendar` enabled will automatically skip non-working days when calculating their duration and end dates, ensuring realistic scheduling.
-   **Programmatic Validation:** Use callbacks like `onTaskUpdate` to validate user actions before committing them.

### Resource Management
-   **Resource Histogram:** Visualize resource allocation density over time using the `ResourceHistogramWidget`. This helps identify bottlenecks where specific resources are over-allocated.

[ ^ Table of Contents ^ ](#table-of-contents)

---

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  legacy_gantt_chart: ^5.0.0
```

Then, you can install the package using the command-line:

```shell
flutter pub get
```

Now, import it in your Dart code:

```dart
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
```

[ ^Table of Contents ^ ](#table-of-contents)

---

## Migration Guide

### Migrating to 5.0.0

Version 5.0.0 introduces breaking changes to the sync API and the underlying data model to support more robust Hybrid Logical Clocks (HLC).

*   **Breaking Change (Data Model):** `LegacyGanttTask.lastUpdated` is now type `Hlc` (Hybrid Logical Clock) instead of `int?`. You must use `Hlc.parse()` or `Hlc.fromDate()` when manually instantiating tasks with timestamps.
*   **Breaking Change (Sync Interface):** `GanttSyncClient` now requires `Stream<SyncProgress> get inboundProgress` and `Stream<int> get outboundPendingCount`.
*   **Breaking Change (Protocol):** The sync protocol now uses string-based HLC timestamps (`"2024-01-01T12:00:00.000Z-0000-nodeId"`) instead of integer epochs.
*   **BREAKING (UI):** Refactor `noDataWidgetBuilder` to `emptyStateBuilder` to align with package convention and reduce duplication.
*   **BREAKING (Theming):** Refactor `loadingIndicatorHeight` to `linearProgressHeight` to align with package convention.

#### How to Migrate

**1. Data Model (HLC)**
If you are manually creating tasks, replace `int` timestamps with `Hlc` objects.
```dart
// Before
LegacyGanttTask(lastUpdated: DateTime.now().millisecondsSinceEpoch);

// After
LegacyGanttTask(lastUpdated: Hlc.fromDate(DateTime.now(), 'device-id'));
```

**2. Sync Client Interface**
Update your custom `GanttSyncClient` implementations to include the new progress streams.
```dart
class MySyncClient implements GanttSyncClient {
  @override
  Stream<SyncProgress> get inboundProgress => _inboundController.stream;
  @override
  Stream<int> get outboundPendingCount => _outboundController.stream;
  // ...
}
```

**3. UI & Theming Property Renames**
Rename the following parameters in `LegacyGanttChartWidget` and associated theme classes:
```dart
// Before
LegacyGanttChartWidget(
  noDataWidgetBuilder: (context) => MyCustomEmptyView(),
  loadingIndicatorHeight: 4.0,
)

// After
LegacyGanttChartWidget(
  emptyStateBuilder: (context) => MyCustomEmptyView(),
  linearProgressHeight: 4.0,
)
```

### Migrating to v3.0.0

Version 3.0.0 introduces a breaking change to improve performance by separating conflict indicators from the main task list.

**Before (v2.x.x):**

Conflict indicators were mixed into the main `data` list.

```dart
// Conflict indicators were mixed into the main data list
final allTasks = [...myTasks, ...myConflictIndicators];

LegacyGanttChartWidget(
  data: allTasks,
  // ...
);
```

**After (v3.0.0):**

Pass conflict indicators to the new `conflictIndicators` parameter. This applies to both `LegacyGanttChartWidget` and `LegacyGanttController`.

```dart
// Pass conflict indicators separately
LegacyGanttChartWidget(
  data: myTasks,
  conflictIndicators: myConflictIndicators,
  // ...
);
```
[ ^Table of Contents ^ ](#table-of-contents)

---

## Quick Start

Here is a minimal example of how to create a static Gantt chart.

```dart
import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

class MinimalGanttChart extends StatelessWidget {
  const MinimalGanttChart({super.key});

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

    // 3. Create the widget
    return Scaffold(
      appBar: AppBar(title: const Text('Simple Gantt Chart')),
      body: LegacyGanttChartWidget(
        data: tasks,
        visibleRows: rows,
        rowMaxStackDepth: const {'row1': 2, 'row2': 1}, // Max overlapping tasks per row
        gridMin: DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch.toDouble(),
        gridMax: DateTime.now().add(const Duration(days: 15)).millisecondsSinceEpoch.toDouble(),
      ),
    );
  }
}
```

[ ^Table of Contents ^ ](#table-of-contents)

## Running the Example

To see a full-featured demo of the `legacy_gantt_chart` in action, you can run the example application included in the repository.

1.  **Navigate to the `example` directory:**
    ```shell
    cd example
    ```

2.  **Install dependencies:**
    ```shell
    flutter pub get
    ```

3.  **Run the app:**
    ```shell
    flutter run
    ```

[ ^Table of Contents ^ ](#table-of-contents)

## API Documentation 

For a complete overview of all available classes, methods, and properties, please see the API reference on pub.dev.

[ ^Table of Contents ^ ](#table-of-contents)

## Advanced Usage

### Dynamic Data Loading with `LegacyGanttController`

For real-world applications, you'll often need to load data from a server based on the visible date range. The `LegacyGanttController` is designed for this purpose.

```dart
class DynamicGanttChartPage extends StatefulWidget {
  @override
  _DynamicGanttChartPageState createState() => _DynamicGanttChartPageState();
}

class _DynamicGanttChartPageState extends State<DynamicGanttChartPage> {
  late final LegacyGanttController _controller;
  final List<LegacyGanttRow> _rows = [LegacyGanttRow(id: 'row1')];

  @override
  void initState() {
    super.initState();
    _controller = LegacyGanttController(
      initialVisibleStartDate: DateTime.now().subtract(const Duration(days: 15)),
      initialVisibleEndDate: DateTime.now().add(const Duration(days: 15)),
      tasksAsync: _fetchTasks, // Your data fetching function
    );
  }

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

The `legacy_timeline_scrubber` package is a separate, standalone package that is re-exported by `legacy_gantt_chart` for convenience. It provides a "mini-map" of the entire project timeline, allowing for quick and intuitive navigation.

To achieve two-way synchronization, you need to manage a shared state for the visible date range. When the user scrolls the chart, the scrubber's window should update. When the user drags the scrubber's window, the chart should scroll to that date range.

Here is a simplified example using `StatefulWidget` to manage the state. In a real application, you would likely use a more robust state management solution like Provider or BLoC, as demonstrated in the example app with `GanttViewModel`.

```dart
class SyncedGanttChart extends StatefulWidget {
  @override
  _SyncedGanttChartState createState() => _SyncedGanttChartState();
}

class _SyncedGanttChartState extends State<SyncedGanttChart> {
  // 1. Define state for the visible window
  DateTime _visibleStart = DateTime.now().subtract(const Duration(days: 15));
  DateTime _visibleEnd = DateTime.now().add(const Duration(days: 15));

  // Define the total range of your project
  final DateTime _totalStart = DateTime.now().subtract(const Duration(days: 365));
  final DateTime _totalEnd = DateTime.now().add(const Duration(days: 365));

  // Your task data
  final List<LegacyGanttTask> _tasks = []; // Populate with your tasks
  final List<LegacyGanttRow> _rows = []; // Populate with your rows

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LegacyGanttChartWidget(
            data: _tasks,
            visibleRows: _rows,
            rowMaxStackDepth: const {},
            // 2. The chart's visible window is driven by the state
            gridMin: _visibleStart.millisecondsSinceEpoch.toDouble(),
            gridMax: _visibleEnd.millisecondsSinceEpoch.toDouble(),
            // The total range defines the scrollable area
            totalGridMin: _totalStart.millisecondsSinceEpoch.toDouble(),
            totalGridMax: _totalEnd.millisecondsSinceEpoch.toDouble(),
            // Note: For the chart to update the scrubber on scroll, you would
            // need to use a controller or listen to scroll notifications to
            // calculate the new visible range and update the state.
          ),
        ),
        LegacyGanttTimelineScrubber(
          totalStartDate: _totalStart,
          totalEndDate: _totalEnd,
          // 3. The scrubber's window is also driven by the state
          visibleStartDate: _visibleStart,
          visibleEndDate: _visibleEnd,
          tasks: _tasks,
          // 4. When the scrubber changes, update the state
          onWindowChanged: (newStart, newEnd) {
            setState(() {
              _visibleStart = newStart;
              _visibleEnd = newEnd;
            });
          },
        ),
      ],
    );
  }
}
```

### Interactive Tasks (Drag & Drop, Resize)

Enable interactivity and listen for updates using the `onTaskUpdate` callback.

```dart
LegacyGanttChartWidget(
  // ... other properties
  enableDragAndDrop: true,
  enableResize: true,
  onTaskUpdate: (task, newStart, newEnd) {
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

### Customizing the "No Data" View

You can provide a custom widget to be displayed when `data` is empty using the `emptyStateBuilder`.

```dart
LegacyGanttChartWidget(
  data: [], // Empty data
  visibleRows: [],
  rowMaxStackDepth: {},
  emptyStateBuilder: (context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('No tasks scheduled yet.', style: Theme.of(context).textTheme.titleMedium),
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

### User Interaction Modes (Draw & Select)

The package now supports specialized interaction modes, managed via the `LegacyGanttController`.

-   **`GanttTool.move` (Default):** Standard interaction. Pan the chart, drag-and-drop tasks, and resize tasks.
-   **`GanttTool.select`:** Click and drag to draw a selection box and select multiple tasks at once.
-   **`GanttTool.draw`:** Click and drag on an empty row to visually "draw" a new task.

#### Implementing the Draw Tool

To enable the draw tool, you need to provide a UI for switching tools and handle the drawing completion event.

1.  **Toolbar:** Use the `LegacyGanttToolbar` widget to allow users to switch between modes.
    ```dart
    Column(
      children: [
        LegacyGanttToolbar(controller: _controller),
        Expanded(child: LegacyGanttChartWidget(...)),
      ],
    )
    ```

2.  **Handle Drawing:** Implement the `onTaskDrawEnd` callback. This is triggered when the user finishes dragging in draw mode.
    ```dart
    LegacyGanttChartWidget(
      controller: _controller,
      // ... other props
      onTaskDrawEnd: (start, end, rowId) {
        // Logic to create a new task
        final newTask = LegacyGanttTask(
          id: Uuid().v4(),
          rowId: rowId,
          name: 'New Task',
          start: start,
          end: end,
        );
        setState(() {
          _tasks.add(newTask);
        });
      },
    )
    ```

### Theming

Customize colors, text styles, and more by providing a `LegacyGanttTheme`. You can create one from scratch or modify the default theme derived from your app's `ThemeData`.

[ ^Table of Contents ^ ](#table-of-contents)

---

## Experimental: Real-time Sync & Offline Support

> **Note:** This feature is currently in **alpha**. APIs are subject to change.

The package now includes experimental support for real-time synchronization and offline capabilities using Conflict-Free Replicated Data Types (CRDTs). This allows multiple users to edit the chart simultaneously, with changes merging automatically and conflict-free.

### Key Components

*   **`WebSocketGanttSyncClient`**: Connects to a compatible backend to push and receive updates in real-time. A reference server implementation is provided in `bin/server.dart`.
*   **`OfflineGanttSyncClient`**: Queues operations when offline and syncs them when the connection is restored.
*   **`CrdtEngine`**: The core logic that handles the merging of concurrent edits.

### Usage

To use the sync client, you typically initialize it and pass it to your `LegacyGanttController` or view model.

```dart
// 1. Authenticate (Optional - depends on server)
final token = 'your-jwt-token'; 

// 2. Initialize
final syncClient = WebSocketGanttSyncClient(
  uri: Uri.parse('ws://your-server.com/ws'),
  authToken: token,
);

// 3. Connect
syncClient.connect('your-tenant-id');

// 4. Send Operation
syncClient.sendOperation(Operation(
  type: 'INSERT_TASK',
  data: newTask.toJson(),
  timestamp: Hlc.fromDate(DateTime.now(), 'my-device-id'),
  actorId: 'user-1',
));
```

For a full implementation reference, check the `example/lib/main.dart` file which implements a complete sync-enabled Gantt chart.

[ ^Table of Contents ^ ](#table-of-contents)

---

## Contributing

Contributions are welcome! Please see our [Contributing Guidelines](CONTRIBUTING.md) for more details on how to get started, including our code style guide.

[ ^Table of Contents ^ ](#table-of-contents)

## License

This project is licensed under the MIT License.

[ ^Table of Contents ^ ](#table-of-contents)
