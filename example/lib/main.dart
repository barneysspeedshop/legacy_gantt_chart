import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:legacy_context_menu/legacy_context_menu.dart';
import 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart' as scrubber;
import 'ui/widgets/gantt_grid.dart';
import 'ui/widgets/dashboard_header.dart';
import 'view_models/gantt_view_model.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Legacy Gantt Chart Example',
        // The localizations delegates and supported locales are required for the
        // `intl` package, which is used for formatting dates and times.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('fr', 'FR'),
          Locale('de', 'DE'),
          Locale('ja', 'JP'),
        ],
        theme: ThemeData.from(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        // The Gantt chart supports dark mode out of the box.
        darkTheme: ThemeData.from(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        ),
        themeMode: ThemeMode.system,
        home: const GanttView(),
      );
}

// The main view for the Gantt chart example application.
class GanttView extends StatefulWidget {
  const GanttView({super.key});

  @override
  State<GanttView> createState() => _GanttViewState();
}

// An enum to manage the different timeline label formats demonstrated in the example.
enum TimelineAxisFormat {
  dayOfMonth,
  dayAndMonth,
  monthAndYear,
  dayOfWeek,
  custom,
}

class _GanttViewState extends State<GanttView> {
  late final GanttViewModel _viewModel;
  bool _isPanelVisible = true;
  TimelineAxisFormat _selectedAxisFormat = TimelineAxisFormat.dayOfMonth;
  String _selectedLocale = 'en_US';

  @override
  void initState() {
    super.initState();
    _viewModel = GanttViewModel(initialLocale: _selectedLocale);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// Builds a [LegacyGanttTheme] based on the current application theme and the
  /// selected theme preset from the control panel.
  ///
  /// This demonstrates how to create custom themes for the Gantt chart. You can
  /// start with `LegacyGanttTheme.fromTheme(Theme.of(context))` to get a baseline
  /// theme that matches your app's color scheme and then use `copyWith` to override specific colors or styles.
  LegacyGanttTheme _buildGanttTheme() {
    final baseTheme = LegacyGanttTheme.fromTheme(Theme.of(context));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    switch (_viewModel.selectedTheme) {
      case ThemePreset.forest:
        return baseTheme.copyWith(
          barColorPrimary: Colors.green.shade800,
          barColorSecondary: Colors.green.shade600,
          containedDependencyBackgroundColor: Colors.brown.withValues(alpha: 0.2),
          dependencyLineColor: Colors.brown.shade800,
          timeRangeHighlightColor: Colors.yellow.withValues(alpha: 0.1),
          backgroundColor: isDarkMode ? const Color(0xFF2d2c2a) : const Color(0xFFf5f3f0),
          emptySpaceHighlightColor: Colors.green.withValues(alpha: 0.1),
          emptySpaceAddIconColor: Colors.green.shade600,
          taskTextStyle: baseTheme.taskTextStyle.copyWith(color: Colors.white),
        );
      case ThemePreset.midnight:
        return baseTheme.copyWith(
          barColorPrimary: Colors.indigo.shade700,
          barColorSecondary: Colors.indigo.shade500,
          containedDependencyBackgroundColor: Colors.purple.withValues(alpha: 0.2),
          dependencyLineColor: Colors.purple.shade200,
          timeRangeHighlightColor: Colors.blueGrey.withValues(alpha: 0.2),
          backgroundColor: isDarkMode ? const Color(0xFF1a1a2e) : const Color(0xFFe3e3f3),
          emptySpaceHighlightColor: Colors.indigo.withValues(alpha: 0.1),
          emptySpaceAddIconColor: Colors.indigo.shade200,
          textColor: isDarkMode ? Colors.white70 : Colors.black87,
          taskTextStyle: baseTheme.taskTextStyle.copyWith(color: Colors.white),
        );
      case ThemePreset.standard:
        return baseTheme.copyWith(
          barColorPrimary: Colors.blue.shade700,
          barColorSecondary: Colors.blue[600],
          containedDependencyBackgroundColor: Colors.green.withValues(alpha: 0.15),
          dependencyLineColor: Colors.red.shade700,
          timeRangeHighlightColor: isDarkMode ? Colors.grey[850] : Colors.grey[200],
          emptySpaceHighlightColor: Colors.blue.withValues(alpha: 0.1),
          emptySpaceAddIconColor: Colors.blue.shade700,
          taskTextStyle: baseTheme.taskTextStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white, // Ensure good contrast on blue bars
          ),
        );
    }
  }

  // --- Context Menu and Dialog Handlers ---

  void _handleCopyTask(LegacyGanttTask task) {
    _viewModel.handleCopyTask(task);
    _showSnackbar('Copied task: ${task.name}');
  }

  void _handleDeleteTask(LegacyGanttTask task) {
    _viewModel.handleDeleteTask(task);
    _showSnackbar('Deleted task: ${task.name}');
  }

