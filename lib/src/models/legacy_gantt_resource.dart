import 'dart:convert';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'immutable_metadata.dart';

/// Represents a resource (person or job) in the Gantt chart.
class LegacyGanttResource {
  /// The unique identifier for the resource.
  final String id;

  /// The display name of the resource.
  final String name;

  /// The ID of the parent resource, if hierarchical.
  final String? parentId;

  /// Whether this resource group is expanded in the UI.
  final bool isExpanded;

  /// The type of resource ('person' or 'job').
  final String ganttType;

  /// Whether this resource has been marked as deleted (tombstone).
  final bool isDeleted;

  /// Metadata extensions retained across protocol round trips and edits.
  final Map<String, dynamic> extraMetadata;

  LegacyGanttResource({
    required this.id,
    required this.name,
    this.parentId,
    this.isExpanded = true,
    this.ganttType = 'person',
    this.isDeleted = false,
    Map<String, dynamic> extraMetadata = const {},
  }) : extraMetadata = immutableMetadata(extraMetadata);

  LegacyGanttResource copyWith({
    String? id,
    String? name,
    String? parentId,
    bool? isExpanded,
    String? ganttType,
    bool? isDeleted,
    Map<String, dynamic>? extraMetadata,
  }) => LegacyGanttResource(
    id: id ?? this.id,
    name: name ?? this.name,
    parentId: parentId ?? this.parentId,
    isExpanded: isExpanded ?? this.isExpanded,
    ganttType: ganttType ?? this.ganttType,
    isDeleted: isDeleted ?? this.isDeleted,
    extraMetadata: extraMetadata ?? this.extraMetadata,
  );

  ProtocolResource toProtocolResource() => ProtocolResource(
    id: id,
    name: name,
    parentId: parentId,
    type: ganttType,
    isDeleted: isDeleted,
    metadataJson: jsonEncode({
      ...extraMetadata,
      'isExpanded': isExpanded,
      'ganttType': ganttType, // Keep ganttType in metadata too if ProtocolResource uses 'type'
    }),
  );

  factory LegacyGanttResource.fromProtocolResource(ProtocolResource pr) {
    final metadata = ProtobufMapper.metadataFromJson({'metadataJson': pr.metadataJson});
    return LegacyGanttResource(
      id: pr.id,
      name: pr.name,
      parentId: pr.parentId.isEmpty ? null : pr.parentId,
      ganttType: metadata['ganttType'] ?? (pr.type.isEmpty ? 'person' : pr.type),
      isDeleted: pr.isDeleted,
      isExpanded: metadata['isExpanded'] != false,
      extraMetadata: Map<String, dynamic>.from(metadata)
        ..remove('ganttType')
        ..remove('isExpanded'),
    );
  }

  /// Calculates a deterministic hash of the resource's content for Merkle Tree synchronization.
  String get contentHash => toProtocolResource().contentHash;

  factory LegacyGanttResource.fromJson(Map<String, dynamic> json) => LegacyGanttResource(
    id: json['id'],
    name: json['name'],
    parentId: json['parentId'],
    isExpanded: json['isExpanded'] == true,
    ganttType: json['ganttType'] ?? 'person',
    isDeleted: json['isDeleted'] == true,
    extraMetadata: ProtobufMapper.metadataFromJson(json)..remove('isExpanded'),
  );

  Map<String, dynamic> toJson() => {
    ...extraMetadata,
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
