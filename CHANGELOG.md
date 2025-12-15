## 4.3.2

* **FIX**: Fix bulk actions performance in web browsers

## 4.3.1

* **FIX**: Fix bulk websocket sync executed sequentially

## 4.3.0

* **FEATURE**: Implement bulk update over websocket

## 4.2.0

* **FEATURE**: Implement web worker for offline database
* **FEATURE**: Implement message queuing for offline database

## 4.1.1

* **FIX**: Fix for an issue that caused a range error when calculating offsets on visible rows during data reset
* **EXAMPLE FIX**: Clear dependencies when resetting data

## 4.1.0

* **FEATURE**: Implemented the ability to select a group of tasks and move them in bulk
* **FEATURE**: Enhanced Axis Labels to be contextual:
    * The first visible tick now always displays the Date (e.g., "Oct 10") instead of just time, providing immediate context.
    * Ticks crossing into a new day also display the Date.
* **FEATURE**: Implemented Adaptive Axis Ticks logic to prevent label overlap when zooming out.
* **EXAMPLE FIX**: Fixed a visual "drift" issue where the visible date range would jump unexpectedly when resizing the window; the chart now correctly maintains the scroll offset.
* **FIX**: Fixed Axis Tick Alignment to respect local timezones, ensuring ticks land on "round" hours (e.g., 00:00, 12:00) rather than UTC-shifted offsets.
* **FIX**: Fixed Axis Header visibility issue by correcting the painter's Y-coordinate logic.

## 4.0.11

* **FIX**: Fix for an issue that caused dependency sync to fail

## 4.0.10

* **FIX**: Fix milestone sync

## 4.0.9

* **EXAMPLE FIX**: Fix for an issue that prevented milestones from populating in the example in local DB mode 

## 4.0.8

* **EXAMPLE FIX**: Fix for an issue that caused grid expansion states to be out of sync with their respective gantt bars on foreign clients

## 4.0.7

* **FIX**: Fix null check on null operator during startup when viewport has no dimensions yet

## 4.0.6

* **FIX**: Throttle cursor events to 100ms for performance enhancement

## 4.0.5

* **FIX**: More performance enhancement to panning and scrolling.

## 4.0.4

* **ERROR 404**: VERSION NOT FOUND!

## 4.0.3

* **FIX**: Fix axis timeline render performance at high zoom levels. Panning should now be stable and fluid at all zoom levels. 

## 4.0.2

* **ADJUSTMENT**: Adjust backend sync to perform in-band authentication, reducing token leakage potential

## 4.0.1

* **FIX**: Fix `last_synced` so that the backend can send only what is needed, not all time

## 4.0.0

* **FEATURE**: Added experimental support for CRDT. This still needs some polishing
* **FEATURE**: Cursor sync
* **FEATURE**: Ghost sync
* **NEW EXAMPLE**: Minimum Viable Example for gantt sync
* **EXAMPLE FEATURE**: Implemented backend connection in main UI example
* **EXAMPLE FEATURE**: Implemented a real backend URL for testing. Don't rely on this existing forever... It may not
* **EXAMPLE FEATURE**: Implement websocket gantt sync client
* **EXAMPLE FEATURE**: Added a toggle to the example application that demonstrates how to use CRDTs with the gantt chart
* **TESTS**: Implement more comprehensive testing

## 3.1.8

* **FIX**: Fix block function body lint

## 3.1.7

* **EXAMPLE FEATURE**: Implemented the ability to select a task in the gantt view and have the corresponding row in the grid view selected.
* **EXAMPLE FEATURE**: Added a new test file `select_gantt_selects_grid_row_test.dart` to demonstrate the issue where selecting a task in the gantt view does not select the corresponding row in the grid view.

## 3.1.6

* **EXAMPLE FIX**: Disable sorting in the example grid to prevent unexpected behavior.

## 3.1.5

* **EXAMPLE IMPROVEMENT**: Update example to use `legacy_tree_grid` instead of `legacy_gantt_grid`.

## 3.1.4

* **FIX**: More test adjustments. Enjoy some π!

## 3.1.3

* **FIX**: Remove some left over tests that are not needed which caused false-positive CI failures.

## 3.1.2

