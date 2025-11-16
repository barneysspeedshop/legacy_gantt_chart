import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart' as scrubber;
import '../main.dart';

import '../data/models.dart';
import '../services/gantt_schedule_service.dart';
import '../ui/dialogs/create_task_dialog.dart';
import '../ui/gantt_grid_data.dart';

/// An enum to manage the different theme presets demonstrated in the example.
enum ThemePreset {
  standard,
  forest,
  midnight,
}

class GanttViewModel extends ChangeNotifier {
  // --- Core Data State ---
  /// The main list of tasks displayed on the Gantt chart, including regular tasks,
  /// summary tasks, highlights, and conflict indicators.
  List<LegacyGanttTask> _ganttTasks = [];

  /// The list of dependencies between tasks.
  List<LegacyGanttTaskDependency> _dependencies = [];

  /// The hierarchical data structure for the grid on the left side of the chart.
  List<GanttGridData> _gridData = [];

  /// A map that stores the maximum number of overlapping tasks for each row,
  /// used to calculate the row's total height.
  Map<String, int> _rowMaxStackDepth = {};

  /// The original API response from the service. This is kept to allow for
  /// reprocessing data (e.g., when a task is edited) and for exporting the original data structure.
  GanttResponse? _apiResponse;

  /// A map for quick lookups of original event data by task ID, used for tooltips.
  Map<String, GanttEventData> _eventMap = {};

  // --- UI and Feature Control State ---
  /// The currently selected theme preset.
  ThemePreset _selectedTheme = ThemePreset.standard;

  /// Flags to enable or disable interactive features of the Gantt chart.
  bool _dragAndDropEnabled = true;
  bool _resizeEnabled = true;
  bool _createTasksEnabled = true;
  bool _dependencyCreationEnabled = true;
  bool _showConflicts = true;
  bool _showEmptyParentRows = false;
  bool _showDependencies = true;

  /// The width of the resize handles on the edges of task bars.
  double _resizeHandleWidth = 10.0;

  /// The height of a single task lane within a row.
  final double rowHeight = 27.0;

  /// The currently selected locale for date and time formatting.
  String _selectedLocale = 'en_US';

  /// The format for labels on the timeline axis.
  TimelineAxisFormat _selectedAxisFormat = TimelineAxisFormat.dayOfMonth;

  /// A function to format the date in the resize tooltip. This is updated by the view.
  String Function(DateTime)? _resizeTooltipDateFormat;

  /// The type of progress indicator to show during loading.
  GanttLoadingIndicatorType _loadingIndicatorType = GanttLoadingIndicatorType.circular;

  /// The position of the linear progress indicator.
  GanttLoadingIndicatorPosition _loadingIndicatorPosition = GanttLoadingIndicatorPosition.top;

  // --- Data Generation Parameters ---
  /// The start date for fetching schedule data.
  DateTime _startDate = DateTime.now();

  /// Default start and end times used when creating new tasks.
  final TimeOfDay _defaultStartTime = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay _defaultEndTime = const TimeOfDay(hour: 17, minute: 0);

  /// The number of days to fetch data for.
  int _range = 14; // Default range for data fetching

  /// The number of "persons" (parent rows) to generate in the sample data.
  int _personCount = 10;

  /// The number of "jobs" (child rows) to generate in the sample data.
  int _jobCount = 16;

  // --- Date Range and Scrolling State ---
  /// The start and end dates of the entire dataset.
  DateTime? _totalStartDate;
  DateTime? _totalEndDate;

  /// The start and end dates of the currently visible window in the Gantt chart.
  DateTime? _visibleStartDate;
  DateTime? _visibleEndDate;

  /// Padding added to the total date range to provide scrollable space at the edges of the timeline.
  final Duration _ganttStartPadding = const Duration(days: 7);
  final Duration _ganttEndPadding = const Duration(days: 7);

  /// Scroll controllers to synchronize the vertical scroll of the grid and chart,
  /// and to manage the horizontal scroll of the chart.
  final ScrollController _scrollController = ScrollController();
  final ScrollController _ganttHorizontalScrollController = ScrollController();

  /// A flag to prevent a feedback loop between the timeline scrubber and the horizontal scroll controller.
  bool _isScrubberUpdating = false; // Prevents feedback loop between scroller and scrubber

  /// A flag to indicate when data is being fetched.
  bool _isLoading = true;

  OverlayEntry? _tooltipOverlay;
  String? _hoveredTaskId;

  final GanttScheduleService _scheduleService = GanttScheduleService();
  GanttResponse? get apiResponse => _apiResponse;

  double? _gridWidth;
  double? _controlPanelWidth = 300.0;

  // Getters for the UI
  List<LegacyGanttTask> get ganttTasks => _ganttTasks;
  String Function(DateTime)? get resizeTooltipDateFormat => _resizeTooltipDateFormat;
  List<LegacyGanttTaskDependency> get dependencies => _showDependencies ? _dependencies : [];
  List<GanttGridData> get gridData => _gridData;
  ThemePreset get selectedTheme => _selectedTheme;
  bool get dragAndDropEnabled => _dragAndDropEnabled;
  bool get resizeEnabled => _resizeEnabled;
  bool get createTasksEnabled => _createTasksEnabled;
  bool get dependencyCreationEnabled => _dependencyCreationEnabled;
  bool get showConflicts => _showConflicts;
  bool get showEmptyParentRows => _showEmptyParentRows;
  bool get showDependencies => _showDependencies;
  double get resizeHandleWidth => _resizeHandleWidth;
  DateTime get startDate => _startDate;
  GanttLoadingIndicatorType get loadingIndicatorType => _loadingIndicatorType;
  GanttLoadingIndicatorPosition get loadingIndicatorPosition => _loadingIndicatorPosition;
  TimeOfDay get defaultStartTime => _defaultStartTime;
  TimeOfDay get defaultEndTime => _defaultEndTime;
  int get range => _range;
  int get personCount => _personCount;
  int get jobCount => _jobCount;
  DateTime? get totalStartDate => _totalStartDate;
  DateTime? get totalEndDate => _totalEndDate;
  DateTime? get visibleStartDate => _visibleStartDate;
  DateTime? get visibleEndDate => _visibleEndDate;
  bool get isLoading => _isLoading;

