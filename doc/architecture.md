# Architecture Overview

The `legacy_gantt_chart` package is designed with a clear separation of concerns to ensure performance and flexibility. The core component is the `LegacyGanttChartWidget`, which coordinates several specialized classes to render the chart and handle user interactions.

The following diagram illustrates the main components and their roles:

```plaintext
[ LegacyGanttChartWidget ]
       |
       +--- [ LegacyGanttViewModel ] (Manages state, gesture logic, coordinate conversion)
       |
       +--- [ LegacyGanttController ] (Optional: Manages dynamic data fetching & viewport)
       |
       +--- [ Painters ]
            |
            +--- AxisPainter (Draws background grid & time headers)
            |
            +--- BarsCollectionPainter (Highly optimized painter for all tasks & dependencies)
            |
            +--- ResourceHistogramWidget (Visualizes resource density)
```

## Component Breakdown

*   **`LegacyGanttChartWidget`**: The main `StatefulWidget` that you add to your application. It serves as the entry point and orchestrates the other components. It handles the lifecycle and passes configuration data down to the view model and painters.

*   **`LegacyGanttViewModel`**: An internal `ChangeNotifier` that holds the chart's UI state. It translates user gestures (like panning and tapping) into actions, manages the scroll position, calculates the time-to-pixel scale, and determines what is visible. It is the "brain" behind the chart's interactivity.

*   **`LegacyGanttController`**: An optional `ChangeNotifier` that you can provide to the widget for dynamic data loading. It manages the visible date range and exposes methods to fetch data asynchronously as the user scrolls and zooms. This is the key to handling large datasets efficiently.

*   **Painters (`CustomPainter`)**: For maximum performance, the chart relies on `CustomPainter` to draw the most complex visual elements.
    *   **`AxisPainter`**: Responsible for drawing the background grid lines and the labels on the timeline axis.
    *   **`BarsCollectionPainter`**: A highly optimized painter that draws all task bars, summary bars, highlights, conflict indicators, and dependency lines in a single paint cycle.

*   **Resource Management**:
    *   **`ResourceHistogramWidget`**: A widget that visualizes resource allocation density over time, helping to identify bottlenecks.

*   **Logic & Helpers**:
    *   **`WorkCalendar`**: Defines working days and holidays for realistic scheduling.
    *   **Auto-Scheduling**: Logic within the ViewModel that automatically adjusts dependent tasks when a predecessor or parent is modified.
    *   **`LegacyGanttConflictDetector`**: Utility to identify overlapping tasks.

*   **Repository Layer (Optional)**: For offline-first or local-only deployments, the package supports a repository pattern backed by SQLite and CRDTs.
    *   **`LocalGanttRepository`**: Handles CRUD operations and data synchronization logic. It abstracts the underlying database and provides streams for real-time UI updates.
    *   **`GanttDb`**: The local SQLite database, enhanced with `sqlite_crdt` to ensure consistent state across multiple devices or offline sessions.