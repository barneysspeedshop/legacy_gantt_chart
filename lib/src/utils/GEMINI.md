# Gemini Code Generation Documentation

This document provides an overview of the utility classes located in the `lib/src/utils/` directory.

## `legacy_gantt_conflict_detector.dart`

This file contains the `LegacyGanttConflictDetector`, a utility class designed to identify and report scheduling conflicts between tasks.

### `LegacyGanttConflictDetector`

This class encapsulates the logic for finding overlapping time intervals among a list of tasks. Its primary goal is to produce a list of "conflict indicator" tasks that can be visually rendered on the Gantt chart to highlight where conflicts occur.

#### How It Works

The main logic is in the `run` method, which performs the following steps:

1.  **Grouping**: It accepts a list of all tasks and a `taskGrouper` function. This function is key, as it defines which tasks should be compared against each other. For example, it could group tasks by an assigned resource, ensuring that one person isn't scheduled for two tasks at the same time. Tasks that don't belong to a group (i.e., the grouper returns `null`) are ignored.

2.  **Finding Raw Overlaps**: Within each group, the detector iterates through all pairs of tasks to find any that overlap in time.
    -   It correctly handles tasks that are defined by `segments`. It compares every segment of one task against every segment of another to find the precise period of overlap.

3.  **Creating Indicators for Child Tasks**: For each raw overlap found, it creates two `LegacyGanttTask` objects—one for each of the conflicting tasks. These new tasks are marked with `isOverlapIndicator: true` and cover the exact time range of the conflict. This allows the UI to draw a conflict marker on both of the original tasks.

4.  **Merging Conflict Intervals**: If multiple tasks overlap in complex ways (e.g., A overlaps with B, and B overlaps with C), this can result in many small, overlapping conflict indicators. To simplify this, the detector merges all the raw overlap intervals within a group into a minimal set of continuous conflict periods.

5.  **Creating Indicators for Summary Tasks**: After identifying the merged conflict periods, the detector checks if any of these conflicts fall within the time range of a `summary` task in the same group. If they do, it creates additional conflict indicators that are specifically placed on top of the summary task bar, providing a high-level view of the conflict.

The final output of the `run` method is a flat list of these `LegacyGanttTask` conflict indicators, which can then be added to the main list of tasks for rendering.
