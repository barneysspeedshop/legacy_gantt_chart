import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:collection/collection.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:intl/intl.dart';
import 'package:legacy_tree_grid/legacy_tree_grid.dart';
import 'package:provider/provider.dart';
import 'package:legacy_context_menu/legacy_context_menu.dart';
import 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart' as scrubber;
import 'ui/widgets/dashboard_header.dart';
import 'ui/widgets/custom_header_painter.dart';
import 'ui/widgets/dependency_dialog.dart';
import 'view_models/gantt_view_model.dart';
import 'ui/dialogs/create_task_dialog.dart';

import 'platform/platform_init.dart'
    if (dart.library.io) 'platform/platform_init_io.dart'
    if (dart.library.html) 'platform/platform_init_web.dart';

void main() {
  initializePlatform();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Legacy Gantt Chart Example',
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

class GanttView extends StatefulWidget {
  const GanttView({super.key});

  @override
  State<GanttView> createState() => _GanttViewState();
}

class _GanttViewState extends State<GanttView> {
  late final GanttViewModel _viewModel;
  bool _isPanelVisible = true;
  TimelineAxisFormat _selectedAxisFormat = TimelineAxisFormat.auto;
  String _selectedLocale = 'en_US';
  bool _showCursors = true;
  Timer? _bulkUpdateTimer;
  int _bulkUpdateCount = 0;
  OverlayEntry? _tooltipOverlay;

  late final TextEditingController _uriController;
  late final TextEditingController _tenantIdController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _viewModel = GanttViewModel(initialLocale: _selectedLocale, useLocalDatabase: true);
    _uriController = TextEditingController(text: 'https://gantt.legacy-automation.online');
    _tenantIdController = TextEditingController(text: 'legacy');
    _usernameController = TextEditingController(text: 'patrick');
    _passwordController = TextEditingController(text: 'password');
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _uriController.dispose();
    _tenantIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
    var taskDuration = task.end.difference(task.start);
    Duration newWindowDuration;

    // If the task is a milestone (zero duration), set a default window duration.
    if (taskDuration == Duration.zero) {
      newWindowDuration = const Duration(days: 1);
      taskDuration = newWindowDuration; // Use this for centering calculation
    } else {
      // For regular tasks, make the new window 3 times the duration for context.
      newWindowDuration = Duration(milliseconds: taskDuration.inMilliseconds * 3);
    }

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
      builder: (context) => DependencyManagerDialog(
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
      ContextMenuItem(
        caption: 'Convert to...',
        submenuBuilder: (context) async {
          final items = <ContextMenuItem>[];
          if (!task.isMilestone && !task.isSummary) {
            items.add(ContextMenuItem(
              caption: 'Standard Task',
              onTap: () => _viewModel.convertTaskType(task, 'task'),
            ));
          }
          if (!task.isMilestone) {
            items.add(ContextMenuItem(
              caption: 'Milestone',
              onTap: () => _viewModel.convertTaskType(task, 'milestone'),
            ));
          }
          if (!task.isSummary) {
            items.add(ContextMenuItem(
              caption: 'Summary Task',
              onTap: () => _viewModel.convertTaskType(task, 'summary'),
            ));
          }
          return items;
        },
      ),
      ContextMenuItem(
        caption: 'Edit...',
        onTap: () => _showEditTaskDialog(context, task),
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
                      caption: otherTask.name,
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
                      caption: otherTask.name,
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

  // --- User Presence UI ---
  List<Widget> _buildUserChips(BuildContext context, GanttViewModel vm) => vm.connectedUsers.entries.map((entry) {
        final userId = entry.key;
        final ghost = entry.value;
        final isFollowed = vm.followedUserId == userId;
        final color = _parseColor(ghost.userColor);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: GestureDetector(
            onTapDown: (details) => _showUserContextMenu(context, userId, details.globalPosition),
            child: Chip(
              avatar: CircleAvatar(
                backgroundColor: color,
                radius: 10,
                child: Text(
                  (ghost.userName ?? userId).substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              label: Text(
                ghost.userName ?? userId.substring(0, math.min(4, userId.length)),
                style: TextStyle(color: isFollowed ? color : null, fontWeight: isFollowed ? FontWeight.bold : null),
              ),
              backgroundColor: isFollowed ? color.withValues(alpha: 0.1) : null,
              side: isFollowed ? BorderSide(color: color, width: 2) : BorderSide.none,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      }).toList();

  void _showUserContextMenu(BuildContext context, String userId, Offset position) {
    showContextMenu(
      context: context,
      tapPosition: position,
      menuItems: [
        if (_viewModel.followedUserId == userId)
          ContextMenuItem(
            caption: 'Stop Following',
            onTap: () => _viewModel.setFollowedUser(null),
          )
        else
          ContextMenuItem(
            caption: 'Follow Cursor',
            onTap: () => _viewModel.setFollowedUser(userId),
          ),
      ],
    );
  }

  Color _parseColor(String? hexString) {
    if (hexString == null) return Colors.grey;
    try {
      return Color(int.parse(hexString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.grey;
    }
  }

  // --- Gantt Chart Customization Builders ---

  /// Returns a builder function for the timeline axis labels based on the
  /// format selected in the control panel.
  ///
  /// This demonstrates the `timelineAxisLabelBuilder` property, which gives you
  /// full control over how labels on the timeline are formatted.
  String Function(DateTime, Duration)? _getTimelineAxisLabelBuilder() {
    if (_selectedAxisFormat == TimelineAxisFormat.custom || _selectedAxisFormat == TimelineAxisFormat.auto) return null;

    switch (_selectedAxisFormat) {
      case TimelineAxisFormat.auto:
        return null; // The default behavior of the chart is auto-graduation.
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
        painter: CustomHeaderPainter(
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
            Text('Server Sync', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (vm.isSyncConnected)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Text('Connected', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () => vm.disconnectSync(),
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _uriController,
                    decoration: const InputDecoration(labelText: 'Server URI', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tenantIdController,
                    decoration: const InputDecoration(labelText: 'Tenant ID', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(labelText: 'User', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(labelText: 'Pass', isDense: true),
                          obscureText: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await vm.connectSync(
                          uri: _uriController.text,
                          tenantId: _tenantIdController.text,
                          username: _usernameController.text,
                          password: _passwordController.text,
                        );
                        _showSnackbar('Connected to Sync Server');
                      } catch (e) {
                        _showSnackbar('Connection Failed: $e');
                      }
                    },
                    child: const Text('Connect'),
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
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-seed Local Data'),
                  onPressed: () => vm.seedLocalDatabase(),
                ),
              ),
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
                const Text('Show Critical Path'),
                Switch(
                  value: vm.showCriticalPath,
                  onChanged: vm.setShowCriticalPath,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show Cursors'),
                Switch(
                  value: _showCursors,
                  onChanged: (val) => setState(() => _showCursors = val),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show Resource Histogram'),
                Switch(
                  value: vm.showResourceHistogram,
                  onChanged: (value) => vm.setShowResourceHistogram(value),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Enable Work Calendar'),
                Switch(
                  value: vm.enableWorkCalendar,
                  onChanged: (value) => vm.setEnableWorkCalendar(value),
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
                ButtonSegment(value: TimelineAxisFormat.auto, label: Text('Auto')),
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
    // We now use the live data from the view model.
    if (vm.data.isEmpty) {
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

    final exportData = vm.exportToJson();

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
  final GlobalKey<UnifiedDataGridState> _gridKey = GlobalKey<UnifiedDataGridState>();

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
          actions: [
            Consumer<GanttViewModel>(
              builder: (context, vm, child) =>
                  Row(mainAxisSize: MainAxisSize.min, children: _buildUserChips(context, vm)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Consumer<GanttViewModel>(
            builder: (context, vm, child) {
              final ganttTheme = _buildGanttTheme();
              // Update the format after the current frame is built to avoid calling notifyListeners during build.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                vm.updateResizeTooltipDateFormat(_getResizeTooltipDateFormat());
                // Attach scroll listeners after the first frame is built to ensure
                // the controllers are attached to their respective scroll views.
                // This prevents the "ScrollController not attached" error.
                vm.attachScrollListeners();
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

                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          LegacyGanttToolbar(
                            controller: vm.controller,
                            theme: ganttTheme,
                          ),
                          Expanded(
                              child: Row(
                            children: [
                              // Gantt Grid (Left Side)
                              // This is a custom widget for this example app that shows a data grid.
                              // It is synchronized with the Gantt chart via a shared ScrollController.
                              // This is a common pattern for building a complete Gantt chart UI.
                              SizedBox(
                                width: vm.gridWidth ?? constraints.maxWidth * 0.41,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) => UnifiedDataGrid<Map<String, dynamic>>(
                                          // Use a key that changes when data reloads to force a grid refresh.
                                          allowSorting: false,
                                          // Combine seedVersion (for full resets) with expansionSignature (for remote/local toggles).
                                          // This ensures the grid is recreated, respecting the new initialExpandedRowIds.
                                          key: ValueKey('local_grid_${vm.seedVersion}'),
                                          mode: DataGridMode.client,
                                          clientData: vm.flatGridData,
                                          toMap: (item) => item,
                                          rowIdKey: 'id',
                                          isTree: true,
                                          parentIdKey: 'parentId',
                                          isExpandedKey: 'isExpanded',
                                          rowHeightBuilder: (data) {
                                            final rowId = data['id'] as String;
                                            return (vm.rowMaxStackDepth[rowId] ?? 1) * vm.rowHeight;
                                          },
                                          onRowToggle: (rowId, _) => vm.toggleExpansion(rowId),
                                          initialExpandedRowIds:
                                              vm.gridData.where((p) => p.isExpanded).map((p) => p.id).toSet(),
                                          scrollController: vm.gridScrollController,
                                          headerHeight: _selectedAxisFormat == TimelineAxisFormat.custom ? 54.0 : 27.0,
                                          showFooter: false,
                                          allowFiltering: false, // Filtering can be enabled if desired.
                                          selectedRowId: vm.selectedRowId,
                                          columnDefs: [
                                            DataColumnDef(
                                              id: 'name',
                                              caption: 'Name',
                                              // Use flex to make the name column fill available space.
                                              flex: 1,
                                              isNameColumn: true,
                                              minWidth: 150,
                                            ),
                                            DataColumnDef(
                                              id: 'completion',
                                              caption: 'Completed %',
                                              width: 100,
                                              minWidth: 100,
                                              cellBuilder: (context, data) {
                                                final double? completion = data['completion'];
                                                if (completion == null) return const SizedBox.shrink();
                                                final percentage = (completion * 100).clamp(0, 100);
                                                final percentageText = '${percentage.toStringAsFixed(0)}%';
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                                                  child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      LinearProgressIndicator(
                                                        value: completion,
                                                        backgroundColor: Colors.grey.shade300,
                                                        color: Colors.blue,
                                                        minHeight: 20,
                                                      ),
                                                      Text(
                                                        percentageText,
                                                        style: TextStyle(
                                                          color: percentage > 50 ? Colors.white : Colors.black,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                            DataColumnDef(
                                              id: 'actions',
                                              caption: '',
                                              width: 56,
                                              minWidth: 56,
                                              cellBuilder: (context, data) {
                                                final bool isParent = data['parentId'] == null;
                                                final String rowId = data['id'];
                                                if (isParent) {
                                                  return PopupMenuButton<String>(
                                                    padding: EdgeInsets.zero,
                                                    icon: const Icon(Icons.more_vert, size: 16),
                                                    tooltip: 'Options',
                                                    onSelected: (value) {
                                                      if (value == 'add_line_item') {
                                                        vm.addLineItem(context, rowId);
                                                      } else if (value == 'delete_row') {
                                                        vm.deleteRow(rowId);
                                                      } else if (value == 'edit_task') {
                                                        vm.editParentTask(context, rowId);
                                                      } else if (value == 'edit_dependent_tasks') {
                                                        vm.editDependentTasks(context, rowId);
                                                      }
                                                    },
                                                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                                      const PopupMenuItem<String>(
                                                          value: 'add_line_item', child: Text('Add Line Item')),
                                                      const PopupMenuItem<String>(
                                                          value: 'edit_task', child: Text('Edit Task')),
                                                      const PopupMenuItem<String>(
                                                          value: 'edit_dependent_tasks',
                                                          child: Text('Edit Dependent Tasks')),
                                                      const PopupMenuDivider(),
                                                      const PopupMenuItem<String>(
                                                          value: 'delete_row', child: Text('Delete Row')),
                                                    ],
                                                  );
                                                } else {
                                                  return IconButton(
                                                    icon: const Icon(Icons.delete_outline, size: 18),
                                                    tooltip: 'Delete Row',
                                                    onPressed: () => vm.deleteRow(rowId),
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                          // Replicate the header buttons from the old GanttGrid.
                                          headerTrailingWidgets: [
                                            (context) => PopupMenuButton<String>(
                                                  padding: const EdgeInsets.only(right: 16.0),
                                                  icon: const Icon(Icons.more_vert, size: 16),
                                                  tooltip: 'More Options',
                                                  onSelected: (value) {
                                                    if (value == 'add_contact') {
                                                      vm.addContact(context);
                                                    } else if (value == 'edit_all_parents') {
                                                      vm.editAllParentTasks(context);
                                                    }
                                                  },
                                                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                                                    const PopupMenuItem<String>(
                                                      value: 'add_contact',
                                                      child: ListTile(
                                                          leading: Icon(Icons.person_add), title: Text('Add Contact')),
                                                    ),
                                                    const PopupMenuItem<String>(
                                                      value: 'edit_all_parents',
                                                      child: ListTile(
                                                          leading: Icon(Icons.edit),
                                                          title: Text('Edit All Parent Tasks')),
                                                    ),
                                                  ],
                                                )
                                          ],
                                        ),
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

                                          // Notify VM of the width so it can adjust scroll offset if needed (maintain visible date)
                                          vm.maintainScrollOffsetForWidth(ganttWidth);

                                          // The axis height is adjusted based on whether we are using the
                                          // default single-line header or the custom two-line header.
                                          final double axisHeight =
                                              _selectedAxisFormat == TimelineAxisFormat.custom ? 54.0 : 27.0;

                                          return SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            controller: vm.ganttHorizontalScrollController,
                                            child: SizedBox(
                                              width: ganttWidth,
                                              height: chartConstraints
                                                  .maxHeight, // Fix: Constrain height to viewport so internal scroll works
                                              child: LegacyGanttChartWidget(
                                                controller: vm.controller,
                                                loadingIndicatorType: vm.loadingIndicatorType,
                                                loadingIndicatorPosition: vm.loadingIndicatorPosition,
                                                syncClient: vm.syncClient,
                                                showCursors: _showCursors,
                                                showCriticalPath: vm.showCriticalPath,
                                                showResourceHistogram: vm.showResourceHistogram,
                                                workCalendar: vm.workCalendar,
                                                onTaskSecondaryTap: (task, position) =>
                                                    _showTaskContextMenu(context, task, position),
                                                onTaskLongPress: (task, position) =>
                                                    _showTaskContextMenu(context, task, position),
                                                onTaskHover: (task, globalPosition) {
                                                  // Show tooltip overlay
                                                  if (task == null) {
                                                    _tooltipOverlay?.remove();
                                                    _tooltipOverlay = null;
                                                    return;
                                                  }

                                                  // Format content
                                                  final sb = StringBuffer();
                                                  sb.writeln(task.name);
                                                  sb.writeln('Start: ${task.start.toString().substring(0, 16)}');
                                                  sb.writeln('End: ${task.end.toString().substring(0, 16)}');

                                                  if (vm.showCriticalPath) {
                                                    final stats = vm.cpmStats[task.id];
                                                    if (stats != null) {
                                                      sb.writeln('');
                                                      sb.writeln('Critical: ${stats.float <= 0 ? "YES" : "NO"}');
                                                      sb.writeln(
                                                          'Float: ${Duration(minutes: stats.float).inDays} days');

                                                      if (vm.totalStartDate != null) {
                                                        final esDate =
                                                            vm.totalStartDate!.add(Duration(minutes: stats.earlyStart));
                                                        final lfDate =
                                                            vm.totalStartDate!.add(Duration(minutes: stats.lateFinish));
                                                        final dateFormat = DateFormat('MM/dd HH:mm');
                                                        sb.writeln('Early Start: ${dateFormat.format(esDate)}');
                                                        sb.writeln('Late Finish: ${dateFormat.format(lfDate)}');
                                                      }
                                                    }
                                                  }

                                                  if (_tooltipOverlay == null) {
                                                    _tooltipOverlay = OverlayEntry(
                                                        builder: (context) => Positioned(
                                                              left: globalPosition.dx + 10,
                                                              top: globalPosition.dy + 10,
                                                              child: Material(
                                                                elevation: 4,
                                                                color: Colors.black87,
                                                                borderRadius: BorderRadius.circular(4),
                                                                child: Padding(
                                                                  padding: const EdgeInsets.all(8.0),
                                                                  child: Text(
                                                                    sb.toString().trim(),
                                                                    style: const TextStyle(
                                                                        color: Colors.white, fontSize: 12),
                                                                  ),
                                                                ),
                                                              ),
                                                            ));
                                                    Overlay.of(context).insert(_tooltipOverlay!);
                                                  } else {
                                                    // Rebuild/reposition if needed, but for simplicity we assume
                                                    // the overlay might need to be removed and re-added or we use a sophisticated tooltip.
                                                    // For this quick fix, let's just remove and re-add to update position/content
                                                    _tooltipOverlay?.remove();
                                                    _tooltipOverlay = OverlayEntry(
                                                        builder: (context) => Positioned(
                                                              left: globalPosition.dx + 10,
                                                              top: globalPosition.dy + 10,
                                                              child: Material(
                                                                elevation: 4,
                                                                color: Colors.black87,
                                                                borderRadius: BorderRadius.circular(4),
                                                                child: Padding(
                                                                  padding: const EdgeInsets.all(8.0),
                                                                  child: Text(
                                                                    sb.toString().trim(),
                                                                    style: const TextStyle(
                                                                        color: Colors.white, fontSize: 12),
                                                                  ),
                                                                ),
                                                              ),
                                                            ));
                                                    Overlay.of(context).insert(_tooltipOverlay!);
                                                  }
                                                },

                                                taskGrouper: (task) => task.rowId,
                                                // --- Custom Builders ---
                                                timelineAxisLabelBuilder: _getTimelineAxisLabelBuilder(),
                                                timelineAxisHeaderBuilder:
                                                    _selectedAxisFormat == TimelineAxisFormat.custom
                                                        ? _buildCustomTimelineHeader
                                                        : null,

                                                // --- Data and Layout ---
                                                // data: vm.ganttTasks, // Removed: Controlled by vm.controller
                                                // dependencies: vm.dependencies, // Removed: Controlled by vm.controller
                                                // conflictIndicators: vm.conflictIndicators, // Removed: Controlled by vm.controller
                                                visibleRows: vm.visibleGanttRows, // This should be correct
                                                rowHeight: 27.0,
                                                rowMaxStackDepth: vm.rowMaxStackDepth,
                                                // The axis height is adjusted based on whether we are using the
                                                // default single-line header or the custom two-line header.
                                                axisHeight: axisHeight,

                                                // --- Scroll Controllers and Syncing ---
                                                // This is the key to synchronizing the vertical scroll between the
                                                // left-side grid and the right-side chart. We pass the grid's
                                                // controller here for the internal view model to drive.
                                                scrollController: vm.gridScrollController,
                                                onRowRequestVisible: (rowId) {
                                                  vm.ensureRowIsVisible(rowId);
                                                  // Find parent and expand in grid
                                                  final parent = vm.gridData
                                                      .firstWhereOrNull((p) => p.children.any((c) => c.id == rowId));
                                                  if (parent != null) {
                                                    _gridKey.currentState?.setRowExpansion(parent.id, true);
                                                  }
                                                },
                                                focusedTaskId: vm.focusedTaskId,
                                                onFocusChange: vm.setFocusedTaskId,
                                                horizontalScrollController: vm.ganttHorizontalScrollController,

                                                // --- Date Range ---
                                                // These define the currently visible time window.
                                                // gridMin: vm.visibleStartDate?.millisecondsSinceEpoch.toDouble(), // Removed: Controlled by vm.controller
                                                // gridMax: vm.visibleEndDate?.millisecondsSinceEpoch.toDouble(), // Removed: Controlled by vm.controller
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
                                                  _bulkUpdateCount++;
                                                  _bulkUpdateTimer?.cancel();
                                                  _bulkUpdateTimer = Timer(const Duration(milliseconds: 100), () {
                                                    if (_bulkUpdateCount == 1) {
                                                      _showSnackbar('Updated ${task.name}');
                                                    } else {
                                                      _showSnackbar('Updated $_bulkUpdateCount tasks');
                                                    }
                                                    _bulkUpdateCount = 0;
                                                  });
                                                },
                                                onTaskDoubleClick: (task) {
                                                  _handleSnapToTask(task);
                                                },
                                                // This callback is triggered when a user clicks on an empty space,
                                                // allowing for the creation of new tasks.
                                                onEmptySpaceClick: (rowId, time) =>
                                                    vm.handleEmptySpaceClick(context, rowId, time),
                                                onTaskDrawEnd: vm.handleTaskDrawEnd,
                                                onPressTask: (task) {
                                                  vm.setFocusedTaskId(task.id);
                                                  _showSnackbar('Selected task: ${task.name}');
                                                },

                                                onDependencyAdd: (dependency) => vm.addDependencyObject(dependency),

                                                // --- Theming and Styling ---
                                                theme: ganttTheme,
                                                weekendColor: Colors.grey.withValues(alpha: 0.1),
                                                resizeTooltipDateFormat: _getResizeTooltipDateFormat(),
                                                resizeTooltipBackgroundColor: Colors.purple,
                                                resizeHandleWidth: vm.resizeHandleWidth,
                                                resizeTooltipFontColor: Colors.white,
                                                focusedTaskResizeHandleWidth: vm.resizeHandleWidth,

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
                                                                builder: (context) => MouseRegion(
                                                                  cursor: SystemMouseCursors.click,
                                                                  child: GestureDetector(
                                                                    behavior: HitTestBehavior.opaque,
                                                                    onPanStart: (_) {}, // Consumes the drag gesture
                                                                    onPanUpdate: (_) {},
                                                                    child: IconButton(
                                                                      padding: EdgeInsets.zero,
                                                                      icon: Icon(Icons.more_vert,
                                                                          color: textColor, size: 18),
                                                                      tooltip: 'Task Options',
                                                                      onPressed: () {
                                                                        final RenderBox button =
                                                                            context.findRenderObject() as RenderBox;
                                                                        final Offset offset =
                                                                            button.localToGlobal(Offset.zero);
                                                                        final tapPosition =
                                                                            offset.translate(button.size.width, 0);
                                                                        _showTaskContextMenu(
                                                                            context, task, tapPosition);
                                                                      },
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      );
                                                    }),
                                                  );
                                                },
                                                // This is the new builder for the floating resize handles.
                                                focusedTaskResizeHandleBuilder: (task, part, internalVm, handleWidth) {
                                                  final icon = part == TaskPart.startHandle
                                                      ? Icons.chevron_left
                                                      : Icons.chevron_right;

                                                  // Using a GestureDetector to make the handle draggable.
                                                  // The onPanStart call directly triggers the resize logic
                                                  // in the view model.
                                                  return GestureDetector(
                                                    key: ValueKey(handleWidth), // Pass width for positioning
                                                    onPanStart: (details) {
                                                      internalVm.onPanStart(
                                                        DragStartDetails(
                                                          sourceTimeStamp: details.sourceTimeStamp,
                                                          globalPosition: details.globalPosition,
                                                          localPosition: details.localPosition,
                                                        ),
                                                        // We explicitly tell the view model which task and part
                                                        // is being dragged, bypassing the need for hit-testing.
                                                        overrideTask: task,
                                                        overridePart: part,
                                                      );
                                                    },
                                                    onPanUpdate: internalVm.onPanUpdate,
                                                    onPanEnd: internalVm.onPanEnd,
                                                    child: Container(
                                                      width: handleWidth,
                                                      height: vm.rowHeight, // Ensure container has height for alignment
                                                      color: Colors.transparent, // Make the gesture area larger
                                                      child: Center(
                                                        // Center the icon
                                                        child: Icon(
                                                          icon,
                                                          size: handleWidth,
                                                          color: ganttTheme.barColorSecondary,
                                                        ),
                                                      ),
                                                    ),
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
                                          tasks: [...vm.ganttTasks, ...vm.conflictIndicators]
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
                          ))
                        ]);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ));

  Future<void> _showEditTaskDialog(BuildContext context, LegacyGanttTask task) async {
    await showDialog(
      context: context,
      builder: (context) => TaskDialog(
        task: task,
        onSubmit: (updatedTask) {
          _viewModel.updateTask(updatedTask);
        },
        defaultStartTime: const TimeOfDay(hour: 9, minute: 0),
        defaultEndTime: const TimeOfDay(hour: 17, minute: 0),
      ),
    );
  }
}
