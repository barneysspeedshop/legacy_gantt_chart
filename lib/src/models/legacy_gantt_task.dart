import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

int? _colorToHex(Color? color) {
  if (color == null) return null;
  return color.toARGB32();
}

Color? _parseColor(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    try {
      if (value.startsWith('#')) return Color(int.parse(value.substring(1), radix: 16));
      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return null;
    }
  }
  if (value is int) return Color(value);
  return null;
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
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'color': _colorToHex(color)?.toRadixString(16),
      };

  factory LegacyGanttTaskSegment.fromJson(Map<String, dynamic> json) => LegacyGanttTaskSegment(
        start: DateTime.parse(json['start']),
        end: DateTime.parse(json['end']),
        color: _parseColor(json['color']),
      );

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
  none,
  constrain,
  elastic,
}

/// Represents a single task or event bar in the Gantt chart.
@immutable
class LegacyGanttTask {
  /// The unique identifier for this task.
  final String id;

  /// The ID of the row this task belongs to.
  final String rowId;

  /// The start date and time of the task.
  final DateTime start;

  /// The end date and time of the task.
  final DateTime end;

  /// The display name of the task.
  final String? name;

  /// The specific color of this task bar. Overrides theme defaults if provided.
  final Color? color;

  /// The text color for this task. Overrides theme defaults if provided.
  final Color? textColor;

  /// The vertical stack index of this task within its row, used for handling overlaps.
  final int stackIndex;

  /// The original ID of the task, if it was imported or transformed.
  final String? originalId;

  /// Whether this task represents a summary or parent task (e.g., a project phase).
  final bool isSummary;

  /// Whether this task is a background highlight (e.g., holiday, weekend) rather than a workable task.
  final bool isTimeRangeHighlight;

  /// Whether this task is a visual indicator of a scheduling conflict.
  final bool isOverlapIndicator;

  /// The completion percentage of the task (0.0 to 1.0).
  final double completion;

  /// Optional list of [LegacyGanttTaskSegment]s for split tasks.
  final List<LegacyGanttTaskSegment>? segments;

  /// Whether this task is a zero-duration milestone.
  final bool isMilestone;

  /// A builder to create a custom widget for each day cell this task spans.
  final Widget Function(DateTime cellDate)? cellBuilder;

  /// The timestamp of the last update to this task.
  final Hlc lastUpdated;

  /// The ID of the user or system that last updated this task.
  final String? lastUpdatedBy;

  /// The ID of the resource assigned to this task.
  final String? resourceId;

  /// The ID of the parent task, if this task is part of a hierarchy.
  final String? parentId;

  /// The planned start date of the task, for baseline comparison.
  final DateTime? baselineStart;

  /// The planned end date of the task, for baseline comparison.
  final DateTime? baselineEnd;

  /// Additional notes or description for the task.
  final String? notes;

  /// Whether this task should respect the [WorkCalendar] for scheduling duration.
  final bool usesWorkCalendar;

  /// The resource load factor (e.g., 1.0 for full allocation, 0.5 for half).
  final double load;

  /// Whether this task is automatically scheduled by the engine.
  final bool? isAutoScheduled;

  /// Whether moving this task should propagate changes to its children (if it is a summary).
  final bool propagatesMoveToChildren;

  /// The policy for how this task reacts when its parent is resized.
  final ResizePolicy resizePolicy;

  /// Map of field names to their last update timestamp (HLC).
  final Map<String, Hlc> fieldTimestamps;