* **FIX**: Fix for an issue that caused interactions to be ignored on the gantt view for dragon drop, resize, and gantt bar action menu.

## 3.1.1

* **FIX**: Fix for an issue that caused labels to fall out of sync with gantt bars when expanding/collapsing rows.

## 3.1.0

* **FEATURE**: Added support for Milestones.
    * Introduced the isMilestone property to LegacyGanttTask.
    * Milestones are rendered as diamond-shaped indicators on the chart.
    * Milestones allow for zero-duration events (start equals end) to be clearly visible.
* **FEATURE**: Updated interaction logic to support dragging and selecting milestones.
* **EXAMPLE FEATURE**: Updated the example application to demonstrate how to define and style milestone tasks.

## 3.0.1

* **FIX**: Fix withOpacity usage
* **EXAMPLE IMPROVEMENT**: Add conflictIndicators to the JSON export

## 3.0.0

* **BREAKING**: Conflict indicators are now handled as a separate concern that is free from standard tasks.
    * **LegacyGanttChartWidget**: Added a `conflictIndicators` parameter. You should no longer merge conflict indicator tasks into the main `data` list.
    * **LegacyGanttController**: Added `conflictIndicators` getter and `setConflictIndicators()` method.
    * **BarsCollectionPainter**: Now requires a `conflictIndicators` list to be passed explicitly.
* **FEATURE**: Improved performance and state management by isolating conflict detection logic from task data updates.

## 2.11.0

* **FEATURE**: Added extended drag handles for selected tasks as a usability improvement for smaller screen sizes

## 2.10.3

* **FIX**: Fix changelog

## 2.10.2

* **FIX**: Fix for an issue that prevented dependency lines from populating on dependency creation, only appearing after adjusting times or other repaint. 

## 2.10.1

* **FIX**: Adjust pubignore to remove gif from package

## 2.10.0

* **FEATURE**: Added comprehensive keyboard navigation and accessibility support.
    * Added `focusedTaskId`, `onFocusChange`, and `onRowRequestVisible` properties to enable external state management of task focus.
    * The chart now internally handles `Tab` and `Shift+Tab` key presses to cycle focus between tasks.
    * A visual focus indicator (border) is now drawn around the task specified by `focusedTaskId`.
    * The chart now automatically scrolls (pans) vertically and horizontally to bring the focused task into view if it is off-screen.
    * Added `onRowRequestVisible` callback, allowing the parent application to react when a hidden task (e.g., in a collapsed row) is focused.
    
* **EXAMPLE FEATURE**: The example application was updated to fully demonstrate the new keyboard navigation features.
    * Clicking a task now sets it as the focused task, unifying mouse and keyboard selection.
    * The focused task state is now managed in the `GanttViewModel`, preserving focus across rebuilds (e.g., when expanding/collapsing rows).
    * Implemented the `onRowRequestVisible` callback to automatically expand parent rows when a hidden child task is focused via keyboard navigation.

## 2.9.4

* **FIX**: Fix for an issue that caused difficulty grabbing a drag handle to resize the task when task width is small.

## 2.9.3

* **EXAMPLE FIX**: Fix the auto-scaling axis timeline formatting in the example application (day/hour/minute, etc).

## 2.9.2

* **PERFORMANCE**: Optimized hit-testing in `LegacyGanttViewModel` by replacing the linear row scan with an O(log N) binary search, improving UI performance reliability during user interactions, particularly with large datasets.

## 2.9.1

* **FIX**: Add gif file to the repo that the `README.md` attempts to point to

## 2.9.0

* **FEATURE**: Add `weekendColor` property to allow customizing the weekend highlight color.

## 2.8.4

* **CHORE**: Update `provider` dependency
* **EXAMPLE FIX**: Fix for an issue that caused expand/collapse to be one frame behind

## 2.8.3

* **EXAMPLE FIX**: Render example in safe areas

## 2.8.2

* **DOC**: Added `doc/` dir including more information on usage and customization

## 2.8.1

* **FIX**: Fix a typo in the changelog

## 2.8.0

* **FEATURE**: Update hashing characteristics for more stable task drag/drop/resize
* **EXAMPLE FEATURE**: Added a minimal example as `main2.dart` for more barebones usage

