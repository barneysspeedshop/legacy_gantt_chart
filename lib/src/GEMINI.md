# Gemini Code Generation Documentation

This document provides a detailed overview of the core components within the `lib/src/` directory, which form the foundation of the Gantt chart functionality.

## Core Components

### `legacy_gantt_chart_widget.dart`

This is the main entry point for rendering the Gantt chart. It's a `StatefulWidget` that orchestrates the entire UI, bringing together data, state management, and rendering.

-   **Data Handling**: It is designed to be flexible in how it receives data:
    1.  **Static Data**: A simple `List<LegacyGanttTask>` for displaying a fixed set of tasks.
    2.  **Asynchronous Loading**: A `Future<List<LegacyGanttTask>>` to display a loading indicator while tasks are fetched, and then render them once available. It uses a `FutureBuilder` for this.
    3.  **Dynamic Control**: A `LegacyGanttController` for advanced use cases where data needs to be fetched dynamically as the user scrolls or when the visible date range changes. It uses an `AnimatedBuilder` to listen to the controller and rebuild when data changes.

-   **UI Composition**:
    -   It uses a `ChangeNotifierProvider` to create and provide the `LegacyGanttViewModel` to its descendants.
    -   A `Consumer<LegacyGanttViewModel>` listens for state changes from the view model and rebuilds the chart accordingly.
    -   The UI is built using a `Stack` that layers several components:
        -   `CustomPaint` with `AxisPainter` for the background grid.
        -   `CustomPaint` with `BarsCollectionPainter` for drawing the task bars and dependencies.
        -   A series of `Positioned` widgets for custom task bar builders or other interactive elements.
        -   A `CustomPaint` for the timeline header, also using `AxisPainter`.

-   **Key Customization Callbacks**:
    -   `taskBarBuilder`: Allows for replacing the default task bar with a completely custom widget.
    -   `taskContentBuilder`: Allows for injecting custom content *inside* the default task bar.
    -   `timelineAxisHeaderBuilder`: Allows for replacing the entire timeline header with a custom widget.
    -   `onTaskUpdate`: A crucial callback that is invoked when a task is moved or resized, providing the updated task information.

-   **Internal Widgets**:
    -   `_DefaultTaskBar`: The default widget used to represent a task if no custom builder is provided.
    -   `_OverlapIndicatorBar`: A widget that uses a `CustomPainter` (`_OverlapPainter`) to draw a special pattern indicating that too many tasks are overlapping in the same space.

### `legacy_gantt_view_model.dart`

This class is a `ChangeNotifier` and serves as the "brain" of the Gantt chart. It encapsulates all the state and business logic required for the chart to function.

-   **State Management**: It holds the chart's state, including:
    -   The calculated scales for converting between `DateTime` and pixel coordinates.
    -   The current vertical scroll offset (`translateY`).
    -   The state of any ongoing user interaction (e.g., `draggedTask`, `dragMode`).
    -   The current mouse cursor style.

-   **Interaction Logic**: It contains all the gesture handling logic:
    -   `onPanStart`, `onPanUpdate`, `onPanEnd`: These methods work together to handle dragging. They determine if the user is performing a vertical scroll or a horizontal drag to move/resize a task.
    -   `onTapUp`, `onDoubleTap`: Handle tap and double-tap events on tasks.
    -   `onHover`: Manages hover effects, updates the mouse cursor, and shows/hides tooltips.

-   **Drag and Resize Operations**:
    -   It defines a `DragMode` enum (`none`, `move`, `resizeStart`, `resizeEnd`) to track the current drag operation.
    -   During a drag, it calculates a "ghost" task (`ghostTaskStart`, `ghostTaskEnd`) to show a preview of the task's new position.
    -   It manages a resize/drag tooltip, updating its text and position as the user drags.

-   **Coordinate System**:
    -   `_calculateDomains`: This method calculates the `_totalScale` function, which is essential for mapping dates to the horizontal axis.
    -   `_getTaskPartAtPosition`: A hit-testing method that determines which task (and which part of it: body, start handle, or end handle) is at a given screen position.

### `legacy_gantt_controller.dart`

This controller provides an API for programmatically managing the Gantt chart from outside the widget. It's essential for building more complex applications where other UI elements need to interact with the chart.

-   **External Control**:
    -   `setVisibleRange`: Allows you to programmatically set the visible start and end dates of the chart.
    -   `next()` and `prev()`: Convenience methods for paging the timeline forward or backward.
    -   `setTasks`, `setHolidays`, `setDependencies`: Methods to manually update the data displayed on the chart.

-   **Dynamic Data Fetching**:
    -   The controller can be constructed with `tasksAsync` and `holidaysAsync` callback functions.
    -   When `setVisibleRange` is called (or `next`/`prev`), the controller invokes these callbacks with the new date range.
    -   It manages the loading state (`isLoading`, `isHolidayLoading`) and notifies the `LegacyGanttChartWidget` to rebuild and display a loading indicator.

### `axis_painter.dart`

A `CustomPainter` dedicated to drawing the time axis and the background grid lines.

-   **Dynamic Ticks**: Its core logic is to determine the appropriate interval for tick marks (e.g., every day, every 2 hours, every 15 minutes) based on the duration of the visible time range (`visibleDuration`). This ensures the timeline is always readable, no matter the zoom level.
-   **Label Formatting**: It uses the `intl` package to format the labels for the tick marks appropriately for the chosen interval.
-   **`shouldRepaint`**: The repaint logic is optimized to only trigger a repaint when necessary, such as when the theme, scale, or visible domain changes.

### `bars_collection_painter.dart`

A highly optimized `CustomPainter` responsible for drawing all the visual elements within the main chart area, including tasks, dependencies, and highlights.

-   **Efficient Rendering**: It is designed to draw a large number of items in a single paint cycle for optimal performance. It iterates through the visible rows and tasks, drawing them directly onto the canvas.
-   **Painting Order**: It follows a specific painting order to ensure correct layering:
    1.  Dependency backgrounds (for "contained" dependencies).
    2.  Empty space highlights (for creating new tasks).
    3.  Time range highlight bars (e.g., holidays).
    4.  Regular task bars (and their segments, progress, and summary patterns).
    5.  Conflict indicators.
    6.  Dependency lines between tasks.
    7.  The "ghost" bar for the task currently being dragged.
-   **Customization Hooks**: It checks `hasCustomTaskBuilder` and `hasCustomTaskContentBuilder` to know whether it should skip drawing the default bars or their content, deferring to the widget layer.
-   **Helper Methods**: It contains numerous private helper methods (`_drawSummaryPattern`, `_drawConflictIndicator`, `_drawFinishToStartDependency`, etc.) that encapsulate the drawing logic for specific elements.

## Subdirectories

-   **`models/`**: Contains all the data model classes used by the Gantt chart, such as `LegacyGanttTask`, `LegacyGanttRow`, `LegacyGanttDependency`, and `LegacyGanttTheme`. These classes define the structure of the data that the chart displays.
-   **`utils/`**: Contains utility functions and helper classes.
-   **`widgets/`**: Contains smaller, reusable Flutter widgets that are part of the Gantt chart's UI, but are not custom painters.