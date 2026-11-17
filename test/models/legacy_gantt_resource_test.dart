import 'dart:convert';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_resource.dart';

void main() {
  group('LegacyGanttResource', () {
    test('constructs with default values', () {
      final resource = LegacyGanttResource(id: 'r1', name: 'Resource 1');
      expect(resource.id, 'r1');
      expect(resource.name, 'Resource 1');
      expect(resource.parentId, isNull);
      expect(resource.isExpanded, isTrue);
      expect(resource.ganttType, 'person');
      expect(resource.isDeleted, isFalse);
    });

    test('copyWith creates a new instance with updated values', () {
      final original = LegacyGanttResource(
        id: 'r1',
        name: 'Original',
        parentId: 'p1',
        isExpanded: false,
        ganttType: 'job',
        isDeleted: true,
      );

      final updated = original.copyWith(name: 'Updated', isExpanded: true);

      expect(updated.id, 'r1');
      expect(updated.name, 'Updated');
      expect(updated.parentId, 'p1');
      expect(updated.isExpanded, isTrue);
      expect(updated.ganttType, 'job');
      expect(updated.isDeleted, isTrue);

      // Verify original is unchanged
      expect(original.name, 'Original');
      expect(original.isExpanded, isFalse);
    });

    test('converts to/from protocol resource correctly', () {
      final original = LegacyGanttResource(
        id: 'r1',
        name: 'Test Resource',
        parentId: 'p1',
        isExpanded: false,
        ganttType: 'job',
        isDeleted: false,
      );

      final protocolResource = original.toProtocolResource();
      expect(protocolResource.id, original.id);
      expect(protocolResource.name, original.name);
      expect(protocolResource.parentId, original.parentId);
      expect(protocolResource.type, original.ganttType);
      expect(protocolResource.isDeleted, original.isDeleted);
      expect((jsonDecode(protocolResource.metadataJson) as Map<String, dynamic>)['isExpanded'], original.isExpanded);

      final restored = LegacyGanttResource.fromProtocolResource(protocolResource);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.parentId, original.parentId);
      expect(restored.isExpanded, original.isExpanded);
      expect(restored.ganttType, original.ganttType);
      expect(restored.isDeleted, original.isDeleted);
    });

    test('converts to/from json correctly', () {
      final original = LegacyGanttResource(
        id: 'r1',
        name: 'JSON Test',
        parentId: 'p1',
        isExpanded: false,
        ganttType: 'person',
        isDeleted: true,
      );

      final json = original.toJson();
      expect(json['id'], 'r1');
      expect(json['name'], 'JSON Test');
      expect(json['parentId'], 'p1');
      expect(json['isExpanded'], isFalse);
      expect(json['ganttType'], 'person');
      expect(json['isDeleted'], isTrue);

      final restored = LegacyGanttResource.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.parentId, original.parentId);
      expect(restored.isExpanded, original.isExpanded);
      expect(restored.ganttType, original.ganttType);
      expect(restored.isDeleted, original.isDeleted);
    });

    test('provides a contentHash delegate', () {
      final resource = LegacyGanttResource(id: 'r1', name: 'Hash Test');
      expect(resource.contentHash, isNotEmpty);
      expect(resource.contentHash, equals(resource.toProtocolResource().contentHash));
    });

    for (final deleted in [false, true]) {
      test('metadata extensions survive resource protocol round trips (deleted: $deleted)', () {
        final protocol = ProtocolResource(
          id: 'r-extra',
          name: 'Equipment',
          type: 'tool',
          isDeleted: deleted,
          metadataJson: jsonEncode({
            'ganttType': 'tool',
            'isExpanded': false,
            'category': 'equipment',
            'custom': {'rate': 3},
            'labels': ['shared'],
          }),
        );
        final resource = LegacyGanttResource.fromProtocolResource(protocol);
        expect(resource.contentHash, protocol.contentHash);
        expect(resource.copyWith().contentHash, protocol.contentHash);
        final edited = resource.copyWith(name: 'Updated Equipment');
        final metadata = jsonDecode(edited.toProtocolResource().metadataJson) as Map<String, dynamic>;
        expect(metadata['category'], 'equipment');
        expect(metadata['custom'], {'rate': 3});
        expect(metadata['labels'], ['shared']);
        expect(metadata['isExpanded'], isFalse);
        expect(metadata['ganttType'], 'tool');
        expect(LegacyGanttResource.fromJson(resource.toJson()).contentHash, protocol.contentHash);
        expect(() => resource.extraMetadata['category'] = 'changed', throwsUnsupportedError);
        expect(() => (resource.extraMetadata['custom'] as Map)['rate'] = 4, throwsUnsupportedError);
        expect(() => (resource.extraMetadata['labels'] as List).add('changed'), throwsUnsupportedError);
      });
    }

    test('omitted resource scalars retain hashes through public defaults', () {
      final protocol = ProtocolResource(id: 'resource');
      final resource = LegacyGanttResource.fromProtocolResource(protocol);
      expect(resource.ganttType, 'person');
      expect(resource.isExpanded, isTrue);
      expect(resource.contentHash, protocol.contentHash);
    });

    test('toString returns a descriptive string', () {
      final resource = LegacyGanttResource(id: 'r1', name: 'String Test');
      final str = resource.toString();
      expect(str, contains('r1'));
      expect(str, contains('String Test'));
      expect(str, startsWith('LegacyGanttResource{'));
    });
  });
}
