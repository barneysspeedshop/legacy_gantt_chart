import 'package:flutter/foundation.dart';

/// Represents the aggregated load for a specific resource on a specific date.
@immutable
class ResourceBucket {
  final DateTime date;
  final String resourceId;
  final double totalLoad;

  const ResourceBucket({
    required this.date,
    required this.resourceId,
    this.totalLoad = 0.0,
  });

  /// 1.0 = 100% capacity.
  bool get isOverAllocated => totalLoad > 1.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceBucket &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          resourceId == other.resourceId &&
          totalLoad == other.totalLoad;

  @override
  int get hashCode => date.hashCode ^ resourceId.hashCode ^ totalLoad.hashCode;

  ResourceBucket copyWith({
    DateTime? date,
    String? resourceId,
    double? totalLoad,
  }) =>
      ResourceBucket(
        date: date ?? this.date,
        resourceId: resourceId ?? this.resourceId,
        totalLoad: totalLoad ?? this.totalLoad,
      );
}
