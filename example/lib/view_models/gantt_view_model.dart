import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:intl/intl.dart';
import '../main.dart';

import '../data/models.dart';
import '../services/gantt_schedule_service.dart';
import '../ui/dialogs/create_task_dialog.dart';
import '../ui/gantt_grid_data.dart';
import '../utils/task_helpers.dart';

enum ThemePreset {
  standard,
  forest,
  midnight,
}

class GanttViewModel extends ChangeNotifier {
  // State variables
  List<LegacyGanttTask> _ganttTasks = [];
  List<LegacyGanttTaskDependency> _dependencies = [];
  List<GanttGridData> _gridData = [];
  ThemePreset _selectedTheme = ThemePreset.standard;
  bool _dragAndDropEnabled = true;
  bool _resizeEnabled = true;
  bool _createTasksEnabled = true;
  bool _dependencyCreationEnabled = true;
  double _resizeHandleWidth = 10.0;
  DateTime _startDate = DateTime.now();
  final TimeOfDay _defaultStartTime = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay _defaultEndTime = const TimeOfDay(hour: 17, minute: 0);
  int _range = 14; // Default range for data fetching
  int _personCount = 10;
  int _jobCount = 16;
  String _selectedLocale = 'en_US'; // Default locale
  TimelineAxisFormat _selectedAxisFormat = TimelineAxisFormat.dayOfMonth; // Default format;
  bool _showConflicts = true;
  String Function(DateTime)? _resizeTooltipDateFormat; // Internal storage for resize tooltip format

  String Function(DateTime)? get resizeTooltipDateFormat => _resizeTooltipDateFormat;

  // Date range state for the Gantt chart view and scrubber
  DateTime? _totalStartDate;
  DateTime? _totalEndDate;
  DateTime? _visibleStartDate;
  DateTime? _visibleEndDate;

  // Padding for the Gantt chart timeline to provide some space at the edges.
  final Duration _ganttStartPadding = const Duration(days: 7);
  final Duration _ganttEndPadding = const Duration(days: 7);

// Stores the original max stack depth for each row
  Map<String, int> _rowMaxStackDepth = {}; // Stores max stack depth for each row
  final ScrollController _scrollController = ScrollController();
  final ScrollController _ganttHorizontalScrollController = ScrollController();
  bool _isScrubberUpdating = false; // Prevents feedback loop between scroller and scrubber

  OverlayEntry? _tooltipOverlay;
  String? _hoveredTaskId;
  Map<String, GanttEventData> _eventMap = {};

  final GanttScheduleService _scheduleService = GanttScheduleService();
  GanttResponse? _apiResponse;

  double? _gridWidth;
  double? _controlPanelWidth = 300.0;

  // Getters for the UI
  List<LegacyGanttTask> get ganttTasks => _ganttTasks;
  List<LegacyGanttTaskDependency> get dependencies => _dependencies;
  List<GanttGridData> get gridData => _gridData;
  ThemePreset get selectedTheme => _selectedTheme;
  bool get dragAndDropEnabled => _dragAndDropEnabled;
  bool get resizeEnabled => _resizeEnabled;
  bool get createTasksEnabled => _createTasksEnabled;
  bool get dependencyCreationEnabled => _dependencyCreationEnabled;
  bool get showConflicts => _showConflicts;
  double get resizeHandleWidth => _resizeHandleWidth;
  DateTime get startDate => _startDate;
  TimeOfDay get defaultStartTime => _defaultStartTime;
  TimeOfDay get defaultEndTime => _defaultEndTime;
  int get range => _range;
  int get personCount => _personCount;
  int get jobCount => _jobCount;
  DateTime? get totalStartDate => _totalStartDate;
  DateTime? get totalEndDate => _totalEndDate;
  DateTime? get visibleStartDate => _visibleStartDate;
  DateTime? get visibleEndDate => _visibleEndDate;
  DateTime? get effectiveTotalStartDate => _totalStartDate?.subtract(_ganttStartPadding);
  DateTime? get effectiveTotalEndDate => _totalEndDate?.add(_ganttEndPadding);
  Map<String, int> get rowMaxStackDepth => _rowMaxStackDepth;
  ScrollController get scrollController => _scrollController;
  ScrollController get ganttHorizontalScrollController => _ganttHorizontalScrollController;
  double? get gridWidth => _gridWidth;
  double? get controlPanelWidth => _controlPanelWidth;

  List<GanttGridData> get visibleGridData => _gridData;

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

