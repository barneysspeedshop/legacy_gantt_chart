import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/persisted_gantt_sync_client.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart' show WebSocketGanttSyncClient;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;

class _Transport implements WebSocketGanttSyncClient {
  final connections = StreamController<bool>.broadcast();
  final operations = StreamController<Operation>.broadcast();
  final sent = <Operation>[];
  @override
  Stream<bool> get connectionStateStream => connections.stream;
  @override
  Stream<Operation> get operationStream => operations.stream;
  @override
  Future<void> sendOperations(List<Operation> batch) async => sent.addAll(batch);
  @override
  Future<void> dispose() async {
    await connections.close();
    await operations.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Operation _task(String id, int tick) => Operation(
  type: 'UPDATE_TASK',
  data: {'id': id, 'name': 'Private $id', 'notes': 'Only for $id'},
  timestamp: Hlc(millis: tick, counter: 0, nodeId: 'tenant-fixture'),
  actorId: 'tenant-fixture',
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late SqliteCrdt db;
  late ProtocolStateStore a;
  late ProtocolStateStore b;
  late PersistedGanttSyncClient oldClient;
  late PersistedGanttSyncClient newClient;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gantt-tenant-binding-');
    db = await GanttDb.open('${directory.path}/shared.sqlite');
    a = ProtocolStateStore(Future.value(db), scope: 'tenant-a');
    b = ProtocolStateStore(Future.value(db), scope: 'tenant-b');
    await a.applyOperations([_task('a', 100)], bindScope: true);
    oldClient = PersistedGanttSyncClient(Future.value(db), protocolState: () => a);
    newClient = PersistedGanttSyncClient(Future.value(db), protocolState: () => b);
    await Future.wait([oldClient.ready, newClient.ready]);
  });
  tearDown(() async {
    await oldClient.dispose();
    await newClient.dispose();
    await a.close();
    await b.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  test('a stale client cannot enqueue or project old-tenant data after another client rebinds', () async {
    final originalRoot = (await a.computeMerkleTree()).root.hash;
    await b.applyOperations([_task('b', 200)], bindScope: true);
    await b.restoreProjection();
    final activeRoot = (await b.computeMerkleTree()).root.hash;
    await expectLater(oldClient.sendOperation(_task('a', 300)), throwsStateError);
    await expectLater(a.applyOperations([_task('a', 400)]), throwsStateError);
    await expectLater(a.restoreProjection(), throwsStateError);
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), isEmpty);
    expect((await db.query('SELECT name FROM tasks WHERE is_deleted = 0')).single['name'], 'Private b');
    expect((await a.computeMerkleTree()).root.hash, originalRoot);
    expect((await b.computeMerkleTree()).root.hash, activeRoot);
  });

  test('a pending edit inserted after a rebind precheck prevents the transactional rebind', () async {
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), isEmpty);
    await oldClient.sendOperation(_task('a', 300));
    await db.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
      'last_server_sync',
      _task('a', 100).timestamp.toString(),
    ]);
    await expectLater(b.applyOperations([], bindScope: true), throwsStateError);
    final binding = (await db.query(
      "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
    )).single;
    expect(binding['meta_value'], 'tenant-a');
    final queued = (await db.query('SELECT data FROM offline_queue WHERE is_deleted = 0')).single;
    expect((jsonDecode(queued['data'] as String) as Map)['id'], 'a');
    expect((await a.readState()).tasks.single.name, 'Private a');
    expect((await b.readState()).tasks, isEmpty);
    expect((await db.query('SELECT name FROM tasks WHERE is_deleted = 0')).single['name'], 'Private a');
    expect(
      (await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'last_server_sync' AND is_deleted = 0"))
          .single['meta_value'],
      _task('a', 100).timestamp.toString(),
    );
  });

  test(
    'an accepted binding replaces the projection atomically even when its canonical records are unchanged',
    () async {
      await b.applyOperations([_task('b', 200)], bindScope: true);
      await a.applyOperations([], bindScope: true);
      final cursor = _task('a', 100).timestamp.toString();
      await db.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', ['last_server_sync', cursor]);
      await db.execute(
        "CREATE TRIGGER reject_binding BEFORE INSERT ON sync_metadata WHEN NEW.meta_key = 'canonical_scope' AND NEW.meta_value = 'tenant-b' BEGIN SELECT RAISE(ABORT, 'binding failure'); END",
      );
      await expectLater(b.applyOperations([], bindScope: true), throwsA(anything));
      expect((await db.query('SELECT name FROM tasks WHERE is_deleted = 0')).single['name'], 'Private a');
      expect(
        (await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0"))
            .single['meta_value'],
        'tenant-a',
      );
      expect(
        (await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'last_server_sync' AND is_deleted = 0"))
            .single['meta_value'],
        cursor,
      );
      await db.execute('DROP TRIGGER reject_binding');
      await b.applyOperations([], bindScope: true);
      expect((await db.query('SELECT name FROM tasks WHERE is_deleted = 0')).single['name'], 'Private b');
      expect(
        await db.query("SELECT meta_value FROM sync_metadata WHERE meta_key = 'last_server_sync' AND is_deleted = 0"),
        isEmpty,
      );
      expect((await a.readState()).tasks.single.name, 'Private a');
      expect((await b.readState()).tasks.single.name, 'Private b');
    },
  );

  test('a stale connected client cannot flush the active tenant outgoing queue', () async {
    await b.applyOperations([], bindScope: true);
    await newClient.sendOperation(_task('b', 200));
    final transport = _Transport();
    await oldClient.setInnerClient(transport);
    final connected = oldClient.connectionStateStream.firstWhere((value) => value);
    transport.connections.add(true);
    await connected;
    await oldClient.flushPending();
    await expectLater(a.loadPendingOperations(), throwsStateError);
    expect(transport.sent, isEmpty);
    final queued = await b.loadPendingOperations();
    expect(queued, hasLength(1));
    expect((jsonDecode(queued.single['data'] as String) as Map)['id'], 'b');
    expect((await b.readState()).tasks.single.notes, 'Only for b');
  });
}
