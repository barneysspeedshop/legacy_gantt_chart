import 'dart:convert';
import 'package:crypto/crypto.dart';
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

  String get contentHash {
    final data = {
      'predecessorTaskId': predecessorTaskId,
      'successorTaskId': successorTaskId,
      'type': type.name,
      'lag': lag?.inMilliseconds,
      // 'lastUpdated': lastUpdated, // Exclude mutable metadata from content hash usually?
      // Wait, strict Merkle includes everything. But existing Task contentHash excluded local state?
      // Task contentHash included 'lastUpdated'? No, it didn't in the snippet I saw earlier!
      // Let's check LegacyGanttTask.contentHash again.
      // It has 'completion', 'name' etc. It did NOT include 'lastUpdated'.
      // So we should verify if 'lastUpdated' is strictly part of content.
      // Usually Merkle state is about VALUE. 'lastUpdated' is METADATA.
      // But for Sovereign Sync, if I update metadata, I want to sync.
      // However, HLC usually handles the "version".
      // If I change 'lag', contentHash changes.
      // If I just 'touch' the file without changing content, contentHash stays same, but lastUpdated changes.
      // If we exclude lastUpdated, we might miss pure timestamp updates, but usually we care about data.
      // Let's stick to DATA fields for now.
    };
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
