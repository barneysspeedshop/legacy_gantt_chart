import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/sync/gantt_sync_client.dart';
import 'package:legacy_gantt_chart/src/sync/hlc.dart';

/// A mock implementation of GanttSyncClient for testing purposes.
class MockGanttSyncClient implements GanttSyncClient {
  final _controller = StreamController<Operation>.broadcast();
  final List<Operation> sentOperations = [];

  @override
  Stream<Operation> get operationStream => _controller.stream;

  @override
  Future<void> sendOperation(Operation operation) async {
    sentOperations.add(operation);
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    for (final op in operations) {
      await sendOperation(op);
    }
  }

  @override
  Future<List<Operation>> getInitialState() async => [];

  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {}

  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'mock');

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));

  // Helper to simulate receiving an operation from a remote source.
  void receiveOperation(Operation op) {
    _controller.add(op);
  }

  @override
  Future<String> getMerkleRoot() async => '';

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {}
}

void main() {
  group('Operation', () {
    test('should initialize correctly with constructor', () {
      final operation = Operation(
        type: 'update',
        data: {'key': 'value'},
        timestamp: Hlc.fromIntTimestamp(1234567890),
        actorId: 'user1',
      );

      expect(operation.type, 'update');
      expect(operation.data, {'key': 'value'});
      expect(operation.timestamp, Hlc.fromIntTimestamp(1234567890));
      expect(operation.actorId, 'user1');
    });

    test('should serialize to JSON correctly via toJson', () {
      final operation = Operation(
        type: 'insert',
        data: {'id': 1, 'name': 'task'},
        timestamp: Hlc.fromIntTimestamp(1000),
        actorId: 'abc',
      );

      final json = operation.toJson();

      expect(json, {
        'type': 'insert',
        'data': {'id': 1, 'name': 'task'},
        'timestamp': Hlc.fromIntTimestamp(1000).toString(),
        'actorId': 'abc',
      });
    });

    test('should deserialize from JSON correctly via fromJson', () {
      final json = {
        'type': 'delete',
        'data': {'id': 2},
        'timestamp': Hlc.fromIntTimestamp(2000).toString(),
        'actorId': 'xyz',
      };

      final operation = Operation.fromJson(json);

      expect(operation.type, 'delete');
      expect(operation.data, {'id': 2});
      expect(operation.timestamp, Hlc.fromIntTimestamp(2000));
      expect(operation.actorId, 'xyz');
    });

    test('should remain equal after toJson and fromJson roundtrip', () {
      final originalOp = Operation(
        type: 'move',
        data: {'taskId': 't1', 'newStart': '2025-12-01'},
        timestamp: Hlc.fromIntTimestamp(1672531200),
        actorId: 'user-2',
      );

      final json = originalOp.toJson();
      final reconstructedOp = Operation.fromJson(json);

      expect(reconstructedOp, originalOp);
    });
  });

  group('GanttSyncClient', () {
    test('can be implemented and used', () {
      // This test verifies that the abstract class can be implemented.
      expect(MockGanttSyncClient(), isA<GanttSyncClient>());
    });
  });
}
