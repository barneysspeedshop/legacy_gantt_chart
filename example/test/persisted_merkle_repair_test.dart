import 'dart:async';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/persisted_gantt_sync_client.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;

Operation _wire(Operation operation) => Operation.fromJson(
  ProtobufMapper.toJson(ProtocolMessage.fromBuffer(ProtobufMapper.toProtobuf(operation.toJson()).writeToBuffer())),
);

class _ServerClient implements WebSocketGanttSyncClient {
  final ProtocolStateStore server;
  final connections = StreamController<bool>.broadcast();
  final operations = StreamController<Operation>.broadcast();
  bool dropWrites = true;
  bool failWrites = false;
  int batches = 0;
  Future<void> Function()? beforeRoot;
  _ServerClient(this.server);

  @override
  Stream<bool> get connectionStateStream => connections.stream;
  @override
  Stream<Operation> get operationStream => operations.stream;
  @override
  Future<void> sendOperations(List<Operation> batch) async {
    batches++;
    if (failWrites) throw StateError('transport failed');
    if (!dropWrites) await server.applyOperations(batch.map(_wire).toList());
  }

  @override
  Future<String> getMerkleRoot() async {
    await beforeRoot?.call();
    return (await server.computeMerkleTree()).root.hash;
  }

  @override
  Future<void> syncWithMerkle({required MerkleTree localTree}) async {
    (await server.exportState()).map(_wire).forEach(operations.add);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    await connections.close();
    await operations.close();
  }

