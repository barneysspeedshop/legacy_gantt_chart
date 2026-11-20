import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/legacy_projection_migration.dart';
import 'package:example/data/local/local_gantt_repository.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart' show LegacyGanttTask;
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;

Hlc _clock(int minute) => Hlc.fromDate(DateTime.utc(2024, 1, 1, 0, minute), 'fixture');

ProtocolTask _task() => ProtocolTask(
  id: 'task-1',
  rowId: 'row-1',
  name: 'Full task',
  start: '2024-01-01T00:00:00.000Z',
  end: '2024-01-02T00:00:00.000Z',
  parentId: 'parent-1',
  resourceId: 'resource-1',
  notes: 'Keep on deletion',
  completion: 0.5,
  lastUpdated: _clock(1).toString(),
  metadataJson: jsonEncode(
    MerkleHashNormalizer.completeTaskMetadata({
      'color': '80010203',
      'textColor': 'ff112233',
      'load': 2.0,
      'stackIndex': 3,
      'isAutoScheduled': false,
      'originalId': 'import-1',
      'isTimeRangeHighlight': true,
      'custom': {'externalId': 'task-custom-42'},
    }),
  ),
);

ProtocolResource _resource() => ProtocolResource(
  id: 'resource-1',
  name: 'Equipment',
  parentId: 'resource-group',
  type: 'tool',
  lastUpdated: _clock(2).toString(),
  metadataJson: jsonEncode({
    'isExpanded': false,
    'custom': {'rate': 3},
  }),
);

ProtocolDependency _dependency() => ProtocolDependency(
  predecessorTaskId: 'task-1',
  successorTaskId: 'task-2',
  type: 'contained',
  lag: ProtobufMapper.dependencyFromJson({'lag': 4500}).lag,
  lastUpdated: _clock(3).toString(),
);

ProtocolResource _resourceTombstone(Hlc clock) => ProtocolResource(
  id: 'resource-1',
  name: '',
  parentId: '',
  type: 'person',
  isDeleted: true,
  lastUpdated: clock.toString(),
  metadataJson: '{}',
);

ProtocolDependency _dependencyTombstone(Hlc clock) => ProtocolDependency(
  predecessorTaskId: 'task-1',
  successorTaskId: 'task-2',
  type: 'DELETE',
  lastUpdated: clock.toString(),
);

Operation _operation(String type, Map<String, dynamic> data, Hlc timestamp) =>
    Operation(type: type, data: data, timestamp: timestamp, actorId: 'fixture');

Operation _wire(Operation operation) => Operation.fromJson(
  ProtobufMapper.toJson(ProtocolMessage.fromBuffer(ProtobufMapper.toProtobuf(operation.toJson()).writeToBuffer())),
);

Operation _snapshot({ProtocolTask? task, ProtocolResource? resource, ProtocolDependency? dependency}) {
  if (task != null && task.fieldTimestamps.isEmpty) {
    // Full canonical snapshots carry the baseline of every semantic register.
    task.fieldTimestamps.addAll(task.normalizedFieldTimestamps);
  }
  return _wire(
    _operation('BATCH_UPDATE', {
      'operations': [
        if (task != null)
          {
            'type': task.isDeleted ? 'DELETE_TASK' : 'UPDATE_TASK',
            'data': ProtobufMapper.taskToJson(task),
            'timestamp': task.lastUpdated,
          },
        if (resource != null)
          {
            'type': resource.isDeleted ? 'DELETE_RESOURCE' : 'UPDATE_RESOURCE',
            'data': ProtobufMapper.resourceToJson(resource),
            'timestamp': resource.lastUpdated,
          },
        if (dependency != null)
          {
            'type': dependency.type == 'DELETE' ? 'DELETE_DEPENDENCY' : 'UPDATE_DEPENDENCY',
            'data': ProtobufMapper.dependencyToJson(dependency),
            'timestamp': dependency.lastUpdated,
          },
      ],
    }, _clock(4)),
  );
}