  void _handleClearDependencies(LegacyGanttTask task) {
    _viewModel.clearDependenciesForTask(task);
    _showSnackbar('Cleared all dependencies for ${task.name}');
  }

  /// A handler that demonstrates how to programmatically change the visible
  /// window of the Gantt chart to focus on a specific task.
  void _handleSnapToTask(LegacyGanttTask task) {
    final taskDuration = task.end.difference(task.start);
    // Make the new window 3 times the duration of the task for context.
    final newWindowDuration = Duration(milliseconds: taskDuration.inMilliseconds * 3);
    // Center the window on the task.
    final newStart = task.start
        .subtract(Duration(milliseconds: (newWindowDuration.inMilliseconds - taskDuration.inMilliseconds) ~/ 2));
    final newEnd = newStart.add(newWindowDuration);

    _viewModel.onScrubberWindowChanged(newStart, newEnd);
    _showSnackbar('Snapped to task: ${task.name}');
  }

  /// Shows a dialog that lists all dependencies for a given task and allows the user to remove one.
  Future<void> _showDependencyRemover(BuildContext context, LegacyGanttTask task) async {
    final dependencies = _viewModel.getDependenciesForTask(task);

    final dependencyToRemove = await showDialog<LegacyGanttTaskDependency>(
      context: context,
      builder: (context) => _DependencyManagerDialog(
        title: 'Remove Dependency for "${task.name}"',
        dependencies: dependencies,
        tasks: _viewModel.ganttTasks,
        sourceTask: task,
      ),
    );

    if (dependencyToRemove != null) {
      _viewModel.removeDependency(dependencyToRemove);
      _showSnackbar('Removed dependency');
    }
  }

  void _showSnackbar(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );

  /// Shows a context menu at the given position for a specific task.
  /// This example uses the `legacy_context_menu` package.
  void _showTaskContextMenu(BuildContext context, LegacyGanttTask task, Offset tapPosition) => showContextMenu(
        context: context,
        menuItems: _buildTaskContextMenuItems(context, task),
        tapPosition: tapPosition,
      );

  /// Builds the list of [ContextMenuItem]s for a task.
  ///
  /// This demonstrates how to build a dynamic context menu that allows for
  // creating and removing dependencies by interacting with the view model.
  /// The submenus for adding predecessors/successors are populated with tasks that are valid dependency targets.
  List<ContextMenuItem> _buildTaskContextMenuItems(BuildContext context, LegacyGanttTask task) {
    final dependencies = _viewModel.getDependenciesForTask(task);
    final availableTasks = _viewModel.getValidDependencyTasks(task);
    final hasDependencies = dependencies.isNotEmpty;

    return <ContextMenuItem>[
      ContextMenuItem(
        caption: 'Copy',
        onTap: () => _handleCopyTask(task),
      ),
      ContextMenuItem(
        caption: 'Delete',
        onTap: () => _handleDeleteTask(task),
      ),
      if (_viewModel.dependencyCreationEnabled) ContextMenuItem.divider,
      if (_viewModel.dependencyCreationEnabled)
        ContextMenuItem(
          caption: 'Add Predecessor',
          submenuBuilder: (context) async {
            if (availableTasks.isEmpty) {
              return [const ContextMenuItem(caption: 'No valid tasks')];
            }
            return availableTasks
                .map((otherTask) => ContextMenuItem(
                      caption: otherTask.name ?? 'Unnamed Task',
                      onTap: () {
                        _viewModel.addDependency(otherTask.id, task.id);
                        _showSnackbar('Added dependency for ${task.name}');
                      },
                    ))
                .toList();
          },
        ),
      if (_viewModel.dependencyCreationEnabled)
        ContextMenuItem(
          caption: 'Add Successor',
          submenuBuilder: (context) async {
            if (availableTasks.isEmpty) {
              return [const ContextMenuItem(caption: 'No valid tasks')];
            }
            return availableTasks
                .map((otherTask) => ContextMenuItem(
                      caption: otherTask.name ?? 'Unnamed Task',
                      onTap: () {
                        _viewModel.addDependency(task.id, otherTask.id);
                        _showSnackbar('Added dependency for ${task.name}');
                      },
                    ))
                .toList();
          },
        ),
      if (_viewModel.dependencyCreationEnabled && hasDependencies) ContextMenuItem.divider,
      if (_viewModel.dependencyCreationEnabled && hasDependencies)
        ContextMenuItem(
          caption: 'Remove Dependency...',
          onTap: () => _showDependencyRemover(context, task),
        ),
      if (_viewModel.dependencyCreationEnabled && hasDependencies)
        ContextMenuItem(
          caption: 'Clear All Dependencies',
          onTap: () => _handleClearDependencies(task),
        ),
    ];
  }