  /// Indicates if this task is logically deleted (Tombstone).
  final bool isDeleted;

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
    this.fieldTimestamps = const {},
    this.isDeleted = false,
  }) : lastUpdated = lastUpdated ?? Hlc.zero;

  factory LegacyGanttTask.empty() => LegacyGanttTask(
        id: '',
        rowId: '',
        start: DateTime.utc(0),
        end: DateTime.utc(0).add(const Duration(days: 1)),
        name: '',
      );

  factory LegacyGanttTask.fromProtocolTask(ProtocolTask pt) {
    final meta = pt.metadata;
    return LegacyGanttTask(
      id: pt.id,
      rowId: pt.rowId,
      start: pt.start,
      end: pt.end,
      name: pt.name,
      completion: pt.completion,
      isSummary: pt.isSummary || meta['ganttType'] == 'summary' || meta['ganttType'] == 'project',
      isMilestone: pt.isMilestone,
      resourceId: pt.resourceId,
      parentId: pt.parentId,
      notes: pt.notes,
      isDeleted: pt.isDeleted,
      lastUpdated: pt.lastUpdated,
      lastUpdatedBy: pt.lastUpdatedBy,
      fieldTimestamps: pt.fieldTimestamps,
      color: _parseColor(meta['color']),
      textColor: _parseColor(meta['textColor']),
      stackIndex: meta['stackIndex'] ?? 0,
      originalId: meta['originalId'],
      isTimeRangeHighlight: meta['isTimeRangeHighlight'] == true,
      isOverlapIndicator: meta['isOverlapIndicator'] == true,
      segments: (meta['segments'] as List?)?.map((e) => LegacyGanttTaskSegment.fromJson(e)).toList(),
      usesWorkCalendar: meta['usesWorkCalendar'] == true,
      load: (meta['load'] as num?)?.toDouble() ?? 1.0,
      isAutoScheduled: meta['isAutoScheduled'] == true,
      propagatesMoveToChildren: meta['propagatesMoveToChildren'] ?? true,
      resizePolicy: meta['resizePolicy'] != null
          ? ResizePolicy.values.firstWhere((e) => e.name == meta['resizePolicy'], orElse: () => ResizePolicy.none)
          : ResizePolicy.none,
      baselineStart: meta['baselineStart'] != null ? DateTime.parse(meta['baselineStart']) : null,
      baselineEnd: meta['baselineEnd'] != null ? DateTime.parse(meta['baselineEnd']) : null,
    );
  }

  ProtocolTask toProtocolTask() => ProtocolTask(
        id: id,
        rowId: rowId,
        start: start,
        end: end,
        name: name,
        completion: completion,
        isSummary: isSummary,
        isMilestone: isMilestone,
        resourceId: resourceId,
        parentId: parentId,
        notes: notes,
        isDeleted: isDeleted,
        lastUpdated: lastUpdated,
        lastUpdatedBy: lastUpdatedBy,
        fieldTimestamps: fieldTimestamps,
        metadata: {
          'color': _colorToHex(color)?.toRadixString(16),
          'textColor': _colorToHex(textColor)?.toRadixString(16),
          'stackIndex': stackIndex,
          'originalId': originalId,
          'isTimeRangeHighlight': isTimeRangeHighlight,
          'isOverlapIndicator': isOverlapIndicator,
          'segments': segments?.map((s) => s.toJson()).toList(),
          'usesWorkCalendar': usesWorkCalendar,
          'load': load,
          'isAutoScheduled': isAutoScheduled,
          'propagatesMoveToChildren': propagatesMoveToChildren,
          'resizePolicy': resizePolicy.name,
          'baselineStart': baselineStart?.toUtc().toIso8601String(),
          'baselineEnd': baselineEnd?.toUtc().toIso8601String(),
          'hasCellBuilder': cellBuilder != null,
        },
      );

  factory LegacyGanttTask.fromJson(Map<String, dynamic> json) {
    final meta = <String, dynamic>{
      'color': json['color'],
      'textColor': json['textColor'],
      'stackIndex': json['stackIndex'],
      'originalId': json['originalId'],
      'isTimeRangeHighlight': json['isTimeRangeHighlight'],
      'isOverlapIndicator': json['isOverlapIndicator'],
      'segments': json['segments'],
      'usesWorkCalendar': json['usesWorkCalendar'],
      'load': json['load'],
      'isAutoScheduled': json['isAutoScheduled'],
      'propagatesMoveToChildren': json['propagatesMoveToChildren'],
      'resizePolicy': json['resizePolicy'],
      'baselineStart': json['baselineStart'],
      'baselineEnd': json['baselineEnd'],
    };

    final pt = ProtocolTask.fromJson({
      ...json,
      'lastUpdatedBy': json['lastUpdatedBy'] ?? json['last_updated_by'], // Support both snake and camel for safety
      'metadata': meta, // ProtocolTask.fromJson looks for 'metadata'
    });

    return LegacyGanttTask.fromProtocolTask(pt);
  }

  Map<String, dynamic> toJson() {
    final pt = toProtocolTask();
    final json = pt.toJson();
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    json.remove('metadata');
    return {...json, ...meta};
  }

  String get contentHash => toProtocolTask().contentHash;

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
          isMilestone == other.isMilestone &&
          resourceId == other.resourceId &&
          parentId == other.parentId &&
          baselineStart == other.baselineStart &&
          baselineEnd == other.baselineEnd &&
          notes == other.notes &&
          usesWorkCalendar == other.usesWorkCalendar &&
          load == other.load &&
          isAutoScheduled == other.isAutoScheduled &&
          propagatesMoveToChildren == other.propagatesMoveToChildren &&
          resizePolicy == other.resizePolicy &&
          isDeleted == other.isDeleted &&
          lastUpdated == other.lastUpdated &&
          lastUpdatedBy == other.lastUpdatedBy &&
          const ListEquality().equals(segments, other.segments) &&
          const MapEquality().equals(fieldTimestamps, other.fieldTimestamps);

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
      isSummary.hashCode ^
      completion.hashCode ^
      isMilestone.hashCode ^
      resourceId.hashCode ^
      parentId.hashCode ^
      lastUpdated.hashCode;

  LegacyGanttTask copyWithProtocol(ProtocolTask pt) {
    final meta = pt.metadata;
    return LegacyGanttTask(
      id: pt.id,
      rowId: pt.rowId,
      start: pt.start,
      end: pt.end,
      name: pt.name,
      completion: pt.completion,
      isSummary: pt.isSummary || meta['ganttType'] == 'summary' || meta['ganttType'] == 'project',
      isMilestone: pt.isMilestone,
      resourceId: pt.resourceId,
      parentId: pt.parentId,
      notes: pt.notes,
      isDeleted: pt.isDeleted,
      lastUpdated: pt.lastUpdated,
      lastUpdatedBy: pt.lastUpdatedBy,
      fieldTimestamps: pt.fieldTimestamps,
      color: _parseColor(meta['color']),
      textColor: _parseColor(meta['textColor']),
      stackIndex: meta['stackIndex'] ?? 0,
      originalId: meta['originalId'],
      isTimeRangeHighlight: meta['isTimeRangeHighlight'] == true,
      isOverlapIndicator: meta['isOverlapIndicator'] == true,
      segments: (meta['segments'] as List?)?.map((e) => LegacyGanttTaskSegment.fromJson(e)).toList(),
      usesWorkCalendar: meta['usesWorkCalendar'] == true,
      load: (meta['load'] as num?)?.toDouble() ?? 1.0,
      isAutoScheduled: meta['isAutoScheduled'] == true,
      propagatesMoveToChildren: meta['propagatesMoveToChildren'] ?? true,
      resizePolicy: meta['resizePolicy'] != null
          ? ResizePolicy.values.firstWhere((e) => e.name == meta['resizePolicy'], orElse: () => ResizePolicy.none)
          : ResizePolicy.none,
      baselineStart: meta['baselineStart'] != null ? DateTime.parse(meta['baselineStart']) : null,
      baselineEnd: meta['baselineEnd'] != null ? DateTime.parse(meta['baselineEnd']) : null,
      cellBuilder: cellBuilder,
    );
  }

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
    Map<String, Hlc>? fieldTimestamps,
    bool? isDeleted,
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
        fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
