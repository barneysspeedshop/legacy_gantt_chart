import 'dart:convert';

import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:synchronized/synchronized.dart';

/// Persists the protocol state used for integrity checks, including tombstones.
/// The scope separates each server and tenant from the example's local UI data.
class ProtocolStateStore {
  final Future<SqliteCrdt> _database;
  final String scope;
  final _lock = Lock();
  final _engine = CRDTEngine();
  late final Future<SqliteCrdt> _ready = _open();

  ProtocolStateStore(this._database, {this.scope = 'local'});

  Future<SqliteCrdt> _open() async {
    final database = await _database;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS canonical_protocol_state (
        scope TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY (scope, entity_type, entity_id)
      )
    ''');
    return database;
  }

  Future<void> applyOperations(List<Operation> operations, {bool local = false}) => _lock.synchronized(() async {
    final canonical = operations.expand((operation) => _canonicalOperations(operation, local: local)).toList();
    if (canonical.isEmpty) return;
    final database = await _ready;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?',
        [scope],
      );
      final state = _ProtocolState.fromRows(rows);
      final pending = <Operation>[];
      void flush() {
        if (pending.isEmpty) return;
        state.tasks = _engine.mergeTasks(state.tasks, pending);
        state.resources = _engine.mergeResources(state.resources, pending);
        for (final operation in pending) {
          if (!operation.type.contains('DEPENDENCY')) continue;
          final dependency = ProtobufMapper.dependencyFromJson(operation.data);
          final key = _dependencyKey(dependency);
          final existing = state.dependencies[key];
          if (existing != null && existing.parsedLastUpdated > operation.timestamp) continue;
          state.dependencies[key] = operation.type == 'DELETE_DEPENDENCY'
              ? ((operation.data.containsKey('lag') ? dependency : existing ?? dependency).deepCopy()
                  ..type = 'DELETE'
                  ..lastUpdated = operation.timestamp.toString())
              : (dependency..lastUpdated = operation.timestamp.toString());
        }
        pending.clear();
      }

      for (final operation in canonical) {
        if (operation.type == 'RESET_DATA') {
          flush();
          if (state.lastReset != null && operation.timestamp <= state.lastReset!) continue;
          final clock = operation.timestamp.toString();
          state.tasks = state.tasks
              .map(
                (task) => task.deepCopy()
                  ..isDeleted = true
                  ..lastUpdated = clock,
              )
              .toList();
          state.resources = state.resources
              .map(
                (resource) => resource.deepCopy()
                  ..isDeleted = true
                  ..lastUpdated = clock,
              )
              .toList();
          state.dependencies.updateAll(
            (_, dependency) => dependency.deepCopy()
              ..type = 'DELETE'
              ..lastUpdated = clock,
          );
          state.lastReset = operation.timestamp;
        } else if (state.lastReset == null || operation.timestamp >= state.lastReset!) {
          pending.add(operation);
        }
      }
      flush();
      final previous = {for (final row in rows) '${row['entity_type']}:${row['entity_id']}': row['payload']};
      Future<void> save(String type, String id, String payload) async {
        if (previous['$type:$id'] == payload) return;
        await transaction.execute(
          'INSERT OR REPLACE INTO canonical_protocol_state (scope, entity_type, entity_id, payload) VALUES (?, ?, ?, ?)',
          [scope, type, id, payload],
        );
      }

      for (final task in state.tasks) {
        await save('task', task.id, base64Encode(task.writeToBuffer()));
      }
      for (final resource in state.resources) {
        await save('resource', resource.id, base64Encode(resource.writeToBuffer()));
      }
      for (final entry in state.dependencies.entries) {
        await save('dependency', entry.key, base64Encode(entry.value.writeToBuffer()));
      }
      if (state.lastReset != null) await save('control', 'reset', state.lastReset.toString());
    });
  });

  Future<MerkleTree> computeMerkleTree() => _lock.synchronized(() async {
    final database = await _ready;
    final state = _ProtocolState.fromRows(
      await database.query('SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?', [
        scope,
      ]),
    );
    return _engine.computeMerkleTree(
      state.tasks,
      resources: state.resources,
      dependencies: state.dependencies.values.toList(),
    );
  });

  Iterable<Operation> _canonicalOperations(Operation operation, {required bool local}) sync* {
    if (!const {
      'BATCH_UPDATE',
      'INSERT_TASK',
      'UPDATE_TASK',
      'DELETE_TASK',
      'INSERT_RESOURCE',
      'UPDATE_RESOURCE',
      'DELETE_RESOURCE',
      'INSERT_DEPENDENCY',
      'UPDATE_DEPENDENCY',
      'DELETE_DEPENDENCY',
      'RESET_DATA',
    }.contains(operation.type)) {
      return;
    }
    if (local && operation.type == 'BATCH_UPDATE') {
      for (final child in operation.data['operations'] as List? ?? []) {
        final data = Map<String, dynamic>.from(child as Map);
        final nested = Operation.fromJson({
          ...data,
          'timestamp': data['timestamp'] ?? operation.timestamp.toString(),
          'actorId': data['actorId'] ?? operation.actorId,
        });
        yield* _canonicalOperations(nested, local: true);
      }
      return;
    }
    if (local && operation.type.startsWith('DELETE_')) {
      final data = operation.data['data'] is Map
          ? Map<String, dynamic>.from(operation.data['data'] as Map)
          : operation.data;
      yield Operation(
        type: operation.type,
        data: operation.type == 'DELETE_DEPENDENCY'
            ? {'predecessorTaskId': data['predecessorTaskId'], 'successorTaskId': data['successorTaskId']}
            : {'id': data['id'] ?? data['taskId'] ?? data['resourceId']},
        timestamp: operation.timestamp,
        actorId: operation.actorId,
      );
      return;
    }
    final decoded = ProtobufMapper.toJson(ProtobufMapper.toProtobuf(operation.toJson()));
    if (operation.type == 'BATCH_UPDATE') {
      for (final child in (decoded['data'] as Map<String, dynamic>)['operations'] as List) {
        yield Operation.fromJson(child as Map<String, dynamic>);
      }
    } else {
      yield Operation.fromJson({
        ...decoded,
        'data': decoded['data'] ?? <String, dynamic>{},
        'timestamp': decoded['timestamp'] ?? operation.timestamp.toString(),
        'actorId': decoded['actorId'] ?? operation.actorId,
      });
    }
  }
}

String _dependencyKey(ProtocolDependency dependency) =>
    jsonEncode([dependency.predecessorTaskId, dependency.successorTaskId]);

class _ProtocolState {
  List<ProtocolTask> tasks = [];
  List<ProtocolResource> resources = [];
  final Map<String, ProtocolDependency> dependencies = {};
  Hlc? lastReset;

  _ProtocolState.fromRows(List<Map<String, Object?>> rows) {
    for (final row in rows) {
      final payload = row['payload'] as String;
      switch (row['entity_type']) {
        case 'task':
          tasks.add(ProtocolTask.fromBuffer(base64Decode(payload)));
        case 'resource':
          resources.add(ProtocolResource.fromBuffer(base64Decode(payload)));
        case 'dependency':
          final dependency = ProtocolDependency.fromBuffer(base64Decode(payload));
          dependencies[_dependencyKey(dependency)] = dependency;
        case 'control':
          lastReset = Hlc.parse(payload);
      }
    }
  }
}
