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

  // Adjacency lists for graph traversal
  final List<LegacyGanttTaskDependency> incomingEdges = [];
  final List<LegacyGanttTaskDependency> outgoingEdges = [];

  // For Kahn's algorithm
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

    // 1. Build Graph
    final Map<String, _TaskNode> nodeMap = {};
    for (final task in tasks) {
      nodeMap[task.id] = _TaskNode(task);
    }

    // Populate edges and in-degrees
    // We only consider dependencies where both tasks exist in the task list.
    for (final dep in dependencies) {
      final predNode = nodeMap[dep.predecessorTaskId];
      final succNode = nodeMap[dep.successorTaskId];

      if (predNode != null && succNode != null && dep.type != DependencyType.contained) {
        predNode.outgoingEdges.add(dep);
        succNode.incomingEdges.add(dep);
        succNode.inDegree++;
      }
    }

    // 2. Topological Sort (Kahn's Algorithm)
    final Queue<_TaskNode> queue = Queue();
    final List<_TaskNode> sortedNodes = [];

    // Initialize queue with nodes having 0 in-degree
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

    // Check for cycles
    if (sortedNodes.length != nodeMap.length) {
      // Cycle detected!
      // In a real application, we might want to throw or return an error state.
      // For now, we will return an empty result or handle gracefully by processing what we can.
      // However, typical CPM requires a DAG.
      // Let's degrade gracefully by using the partially sorted list (though results will be invalid for the cycle).
      // Or we can just abort. Warning the console is good.
      print('Warning: Cycle detected in dependencies. Critical Path calculation may be incorrect.');
    }

    // We need a baseline start time. Usually 0 relative to project start.
    // However, tasks have fixed dates in this Gantt chart.
    // CPM usually schedules tasks. But here we are *analyzing* existing schedule
    // or we are calculating the *theoretical* limits?
    // User request implies standard CPM: "Forward Pass to find earliest dates... Backward Pass...".
    // This implies we are effectively calculating "Early Dates" based on durations and links,
    // assuming the project starts at the earliest task start date?
    // OR are we respecting the *actual* start dates of tasks as constraints?
    // Standard CPM assumes ASAP scheduling. Fixed tasks might act as constraints (Must Start On).
    // Given the prompt: "The Early Start (ES) of a task is the maximum Early Finish (EF) of all its predecessors."
    // This implies we are calculating theoretical Early dates.

    // Let's normalize everything to minutes relative to a global project start.
    // Or just work with relative integers from 0 if we assume the first task starts at T=0.
    // Actually, tasks have real dates. Let's use minutes from the earliest start date in the project.

    // Find absolute minimum start to normalize dates (optional, but helpful for int math)
    // Actually, let's just use 0 as the start of the first task(s) in local relative time?
    // No, standard CPM calculates relative to project start.
    // BUT the 'Duration' of a node is fixed.

    // Let's initialize ES of all starter nodes to 0 (or their actual start if we treat them as fixed constraints?).
    // "Rule: The Early Start (ES) of a task is the maximum Early Finish (EF) of all its predecessors."
    // For source nodes, ES = 0.

    // 3. Forward Pass
    for (final u in sortedNodes) {
      // If it's a source node (no incoming edges relevant to calc), ES is 0?
      // Or should we respect its current placement?
      // Standard CPM calculates the *optimum* schedule.
      // If the user placed a task way in the future, is it critical?
      // If we strictly follow dependencies, a gap means "float".
      // So ES is strictly derived from predecessors.

      int maxPredecessorEF = 0;

      for (final dep in u.incomingEdges) {
        final v = nodeMap[dep.predecessorTaskId]!;
        // Logic for different dependency types
        // FS: ES = max(Predecessor EF)
        // SS: ES = max(Predecessor ES)
        // FF: EF = max(Predecessor EF) -> ES = EF - Duration
        // SF: EF = max(Predecessor ES) -> ES = EF - Duration

        // Standard is FS.
        int val = 0;
        switch (dep.type) {
          case DependencyType.finishToStart:
            val = v.earlyFinish;
            break;
          case DependencyType.startToStart:
            val = v.earlyStart;
            break;
          case DependencyType.finishToFinish:
            // Constraint on Finish, convert to start constraint: ES >= v.EF - u.Duration
            val = v.earlyFinish - u.durationMinutes;
            break;
          case DependencyType.startToFinish:
            // Constraint on Finish: ES >= v.ES - u.Duration
            val = v.earlyStart - u.durationMinutes;
            break;
          case DependencyType.contained:
            // Ignored
            break;
        }

        // Add Lag? Prompt didn't specify lag logic detail but `LegacyGanttDependency` has `lag`.
        // Let's verify if `lag` exists. The prompt only listed simple types.
        // But `LegacyGanttDependency` DOES have `Duration? lag`.
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

    // 4. Backward Pass
    // Project completion time is the max EF of all nodes.
    int projectDuration = 0;
    for (final node in sortedNodes) {
      if (node.earlyFinish > projectDuration) {
        projectDuration = node.earlyFinish;
      }
    }

    // Initialize LS and LF for all nodes to Project Duration (as a baseline for min logic)
    // Actually, for Sink nodes (no successors), LF = ProjectDuration.
    // For others, it's min of successors.
    // It's easier to initialize all to projectDuration (or infinity) and iterate reverse.

    // Initialize
    for (final node in nodeMap.values) {
      node.lateFinish = projectDuration;
      node.lateStart = node.lateFinish - node.durationMinutes;
    }

    // Reverse topological order
    final reversedNodes = List<_TaskNode>.from(sortedNodes.reversed);

    for (final u in reversedNodes) {
      // If it is a sink node (no outgoing edges), LF is implicitly projectDuration (already set).
      // If it has successors, LF is min(Successor LS).
      // HOWEVER, we must respect dependency types again.

      if (u.outgoingEdges.isNotEmpty) {
        int minSuccessorLS = projectDuration; // effectively infinity relative to valid range
        bool hasConstraint = false;

        for (final dep in u.outgoingEdges) {
          final v = nodeMap[dep.successorTaskId]!;

          // Reverse Logic:
          // FS: u.LF <= v.LS  => u.LF = min(v.LS)
          // SS: u.ES <= v.ES  => u.LS <= v.LS => u.LF - Dur <= v.LS => u.LF <= v.LS + Dur?? No wait.
          // Let's stick to standard relations:
          // FS (u->v): v.Start >= u.End => u.End <= v.Start => u.LF <= v.LS
          // SS (u->v): v.Start >= u.Start => u.Start <= v.Start => u.LS <= v.LS => u.LF <= v.LS + u.Duration
          // FF (u->v): v.End >= u.End => u.End <= v.End => u.LF <= v.LF
          // SF (u->v): v.End >= u.Start => u.Start <= v.End => u.LS <= v.LF => u.LF <= v.LF + u.Duration

          int val = projectDuration;

          // Adjust for lag: Constraint is u + lag <= v
          // So u <= v - lag
          final lagMin = dep.lag?.inMinutes ?? 0;

          switch (dep.type) {
            case DependencyType.finishToStart:
              // u.finish <= v.start
              val = v.lateStart - lagMin;
              break;
            case DependencyType.startToStart:
              // u.start <= v.start => u.finish - u.dur <= v.start
              // u.finish <= v.start + u.dur
              val = v.lateStart + u.durationMinutes - lagMin;
              break;
            case DependencyType.finishToFinish:
              // u.finish <= v.finish
              val = v.lateFinish - lagMin;
              break;
            case DependencyType.startToFinish:
              // u.start <= v.finish => u.finish - u.dur <= v.finish
              // u.finish <= v.finish + u.dur
              val = v.lateFinish + u.durationMinutes - lagMin;
              break;
            case DependencyType.contained:
              break;
          }

          // If this is the first constraint check, or if val is tighter (smaller), update
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

    // 5. Identify Critical Path
    final Set<String> criticalTaskIds = {};
    final Set<LegacyGanttTaskDependency> criticalDependencies = {};

    for (final node in nodeMap.values) {
      if (node.float <= 0) {
        // Should look for 0, but allowing for minor calc quirks
        criticalTaskIds.add(node.task.id);
      }
    }

    // Identify Critical Dependencies
    // A dependency is critical if it connects two critical tasks AND determines the schedule (zero slack on edge).
    for (final dep in dependencies) {
      if (dep.type == DependencyType.contained) continue;

      if (criticalTaskIds.contains(dep.predecessorTaskId) && criticalTaskIds.contains(dep.successorTaskId)) {
        final u = nodeMap[dep.predecessorTaskId]!;
        final v = nodeMap[dep.successorTaskId]!;

        // rigorous check: does the constraint match the dates?
        // e.g. for FS: u.EF == v.ES (plus lag)
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

    // Since we calculated relative to 0, if we want to return a Project End Date,
    // we need to anchor it to something.
    // But since the chart is interactive and users move things, the "Calculated CPM End Date"
    // corresponds to the end of the chain relative to the start.
    // Let's just return the timestamp of the latest finish in our calc?
    // But our calc used normalized minutes starting at 0.
    // Wait, we didn't use an anchor date. We assumed 0.
    // So the "Project End Date" implies a date.
    // To give a real date, we should find the minimum partial start date among the starter tasks
    // and add the projectDuration to it.

    DateTime minStart = DateTime(2999);
    bool foundStart = false;
    for (final task in tasks) {
      if (tasks.any((t) => t.id == task.id)) {
        // valid task
        if (task.start.isBefore(minStart)) {
          minStart = task.start;
          foundStart = true;
        }
      }
    }
    final anchor = foundStart ? minStart : DateTime.now();
    final projectEnd = anchor.add(Duration(minutes: projectDuration));

    // Build stats map
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
