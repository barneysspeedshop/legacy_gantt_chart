import 'dart:collection';

import '../models/legacy_gantt_dependency.dart';
import '../models/legacy_gantt_task.dart';

/// Result of a critical path calculation.
class CriticalPathResult {
  /// The Set of task IDs that are on the critical path.
  final Set<String> criticalTaskIds;

  /// The Set of dependencies that form the critical path.
  final Set<LegacyGanttTaskDependency> criticalDependencies;

  /// The calculated projected end date of the project (earliest finish associated with the critical path).
  final DateTime projectEndDate;

  /// Map of task ID to its CPM stats.
  final Map<String, CpmTaskStats> taskStats;

  const CriticalPathResult({
    required this.criticalTaskIds,
    required this.criticalDependencies,
    required this.projectEndDate,
    this.taskStats = const {},
  });

  factory CriticalPathResult.empty() => CriticalPathResult(
        criticalTaskIds: {},
        criticalDependencies: {},
        projectEndDate: DateTime.now(),
        taskStats: {},
      );
}

/// Holds calculated CPM statistics for a task.
class CpmTaskStats {
  final int earlyStart;
  final int earlyFinish;
  final int lateStart;
  final int lateFinish;
  final int float;

  CpmTaskStats({
    required this.earlyStart,
    required this.earlyFinish,
    required this.lateStart,
    required this.lateFinish,
    required this.float,
  });
}

/// Internal node representation for CPM calculations.
class _TaskNode {
  final LegacyGanttTask task;
  final int durationMinutes;

  int earlyStart = 0;
  int earlyFinish = 0;
  int lateStart = 0;
  int lateFinish = 0;
  int float = 0;

  final List<LegacyGanttTaskDependency> incomingEdges = [];
  final List<LegacyGanttTaskDependency> outgoingEdges = [];

  int inDegree = 0;

  _TaskNode(this.task) : durationMinutes = task.end.difference(task.start).inMinutes;

  void calculateFloat() {
    float = lateStart - earlyStart;
  }
}

