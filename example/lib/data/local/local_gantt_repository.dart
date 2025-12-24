import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:synchronized/synchronized.dart';

import 'gantt_db.dart';

class LocalGanttRepository {
  final _lock = Lock();

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
        // SPLIT INTO UPDATE + INSERT OR IGNORE to avoid parser crash on ON CONFLICT
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
            resize_policy = ?21
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
            task.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
            task.completion,
            task.baselineStart?.toIso8601String(),
            task.baselineEnd?.toIso8601String(),
            task.notes,
            task.usesWorkCalendar ? 1 : 0,
            task.parentId,
            (task.isAutoScheduled ?? true) ? 1 : 0,
            task.propagatesMoveToChildren ? 1 : 0,
            task.resizePolicy.index
          ],
        );

        batch.execute(
          '''
          INSERT OR IGNORE INTO tasks (id, row_id, start_date, end_date, name, color, text_color, stack_index, is_summary, is_milestone, resource_id, last_updated, completion, baseline_start, baseline_end, notes, uses_work_calendar, deleted_at, is_deleted, parent_id, is_auto_scheduled, propagates_move_to_children, resize_policy)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, NULL, 0, ?18, ?19, ?20, ?21)
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
            task.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
            task.completion,
            task.baselineStart?.toIso8601String(),
            task.baselineEnd?.toIso8601String(),
            task.notes,
            task.usesWorkCalendar ? 1 : 0,
            task.parentId,
            (task.isAutoScheduled ?? true) ? 1 : 0,
            task.propagatesMoveToChildren ? 1 : 0,
            task.resizePolicy.index
          ],
        );
      }
      await batch.commit();
    });
  }

  Future<void> insertOrUpdateTask(LegacyGanttTask task) async {
    // Use lock to prevent concurrent writes that cause "database is locked" errors
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      // SPLIT INTO UPDATE + INSERT OR IGNORE to avoid parser crash on ON CONFLICT
      // Note: For single execution we *could* check results, but db.execute return value is implementation dependent for affected rows.
      // So we use the same robust double-statement pattern essentially.
      // Actually, since this is not a batch, we can be slightly more optimized if we want, but for consistency:
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
          resize_policy = ?21
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
          task.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
          task.completion,
          task.baselineStart?.toIso8601String(),
          task.baselineEnd?.toIso8601String(),
          task.notes,
          task.usesWorkCalendar ? 1 : 0,
          task.parentId,
          (task.isAutoScheduled ?? true) ? 1 : 0,
          task.propagatesMoveToChildren ? 1 : 0,
          task.resizePolicy.index
        ],
      );

      await db.execute(
        '''
        INSERT OR IGNORE INTO tasks (id, row_id, start_date, end_date, name, color, text_color, stack_index, is_summary, is_milestone, resource_id, last_updated, completion, baseline_start, baseline_end, notes, uses_work_calendar, deleted_at, is_deleted, parent_id, is_auto_scheduled, propagates_move_to_children, resize_policy)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, NULL, 0, ?18, ?19, ?20, ?21)
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
          task.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
          task.completion,
          task.baselineStart?.toIso8601String(),
          task.baselineEnd?.toIso8601String(),
          task.notes,
          task.usesWorkCalendar ? 1 : 0,
          task.parentId,
          (task.isAutoScheduled ?? true) ? 1 : 0,
          task.propagatesMoveToChildren ? 1 : 0,
          task.resizePolicy.index
        ],
      );
    });
  }

  Future<void> deleteTask(String taskId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE tasks SET is_deleted = 1, deleted_at = ?, last_updated = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch, taskId],
      );
    });
  }

  Future<void> insertDependencies(List<LegacyGanttTaskDependency> dependencies) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      final batch = db.batch();
      for (final dependency in dependencies) {
        // SPLIT INTO UPDATE + INSERT OR IGNORE
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
            dependency.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
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
            dependency.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
      await batch.commit();
    });
  }

  Future<void> insertOrUpdateDependency(LegacyGanttTaskDependency dependency) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      // SPLIT INTO UPDATE + INSERT OR IGNORE
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
          dependency.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
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
          dependency.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<void> deleteDependency(String fromId, String toId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE dependencies SET is_deleted = 1, deleted_at = ?, last_updated = ? WHERE from_id = ? AND to_id = ?',
        [DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch, fromId, toId],
      );
    });
  }

  Future<void> deleteDependenciesForTask(String taskId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE dependencies SET is_deleted = 1, deleted_at = ?, last_updated = ? WHERE from_id = ? OR to_id = ?',
        [DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch, taskId, taskId],
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

  // Helper to convert DB row to LegacyGanttTask
  LegacyGanttTask _rowToTask(Map<String, Object?> row) => LegacyGanttTask(
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
        originalId: row['resource_id']
            as String?, // Keep for compatibility if needed, but resource_id is the canonical field now
        completion: (row['completion'] as num?)?.toDouble() ?? 0.0,
        baselineStart: row['baseline_start'] != null ? DateTime.tryParse(row['baseline_start'] as String) : null,
        baselineEnd: row['baseline_end'] != null ? DateTime.tryParse(row['baseline_end'] as String) : null,
        notes: row['notes'] as String?,
        usesWorkCalendar: (row['uses_work_calendar'] as int?) == 1,
        parentId: row['parent_id'] as String?,
        isAutoScheduled: (row['is_auto_scheduled'] as int?) != 0,
        propagatesMoveToChildren: (row['propagates_move_to_children'] as int?) != 0,
        resizePolicy: ResizePolicy.values[(row['resize_policy'] as int?) ?? 0],
      );

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

  // Resources CRUD
  Stream<List<LocalResource>> watchResources() async* {
    final db = await GanttDb.db;
    yield* db.watch('SELECT * FROM resources WHERE is_deleted = 0 ORDER BY id ASC').map((rows) {
      final resources = rows.map((row) => _rowToResource(row)).toList();
      resources.sort((a, b) => compareNatural(a.id, b.id));
      return resources;
    });
  }

  Future<void> insertResources(List<LocalResource> resources) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      final batch = db.batch();
      for (final resource in resources) {
        // SPLIT INTO UPDATE + INSERT OR IGNORE
        batch.execute(
          '''
          UPDATE resources SET
            name = ?2,
            parent_id = ?3,
            is_expanded = ?4,
            last_updated = ?5,
            deleted_at = NULL,
            is_deleted = 0
          WHERE id = ?1
          ''',
          [
            resource.id,
            resource.name,
            resource.parentId,
            resource.isExpanded ? 1 : 0,
            resource.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );

        batch.execute(
          '''
          INSERT OR IGNORE INTO resources (id, name, parent_id, is_expanded, last_updated, deleted_at)
          VALUES (?1, ?2, ?3, ?4, ?5, NULL)
          ''',
          [
            resource.id,
            resource.name,
            resource.parentId,
            resource.isExpanded ? 1 : 0,
            resource.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
      await batch.commit();
    });
  }

  Future<void> insertOrUpdateResource(LocalResource resource) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      // SPLIT INTO UPDATE + INSERT OR IGNORE
      await db.execute(
        '''
        UPDATE resources SET
          name = ?2,
          parent_id = ?3,
          is_expanded = ?4,
          last_updated = ?5,
          deleted_at = NULL,
          is_deleted = 0
        WHERE id = ?1
        ''',
        [
          resource.id,
          resource.name,
          resource.parentId,
          resource.isExpanded ? 1 : 0,
          resource.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
        ],
      );

      await db.execute(
        '''
        INSERT OR IGNORE INTO resources (id, name, parent_id, is_expanded, last_updated, deleted_at)
        VALUES (?1, ?2, ?3, ?4, ?5, NULL)
        ''',
        [
          resource.id,
          resource.name,
          resource.parentId,
          resource.isExpanded ? 1 : 0,
          resource.lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<void> updateResourceExpansion(String id, bool isExpanded) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE resources SET is_expanded = ?, last_updated = ? WHERE id = ?',
        [isExpanded ? 1 : 0, DateTime.now().millisecondsSinceEpoch, id],
      );
    });
  }

  Future<void> deleteAllResources() async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute('DELETE FROM resources');
    });
  }

  Future<void> deleteResource(String id) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute('UPDATE resources SET deleted_at = ?, last_updated = ? WHERE id = ?',
          [DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch, id]);
    });
  }

  LocalResource _rowToResource(Map<String, Object?> row) => LocalResource(
        id: row['id'] as String,
        name: row['name'] as String?,
        parentId: row['parent_id'] as String?,
        isExpanded: (row['is_expanded'] as int?) == 1,
        lastUpdated: row['last_updated'] as int?,
      );

  Future<int> getMaxLastUpdated() async {
    final db = await GanttDb.db;
    // We want the maximum of last_updated OR deleted_at across all tables.
    // We can do this with a few queries.

    int maxTs = 0;

    final tRes =
        await db.query('SELECT MAX(MAX(COALESCE(last_updated, 0), COALESCE(deleted_at, 0))) as max_ts FROM tasks');
    if (tRes.isNotEmpty && tRes.first['max_ts'] != null) {
      final val = tRes.first['max_ts'] as int;
      if (val > maxTs) maxTs = val;
    }

    final dRes = await db
        .query('SELECT MAX(MAX(COALESCE(last_updated, 0), COALESCE(deleted_at, 0))) as max_ts FROM dependencies');
    if (dRes.isNotEmpty && dRes.first['max_ts'] != null) {
      final val = dRes.first['max_ts'] as int;
      if (val > maxTs) maxTs = val;
    }

    final rRes =
        await db.query('SELECT MAX(MAX(COALESCE(last_updated, 0), COALESCE(deleted_at, 0))) as max_ts FROM resources');
    if (rRes.isNotEmpty && rRes.first['max_ts'] != null) {
      final val = rRes.first['max_ts'] as int;
      if (val > maxTs) maxTs = val;
    }

    return maxTs;
  }

  Future<int?> getLastServerSyncTimestamp() async {
    final db = await GanttDb.db;
    final res = await db.query('SELECT meta_value FROM sync_metadata WHERE meta_key = ?', ['last_server_sync']);
    if (res.isNotEmpty && res.first['meta_value'] != null) {
      return int.tryParse(res.first['meta_value'] as String);
    }
    return null;
  }

  Future<void> setLastServerSyncTimestamp(int timestamp) async {
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
  final int? lastUpdated;

  LocalResource({required this.id, this.name, this.parentId, this.isExpanded = true, this.lastUpdated});
}
