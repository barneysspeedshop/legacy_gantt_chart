import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import '../../services/gantt_natural_language_service.dart';
import '../../view_models/gantt_view_model.dart';
import '../../data/local/local_gantt_repository.dart';
import 'package:collection/collection.dart';

class GanttAssistantWidget extends StatefulWidget {
  final GanttNaturalLanguageService service;
  final GanttViewModel viewModel;

  const GanttAssistantWidget({
    super.key,
    required this.service,
    required this.viewModel,
  });

  @override
  State<GanttAssistantWidget> createState() => _GanttAssistantWidgetState();
}

class _GanttAssistantWidgetState extends State<GanttAssistantWidget> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _apiKeyController =
      TextEditingController(text: const String.fromEnvironment('GEMINI_API_KEY'));
  bool _isLoading = false;
  String? _feedback;
  bool _feedbackIsError = false;

  // -------------------------------------------------------------------------
  // Submit / dispatch
  // -------------------------------------------------------------------------

  Future<void> _handleSubmit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _setFeedback('Please provide a Gemini API Key.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _feedback = null;
      _feedbackIsError = false;
    });

    try {
      final command = await widget.service.parse(input, apiKey: apiKey);
      if (command != null) {
        await _dispatch(command);
        _controller.clear();
        widget.service.clearConversation();
      } else {
        _setFeedback('Could not understand command.', isError: true);
      }
    } catch (e) {
      _setFeedback('Error: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _setFeedback(String message, {required bool isError}) {
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  Future<void> _dispatch(GanttCommand command) async {
    if (command is ClarificationRequiredCommand) {
      _setFeedback('I need more information: ${command.question}', isError: false);
      return;
    }

    if (command is HelpCommand) {
      return _executeHelp(command);
    }

    if (command is ScheduleQueryCommand) {
      final text = await _executeQuery(command);
      _setFeedback(text, isError: false);
      return;
    }

    // Functional commands - show success message after completion
    if (command is AddTasksCommand) {
      await _executeAddTasks(command);
    } else if (command is UpdateTaskCommand) {
      await _executeUpdateTask(command);
    } else if (command is TransposeTasksCommand) {
      await _executeTransposeTasks(command);
    } else if (command is AnchorScheduleCommand) {
      await _executeAnchorSchedule(command);
    } else if (command is DeleteTasksCommand) {
      await _executeDeleteTasks(command);
    } else if (command is ReassignTasksCommand) {
      await _executeReassignTasks(command);
    } else if (command is AddDependencyCommand) {
      await _executeAddDependency(command);
    } else if (command is CompressScheduleCommand) {
      await _executeCompressSchedule(command);
    } else if (command is ShiftWorkingDaysCommand) {
      await _executeShiftWorkingDays(command);
    } else if (command is PackTasksCommand) {
      await _executePackTasks(command);
    } else if (command is MirrorScheduleCommand) {
      await _executeMirrorSchedule(command);
    }

    _setFeedback('✓ ${command.description}', isError: false);
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.all(8.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Gantt Assistant', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Gemini API Key',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'e.g., "Delete all tasks for person 0"',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _handleSubmit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _isLoading ? null : _handleSubmit,
                  ),
                ],
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 8),
                Text(
                  _feedback!,
                  style: TextStyle(
                    color: _feedbackIsError ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Resolve resource IDs from a list of resource name strings.
  Set<String> _resolveResourceIds(List<String> resourceNames) {
    final lower = resourceNames.map((r) => r.toLowerCase()).toSet();
    return widget.viewModel.localResources
        .where((r) => lower.contains(r.name?.toLowerCase() ?? '') || lower.contains(r.id.toLowerCase()))
        .map((r) => r.id)
        .toSet();
  }

  /// Filter tasks by resource names (and optional task name)
  Future<void> _executeHelp(HelpCommand command) async {
    final topic = command.topic.toLowerCase();
    final helpMap = {
      'add': '• **Add**: "Add 3 tasks to Person A starting next Monday"\n'
          'Use this to create new tasks, milestones, or summaries.',
      'update': '• **Update**: "Mark task 0-2 as 50% done" or "Change color of Job 1 to red"\n'
          'Change completion, colors, notes, or dates of existing tasks.',
      'move': '• **Move/Shift**: "Shift Task A after Task B" or "Move Job 2 right by 3 days"\n'
          'Transposes tasks in time, either by an offset or relative to another task.',
      'transpose': '• **Move/Shift**: "Shift Task A after Task B" or "Move Job 2 right by 3 days"\n'
          'Transposes tasks in time, either by an offset or relative to another task.',
      'shift': '• **Move/Shift**: "Shift Task A after Task B" or "Move Job 2 right by 3 days"\n'
          'Transposes tasks in time, either by an offset or relative to another task.',
      'anchor': '• **Anchor**: "Shift everything to start Jan 1 2026"\n'
          'Moves an entire group of tasks (or the whole schedule) to a new start date.',
      'delete': '• **Delete**: "Delete all tasks for Person 0" or "Remove the review task"\n'
          'Removes tasks or milestones. "All tasks" includes milestones and summaries.',
      'reassign': '• **Reassign**: "Move Person 0\'s tasks to Person 1"\n'
          'Moves tasks from one resource/person to another.',
      'link': '• **Link (Dependency)**: "Make Task B depend on Task A"\n'
          'Creates a logical link between tasks (FS, SS, FF, SF).',
      'dependency': '• **Link (Dependency)**: "Make Task B depend on Task A"\n'
          'Creates a logical link between tasks (FS, SS, FF, SF).',
      'compress': '• **Compress**: "Compress the schedule by 50%"\n'
          'Scales the duration of the schedule for specific resources or the whole project.',
      'working days': '• **Shift Working Days**: "Shift Job 2 right by 5 working days"\n'
          'Moves tasks while skipping weekends.',
      'pack': '• **Pack**: "Remove gaps between Job 1\'s tasks"\n'
          'Squeezes tasks together to eliminate idle time.',
      'mirror': '• **Mirror**: "Flip the schedule to end on March 31"\n'
          'Reverses the schedule so it ends precisely on a target date.',
      'query': '• **Query**: "Do I have any overlaps?" or "How many days of work for Person 0?"\n'
          'Ask questions about the current state of the Gantt chart.',
    };

    setState(() {
      _feedbackIsError = false;
      if (topic == 'all' || !helpMap.containsKey(topic)) {
        _feedback = 'Topic: ${command.topic}\n\n'
            'I can help you manage your Gantt chart with these natural language commands:\n'
            '${helpMap.values.join('\n')}';
      } else {
        _feedback = 'Help: ${command.topic}\n\n${helpMap[topic]}';
      }
    });
  }

  List<LegacyGanttTask> _filterTasks({
    required List<String> resourceNames,
    String? taskName,
    bool includeAllIfNoResource = true,
  }) {
    final vm = widget.viewModel;
    final lowerNames = resourceNames.map((n) => n.toLowerCase()).toList();
    final resourceIds = _resolveResourceIds(resourceNames);
    final lowerSearch = taskName?.toLowerCase();

    // Check if the search term explicitly means "everything"
    final isExplicitAll = lowerSearch == 'all' ||
        lowerSearch == 'everything' ||
        (lowerSearch != null && lowerSearch.contains('all tasks'));

    return vm.allTasks.where((t) {
      final tName = t.name?.toLowerCase() ?? '';
      final tId = t.id.toLowerCase();

      // 1. Resource Match:
      // A task matches if its rowId matches a resolved resource ID,
      // OR if its rowId itself contains any segment from resourceNames.
      // If isExplicitAll is true, we allow everything regardless of resourceNames.
      bool matchesResource = (resourceNames.isEmpty && (includeAllIfNoResource || isExplicitAll)) ||
          resourceIds.contains(t.rowId) ||
          lowerNames.any((n) => t.rowId.toLowerCase().contains(n));

      // 2. Search Match:
      // If taskName is provided, the task name or ID must contain it.
      bool matchesSearch = lowerSearch == null || isExplicitAll;
      if (lowerSearch != null && !isExplicitAll) {
        final cleanSearch = lowerSearch.replaceAll('task', '').trim();
        if (cleanSearch.isEmpty) {
          matchesSearch = true; // "task" / "tasks" acts as a wildcard within the resource scope
        } else {
          matchesSearch = tName.contains(lowerSearch) ||
              tId.contains(lowerSearch) ||
              (cleanSearch.isNotEmpty && (tName.contains(cleanSearch) || tId.contains(cleanSearch)));
        }
      }

      // 3. Fallback:
      // If it failed to match the resource filter but could match one of the task filters directly.
      if (!matchesResource && resourceNames.isNotEmpty && lowerSearch == null) {
        matchesResource = lowerNames.any((n) {
          final cleanN = n.replaceAll('task', '').replaceAll('all', '').trim();
          if (cleanN.isEmpty || n == 'all' || n == 'everything') return true;
          return tName.contains(n) ||
              tId.contains(n) ||
              (cleanN.isNotEmpty && (tName.contains(cleanN) || tId.contains(cleanN)));
        });
      }

      return matchesResource && matchesSearch;
    }).toList();
  }

  /// Recursively collect a task and all its children.
  Set<LegacyGanttTask> _withChildren(Iterable<LegacyGanttTask> seeds) {
    final vm = widget.viewModel;
    final result = <LegacyGanttTask>{};
    void add(LegacyGanttTask t) {
      if (result.add(t)) {
        vm.allTasks.where((c) => c.parentId == t.id).forEach(add);
      }
    }

    seeds.forEach(add);
    return result;
  }

  /// Add [days] working days (Mon–Fri) to [date].
  DateTime _addWorkingDays(DateTime date, int days) {
    final step = days >= 0 ? 1 : -1;
    var remaining = days.abs();
    var current = date;
    while (remaining > 0) {
      current = current.add(Duration(days: step));
      if (current.weekday != DateTime.saturday && current.weekday != DateTime.sunday) {
        remaining--;
      }
    }
    return current;
  }

  // -------------------------------------------------------------------------
  // Phase 1 — Write executors
  // -------------------------------------------------------------------------

  Future<void> _executeAddTasks(AddTasksCommand command) async {
    final vm = widget.viewModel;
    final startDate = command.startDate ?? vm.controller.visibleStartDate;
    final endDate = command.endDate ?? startDate.add(const Duration(days: 1));

    for (final name in command.resourceNames) {
      var resource = vm.localResources.firstWhere(
        (r) => r.name?.toLowerCase() == name.toLowerCase(),
        orElse: () => LocalResource(id: 'res-${DateTime.now().millisecondsSinceEpoch}-${name.hashCode}', name: name),
      );
      if (!vm.localResources.contains(resource)) {
        await vm.addResources([resource]);
      }
      for (int i = 0; i < command.count; i++) {
        final task = LegacyGanttTask(
          id: 'task-${DateTime.now().millisecondsSinceEpoch}-$i',
          rowId: resource.id,
          name: 'New Task $i',
          start: startDate,
          end: endDate,
          isMilestone: command.taskType == 'milestone',
          isSummary: command.taskType == 'summary',
        );
        await vm.addTask(task);
      }
    }
  }

  Future<void> _executeUpdateTask(UpdateTaskCommand command) async {
    final vm = widget.viewModel;
    final matchingTasks = _filterTasks(resourceNames: command.resourceNames, taskName: command.taskName);

    final updated = matchingTasks.map((task) {
      var completion = task.completion;
      var notes = task.notes;
      var color = task.color;
      var startDate = task.start;
      var endDate = task.end;
      var load = task.load;

      if (command.updates.containsKey('completion')) {
        completion = (command.updates['completion'] as num).toDouble();
      }
      if (command.updates.containsKey('notes')) {
        notes = command.updates['notes'] as String?;
      }
      if (command.updates.containsKey('color')) {
        final raw = (command.updates['color'] as String? ?? '').replaceAll('#', '');
        if (raw.isNotEmpty) {
          try {
            final argb = raw.length == 6 ? 'ff$raw' : raw;
            color = Color(int.parse(argb, radix: 16));
          } catch (_) {}
        }
      }
      if (command.updates.containsKey('startDate')) {
        startDate = DateTime.tryParse(command.updates['startDate'] as String? ?? '') ?? startDate;
      }
      if (command.updates.containsKey('endDate')) {
        endDate = DateTime.tryParse(command.updates['endDate'] as String? ?? '') ?? endDate;
      }
      if (command.updates.containsKey('load')) {
        load = (command.updates['load'] as num).toDouble();
      }
      return task.copyWith(
          completion: completion, notes: notes, color: color, start: startDate, end: endDate, load: load);
    }).toList();

    await vm.updateTasksBulk(updated);
  }

  Future<void> _executeTransposeTasks(TransposeTasksCommand command) async {
    final vm = widget.viewModel;
    final matching = _filterTasks(
        resourceNames: command.resourceNames,
        taskName: command.taskName,
        includeAllIfNoResource: command.resourceNames.isEmpty);
    if (matching.isEmpty) {
      throw Exception('Source tasks matching "${command.taskName ?? command.resourceNames.join(', ')}" not found.');
    }

    final toUpdate = _withChildren(matching);
    Duration? offset = command.offset;

    // Resolve target date if specified
    DateTime? targetBaseDate = command.targetDate;
    if (command.targetTaskName != null) {
      final search = command.targetTaskName!.toLowerCase();
      final targetTask = vm.allTasks.firstWhereOrNull(
          (t) => t.name?.toLowerCase().contains(search) == true || t.id.toLowerCase().contains(search) == true);
      if (targetTask != null) {
        if (command.relativeSide == 'before') {
          targetBaseDate = targetTask.start;
        } else if (command.relativeSide == 'after') {
          targetBaseDate = targetTask.end;
        } else {
          targetBaseDate = targetTask.start;
        }
      } else {
        throw Exception('Target task "${command.targetTaskName}" (searched as "$search") not found.');
      }
    }

    if (targetBaseDate != null) {
      if (command.relativeSide == 'before') {
        // Move so the LATEST of matching tasks ends at targetBaseDate
        final latestMatching = matching.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
        offset = targetBaseDate.difference(latestMatching);
      } else {
        // Move so the EARLIEST of matching tasks starts at targetBaseDate
        final earliestMatching = matching.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b);
        offset = targetBaseDate.difference(earliestMatching);
      }
    }

    if (offset == null || offset == Duration.zero) return;

    final updated = toUpdate.map((t) => t.copyWith(start: t.start.add(offset!), end: t.end.add(offset))).toList();
    await vm.updateTasksBulk(updated);
  }

  Future<void> _executeAnchorSchedule(AnchorScheduleCommand command) async {
    final vm = widget.viewModel;
    final candidates =
        command.resourceNames.isEmpty ? vm.allTasks.toList() : _filterTasks(resourceNames: command.resourceNames);

    if (candidates.isEmpty) {
      throw Exception('No tasks found matching "${command.resourceNames.join(', ')}".');
    }

    DateTime? targetDate = command.targetDate;
    if (command.targetTaskName != null) {
      final search = command.targetTaskName!.toLowerCase();
      final targetTask = vm.allTasks.firstWhereOrNull(
          (t) => t.name?.toLowerCase().contains(search) == true || t.id.toLowerCase().contains(search) == true);
      if (targetTask != null) {
        if (command.relativeSide == 'before') {
          targetDate = targetTask.start;
        } else if (command.relativeSide == 'after') {
          targetDate = targetTask.end;
        } else {
          targetDate = targetTask.start;
        }
      } else {
        throw Exception('Target task "${command.targetTaskName}" (searched as "$search") not found.');
      }
    }

    if (targetDate == null) return;

    final earliest = candidates.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b);

    final Duration offset;
    if (command.relativeSide == 'before') {
      // Move so the LATEST candidate ends at targetDate
      final latest = candidates.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
      offset = targetDate.difference(latest);
    } else {
      // Move so the EARLIEST candidate starts at targetDate
      offset = targetDate.difference(earliest);
    }

    if (offset == Duration.zero) return;

    final allShifted = vm.allTasks.map((t) => t.copyWith(start: t.start.add(offset), end: t.end.add(offset))).toList();
    await vm.updateTasksBulk(allShifted);
  }

  Future<void> _executeDeleteTasks(DeleteTasksCommand command) async {
    final vm = widget.viewModel;
    final matching =
        _filterTasks(resourceNames: command.resourceNames, taskName: command.taskName, includeAllIfNoResource: false);
    final toDelete = _withChildren(matching).toList();
    await vm.deleteTasksBulk(toDelete);
  }

  Future<void> _executeReassignTasks(ReassignTasksCommand command) async {
    final vm = widget.viewModel;
    final matching = _filterTasks(resourceNames: command.fromResourceNames, taskName: command.taskName);
    if (matching.isEmpty) return;

    // Find target resource
    final targetRes =
        vm.localResources.firstWhereOrNull((r) => r.name?.toLowerCase() == command.toResourceName.toLowerCase());
    if (targetRes == null) {
      throw Exception('Resource "${command.toResourceName}" not found.');
    }

    final updated = matching.map((t) => t.copyWith(rowId: targetRes.id, resourceId: targetRes.id)).toList();
    await vm.updateTasksBulk(updated);
  }

  Future<void> _executeAddDependency(AddDependencyCommand command) async {
    final vm = widget.viewModel;
    final pred = vm.allTasks
        .firstWhereOrNull((t) => t.name?.toLowerCase().contains(command.predecessorTaskName.toLowerCase()) == true);
    final succ = vm.allTasks
        .firstWhereOrNull((t) => t.name?.toLowerCase().contains(command.successorTaskName.toLowerCase()) == true);

    if (pred == null) throw Exception('Task "${command.predecessorTaskName}" not found.');
    if (succ == null) throw Exception('Task "${command.successorTaskName}" not found.');

    final depType = {
          'FS': DependencyType.finishToStart,
          'SS': DependencyType.startToStart,
          'FF': DependencyType.finishToFinish,
          'SF': DependencyType.startToFinish,
        }[command.dependencyType.toUpperCase()] ??
        DependencyType.finishToStart;

    await vm.addDependencies([
      LegacyGanttTaskDependency(
        predecessorTaskId: pred.id,
        successorTaskId: succ.id,
        type: depType,
      ),
    ]);
  }

  // -------------------------------------------------------------------------
  // Phase 2 — Schedule manipulation
  // -------------------------------------------------------------------------

  Future<void> _executeCompressSchedule(CompressScheduleCommand command) async {
    final vm = widget.viewModel;
    final candidates =
        command.resourceNames.isEmpty ? vm.allTasks.toList() : _filterTasks(resourceNames: command.resourceNames);
    if (candidates.isEmpty) return;

    final earliest = candidates.map((t) => t.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final factor = command.factor;

    // We need to scale all tasks, not just the filtered ones, to keep structure.
    final toScale = command.resourceNames.isEmpty ? vm.allTasks : candidates;

    final scaled = toScale.map((t) {
      final newStartMs = earliest.millisecondsSinceEpoch +
          ((t.start.millisecondsSinceEpoch - earliest.millisecondsSinceEpoch) * factor).round();
      final durationMs = ((t.end.millisecondsSinceEpoch - t.start.millisecondsSinceEpoch) * factor)
          .round()
          .clamp(60000, double.maxFinite.toInt()); // minimum 1 minute
      final newStart = DateTime.fromMillisecondsSinceEpoch(newStartMs);
      final newEnd = DateTime.fromMillisecondsSinceEpoch(newStartMs + durationMs);
      return t.copyWith(start: newStart, end: newEnd);
    }).toList();

    await vm.updateTasksBulk(scaled);
  }

  Future<void> _executeShiftWorkingDays(ShiftWorkingDaysCommand command) async {
    final vm = widget.viewModel;
    final matching = _filterTasks(
        resourceNames: command.resourceNames,
        taskName: command.taskName,
        includeAllIfNoResource: command.resourceNames.isEmpty);
    final toUpdate = _withChildren(matching);

    final updated = toUpdate.map((t) {
      final newStart = _addWorkingDays(t.start, command.offsetWorkingDays);
      final duration = t.end.difference(t.start);
      return t.copyWith(start: newStart, end: newStart.add(duration));
    }).toList();

    await vm.updateTasksBulk(updated);
  }

  Future<void> _executePackTasks(PackTasksCommand command) async {
    final vm = widget.viewModel;
    final resourceIds = _resolveResourceIds(command.resourceNames);

    // Process each resource independently
    final updates = <LegacyGanttTask>[];
    for (final resId in resourceIds) {
      final tasks = vm.allTasks.where((t) => t.rowId == resId && t.parentId == null).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

      if (tasks.isEmpty) continue;

      DateTime cursor = tasks.first.start;
      for (final task in tasks) {
        final duration = task.end.difference(task.start);
        final newStart = cursor;
        final newEnd = cursor.add(duration);
        updates.add(task.copyWith(start: newStart, end: newEnd));
        cursor = newEnd;
      }
    }

    if (updates.isNotEmpty) await vm.updateTasksBulk(updates);
  }

  Future<void> _executeMirrorSchedule(MirrorScheduleCommand command) async {
    final vm = widget.viewModel;
    final candidates =
        command.resourceNames.isEmpty ? vm.allTasks.toList() : _filterTasks(resourceNames: command.resourceNames);
    if (candidates.isEmpty) return;

    final latestEnd = candidates.map((t) => t.end).reduce((a, b) => a.isAfter(b) ? a : b);
    final target = command.targetEndDate;

    final toMirror = command.resourceNames.isEmpty ? vm.allTasks : candidates;
    final mirrored = toMirror.map((t) {
      final newStart = target.subtract(latestEnd.difference(t.start));
      final newEnd = target.subtract(latestEnd.difference(t.end));
      return t.copyWith(start: newStart, end: newEnd);
    }).toList();

    await vm.updateTasksBulk(mirrored);
  }

  // -------------------------------------------------------------------------
  // Phase 3 — Query
  // -------------------------------------------------------------------------

  Future<String> _executeQuery(ScheduleQueryCommand command) async {
    final vm = widget.viewModel;
    // Map rowId to parentId if available (e.g. job-0-0 -> person-0)
    final rowToGroup = <String, String>{};
    for (final r in vm.localResources) {
      rowToGroup[r.id] = r.parentId ?? r.id;
    }

    final realTasks = vm.allTasks.where((t) => !t.isTimeRangeHighlight && !t.isOverlapIndicator).toList();

    // Pre-compute overlaps per group so the LLM gets explicit conflict data.
    // A group represents a person/resource (including their multiple jobs/rows).
    final conflicts = <Map<String, dynamic>>[];
    final byGroup = <String, List<LegacyGanttTask>>{};
    for (final t in realTasks) {
      final groupId = rowToGroup[t.rowId] ?? t.rowId;
      byGroup.putIfAbsent(groupId, () => []).add(t);
    }

    final groupNames = {for (final r in vm.localResources) r.id: r.name ?? r.id};

    for (final entry in byGroup.entries) {
      final groupId = entry.key;
      final tasks = entry.value..sort((a, b) => a.start.compareTo(b.start));
      for (int i = 0; i < tasks.length; i++) {
        for (int j = i + 1; j < tasks.length; j++) {
          final a = tasks[i];
          final b = tasks[j];
          // Overlap: a starts before b ends AND b starts before a ends
          // Skip summary tasks as they are expected to overlap their children
          if (!a.isSummary && !b.isSummary && a.start.isBefore(b.end) && b.start.isBefore(a.end)) {
            final overlapStart = a.start.isAfter(b.start) ? a.start : b.start;
            final overlapEnd = a.end.isBefore(b.end) ? a.end : b.end;
            conflicts.add({
              'resource': groupNames[groupId] ?? groupId,
              'taskA': a.name ?? (a.isMilestone ? 'Milestone' : 'Task'),
              'taskB': b.name ?? (b.isMilestone ? 'Milestone' : 'Task'),
              'overlapStart': overlapStart.toIso8601String(),
              'overlapEnd': overlapEnd.toIso8601String(),
              'overlapMinutes': overlapEnd.difference(overlapStart).inMinutes,
            });
          }
        }
      }
    }

    // Build task snapshot
    final taskSnapshot = realTasks
        .map((t) => {
              'id': t.id,
              'name': t.name,
              'resource': groupNames[t.rowId] ?? t.rowId,
              'person': groupNames[rowToGroup[t.rowId] ?? t.rowId],
              'start': t.start.toIso8601String(),
              'end': t.end.toIso8601String(),
              'durationHours': t.end.difference(t.start).inMinutes / 60.0,
              'completion': t.completion,
              'isMilestone': t.isMilestone,
              'isSummary': t.isSummary,
              'parentId': t.parentId,
              'notes': t.notes,
            })
        .toList();

    final snapshot = jsonEncode({
      'tasks': taskSnapshot,
      'conflicts': conflicts,
      'taskCount': taskSnapshot.length,
      'conflictCount': conflicts.length,
    });

    return widget.service.query(command.question, snapshot);
  }
}