  void setShowConflicts(bool value) {
    _showConflicts = value;
    // Recalculate tasks with the new conflict visibility setting.
    // This is more robust than just changing the stack depth.
    final (recalculatedTasks, newMaxDepth) =
        _scheduleService.publicCalculateTaskStacking(_ganttTasks, _apiResponse!, showConflicts: _showConflicts);
    _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
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

  Future<void> fetchScheduleData() async {
    _ganttTasks = [];
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

      // 2. Find two tasks in the same row for a 'finishToStart' dependency
      final tasksByRow = <String, List<LegacyGanttTask>>{};
      for (final task in ganttTasks) {
        if (!task.isSummary && !task.isTimeRangeHighlight) {
          tasksByRow.putIfAbsent(task.rowId, () => []).add(task);
        }
      }

      for (final tasksInRow in tasksByRow.values) {
        if (tasksInRow.length > 1) {
          tasksInRow.sort((a, b) => a.start.compareTo(b.start));
          newDependencies.add(
            LegacyGanttTaskDependency(predecessorTaskId: tasksInRow[0].id, successorTaskId: tasksInRow[1].id),
          );
          break; // Just add one for demonstration
        }
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

      _visibleStartDate = effectiveTotalStartDate;
      _visibleEndDate = effectiveTotalEndDate;

      notifyListeners();

      WidgetsBinding.instance.addPostFrameCallback((_) => _setInitialScroll());
    } catch (e) {
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

  void onScrubberWindowChanged(DateTime newStart, DateTime newEnd) {
    // Set a flag to prevent the scroll listener from firing and causing a loop.
    _isScrubberUpdating = true;

    // Update the state with the new visible window from the scrubber.
    // This will trigger a rebuild, which updates the Gantt chart's gridMin/gridMax
    // and recalculates its total width.
    _visibleStartDate = newStart;
    _visibleEndDate = newEnd;
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
          final startOffsetMs = newStart.difference(effectiveTotalStartDate!).inMilliseconds;
          final newScrollOffset = (startOffsetMs / totalDataDuration) * totalGanttWidth;

          _ganttHorizontalScrollController.jumpTo(newScrollOffset.clamp(0.0, position.maxScrollExtent));
        }
      }
      // Reset the flag after the update is complete.
      _isScrubberUpdating = false;
    });
  }

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

  // Sets initial scroll position after data loads and layout is built.
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

  void _updateTasksAndStacking(List<LegacyGanttTask> tasks, Map<String, int> maxDepth) {
    _ganttTasks = tasks;
    _rowMaxStackDepth = maxDepth;
// Keep a copy of the original
    notifyListeners();
  }

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

  Future<void> addContact(BuildContext context) async {
    final newContactName = await _showTextInputDialog(
      context: context,
      title: 'Add New Contact',
      label: 'Contact Name',
    );

    if (newContactName != null && newContactName.isNotEmpty) {
      final newResourceId = 'person_${DateTime.now().millisecondsSinceEpoch}';

      // Create new data objects
      final newResource = GanttResourceData(id: newResourceId, name: newContactName, children: []);
      final newGridItem =
          GanttGridData(id: newResourceId, name: newContactName, isParent: true, isExpanded: true, children: []);

      // Update the mock API response and the grid data
      _apiResponse?.resourcesData.add(newResource);
      _gridData.add(newGridItem);
      notifyListeners();
    }
  }

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
          id: newJobId,
          name: newLineItemName,
          taskName: newLineItemName,
          status: 'New',
          taskColor: '9E9E9E',
          completion: 0.0);
      final newGridItem = GanttGridData.fromJob(newJob);

      // Find the parent in both data structures and add the new child
      final parentResource = _apiResponse?.resourcesData.firstWhere((r) => r.id == parentId);
      parentResource?.children.add(newJob);
      parentGridItem.children.add(newGridItem);
      notifyListeners();
    }
  }

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

  void _addNewTask(LegacyGanttTask newTask) {
    final newTasks = [..._ganttTasks, newTask];
    if (_apiResponse != null) {
      final (recalculatedTasks, newMaxDepth) =
          _scheduleService.publicCalculateTaskStacking(newTasks, _apiResponse!, showConflicts: _showConflicts);
      _updateTasksAndStacking(recalculatedTasks, newMaxDepth);
    }
  }

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

  void toggleExpansion(String id) {
    final item = _gridData.firstWhere((element) => element.id == id);
    item.isExpanded = !item.isExpanded;
    notifyListeners();
  }

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
    }
  }
}
