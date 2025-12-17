// packages/gantt_chart/lib/src/models/gantt_task.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

int? _colorToHex(Color? color) {
  if (color == null) return null;
  // Use toARGB32() for an explicit conversion to a 32-bit integer.
  return color.toARGB32();
}

/// Represents a single segment within a [LegacyGanttTask].
@immutable
class LegacyGanttTaskSegment {
  final DateTime start;
  final DateTime end;
  final Color? color;

  const LegacyGanttTaskSegment({
    required this.start,
    required this.end,
    this.color,
  });

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'color': _colorToHex(color)?.toRadixString(16),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyGanttTaskSegment &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          color == other.color;

  @override
  int get hashCode => start.hashCode ^ end.hashCode ^ color.hashCode;
}

/// Represents a single task or event bar in the Gantt chart.
///
/// For optimal performance, it's recommended to override `==` and `hashCode`
/// or use a package like `equatable` if your task objects might be frequently
/// rebuilt, to prevent unnecessary repaints.
@immutable
class LegacyGanttTask {
  final String id;
  final String rowId;
  final DateTime start;
  final DateTime end;
  final String? name;
  final Color? color;
  final Color? textColor;
  final int stackIndex;
  final String? originalId;
  final bool isSummary;
  final bool isTimeRangeHighlight;
  final bool isOverlapIndicator;
  final double completion;
  final List<LegacyGanttTaskSegment>? segments;
  final bool isMilestone;

  /// A builder to create a custom widget for each day cell this task spans.
  /// If provided, the default task bar will not be drawn for this task.
  final Widget Function(DateTime cellDate)? cellBuilder;

  final int? lastUpdated;
  final String? lastUpdatedBy;

  final String? resourceId;
  final DateTime? baselineStart;
  final DateTime? baselineEnd;
  final String? notes;
  final bool usesWorkCalendar;
  final double load;

  const LegacyGanttTask({
    required this.id,
    required this.rowId,
    required this.start,
    required this.end,
    this.name,
    this.color,
    this.textColor,
    this.originalId,
    this.stackIndex = 0,
    this.isSummary = false,
    this.isTimeRangeHighlight = false,
    this.isOverlapIndicator = false,
    this.completion = 0.0,
    this.segments,
    this.cellBuilder,
    this.isMilestone = false,
    this.lastUpdated,
    this.lastUpdatedBy,
    this.resourceId,
    this.baselineStart,
    this.baselineEnd,
    this.notes,
    this.usesWorkCalendar = false,
    this.load = 1.0,
  });

  factory LegacyGanttTask.empty() => LegacyGanttTask(
        id: '',
        rowId: '',
        start: DateTime(0),
        end: DateTime(0),
        name: '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rowId': rowId,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'name': name,
        'color': _colorToHex(color)?.toRadixString(16),
        'textColor': _colorToHex(textColor)?.toRadixString(16),
        'stackIndex': stackIndex,
        'originalId': originalId,
        'isSummary': isSummary,
        'isTimeRangeHighlight': isTimeRangeHighlight,
        'isOverlapIndicator': isOverlapIndicator,
        'completion': completion,
        'segments': segments?.map((s) => s.toJson()).toList(),
        'isMilestone': isMilestone,
        // Note: copyWith does not support functions, so cellBuilder is not included here.
        // cellBuilder is a function and cannot be serialized to JSON.
        'hasCellBuilder': cellBuilder != null,
        'lastUpdated': lastUpdated,
        'lastUpdatedBy': lastUpdatedBy,
        'resourceId': resourceId,
        'baselineStart': baselineStart?.toIso8601String(),
        'baselineEnd': baselineEnd?.toIso8601String(),
        'notes': notes,
        'usesWorkCalendar': usesWorkCalendar,
        'load': load,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyGanttTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          rowId == other.rowId &&
          start == other.start &&
          end == other.end &&
          name == other.name &&
          color == other.color &&
          textColor == other.textColor &&
          stackIndex == other.stackIndex &&
          originalId == other.originalId &&
          isSummary == other.isSummary &&
          isTimeRangeHighlight == other.isTimeRangeHighlight &&
          isOverlapIndicator == other.isOverlapIndicator &&
          completion == other.completion &&
          listEquals(segments, other.segments) &&
          isMilestone == other.isMilestone &&
          cellBuilder == other.cellBuilder &&
          lastUpdated == other.lastUpdated &&
          lastUpdatedBy == other.lastUpdatedBy &&
          resourceId == other.resourceId &&
          baselineStart == other.baselineStart &&
          baselineEnd == other.baselineEnd &&
          notes == other.notes &&
          usesWorkCalendar == other.usesWorkCalendar &&
          load == other.load;

  @override
  int get hashCode =>
      id.hashCode ^
      rowId.hashCode ^
      start.hashCode ^
      end.hashCode ^
      name.hashCode ^
      color.hashCode ^
      textColor.hashCode ^
      stackIndex.hashCode ^
      originalId.hashCode ^
      isSummary.hashCode ^
      isTimeRangeHighlight.hashCode ^
      isOverlapIndicator.hashCode ^
      completion.hashCode ^
      Object.hashAll(segments ?? []) ^
      isMilestone.hashCode ^
      cellBuilder.hashCode ^
      lastUpdated.hashCode ^
      lastUpdatedBy.hashCode ^
      resourceId.hashCode ^
      baselineStart.hashCode ^
      baselineEnd.hashCode ^
      notes.hashCode ^
      usesWorkCalendar.hashCode ^
      load.hashCode;

  LegacyGanttTask copyWith({
    String? id,
    String? rowId,
    DateTime? start,
    DateTime? end,
    String? name,
    Color? color,
    Color? textColor,
    int? stackIndex,
    String? originalId,
    bool? isSummary,
    bool? isTimeRangeHighlight,
    bool? isOverlapIndicator,
    double? completion,
    List<LegacyGanttTaskSegment>? segments,
    bool? isMilestone,
    Widget Function(DateTime cellDate)? cellBuilder,
    int? lastUpdated,
    String? lastUpdatedBy,
    String? resourceId,
    DateTime? baselineStart,
    DateTime? baselineEnd,
    String? notes,
    bool? usesWorkCalendar,
    double? load,
  }) =>
      LegacyGanttTask(
        id: id ?? this.id,
        rowId: rowId ?? this.rowId,
        start: start ?? this.start,
        end: end ?? this.end,
        name: name ?? this.name,
        color: color ?? this.color,
        textColor: textColor ?? this.textColor,
        stackIndex: stackIndex ?? this.stackIndex,
        originalId: originalId ?? this.originalId,
        isSummary: isSummary ?? this.isSummary,
        isTimeRangeHighlight: isTimeRangeHighlight ?? this.isTimeRangeHighlight,
        isOverlapIndicator: isOverlapIndicator ?? this.isOverlapIndicator,
        completion: completion ?? this.completion,
        segments: segments ?? this.segments,
        isMilestone: isMilestone ?? this.isMilestone,
        cellBuilder: cellBuilder ?? this.cellBuilder,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
        resourceId: resourceId ?? this.resourceId,
        baselineStart: baselineStart ?? this.baselineStart,
        baselineEnd: baselineEnd ?? this.baselineEnd,
        notes: notes ?? this.notes,
        usesWorkCalendar: usesWorkCalendar ?? this.usesWorkCalendar,
        load: load ?? this.load,
      );
}
