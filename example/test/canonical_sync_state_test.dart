import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/protocol_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
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
  metadataJson: jsonEncode({
    'color': '80010203',
    'textColor': 'ff112233',
    'load': 2.0,
    'stackIndex': 3,
    'isAutoScheduled': false,
    'originalId': 'import-1',
    'isTimeRangeHighlight': true,
    'custom': {'externalId': 'task-custom-42'},
  }),
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

Operation _operation(String type, Map<String, dynamic> data, Hlc timestamp) =>
    Operation(type: type, data: data, timestamp: timestamp, actorId: 'fixture');

Operation _wire(Operation operation) => Operation.fromJson(
  ProtobufMapper.toJson(ProtocolMessage.fromBuffer(ProtobufMapper.toProtobuf(operation.toJson()).writeToBuffer())),
);

Operation _snapshot({ProtocolTask? task, ProtocolResource? resource, ProtocolDependency? dependency}) => _wire(
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

String _root({ProtocolTask? task, ProtocolResource? resource, ProtocolDependency? dependency}) => MerkleTree.build([
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
    db = await SqliteCrdt.open(path, version: 1, onCreate: (db, version) async {});
    store = ProtocolStateStore(Future.value(db));
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gantt-canonical-state-');
    path = '${directory.path}/state.sqlite';
    db = await SqliteCrdt.open(path, version: 1, onCreate: (db, version) async {});
    store = ProtocolStateStore(Future.value(db));
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
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
    final remote = _snapshot(task: updated);
    await store.applyOperations([remote]);
    expect((await store.computeMerkleTree()).root.hash, _root(task: updated));
    await store.applyOperations([_snapshot(task: task), remote]);
    expect((await store.computeMerkleTree()).root.hash, _root(task: updated));
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, _root(task: updated));
  });

  for (final local in [false, true]) {
    test('deleting all entity types retains full tombstones (local: $local)', () async {
      final task = _task();
      final resource = _resource();
      final dependency = _dependency();
      await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
      final deletedTask = task.deepCopy()
        ..isDeleted = true
        ..lastUpdated = _clock(11).toString();
      final deletedResource = resource.deepCopy()
        ..isDeleted = true
        ..lastUpdated = _clock(12).toString();
      final deletedDependency = dependency.deepCopy()
        ..type = 'DELETE'
        ..lastUpdated = _clock(13).toString();
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

  test('full tombstones received without a previous live record survive reopen', () async {
    final task = _task()..isDeleted = true;
    final resource = _resource()..isDeleted = true;
    final dependency = _dependency()..type = 'DELETE';
    await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
    final expected = _root(task: task, resource: resource, dependency: dependency);
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
    final deletedResource = resource.deepCopy()
      ..isDeleted = true
      ..lastUpdated = _clock(20).toString();
    final deletedDependency = dependency.deepCopy()
      ..type = 'DELETE'
      ..lastUpdated = _clock(20).toString();
    final expected = _root(task: deletedTask, resource: deletedResource, dependency: deletedDependency);
    expect((await store.computeMerkleTree()).root.hash, expected);
    await reopen();
    expect((await store.computeMerkleTree()).root.hash, expected);
    await store.applyOperations([_snapshot(task: task, resource: resource, dependency: dependency)]);
    expect((await store.computeMerkleTree()).root.hash, expected);
    final restored = task.deepCopy()
      ..name = 'After reset'
      ..lastUpdated = _clock(21).toString();
    await store.applyOperations([_snapshot(task: restored)]);
    expect(
      (await store.computeMerkleTree()).root.hash,
      _root(task: restored, resource: deletedResource, dependency: deletedDependency),
    );
    await store.applyOperations([_wire(_operation('RESET_DATA', <String, dynamic>{}, _clock(20)))]);
    expect(
      (await store.computeMerkleTree()).root.hash,
      _root(task: restored, resource: deletedResource, dependency: deletedDependency),
    );
  });

  test('large local reseed persists every record and retains hashes after reopening', () async {
    final tasks = List.generate(1000, (i) => _task()
      ..id = 'task-$i'
      ..name = 'Task "$i" – local');
    await store.applyOperations([
      for (final task in tasks)
        _operation('INSERT_TASK', ProtobufMapper.taskToJson(task), _clock(1)),
    ], local: true);
    final rows = await db.query(
      "SELECT entity_id FROM canonical_protocol_state WHERE scope = 'local' AND entity_type = 'task' ORDER BY entity_id");
    expect(rows.map((row) => row['entity_id']).toSet(),
        {for (var i = 0; i < 1000; i++) 'task-$i'});
    final expected = MerkleTree.build([
      for (final task in tasks) MapEntry(task.lastUpdated, task.contentHash),
    ]).root.hash;
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
