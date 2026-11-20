import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:example/data/local/gantt_db.dart';

class FakeSyncClient implements WebSocketGanttSyncClient {
  final _operationController = StreamController<Operation>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final List<Operation> sentOperations = [];
  bool isConnected = false;
  Hlc? lastConnectedCursor;
  bool isDisposed = false;

  Completer<void>? merkleGate;
  final merkleRequests = StreamController<MerkleTree>.broadcast();
  @override
  String get actorId => 'fake';
  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();
  @override
  Stream<int> get outboundPendingCount => Stream.value(0);
  @override
  Future<void> sendOperations(List<Operation> operations) async {
    sentOperations.addAll(operations);
  }

  @override
  Future<void> syncWithMerkle({required MerkleTree localTree}) async {
    merkleRequests.add(localTree);
    await merkleGate?.future;
  }

  void simulateReconnect() => _connectionStateController.add(true);

  @override
  Stream<Operation> get operationStream => _operationController.stream;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {
    lastConnectedCursor = lastSyncedTimestamp;
    isConnected = true;
    _connectionStateController.add(true);
  }

  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'fake');

  @override
  Future<void> sendOperation(Operation op) async {
    sentOperations.add(op);
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    _operationController.close();
    _connectionStateController.close();
  }

  // Helper to simulate connection drop
  void simulateConnectionDrop() {
    _connectionStateController.add(false);
  }

  // Implement other members as needed (stubs)
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GanttViewModel Sync Integration', () {
    late GanttViewModel viewModel;
    late FakeSyncClient fakeClient;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await GanttDb.reset();
      GanttDb.overridePath = inMemoryDatabasePath;

      viewModel = GanttViewModel(useLocalDatabase: false); // Use memory mode
      fakeClient = FakeSyncClient();

      // Inject factories
      viewModel.loginFunction = ({required uri, required username, required password}) async {
        if (username == 'valid') return 'fake_token';
        throw Exception('Invalid credentials');
      };

      viewModel.syncClientFactory = ({required uri, required authToken}) => fakeClient;

      // Ensure no database calls are made
      // viewModel.seedLocalDatabase();
    });

    tearDown(() async {
      await viewModel.disconnectSync();
      viewModel.dispose();
    });

    test('connectSync success', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );

      expect(viewModel.isSyncConnected, isTrue);
      expect(fakeClient.isConnected, isTrue);
    });

    test('reconnect Merkle uses full deleted protocol snapshots rather than visible tasks', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );
      final clock = Hlc.fromIntTimestamp(2000);
      final source = ProtocolTask(
        id: 'deleted',
        rowId: 'row',
        name: 'Deleted',
        start: '2026-11-17T00:00:00.000Z',
        end: '2026-11-18T00:00:00.000Z',
        isDeleted: true,
        metadataJson: '{"unknownPluginSetting":42}',
        lastUpdated: clock.toString(),
      );
      final operation = Operation.fromJson(
        ProtobufMapper.toJson(
          ProtocolMessage.fromBuffer(
            ProtobufMapper.toProtobuf({
              'type': 'DELETE_TASK',
              'data': ProtobufMapper.taskToJson(source),
              'timestamp': clock.toString(),
              'actorId': 'server',
            }).writeToBuffer(),
          ),
        ),
      );
      await viewModel.handleIncomingOperationForTesting(operation);
      expect(viewModel.allTasks.where((task) => task.id == 'deleted'), isEmpty);
      fakeClient.simulateConnectionDrop();
      await Future<void>.delayed(Duration.zero);
      final request = fakeClient.merkleRequests.stream.first;
      fakeClient.simulateReconnect();
      final tree = await request.timeout(const Duration(seconds: 5));
      expect(tree.root.hash, CRDTEngine().computeMerkleRoot([source]));
      await viewModel.disconnectSync();
    });

    test('local sends retain deleted task hashes without a server echo', () async {
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant1',
          username: 'valid', password: 'password');
      final task = LegacyGanttTask(id: 'local-task', rowId: 'row', name: 'Local',
          start: DateTime.utc(2026, 11, 17), end: DateTime.utc(2026, 11, 18));
      await viewModel.addTask(task);
      final insert = fakeClient.sentOperations.lastWhere((operation) => operation.type == 'INSERT_TASK');
      final wireInsert = Operation.fromJson(ProtobufMapper.toJson(ProtocolMessage.fromBuffer(
          ProtobufMapper.toProtobuf(insert.toJson()).writeToBuffer())));
      final engine = CRDTEngine();
      var expected = engine.mergeTasks([], [wireInsert]);
      await viewModel.deleteTasksBulk([task]);
      final deletion = fakeClient.sentOperations.lastWhere((operation) => operation.type == 'DELETE_TASK');
      expected = engine.mergeTasks(expected, [deletion]);
      expect(expected.single.isDeleted, isTrue);
      fakeClient.simulateConnectionDrop();
      await Future<void>.delayed(Duration.zero);
      final request = fakeClient.merkleRequests.stream.first;
      fakeClient.simulateReconnect();
      final tree = await request.timeout(const Duration(seconds: 5));
      expect(tree.root.hash, engine.computeMerkleRoot(expected));
      expect(tree.root.hash, isNot(engine.computeMerkleRoot([])));
    });

    test('stored server scope excludes URI credentials and tokens', () async {
      await viewModel.connectSync(uri: 'http://user:private@localhost:8080?token=secret#fragment',
          tenantId: 'tenant1', username: 'valid', password: 'password');
      final db = await GanttDb.db;
      final rows = await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope'");
      expect(rows.single['meta_value'], '["ws://localhost:8080/ws","tenant1"]');
    });

    test('switching tenants clears prior UI rows and incremental sync cursor', () async {
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant1',
          username: 'valid', password: 'password');
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'UPDATE_TASK', data: {'id': 'old-tenant', 'rowId': 'row', 'name': 'Private',
          'start': '2026-11-17T00:00:00.000Z', 'end': '2026-11-18T00:00:00.000Z'},
        timestamp: Hlc.fromIntTimestamp(1000), actorId: 'server'));
      expect(viewModel.allTasks.any((task) => task.id == 'old-tenant'), isTrue);
      final db = await GanttDb.db;
      await db.execute('INSERT OR REPLACE INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)',
          ['last_server_sync', Hlc.fromIntTimestamp(1000).toString()]);
      await viewModel.disconnectSync();
      fakeClient = FakeSyncClient();
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant2',
          username: 'valid', password: 'password');
      expect(viewModel.allTasks.any((task) => task.id == 'old-tenant'), isFalse);
      expect(fakeClient.lastConnectedCursor, isNull);
      expect(await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'last_server_sync' AND is_deleted = 0"), isEmpty);
      expect(await db.query('SELECT * FROM tasks WHERE is_deleted = 0'), isEmpty);
    });

    test('pending edits cannot be sent to a different tenant', () async {
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant1',
          username: 'valid', password: 'password');
      await viewModel.disconnectSync();
      final db = await GanttDb.db;
      await db.execute('INSERT INTO offline_queue (type, data, timestamp, actor_id) VALUES (?, ?, ?, ?)',
          ['UPDATE_TASK', '{"id":"pending"}', Hlc.fromIntTimestamp(1000).toString(), 'old-user']);
      fakeClient = FakeSyncClient();
      await expectLater(viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant2',
          username: 'valid', password: 'password'), throwsStateError);
      expect(fakeClient.isConnected, isFalse);
      expect(fakeClient.sentOperations, isEmpty);
      final rows = await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0");
      expect(rows.single['meta_value'], '["ws://localhost:8080/ws","tenant1"]');
    });

    test('binary root resources remain visible roots', () async {
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant1',
          username: 'valid', password: 'password');
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'RESET_DATA', data: {}, timestamp: Hlc.fromIntTimestamp(1000), actorId: 'server'));
      final encoded = ProtobufMapper.toProtobuf({
        'type': 'BATCH_UPDATE', 'timestamp': Hlc.fromIntTimestamp(2000).toString(), 'actorId': 'server',
        'data': {'operations': [
          {'type': 'INSERT_RESOURCE', 'data': {'id': 'root', 'name': 'Root', 'parentId': null,
            'isExpanded': true}, 'timestamp': Hlc.fromIntTimestamp(1001).toString()},
          {'type': 'INSERT_TASK', 'data': {'id': 'task', 'rowId': 'root', 'name': 'Task',
            'start': '2026-11-17T00:00:00.000Z', 'end': '2026-11-18T00:00:00.000Z'},
            'timestamp': Hlc.fromIntTimestamp(1002).toString()},
          {'type': 'INSERT_DEPENDENCY', 'data': {'predecessorTaskId': 'task', 'successorTaskId': 'next-task',
            'type': 'finishToStart', 'lag': 60000}, 'timestamp': Hlc.fromIntTimestamp(1003).toString()},
        ]},
      }).writeToBuffer();
      await viewModel.handleIncomingOperationForTesting(Operation.fromJson(
        ProtobufMapper.toJson(ProtocolMessage.fromBuffer(encoded))));
      expect(viewModel.localResources.single.parentId, isNull);
      expect(viewModel.gridData.map((row) => row.name).toList(), ['Root']);
      expect(viewModel.dependencies.map((dep) => (dep.predecessorTaskId, dep.successorTaskId)).toList(),
          [('task', 'next-task')]);
    });

    test('older and replayed resets cannot erase replacement tasks', () async {
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant1',
          username: 'valid', password: 'password');
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'RESET_DATA', data: {}, timestamp: Hlc.fromIntTimestamp(2000), actorId: 'client-a'));
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'INSERT_TASK', data: {'id': 'replacement', 'rowId': 'row', 'name': 'Replacement',
          'start': '2026-11-17T00:00:00.000Z', 'end': '2026-11-18T00:00:00.000Z'},
        timestamp: Hlc.fromIntTimestamp(2001), actorId: 'client-a'));
      for (final clock in [1000, 2000]) {
        await viewModel.handleIncomingOperationForTesting(Operation(
          type: 'RESET_DATA', data: {}, timestamp: Hlc.fromIntTimestamp(clock), actorId: 'server-sync-reset'));
        expect(viewModel.allTasks.map((task) => task.id).toList(), ['replacement']);
      }
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'BATCH_UPDATE', data: {'operations': [
          {'type': 'INSERT_TASK', 'data': {'id': 'stale-task', 'rowId': 'row'},
            'timestamp': Hlc.fromIntTimestamp(1001).toString(), 'actorId': 'server'},
        ]}, timestamp: Hlc.fromIntTimestamp(3000), actorId: 'server'));
      expect(viewModel.allTasks.map((task) => task.id).toList(), ['replacement']);
    });

    test('Merkle replay applies buffered task and resource batches', () async {
      await viewModel.connectSync(uri: 'http://localhost:8080', tenantId: 'tenant1',
          username: 'valid', password: 'password');
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'RESET_DATA', data: {}, timestamp: Hlc.fromIntTimestamp(1000), actorId: 'client-a'));
      fakeClient.simulateConnectionDrop();
      await Future<void>.delayed(Duration.zero);
      fakeClient.merkleGate = Completer<void>();
      final request = fakeClient.merkleRequests.stream.first;
      fakeClient.simulateReconnect();
      await request.timeout(const Duration(seconds: 5));
      try {
        await viewModel.handleIncomingOperationForTesting(Operation(
          type: 'SYNC_METADATA', data: {'totalOperations': 2},
          timestamp: Hlc.fromIntTimestamp(1001), actorId: 'server'));
        await viewModel.handleIncomingOperationForTesting(Operation(
          type: 'BATCH_UPDATE', data: {'operations': [
            {'type': 'INSERT_RESOURCE', 'data': {'id': 'row', 'name': 'Resource', 'isExpanded': true},
              'timestamp': Hlc.fromIntTimestamp(1002).toString(), 'actorId': 'client-b'},
            {'type': 'INSERT_TASK', 'data': {'id': 'remote-task', 'rowId': 'row', 'name': 'Remote task',
              'start': '2026-11-17T00:00:00.000Z', 'end': '2026-11-18T00:00:00.000Z'},
              'timestamp': Hlc.fromIntTimestamp(1003).toString(), 'actorId': 'client-b'},
          ]}, timestamp: Hlc.fromIntTimestamp(1004), actorId: 'server'));
        expect(viewModel.allTasks, isEmpty);
        await viewModel.finalizeMerkleSync();
        expect(viewModel.allTasks.map((task) => task.id).toList(), ['remote-task']);
        expect(viewModel.localResources.map((resource) => resource.id).toList(), ['row']);
        expect(viewModel.gridData.map((row) => row.name).toList(), ['Resource']);
      } finally {
        fakeClient.merkleGate!.complete();
        await Future<void>.delayed(Duration.zero);
      }
    });

    test('connectSync failure', () async {
      await expectLater(
        viewModel.connectSync(
          uri: 'http://localhost:8080',
          tenantId: 'tenant1',
          username: 'invalid', // Will throw exception
          password: 'password',
        ),
        throwsException,
      );

      expect(viewModel.isSyncConnected, isFalse);
    });

    test('detects connection drop', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );

      expect(viewModel.isSyncConnected, isTrue);

      // Simulate drop
      fakeClient.simulateConnectionDrop();

      // Wait for stream to propogate
      await Future.delayed(Duration.zero);

      expect(viewModel.isSyncConnected, isFalse);
    });

    test('disconnectSync', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );

      // FIX: Add await here
      await viewModel.disconnectSync();

      expect(viewModel.isSyncConnected, isFalse);
      expect(fakeClient.isDisposed, isTrue);
    });

    // Note: To test handleTaskUpdate sending operations, we need to ensure the task exists.
    // Since seedLocalDatabase populates data asynchronously or via method, we need to ensure it's ready.
    // However, in mock mode, it uses _apiResponse.
  });
}