String _root({ProtocolTask? task, ProtocolResource? resource, ProtocolDependency? dependency, Hlc? reset}) =>
    MerkleTree.build([
      if (reset != null) CRDTEngine.resetMerkleEntry(reset),
      if (task != null) MapEntry(task.lastUpdated, task.contentHash),
      if (resource != null) MapEntry(resource.lastUpdated, resource.contentHash),
      if (dependency != null) MapEntry(dependency.lastUpdated, dependency.contentHash),
    ]).root.hash;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late SqliteCrdt db;
  late ProtocolStateStore store;
  late String path;

  Future<void> reopen() async {
    await db.close();
    db = await GanttDb.open(path);
    store = ProtocolStateStore(Future.value(db));
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gantt-canonical-state-');
    path = '${directory.path}/state.sqlite';
    db = await GanttDb.open(path);
    store = ProtocolStateStore(Future.value(db));
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('failed outbox persistence rolls back canonical state and visible projection together', () async {
    final before = (await store.computeMerkleTree()).root.hash;
    final emitted = <ProtocolSnapshot>[];
    final subscription = store.snapshots.listen(emitted.add);
    addTearDown(subscription.cancel);
    await db.execute('''
      CREATE TRIGGER reject_test_outbox BEFORE INSERT ON offline_queue
      BEGIN SELECT RAISE(ABORT, 'injected outbox persistence failure'); END
    ''');
    final operation = _operation('INSERT_TASK', ProtobufMapper.taskToJson(_task()), _clock(1));
    await expectLater(store.applyOperations([operation], local: true, enqueue: true), throwsA(isA<Exception>()));
    expect((await store.computeMerkleTree()).root.hash, before);
    expect((await store.readState()).tasks, isEmpty);
    expect(await db.query('SELECT id FROM tasks WHERE is_deleted = 0'), isEmpty);
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), isEmpty);
    expect(emitted, isEmpty, reason: 'A rolled-back commit must not publish a state snapshot');

    await db.execute('DROP TRIGGER reject_test_outbox');
    final published = store.snapshots.first;
    await store.applyOperations([operation], local: true, enqueue: true);
    expect((await published).tasks.single.name, 'Full task');
    expect((await db.query('SELECT id FROM tasks WHERE is_deleted = 0')).single['id'], 'task-1');
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), hasLength(1));
    await reopen();
    expect((await store.readState()).tasks.single.name, 'Full task');
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), hasLength(1));
  });

  test('upgrade preserves newer legacy edits and deletions without resurrecting pre-reset rows', () async {
    ProtocolTask task(String id, int minute) => _task()
      ..id = id
      ..lastUpdated = _clock(minute).toString();
    await store.applyOperations([
      for (final id in ['a', 'b']) _operation('INSERT_TASK', ProtobufMapper.taskToJson(task(id, 1)), _clock(1)),
      _operation('RESET_DATA', {}, _clock(2)),
      for (final id in ['a', 'b']) _operation('UPDATE_TASK', ProtobufMapper.taskToJson(task(id, 3)), _clock(3)),
    ]);
    final repository = LocalGanttRepository(database: Future.value(db));
    await repository.insertOrUpdateTask(LegacyGanttTask.fromProtocolTask(task('a', 4)..name = 'Legacy offline edit'));
    await repository.deleteTask('b', _clock(4));
    await repository.insertOrUpdateTask(LegacyGanttTask.fromProtocolTask(task('stale', 1)));
    expect(await migrateLegacyProjection(database: db, state: store, enqueue: true), 2);
    await store.restoreProjection();
    final snapshot = await store.readState();
    expect(snapshot.tasks.map((task) => (task.id, task.name)), [('a', 'Legacy offline edit')]);
    expect((await repository.getAllTasks()).map((task) => task.id), ['a']);
    final queue = await db.query('SELECT type FROM offline_queue WHERE is_deleted = 0 ORDER BY id');
    expect(queue.map((row) => row['type']), ['UPDATE_TASK', 'DELETE_TASK']);
    final root = (await store.computeMerkleTree()).root.hash;
    expect(await migrateLegacyProjection(database: db, state: store, enqueue: true), 0);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, root);
    expect((await store.readState()).tasks.single.name, 'Legacy offline edit');
    expect(await migrateLegacyProjection(database: db, state: store, enqueue: true), 0);
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), hasLength(2));
  });

  test('canonical repair refuses a changed tenant binding without touching state or outbox', () async {
    await store.applyOperations([_snapshot(task: _task())]);
    final root = (await store.computeMerkleTree()).root.hash;
    await db.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
      'canonical_scope',
      'another-tenant',
    ]);
    await expectLater(store.enqueueRepair(), throwsStateError);
    expect(await store.hasPendingOperations(), isFalse);
    expect(await db.query('SELECT id FROM offline_queue WHERE is_deleted = 0'), isEmpty);
    expect((await store.computeMerkleTree()).root.hash, root);
    expect((await store.readState()).tasks.single.name, 'Full task');
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, root);
    expect(await store.hasPendingOperations(), isFalse);
  });

  test('full binary records preserve custom metadata and hashes after reopen', () async {
    final task = _task();
    final resource = _resource();
    final dependency = _dependency();
    await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
    final expected = _root(task: task, resource: resource, dependency: dependency);
    expect((await store.computeMerkleTree()).root.hash, expected);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
  });

  test('local and remote updates converge, stale updates and replays do not change state', () async {
    final task = _task();
    await store.applyOperations([_operation('UPDATE_TASK', ProtobufMapper.taskToJson(task), _clock(1))]);
    final updated = task.deepCopy()
      ..name = 'Remote revision'
      ..lastUpdated = _clock(10).toString();
    updated.fieldTimestamps.addAll({'name': _clock(10).toString(), 'isDeleted': _clock(10).toString()});
    final remote = _snapshot(task: updated);
    await store.applyOperations([remote]);
    expect((await store.computeMerkleTree()).root.hash, _root(task: updated));
    await store.applyOperations([_snapshot(task: task), remote]);
    expect((await store.computeMerkleTree()).root.hash, _root(task: updated));
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, _root(task: updated));
  });

  for (final removal in ['DELETE_TASK', 'RESET_DATA']) {
    test('historical task fields converge across $removal delivery order without resurrection', () async {
      final other = ProtocolStateStore(Future.value(db), scope: 'other-order');
      final initial = _operation('INSERT_TASK', ProtobufMapper.taskToJson(_task()), _clock(1));
      final historicalEdit = _operation('UPDATE_TASK', {'id': 'task-1', 'name': 'Historical newer name'}, _clock(2));
      final removed = _operation(removal, removal == 'DELETE_TASK' ? {'id': 'task-1'} : {}, _clock(3));
      await store.applyOperations([initial, historicalEdit, removed]);
      await other.applyOperations([initial, removed, historicalEdit]);
      for (final state in [store, other]) {
        expect((await state.readState()).tasks, isEmpty);
        final row = (await db.query(
          "SELECT payload FROM canonical_protocol_state WHERE scope = ? AND entity_type = 'task' AND entity_id = 'task-1'",
          [state.scope],
        )).single;
        final tombstone = ProtocolTask.fromBuffer(base64Decode(row['payload'] as String));
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.name, 'Historical newer name');
      }
      final root = (await store.computeMerkleTree()).root.hash;
      expect((await other.computeMerkleTree()).root.hash, root);
      await reopen();
      expect((await store.computeMerkleTree()).root.hash, root);
      expect((await ProtocolStateStore(Future.value(db), scope: 'other-order').computeMerkleTree()).root.hash, root);
    });
  }

  test('an old task first received after reset becomes the same historical tombstone', () async {
    final other = ProtocolStateStore(Future.value(db), scope: 'other-order');
    final initial = _operation('INSERT_TASK', ProtobufMapper.taskToJson(_task()), _clock(1));
    final reset = _operation('RESET_DATA', {}, _clock(3));
    await store.applyOperations([reset, initial]);
    await other.applyOperations([initial, reset]);
    expect((await store.readState()).tasks, isEmpty);
    expect((await other.readState()).tasks, isEmpty);
    final deleted = _task()
      ..isDeleted = true
      ..lastUpdated = _clock(3).toString();
    deleted.fieldTimestamps.addAll({..._task().normalizedFieldTimestamps, 'isDeleted': _clock(3).toString()});
    expect((await store.computeMerkleTree()).root.hash, _root(task: deleted, reset: _clock(3)));
    expect((await other.computeMerkleTree()).root.hash, _root(task: deleted, reset: _clock(3)));
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, _root(task: deleted, reset: _clock(3)));
  });

  test(
    'historical edits, reset and newer partial edits converge in all 24 orders including sparse first writes',
    () async {
      final initial = _operation('INSERT_TASK', ProtobufMapper.taskToJson(_task()), _clock(1));
      final operations = [
        initial,
        _operation('UPDATE_TASK', {'id': 'task-1', 'notes': 'Historical notes'}, _clock(2)),
        _operation('RESET_DATA', {}, _clock(3)),
        _operation('UPDATE_TASK', {'id': 'task-1', 'name': 'After reset'}, _clock(4)),
      ];
      final expected = _task()
        ..name = 'After reset'
        ..notes = 'Historical notes'
        ..lastUpdated = _clock(4).toString();
      expected.fieldTimestamps.addAll({
        ..._task().normalizedFieldTimestamps,
        'notes': _clock(2).toString(),
        'name': _clock(4).toString(),
        'isDeleted': _clock(4).toString(),
      });
      final orders = [
        for (var a = 0; a < 4; a++)
          for (var b = 0; b < 4; b++)
            for (var c = 0; c < 4; c++)
              for (var d = 0; d < 4; d++)
                if ({a, b, c, d}.length == 4) [a, b, c, d],
      ];
      for (final order in orders) {
        final state = ProtocolStateStore(Future.value(db), scope: 'order-${order.join()}');
        await state.applyOperations(order.map((index) => operations[index]).toList());
        final visible = (await state.readState()).tasks.single;
        expect(visible.name, 'After reset', reason: '$order');
        expect(visible.notes, 'Historical notes', reason: '$order');
        expect(visible.rowId, 'row-1', reason: '$order');
        expect(
          (await state.computeMerkleTree()).root.hash,
          _root(task: expected, reset: _clock(3)),
          reason: '$order',
        );
      }
      await reopen();
      for (final indices in orders) {
        final state = ProtocolStateStore(Future.value(db), scope: 'order-${indices.join()}');
        expect((await state.computeMerkleTree()).root.hash, _root(task: expected, reset: _clock(3)));
        expect((await state.readState()).tasks.single.notes, 'Historical notes');
      }
    },
  );

  test('old unknown resources and dependencies converge across reset without retaining hidden payloads', () async {
    final other = ProtocolStateStore(Future.value(db), scope: 'other-order');
    final old = [
      _operation('UPDATE_RESOURCE', ProtobufMapper.resourceToJson(_resource()), _clock(2)),
      _operation('UPDATE_DEPENDENCY', ProtobufMapper.dependencyToJson(_dependency()), _clock(3)),
    ];
    final reset = _operation('RESET_DATA', {}, _clock(4));
    await store.applyOperations([reset, ...old]);
    await other.applyOperations([...old, reset]);
    final expected = _root(
      resource: _resourceTombstone(_clock(4)),
      dependency: _dependencyTombstone(_clock(4)),
      reset: _clock(4),
    );
    for (final state in [store, other]) {
      expect((await state.readState()).resources, isEmpty);
      expect((await state.readState()).dependencies, isEmpty);
      expect((await state.computeMerkleTree()).root.hash, expected);
    }
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
    expect((await ProtocolStateStore(Future.value(db), scope: 'other-order').computeMerkleTree()).root.hash, expected);
  });

  test('projection migration persists normalized legacy tombstones while retaining task history', () async {
    await store.readState();
    final task = _task()
      ..isDeleted = true
      ..lastUpdated = _clock(20).toString();
    final resource = _resource()
      ..isDeleted = true
      ..lastUpdated = _clock(20).toString();
    final dependency = _dependency()
      ..type = 'DELETE'
      ..lastUpdated = _clock(20).toString();
    for (final record in [
      ('task', task.id, task.writeToBuffer()),
      ('resource', resource.id, resource.writeToBuffer()),
      (
        'dependency',
        jsonEncode([dependency.predecessorTaskId, dependency.successorTaskId]),
        dependency.writeToBuffer(),
      ),
    ]) {
      await db.execute(
        'INSERT INTO canonical_protocol_state (scope, entity_type, entity_id, payload) VALUES (?, ?, ?, ?)',
        ['local', record.$1, record.$2, base64Encode(record.$3)],
      );
    }
    await store.restoreProjection();
    final expected = _root(
      task: task,
      resource: _resourceTombstone(_clock(20)),
      dependency: _dependencyTombstone(_clock(20)),
    );
    expect((await store.computeMerkleTree()).root.hash, expected);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
    final rows = await db.query("SELECT entity_type, payload FROM canonical_protocol_state WHERE scope = 'local'");
    final payloads = {for (final row in rows) row['entity_type']: base64Decode(row['payload'] as String)};
    final persistedResource = ProtocolResource.fromBuffer(payloads['resource']!);
    expect(persistedResource.name, '');
    expect(persistedResource.parentId, '');
    expect(persistedResource.type, 'person');
    expect(persistedResource.metadataJson, '{}');
    expect(ProtocolDependency.fromBuffer(payloads['dependency']!).lag.toInt(), 0);
    final persistedTask = ProtocolTask.fromBuffer(payloads['task']!);
    expect(persistedTask.notes, 'Keep on deletion');
    expect(persistedTask.fieldTimestamps, isNotEmpty);
    expect(persistedTask.fieldTimestamps['notes'], _clock(20).toString());
    final coldTaskStore = ProtocolStateStore(Future.value(db), scope: 'cold-task-export');
    await coldTaskStore.applyOperations([
      _wire(_operation('DELETE_TASK', ProtobufMapper.taskToJson(persistedTask), _clock(20))),
    ]);
    expect((await coldTaskStore.readState()).tasks, isEmpty);
    expect((await coldTaskStore.computeMerkleTree()).root.hash, _root(task: task));

    expect((await store.readState()).tasks, isEmpty);
  });

  for (final local in [false, true]) {
    test('deletion retains task history and minimal resource/dependency tombstones (local: $local)', () async {
      final task = _task();
      final resource = _resource();
      final dependency = _dependency();
      await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
      final deletedTask = task.deepCopy()
        ..isDeleted = true
        ..lastUpdated = _clock(11).toString();
      deletedTask.fieldTimestamps['isDeleted'] = _clock(11).toString();
      final deletedResource = _resourceTombstone(_clock(12));
      final deletedDependency = _dependencyTombstone(_clock(13));
      if (local) {
        await store.applyOperations([
          _wire(_operation('DELETE_TASK', {'id': task.id}, _clock(11))),
          _wire(_operation('DELETE_RESOURCE', {'id': resource.id}, _clock(12))),
          _wire(
            _operation('DELETE_DEPENDENCY', {
              'predecessorTaskId': dependency.predecessorTaskId,
              'successorTaskId': dependency.successorTaskId,
            }, _clock(13)),
          ),
        ], local: local);
      } else {
        await store.applyOperations([
          _snapshot(task: deletedTask, resource: deletedResource, dependency: deletedDependency),
        ]);
      }
      final expected = _root(task: deletedTask, resource: deletedResource, dependency: deletedDependency);
      expect((await store.computeMerkleTree()).root.hash, expected);
      expect(expected, isNot(_root()));
      await reopen();
      expect((await store.computeMerkleTree()).root.hash, expected);
    });
  }

  test('cold replay normalizes resource/dependency tombstones and preserves task history', () async {
    final task = _task()..isDeleted = true;
    final resource = _resource()..isDeleted = true;
    final dependency = _dependency()..type = 'DELETE';
    await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
    final expected = _root(
      task: task,
      resource: _resourceTombstone(_clock(2)),
      dependency: _dependencyTombstone(_clock(3)),
    );
    expect((await store.computeMerkleTree()).root.hash, expected);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
  });

  test('reset retains canonical tombstones, survives reopen, and allows later edits', () async {
    final task = _task();
    final resource = _resource();
    final dependency = _dependency();
    await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
    await store.applyOperations([_wire(_operation('RESET_DATA', <String, dynamic>{}, _clock(20)))]);
    final deletedTask = task.deepCopy()
      ..isDeleted = true
      ..lastUpdated = _clock(20).toString();
    deletedTask.fieldTimestamps['isDeleted'] = _clock(20).toString();
    final deletedResource = _resourceTombstone(_clock(20));
    final deletedDependency = _dependencyTombstone(_clock(20));
    final expected = _root(
      task: deletedTask,
      resource: deletedResource,
      dependency: deletedDependency,
      reset: _clock(20),
    );
    expect((await store.computeMerkleTree()).root.hash, expected);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
    await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
    expect((await store.computeMerkleTree()).root.hash, expected);
    final restored = task.deepCopy()
      ..name = 'After reset'
      ..lastUpdated = _clock(21).toString();
    restored.fieldTimestamps.addAll({'name': _clock(21).toString(), 'isDeleted': _clock(21).toString()});
    await store.applyOperations([_snapshot(task: restored)]);
    expect(
      (await store.computeMerkleTree()).root.hash,
      _root(task: restored, resource: deletedResource, dependency: deletedDependency, reset: _clock(20)),
    );
    await store.applyOperations([_wire(_operation('RESET_DATA', <String, dynamic>{}, _clock(20)))]);
    expect(
      (await store.computeMerkleTree()).root.hash,
      _root(task: restored, resource: deletedResource, dependency: deletedDependency, reset: _clock(20)),
    );
  });

  test('large local reseed persists every record and retains hashes after reopening', () async {
    final tasks = List.generate(
      1000,
      (i) => _task()
        ..id = 'task-$i'
        ..name = 'Task "$i" – local',
    );
    await store.applyOperations([
      for (final task in tasks) _operation('INSERT_TASK', ProtobufMapper.taskToJson(task), _clock(1)),
    ], local: true);
    final rows = await db.query(
      "SELECT entity_id FROM canonical_protocol_state WHERE scope = 'local' AND entity_type = 'task' ORDER BY entity_id",
    );
    expect(rows.map((row) => row['entity_id']).toSet(), {for (var i = 0; i < 1000; i++) 'task-$i'});
    final expected = MerkleTree.build([for (final task in tasks) MapEntry(task.lastUpdated, task.contentHash)])
        .root
        .hash;
    expect((await store.computeMerkleTree()).root.hash, expected);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
  });

  test('canonical records are isolated by synchronization scope', () async {
    final first = ProtocolStateStore(Future.value(db), scope: 'tenant-a');
    final second = ProtocolStateStore(Future.value(db), scope: 'tenant-b');
    await first.applyOperations([_snapshot(task: _task())]);
    await second.applyOperations([_snapshot(resource: _resource())]);
    expect((await first.computeMerkleTree()).root.hash, _root(task: _task()));
    expect((await second.computeMerkleTree()).root.hash, _root(resource: _resource()));
  });
}