  @override
  int get correctedTimestamp => DateTime.now().millisecondsSinceEpoch;
  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'server-fixture');
  @override
  String get actorId => 'fixture';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late SqliteCrdt localDb;
  late SqliteCrdt serverDb;
  late ProtocolStateStore local;
  late ProtocolStateStore server;
  late PersistedGanttSyncClient client;
  late _ServerClient transport;
  late StreamSubscription<Operation> incoming;
  Future<void> accepted = Future.value();
  const clock = Hlc(millis: 2000, counter: 4, nodeId: 'offline-fixture');
  final write = Operation(
    type: 'INSERT_TASK',
    data: {
      'id': 'offline-task',
      'name': 'Offline edit',
      'notes': 'Must reach server',
      'start': '2026-11-20T00:00:00.000Z',
      'end': '2026-11-21T00:00:00.000Z',
      'lastUpdated': clock.toString(),
      'fieldTimestamps': {'name': clock.toString(), 'notes': clock.toString()},
    },
    timestamp: clock,
    actorId: 'offline-fixture',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gantt-merkle-repair-');
    localDb = await GanttDb.open('${directory.path}/local.sqlite');
    serverDb = await GanttDb.open('${directory.path}/server.sqlite');
    local = ProtocolStateStore(Future.value(localDb));
    server = ProtocolStateStore(Future.value(serverDb));
    accepted = Future.value();
    client = PersistedGanttSyncClient(
      Future.value(localDb),
      protocolState: () => local,
      settleIncoming: () => accepted,
    );
    transport = _ServerClient(server);
    incoming = client.operationStream.listen((operation) {
      accepted = accepted.then((_) async {
        await local.applyOperations([operation]);
      });
    });
    await client.ready;
    await client.setInnerClient(transport);
    transport.connections.add(true);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    await incoming.cancel();
    await accepted;
    await client.dispose();
    await local.close();
    await server.close();
    await localDb.close();
    await serverDb.close();
    await directory.delete(recursive: true);
  });

  test('Merkle repair restores a lost socket handoff after durable outbox deletion', () async {
    await client.sendOperation(write);
    await client.flushPending();
    expect(await local.hasPendingOperations(), false);
    expect((await server.readState()).tasks, isEmpty);
    final before = (await local.computeMerkleTree()).root.hash;
    final original = (await local.exportState()).singleWhere((operation) => operation.type.contains('TASK'));
    transport.dropWrites = false;
    await client.syncWithMerkle(localTree: MerkleTree.build([]));
    expect((await server.readState()).tasks.single.notes, 'Must reach server');
    expect((await server.computeMerkleTree()).root.hash, before);
    expect((await local.computeMerkleTree()).root.hash, before);
    final repaired = (await server.exportState()).singleWhere((operation) => operation.type.contains('TASK'));
    expect(repaired.timestamp, original.timestamp);
    expect(repaired.data['fieldTimestamps'], original.data['fieldTimestamps']);
    expect(await local.hasPendingOperations(), false);
  });

  test('repair combines independent server fields with lost offline fields', () async {
    await client.sendOperation(write);
    await client.flushPending();
    const serverClock = Hlc(millis: 3000, counter: 0, nodeId: 'server-fixture');
    await server.applyOperations([
      Operation(
        type: 'UPDATE_TASK',
        data: {'id': 'offline-task', 'name': 'Server rename'},
        timestamp: serverClock,
        actorId: 'server-fixture',
      ),
    ]);
    transport.dropWrites = false;
    await client.syncWithMerkle(localTree: MerkleTree.build([]));
    for (final state in [local, server]) {
      final task = (await state.readState()).tasks.single;
      expect(task.name, 'Server rename');
      expect(task.notes, 'Must reach server');
    }
    expect((await local.computeMerkleTree()).root.hash, (await server.computeMerkleTree()).root.hash);
  });

  test('repair preserves full historical fields of a lost task tombstone', () async {
    await client.sendOperation(write);
    await client.flushPending();
    const deletedClock = Hlc(millis: 3000, counter: 0, nodeId: 'offline-fixture');
    await client.sendOperation(
      Operation(type: 'DELETE_TASK', data: {'id': 'offline-task'}, timestamp: deletedClock, actorId: 'offline-fixture'),
    );
    await client.flushPending();
    final before = (await local.computeMerkleTree()).root.hash;
    transport.dropWrites = false;
    await client.syncWithMerkle(localTree: MerkleTree.build([]));
    expect((await server.readState()).tasks, isEmpty);
    expect((await server.computeMerkleTree()).root.hash, before);
    final tombstone = (await server.exportState()).singleWhere((op) => op.type == 'DELETE_TASK');
    expect(tombstone.data['notes'], 'Must reach server');
    expect(tombstone.data['isDeleted'], true);
  });

  test('root comparison waits for incoming canonical commits received during the request', () async {
    transport.dropWrites = false;
    await client.sendOperation(write);
    await client.flushPending();
    final batches = transport.batches;
    const remoteClock = Hlc(millis: 3000, counter: 0, nodeId: 'server-fixture');
    final remote = Operation(
      type: 'UPDATE_TASK',
      data: {'id': 'offline-task', 'notes': 'Incoming change'},
      timestamp: remoteClock,
      actorId: 'server-fixture',
    );
    transport.beforeRoot = () async {
      transport.beforeRoot = null;
      await server.applyOperations([remote]);
      transport.operations.add(_wire((await server.exportState()).singleWhere((op) => op.type.contains('TASK'))));
      await Future<void>.delayed(Duration.zero);
    };
    await client.syncWithMerkle(localTree: MerkleTree.build([]));
    expect((await local.readState()).tasks.single.notes, 'Incoming change');
    expect(transport.batches, batches, reason: 'A settled matching state needs no repair upload');
  });

  test('repair stops after three lost handoffs while canonical state stays durable', () async {
    await client.sendOperation(write);
    await client.flushPending();
    final before = (await local.computeMerkleTree()).root.hash;
    final batches = transport.batches;
    await expectLater(client.syncWithMerkle(localTree: MerkleTree.build([])), throwsStateError);
    expect(transport.batches - batches, 3);
    expect((await local.computeMerkleTree()).root.hash, before);
    expect((await server.readState()).tasks, isEmpty);
  });

  test('failed repair handoff retains its outbox and reports failure', () async {
    await client.sendOperation(write);
    await client.flushPending();
    transport.failWrites = true;
    await expectLater(client.syncWithMerkle(localTree: MerkleTree.build([])), throwsStateError);
    expect(await local.hasPendingOperations(), true);
    expect((await local.readState()).tasks.single.notes, 'Must reach server');
  });

  test('replacing the connection aborts an in-flight repair before enqueue or handoff', () async {
    await client.sendOperation(write);
    await client.flushPending();
    final entered = Completer<void>();
    final resume = Completer<void>();
    transport.beforeRoot = () async {
      entered.complete();
      await resume.future;
    };
    final repair = client.syncWithMerkle(localTree: MerkleTree.build([]));
    final rejected = expectLater(repair, throwsStateError);
    await entered.future;
    final replacement = _ServerClient(server)..dropWrites = false;
    await client.setInnerClient(replacement);
    transport = replacement;
    replacement.connections.add(true);
    await Future<void>.delayed(Duration.zero);
    resume.complete();
    await rejected;
    expect(replacement.batches, 0);
    expect(await local.hasPendingOperations(), false);
    expect((await server.readState()).tasks, isEmpty);
  });

  test('disconnected repair cannot report success', () async {
    await client.sendOperation(write);
    await client.flushPending();
    transport.connections.add(false);
    await Future<void>.delayed(Duration.zero);
    await expectLater(client.syncWithMerkle(localTree: MerkleTree.build([])), throwsStateError);
  });
}
