import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Represents a resource (person or job) in the Gantt chart.
class LegacyGanttResource {
  final String id;
  final String name;
  final String? parentId;
  final bool isExpanded;
  final String ganttType; // 'person' or 'job'

  // Metadata for sync
  final bool isDeleted;

  LegacyGanttResource({
    required this.id,
    required this.name,
    this.parentId,
    this.isExpanded = true,
    this.ganttType = 'person',
    this.isDeleted = false,
  });

  LegacyGanttResource copyWith({
    String? id,
    String? name,
    String? parentId,
    bool? isExpanded,
    String? ganttType,
    bool? isDeleted,
  }) =>
      LegacyGanttResource(
        id: id ?? this.id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
        isExpanded: isExpanded ?? this.isExpanded,
        ganttType: ganttType ?? this.ganttType,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  /// Calculates a deterministic hash of the resource's content for Merkle Tree synchronization.
  String get contentHash {
    final data = {
      'id': id,
      'name': name,
      'parentId': parentId,
      'isExpanded': isExpanded,
      'ganttType': ganttType,
      'isDeleted': isDeleted,
    };
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    return sha256.convert(bytes).toString();
  }

  factory LegacyGanttResource.fromJson(Map<String, dynamic> json) => LegacyGanttResource(
        id: json['id'],
        name: json['name'],
        parentId: json['parentId'],
        isExpanded: json['isExpanded'] == true,
        ganttType: json['ganttType'] ?? 'person',
        isDeleted: json['isDeleted'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'isExpanded': isExpanded,
        'ganttType': ganttType,
        'isDeleted': isDeleted,
      };

  @override
  String toString() =>
      'LegacyGanttResource{id: $id, name: $name, parentId: $parentId, isExpanded: $isExpanded, ganttType: $ganttType, isDeleted: $isDeleted}';
}
