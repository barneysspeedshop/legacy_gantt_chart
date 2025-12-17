import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/utils/resource_load_aggregator.dart';

void main() {
  group('aggregateResourceLoad', () {
    test('aggregates simple load for single task', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 3), // 1st and 2nd
        resourceId: 'User A',
        load: 1.0,
      );

      final result = aggregateResourceLoad([task]);

      expect(result.keys, ['User A']);
      final buckets = result['User A']!;
      expect(buckets.length, 3);
      expect(buckets[0].date, DateTime(2023, 1, 1));
      expect(buckets[0].totalLoad, 1.0);
      expect(buckets[1].date, DateTime(2023, 1, 2));
      expect(buckets[1].totalLoad, 1.0);
      expect(buckets[2].date, DateTime(2023, 1, 3));
      expect(buckets[2].totalLoad, 1.0);
    });

    test('sums load from overlapping tasks', () {
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        resourceId: 'User A',
        load: 0.5,
      );
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r2',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        resourceId: 'User A',
        load: 0.8,
      );

      final result = aggregateResourceLoad([task1, task2]);
      final buckets = result['User A']!;

      expect(buckets.length, 2);
      expect(buckets[0].totalLoad, 1.3);
      expect(buckets[0].isOverAllocated, true);
    });

    test('respects start and end bounds', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5),
        resourceId: 'User A',
      );

      final result = aggregateResourceLoad(
        [task],
        start: DateTime(2023, 1, 2),
        end: DateTime(2023, 1, 4),
      );

      final buckets = result['User A']!;
      expect(buckets.length, 3); // 2nd, 3rd, 4th
      expect(buckets[0].date, DateTime(2023, 1, 2));
      expect(buckets.last.date, DateTime(2023, 1, 4));
    });

    test('handles multiple resources', () {
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        resourceId: 'User A',
      );
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r2',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        resourceId: 'User B',
      );

      final result = aggregateResourceLoad([task1, task2]);
      expect(result.containsKey('User A'), true);
      expect(result.containsKey('User B'), true);
      expect(result['User A']!.length, 2);
      expect(result['User B']!.length, 2);
    });
  });
}
