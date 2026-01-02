import 'dart:convert';
import 'package:crypto/crypto.dart';
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
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
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

  /// Map of field names to their last update timestamp (HLC).
  /// Used for Field-Level LWW conflict resolution.
  final Map<String, Hlc> fieldTimestamps;

  /// Indicates if this task is logically deleted (Tombstone).
  /// Used for Add-Wins OR-Set logic.
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

    Map<String, Hlc> parsedFieldTimestamps = {};
    if (json['fieldTimestamps'] != null) {
      final map = json['fieldTimestamps'] as Map<String, dynamic>;
      map.forEach((k, v) {
        if (v is String) {
          parsedFieldTimestamps[k] = Hlc.parse(v);
        }
      });
    }

    return LegacyGanttTask(
      id: json['id'] as String,
      rowId: json['rowId'] as String,
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      name: json['name'] as String?,
      color: _parseColor(json['color']),
      textColor: _parseColor(json['textColor']),
      stackIndex: json['stackIndex'] as int? ?? 0,
      originalId: json['originalId'] as String?,
      isSummary: json['isSummary'] == true,
      isTimeRangeHighlight: json['isTimeRangeHighlight'] == true,
      isOverlapIndicator: json['isOverlapIndicator'] == true,
      completion: (json['completion'] as num?)?.toDouble() ?? 0.0,
      segments: (json['segments'] as List?)
          ?.map((e) => LegacyGanttTaskSegment(
                start: DateTime.parse(e['start']),
                end: DateTime.parse(e['end']),
                color: _parseColor(e['color']),
              ))
          .toList(),
      isMilestone: json['isMilestone'] == true,
      lastUpdated: parsedHlc,
      lastUpdatedBy: json['lastUpdatedBy'] as String?,
      resourceId: json['resourceId'] as String?,
      parentId: json['parentId'] as String?,
      baselineStart: json['baselineStart'] != null ? DateTime.parse(json['baselineStart']) : null,
      baselineEnd: json['baselineEnd'] != null ? DateTime.parse(json['baselineEnd']) : null,
      notes: json['notes'] as String?,
      usesWorkCalendar: json['usesWorkCalendar'] == true,
      load: (json['load'] as num?)?.toDouble() ?? 1.0,
      isAutoScheduled: json['isAutoScheduled'] == true,
      propagatesMoveToChildren: json['propagatesMoveToChildren'] ?? true,
      resizePolicy: json['resizePolicy'] != null
          ? ResizePolicy.values.firstWhere((e) => e.name == json['resizePolicy'], orElse: () => ResizePolicy.none)
          : ResizePolicy.none,
      fieldTimestamps: parsedFieldTimestamps,
      isDeleted: json['isDeleted'] == true,
    );
  }

  static Color? _parseColor(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return Color(int.parse(value, radix: 16));
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rowId': rowId,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
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
        'baselineStart': baselineStart?.toUtc().toIso8601String(),
        'baselineEnd': baselineEnd?.toUtc().toIso8601String(),
        'notes': notes,
        'usesWorkCalendar': usesWorkCalendar,
        'load': load,
        'isAutoScheduled': isAutoScheduled,
        'propagatesMoveToChildren': propagatesMoveToChildren,
        'resizePolicy': resizePolicy.name,
        'fieldTimestamps': fieldTimestamps.map((k, v) => MapEntry(k, v.toString())),
        'isDeleted': isDeleted,
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
          parentId == other.parentId &&
          baselineStart == other.baselineStart &&
          baselineEnd == other.baselineEnd &&
          notes == other.notes &&
          usesWorkCalendar == other.usesWorkCalendar &&
          load == other.load &&
          isAutoScheduled == other.isAutoScheduled &&
          propagatesMoveToChildren == other.propagatesMoveToChildren &&
          resizePolicy == other.resizePolicy &&
          mapEquals(fieldTimestamps, other.fieldTimestamps) &&
          isDeleted == other.isDeleted;

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
      isAutoScheduled.hashCode ^
      propagatesMoveToChildren.hashCode ^
      resizePolicy.hashCode ^
      Object.hashAll(fieldTimestamps.keys) ^
      Object.hashAll(fieldTimestamps.values) ^
      isDeleted.hashCode;

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

  String get contentHash {
    final data = {
      'id': id,
      'rowId': rowId,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'name': name,
      'color': _colorToHex(color)?.toRadixString(16),
      'textColor': _colorToHex(textColor)?.toRadixString(16),
      // Server MerkleService hardcodes these for now, so we must match to ensure consistent roots
      'stackIndex': 0,
      'originalId': id, // fallback matches server
      'isSummary': isSummary,
      'completion': completion,
      'segments': null,
      'isMilestone': isMilestone,
      'resourceId': resourceId,
      'parentId': parentId,
      'baselineStart': baselineStart?.toUtc().toIso8601String(),
      'baselineEnd': baselineEnd?.toUtc().toIso8601String(),
      'notes': notes,
      'usesWorkCalendar': usesWorkCalendar,
      'load': 1.0, // Server hardcodes 1.0
      'isAutoScheduled': false, // Server hardcodes false
      'isDeleted': isDeleted,
    };
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