  // --- Gantt Chart Customization Builders ---

  /// Returns a builder function for the timeline axis labels based on the
  /// format selected in the control panel.
  ///
  /// This demonstrates the `timelineAxisLabelBuilder` property, which gives you
  /// full control over how labels on the timeline are formatted.
  String Function(DateTime, Duration)? _getTimelineAxisLabelBuilder() {
    if (_selectedAxisFormat == TimelineAxisFormat.custom) return null;

    switch (_selectedAxisFormat) {
      case TimelineAxisFormat.dayOfMonth:
        return (date, interval) => DateFormat('d', _selectedLocale).format(date);
      case TimelineAxisFormat.dayAndMonth:
        return (date, interval) => DateFormat.MMMd(_selectedLocale).format(date);
      case TimelineAxisFormat.monthAndYear:
        return (date, interval) => DateFormat.yMMM(_selectedLocale).format(date);
      case TimelineAxisFormat.dayOfWeek:
        return (date, interval) => DateFormat.E(_selectedLocale).format(date);
      case TimelineAxisFormat.custom:
        return null;
    }
  }

  /// A builder function for a completely custom timeline header.
  ///
  /// This is passed to the `timelineAxisHeaderBuilder` property. It receives
  /// everything it needs to draw a custom header, including the scale function,
  /// visible and total date domains, and the current theme.
  ///
  /// In this example, it uses a `CustomPaint` with a `_CustomHeaderPainter` to
  /// draw a two-tiered header with months on top and days on the bottom.
  Widget _buildCustomTimelineHeader(BuildContext context, double Function(DateTime) scale, List<DateTime> visibleDomain,
          List<DateTime> totalDomain, LegacyGanttTheme theme, double totalContentWidth) =>
      CustomPaint(
        size: Size(totalContentWidth, 54.0),
        painter: _CustomHeaderPainter(
          scale: scale,
          visibleDomain: visibleDomain,
          totalDomain: totalDomain,
          theme: theme,
          selectedLocale: _selectedLocale,
        ),
      );

  /// Returns a date formatting function for the resize tooltip.
  ///
  /// This demonstrates the `resizeTooltipDateFormat` property, allowing you to
  /// control the format of the date/time displayed in the tooltip that appears
  /// when a user is resizing a task.
  String Function(DateTime) _getResizeTooltipDateFormat() =>
      // Always return a full date and time format, honoring the selected locale.
      (date) => DateFormat.yMd(_selectedLocale).add_jm().format(date);

