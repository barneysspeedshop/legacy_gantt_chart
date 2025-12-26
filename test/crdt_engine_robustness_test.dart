import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/sync/crdt_engine.dart';
import 'package:legacy_gantt_chart/src/sync/gantt_sync_client.dart';
import 'package:legacy_gantt_chart/src/sync/hlc.dart';

void main() {
  group('CRDTEngine Robustness', () {
    late CRDTEngine engine;

    setUp(() {
      engine = CRDTEngine();
    });

    test('should handle "start" and "end" keys (as well as variants)', () {
      final op = Operation(
        type: 'INSERT_TASK',
        data: {
          'id': 't1',
          'start': '2025-12-26T20:00:00.000Z',
          'end': '2025-12-27T20:00:00.000Z',
          'name': 'Test Task',
        },
        timestamp: Hlc.parse('2025-12-26T20:05:00.000Z-0000-node1'),
        actorId: 'node1',
      );

      final result = engine.mergeTasks([], [op]);
      expect(result.length, 1);
      expect(result.first.start, equals(DateTime.utc(2025, 12, 26, 20)));
      expect(result.first.end, equals(DateTime.utc(2025, 12, 27, 20)));
    });

    test('should use defaults (not 0 duration) on parsing failure', () {
      final op = Operation(
        type: 'INSERT_TASK',
        data: {
          'id': 't2',
          'start': 'garbage',
          'end': 'more_garbage',
        },
        timestamp: Hlc.parse('2025-12-26T20:10:00.000Z-0000-node1'),
        actorId: 'node1',
      );

      final result = engine.mergeTasks([], [op]);
      expect(result.length, 1);
      final task = result.first;

      // Should NOT be 0 duration
      expect(task.end.isAfter(task.start), isTrue);
      expect(task.end.difference(task.start).inHours, equals(24));
    });

    test('should preserve duration if only start is updated (or vice versa) via existing fallback', () {
      // First create a task
      final op1 = Operation(
        type: 'INSERT_TASK',
        data: {
          'id': 't3',
          'start_date': '2025-12-26T10:00:00.000Z',
          'end_date': '2025-12-26T12:00:00.000Z',
        },
        timestamp: Hlc.parse('2025-12-26T10:00:00.000Z-0000-node1'),
        actorId: 'node1',
      );

      // Update only start with a different key format
      final op2 = Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': 't3',
          'startDate': '2025-12-26T11:00:00.000Z',
        },
        timestamp: Hlc.parse('2025-12-26T11:00:00.000Z-0000-node1'),
        actorId: 'node1',
      );

      final result = engine.mergeTasks([], [op1, op2]);
      expect(result.length, 1);
      expect(result.first.start, equals(DateTime.utc(2025, 12, 26, 11)));
      expect(result.first.end, equals(DateTime.utc(2025, 12, 26, 12))); // Preserved from op1
    });
  });
}
