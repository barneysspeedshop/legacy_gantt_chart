import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:example/sync/offline_gantt_sync_client.dart';
import 'package:example/sync/websocket_gantt_sync_client.dart';
import 'package:example/data/local/gantt_db.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:path/path.dart' as p;

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

    late String testDbPath;

    setUp(() async {
      mockInner = MockInnerClient();
      await GanttDb.reset();

      final tempDir = Directory.systemTemp.createTempSync();
      // Use microseconds and extra randomness to prevent collision in fast tests
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(mockInner)}';
      testDbPath = p.join(tempDir.path, 'test_gantt_$uniqueId.db');
      GanttDb.overridePath = testDbPath;

      // Ensure DB is created and empty (though new file should be empty)
      await GanttDb.db;

      client = OfflineGanttSyncClient(mockInner);
      // Wait for db init in the client
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await client.dispose();
      await GanttDb.reset(); // Close DB connection
      try {
        if (File(testDbPath).existsSync()) {
          File(testDbPath).deleteSync();
        }
      } catch (e) {
        print('Error deleting test db: $e');
      }
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
  });
}
