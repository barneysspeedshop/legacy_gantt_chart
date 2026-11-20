import 'dart:convert';

import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;

import 'protocol_state_store.dart';

/// Recovers edits made by older versions outside their canonical operation path.
/// Strict clocks preserve canonical tombstones and make interrupted migration safe
/// to repeat. This must run before restoring the canonical materialized read model.
Future<int> migrateLegacyProjection({
  required SqliteCrdt database,
  required ProtocolStateStore state,
  required bool enqueue,
}) async {
  final marker = 'canonical_projection_migration_v1:${state.scope}';
  if ((await database.query('SELECT meta_value FROM sync_metadata WHERE meta_key = ? AND is_deleted = 0', [
    marker,
  ])).isNotEmpty) {
    return 0;
  }
  final snapshot = await state.readState();
  final canonical = await database.query(
    'SELECT entity_type, entity_id, payload FROM canonical_protocol_state WHERE scope = ?',
    [state.scope],
  );
  final knownTasks = <String, ProtocolTask>{};
  final knownResources = <String, ProtocolResource>{};
  final knownDependencies = <String, ProtocolDependency>{};
  for (final row in canonical) {
    final id = row['entity_id'] as String;
    final payload = row['payload'] as String;
    switch (row['entity_type']) {
      case 'task':
        knownTasks[id] = ProtocolTask.fromBuffer(base64Decode(payload));
      case 'resource':
        knownResources[id] = ProtocolResource.fromBuffer(base64Decode(payload));
      case 'dependency':
        knownDependencies[id] = ProtocolDependency.fromBuffer(base64Decode(payload));
    }
  }
  final operations = <Operation>[];
  bool newer(Hlc clock, Hlc? existing) =>
      (snapshot.lastReset == null || clock > snapshot.lastReset!) && (existing == null || clock > existing);
  void add(String type, Map<String, dynamic> data, Hlc clock) =>
      operations.add(Operation(type: type, data: data, timestamp: clock, actorId: 'legacy-local-migration'));
  for (final row in await database.query('SELECT * FROM tasks')) {
    final id = row['id'] as String;
    final clock = _rowClock(row);
    final existing = knownTasks[id];
    if (!newer(clock, existing?.parsedLastUpdated)) continue;
    if (_deleted(row)) {
      add('DELETE_TASK', {'id': id}, clock);
      continue;
    }
    final metadata = <String, dynamic>{
      if (existing != null) ...ProtobufMapper.metadataFromJson({'metadataJson': existing.metadataJson}),
      'color': row['color'],
      'textColor': row['text_color'],
      'stackIndex': row['stack_index'] ?? 0,
      'originalId': existing == null
          ? row['resource_id']
          : ProtobufMapper.metadataFromJson({'metadataJson': existing.metadataJson})['originalId'],
      'usesWorkCalendar': _boolean(row['uses_work_calendar']),
      'isAutoScheduled': row['is_auto_scheduled'] != 0,
      'propagatesMoveToChildren': row['propagates_move_to_children'] != 0,
      'resizePolicy': MerkleHashNormalizer.normalizeResizePolicy(row['resize_policy']),
      'baselineStart': MerkleHashNormalizer.formatProtocolDateOrNull(row['baseline_start']),
      'baselineEnd': MerkleHashNormalizer.formatProtocolDateOrNull(row['baseline_end']),
      'isTimeRangeHighlight': _boolean(row['is_time_range_highlight']),
    };
    add('UPDATE_TASK', {
      'id': id,
      'rowId': row['row_id'],
      'start': row['start_date'],
      'end': row['end_date'],
      'name': row['name'],
      'completion': row['completion'] ?? 0.0,
      'isSummary': _boolean(row['is_summary']),
      'isMilestone': _boolean(row['is_milestone']),
      'resourceId': row['resource_id'],
      'parentId': row['parent_id'],
      'notes': row['notes'],
      'lastUpdatedBy': row['last_updated_by'],
      'metadataJson': jsonEncode(metadata),
    }, clock);
  }
  for (final row in await database.query('SELECT * FROM resources')) {
    final id = row['id'] as String;
    final clock = _rowClock(row);
    final existing = knownResources[id];
    if (!newer(clock, existing?.parsedLastUpdated)) continue;
    if (_deleted(row)) {
      add('DELETE_RESOURCE', {'id': id}, clock);
      continue;
    }
    add('UPDATE_RESOURCE', {
      'id': id,
      'name': row['name'],
      'parentId': row['parent_id'],
      'type': existing?.type ?? 'person',
      'metadataJson': jsonEncode({
        if (existing != null) ...ProtobufMapper.metadataFromJson({'metadataJson': existing.metadataJson}),
        'isExpanded': _boolean(row['is_expanded']),
        'sort_order': row['sort_order'],
      }),
    }, clock);
  }
  for (final row in await database.query('SELECT * FROM dependencies')) {
    final pred = row['from_id'] as String;
    final succ = row['to_id'] as String;
    final clock = _rowClock(row);
    if (!newer(clock, knownDependencies[jsonEncode([pred, succ])]?.parsedLastUpdated)) continue;
    final typeIndex = (row['type'] as num?)?.toInt() ?? 0;
    add(_deleted(row) ? 'DELETE_DEPENDENCY' : 'UPDATE_DEPENDENCY', {
      'predecessorTaskId': pred,
      'successorTaskId': succ,
      'type': DependencyType.values[typeIndex].name,
      'lag': row['lag_ms'] ?? 0,
    }, clock);
  }
  if (operations.isNotEmpty) await state.applyOperations(operations, local: true, enqueue: enqueue);
  await database.execute('INSERT OR REPLACE INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [marker, '1']);
  return operations.length;
}

Hlc _rowClock(Map<String, Object?> row) {
  Hlc parse(Object? value) => value is num
      ? Hlc.fromIntTimestamp(value.toInt())
      : value is String && value.isNotEmpty
      ? Hlc.parse(value)
      : Hlc.zero;
  final updated = parse(row['last_updated']);
  final deleted = parse(row['deleted_at']);
  return deleted > updated ? deleted : updated;
}

bool _deleted(Map<String, Object?> row) => _boolean(row['is_deleted']) || row['deleted_at'] != null;
bool _boolean(Object? value) => value == true || value == 1 || value == '1' || value == 'true';
