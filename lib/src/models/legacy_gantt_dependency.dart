import 'package:fixnum/fixnum.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:flutter/foundation.dart';

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
  /// The ID of the task that must happen first (or determines the timing).
  final String predecessorTaskId;

  /// The ID of the task that is dependent on the predecessor.
  final String successorTaskId;

  /// The nature of the dependency (e.g., finish-to-start).
  final DependencyType type;

  /// The optional duration of lag (delay) or lead (negative delay) between tasks.
  final Duration? lag;

  /// The timestamp of the last update to this dependency, if tracked.
  final Hlc? lastUpdated;

  const LegacyGanttTaskDependency({
    required this.predecessorTaskId,
    required this.successorTaskId,
    this.type = DependencyType.finishToStart,
    this.lag,
    this.lastUpdated,
  });

  ProtocolDependency toProtocolDependency() => ProtocolDependency(
    predecessorTaskId: predecessorTaskId,
    successorTaskId: successorTaskId,
    type: type.name,
    lag: lag == null ? null : Int64(lag!.inMilliseconds),
    lastUpdated: lastUpdated?.toString(),
  );

  factory LegacyGanttTaskDependency.fromProtocolDependency(ProtocolDependency pd) => LegacyGanttTaskDependency(
    predecessorTaskId: pd.predecessorTaskId,
    successorTaskId: pd.successorTaskId,
    type: DependencyType.values.byName(pd.type),
    lag: pd.hasLag() ? Duration(milliseconds: pd.lag.toInt()) : null,
    lastUpdated: pd.lastUpdated.isEmpty ? null : pd.parsedLastUpdated,
  );

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

  String get contentHash => toProtocolDependency().contentHash;
}