  /// The effective total date range, including padding. This is passed to the Gantt chart widget
  /// to define the full scrollable width of the timeline.
  DateTime? get effectiveTotalStartDate => _totalStartDate?.subtract(_ganttStartPadding);
  DateTime? get effectiveTotalEndDate => _totalEndDate?.add(_ganttEndPadding);

  /// A map of row IDs to their maximum task stack depth, used by the Gantt chart widget.
  Map<String, int> get rowMaxStackDepth => _rowMaxStackDepth;
  ScrollController get scrollController => _scrollController;
  ScrollController get ganttHorizontalScrollController => _ganttHorizontalScrollController;
  double? get gridWidth => _gridWidth;
  double? get controlPanelWidth => _controlPanelWidth;

  List<GanttGridData> get visibleGridData => _gridData;

  /// Calculates the list of `LegacyGanttRow`s that should be visible based on the
  /// expanded/collapsed state of the parent items in the `gridData`.
  /// This is passed to the `LegacyGanttChartWidget` to determine which rows to render.
  List<LegacyGanttRow> get visibleGanttRows {
    final List<LegacyGanttRow> rows = [];
    for (final item in visibleGridData) {
      rows.add(LegacyGanttRow(id: item.id));
      if (item.isParent && item.isExpanded) {
        rows.addAll(item.children.map((child) => LegacyGanttRow(id: child.id)));
      }
    }
    return rows;
  }

  /// Constructor initializes the locale and sets up a listener for horizontal scrolling.
  GanttViewModel({String? initialLocale}) {
    if (initialLocale != null) {
      _selectedLocale = initialLocale;
    }
    _ganttHorizontalScrollController.addListener(_onGanttScroll);
    fetchScheduleData();
  }

  @override
  void dispose() {
    _removeTooltip();
    _scrollController.dispose();
    _ganttHorizontalScrollController.removeListener(_onGanttScroll);
    _ganttHorizontalScrollController.dispose();
    super.dispose();
  }

  // --- Setters for UI State ---
  void setGridWidth(double? value) {
    _gridWidth = value;
    notifyListeners();
  }

  void setControlPanelWidth(double? value) {
    if (_controlPanelWidth == value) return;
    _controlPanelWidth = value;
    notifyListeners();
  }

  void setSelectedTheme(ThemePreset theme) {
    _selectedTheme = theme;
    notifyListeners();
  }

  void setDragAndDropEnabled(bool value) {
    _dragAndDropEnabled = value;
    notifyListeners();
  }

  void setResizeEnabled(bool value) {
    _resizeEnabled = value;
    notifyListeners();
  }

  void setCreateTasksEnabled(bool value) {
    _createTasksEnabled = value;
    notifyListeners();
  }

  void setDependencyCreationEnabled(bool value) {
    _dependencyCreationEnabled = value;
    notifyListeners();
  }

  void setShowDependencies(bool value) {
    if (_showDependencies == value) return;
    _showDependencies = value;
    notifyListeners();
  }

  void setShowConflicts(bool value) {
    _showConflicts = value;
    // Re-run the task stacking calculation with the new conflict visibility setting.
    // This ensures that conflict indicators are added or removed correctly.
    final (recalculatedTasks, newMaxDepth) =
        _scheduleService.publicCalculateTaskStacking(_ganttTasks, _apiResponse!, showConflicts: _showConflicts);
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
  }

  Future<void> setShowEmptyParentRows(bool value) async {
    if (_showEmptyParentRows == value) return;
    _showEmptyParentRows = value;
    await _reprocessDataFromApiResponse();
  }

  void setResizeHandleWidth(double value) {
    if (_resizeHandleWidth == value) return;
    _resizeHandleWidth = value;
    notifyListeners();
  }

  void setPersonCount(int value) {
    if (_personCount == value) return;
    _personCount = value;
    fetchScheduleData();
    notifyListeners();
  }

  void setJobCount(int value) {
    if (_jobCount == value) return;
    _jobCount = value;
    fetchScheduleData();
    notifyListeners();
  }

  void setLoadingIndicatorType(GanttLoadingIndicatorType value) {
    if (_loadingIndicatorType == value) return;
    _loadingIndicatorType = value;
    notifyListeners();
  }

  void setLoadingIndicatorPosition(GanttLoadingIndicatorPosition value) {
    if (_loadingIndicatorPosition == value) return;
    _loadingIndicatorPosition = value;
    notifyListeners();
  }

  void setSelectedLocale(String value) {
    if (_selectedLocale == value) return;
    _selectedLocale = value;
    notifyListeners();
  }

  void setSelectedAxisFormat(TimelineAxisFormat value) {
    if (_selectedAxisFormat == value) return;
    _selectedAxisFormat = value;
    notifyListeners();
  }

  void updateResizeTooltipDateFormat(String Function(DateTime)? newFormat) {
    if (_resizeTooltipDateFormat != newFormat) {
      _resizeTooltipDateFormat = newFormat;
      notifyListeners();
    }
  }

