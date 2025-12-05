import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/utils/legacy_gantt_conflict_detector.dart';

void main() {
  test('Conflict Detector generates unique IDs for multiple overlaps', () {
    final taskA = LegacyGanttTask(
      id: 'A',
      rowId: '1',
      start: DateTime(2023, 1, 1, 10),
      end: DateTime(2023, 1, 1, 12),
      name: 'Task A',
    );
    final taskB = LegacyGanttTask(
      id: 'B',
      rowId: '1',
      start: DateTime(2023, 1, 1, 11),
      end: DateTime(2023, 1, 1, 13),
      name: 'Task B',
    );
    final taskC = LegacyGanttTask(
      id: 'C',
      rowId: '1',
      start: DateTime(2023, 1, 1, 11, 30),
      end: DateTime(2023, 1, 1, 13, 30),
      name: 'Task C',
    );

    final detector = LegacyGanttConflictDetector();
    final indicators = detector.run(
      tasks: [taskA, taskB, taskC],
      taskGrouper: (t) => t.rowId,
    );

    print('Generated ${indicators.length} indicators.');
    for (var i in indicators) {
      print('${i.id}: ${i.start} - ${i.end}');
    }

    final ids = indicators.map((t) => t.id).toList();
    final uniqueIds = ids.toSet();

    if (ids.length != uniqueIds.length) {
      fail('Duplicate IDs generated: ${ids.length} total vs ${uniqueIds.length} unique.');
    }
  });
}
