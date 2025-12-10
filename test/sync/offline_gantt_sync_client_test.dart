import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
// ignore: implementation_imports
import 'package:legacy_gantt_chart/src/sync/offline_gantt_sync_client.dart';
// ignore: implementation_imports
import 'package:legacy_gantt_chart/src/sync/websocket_gantt_sync_client.dart';

class MockInnerClient implements WebSocketGanttSyncClient {
  final connectionController = StreamController<bool>.broadcast();
  final operationController = StreamController<Operation>.broadcast();
  final sentOperations = <Operation>[];
  bool shouldFailSend = false;

  @override
  Stream<bool> get connectionStateStream => connectionController.stream;

  @override
  Stream<Operation> get operationStream => operationController.stream;

  @override
  Future<void> sendOperation(Operation operation) async {
    if (shouldFailSend) throw Exception('Offline simulation');
    sentOperations.add(operation);
  }

  @override
  void connect(String tenantId) {}

  @override
  Future<void> dispose() async {
    await connectionController.close();
    await operationController.close();
  }

  @override
  Uri get uri => Uri.parse('ws://mock');

  @override
  String? get authToken => 'mock';

  @override
  Future<List<Operation>> getInitialState() async => [];
}

void main() {
  // Initialize FFI for SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('OfflineGanttSyncClient', () {
    late MockInnerClient mockInner;
    late OfflineGanttSyncClient client;

    setUp(() async {
      mockInner = MockInnerClient();

      // Use in-memory DB
      final dbFuture = SqliteCrdt.openInMemory(
        version: 1,
        onCreate: (db, version) async {},
      );

      client = OfflineGanttSyncClient(dbFuture, mockInner);
      // Wait for db init in the client
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await client.dispose();
    });

    test('Passes operations through when online', () async {
      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(Duration.zero); // Let listener process

      final op = Operation(type: 'ONLINE', data: {}, timestamp: 1, actorId: 'A');
      await client.sendOperation(op);

      // Wait for async flush
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockInner.sentOperations, hasLength(1));
      expect(mockInner.sentOperations.first.type, 'ONLINE');
    });

    test('Queues operations when send fails (offline)', () async {
      mockInner.shouldFailSend = true;

      final op = Operation(type: 'OFFLINE', data: {}, timestamp: 2, actorId: 'A');
      await client.sendOperation(op);

      expect(mockInner.sentOperations, isEmpty);

      // Simulate reconnect
      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);

      // Wait for flush (minimal delay for async db)
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockInner.sentOperations, hasLength(1));
      expect(mockInner.sentOperations.first.type, 'OFFLINE');
    });

    test('Preserves order of queued operations', () async {
      mockInner.shouldFailSend = true;

      await client.sendOperation(Operation(type: 'msg1', data: {}, timestamp: 1, actorId: 'A'));
      await client.sendOperation(Operation(type: 'msg2', data: {}, timestamp: 2, actorId: 'A'));
      await client.sendOperation(Operation(type: 'msg3', data: {}, timestamp: 3, actorId: 'A'));

      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockInner.sentOperations, hasLength(3));
      expect(mockInner.sentOperations[0].type, 'msg1');
      expect(mockInner.sentOperations[1].type, 'msg2');
      expect(mockInner.sentOperations[2].type, 'msg3');
    });

    test('Flushes queue before sending new online operation', () async {
      mockInner.shouldFailSend = true;
      await client.sendOperation(Operation(type: 'OFFLINE_OP', data: {}, timestamp: 1, actorId: 'A'));

      mockInner.shouldFailSend = false;
      // Signal online. This triggers auto-flush.
      mockInner.connectionController.add(true);
      await Future.delayed(Duration.zero);

      // Even if we call send immediately, it should await the flush lock or append after.
      // Actually with the new logic, sendOperation calls _flushQueue first.

      await client.sendOperation(Operation(type: 'ONLINE_OP', data: {}, timestamp: 2, actorId: 'A'));

      // Wait for async flush
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockInner.sentOperations, hasLength(2));
      expect(mockInner.sentOperations[0].type, 'OFFLINE_OP');
      expect(mockInner.sentOperations[1].type, 'ONLINE_OP');
    });

    test('Handles concurrent flushing and queuing without locking DB', () async {
      // 1. Queue many items
      mockInner.shouldFailSend = true;
      for (int i = 0; i < 50; i++) {
        await client.sendOperation(Operation(type: 'MSG_$i', data: {}, timestamp: i, actorId: 'A'));
      }

      // 2. Go online. Flush starts.
      // We simulate a slow network send in the mock to keep the flush active.
      mockInner.shouldFailSend = false;
      // We need to subclass MockInner to add delay or modify it.
      // For now, let's just hammer 'sendOperation' while it's flushing.

      mockInner.connectionController.add(true);

      // 3. Immediately queue more items concurrently
      final future1 = client.sendOperation(Operation(type: 'CONCURRENT_1', data: {}, timestamp: 100, actorId: 'A'));
      final future2 = client.sendOperation(Operation(type: 'CONCURRENT_2', data: {}, timestamp: 101, actorId: 'A'));

      await Future.wait<void>([future1, future2]);

      // Wait for everything to flush
      await Future.delayed(const Duration(seconds: 1));

      expect(mockInner.sentOperations.length, 52);
      expect(mockInner.sentOperations.last.type, isNotNull);
    });
    test('Drops ephemeral operations when offline', () async {
      mockInner.shouldFailSend = true;

      // Send ephemeral operations
      await client.sendOperation(Operation(type: 'CURSOR_MOVE', data: {}, timestamp: 1, actorId: 'A'));
      await client.sendOperation(Operation(type: 'GHOST_UPDATE', data: {}, timestamp: 2, actorId: 'A'));

      // Send a normal operation
      await client.sendOperation(Operation(type: 'NORMAL_OP', data: {}, timestamp: 3, actorId: 'A'));

      // Reconnect
      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);

      // Wait for flush
      await Future.delayed(const Duration(milliseconds: 100));

      // Should only see the normal operation
      expect(mockInner.sentOperations, hasLength(1));
      expect(mockInner.sentOperations.first.type, 'NORMAL_OP');
    });
  });
}
