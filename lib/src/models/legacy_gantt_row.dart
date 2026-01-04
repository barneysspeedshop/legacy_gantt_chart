// packages/gantt_chart/lib/src/models/gantt_row.dart
import 'package:flutter/foundation.dart';

/// Represents a row in the Gantt chart.
@immutable
class LegacyGanttRow {
  /// The unique identifier for this row.
  final String id;

  /// The timestamp of the last update to this row.
  final int? lastUpdated;

  /// The ID of the user who last updated this row.
  final String? lastUpdatedBy;

  const LegacyGanttRow({
    required this.id,
    this.label,
    this.lastUpdated,
    this.lastUpdatedBy,
  });

  /// The display label for the row (e.g., resource name).
  final String? label;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LegacyGanttRow && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
