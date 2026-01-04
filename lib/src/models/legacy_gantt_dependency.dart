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
  final String predecessorTaskId;
  final String successorTaskId;
  final DependencyType type;
  final Duration? lag;
  final int? lastUpdated;

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
        type: _mapTypeToProtocol(type),
        lag: lag,
        lastUpdated: lastUpdated,
      );

  factory LegacyGanttTaskDependency.fromProtocolDependency(ProtocolDependency pd) => LegacyGanttTaskDependency(
        predecessorTaskId: pd.predecessorTaskId,
        successorTaskId: pd.successorTaskId,
        type: _mapTypeFromProtocol(pd.type),
        lag: pd.lag,
        lastUpdated: pd.lastUpdated,
      );

  static ProtocolDependencyType _mapTypeToProtocol(DependencyType type) {
    switch (type) {
      case DependencyType.finishToStart:
        return ProtocolDependencyType.finishToStart;
      case DependencyType.startToStart:
        return ProtocolDependencyType.startToStart;
      case DependencyType.finishToFinish:
        return ProtocolDependencyType.finishToFinish;
      case DependencyType.startToFinish:
        return ProtocolDependencyType.startToFinish;
      case DependencyType.contained:
        return ProtocolDependencyType.contained;
    }
  }

  static DependencyType _mapTypeFromProtocol(ProtocolDependencyType type) {
    switch (type) {
      case ProtocolDependencyType.finishToStart:
        return DependencyType.finishToStart;
      case ProtocolDependencyType.startToStart:
        return DependencyType.startToStart;
      case ProtocolDependencyType.finishToFinish:
        return DependencyType.finishToFinish;
      case ProtocolDependencyType.startToFinish:
        return DependencyType.startToFinish;
      case ProtocolDependencyType.contained:
        return DependencyType.contained;
    }
  }

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