  /// Builds the control panel on the left side of the screen.
  Widget _buildControlPanel(BuildContext context, GanttViewModel vm) => Container(
        width: vm.controlPanelWidth ?? 350,
        color: Theme.of(context).cardColor,
        child: ListView(
          padding: const EdgeInsets.all(12.0),
          children: [
            Row(
              children: [
                Expanded(child: Text('Controls', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  icon: const Icon(Icons.data_object),
                  tooltip: 'Export Tasks to JSON',
                  onPressed: () => _showJsonExportDialog(vm),
                ),
              ],
            ),
            const Divider(height: 24),
            DashboardHeader(
              selectedDate: vm.startDate,
              selectedRange: vm.range,
              onSelectDate: vm.onSelectDate,
              onRangeChange: vm.onRangeChange,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('Persons:')),
                DropdownButton<int>(
                  value: vm.personCount,
                  onChanged: (value) {
                    if (value != null) vm.setPersonCount(value);
                  },
                  items: List.generate(101, (i) => i)
                      .map((count) => DropdownMenuItem(value: count, child: Text(count.toString())))
                      .toList(),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Jobs:')),
                DropdownButton<int>(
                  value: vm.jobCount,
                  onChanged: (value) {
                    if (value != null) vm.setJobCount(value);
                  },
                  items: List.generate(101, (i) => i)
                      .map((count) => DropdownMenuItem(value: count, child: Text(count.toString())))
                      .toList(),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Theme', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemePreset>(
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              segments: const [
                ButtonSegment(value: ThemePreset.standard, icon: Icon(Icons.palette)),
                ButtonSegment(value: ThemePreset.forest, icon: Icon(Icons.park)),
                ButtonSegment(value: ThemePreset.midnight, icon: Icon(Icons.nightlight_round)),
              ],
              selected: {vm.selectedTheme},
              onSelectionChanged: (newSelection) => vm.setSelectedTheme(newSelection.first),
            ),
            const Divider(height: 24),
            Text('Features', style: Theme.of(context).textTheme.titleMedium),
            // These switches demonstrate how to toggle the interactive features
            // of the Gantt chart by changing the boolean properties on the widget.
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Drag & Drop'),
                Switch(
                  value: vm.dragAndDropEnabled,
                  onChanged: vm.setDragAndDropEnabled,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Resize'),
                Switch(
                  value: vm.resizeEnabled,
                  onChanged: vm.setResizeEnabled,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Create Tasks'),
                Switch(
                  value: vm.createTasksEnabled,
                  onChanged: vm.setCreateTasksEnabled,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Create Dependencies'),
                Switch(
                  value: vm.dependencyCreationEnabled,
                  onChanged: vm.setDependencyCreationEnabled,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show Conflicts'),
                Switch(
                  value: vm.showConflicts,
                  onChanged: vm.setShowConflicts,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show Dependencies'),
                Switch(
                  value: vm.showDependencies,
                  onChanged: vm.setShowDependencies,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show Empty Parents'),
                Switch(
                  value: vm.showEmptyParentRows,
                  onChanged: (value) => vm.setShowEmptyParentRows(value),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Drag Handle Options', style: Theme.of(context).textTheme.titleMedium),
            // This dropdown demonstrates how to control the width of the resize handles on tasks.
            Row(
              children: [
                const Expanded(child: Text('Resize Handle Width:')),
                DropdownButton<double>(
                  value: vm.resizeHandleWidth,
                  onChanged: (value) => vm.setResizeHandleWidth(value!),
                  items: [1.0, 2.0, 3.0, 4.0, 5.0, 10.0, 15.0, 20.0]
                      .map((size) => DropdownMenuItem(value: size, child: Text(size.toStringAsFixed(0))))
                      .toList(),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Loading Indicator', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<GanttLoadingIndicatorType>(
              segments: const [
                ButtonSegment(value: GanttLoadingIndicatorType.circular, label: Text('Circular')),
                ButtonSegment(value: GanttLoadingIndicatorType.linear, label: Text('Linear')),
              ],
              selected: {vm.loadingIndicatorType},
              onSelectionChanged: (newSelection) => vm.setLoadingIndicatorType(newSelection.first),
            ),
            if (vm.loadingIndicatorType == GanttLoadingIndicatorType.linear) ...[
              const SizedBox(height: 8),
              SegmentedButton<GanttLoadingIndicatorPosition>(
                segments: const [
                  ButtonSegment(
                    value: GanttLoadingIndicatorPosition.top,
                    label: Text('Top'),
                  ),
                  ButtonSegment(
                    value: GanttLoadingIndicatorPosition.bottom,
                    label: Text('Bottom'),
                  ),
                ],
                selected: {vm.loadingIndicatorPosition},
                onSelectionChanged: (newSelection) => vm.setLoadingIndicatorPosition(newSelection.first),
              ),
            ],
            const Divider(height: 24),
            Text('Timeline Label Format', style: Theme.of(context).textTheme.titleMedium),
            // This segmented button controls which label format is used for the timeline,
            // demonstrating the `timelineAxisLabelBuilder` and `timelineAxisHeaderBuilder` properties.
            const SizedBox(height: 8),
            SegmentedButton<TimelineAxisFormat>(
              multiSelectionEnabled: false,
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              ),
              segments: const [
                ButtonSegment(value: TimelineAxisFormat.dayOfMonth, label: Text('Day')),
                ButtonSegment(value: TimelineAxisFormat.dayAndMonth, label: Text('Month')),
                ButtonSegment(value: TimelineAxisFormat.monthAndYear, label: Text('Year')),
                ButtonSegment(value: TimelineAxisFormat.dayOfWeek, label: Text('Weekday')),
                ButtonSegment(value: TimelineAxisFormat.custom, label: Text('Custom')),
              ],
              selected: {_selectedAxisFormat},
              onSelectionChanged: (newSelection) => setState(() => _selectedAxisFormat = newSelection.first),
            ),
            const Divider(height: 24),
            Text('Locale', style: Theme.of(context).textTheme.titleMedium),
            // This demonstrates how changing the locale affects date formatting
            // throughout the chart, powered by the `intl` package.
            const SizedBox(height: 8),
            SegmentedButton<String>(
              multiSelectionEnabled: false,
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              ),
              segments: const [
                ButtonSegment(value: 'en_US', label: Text('EN')),
                ButtonSegment(value: 'fr_FR', label: Text('FR')),
                ButtonSegment(value: 'de_DE', label: Text('DE')),
                ButtonSegment(value: 'ja_JP', label: Text('JA')),
              ],
              selected: {_selectedLocale},
              onSelectionChanged: (newSelection) {
                setState(() => _selectedLocale = newSelection.first);
                vm.setSelectedLocale(newSelection.first);
              },
            ),
          ],
        ),
      );

  /// Shows a dialog with the current Gantt data exported as a JSON string.
  /// This demonstrates how you might extract the data from the chart for saving or sharing.
  void _showJsonExportDialog(GanttViewModel vm) {
    // This function builds the JSON structure from the original API response data.
    final apiResponse = vm.apiResponse;
    if (apiResponse == null) {
      // Handle case where data hasn't been loaded yet.
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('noDataExportDialog'),
          title: const Text('Error'),
          content: const Text('No data available to export.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    // We will rebuild the JSON from the stored API response,
    // which matches the structure you provided.
    final exportData = {
      'success': apiResponse.success,
      'eventsData': apiResponse.eventsData
          .map((e) => e.toJson()) // Assuming toJson exists on your models
          .toList(),
      'resourcesData': apiResponse.resourcesData.map((r) => r.toJson()).toList(),
      'assignmentsData': apiResponse.assignmentsData.map((a) => a.toJson()).toList(),
      'resourceTimeRangesData': apiResponse.resourceTimeRangesData.map((r) => r.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(
      // Instead of converting internal GanttTask objects,
      // we now convert the original API response data structure.
      exportData,
    );

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('jsonExportDialog'),
        title: const Text('Gantt Tasks JSON Export'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonString,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonString));
              _showSnackbar('JSON copied to clipboard');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // The root of the application uses a ChangeNotifierProvider to make the
  // GanttViewModel available to the entire widget tree below it. This allows
  // any widget to listen to changes in the view model and rebuild accordingly.
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: _viewModel,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Legacy Gantt Chart Example'),
            leading: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Toggle Controls',
              onPressed: () => setState(() => _isPanelVisible = !_isPanelVisible),
            ),
          ),
          body: SafeArea(
            child: Consumer<GanttViewModel>(
              builder: (context, vm, child) {
                final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
                final ganttTheme = _buildGanttTheme();
                // Update the format after the current frame is built to avoid calling notifyListeners during build.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  vm.updateResizeTooltipDateFormat(_getResizeTooltipDateFormat());
                });

                return Row(
                  children: [
                    if (_isPanelVisible)
                      SizedBox(
                        width: vm.controlPanelWidth ?? 350,
                        child: _buildControlPanel(context, vm),
                      ),
                    if (_isPanelVisible)
                      GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          final newWidth = (vm.controlPanelWidth ?? 350) + details.delta.dx;
                          vm.setControlPanelWidth(newWidth.clamp(150.0, 400.0));
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: VerticalDivider(
                            width: 8,
                            thickness: 8,
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (vm.gridWidth == null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              vm.setGridWidth(constraints.maxWidth * 0.4);
                            });
                          }

                          return Row(
                            children: [
                              // Gantt Grid (Left Side)
                              // This is a custom widget for this example app that shows a data grid.
                              // It is synchronized with the Gantt chart via a shared ScrollController.
                              // This is a common pattern for building a complete Gantt chart UI.
                              SizedBox(
                                width: vm.gridWidth ?? constraints.maxWidth * 0.4,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: GanttGrid(
                                        headerHeight: _selectedAxisFormat == TimelineAxisFormat.custom ? 54.0 : 27.0,
                                        gridData: vm.visibleGridData,
                                        visibleGanttRows: vm.visibleGanttRows,
                                        rowMaxStackDepth: vm.rowMaxStackDepth,
                                        scrollController: vm.scrollController,
                                        onToggleExpansion: vm.toggleExpansion,
                                        isDarkMode: isDarkMode,
                                        onAddContact: () => vm.addContact(context),
                                        onAddLineItem: (parentId) => vm.addLineItem(context, parentId),
                                        onSetParentTaskType: vm.setParentTaskType,
                                        onEditParentTask: (parentId) => vm.editParentTask(context, parentId),
                                        onEditDependentTasks: (parentId) => vm.editDependentTasks(context, parentId),
                                        onEditAllParentTasks: () => vm.editAllParentTasks(context),
                                        onDeleteRow: vm.deleteRow,
                                        ganttTasks: vm.ganttTasks,
                                      ),
                                    ),
                                    // This SizedBox balances the height of the timeline scrubber on the right.
                                    const SizedBox(height: 40),
                                  ],
                                ),
                              ),
                              // Draggable Divider
                              GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  final newWidth = (vm.gridWidth ?? 0) + details.delta.dx;
                                  vm.setGridWidth(newWidth.clamp(150.0, constraints.maxWidth - 150.0));
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeLeftRight,
                                  child: VerticalDivider(
                                    width: 8,
                                    thickness: 8,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                              // Gantt Chart (Right Side)
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, chartConstraints) {
                                          // If data is still loading, show a progress indicator
                                          if (vm.isLoading) {
                                            return const Center(child: CircularProgressIndicator());
                                          }

                                          final ganttWidth = vm.calculateGanttWidth(chartConstraints.maxWidth);

                                          // Calculate the total height required for the Gantt chart content.
                                          // This is essential when the chart is in a vertically scrolling view.
                                          final double axisHeight =
                                              _selectedAxisFormat == TimelineAxisFormat.custom ? 54.0 : 27.0;
                                          final double ganttContentHeight = vm.visibleGanttRows.fold<double>(
                                            0.0,
                                            (prev, row) => prev + (vm.rowMaxStackDepth[row.id] ?? 1) * vm.rowHeight,
                                          ); // Use vm.rowHeight

                                          return SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            controller: vm.ganttHorizontalScrollController,
                                            child: SizedBox(
                                              width: ganttWidth,
                                              height: axisHeight + ganttContentHeight,
                                              child: LegacyGanttChartWidget(
                                                loadingIndicatorType: vm.loadingIndicatorType,
                                                loadingIndicatorPosition: vm.loadingIndicatorPosition,
                                                // --- Custom Builders ---
                                                timelineAxisLabelBuilder: _getTimelineAxisLabelBuilder(),
                                                timelineAxisHeaderBuilder:
                                                    _selectedAxisFormat == TimelineAxisFormat.custom
                                                        ? _buildCustomTimelineHeader
                                                        : null,

                                                // --- Data and Layout ---
                                                data: vm.ganttTasks,
                                                dependencies: vm.dependencies,
                                                visibleRows: vm.visibleGanttRows, // This should be correct
                                                rowHeight: 27.0,
                                                rowMaxStackDepth: vm.rowMaxStackDepth,
                                                // The axis height is adjusted based on whether we are using the
                                                // default single-line header or the custom two-line header.
                                                axisHeight: axisHeight,

                                                // --- Scroll Controllers and Syncing ---
                                                // This is the key to synchronizing the vertical scroll between the
                                                // left-side grid and the right-side chart.
                                                scrollController: vm.scrollController,

                                                // --- Date Range ---
                                                // These define the currently visible time window.
                                                gridMin: vm.visibleStartDate?.millisecondsSinceEpoch.toDouble(),
                                                gridMax: vm.visibleEndDate?.millisecondsSinceEpoch.toDouble(),
                                                // These define the total scrollable time range.
                                                totalGridMin:
                                                    vm.effectiveTotalStartDate?.millisecondsSinceEpoch.toDouble(),
                                                totalGridMax:
                                                    vm.effectiveTotalEndDate?.millisecondsSinceEpoch.toDouble(),
                                                enableDragAndDrop: vm.dragAndDropEnabled,
                                                showEmptyRows: vm.showEmptyParentRows,
                                                enableResize: vm.resizeEnabled,
                                                onTaskUpdate: (task, start, end) {
                                                  vm.handleTaskUpdate(task, start, end);
                                                  _showSnackbar('Updated ${task.name}');
                                                },
                                                onTaskDoubleClick: (task) {
                                                  _handleSnapToTask(task);
                                                },
                                                // This callback is triggered when a user clicks on an empty space,
                                                // allowing for the creation of new tasks.
                                                onEmptySpaceClick: (rowId, time) =>
                                                    vm.handleEmptySpaceClick(context, rowId, time),
                                                onPressTask: (task) => _showSnackbar('Tapped on task: ${task.name}'),
                                                onTaskHover: (task, globalPosition) =>
                                                    vm.onTaskHover(task, context, globalPosition),

                                                // --- Theming and Styling ---
                                                theme: ganttTheme,
                                                weekendColor: Colors.grey.withValues(alpha:0.1),
                                                resizeTooltipDateFormat: _getResizeTooltipDateFormat(),
                                                resizeTooltipBackgroundColor: Colors.purple,
                                                resizeHandleWidth: vm.resizeHandleWidth,
                                                resizeTooltipFontColor: Colors.white,

                                                // --- Custom Task Content ---
                                                // This builder injects custom content *inside* the default task bar.
                                                // It's used here to add an icon and a context menu button.
                                                taskContentBuilder: (task) {
                                                  if (task.isTimeRangeHighlight) {
                                                    return const SizedBox.shrink(); // Hide content for highlights
                                                  }
                                                  final barColor = task.color ?? ganttTheme.barColorPrimary;
                                                  final textColor =
                                                      ThemeData.estimateBrightnessForColor(barColor) == Brightness.dark
                                                          ? Colors.white
                                                          : Colors.black;
                                                  final textStyle = ganttTheme.taskTextStyle.copyWith(color: textColor);
                                                  return GestureDetector(
                                                    onSecondaryTapUp: (details) {
                                                      _showTaskContextMenu(context, task, details.globalPosition);
                                                    },
                                                    child: LayoutBuilder(builder: (context, constraints) {
                                                      // Define minimum widths for content visibility.
                                                      final bool canShowButton = constraints.maxWidth >= 32;
                                                      final bool canShowText = constraints.maxWidth > 66;

                                                      return Stack(
                                                        children: [
                                                          // Task content (icon and name)
                                                          if (canShowText)
                                                            Padding(
                                                              // Pad to the right to avoid overlapping the options button.
                                                              padding: const EdgeInsets.only(left: 4.0, right: 32.0),
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    task.isSummary
                                                                        ? Icons.summarize_outlined
                                                                        : Icons.task_alt,
                                                                    color: textColor,
                                                                    size: 16,
                                                                  ),
                                                                  const SizedBox(width: 4),
                                                                  Expanded(
                                                                    child: Text(
                                                                      task.name ?? '',
                                                                      style: textStyle,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      softWrap: false,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),

                                                          // Options menu button
                                                          if (canShowButton)
                                                            Positioned(
                                                              right:
                                                                  8, // Inset from the right edge to leave space for resize handle
                                                              top: 0,
                                                              bottom: 0,
                                                              child: Builder(
                                                                builder: (context) => IconButton(
                                                                  padding: EdgeInsets.zero,
                                                                  icon:
                                                                      Icon(Icons.more_vert, color: textColor, size: 18),
                                                                  tooltip: 'Task Options',
                                                                  onPressed: () {
                                                                    final RenderBox button =
                                                                        context.findRenderObject() as RenderBox;
                                                                    final Offset offset =
                                                                        button.localToGlobal(Offset.zero);
                                                                    final tapPosition =
                                                                        offset.translate(button.size.width, 0);
                                                                    _showTaskContextMenu(context, task, tapPosition);
                                                                  },
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      );
                                                    }),
                                                  );
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    // --- Timeline Scrubber ---
                                    // This widget from the `legacy_timeline_scrubber` package provides a
                                    // mini-map of the entire timeline, allowing for quick navigation.
                                    // It's a separate package but designed to work well with the Gantt chart.
                                    // Note how the task data is mapped to the scrubber's own task model.
                                    if (vm.totalStartDate != null &&
                                        vm.totalEndDate != null &&
                                        vm.visibleStartDate != null &&
                                        vm.visibleEndDate != null)
                                      Container(
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                        color: Theme.of(context).cardColor,
                                        child: scrubber.LegacyGanttTimelineScrubber(
                                          totalStartDate: vm.totalStartDate!,
                                          totalEndDate: vm.totalEndDate!,
                                          visibleStartDate: vm.visibleStartDate!,
                                          visibleEndDate: vm.visibleEndDate!,
                                          onWindowChanged: vm.onScrubberWindowChanged,
                                          visibleRows: vm.visibleGanttRows.map((row) => row.id).toList(),
                                          rowMaxStackDepth: vm.rowMaxStackDepth,
                                          rowHeight: 27.0,
                                          tasks: vm.ganttTasks
                                              .map((t) => scrubber.LegacyGanttTask(
                                                    id: t.id,
                                                    rowId: t.rowId,
                                                    stackIndex: t.stackIndex,
                                                    start: t.start,
                                                    end: t.end,
                                                    name: t.name,
                                                    color: t.color,
                                                    isOverlapIndicator: t.isOverlapIndicator,
                                                    isTimeRangeHighlight: t.isTimeRangeHighlight,
                                                    isSummary: t.isSummary,
                                                  ))
                                              .toList(),
                                          startPadding: const Duration(days: 7),
                                          endPadding: const Duration(days: 7),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

class _CustomHeaderPainter extends CustomPainter {
  final double Function(DateTime) scale;
  final List<DateTime> visibleDomain;
  final List<DateTime> totalDomain;
  final LegacyGanttTheme theme;
  final String selectedLocale;

  _CustomHeaderPainter({
    required this.scale,
    required this.visibleDomain,
    required this.totalDomain,
    required this.theme,
    required this.selectedLocale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDomain.isEmpty || visibleDomain.isEmpty) {
      return;
    }
    final visibleDuration = visibleDomain.last.difference(visibleDomain.first);
    final monthTextStyle = theme.axisTextStyle.copyWith(fontWeight: FontWeight.bold);
    final dayTextStyle = theme.axisTextStyle.copyWith(fontSize: 10);

    // Determine the tick interval based on the visible duration.
    Duration tickInterval;
    if (visibleDuration.inDays > 60) {
      tickInterval = const Duration(days: 7);
    } else if (visibleDuration.inDays > 14) {
      tickInterval = const Duration(days: 2);
    } else {
      tickInterval = const Duration(days: 1);
    }

    DateTime current = totalDomain.first;
    String? lastMonth;
    while (current.isBefore(totalDomain.last)) {
      final next = current.add(tickInterval);
      final monthFormat = DateFormat('MMMM yyyy', selectedLocale);
      final dayFormat = DateFormat('d', selectedLocale);

      // Month label
      final monthStr = monthFormat.format(current);
      if (monthStr != lastMonth) {
        lastMonth = monthStr;
        final monthStart = DateTime(current.year, current.month, 1);
        final monthEnd = DateTime(current.year, current.month + 1, 0);
        final startX = scale(monthStart.isBefore(visibleDomain.first) ? visibleDomain.first : monthStart);
        final endX = scale(monthEnd.isAfter(visibleDomain.last) ? visibleDomain.last : monthEnd);

        final textSpan = TextSpan(text: monthStr, style: monthTextStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        if (endX > startX) {
          textPainter.paint(
            canvas,
            Offset(startX + (endX - startX) / 2 - textPainter.width / 2, 0),
          );
        }
      }

      // Day label
      final dayX = scale(current);
      final dayText = dayFormat.format(current);
      final textSpan = TextSpan(text: dayText, style: dayTextStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(dayX - textPainter.width / 2, 20),
      );

      current = next;
    }
  }

  @override
  bool shouldRepaint(covariant _CustomHeaderPainter oldDelegate) =>
      oldDelegate.scale != scale ||
      !listEquals(oldDelegate.visibleDomain, visibleDomain) ||
      !listEquals(oldDelegate.totalDomain, totalDomain) ||
      oldDelegate.theme != theme ||
      oldDelegate.selectedLocale != selectedLocale;
}

/// A dialog to manage (remove) dependencies for a task.
class _DependencyManagerDialog extends StatelessWidget {
  final String title;
  final List<LegacyGanttTaskDependency> dependencies;
  final List<LegacyGanttTask> tasks;
  final LegacyGanttTask sourceTask;

  const _DependencyManagerDialog({
    required this.title,
    required this.dependencies,
    required this.tasks,
    required this.sourceTask,
  });

  String _dependencyText(LegacyGanttTaskDependency dep) {
    final sourceTaskName = tasks.firstWhere((t) => t.id == dep.predecessorTaskId).name;
    final targetTaskName = tasks.firstWhere((t) => t.id == dep.successorTaskId).name;
    return '$sourceTaskName -> $targetTaskName';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('dependencyManagerDialog'),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: dependencies.isEmpty
              ? const Text('No dependencies to remove.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: dependencies.length,
                  itemBuilder: (context, index) {
                    final dep = dependencies[index];
                    return ListTile(
                      title: Text(_dependencyText(dep)),
                      onTap: () => Navigator.of(context).pop(dep),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ],
      );
}

/// A stateful widget for the "Create Task" dialog.
class _CreateTaskAlertDialog extends StatefulWidget {
  final DateTime initialTime;
  final String resourceName;
  final String rowId;
  final Function(LegacyGanttTask) onCreate;
  final TimeOfDay defaultStartTime;
  final TimeOfDay defaultEndTime;

  const _CreateTaskAlertDialog({
    required this.initialTime,
    required this.resourceName,
    required this.rowId,
    required this.onCreate,
    required this.defaultStartTime,
    required this.defaultEndTime,
  });

  @override
  State<_CreateTaskAlertDialog> createState() => _CreateTaskAlertDialogState();
}

class _CreateTaskAlertDialogState extends State<_CreateTaskAlertDialog> {
  late final TextEditingController _nameController;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'New Task for ${widget.resourceName}');
    // Select the default text so the user can easily overwrite it.
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );

    // Use the date part from where the user clicked, but apply the default times.
    final datePart = widget.initialTime;
    _startDate = DateTime(
      datePart.year,
      datePart.month,
      datePart.day,
      widget.defaultStartTime.hour,
      widget.defaultStartTime.minute,
    );
    _endDate = DateTime(
      datePart.year,
      datePart.month,
      datePart.day,
      widget.defaultEndTime.hour,
      widget.defaultEndTime.minute,
    );

    // Handle overnight case where end time is on the next day.
    if (_endDate.isBefore(_startDate)) {
      _endDate = _endDate.add(const Duration(days: 1));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.trim().isNotEmpty) {
      final newTask = LegacyGanttTask(
          id: 'new_task_${DateTime.now().millisecondsSinceEpoch}',
          rowId: widget.rowId,
          name: _nameController.text.trim(),
          start: _startDate,
          end: _endDate);
      widget.onCreate(newTask);
      Navigator.pop(context); // Close the dialog on successful creation
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
        if (_endDate.isBefore(_startDate)) _endDate = _startDate.add(const Duration(hours: 1));
      } else {
        _endDate = newDateTime;
        if (_startDate.isAfter(_endDate)) _startDate = _endDate.subtract(const Duration(hours: 1));
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('createTaskDialog'),
        title: Text('Create Task for ${widget.resourceName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Task Name'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Start:'),
            TextButton(
                onPressed: () => _selectDateTime(context, true),
                child: Text(DateFormat.yMd().add_jm().format(_startDate)))
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('End:'),
            TextButton(
                onPressed: () => _selectDateTime(context, false),
                child: Text(DateFormat.yMd().add_jm().format(_endDate)))
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: _submit, child: const Text('Create')),
        ],
      );
}
