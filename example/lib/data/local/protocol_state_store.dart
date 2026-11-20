import 'dart:async';
import 'dart:convert';

import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:synchronized/synchronized.dart';

import 'protocol_projection.dart';
export 'protocol_projection.dart' show ProtocolSnapshot, ProtocolCommit;

/// Owns accepted CRDT state, its local read model, and durable outgoing work.
class ProtocolStateStore {
  final Future<SqliteCrdt> _database;
  final String scope;
  final _lock = Lock();
  final _engine = CRDTEngine();
  final _snapshots = StreamController<ProtocolSnapshot>.broadcast();
  Hlc? _lastResetTimestamp;
  Hlc? get lastResetTimestamp => _lastResetTimestamp;
  Stream<ProtocolSnapshot> get snapshots => _snapshots.stream;
  late final Future<SqliteCrdt> _ready = _open();

  ProtocolStateStore(this._database, {this.scope = 'local'});

  Future<SqliteCrdt> _open() async {
    final database = await _database;
    await database.execute('''CREATE TABLE IF NOT EXISTS canonical_protocol_state (
      scope TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY (scope, entity_type, entity_id))''');
    return database;
  }

  Future<ProtocolCommit> applyOperations(
    List<Operation> operations, {
    bool local = false,
    bool enqueue = false,
    bool bindScope = false,
  }) => _lock.synchronized(() async {
    final database = await _ready;
    late ProtocolCommit commit;
    await database.transaction((transaction) async {
      final replaceProjection = await _validateBinding(transaction, allowRebind: bindScope);
      final rows = await transaction.query(
        'SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?',
        [scope],
      );
      final state = _ProtocolState.fromRows(rows);
      final previous = {for (final row in rows) '${row['entity_type']}:${row['entity_id']}': row['payload']};
      final outgoing = <Operation>[];
      Hlc? acceptedReset;
      for (final original in operations.expand(_originalOperations)) {
        final accepted = <Operation>[];
        final canonical = _canonicalOperations(original, local: local).toList();
        for (final operation in canonical) {
          final before = _entityPayload(state, operation);
          if (operation.type == 'RESET_DATA') {
            if (state.lastReset != null && operation.timestamp <= state.lastReset!) continue;
            state.tasks = _engine.mergeTasks(state.tasks, [
              for (final task in state.tasks)
                Operation(type: 'DELETE_TASK', data: {'id': task.id}, timestamp: operation.timestamp, actorId: 'reset'),
            ]);
            state.resources = _engine.mergeResources(state.resources, [
              for (final resource in state.resources)
                Operation(
                  type: 'DELETE_RESOURCE',
                  data: {'id': resource.id},
                  timestamp: operation.timestamp,
                  actorId: 'reset',
                ),
            ]);
            state.dependencies.updateAll(
              (_, dependency) => dependency.parsedLastUpdated > operation.timestamp
                  ? dependency
                  : (ProtocolDependency()
                      ..predecessorTaskId = dependency.predecessorTaskId
                      ..successorTaskId = dependency.successorTaskId
                      ..type = 'DELETE'
                      ..lastUpdated = operation.timestamp.toString()),
            );
            state.lastReset = operation.timestamp;
            acceptedReset = operation.timestamp;
          } else {
            final taskOperation = operation.type.endsWith('_TASK');
            if (state.lastReset != null) {
              if (taskOperation) {
                // A reset fences presence, while historical field values still
                // merge into tombstones independently of delivery order.
                state.tasks = _engine.mergeTasks(state.tasks, [
                  Operation(
                    type: 'DELETE_TASK',
                    data: {'id': operation.data['id']},
                    timestamp: state.lastReset!,
                    actorId: 'reset',
                  ),
                ]);
              } else if (operation.type.endsWith('_RESOURCE')) {
                state.resources = _engine.mergeResources(state.resources, [
                  Operation(
                    type: 'DELETE_RESOURCE',
                    data: {'id': operation.data['id']},
                    timestamp: state.lastReset!,
                    actorId: operation.actorId,
                  ),
                ]);
              } else if (operation.type.endsWith('_DEPENDENCY')) {
                final dependency = ProtobufMapper.dependencyFromJson(operation.data);
                final key = _dependencyKey(dependency);
                final existing = state.dependencies[key];
                if (existing == null || existing.parsedLastUpdated <= state.lastReset!) {
                  state.dependencies[key] = ProtocolDependency()
                    ..predecessorTaskId = dependency.predecessorTaskId
                    ..successorTaskId = dependency.successorTaskId
                    ..type = 'DELETE'
                    ..lastUpdated = state.lastReset.toString();
                }
              }
            }
            state.tasks = _engine.mergeTasks(state.tasks, [operation]);
            state.resources = _engine.mergeResources(state.resources, [operation]);
            if (operation.type.contains('DEPENDENCY')) {
              final dependency = ProtobufMapper.dependencyFromJson(operation.data);
              final key = _dependencyKey(dependency);
              final existing = state.dependencies[key];
              if (existing == null ||
                  (existing.parsedLastUpdated <= operation.timestamp &&
                      !(existing.type == 'DELETE' &&
                          operation.type != 'DELETE_DEPENDENCY' &&
                          operation.timestamp <= existing.parsedLastUpdated))) {
                state.dependencies[key] = operation.type == 'DELETE_DEPENDENCY'
                    ? (ProtocolDependency()
                        ..predecessorTaskId = dependency.predecessorTaskId
                        ..successorTaskId = dependency.successorTaskId
                        ..type = 'DELETE'
                        ..lastUpdated = operation.timestamp.toString())
                    : (dependency..lastUpdated = operation.timestamp.toString());
              }
            }
          }
          final after = _entityPayload(state, operation);
          if (before != after) accepted.add(operation);
        }
        if (enqueue) {
          if (canonical.isEmpty) {
            // Non-entity server commands have no local projection to merge.
            outgoing.add(original);
          } else if (accepted.isNotEmpty) {
            outgoing.add(original);
          }
        }
      }
      final payloads = _payloads(state);
      final changedKeys = payloads.keys.where((key) => previous[key] != payloads[key]).toSet();
      final changedRows = changedKeys.map((key) {
        final separator = key.indexOf(':');
        return {'type': key.substring(0, separator), 'id': key.substring(separator + 1), 'payload': payloads[key]};
      }).toList();
      final snapshot = ProtocolProjection.snapshot(
        state.tasks,
        state.resources,
        state.dependencies.values,
        state.lastReset,
      );
      if (changedRows.isNotEmpty) {
        await transaction.execute(
          r'''INSERT OR REPLACE INTO canonical_protocol_state (scope, entity_type, entity_id, payload)
          SELECT ?1, json_extract(value, '$.type'), json_extract(value, '$.id'), json_extract(value, '$.payload')
          FROM json_each(?2)''',
          [scope, jsonEncode(changedRows)],
        );
      }
      if (replaceProjection) {
        await transaction.execute("DELETE FROM sync_metadata WHERE meta_key = 'last_server_sync'");
      }
      if (changedRows.isNotEmpty || replaceProjection) {
        await ProtocolProjection.write(
          transaction,
          snapshot,
          taskIds: {
            for (final key in changedKeys)
              if (key.startsWith('task:')) key.substring(5),
          },
          resourceIds: {
            for (final key in changedKeys)
              if (key.startsWith('resource:')) key.substring(9),
          },
          dependencyKeys: {
            for (final key in changedKeys)
              if (key.startsWith('dependency:')) key.substring(11),
          },
          replace: replaceProjection,
        );
      }
      if (outgoing.isNotEmpty) {
        await transaction.execute(
          r'''INSERT INTO offline_queue (type, data, timestamp, actor_id)
          SELECT json_extract(value, '$.type'), json_extract(value, '$.data'),
            json_extract(value, '$.timestamp'), json_extract(value, '$.actorId') FROM json_each(?1)''',
          [
            jsonEncode(outgoing.map((op) => {...op.toJson(), 'data': jsonEncode(op.data)}).toList()),
          ],
        );
      }
      if (bindScope) {
        await transaction.execute('INSERT OR REPLACE INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
          'canonical_scope',
          scope,
        ]);
      }
      commit = ProtocolCommit(
        state: snapshot,
        changed: changedRows.isNotEmpty || replaceProjection,
        acceptedReset: acceptedReset,
      );
    });
    _lastResetTimestamp = commit.state.lastReset;
    if (commit.changed && !_snapshots.isClosed) _snapshots.add(commit.state);
    return commit;
  });

  Future<ProtocolSnapshot> readState() => _lock.synchronized(() async {
    final state = await _read();
    _lastResetTimestamp = state.lastReset;
    return ProtocolProjection.snapshot(state.tasks, state.resources, state.dependencies.values, state.lastReset);
  });

  Future<List<Operation>> exportState() => _lock.synchronized(() async => _repairOperations(await _read()));

  Future<bool> hasPendingOperations() => _lock.synchronized(() async {
    final database = await _ready;
    return (await database.query('SELECT id FROM offline_queue WHERE is_deleted = 0 LIMIT 1')).isNotEmpty;
  });

  /// Requeues canonical registers without changing their clocks or values.
  Future<void> enqueueRepair() => _lock.synchronized(() async {
    final database = await _ready;
    await database.transaction((transaction) async {
      await _validateBinding(transaction);
      final state = _ProtocolState.fromRows(
        await transaction.query(
          'SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?',
          [scope],
        ),
      );
      final operations = _repairOperations(state);
      if (operations.isEmpty) return;
      await transaction.execute(
        r'''INSERT INTO offline_queue (type, data, timestamp, actor_id)
        SELECT json_extract(value, '$.type'), json_extract(value, '$.data'),
          json_extract(value, '$.timestamp'), json_extract(value, '$.actorId') FROM json_each(?1)''',
        [
          jsonEncode(operations.map((op) => {...op.toJson(), 'data': jsonEncode(op.data)}).toList()),
        ],
      );
    });
  });

  Future<List<Map<String, Object?>>> loadPendingOperations() => _lock.synchronized(() async {
    final database = await _ready;
    late List<Map<String, Object?>> rows;
    await database.transaction((transaction) async {
      await _validateBinding(transaction);
      rows = await transaction.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC LIMIT 500');
    });
    return rows;
  });

  Future<bool> _validateBinding(CrdtExecutor transaction, {bool allowRebind = false}) async {
    final binding = await transaction.query(
      "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
    );
    final activeScope = binding.firstOrNull?['meta_value'];
    if (activeScope == scope) return false;
    if (!allowRebind) {
      if (activeScope == null) return false;
      throw StateError('The active tenant changed before this synchronization operation could be applied.');
    }
    final pending = await transaction.query('SELECT id FROM offline_queue WHERE is_deleted = 0 LIMIT 1');
    if (activeScope != null && pending.isNotEmpty) {
      throw StateError('Synchronize pending changes with their original tenant before changing the active tenant.');
    }
    return pending.isEmpty;
  }

  static List<Operation> _repairOperations(_ProtocolState state) => [
    if (state.lastReset case final reset?) Operation(type: 'RESET_DATA', data: {}, timestamp: reset, actorId: 'reset'),
    for (final resource in state.resources)
      Operation(
        type: resource.isDeleted ? 'DELETE_RESOURCE' : 'UPDATE_RESOURCE',
        data: ProtobufMapper.resourceToJson(resource),
        timestamp: resource.parsedLastUpdated,
        actorId: 'canonical-repair',
      ),
    for (final task in state.tasks)
      Operation(
        type: task.isDeleted ? 'DELETE_TASK' : 'UPDATE_TASK',
        data: ProtobufMapper.taskToJson(task),
        timestamp: task.parsedLastUpdated,
        actorId: task.lastUpdatedBy.isEmpty ? 'canonical-repair' : task.lastUpdatedBy,
      ),
    for (final dependency in state.dependencies.values)
      Operation(
        type: dependency.type == 'DELETE' ? 'DELETE_DEPENDENCY' : 'UPDATE_DEPENDENCY',
        data: ProtobufMapper.dependencyToJson(dependency),
        timestamp: dependency.parsedLastUpdated,
        actorId: 'canonical-repair',
      ),
  ];

  Future<void> restoreProjection() async {
    // Persist protocol-version normalization before rebuilding the read model.
    await applyOperations([]);
    await _lock.synchronized(() async {
      final database = await _ready;
      late ProtocolSnapshot snapshot;
      await database.transaction((transaction) async {
        await _validateBinding(transaction);
        final state = _ProtocolState.fromRows(
          await transaction.query(
            'SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?',
            [scope],
          ),
        );
        snapshot = ProtocolProjection.snapshot(
          state.tasks,
          state.resources,
          state.dependencies.values,
          state.lastReset,
        );
        await ProtocolProjection.write(
          transaction,
          snapshot,
          taskIds: {},
          resourceIds: {},
          dependencyKeys: {},
          replace: true,
        );
      });
      _lastResetTimestamp = snapshot.lastReset;
      if (!_snapshots.isClosed) _snapshots.add(snapshot);
    });
  }

  Future<_ProtocolState> _read() async {
    final database = await _ready;
    return _ProtocolState.fromRows(
      await database.query('SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?', [
        scope,
      ]),
    );
  }

  Future<MerkleTree> computeMerkleTree() => _lock.synchronized(() async {
    final state = await _read();
    return _engine.computeMerkleTree(
      state.tasks,
      resources: state.resources,
      dependencies: state.dependencies.values.toList(),
      resetTimestamp: state.lastReset,
    );
  });

  Future<void> close() => _lock.synchronized(() => _snapshots.close());

  static Map<String, String> _payloads(_ProtocolState state) => {
    for (final task in state.tasks) 'task:${task.id}': base64Encode(task.writeToBuffer()),
    for (final resource in state.resources) 'resource:${resource.id}': base64Encode(resource.writeToBuffer()),
    for (final entry in state.dependencies.entries)
      'dependency:${entry.key}': base64Encode(entry.value.writeToBuffer()),
    if (state.lastReset != null) 'control:reset': state.lastReset.toString(),
  };

  static String? _entityPayload(_ProtocolState state, Operation operation) {
    if (operation.type == 'RESET_DATA') return state.lastReset?.toString();
    if (operation.type.contains('DEPENDENCY')) {
      final dependency =
          state.dependencies[jsonEncode([operation.data['predecessorTaskId'], operation.data['successorTaskId']])];
      return dependency == null ? null : base64Encode(dependency.writeToBuffer());
    }
    final id = operation.data['id'];
    if (operation.type.contains('RESOURCE')) {
      for (final resource in state.resources) {
        if (resource.id == id) return base64Encode(resource.writeToBuffer());
      }
    } else {
      for (final task in state.tasks) {
        if (task.id == id) return base64Encode(task.writeToBuffer());
      }
    }
    return null;
  }

  Iterable<Operation> _originalOperations(Operation operation) sync* {
    if (operation.type != 'BATCH_UPDATE') {
      yield operation;
      return;
    }
    for (final child in operation.data['operations'] as List? ?? []) {
      final data = Map<String, dynamic>.from(child as Map);
      yield* _originalOperations(
        Operation.fromJson({
          ...data,
          'timestamp': data['timestamp'] ?? operation.timestamp.toString(),
          'actorId': data['actorId'] ?? operation.actorId,
        }),
      );
    }
  }

  Iterable<Operation> _canonicalOperations(Operation operation, {required bool local}) sync* {
    if (!const {
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
    var data = <String, dynamic>{...operation.data};
    if (data['data'] is Map) {
      final nested = Map<String, dynamic>.from(data.remove('data') as Map);
      data.addAll(nested);
    }
    const aliases = {
      'taskId': 'id',
      'resourceId': 'id',
      'row_id': 'rowId',
      'resource_id': 'resourceId',
      'parent_id': 'parentId',
      'is_deleted': 'isDeleted',
      'is_summary': 'isSummary',
      'is_milestone': 'isMilestone',
      'last_updated_by': 'lastUpdatedBy',
      'predecessor_task_id': 'predecessorTaskId',
      'successor_task_id': 'successorTaskId',
      'dependency_type': 'type',
    };
    for (final entry in aliases.entries) {
      if (entry.key == 'resourceId' && !operation.type.contains('RESOURCE')) continue;
      if (!data.containsKey(entry.value) && data.containsKey(entry.key)) data[entry.value] = data[entry.key];
    }
    if (local && operation.type.startsWith('DELETE_')) {
      data = operation.type == 'DELETE_DEPENDENCY'
          ? {'predecessorTaskId': data['predecessorTaskId'], 'successorTaskId': data['successorTaskId']}
          : {'id': data['id']};
    }
    if (data.containsKey('parentId')) data['parentId'] ??= '';
    if (operation.type.contains('DEPENDENCY') && data['type'] is num) {
      const types = ['finishToStart', 'startToStart', 'finishToFinish', 'startToFinish', 'contained'];
      final index = (data['type'] as num).toInt();
      if (index >= 0 && index < types.length) data['type'] = types[index];
    }
    final normalized = Operation(
      type: operation.type,
      data: data,
      timestamp: operation.timestamp,
      actorId: operation.actorId,
    );
    if (!local || operation.type.startsWith('DELETE_') || operation.type == 'RESET_DATA') {
      yield normalized;
    } else {
      final decoded = ProtobufMapper.toJson(ProtobufMapper.toProtobuf(normalized.toJson()));
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
          final task = ProtocolTask.fromBuffer(base64Decode(payload));
          final metadata = ProtobufMapper.metadataFromJson({'metadataJson': task.metadataJson});
          task.metadataJson = jsonEncode(MerkleHashNormalizer.completeTaskMetadata(metadata));
          final clocks = task.normalizedFieldTimestamps;
          task.fieldTimestamps
            ..clear()
            ..addAll(clocks);
          tasks.add(task);
        case 'resource':
          final resource = ProtocolResource.fromBuffer(base64Decode(payload));
          resources.add(
            resource.isDeleted
                ? CRDTEngine().mergeResources([], [
                    Operation(
                      type: 'DELETE_RESOURCE',
                      data: {'id': resource.id},
                      timestamp: resource.parsedLastUpdated,
                      actorId: 'migration',
                    ),
                  ]).single
                : resource,
          );
        case 'dependency':
          final dependency = ProtocolDependency.fromBuffer(base64Decode(payload));
          if (dependency.type == 'DELETE') dependency.clearLag();
          dependencies[_dependencyKey(dependency)] = dependency;
        case 'control':
          lastReset = Hlc.parse(payload);
      }
    }
  }
}
