import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_resource.dart';

void main() {
  group('LegacyGanttResource', () {
    test('serialization and deserialization', () {
      final resource = LegacyGanttResource(
        id: 'r1',
        name: 'Resource 1',
        parentId: 'p1',
        isExpanded: false,
        ganttType: 'job',
        isDeleted: true,
      );

      final json = resource.toJson();
      final fromJson = LegacyGanttResource.fromJson(json);

      expect(fromJson.id, resource.id);
      expect(fromJson.name, resource.name);
      expect(fromJson.parentId, resource.parentId);
      expect(fromJson.isExpanded, resource.isExpanded);
      expect(fromJson.ganttType, resource.ganttType);
      expect(fromJson.isDeleted, resource.isDeleted);
    });

    test('serialization uses default values for missing keys', () {
      // Minimal JSON
      final json = {
        'id': 'r2',
        'name': 'Resource 2',
      };

      final fromJson = LegacyGanttResource.fromJson(json);

      expect(fromJson.id, 'r2');
      expect(fromJson.name, 'Resource 2');
      expect(fromJson.parentId, isNull);
      expect(fromJson.isExpanded, isFalse); // Default is false because json['isExpanded'] == true is false
      // Wait, viewing the source code:
      /*
      factory LegacyGanttResource.fromJson(Map<String, dynamic> json) => LegacyGanttResource(
        id: json['id'],
        name: json['name'],
        parentId: json['parentId'],
        isExpanded: json['isExpanded'] == true,
        ganttType: json['ganttType'] ?? 'person',
        isDeleted: json['isDeleted'] == true,
      );
      */
      expect(fromJson.ganttType, 'person');
      expect(fromJson.isDeleted, isFalse);
    });

    test('copyWith works correctly', () {
      final resource = LegacyGanttResource(
        id: 'r1',
        name: 'Old Name',
      );

      final updated = resource.copyWith(name: 'New Name', isExpanded: false);

      expect(updated.id, resource.id);
      expect(updated.name, 'New Name');
      expect(updated.isExpanded, false);
      // Original should remain unchanged
      expect(resource.name, 'Old Name');
      expect(resource.isExpanded, true); // default
    });

    test('contentHash is deterministic', () {
      final resource1 = LegacyGanttResource(
        id: 'r1',
        name: 'Resource 1',
      );

      final resource2 = LegacyGanttResource(
        id: 'r1',
        name: 'Resource 1',
      );

      expect(resource1.contentHash, resource2.contentHash);

      final resource3 = resource1.copyWith(name: 'Changed');
      expect(resource1.contentHash, isNot(resource3.contentHash));
    });

    test('toString contains key fields', () {
      final resource = LegacyGanttResource(
        id: 'r1',
        name: 'Test Resource',
      );

      final str = resource.toString();
      expect(str, contains('r1'));
      expect(str, contains('Test Resource'));
    });
  });
}
