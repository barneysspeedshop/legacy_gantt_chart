import 'package:flutter_test/flutter_test.dart';
import 'package:example/utils/csv_importer.dart';
// For CsvImportMapping

void main() {
  group('CsvImporter', () {
    test('streamConvertRowsToTasks parses rows correctly in chunks', () async {
      final rows = [
        [
          'Key',
          'Summary',
          'Start',
          'End',
          'Assignee'
        ], // Header (to be skipped by caller usually, but logic handles it if index mappings are correct)
        ['T-1', 'Task 1', 'Jan 1 2023', 'Jan 5 2023', 'Alice'],
        ['T-2', 'Task 2', 'Jan 6 2023', 'Jan 10 2023', 'Bob'],
        ['T-3', 'Task 3', 'Jan 11 2023', 'Jan 15 2023', 'Alice'],
      ];

      const mapping = CsvImportMapping(
        keyColumnIndex: 0,
        nameColumnIndex: 1,
        startColumnIndex: 2,
        endColumnIndex: 3,
        resourceColumnIndex: 4,
      );

      // Use small chunk size to force multiple chunks
      final stream = CsvImporter.streamConvertRowsToTasks(
        rows.skip(1).toList(), // Skip header
        mapping,
        chunkSize: 2,
      );

      final chunks = await stream.toList();

      expect(chunks.length, greaterThanOrEqualTo(2));

      final allTasks = chunks.expand((c) => c.tasks).toList();
      final allResources = chunks.expand((c) => c.resources).toList();

      expect(allTasks.length, 3);
      expect(allResources.map((r) => r.name).toSet(),
          containsAll(['Alice', 'Bob'])); // Assignee rows usually created once unless chunked

      // Verify task details
      expect(allTasks.first.name, 'Task 1');
      expect(allTasks[1].name, 'Task 2');
    });

    test('streamConvertRowsToTasks respects existing resources', () async {
      final rows = [
        ['Summary', 'Assignee'],
        ['Task 1', 'Alice'],
      ];
      const mapping = CsvImportMapping(nameColumnIndex: 0, resourceColumnIndex: 1);

      // Pre-existing resource
      final existingResources = [
        (id: 'res-alice', name: 'Alice'),
      ];

      final stream = CsvImporter.streamConvertRowsToTasks(
        rows.skip(1).toList(),
        mapping,
        existingResourceNames: existingResources,
      );

      final chunks = await stream.toList();
      chunks.expand((c) => c.tasks).toList();
      final allResources = chunks.expand((c) => c.resources).toList();

      // Should NOT create new resource for Alice because it exists
      // However, CsvImporter logic adds to "chunkResources" if it encounters it?
      // Check logic: "if (!resourceMap.containsKey(safeName)) ... add to chunk"
      // Since we pass existingResources, it should be in map.
      // So no NEW resource for Alice.
      // BUT if the task needs a new row ID (under Alice), CsvImporter creates a row?
      // Logic: "String getAssigneeId... return resourceMap[safeName]!"
      // Then "assigneeKeyToRowMap" check...
      // If task doesn't have a key, it creates a NEW row (LocalResource) for the task.
      // And "resources.add(LocalResource(id: taskRowId ... parentId: assigneeId))"
      // So yes, a task row is added, but the Assignee Resource row is NOT added again.

      final aliceAssignee = allResources.any((r) => r.name == 'Alice' && r.id == 'res-alice');
      expect(aliceAssignee, isFalse, reason: 'Should not re-emit existing assignee resource');

      final taskRow = allResources.first; // The row for Task 1
      expect(taskRow.parentId, 'res-alice');
      expect(taskRow.name, 'Task 1');
    });
  });
}
