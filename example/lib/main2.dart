import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_timeline_scrubber/legacy_timeline_scrubber.dart' as scrubber;

void main() => runApp(const SimpleGanttApp());

class SimpleGanttApp extends StatelessWidget {
  const SimpleGanttApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Simple Gantt Chart Example',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const SimpleGanttView(),
      );
}

class SimpleGanttView extends StatefulWidget {
  const SimpleGanttView({super.key});

  @override
  State<SimpleGanttView> createState() => _SimpleGanttViewState();
}

class _SimpleGanttViewState extends State<SimpleGanttView> {
  // Define the data directly in the state.
  // In a real app, you would likely fetch this from an API in initState.
  late List<LegacyGanttTask> _tasks;
  late List<LegacyGanttTaskDependency> _dependencies;

  // Define the total and visible date ranges for the chart.
  // The total range defines the full scrollable area for the scrubber.
  final DateTime _totalStartDate = DateTime(2024, 5, 15);
  final DateTime _totalEndDate = DateTime(2024, 7, 15);
  // The visible range is what the user sees in the main chart.
  late DateTime _visibleStartDate;
  late DateTime _visibleEndDate;

  // Scroll controller to synchronize the row headers and the chart.
  final ScrollController _scrollController = ScrollController();

  // Horizontal scroll controller to link the scrubber and the chart.
  final ScrollController _horizontalScrollController = ScrollController();

  // Data for the row headers. In a real app, this might come from the same
  // source as your tasks.
  final Map<String, String> _rowHeaders = {
    'project_a': 'Project A',
    'resource_1': 'Developer 1',
    'resource_2': 'Developer 2',
  };

  @override
  void initState() {
    super.initState();
    _visibleStartDate = DateTime(2024, 6, 1);
    _visibleEndDate = DateTime(2024, 6, 30);
    _initializeSampleData();
  }