## 2.7.0

* **FEATURE**: Added support for custom linear progress indicator height

## 2.6.1

* **FIX**: Fix for an issue that caused dependency lines to follow the shortest path, leading to unexpected visual appearance.
* **EXAMPLE FIX**: Fix for an issue that caused the example to show name on gantt bars instead of taskName. 

## 2.6.0

* **FEATURE**: Added `loadingIndicatorPosition` and `loadingIndicatorType` to customize the loading indicator. 

## 2.5.0

* **FEATURE**: Added the ability to populate blank rows (rows with no assignments/jobs/events populated)

## 2.4.0

* **FEATURE**: Added `noDataWidgetBuilder` to `LegacyGanttChartWidget` to allow developers to provide a custom widget to display when there are no tasks.
* **FIX**: Resolved an issue where the chart would show an infinite loading indicator when the dataset was empty. The chart now correctly displays the "No data to display" message or the custom widget provided via `noDataWidgetBuilder`.
* **EXAMPLE**: Added `0` to the person and jobs pickers in the example app to demonstrate the "no data" case.
* **EXAMPLE**: Introduced a loading state to the example app's view model to correctly handle the UI difference between "loading" and "empty".

## 2.3.5

* **DOC**: Improve in-code documentation for the example, and overall documentation for the project

## 2.3.4

* **EXAMPLE FEATURE**: Updated the example application for better UX and bug fixes.

## 2.3.3

* **EXAMPLE FEATURE**: Updated the example appliaction to add some bug fixes and additional functionalities for better UX and stability.

## 2.3.2

* **DOC**: Update README.md to add TOC and navigation

## 2.3.1

* **FIX**: Fix for an issue that prevented drag/drop and drag to resize for tasks.

## 2.3.0
* **FEATURE**: Added timelineAxisHeaderBuilder to LegacyGanttChartWidget. This powerful new feature allows developers to completely replace the default time axis header with a custom Flutter widget, granting full control over the layout, styling, and complexity of the timeline visualization (e.g., multi-level headers for Month/Year/Day).
* **FEATURE**: The height of the timeline axis is now dynamically controlled by the axisHeight property (or the default 27.0 if unset) to correctly size the custom header area.

* **EXAMPLE FEATURE**: The example app was updated to demonstrate the new functionality, allowing users to switch to a "Custom" timeline format that displays a two-level header (Month/Year over Day number) using the new builder.

## 2.2.1

* **FIX**: Dart format again

## 2.2.0

* **FEATURE**: Enhanced task hover tooltip to fully honor locale and display complete date/time information.
* **FEATURE** Added `timelineAxisLabelBuilder` to allow custom date formatting for the timeline.
* **EXAMPLE FEATURE**: Added locale selection to the example application for demonstration.

## 2.1.0

* **EXAMPLE FEATURE**: Add support for "showConflicts" in the Example application
* **EXAMPLE FEATURE**: Move control panel to left side in collapsible panel
* **FEATURE**: Add support for adjusting the drag handle size

## 2.0.0

* **BREAKING**: Extract legacy_timeline_scrubber into its own package

## 1.4.1

* **ADJUSTMENT**: Adjust example to use 16 jobs per person by default.

## 1.4.0

* **FEATURE**: Surface conflict indicators in timeline scrubber

## 1.3.5

* **FIX EXAMPLE**: Fix for an issue that caused the date selector to fail to impact the viewable date range

## 1.3.4

* **FIX**: Fix for an issue that caused conflict indicators to draw below their respective tasks
* **FIX**: Fix for an issue that caused tasks to fail to scroll vertically

## 1.3.3

* **CHORE**: Update example dependency on legacy_context_menu to ^2.1.2

## 1.3.2

* **FIX**: Fix dart formatting

## 1.3.1

* **DOC**: Update README.md to reflect the full feature set.

## 1.3.0

* **FEAT**: Add onTaskDelete callback to implement full support for CRUD operations.

## 1.2.1

* **FIX**: Fix for an issue that caused the gantt bars to reset when changing theme and when expanding a collapsed row. This fix is scoped to the example, please take note so that your implementation has the correct scrolling behavior.

