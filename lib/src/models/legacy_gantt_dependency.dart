import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Defines the type of dependency between two tasks.
enum DependencyType {
  /// The successor task cannot start until the predecessor task is finished.
  finishToStart,

  /// The successor task cannot start until the predecessor task starts.
  startToStart,

  /// The successor task cannot finish until the predecessor task finishes.
  finishToFinish,

  /// The successor task cannot finish until the predecessor task starts.
  startToFinish,

  /// The successor task must be completed entirely within the time frame of the
  /// predecessor task.
  contained,
}

/// Represents a dependency relationship between two tasks in the Gantt chart.
@immutable
class LegacyGanttTaskDependency {
  /// The unique ID of the task that must come first.
  final String predecessorTaskId;

  /// The unique ID of the task that depends on the predecessor.
  final String successorTaskId;

  /// The type of dependency, which determines the visual representation and
  /// validation logic.
  final DependencyType type;

  /// An optional time delay between the predecessor and successor tasks.
  /// For [DependencyType.finishToStart], this is the gap after the predecessor
  /// ends and before the successor can begin.
  final Duration? lag;

  /// Timestamp of the last update to this dependency.
  final int? lastUpdated;

  const LegacyGanttTaskDependency({
    required this.predecessorTaskId,
    required this.successorTaskId,
    this.type = DependencyType.finishToStart,
    this.lag,
    this.lastUpdated,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyGanttTaskDependency &&
          runtimeType == other.runtimeType &&
          predecessorTaskId == other.predecessorTaskId &&
          successorTaskId == other.successorTaskId &&
          type == other.type &&
          lag == other.lag &&
          lastUpdated == other.lastUpdated;

  @override
  int get hashCode =>
      predecessorTaskId.hashCode ^ successorTaskId.hashCode ^ type.hashCode ^ lag.hashCode ^ lastUpdated.hashCode;
}