/// Utility class to perform Critical Path Method (CPM) analysis on a set of Gantt tasks.
class CriticalPathCalculator {
  /// Calculates the critical path for the given tasks and dependencies.
  ///
  /// This method treats the Gantt chart as a Directed Acyclic Graph (DAG) and performs:
  /// 1. Topological Sort (using Kahn's Algorithm) to order tasks and detect cycles.
  /// 2. Forward Pass to calculate Early Start (ES) and Early Finish (EF).
  /// 3. Backward Pass to calculate Late Start (LS) and Late Finish (LF).
  /// 4. Float calculation to identify critical tasks (Float ~ 0).
  ///
  /// Returns a [CriticalPathResult] containing critical tasks and dependencies.
  CriticalPathResult calculate({
    required List<LegacyGanttTask> tasks,
    required List<LegacyGanttTaskDependency> dependencies,
  }) {
    if (tasks.isEmpty) return CriticalPathResult.empty();

    final Map<String, _TaskNode> nodeMap = {};
    for (final task in tasks) {
      nodeMap[task.id] = _TaskNode(task);
    }

    for (final dep in dependencies) {
      final predNode = nodeMap[dep.predecessorTaskId];
      final succNode = nodeMap[dep.successorTaskId];

      if (predNode != null && succNode != null && dep.type != DependencyType.contained) {
        predNode.outgoingEdges.add(dep);
        succNode.incomingEdges.add(dep);
        succNode.inDegree++;
      }
    }

    final Queue<_TaskNode> queue = Queue();
    final List<_TaskNode> sortedNodes = [];

    for (final node in nodeMap.values) {
      if (node.inDegree == 0) {
        queue.add(node);
      }
    }

    while (queue.isNotEmpty) {
      final u = queue.removeFirst();
      sortedNodes.add(u);

      for (final dep in u.outgoingEdges) {
        final v = nodeMap[dep.successorTaskId]!;
        v.inDegree--;
        if (v.inDegree == 0) {
          queue.add(v);
        }
      }
    }

    if (sortedNodes.length != nodeMap.length) {
      print('Warning: Cycle detected in dependencies. Critical Path calculation may be incorrect.');
    }

    for (final u in sortedNodes) {
      int maxPredecessorEF = 0;

      for (final dep in u.incomingEdges) {
        final v = nodeMap[dep.predecessorTaskId]!;

        int val = 0;
        switch (dep.type) {
          case DependencyType.finishToStart:
            val = v.earlyFinish;
            break;
          case DependencyType.startToStart:
            val = v.earlyStart;
            break;
          case DependencyType.finishToFinish:
            val = v.earlyFinish - u.durationMinutes;
            break;
          case DependencyType.startToFinish:
            val = v.earlyStart - u.durationMinutes;
            break;
          case DependencyType.contained:
            break;
        }

        if (dep.lag != null) {
          val += dep.lag!.inMinutes;
        }

        if (val > maxPredecessorEF) {
          maxPredecessorEF = val;
        }
      }

      u.earlyStart = maxPredecessorEF;
      u.earlyFinish = u.earlyStart + u.durationMinutes;
    }

    int projectDuration = 0;
    for (final node in sortedNodes) {
      if (node.earlyFinish > projectDuration) {
        projectDuration = node.earlyFinish;
      }
    }

    for (final node in nodeMap.values) {
      node.lateFinish = projectDuration;
      node.lateStart = node.lateFinish - node.durationMinutes;
    }

    final reversedNodes = List<_TaskNode>.from(sortedNodes.reversed);

    for (final u in reversedNodes) {
      if (u.outgoingEdges.isNotEmpty) {
        int minSuccessorLS = projectDuration; // effectively infinity relative to valid range
        bool hasConstraint = false;

        for (final dep in u.outgoingEdges) {
          final v = nodeMap[dep.successorTaskId]!;

          int val = projectDuration;

          final lagMin = dep.lag?.inMinutes ?? 0;

          switch (dep.type) {
            case DependencyType.finishToStart:
              val = v.lateStart - lagMin;
              break;
            case DependencyType.startToStart:
              val = v.lateStart + u.durationMinutes - lagMin;
              break;
            case DependencyType.finishToFinish:
              val = v.lateFinish - lagMin;
              break;
            case DependencyType.startToFinish:
              val = v.lateFinish + u.durationMinutes - lagMin;
              break;
            case DependencyType.contained:
              break;
          }

          if (!hasConstraint || val < minSuccessorLS) {
            minSuccessorLS = val;
            hasConstraint = true;
          }
        }

        if (hasConstraint) {
          u.lateFinish = minSuccessorLS;
          u.lateStart = u.lateFinish - u.durationMinutes;
        }
      }

      u.calculateFloat();
    }

    final Set<String> criticalTaskIds = {};
    final Set<LegacyGanttTaskDependency> criticalDependencies = {};

    for (final node in nodeMap.values) {
      if (node.float <= 0) {
        criticalTaskIds.add(node.task.id);
      }
    }

    for (final dep in dependencies) {
      if (dep.type == DependencyType.contained) continue;

      if (criticalTaskIds.contains(dep.predecessorTaskId) && criticalTaskIds.contains(dep.successorTaskId)) {
        final u = nodeMap[dep.predecessorTaskId]!;
        final v = nodeMap[dep.successorTaskId]!;

        final lagMin = dep.lag?.inMinutes ?? 0;
        bool isTight = false;

        switch (dep.type) {
          case DependencyType.finishToStart:
            if ((u.earlyFinish + lagMin) == v.earlyStart) isTight = true;
            break;
          case DependencyType.startToStart:
            if ((u.earlyStart + lagMin) == v.earlyStart) isTight = true;
            break;
          case DependencyType.finishToFinish:
            if ((u.earlyFinish + lagMin) == v.earlyFinish) isTight = true;
            break;
          case DependencyType.startToFinish:
            if ((u.earlyStart + lagMin) == v.earlyFinish) isTight = true;
            break;
          default:
            break;
        }

        if (isTight) {
          criticalDependencies.add(dep);
        }
      }
    }

    DateTime minStart = DateTime(2999);
    bool foundStart = false;
    for (final task in tasks) {
      if (tasks.any((t) => t.id == task.id)) {
        if (task.start.isBefore(minStart)) {
          minStart = task.start;
          foundStart = true;
        }
      }
    }
    final anchor = foundStart ? minStart : DateTime.now();
    final projectEnd = anchor.add(Duration(minutes: projectDuration));

    final Map<String, CpmTaskStats> stats = {};
    for (final node in nodeMap.values) {
      stats[node.task.id] = CpmTaskStats(
        earlyStart: node.earlyStart,
        earlyFinish: node.earlyFinish,
        lateStart: node.lateStart,
        lateFinish: node.lateFinish,
        float: node.float,
      );
    }

    return CriticalPathResult(
      criticalTaskIds: criticalTaskIds,
      criticalDependencies: criticalDependencies,
      projectEndDate: projectEnd,
      taskStats: stats,
    );
  }
}