  void _initializeSampleData() {
    _tasks = [
      // A summary task that spans over its children.
      LegacyGanttTask(
        id: 'summary_1',
        rowId: 'project_a',
        name: 'Project A Summary',
        start: DateTime(2024, 6, 5),
        end: DateTime(2024, 6, 15),
        isSummary: true,
        color: Colors.amber,
      ),
      // A regular task.
      LegacyGanttTask(
        id: 'task_1',
        rowId: 'resource_1',
        name: 'Task 1 - Design',
        start: DateTime(2024, 6, 5),
        end: DateTime(2024, 6, 8),
        completion: 0.75,
      ),
      // Another regular task.
      LegacyGanttTask(
        id: 'task_2',
        rowId: 'resource_2',
        name: 'Task 2 - Implementation',
        start: DateTime(2024, 6, 9),
        end: DateTime(2024, 6, 15),
      ),
    ];

    _dependencies = [
      // A standard dependency between two tasks.
      const LegacyGanttTaskDependency(
        predecessorTaskId: 'task_1',
        successorTaskId: 'task_2',
        type: DependencyType.finishToStart,
      ),
      // A "contained" dependency for the summary task. This creates a
      // background decoration that visually groups the summary bar with its
      // child rows. The successor task ID is arbitrary for this type.
      const LegacyGanttTaskDependency(
        predecessorTaskId: 'summary_1',
        successorTaskId: 'task_1', // Can be any task ID
        type: DependencyType.contained,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Simple Gantt Chart'),
        ),
        body: Row(
          children: [
            // --- Left side: Row Headers ---
            SizedBox(
              width: 120, // Adjust width as needed
              child: _RowHeader(
                scrollController: _scrollController,
                rowHeight: 32.0,
                axisHeight: 27.0, // Should match axisHeight in Gantt chart
                rows: const [
                  LegacyGanttRow(id: 'project_a'),
                  LegacyGanttRow(id: 'resource_1'),
                  LegacyGanttRow(id: 'resource_2'),
                ],
                rowHeaders: _rowHeaders,
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // --- Right side: Gantt Chart ---
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalDuration = _totalEndDate.difference(_totalStartDate);
                        final visibleDuration = _visibleEndDate.difference(_visibleStartDate);
                        final ganttWidth =
                            (totalDuration.inMicroseconds / visibleDuration.inMicroseconds) * constraints.maxWidth;

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _horizontalScrollController,
                          child: SizedBox(
                            width: ganttWidth,
                            child: LegacyGanttChartWidget(
                              // --- Core Data ---
                              data: _tasks,
                              dependencies: _dependencies,
                              visibleRows: const [
                                LegacyGanttRow(id: 'project_a'),
                                LegacyGanttRow(id: 'resource_1'),
                                LegacyGanttRow(id: 'resource_2'),
                              ],
                              // A map defining the max number of overlapping tasks per row.
                              rowMaxStackDepth: const {
                                'project_a': 1,
                                'resource_1': 1,
                                'resource_2': 1,
                              },
                              rowHeight: 32.0,
                              axisHeight: 27.0,

                              // --- Scroll Controller for synchronization ---
                              scrollController: _scrollController,

                              // --- Date Range ---
                              gridMin: _visibleStartDate.millisecondsSinceEpoch.toDouble(),
                              gridMax: _visibleEndDate.millisecondsSinceEpoch.toDouble(),
                              totalGridMin: _totalStartDate.millisecondsSinceEpoch.toDouble(),
                              totalGridMax: _totalEndDate.millisecondsSinceEpoch.toDouble(),

                              // --- Interactivity ---
                              enableDragAndDrop: true,
                              enableResize: true,
                              onTaskUpdate: (task, newStart, newEnd) {
                                // Handle task updates by finding the task and updating its dates.
                                setState(() {
                                  // It's crucial to find the task in the current state (_tasks)
                                  // and update it, rather than using the 'task' parameter directly.
                                  final index =
                                      _tasks.indexWhere((t) => t.id == task.id); // Use task.id to find the right one
                                  if (index != -1) {
                                    // Create a new list from the old one.
                                    final newTasks = List<LegacyGanttTask>.from(_tasks);
                                    // Update the task in the new list.
                                    newTasks[index] = newTasks[index].copyWith(start: newStart, end: newEnd);
                                    // Replace the old list with the new one.
                                    _tasks = newTasks;
                                  }
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Updated ${task.name}')),
                                );
                              },
                              onTaskDoubleClick: (task) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Double-tapped on ${task.name}')),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // --- Timeline Scrubber ---
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    color: Theme.of(context).cardColor,
                    child: scrubber.LegacyGanttTimelineScrubber(
                      totalStartDate: _totalStartDate,
                      totalEndDate: _totalEndDate,
                      visibleStartDate: _visibleStartDate,
                      visibleEndDate: _visibleEndDate,
                      onWindowChanged: (newStart, newEnd, _) {
                        setState(() {
                          _visibleStartDate = newStart;
                          _visibleEndDate = newEnd;
                        });

                        // After the UI has rebuilt with the new visible range, we need to
                        // programmatically scroll the Gantt chart to the correct position.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_horizontalScrollController.hasClients) {
                            final totalDuration = _totalEndDate.difference(_totalStartDate).inMilliseconds;
                            if (totalDuration <= 0) return;

                            final position = _horizontalScrollController.position;
                            final totalGanttWidth = position.maxScrollExtent + position.viewportDimension;
                            if (totalGanttWidth <= 0) return;

                            // Calculate the offset from the total start date to the new visible start date.
                            final startOffsetMs = newStart.difference(_totalStartDate).inMilliseconds;

                            // Calculate the new scroll position based on the ratio of the offsets.
                            final newScrollOffset = (startOffsetMs / totalDuration) * totalGanttWidth;

                            // Jump to the new position.
                            _horizontalScrollController.jumpTo(
                              newScrollOffset.clamp(0.0, position.maxScrollExtent),
                            );
                          }

                          // Reset the flag after the update is complete to allow chart scrolling
                          // to update the scrubber again.
                        });
                      },
                      tasks: _tasks
                          .map((t) => scrubber.LegacyGanttTask(
                                id: t.id,
                                rowId: t.rowId,
                                start: t.start,
                                end: t.end,
                                color: t.color,
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// A simple widget to display row headers synchronized with the Gantt chart.
class _RowHeader extends StatelessWidget {
  final ScrollController scrollController;
  final List<LegacyGanttRow> rows;
  final double rowHeight;
  final double axisHeight;
  final Map<String, String> rowHeaders;

  const _RowHeader({
    required this.scrollController,
    required this.rows,
    required this.rowHeight,
    required this.axisHeight,
    required this.rowHeaders,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(height: axisHeight), // Space for the timeline header
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: rows.length,
              itemBuilder: (context, index) => Container(
                height: rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Text(rowHeaders[rows[index].id] ?? ''),
              ),
            ),
          ),
        ],
      );
}