  /// Fetches new schedule data from the `GanttScheduleService` and processes it
  /// into the data structures required by the UI (`_ganttTasks`, `_gridData`, etc.).
  /// This method is called on initial load and whenever data generation parameters change.
  Future<void> fetchScheduleData() async {
    _ganttTasks = [];
    _isLoading = true;
    _dependencies = [];
    _gridData = [];
    _rowMaxStackDepth = {};
    _totalStartDate = null;
    _totalEndDate = null;
    _visibleStartDate = null;
    _visibleEndDate = null;
    notifyListeners();

    try {
      final processedData = await _scheduleService.fetchAndProcessSchedule(
        startDate: _startDate,
        range: _range,
        personCount: _personCount,
        jobCount: _jobCount,
      );

      // --- Create sample dependencies for demonstration ---
      final newDependencies = <LegacyGanttTaskDependency>[];
      final ganttTasks = processedData.ganttTasks;

      // Find a suitable task to be the "successor" for all contained dependencies.
      // For this visual effect, the successor doesn't matter, only the predecessor.
      final successorForContainedDemo = ganttTasks.firstWhere(
        (t) => !t.isSummary && !t.isTimeRangeHighlight,
        orElse: () => ganttTasks.first, // Fallback
      );

      // 1. For every summary task, create a 'contained' dependency.
      for (final task in ganttTasks) {
        if (task.isSummary) {
          newDependencies.add(
            LegacyGanttTaskDependency(
              predecessorTaskId: task.id,
              successorTaskId: successorForContainedDemo.id, // The successor is arbitrary for the background to draw
              type: DependencyType.contained,
            ),
          );
        }
      }

      // 2. Find two tasks to link with a 'finishToStart' dependency for demonstration.
      final validTasksForDependency = ganttTasks
          .where((task) => !task.isSummary && !task.isTimeRangeHighlight && !task.isOverlapIndicator)
          .toList();

      if (validTasksForDependency.length > 1) {
        // Sort by start time, then by ID for a stable sort.
        validTasksForDependency.sort((a, b) {
          final startCompare = a.start.compareTo(b.start);
          if (startCompare != 0) return startCompare;
          return a.id.compareTo(b.id);
        });

        // Create a dependency between the first two tasks in the sorted list.
        newDependencies.add(
          LegacyGanttTaskDependency(
            predecessorTaskId: validTasksForDependency[0].id,
            successorTaskId: validTasksForDependency[1].id,
          ),
        );
      }

      _ganttTasks = processedData.ganttTasks;
      _dependencies = newDependencies;
      _gridData = processedData.gridData;
      _rowMaxStackDepth = processedData.rowMaxStackDepth;
      _eventMap = processedData.eventMap;
      _apiResponse = processedData.apiResponse;

      // Calculate total date range based on all tasks
      if (_ganttTasks.isNotEmpty) {
        DateTime minStart = _ganttTasks.first.start;
        DateTime maxEnd = _ganttTasks.first.end;
        for (final task in _ganttTasks) {
          if (task.start.isBefore(minStart)) {
            minStart = task.start;
          }
          if (task.end.isAfter(maxEnd)) {
            maxEnd = task.end;
          }
        }
        _totalStartDate = minStart;
        _totalEndDate = maxEnd;
      } else {
        _totalStartDate = _startDate;
        _totalEndDate = _startDate.add(Duration(days: _range));
      }

      _isLoading = false;

      _visibleStartDate = effectiveTotalStartDate;
      _visibleEndDate = effectiveTotalEndDate;

      notifyListeners();

      // After the UI has been built with the new data, scroll the Gantt chart
      // to the initial visible window.
      WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialScroll());
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Error fetching gantt schedule data: $e');
      // Consider showing an error message to the user
    }
  }

  // Helper to parse hex color strings
  Color _parseColorHex(String? hexString, Color defaultColor) {
    if (hexString == null || hexString.isEmpty) {
      return defaultColor;
    }
    String cleanHex = hexString.startsWith('#') ? hexString.substring(1) : hexString;
    if (cleanHex.length == 3) {
      cleanHex = cleanHex.split('').map((char) => char * 2).join();
    }
    if (cleanHex.length == 6) {
      try {
        return Color(int.parse(cleanHex, radix: 16) + 0xFF000000);
      } catch (e) {
        debugPrint('Error parsing hex color "$hexString": $e');
        return defaultColor;
      }
    }
    return defaultColor;
  }

  void onRangeChange(int? newRange) {
    if (newRange != null) {
      _range = newRange;
      notifyListeners();
      fetchScheduleData(); // Re-fetch data for new range
    }
  }

  Future<void> onSelectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (pickedDate != null && pickedDate != _startDate) {
      _startDate = pickedDate;
      notifyListeners();
      fetchScheduleData(); // Re-fetch data for new date
    }
  }

  /// Callback from the `LegacyGanttTimelineScrubber`. This is triggered when the user
  /// drags the window on the scrubber.
  ///
  /// It updates the `_visibleStartDate` and `_visibleEndDate`, which causes the
  /// main Gantt chart to rebuild. It then programmatically scrolls the chart to the new position.
  void onScrubberWindowChanged(DateTime newStart, DateTime newEnd, [scrubber.ScrubberHandle? handle]) {
    // Set a flag to prevent the scroll listener from firing and causing a loop.
    _isScrubberUpdating = true;

    // Update the state with the new visible window from the scrubber.
    // This will trigger a rebuild, which updates the Gantt chart's gridMin/gridMax
    // and recalculates its total width.
    if (handle == scrubber.ScrubberHandle.left) {
      // Left handle adjusts the start date
      // When resizing from the left, only the start date changes.
      _visibleStartDate = newStart;
    } else if (handle == scrubber.ScrubberHandle.right) {
      // Right handle adjusts the end date
      // When resizing from the right, only the end date changes.
      _visibleEndDate = newEnd;
    } else {
      // If the whole window is dragged (or handle is null/body), update both.
      _visibleStartDate = newStart;
      _visibleEndDate = newEnd;
    }

    notifyListeners();

    // After the UI has rebuilt with the new dimensions, programmatically
    // scroll the Gantt chart to the correct position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (effectiveTotalStartDate != null &&
          effectiveTotalEndDate != null &&
          _ganttHorizontalScrollController.hasClients) {
        final totalDataDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
        if (totalDataDuration <= 0) return;

        final position = _ganttHorizontalScrollController.position;
        final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
        if (totalGanttWidth > 0) {
          // Determine which date to use as the anchor for scrolling.
          // If resizing from the right, we anchor to the existing start date.
          // Otherwise, we anchor to the new start date from the scrubber.
          final DateTime anchorDate;
          if (handle == scrubber.ScrubberHandle.right) {
            // Keep the left side of the viewport fixed.
            anchorDate = _visibleStartDate!;
          } else {
            // Move the viewport based on the new start date.
            anchorDate = newStart;
          }

          final startOffsetMs = anchorDate.difference(effectiveTotalStartDate!).inMilliseconds;
          final newScrollOffset = (startOffsetMs / totalDataDuration) * totalGanttWidth;

          _ganttHorizontalScrollController.jumpTo(newScrollOffset.clamp(0.0, position.maxScrollExtent));
        }
      }
      // Reset the flag after the update is complete.
      _isScrubberUpdating = false;
    });
  }

  /// Listener for the `_ganttHorizontalScrollController`. This is triggered when the
  /// user scrolls the main Gantt chart horizontally.
  ///
  /// It calculates the new visible date window based on the scroll offset and updates
  /// the state, which in turn updates the position of the window on the timeline scrubber.
  void _onGanttScroll() {
    // If the scroll is happening because of the scrubber, do nothing.
    if (_isScrubberUpdating || effectiveTotalStartDate == null || effectiveTotalEndDate == null) return;

    final position = _ganttHorizontalScrollController.position;
    final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
    if (totalGanttWidth <= 0) return;

    final totalDataDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    if (totalDataDuration <= 0) return;
    final startOffsetMs = (position.pixels / totalGanttWidth) * totalDataDuration;
    final newVisibleStart = effectiveTotalStartDate!.add(Duration(milliseconds: startOffsetMs.round()));
    final newVisibleEnd = newVisibleStart.add(_visibleEndDate!.difference(_visibleStartDate!));

    // Only update if there's a significant change to prevent excessive rebuilds
    if (newVisibleStart != _visibleStartDate || newVisibleEnd != _visibleEndDate) {
      _visibleStartDate = newVisibleStart;
      _visibleEndDate = newVisibleEnd;
      notifyListeners();
    }
  }

  /// Sets the initial horizontal scroll position of the Gantt chart after data
  /// has been loaded and the layout has been built for the first time.
  void _setInitialScroll() {
    if (!_ganttHorizontalScrollController.hasClients ||
        effectiveTotalStartDate == null ||
        effectiveTotalEndDate == null ||
        _visibleStartDate == null) {
      return;
    }

    final totalDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    if (totalDuration <= 0) return;

    final position = _ganttHorizontalScrollController.position;
    final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
    if (totalGanttWidth <= 0) return;

    final startOffsetMs = _visibleStartDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    final newScrollOffset = (startOffsetMs / totalDuration) * totalGanttWidth;
    _ganttHorizontalScrollController.jumpTo(newScrollOffset.clamp(0.0, position.maxScrollExtent));
  }

  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  /// Displays a custom tooltip when the user hovers over a task.
  /// It uses an `OverlayEntry` to position the tooltip near the cursor.
  void showTooltip(BuildContext context, LegacyGanttTask task, Offset globalPosition) {
    _removeTooltip(); // Remove previous tooltip first

    final overlay = Overlay.of(context);

    // --- "Day X" Calculation ---
    int? dayNumber;

    // "Day X" is only for child shifts, not summary bars.
    if (!task.isSummary && task.originalId != null) {
      final childEvent = _eventMap[task.originalId];
      if (childEvent?.resourceId != null) {
        final parentEvent = _eventMap[childEvent!.resourceId];
        if (parentEvent?.utcStartDate != null) {
          final parentStartDate = DateTime.tryParse(parentEvent!.utcStartDate!);
          if (parentStartDate != null) {
            dayNumber = task.start.toUtc().difference(parentStartDate.toUtc()).inDays + 1;
          }
        }
      }
    }

    _tooltipOverlay = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        // Get status info from the original event data.
        final event = _eventMap[task.originalId];
        final statusText = event?.referenceData?.taskName;
        // The color from the API doesn't include '#', so we add it for parsing.
        final taskColorHex = event?.referenceData?.taskColor;
        final taskColor = taskColorHex != null ? _parseColorHex('#$taskColorHex', Colors.transparent) : null;
        final textStyle = theme.textTheme.bodySmall;
        final boldTextStyle = textStyle?.copyWith(fontWeight: FontWeight.bold);

        // Position the tooltip near the cursor
        return Positioned(
          left: globalPosition.dx + 15, // Offset from cursor
          top: globalPosition.dy + 15,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(4),
            color: Colors.transparent, // Make Material transparent to show Container's decor
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480), // Style: max-width
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Important for Column in Overlay
                children: [
                  if (dayNumber != null) Text('Day $dayNumber', style: boldTextStyle),
                  Text(task.name ?? '', style: boldTextStyle),
                  if (statusText != null && taskColor != null && taskColor != Colors.transparent)
                    Container(
                      margin: const EdgeInsets.only(top: 2, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: taskColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: textStyle?.copyWith(
                          color: ThemeData.estimateBrightnessForColor(taskColor) == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text('Start: ${_getTooltipDateFormat()(task.start.toLocal())}', style: textStyle),
                  Text('End: ${_getTooltipDateFormat()(task.end.toLocal())}', style: textStyle),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_tooltipOverlay!);
    _hoveredTaskId = task.id;
    notifyListeners();
  }

  /// A callback from the Gantt chart widget when the user's cursor moves over a task.
  void onTaskHover(LegacyGanttTask? task, BuildContext context, Offset globalPosition) {
    if (_hoveredTaskId == task?.id) return;
    _hoveredTaskId = task?.id;
    _removeTooltip();
    if (task != null && !task.isTimeRangeHighlight) {
      // Don't show tooltip for highlights
      showTooltip(context, task, globalPosition);
    }
    notifyListeners();
  }

  /// A helper method to update the task list and stack depth map, then notify listeners.
  void _updateTasksAndStacking(List<LegacyGanttTask> tasks, Map<String, int> maxDepth) {
    _ganttTasks = tasks;
    _rowMaxStackDepth = maxDepth;
    notifyListeners();
  }

  /// A callback from the Gantt chart widget when a task has been moved or resized by the user.
  /// It updates the task in the local list and then recalculates the stacking for all tasks.
  void handleTaskUpdate(LegacyGanttTask task, DateTime newStart, DateTime newEnd) {
    final newTasks = List<LegacyGanttTask>.from(_ganttTasks);
    final index = newTasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      newTasks[index] = newTasks[index].copyWith(start: newStart, end: newEnd);
      final (recalculatedTasks, newMaxDepth) =
          _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
    }
  }

  /// A callback from the Gantt chart widget when the user clicks on an empty
  /// space in a row. This method shows a dialog to create a new task.
  void handleEmptySpaceClick(BuildContext context, String rowId, DateTime time) {
    if (!_createTasksEnabled) return;

    // Find the resource name from the grid data.
    String resourceName = 'Unknown Resource';
    for (final parent in _gridData) {
      if (parent.id == rowId) {
        resourceName = parent.name;
        break;
      }
      for (final child in parent.children) {
        if (child.id == rowId) {
          resourceName = '${parent.name} - ${child.name}';
          break;
        }
      }
    }

    showDialog<void>(
      context: context,
      builder: (context) => CreateTaskAlertDialog(
        initialTime: time,
        resourceName: resourceName,
        rowId: rowId,
        defaultStartTime: _defaultStartTime,
        defaultEndTime: _defaultEndTime,
        onCreate: (newTask) {
          _addNewTask(newTask);
          Navigator.pop(context);
        },
      ),
    );
  }

  /// A generic helper to show a dialog with a single text input field.
  Future<String?> _showTextInputDialog({
    required BuildContext context,
    required String title,
    required String label,
    String? initialValue,
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('textInputDialog'),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Handles the "Add Contact" action from the grid UI.
  Future<void> addContact(BuildContext context) async {
    final newContactName = await _showTextInputDialog(
      context: context,
      title: 'Add New Contact',
      label: 'Contact Name',
    );

    if (newContactName != null && newContactName.isNotEmpty) {
      final newResourceId = 'person_${DateTime.now().millisecondsSinceEpoch}';

      // Create new data objects
      final newResource = GanttResourceData(
        id: newResourceId,
        name: newContactName,
        taskName: 'Summary for $newContactName', // Ensure taskName is set
        children: [],
      );
      final newGridItem =
          GanttGridData(id: newResourceId, name: newContactName, isParent: true, isExpanded: true, children: []);

      // Update the mock API response and the grid data
      _apiResponse?.resourcesData.add(newResource);
      _gridData.add(newGridItem);
      notifyListeners();
    }
  }

  /// Handles the "Add Line Item" action from the grid UI.
  Future<void> addLineItem(BuildContext context, String parentId) async {
    final parentGridItem = _gridData.firstWhere((g) => g.id == parentId);
    final newLineItemName = await _showTextInputDialog(
      context: context,
      title: 'Add New Line Item for ${parentGridItem.name}',
      label: 'Line Item Name',
    );

    if (newLineItemName != null && newLineItemName.isNotEmpty) {
      final newJobId = 'job_${DateTime.now().millisecondsSinceEpoch}';

      // Create new data objects
      final newJob = GanttJobData(
          id: newJobId, name: newLineItemName, taskName: null, status: 'New', taskColor: '9E9E9E', completion: 0.0);
      final newGridItem = GanttGridData.fromJob(newJob);

      // Find the parent in both data structures and add the new child
      final parentResource = _apiResponse?.resourcesData.firstWhere((r) => r.id == parentId);
      parentResource?.children.add(newJob);
      parentGridItem.children.add(newGridItem);
      notifyListeners();
    }
  }

  /// Toggles whether a parent row is rendered as a summary task.
  ///
  /// If `isSummary` is true, it either finds and marks an existing task as a summary
  /// or creates a new summary task that spans the duration of its children.
  void setParentTaskType(String parentId, bool isSummary) {
    if (_apiResponse == null) return;

    List<LegacyGanttTask> nextTasks = _ganttTasks;
    List<LegacyGanttTaskDependency> nextDependencies = _dependencies;

    final parentTaskIndex = nextTasks.indexWhere(
      (t) => t.rowId == parentId && !t.isTimeRangeHighlight,
    );

    if (isSummary) {
      if (parentTaskIndex != -1) {
        final existingTask = nextTasks[parentTaskIndex];
        // Create a new list with the modified task.
        nextTasks = List.from(nextTasks)..[parentTaskIndex] = existingTask.copyWith(isSummary: true);
      } else {
        final parentGridItem = _gridData.firstWhere((g) => g.id == parentId);
        final childIds = parentGridItem.children.map((c) => c.id).toSet();
        final childrenTasks = nextTasks.where((t) => childIds.contains(t.rowId)).toList();

        if (childrenTasks.isNotEmpty) {
          DateTime minStart = childrenTasks.first.start;
          DateTime maxEnd = childrenTasks.first.end;
          for (final task in childrenTasks) {
            if (task.start.isBefore(minStart)) {
              minStart = task.start;
            }
            if (task.end.isAfter(maxEnd)) {
              maxEnd = task.end;
            }
          }

          final newTask = LegacyGanttTask(
            id: 'summary-task-$parentId',
            rowId: parentId,
            name: parentGridItem.name,
            start: minStart,
            end: maxEnd,
            isSummary: true,
          );
          nextTasks = [...nextTasks, newTask];
        }
      }

      final hasDependency =
          nextDependencies.any((d) => d.predecessorTaskId == parentId && d.type == DependencyType.contained);
      if (!hasDependency && nextTasks.isNotEmpty) {
        final successorForContainedDemo = nextTasks.firstWhere(
          (t) => !t.isSummary && !t.isTimeRangeHighlight,
          orElse: () => nextTasks.first,
        );
        final newDependency = LegacyGanttTaskDependency(
          predecessorTaskId: parentId,
          successorTaskId: successorForContainedDemo.id,
          type: DependencyType.contained,
        );
        nextDependencies = [...nextDependencies, newDependency];
      }
    } else {
      if (parentTaskIndex != -1) {
        final existingTask = nextTasks[parentTaskIndex];
        if (existingTask.id.startsWith('summary-task-')) {
          nextTasks = nextTasks.where((t) => t.id != existingTask.id).toList();
        } else {
          nextTasks = List.from(nextTasks)..[parentTaskIndex] = existingTask.copyWith(isSummary: false);
        }
      }
      nextDependencies = nextDependencies
          .where((d) => !(d.predecessorTaskId == parentId && d.type == DependencyType.contained))
          .toList();
    }

    final (recalculatedTasks, newMaxDepth) =
        _scheduleService.publicCalculateTaskStacking(nextTasks, _apiResponse!, showConflicts: _showConflicts);
    _dependencies = nextDependencies;
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
  }

  /// Adds a new task to the list and recalculates stacking.
  void _addNewTask(LegacyGanttTask newTask) {
    final newTasks = [..._ganttTasks, newTask];
    if (_apiResponse != null) {
      final (recalculatedTasks, newMaxDepth) =
          _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
    }
  }

  /// Calculates the total width of the Gantt chart's content area based on the
  /// total duration of all data and the duration of the currently visible window.
  /// This determines the scrollable width of the chart.
  double calculateGanttWidth(double screenWidth) {
    if (effectiveTotalStartDate == null ||
        effectiveTotalEndDate == null ||
        _visibleStartDate == null ||
        _visibleEndDate == null) {
      return screenWidth;
    }
    final totalDuration = effectiveTotalEndDate!.difference(effectiveTotalStartDate!).inMilliseconds;
    final visibleDuration = _visibleEndDate!.difference(_visibleStartDate!).inMilliseconds;

    if (visibleDuration <= 0) return screenWidth;

    final zoomFactor = totalDuration / visibleDuration;
    return screenWidth * zoomFactor;
  }

  /// Toggles the expanded/collapsed state of a parent row in the grid.
  void toggleExpansion(String id) {
    final item = _gridData.firstWhere((element) => element.id == id);
    item.isExpanded = !item.isExpanded;
    notifyListeners();
  }

  /// Handles the "Copy Task" action from the context menu.
  void handleCopyTask(LegacyGanttTask task) {
    if (_apiResponse == null) return;

    // Create a new task, slightly offset in time, with a new unique ID.
    final newTask = task.copyWith(
      id: 'copy_${task.id}_${DateTime.now().millisecondsSinceEpoch}',
      start: task.start.add(const Duration(days: 1)),
      end: task.end.add(const Duration(days: 1)),
    );

    final newTasks = [..._ganttTasks, newTask];
    // Recalculate stacking with the new task.
    final (recalculatedTasks, newMaxDepth) =
        _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
  }

  /// Handles the "Delete Task" action from the context menu.
  void handleDeleteTask(LegacyGanttTask task) {
    if (_apiResponse == null) return;

    // Create new lists by filtering out the deleted task and its dependencies.
    final newTasks = _ganttTasks.where((t) => t.id != task.id).toList();
    final newDependencies =
        _dependencies.where((d) => d.predecessorTaskId != task.id && d.successorTaskId != task.id).toList();

    // After removing the task, recalculate stacking with the new list.
    final (recalculatedTasks, newMaxDepth) =
        _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
    _dependencies = newDependencies;
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
  }

  /// Shows a dialog to edit all parent summary tasks at once.
  Future<void> editAllParentTasks(BuildContext context) async {
    // Get all parent rows that are currently acting as summaries.
    final parentRowIds = _gridData.where((g) => g.isParent).map((g) => g.id).toSet();
    final parentSummaryTasks =
        _ganttTasks.where((t) => t.isSummary && parentRowIds.contains(t.rowId) && !t.isOverlapIndicator).toList();

    if (parentSummaryTasks.isEmpty) return;

    final updatedTasks = await showDialog<List<LegacyGanttTask>>(
      context: context,
      builder: (context) => _EditTasksInRowDialog(tasks: parentSummaryTasks),
    );

    if (updatedTasks != null) {
      _updateMultipleTasks(updatedTasks);
    }
  }

  /// Shows a dialog to edit all child tasks belonging to a specific parent.
  Future<void> editDependentTasks(BuildContext context, String parentId) async {
    final parentData = _gridData.firstWhereOrNull((p) => p.id == parentId);
    if (parentData == null || parentData.children.isEmpty) return;

    final childRowIds = parentData.children.map((c) => c.id).toSet();
    final dependentTasks = _ganttTasks
        .where((t) => childRowIds.contains(t.rowId) && !t.isSummary && !t.isTimeRangeHighlight && !t.isOverlapIndicator)
        .toList();

    if (dependentTasks.isEmpty) return;

    final updatedTasks = await showDialog<List<LegacyGanttTask>>(
      context: context,
      builder: (context) => _EditTasksInRowDialog(tasks: dependentTasks),
    );

    if (updatedTasks != null) {
      _updateMultipleTasks(updatedTasks);
    }
  }

  /// Shows a dialog to edit a single parent (summary) task.
  Future<void> editParentTask(BuildContext context, String rowId) async {
    final parentData = _gridData.firstWhereOrNull((p) => p.id == rowId);
    if (parentData != null && parentData.isParent) {
      // It's a parent row, edit the summary task
      final task = _ganttTasks.firstWhereOrNull((t) => t.rowId == rowId && t.isSummary);
      if (task != null) {
        _editTask(context, task);
      }
    } else {
      // It's a child row, let the user pick a task to edit
      await editChildTask(context, rowId);
    }
  }

  /// Shows a dialog to edit a child task. If multiple tasks exist in the row, it lets the user choose which one to edit.
  Future<void> editChildTask(BuildContext context, String rowId) async {
    final tasksInRow = _ganttTasks
        .where((t) => t.rowId == rowId && !t.isTimeRangeHighlight && !t.isSummary && !t.isOverlapIndicator)
        .toList();
    if (tasksInRow.isEmpty) return;

    if (tasksInRow.length == 1) {
      // If there's only one task, edit it directly.
      await _editTask(context, tasksInRow.first);
    } else {
      // If there are multiple tasks, show a dialog to choose which one to edit.
      final updatedTasks = await showDialog<List<LegacyGanttTask>>(
        context: context,
        builder: (context) => _EditTasksInRowDialog(tasks: tasksInRow),
      );

      if (updatedTasks != null) {
        _updateMultipleTasks(updatedTasks);
      }
    }
  }

  /// Shows the dialog to edit a specific task's start and end times.
  Future<void> _editTask(BuildContext context, LegacyGanttTask task) async {
    final updatedTaskData = await showDialog<({String name, DateTime start, DateTime end, double completion})>(
      context: context,
      builder: (context) => _EditTaskAlertDialog(task: task),
    );

    if (updatedTaskData != null) {
      final updatedTask = task.copyWith(
        name: updatedTaskData.name,
        start: updatedTaskData.start,
        end: updatedTaskData.end,
        completion: updatedTaskData.completion,
      );
      await _updateMultipleTasks([updatedTask]);
    }
  }

  /// Updates multiple tasks at once and recalculates stacking.
  Future<void> _updateMultipleTasks(List<LegacyGanttTask> updatedTasks) async {
    if (_apiResponse == null) return;

    final newTasks = List<LegacyGanttTask>.from(_ganttTasks);
    for (final updatedTask in updatedTasks) {
      final index = newTasks.indexWhere((t) => t.id == updatedTask.id);
      if (index != -1) {
        // Preserve original properties by only copying over the edited fields.
        final originalTask = newTasks[index];
        newTasks[index] = originalTask.copyWith(
          name: updatedTask.name,
          start: updatedTask.start,
          end: updatedTask.end,
          completion: updatedTask.completion,
        );

        // Update the underlying GanttJobData in the API response to persist changes.
        final parentResource =
            _apiResponse?.resourcesData.firstWhereOrNull((r) => r.children.any((c) => c.id == originalTask.rowId));
        if (parentResource != null) {
          final jobIndex = parentResource.children.indexWhere((j) => j.id == originalTask.rowId);
          if (jobIndex != -1) {
            final oldJob = parentResource.children[jobIndex];
            parentResource.children[jobIndex] = oldJob.copyWith(
              name: updatedTask.name,
              taskName: updatedTask.name,
              completion: updatedTask.completion,
            );
          }
        }
      }
    }
    // Instead of manually updating parts of the state, re-run the full processing logic.
    // This guarantees consistency across all data models.
    await _reprocessDataFromApiResponse();
  }

  /// Deletes a row from the grid and all associated tasks from the Gantt chart.
  void deleteRow(String rowId) {
    if (_apiResponse == null) return;

    // Find the parent data to check if we are deleting a parent or a child.
    final parentData = _gridData.firstWhereOrNull((p) => p.children.any((c) => c.id == rowId));

    List<LegacyGanttTask> nextTasks;

    if (parentData != null) {
      // This is a child row (a job).
      parentData.children.removeWhere((child) => child.id == rowId);
      final parentResource = _apiResponse?.resourcesData.firstWhereOrNull((r) => r.id == parentData.id);
      parentResource?.children.removeWhere((job) => job.id == rowId);

      nextTasks = _ganttTasks.where((task) => task.rowId != rowId).toList();
    } else {
      // This is a parent row (a person).
      final parentToDelete = _gridData.firstWhereOrNull((p) => p.id == rowId);
      if (parentToDelete != null) {
        final childIds = parentToDelete.children.map((c) => c.id).toSet();
        // Remove tasks associated with the parent and all its children.
        nextTasks = _ganttTasks.where((task) => task.rowId != rowId && !childIds.contains(task.rowId)).toList();

        // Remove from data sources
        _gridData.removeWhere((parent) => parent.id == rowId);
        _apiResponse?.resourcesData.removeWhere((resource) => resource.id == rowId);
      } else {
        nextTasks = List.from(_ganttTasks);
      }
    }

    // After removing the row and its tasks, recalculate stacking.
    final (recalculatedTasks, newMaxDepth) =
        _scheduleService.publicCalculateTaskStacking(nextTasks, _apiResponse!, showConflicts: _showConflicts);
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
  }

  /// A helper to find the parent ID for any given row ID (child or parent).
  String? _getParentId(String rowId) {
    for (final parent in _gridData) {
      if (parent.id == rowId) {
        return parent.id; // It's a parent row
      }
      for (final child in parent.children) {
        if (child.id == rowId) {
          return parent.id; // It's a child row, return its parent's id
        }
      }
    }
    return null;
  }

  /// Re-processes the current `_apiResponse` to rebuild all UI-facing data models.
  /// This is the most reliable way to ensure data consistency after a mutation.
  Future<void> _reprocessDataFromApiResponse() async {
    if (_apiResponse == null) {
      await fetchScheduleData();
      return;
    }

    // Preserve the expanded/collapsed state of parent rows before reprocessing.
    final expansionStates = {for (var item in _gridData) item.id: item.isExpanded};

    // Re-run the full processing logic from the service.
    // This is a simplified version of the logic in `fetchAndProcessSchedule`.
    final processedData = await _scheduleService.processGanttResponse(
      _apiResponse!,
      startDate: _startDate,
      range: _range,
      showConflicts: _showConflicts,
      showEmptyParentRows: _showEmptyParentRows,
    );

    // Restore the expansion states.
    for (var newItem in processedData.gridData) {
      if (expansionStates.containsKey(newItem.id)) {
        newItem.isExpanded = expansionStates[newItem.id]!;
      }
    }

    // Update all the view model's state variables from the newly processed data.
    _ganttTasks = processedData.ganttTasks;
    _gridData = processedData.gridData;
    _rowMaxStackDepth = processedData.rowMaxStackDepth;
    _eventMap = processedData.eventMap;

    // Recalculate total date range based on all tasks
    if (_ganttTasks.isNotEmpty) {
      DateTime minStart = _ganttTasks.first.start;
      DateTime maxEnd = _ganttTasks.first.end;
      for (final task in _ganttTasks) {
        if (task.start.isBefore(minStart)) minStart = task.start;
        if (task.end.isAfter(maxEnd)) maxEnd = task.end;
      }
      _totalStartDate = minStart;
      _totalEndDate = maxEnd;
    } else {
      _totalStartDate = _startDate;
      _totalEndDate = _startDate.add(Duration(days: _range));
    }

    _visibleStartDate = effectiveTotalStartDate;
    _visibleEndDate = effectiveTotalEndDate;

    notifyListeners();
  }

  /// Returns a list of tasks that are valid targets for a dependency relationship
  /// with the `sourceTask`. In this example, it restricts targets to tasks
  /// under the same parent resource.
  /// Returns a list of tasks that can be selected as a predecessor or successor.
  List<LegacyGanttTask> getValidDependencyTasks(LegacyGanttTask sourceTask) {
    final sourceParentId = _getParentId(sourceTask.rowId);
    if (sourceParentId == null) return [];

    final parentGridItem = _gridData.firstWhere((g) => g.id == sourceParentId,
        orElse: () => GanttGridData(id: '', name: '', isParent: false, children: []));
    if (parentGridItem.id.isEmpty) return [];

    final allRowIdsForParent = <String>{parentGridItem.id, ...parentGridItem.children.map((c) => c.id)};

    return ganttTasks
        .where((task) =>
            !task.isSummary &&
            !task.isTimeRangeHighlight &&
            !task.isOverlapIndicator &&
            task.id != sourceTask.id &&
            allRowIdsForParent.contains(task.rowId))
        .toList();
  }

  /// Adds a new dependency between two tasks.
  void addDependency(String fromTaskId, String toTaskId) {
    // For now, default to FinishToStart. This could be made configurable in the UI.
    final newDependency = LegacyGanttTaskDependency(
      predecessorTaskId: fromTaskId,
      successorTaskId: toTaskId,
      type: DependencyType.finishToStart,
    );

    // Avoid adding duplicate dependencies
    if (!_dependencies.any((d) =>
        d.predecessorTaskId == newDependency.predecessorTaskId && d.successorTaskId == newDependency.successorTaskId)) {
      _dependencies = [..._dependencies, newDependency];
      notifyListeners();
    }
  }

  /// Returns a list of dependencies where the given task is either a predecessor or a successor.
  List<LegacyGanttTaskDependency> getDependenciesForTask(LegacyGanttTask task) =>
      _dependencies.where((d) => d.predecessorTaskId == task.id || d.successorTaskId == task.id).toList();

  /// Removes a specific dependency.
  void removeDependency(LegacyGanttTaskDependency dependency) {
    final initialCount = _dependencies.length;
    final newList = _dependencies.where((d) => d != dependency).toList();

    if (newList.length < initialCount) {
      _dependencies = newList;
      notifyListeners();
    }
  }

  /// Removes all dependencies associated with a given task.
  void clearDependenciesForTask(LegacyGanttTask task) {
    final initialCount = _dependencies.length;
    final newList = _dependencies.where((d) => d.predecessorTaskId != task.id && d.successorTaskId != task.id).toList();

    if (newList.length < initialCount) {
      _dependencies = newList;
      notifyListeners();
    }
  }

  /// Returns a date formatting function for the tooltip based on the selected timeline axis format.
  String Function(DateTime) _getTooltipDateFormat() {
    switch (_selectedAxisFormat) {
      case TimelineAxisFormat.dayOfMonth:
        return (date) => DateFormat.yMd(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.dayAndMonth:
        return (date) => DateFormat.MMMd(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.monthAndYear:
        return (date) => DateFormat.yMMM(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.dayOfWeek:
        return (date) => DateFormat.E(_selectedLocale).add_jm().format(date);
      case TimelineAxisFormat.custom:
        return (date) => DateFormat.yMd(_selectedLocale).add_jm().format(date);
    }
  }
}

/// A dialog for editing the properties of a single task.
class _EditTaskAlertDialog extends StatefulWidget {
  final LegacyGanttTask task;

  const _EditTaskAlertDialog({required this.task});

  @override
  State<_EditTaskAlertDialog> createState() => _EditTaskAlertDialogState();
}

class _EditTaskAlertDialogState extends State<_EditTaskAlertDialog> {
  late final TextEditingController _nameController;
  late DateTime _startDate;
  late DateTime _endDate;
  late double _completion;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task.name);
    _startDate = widget.task.start;
    _endDate = widget.task.end;
    _completion = widget.task.completion;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.isNotEmpty) {
      Navigator.pop(context, (name: _nameController.text, start: _startDate, end: _endDate, completion: _completion));
    }
  }

  Future<void> _selectDateTime(BuildContext context, bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );

    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (pickedTime == null) return;

    setState(() {
      final newDateTime =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
      if (isStart) {
        _startDate = newDateTime;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 1));
        }
      } else {
        _endDate = newDateTime;
        if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate.subtract(const Duration(hours: 1));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('editTaskDialog'),
        title: const Text('Edit Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Task Name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Start:'),
                TextButton(
                    onPressed: () => _selectDateTime(context, true),
                    child: Text(DateFormat.yMd().add_jm().format(_startDate)))
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('End:'),
                TextButton(
                    onPressed: () => _selectDateTime(context, false),
                    child: Text(DateFormat.yMd().add_jm().format(_endDate)))
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Completion:'),
                Expanded(
                  child: Slider(
                    value: _completion,
                    onChanged: (value) => setState(() => _completion = value),
                    label: '${(_completion * 100).round()}%',
                    divisions: 100,
                  ),
                ),
                Text('${(_completion * 100).round()}%'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _submit, child: const Text('Save')),
        ],
      );
}

/// A dialog that displays a list of tasks in a `DataTable` and allows editing their names and dates.
class _EditTasksInRowDialog extends StatefulWidget {
  final List<LegacyGanttTask> tasks;

  const _EditTasksInRowDialog({required this.tasks});

  @override
  State<_EditTasksInRowDialog> createState() => _EditTasksInRowDialogState();
}

class _EditTasksInRowDialogState extends State<_EditTasksInRowDialog> {
  late List<LegacyGanttTask> _tasks;

  @override
  void initState() {
    super.initState();
    // Create a mutable copy to edit.
    _tasks = widget.tasks.map((t) => t.copyWith()).toList();
  }

  Future<void> _editName(LegacyGanttTask task) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _EditNameDialog(initialName: task.name),
    );

    if (newName != null && newName.isNotEmpty) {
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = _tasks[index].copyWith(name: newName);
        }
      });
    }
  }

  Future<void> _editDate(LegacyGanttTask task, bool isStart) async {
    final initialDate = isStart ? task.start : task.end;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate));
    if (pickedTime == null) return;

    setState(() {
      final newDateTime =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        var tempTask = _tasks[index];
        if (isStart) {
          tempTask = tempTask.copyWith(start: newDateTime);
          if (tempTask.end.isBefore(tempTask.start)) {
            tempTask = tempTask.copyWith(end: tempTask.start.add(const Duration(hours: 1)));
          }
        } else {
          tempTask = tempTask.copyWith(end: newDateTime);
          if (tempTask.start.isAfter(tempTask.end)) {
            tempTask = tempTask.copyWith(start: tempTask.end.subtract(const Duration(hours: 1)));
          }
        }
        _tasks[index] = tempTask;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('editTasksInRowDialog'),
        title: const Text('Edit Tasks'),
        scrollable: true,
        content: SizedBox(
          width: 500, // Give it a reasonable width
          child: DataTable(
            columnSpacing: 16,
            columns: const [
              DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Start', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              DataColumn(label: Text('End', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            ],
            rows: _tasks
                .map((task) => DataRow(
                      cells: [
                        DataCell(
                          Text(task.name ?? 'Unnamed Task', overflow: TextOverflow.ellipsis),
                          onTap: () => _editName(task),
                        ),
                        DataCell(
                          Text(DateFormat.yMd().add_jm().format(task.start)),
                          onTap: () => _editDate(task, true),
                        ),
                        DataCell(
                          Text(DateFormat.yMd().add_jm().format(task.end)),
                          onTap: () => _editDate(task, false),
                        ),
                      ],
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, _tasks),
            child: const Text('Save'),
          ),
        ],
      );
}

/// A small dialog specifically for editing a task's name.
class _EditNameDialog extends StatefulWidget {
  final String? initialName;

  const _EditNameDialog({this.initialName});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('editNameDialog'),
        title: const Text('Edit Task Name'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
