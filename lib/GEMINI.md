# Gemini Code Generation Documentation

This document provides an overview of the `legacy_gantt_chart` package.

## `legacy_gantt_chart.dart`

This file serves as the main entry point for the `legacy_gantt_chart` package. It exports all the public-facing APIs that developers need to use the Gantt chart in their applications.

### Exports

The file exports the following key components from the `src/` directory, making them accessible to consumers of the package:

-   **`LegacyGanttChartWidget`**: The main widget for displaying the Gantt chart.
-   **Data Models**:
    -   `LegacyGanttTask`: Represents a single task or event on the chart.
    -   `LegacyGanttRow`: Represents a horizontal row in the chart.
    -   `LegacyGanttDependency`: Represents a dependency between two tasks.
    -   `LegacyGanttTheme`: Defines the visual styling of the chart.
-   **Controller**:
    -   `LegacyGanttController`: Allows for programmatic control of the chart's state, including dynamic data loading.
-   **ViewModel**:
    -   `LegacyGanttViewModel`: Manages the internal state and interaction logic. Exporting this might be intended for advanced customization or for developers who wish to build their own UI on top of the Gantt chart's logic.
-   **Utilities**:
    -   `LegacyGanttConflictDetector`: A utility to detect overlapping tasks within the same row and stack.
-   **Third-Party Re-export**:
    -   It also re-exports the `legacy_timeline_scrubber` package, which provides a timeline scrubbing widget that can be easily integrated with the Gantt chart for navigation. It hides some classes from the scrubber package to avoid naming conflicts.

By importing just `package:legacy_gantt_chart/legacy_gantt_chart.dart`, a developer gains access to all the necessary components to build and interact with a feature-rich Gantt chart.
