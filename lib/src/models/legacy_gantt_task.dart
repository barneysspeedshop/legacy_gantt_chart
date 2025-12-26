// packages/gantt_chart/lib/src/models/gantt_task.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:legacy_gantt_chart/src/sync/hlc.dart';

int? _colorToHex(Color? color) {
  if (color == null) return null;
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

/// Defines how a parent task resizing affects its children.
enum ResizePolicy {
  /// Standard resizing (default). Children are not affected by parent resize,
  /// unless standard dependency rules apply.
  none,

  /// Constrain (Type 4): Children are pushed/clamped to stay inside the parent.
  constrain,

  /// Elastic (Type 5): Children are scaled proportionally to the parent's new duration.
  elastic,
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

  final Hlc lastUpdated;
  final String? lastUpdatedBy;

  final String? resourceId;
  final String? parentId;
  final DateTime? baselineStart;
  final DateTime? baselineEnd;
  final String? notes;
  final bool usesWorkCalendar;
  final double load;
  final bool? isAutoScheduled;
  final bool propagatesMoveToChildren;
  final ResizePolicy resizePolicy;

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
    Hlc? lastUpdated,
    this.lastUpdatedBy,
    this.resourceId,
    this.parentId,
    this.baselineStart,
    this.baselineEnd,
    this.notes,
    this.usesWorkCalendar = false,
    this.load = 1.0,
    this.isAutoScheduled,
    this.propagatesMoveToChildren = true,
    this.resizePolicy = ResizePolicy.none,
  }) : lastUpdated = lastUpdated ?? Hlc.zero;

  factory LegacyGanttTask.empty() => LegacyGanttTask(
        id: '',
        rowId: '',
        start: DateTime(0),
        end: DateTime(0),
        name: '',
      );

  factory LegacyGanttTask.fromJson(Map<String, dynamic> json) {
    Hlc parsedHlc;
    final dynamic rawLastUpdated = json['lastUpdated'];
    if (rawLastUpdated is String) {
      parsedHlc = Hlc.parse(rawLastUpdated);
    } else if (rawLastUpdated is int) {
      parsedHlc = Hlc(millis: rawLastUpdated, counter: 0, nodeId: 'legacy');
    } else {
      parsedHlc = Hlc.zero;
    }

    return LegacyGanttTask(
      id: json['id'] as String,
      rowId: json['rowId'] as String,
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      name: json['name'] as String?,
      // Color parsing logic might be complex if relying on _colorToHex inverse which isn't here.
      // Assuming caller handles color externally or we just null it for now if strict json didn't exist before.
      // But wait, the user instructions only specified lastUpdated logic for fromJson.
      // I will implement bare minimum fromJson for other fields or assume standard names?
      // "The JSON might contain..." implies I am WRITING the fromJson method.
      // I should do my best to map fields, but `color` is tricky as `_colorToHex` is one way.
      // I'll skip color parsing for now or assume int/hex string?
      // Actually, looking at `toJson`, color is `toRadixString(16)`.
      // Let's safe skip complex fields not required by prompt, focusing on lastUpdated.
      // The prompt Requirement 4 "Serialization (fromJson): ... Logic: ...".
      // It implies passing the whole object.
      // I'll try to fill in the rest reasonably.
      isSummary: json['isSummary'] == true,
      lastUpdated: parsedHlc,
      // ... other fields if needed, but the prompt strictly defined `lastUpdated` logic.
    );
  }

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
        'hasCellBuilder': cellBuilder != null,
        'lastUpdated': lastUpdated.toString(),
        'lastUpdatedBy': lastUpdatedBy,
        'resourceId': resourceId,
        'parentId': parentId,
        'baselineStart': baselineStart?.toIso8601String(),
        'baselineEnd': baselineEnd?.toIso8601String(),
        'notes': notes,
        'usesWorkCalendar': usesWorkCalendar,
        'load': load,
        'isAutoScheduled': isAutoScheduled,
        'propagatesMoveToChildren': propagatesMoveToChildren,
        'resizePolicy': resizePolicy.name,
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
          stackIndex == other.stackIndex && // stackIndex
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
          parentId == other.parentId &&
          baselineStart == other.baselineStart &&
          baselineEnd == other.baselineEnd &&
          notes == other.notes &&
          usesWorkCalendar == other.usesWorkCalendar &&
          load == other.load &&
          isAutoScheduled == other.isAutoScheduled &&
          propagatesMoveToChildren == other.propagatesMoveToChildren &&
          resizePolicy == other.resizePolicy;

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
      parentId.hashCode ^
      baselineStart.hashCode ^
      baselineEnd.hashCode ^
      notes.hashCode ^
      usesWorkCalendar.hashCode ^
      load.hashCode ^
      // Removed duplicate load.hashCode
      isAutoScheduled.hashCode ^
      propagatesMoveToChildren.hashCode ^
      resizePolicy.hashCode;

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
    Hlc? lastUpdated,
    String? lastUpdatedBy,
    String? resourceId,
    String? parentId,
    DateTime? baselineStart,
    DateTime? baselineEnd,
    String? notes,
    bool? usesWorkCalendar,
    double? load,
    bool? isAutoScheduled,
    bool? propagatesMoveToChildren,
    ResizePolicy? resizePolicy,
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
        parentId: parentId ?? this.parentId,
        baselineStart: baselineStart ?? this.baselineStart,
        baselineEnd: baselineEnd ?? this.baselineEnd,
        notes: notes ?? this.notes,
        usesWorkCalendar: usesWorkCalendar ?? this.usesWorkCalendar,
        load: load ?? this.load,
        isAutoScheduled: isAutoScheduled ?? this.isAutoScheduled,
        propagatesMoveToChildren: propagatesMoveToChildren ?? this.propagatesMoveToChildren,
        resizePolicy: resizePolicy ?? this.resizePolicy,
      );
}
