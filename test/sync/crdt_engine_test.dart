import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/sync/crdt_engine.dart';
import 'package:legacy_gantt_chart/src/sync/gantt_sync_client.dart';

class MockGanttSyncClient implements GanttSyncClient {
  final _controller = StreamController<Operation>.broadcast();

  @override
  Stream<Operation> get operationStream => _controller.stream;

  @override
  Future<void> sendOperation(Operation operation) async {
    // In a real mock, you might add it to a list of sent operations.
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    // No-op
  }

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));

  void addOperation(Operation op) {
    _controller.add(op);
  }
}

void main() {
  // Note: The tests for the 'Operation' class that were previously here
  // are now in `test/sync/operation_test.dart` for better organization.
  group('CRDTEngine', () {
    late CRDTEngine engine;

    setUp(() {
      engine = CRDTEngine();
    });

    test('should merge new task update', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5),
        name: 'Task 1',
      );

      final op = Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': '1',
          'rowId': 'row1',
          'start': DateTime(2023, 1, 2).toIso8601String(),
          'end': DateTime(2023, 1, 6).toIso8601String(),
          'name': 'Task 1 Updated',
        },
        timestamp: 100,
        actorId: 'user1',
      );

      final result = engine.mergeTasks([task], [op]);

      expect(result.length, 1);
      expect(result.first.start, DateTime(2023, 1, 2));
      expect(result.first.end, DateTime(2023, 1, 6));
      expect(result.first.name, 'Task 1 Updated');
      expect(result.first.lastUpdated, 100);
      expect(result.first.lastUpdatedBy, 'user1');
    });

    test('should ignore older update', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023, 1, 2),
        end: DateTime(2023, 1, 6),
        name: 'Task 1 Updated',
        lastUpdated: 200,
        lastUpdatedBy: 'user1',
      );

      final op = Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': '1',
          'rowId': 'row1',
          'start': DateTime(2023, 1, 1).toIso8601String(),
          'end': DateTime(2023, 1, 5).toIso8601String(),
          'name': 'Task 1 Old',
        },
        timestamp: 100,
        actorId: 'user2',
      );

      final result = engine.mergeTasks([task], [op]);

      expect(result.length, 1);
      expect(result.first.start, DateTime(2023, 1, 2)); // Should remain unchanged
      expect(result.first.name, 'Task 1 Updated');
    });

    test('should handle new task creation via update', () {
      final op = Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': '2',
          'rowId': 'row1',
          'start': DateTime(2023, 1, 1).toIso8601String(),
          'end': DateTime(2023, 1, 5).toIso8601String(),
          'name': 'Task 2',
        },
        timestamp: 100,
        actorId: 'user1',
      );

      final result = engine.mergeTasks([], [op]);

      expect(result.length, 1);
      expect(result.first.id, '2');
      expect(result.first.name, 'Task 2');
    });
  });

  group('GanttSyncClient', () {
    test('can be implemented', () {
      // This test simply verifies that the abstract class can be implemented
      // without issue.
      expect(MockGanttSyncClient(), isA<GanttSyncClient>());
    });
  });
}
