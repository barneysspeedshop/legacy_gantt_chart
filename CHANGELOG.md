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