import 'dart:ui';

import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:synchronized/synchronized.dart';

import 'gantt_db.dart';

class LocalGanttRepository {
  final _lock = Lock();

  /// Parse helper for mixed int/String column
  Hlc? _parseHlc(dynamic value) {
    if (value == null) return null;
    if (value is int) return Hlc.fromIntTimestamp(value);
    if (value is String) return Hlc.parse(value);
    return null;
  }

  Future<void> init() async {
    await GanttDb.db;
  }

  Stream<List<LegacyGanttTask>> watchTasks() async* {
    final db = await GanttDb.db;
    yield* db
        .watch('SELECT * FROM tasks WHERE is_deleted = 0 ORDER BY start_date, id ASC')
        .map((rows) => rows.map((row) => _rowToTask(row)).toList());
  }

  Future<List<LegacyGanttTask>> getAllTasks() async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM tasks WHERE is_deleted = 0 ORDER BY rowid ASC');
    return rows.map((row) => _rowToTask(row)).toList();
  }

  Stream<List<LegacyGanttTaskDependency>> watchDependencies() async* {
    final db = await GanttDb.db;
    yield* db
        .watch('SELECT * FROM dependencies WHERE is_deleted = 0 ORDER BY rowid ASC')
        .map((rows) => rows.map((row) => _rowToDependency(row)).toList());
  }

  Future<void> insertTasks(List<LegacyGanttTask> tasks) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      final batch = db.batch();
      for (final task in tasks) {
        batch.execute(
          '''
          UPDATE tasks SET
            row_id = ?2,
            start_date = ?3,
            end_date = ?4,
            name = ?5,
            color = ?6,
            text_color = ?7,
            stack_index = ?8,
            is_summary = ?9,
            is_milestone = ?10,
            resource_id = ?11,
            resource_id = ?11,
            last_updated = ?12,
            completion = ?13,
            baseline_start = ?14,
            baseline_end = ?15,
            notes = ?16,
            deleted_at = NULL,
            is_deleted = 0,
            uses_work_calendar = ?17,
            parent_id = ?18,
            is_auto_scheduled = ?19,
            propagates_move_to_children = ?20,
            resize_policy = ?21,
            last_updated_by = ?22
          WHERE id = ?1
          ''',
          [
            task.id,
            task.rowId,
            task.start.toIso8601String(),
            task.end.toIso8601String(),
            task.name,
            task.color?.toARGB32().toRadixString(16),
            task.textColor?.toARGB32().toRadixString(16),
            task.stackIndex,
            task.isSummary ? 1 : 0,
            task.isMilestone ? 1 : 0,
            task.resourceId ?? task.originalId,
            task.lastUpdated.toString(),
            task.completion,
            task.baselineStart?.toIso8601String(),
            task.baselineEnd?.toIso8601String(),
            task.notes,
            task.usesWorkCalendar ? 1 : 0,
            task.parentId,
            (task.isAutoScheduled ?? true) ? 1 : 0,
            task.propagatesMoveToChildren ? 1 : 0,
            task.resizePolicy.index,
            task.lastUpdatedBy
          ],
        );

        batch.execute(
          '''
          INSERT OR IGNORE INTO tasks (id, row_id, start_date, end_date, name, color, text_color, stack_index, is_summary, is_milestone, resource_id, last_updated, completion, baseline_start, baseline_end, notes, uses_work_calendar, deleted_at, is_deleted, parent_id, is_auto_scheduled, propagates_move_to_children, resize_policy, last_updated_by)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, NULL, 0, ?18, ?19, ?20, ?21, ?22)
          ''',
          [
            task.id,
            task.rowId,
            task.start.toIso8601String(),
            task.end.toIso8601String(),
            task.name,
            task.color?.toARGB32().toRadixString(16),
            task.textColor?.toARGB32().toRadixString(16),
            task.stackIndex,
            task.isSummary ? 1 : 0,
            task.isMilestone ? 1 : 0,
            task.resourceId ?? task.originalId,
            task.lastUpdated.toString(),
            task.completion,
            task.baselineStart?.toIso8601String(),
            task.baselineEnd?.toIso8601String(),
            task.notes,
            task.usesWorkCalendar ? 1 : 0,
            task.parentId,
            (task.isAutoScheduled ?? true) ? 1 : 0,
            task.propagatesMoveToChildren ? 1 : 0,
            task.resizePolicy.index,
            task.lastUpdatedBy
          ],
        );
      }
      await batch.commit();
    });
  }

  Future<void> insertOrUpdateTask(LegacyGanttTask task) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      print('LocalGanttRepository: Saving task ${task.id}, lastUpdatedBy: ${task.lastUpdatedBy}');
      await db.execute(
        '''
        UPDATE tasks SET
          row_id = ?2,
          start_date = ?3,
          end_date = ?4,
          name = ?5,
          color = ?6,
          text_color = ?7,
          stack_index = ?8,
          is_summary = ?9,
          is_milestone = ?10,
          resource_id = ?11,
          resource_id = ?11,
          last_updated = ?12,
          completion = ?13,
          baseline_start = ?14,
          baseline_end = ?15,
          notes = ?16,
          deleted_at = NULL,
          is_deleted = 0,
          uses_work_calendar = ?17,
          parent_id = ?18,
          is_auto_scheduled = ?19,
          propagates_move_to_children = ?20,
          resize_policy = ?21,
          last_updated_by = ?22
        WHERE id = ?1
        ''',
        [
          task.id,
          task.rowId,
          task.start.toIso8601String(),
          task.end.toIso8601String(),
          task.name,
          task.color?.toARGB32().toRadixString(16),
          task.textColor?.toARGB32().toRadixString(16),
          task.stackIndex,
          task.isSummary ? 1 : 0,
          task.isMilestone ? 1 : 0,
          task.resourceId ?? task.originalId,
          task.lastUpdated.toString(),
          task.completion,
          task.baselineStart?.toIso8601String(),
          task.baselineEnd?.toIso8601String(),
          task.notes,
          task.usesWorkCalendar ? 1 : 0,
          task.parentId,
          (task.isAutoScheduled ?? true) ? 1 : 0,
          task.propagatesMoveToChildren ? 1 : 0,
          task.resizePolicy.index,
          task.lastUpdatedBy
        ],
      );

      await db.execute(
        '''
        INSERT OR IGNORE INTO tasks (id, row_id, start_date, end_date, name, color, text_color, stack_index, is_summary, is_milestone, resource_id, last_updated, completion, baseline_start, baseline_end, notes, uses_work_calendar, deleted_at, is_deleted, parent_id, is_auto_scheduled, propagates_move_to_children, resize_policy, last_updated_by)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, NULL, 0, ?18, ?19, ?20, ?21, ?22)
        ''',
        [
          task.id,
          task.rowId,
          task.start.toIso8601String(),
          task.end.toIso8601String(),
          task.name,
          task.color?.toARGB32().toRadixString(16),
          task.textColor?.toARGB32().toRadixString(16),
          task.stackIndex,
          task.isSummary ? 1 : 0,
          task.isMilestone ? 1 : 0,
          task.resourceId ?? task.originalId,
          task.lastUpdated.toString(),
          task.completion,
          task.baselineStart?.toIso8601String(),
          task.baselineEnd?.toIso8601String(),
          task.notes,
          task.usesWorkCalendar ? 1 : 0,
          task.parentId,
          (task.isAutoScheduled ?? true) ? 1 : 0,
          task.propagatesMoveToChildren ? 1 : 0,
          task.resizePolicy.index,
          task.lastUpdatedBy
        ],
      );
    });
  }

  Future<void> deleteTask(String taskId, Hlc timestamp) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE tasks SET is_deleted = 1, deleted_at = ?, last_updated = ? WHERE id = ?',
        [timestamp.toString(), timestamp.toString(), taskId],
      );
    });
  }

  Future<void> insertDependencies(List<LegacyGanttTaskDependency> dependencies) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      final batch = db.batch();
      for (final dependency in dependencies) {
        batch.execute(
          '''
          UPDATE dependencies SET
            type = ?3,
            lag_ms = ?4,
            last_updated = ?5,
            deleted_at = NULL,
            is_deleted = 0
          WHERE from_id = ?1 AND to_id = ?2
          ''',
          [
            dependency.predecessorTaskId,
            dependency.successorTaskId,
            dependency.type.index,
            dependency.lag?.inMilliseconds,
            dependency.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );

        batch.execute(
          '''
          INSERT OR IGNORE INTO dependencies (from_id, to_id, type, lag_ms, last_updated, deleted_at)
          VALUES (?1, ?2, ?3, ?4, ?5, NULL)
          ''',
          [
            dependency.predecessorTaskId,
            dependency.successorTaskId,
            dependency.type.index,
            dependency.lag?.inMilliseconds,
            dependency.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
      await batch.commit();
    });
  }

  Future<void> insertOrUpdateDependency(LegacyGanttTaskDependency dependency) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        '''
        UPDATE dependencies SET
          type = ?3,
          lag_ms = ?4,
          last_updated = ?5,
          deleted_at = NULL,
          is_deleted = 0
        WHERE from_id = ?1 AND to_id = ?2
        ''',
        [
          dependency.predecessorTaskId,
          dependency.successorTaskId,
          dependency.type.index,
          dependency.lag?.inMilliseconds,
          dependency.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
        ],
      );

      await db.execute(
        '''
        INSERT OR IGNORE INTO dependencies (from_id, to_id, type, lag_ms, last_updated, deleted_at)
        VALUES (?1, ?2, ?3, ?4, ?5, NULL)
        ''',
        [
          dependency.predecessorTaskId,
          dependency.successorTaskId,
          dependency.type.index,
          dependency.lag?.inMilliseconds,
          dependency.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<void> deleteDependency(String fromId, String toId, Hlc timestamp) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      // Check existing timestamp
      final existing = await db.query(
        'SELECT last_updated FROM dependencies WHERE from_id = ? AND to_id = ?',
        [fromId, toId],
      );

      bool shouldUpdate = true;
      if (existing.isNotEmpty && existing.first['last_updated'] != null) {
        final existingHlc = _parseHlc(existing.first['last_updated']);
        if (existingHlc != null && existingHlc >= timestamp) {
          shouldUpdate = false;
        }
      }

      if (shouldUpdate) {
        await db.execute(
          'UPDATE dependencies SET is_deleted = 1, deleted_at = ?, last_updated = ? WHERE from_id = ? AND to_id = ?',
          [timestamp.toString(), timestamp.toString(), fromId, toId],
        );
      }
    });
  }

  Future<void> deleteDependenciesForTask(String taskId, Hlc timestamp) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      // This is a bulk update, so we can't easily check individual row timestamps in Dart without iterating.
      // However, we can use a SQL WHERE clause to only update rows where the timestamp is older.
      // SQLite string comparison works for ISO-like strings, but HLCs have counters/nodeIds.
      // HLCs are lexicographically comparable! (ISO-Counter-NodeId)

      await db.execute(
        '''
        UPDATE dependencies 
        SET is_deleted = 1, deleted_at = ?, last_updated = ? 
        WHERE (from_id = ? OR to_id = ?) 
          AND (last_updated IS NULL OR last_updated < ?)
        ''',
        [timestamp.toString(), timestamp.toString(), taskId, taskId, timestamp.toString()],
      );
    });
  }

  Future<void> deleteAllTasks() async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute('DELETE FROM tasks');
    });
  }

  Future<void> deleteAllDependencies() async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute('DELETE FROM dependencies');
    });
  }

  LegacyGanttTask _rowToTask(Map<String, Object?> row) {
    if (row['last_updated_by'] != null) {
      // Debug print to confirm reading
      print('LocalGanttRepository: Read task ${row['id']}, lastUpdatedBy: ${row['last_updated_by']}');
    }
    return LegacyGanttTask(
      id: row['id'] as String,
      rowId: row['row_id'] as String,
      start: DateTime.parse(row['start_date'] as String),
      end: DateTime.parse(row['end_date'] as String),
      name: row['name'] as String?,
      color: _parseColor(row['color'] as String?),
      textColor: _parseColor(row['text_color'] as String?),
      stackIndex: (row['stack_index'] as int?) ?? 0,
      isSummary: (row['is_summary'] as int?) == 1,
      isMilestone: (row['is_milestone'] as int?) == 1,
      resourceId: row['resource_id'] as String?,
      originalId:
          row['resource_id'] as String?, // Keep for compatibility if needed, but resource_id is the canonical field now
      completion: (row['completion'] as num?)?.toDouble() ?? 0.0,
      baselineStart: row['baseline_start'] != null ? DateTime.tryParse(row['baseline_start'] as String) : null,
      baselineEnd: row['baseline_end'] != null ? DateTime.tryParse(row['baseline_end'] as String) : null,
      notes: row['notes'] as String?,
      usesWorkCalendar: (row['uses_work_calendar'] as int?) == 1,
      parentId: row['parent_id'] as String?,
      isAutoScheduled: (row['is_auto_scheduled'] as int?) != 0,
      propagatesMoveToChildren: (row['propagates_move_to_children'] as int?) != 0,
      resizePolicy: ResizePolicy.values[(row['resize_policy'] as int?) ?? 0],
      lastUpdated: _parseHlc(row['last_updated']),
      lastUpdatedBy: row['last_updated_by'] as String?,
    );
  }

  LegacyGanttTaskDependency _rowToDependency(Map<String, Object?> row) => LegacyGanttTaskDependency(
        predecessorTaskId: row['from_id'] as String,
        successorTaskId: row['to_id'] as String,
        type: DependencyType.values[(row['type'] as int?) ?? 0],
        lag: row['lag_ms'] != null ? Duration(milliseconds: row['lag_ms'] as int) : null,
      );

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
  }

  Stream<List<LocalResource>> watchResources() async* {
    final db = await GanttDb.db;
    yield* db
        .watch('SELECT * FROM resources WHERE is_deleted = 0 ORDER BY COALESCE(sort_order, 100000000.0) ASC, id ASC')
        .map((rows) {
      final resources = rows.map((row) => _rowToResource(row)).toList();
      // No longer force sort by ID, trust DB order (which uses sort_order)
      return resources;
    });
  }

  Future<void> insertResources(List<LocalResource> resources) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      final batch = db.batch();
      for (final resource in resources) {
        batch.execute(
          '''
          UPDATE resources SET
            name = ?2,
            parent_id = ?3,
            is_expanded = ?4,
            last_updated = ?5,
            sort_order = ?6,
            deleted_at = NULL,
            is_deleted = 0
          WHERE id = ?1
          ''',
          [
            resource.id,
            resource.name,
            resource.parentId,
            resource.isExpanded ? 1 : 0,
            resource.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
            resource.sortOrder,
          ],
        );

        batch.execute(
          '''
          INSERT OR IGNORE INTO resources (id, name, parent_id, is_expanded, last_updated, sort_order, deleted_at)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL)
          ''',
          [
            resource.id,
            resource.name,
            resource.parentId,
            resource.isExpanded ? 1 : 0,
            resource.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
            resource.sortOrder,
          ],
        );
      }
      await batch.commit();
    });
  }

  Future<void> insertOrUpdateResource(LocalResource resource) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        '''
        UPDATE resources SET
          name = ?2,
          parent_id = ?3,
          is_expanded = ?4,
          last_updated = ?5,
          sort_order = ?6,
          deleted_at = NULL,
          is_deleted = 0
        WHERE id = ?1
        ''',
        [
          resource.id,
          resource.name,
          resource.parentId,
          resource.isExpanded ? 1 : 0,
          resource.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
          resource.sortOrder,
        ],
      );

      await db.execute(
        '''
        INSERT OR IGNORE INTO resources (id, name, parent_id, is_expanded, last_updated, sort_order, deleted_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL)
        ''',
        [
          resource.id,
          resource.name,
          resource.parentId,
          resource.isExpanded ? 1 : 0,
          resource.lastUpdated?.toString() ?? DateTime.now().millisecondsSinceEpoch,
          resource.sortOrder,
        ],
      );
    });
  }

  Future<void> updateResource(LocalResource resource) async {
    await insertResources([resource]);
  }

  Future<void> updateResourceExpansion(String id, bool isExpanded, Hlc timestamp) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE resources SET is_expanded = ?, last_updated = ? WHERE id = ?',
        [isExpanded ? 1 : 0, timestamp.toString(), id],
      );
    });
  }

  Future<void> deleteAllResources() async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute('DELETE FROM resources');
    });
  }

  Future<void> deleteResource(String id, Hlc timestamp) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute('UPDATE resources SET is_deleted = 1, deleted_at = ?, last_updated = ? WHERE id = ?',
          [timestamp.toString(), timestamp.toString(), id]);
    });
  }

  LocalResource _rowToResource(Map<String, Object?> row) => LocalResource(
        id: row['id'] as String,
        name: row['name'] as String?,
        parentId: row['parent_id'] as String?,
        isExpanded:
            (row['is_expanded'] is String ? int.tryParse(row['is_expanded'] as String) : row['is_expanded'] as int?) ==
                1,
        lastUpdated: _parseHlc(row['last_updated']),
        sortOrder: row['sort_order'] is String
            ? double.tryParse(row['sort_order'] as String)
            : (row['sort_order'] as num?)?.toDouble(),
      );

  Future<Hlc> getMaxLastUpdated() async {
    final db = await GanttDb.db;

    Hlc maxTs = Hlc.zero;

    final tRes =
        await db.query('SELECT MAX(MAX(COALESCE(last_updated, 0), COALESCE(deleted_at, 0))) as max_ts FROM tasks');
    if (tRes.isNotEmpty && tRes.first['max_ts'] != null) {
      final val = _parseHlc(tRes.first['max_ts']);
      if (val != null && val > maxTs) maxTs = val;
    }

    final dRes = await db
        .query('SELECT MAX(MAX(COALESCE(last_updated, 0), COALESCE(deleted_at, 0))) as max_ts FROM dependencies');
    if (dRes.isNotEmpty && dRes.first['max_ts'] != null) {
      final val = _parseHlc(dRes.first['max_ts']);
      if (val != null && val > maxTs) maxTs = val;
    }

    final rRes =
        await db.query('SELECT MAX(MAX(COALESCE(last_updated, 0), COALESCE(deleted_at, 0))) as max_ts FROM resources');
    if (rRes.isNotEmpty && rRes.first['max_ts'] != null) {
      final val = _parseHlc(rRes.first['max_ts']);
      if (val != null && val > maxTs) maxTs = val;
    }

    return maxTs;
  }

  Future<Hlc?> getLastServerSyncTimestamp() async {
    final db = await GanttDb.db;
    final res = await db.query('SELECT meta_value FROM sync_metadata WHERE meta_key = ?', ['last_server_sync']);
    if (res.isNotEmpty && res.first['meta_value'] != null) {
      return Hlc.parse(res.first['meta_value'] as String);
    }
    return null;
  }

  Future<void> setLastServerSyncTimestamp(Hlc timestamp) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'INSERT OR REPLACE INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)',
        ['last_server_sync', timestamp.toString()],
      );
    });
  }
}

class LocalResource {
  final String id;
  final String? name;
  final String? parentId;
  final bool isExpanded;
  final Hlc? lastUpdated;
  final double? sortOrder;

  const LocalResource({
    required this.id,
    this.name,
    this.parentId,
    this.isExpanded = true,
    this.lastUpdated,
    this.sortOrder,
  });

  LocalResource copyWith({
    String? id,
    String? name,
    String? parentId,
    bool? isExpanded,
    Hlc? lastUpdated,
    double? sortOrder,
  }) =>
      LocalResource(
        id: id ?? this.id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
        isExpanded: isExpanded ?? this.isExpanded,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
