// packages/gantt_chart/lib/src/models/gantt_row.dart
import 'package:flutter/foundation.dart';

/// Represents a row in the Gantt chart.
@immutable
class LegacyGanttRow {
  final String id;
  final int? lastUpdated;
  final String? lastUpdatedBy;

  const LegacyGanttRow({
    required this.id,
    this.label,
    this.lastUpdated,
    this.lastUpdatedBy,
  });

  final String? label;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LegacyGanttRow && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
