# Gemini Code Generation Documentation

This document provides an overview of the data models used in the Gantt chart package, located in the `lib/src/models/` directory. These classes define the structure and properties of the various elements that are rendered on the chart.

## Core Models

### `legacy_gantt_task.dart`

This file defines the core `LegacyGanttTask` class, which represents a single bar or event on the Gantt chart.

-   **`LegacyGanttTask`**: An immutable class containing all the information needed to render a task.
    -   **Core Properties**: `id`, `rowId`, `start`, `end`, `name`.
    -   **Styling**: `color`, `textColor` for individual task styling.
    -   **Behavioral Flags**:
        -   `isSummary`: Indicates a summary task, which may be rendered with a special pattern.
        -   `isTimeRangeHighlight`: Used for rendering background highlights like holidays or weekends.
        -   `isOverlapIndicator`: A special task type used to indicate that too many tasks are stacked in one place.
    -   **Data Properties**: `completion` (for progress bars), `segments` (for non-continuous tasks).
    -   **Custom Rendering**: `cellBuilder` allows for completely custom, day-by-day rendering of a task, bypassing the default bar painter.

-   **`LegacyGanttTaskSegment`**: Represents a single continuous portion of a task. A `LegacyGanttTask` can have multiple segments if it is not continuous.

### `legacy_gantt_row.dart`

-   **`LegacyGanttRow`**: A simple, immutable class that represents a horizontal row in the Gantt chart. Its primary purpose is to provide a unique `id` for each row, which is used to associate tasks with their correct row.

### `legacy_gantt_dependency.dart`

This file defines the model for representing dependencies between tasks.

-   **`LegacyGanttTaskDependency`**: An immutable class that defines a relationship between two tasks.
    -   **Properties**: `predecessorTaskId`, `successorTaskId`, `type`, and an optional `lag` duration.

-   **`DependencyType` (enum)**: Defines the nature of the dependency, which affects how the dependency line is drawn and how scheduling logic might be applied.
    -   `finishToStart`: The most common type; the successor can't start until the predecessor finishes.
    -   `startToStart`: The successor can't start until the predecessor starts.
    -   `finishToFinish`: The successor can't finish until the predecessor finishes.
    -   `startToFinish`: The successor can't finish until the predecessor starts.
    -   `contained`: A special type where the successor must occur entirely within the predecessor's time frame. This is often rendered as a background highlight rather than a connecting line.

### `legacy_gantt_theme.dart`

-   **`LegacyGanttTheme`**: An immutable class that encapsulates all the visual styling options for the Gantt chart. This allows for consistent and centralized theme management.
    -   **Colors**: It defines a comprehensive set of colors for every part of the chart, including bars (`barColorPrimary`), backgrounds (`backgroundColor`), grid lines (`gridColor`), dependency lines (`dependencyLineColor`), and special states like conflicts (`conflictBarColor`) and dragging (`ghostBarColor`).
    -   **Text Styles**: `axisTextStyle` and `taskTextStyle` for styling the text on the timeline and inside task bars.
    -   **Dimensions**: `barHeightRatio` and `barCornerRadius` to control the appearance of the task bars.
    -   **Factory Constructor**: `LegacyGanttTheme.fromTheme(ThemeData)` provides a convenient way to create a default Gantt chart theme that is consistent with the overall application theme.

### `legacy_gantt_chart_colors.dart`

-   **`LegacyGanttChartColors`**: A simpler, immutable class that defines a basic color scheme for the chart. It appears to be a subset of the properties found in `LegacyGanttTheme` and may be used for simpler theming requirements or as a building block for a full theme.
