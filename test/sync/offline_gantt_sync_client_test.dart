import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/offline_sync.dart';
// ignore: implementation_imports
// ignore: implementation_imports

class MockInnerClient implements WebSocketGanttSyncClient {
  final connectionController = StreamController<bool>.broadcast();
  final operationController = StreamController<Operation>.broadcast();
  final sentOperations = <Operation>[];
  bool shouldFailSend = false;

  @override
  int get correctedTimestamp => DateTime.now().millisecondsSinceEpoch;

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
  Future<void> sendOperations(List<Operation> operations) async {
    for (final op in operations) {
      await sendOperation(op);
    }
  }

  @override
  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {}

  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'mock');

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

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));

  @override
  Future<String> getMerkleRoot() async => '';

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {}

  @override
  String get actorId => 'mock-inner-actor';

  @override
  String? get userId => 'mock-user-id';
}

void main() {
  // Initialize FFI for SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('OfflineGanttSyncClient', () {
    late MockInnerClient mockInner;
    late OfflineGanttSyncClient client;
    late SqliteCrdt crdt;

    setUp(() async {
      mockInner = MockInnerClient();

      // Use in-memory DB
      final dbFuture = SqliteCrdt.openInMemory(
        version: 1,
        onCreate: (db, version) async {},
      );
      crdt = await dbFuture;

      client = OfflineGanttSyncClient(Future.value(crdt), mockInner);
      // Wait for db init in the client (creates the table)
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await client.dispose();
    });

    test('Passes operations through when online', () async {
      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(Duration.zero); // Let listener process

      final op = Operation(type: 'ONLINE', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A');
      await client.sendOperation(op);

      // Wait for async flush
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockInner.sentOperations, hasLength(1));
      expect(mockInner.sentOperations.first.type, 'ONLINE');
    });

    test('Delegates Hlc and ActorId to inner client', () {
      expect(client.actorId, 'mock-inner-actor');
      expect(client.currentHlc.nodeId, 'mock');
    });

    test('Uses fallback Hlc and ActorId when no inner client', () async {
      await client.removeInnerClient();
      expect(client.actorId, 'offline-user');
      expect(client.currentHlc.nodeId, 'offline-client');
    });

    test('Manages inner client switches correctly', () async {
      final newMock = MockInnerClient();
      await client.setInnerClient(newMock);

      newMock.connectionController.add(true);
      await Future.delayed(Duration.zero);

      await client
          .sendOperation(Operation(type: 'NEW_CLIENT', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(newMock.sentOperations, hasLength(1));
      expect(mockInner.sentOperations, isEmpty);

      await newMock.dispose();
    });

    test('removeInnerClient updates connection state', () async {
      final expectation = expectLater(client.connectionStateStream, emitsInOrder([true, false]));

      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));
      await client.removeInnerClient();

      await expectation;
    });

    test('Queues operations when send fails (offline)', () async {
      mockInner.shouldFailSend = true;

      final op = Operation(type: 'OFFLINE', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A');
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

      await client.sendOperation(Operation(type: 'msg1', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await client.sendOperation(Operation(type: 'msg2', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A'));
      await client.sendOperation(Operation(type: 'msg3', data: {}, timestamp: Hlc.fromIntTimestamp(3), actorId: 'A'));

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
      await client
          .sendOperation(Operation(type: 'OFFLINE_OP', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await Future.delayed(const Duration(milliseconds: 50));

      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));

      await client
          .sendOperation(Operation(type: 'ONLINE_OP', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A'));

      await Future.delayed(const Duration(milliseconds: 200));

      expect(mockInner.sentOperations, hasLength(2));
      expect(mockInner.sentOperations[0].type, 'OFFLINE_OP');
      expect(mockInner.sentOperations[1].type, 'ONLINE_OP');
    });

    test('Outbound pending count stream updates correctly', () async {
      mockInner.shouldFailSend = true;
      final results = <int>[];
      final sub = client.outboundPendingCount.listen(results.add);

      await Future.delayed(Duration.zero); // Initial 0

      await client.sendOperation(Operation(type: 'OP1', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await client.sendOperation(Operation(type: 'OP2', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A'));
      await Future.delayed(const Duration(milliseconds: 100));

      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(results.last, 0);
      expect(results, contains(1));
      expect(results, contains(2));

      await sub.cancel();
    });

    test('Handles concurrent flushing and queuing without locking DB', () async {
      // 1. Queue many items
      mockInner.shouldFailSend = true;
      for (int i = 0; i < 50; i++) {
        await client
            .sendOperation(Operation(type: 'MSG_$i', data: {}, timestamp: Hlc.fromIntTimestamp(i), actorId: 'A'));
      }

      // 2. Go online. Flush starts.
      // We simulate a slow network send in the mock to keep the flush active.
      mockInner.shouldFailSend = false;
      // We need to subclass MockInner to add delay or modify it.
      // For now, let's just hammer 'sendOperation' while it's flushing.

      mockInner.connectionController.add(true);

      // 3. Immediately queue more items concurrently
      final future1 = client
          .sendOperation(Operation(type: 'CONCURRENT_1', data: {}, timestamp: Hlc.fromIntTimestamp(100), actorId: 'A'));
      final future2 = client
          .sendOperation(Operation(type: 'CONCURRENT_2', data: {}, timestamp: Hlc.fromIntTimestamp(101), actorId: 'A'));

      await Future.wait<void>([future1, future2]);

      // Wait for everything to flush
      await Future.delayed(const Duration(seconds: 1));

      expect(mockInner.sentOperations.length, 52);
      expect(mockInner.sentOperations.last.type, isNotNull);
    });
    test('Drops ephemeral operations when offline', () async {
      mockInner.shouldFailSend = true;

      // Send ephemeral operations
      await client
          .sendOperation(Operation(type: 'CURSOR_MOVE', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await client
          .sendOperation(Operation(type: 'GHOST_UPDATE', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A'));

      // Send a normal operation
      await client
          .sendOperation(Operation(type: 'NORMAL_OP', data: {}, timestamp: Hlc.fromIntTimestamp(3), actorId: 'A'));

      // Reconnect
      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);

      // Wait for flush
      await Future.delayed(const Duration(milliseconds: 100));

      // Should only see the normal operation
      expect(mockInner.sentOperations, hasLength(1));
      expect(mockInner.sentOperations.first.type, 'NORMAL_OP');
    });

    test('sendOperations sends directly when online and queue empty', () async {
      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));

      final ops = [
        Operation(type: 'BATCH1', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'),
        Operation(type: 'BATCH2', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A'),
      ];

      await client.sendOperations(ops);
      await Future.delayed(const Duration(milliseconds: 100)); // Wait for async queue & flush

      expect(mockInner.sentOperations, hasLength(2));
      expect(mockInner.sentOperations.map((e) => e.type), containsAll(['BATCH1', 'BATCH2']));
    });

    test('sendOperations drains small queue and bundles with new ops', () async {
      mockInner.shouldFailSend = true;
      await client.sendOperation(Operation(type: 'QUEUED', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await Future.delayed(const Duration(milliseconds: 50));

      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));

      final newOps = [
        Operation(type: 'NEW', data: {}, timestamp: Hlc.fromIntTimestamp(2), actorId: 'A'),
      ];

      await client.sendOperations(newOps);
      await Future.delayed(const Duration(milliseconds: 200)); // Wait for both flushes

      expect(mockInner.sentOperations, hasLength(2));
      expect(mockInner.sentOperations.map((o) => o.type), containsAll(['QUEUED', 'NEW']));
    });

    test('Delegates sync methods to inner client', () async {
      final initialState = await client.getInitialState();
      expect(initialState, isEmpty);

      final root = await client.getMerkleRoot();
      expect(root, '');

      await client.syncWithMerkle(remoteRoot: 'root', depth: 1);
    });

    test('clearQueue and dispose work correctly', () async {
      mockInner.shouldFailSend = true;
      await client
          .sendOperation(Operation(type: 'TO_BE_CLEARED', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'A'));
      await Future.delayed(const Duration(milliseconds: 50));

      await client.clearQueue();
      await Future.delayed(const Duration(milliseconds: 50));

      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 50)); // Propagation
      await client.dispose();

      expect(mockInner.sentOperations, isEmpty);
    });

    test('Maps start/end to start_date/end_date during send and flush', () async {
      mockInner.shouldFailSend = true;
      await client.sendOperation(Operation(
        type: 'MAP_TEST',
        data: {'start': '2023-01-01', 'end': '2023-01-02'},
        timestamp: Hlc.fromIntTimestamp(1),
        actorId: 'A',
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      mockInner.shouldFailSend = false;
      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 100)); // Let it start
      await client.dispose();

      expect(mockInner.sentOperations.isNotEmpty, isTrue);
      expect(mockInner.sentOperations.first.data['start_date'], '2023-01-01');
      expect(mockInner.sentOperations.first.data.containsKey('start'), isFalse);
    });

    test('Handles malformed JSON in offline queue', () async {
      await crdt.execute(
        'INSERT INTO offline_queue (type, data, timestamp, actor_id) VALUES (?, ?, ?, ?)',
        ['BAD_JSON', '{invalid_json}', Hlc.fromIntTimestamp(1).toString(), 'A'],
      );
      await Future.delayed(const Duration(milliseconds: 50));

      mockInner.connectionController.add(true);
      await Future.delayed(const Duration(milliseconds: 100)); // Let it start
      await client.dispose();

      final countResult = await crdt.query('SELECT COUNT(*) FROM offline_queue WHERE is_deleted = 0');
      expect(countResult.first.values.first, 0);
    });

    test('Delegates inboundProgress to inner client', () {
      final stream = client.inboundProgress;
      expect(stream, isNotNull);
    });
  });
}