## 1.2.0

* **FIX**: Fix for an issue that caused vertical scrolling to fail
* **FEAT**: Improve performance when rendering a large number of tasks
* **FEAT**: Update example to render over 10,000 tasks

## 1.1.0

* **FEAT**: Implemented dynamic viewbox zooming for the `LegacyGanttTimelineScrubber`. The scrubber now intelligently zooms in on the selected date range, providing a clearer and more intuitive navigation experience.
* **FEAT**: Added visual fade indicators to the edges of the timeline scrubber when zoomed in, making it clear that more of the timeline is available off-screen.
* **FEAT**: Added a "Reset Zoom" button to the timeline scrubber, allowing users to easily return to the full timeline view.

## 1.0.1

* **DOCS**: Improved README clarity by fixing formatting and better highlighting the unique `LegacyGanttTimelineScrubber` feature.
* **DOCS**: Added a `CONTRIBUTING.md` file with guidelines for developers, including code style rules. 

## 1.0.0

* **GENERAL AVAILABILITY**

## 0.4.7

* **FIX**: Dart formatting fix

## 0.4.6

* **FIX**: Add thorough documentation for all properties

## 0.4.5

* **FIX**: Don't ignore the example...

## 0.4.4

* **FIX**: Properly pubignore the example dir

## 0.4.3

* **FIX**: Formatting to dart's standards

## 0.4.2

* **FIX**: Add screenshot to pubspec.yaml

## 0.4.1

* **FIX**: Resolved a collision of options menu and end date drag handle on the example

## 0.4.0

* **FIX**: Corrected context menu implementation on task bars to support both desktop right-click and mobile tap interactions.
* **FIX**: Resolved an issue where the context sub-menu was not displaying correctly by integrating with the `legacy_context_menu` package properly.
* **FEAT**: Added interactive dependency creation. Users can now drag from handles on task bars to create new dependencies between tasks.
* **FEAT**: Added support for more dependency types: Start-to-Start (SS), Finish-to-Finish (FF), and Start-to-Finish (SF).
* **FEAT**: Implemented visual connectors for the new dependency types.

## 0.3.0

* **EXAMPLE BREAKING**: The example application has been significantly refactored to use an MVVM pattern with a `GanttViewModel`. State management logic has been moved out of the `_GanttViewState`, and the `GanttGrid` widget has been updated. Users who based their implementation on the previous example will need to adapt to this new architecture.

* **FEAT**: Added support for task dependencies (finish-to-start, contained).
* **FEAT**: Added ability to create new tasks by clicking on empty space in the chart.
* **FEAT**: Added an options menu to task bars for actions like copy and delete.
* **FEAT**: Added theming options for dependency lines and other new UI elements.
* **FEAT**: Refactored the example application to use the MVVM pattern for better state management.
* **FEAT**: Added the ability to dynamically add new resources and line items in the example app.

## 0.2.0

* **FEAT**: Implemented dynamic time axis graduations that adjust based on the zoom level, from weeks down to minutes.
* **FEAT**: Added a resizable divider to the example app, allowing users to adjust the width of the data grid.

## 0.1.0

* **FEAT**: Added a tooltip to show start and end dates when dragging a task.
* **FEAT**: Added `resizeTooltipBackgroundColor` and `resizeTooltipFontColor` to allow customization of the drag/resize tooltip.

## 0.0.10

* Improve example quality

## 0.0.9

* Add example to github actions

## 0.0.8

* Fix if... statements not enclosed in curly braces

## 0.0.7

* Dart format
* Update `analysis_options.yaml`

## 0.0.6

* Update README.md to improve clarity

## 0.0.5

* Update URL of screenshot for compatibility with pub.dev

## 0.0.4

* Update README.md to include a screenshot

## 0.0.3

* Live update summary child background

## 0.0.2

* **FEAT**: Added a comprehensive example application to demonstrate features like external scrolling, theming, and custom builders.
* **FIX**: Corrected rendering failures by replacing an incorrect color method with the correct `withOpacity`, resolving blank screen issues and linter warnings.

## 0.0.1

* Initial release of the legacy_gantt_chart package.
* Features include interactive task dragging and resizing, dynamic data loading, and theming.