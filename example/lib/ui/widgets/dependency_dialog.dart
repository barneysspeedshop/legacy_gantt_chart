import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

/// A dialog to manage (remove) dependencies for a task.
class DependencyManagerDialog extends StatelessWidget {
  final String title;
  final List<LegacyGanttTaskDependency> dependencies;
  final List<LegacyGanttTask> tasks;
  final LegacyGanttTask sourceTask;

  const DependencyManagerDialog({
    super.key,
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
