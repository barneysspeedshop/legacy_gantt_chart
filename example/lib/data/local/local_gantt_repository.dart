import 'dart:ui';
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
        .watch('SELECT * FROM tasks WHERE is_deleted = 0')
        .map((rows) => rows.map((row) => _rowToTask(row)).toList());
  }

  Stream<List<LegacyGanttTaskDependency>> watchDependencies() async* {
    final db = await GanttDb.db;
    yield* db
        .watch('SELECT * FROM dependencies WHERE is_deleted = 0')
        .map((rows) => rows.map((row) => _rowToDependency(row)).toList());
  }

  Future<void> insertOrUpdateTask(LegacyGanttTask task) async {
    await bulkInsertOrUpdateTasks([task]);
  }

  Future<void> bulkInsertOrUpdateTasks(List<LegacyGanttTask> tasks) async {
    if (tasks.isEmpty) return;
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.transaction((txn) async {
        const sql = '''
          INSERT INTO tasks (id, row_id, start_date, end_date, name, color, text_color, stack_index, is_summary, is_milestone, resource_id, last_updated, is_deleted)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, 0)
          ON CONFLICT(id) DO UPDATE SET
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
            is_deleted = 0
        ''';

        for (final task in tasks) {
          await txn.execute(
            sql,
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
              task.originalId,
              task.lastUpdated,
            ],
          );
        }
      });
    });
  }

  Future<void> deleteTask(String taskId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE tasks SET is_deleted = 1, last_updated = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch, taskId],
      );
    });
  }

  Future<void> insertOrUpdateDependency(LegacyGanttTaskDependency dependency) async {
    await bulkInsertOrUpdateDependencies([dependency]);
  }

  Future<void> bulkInsertOrUpdateDependencies(List<LegacyGanttTaskDependency> dependencies) async {
    if (dependencies.isEmpty) return;
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.transaction((txn) async {
        const sql = '''
          INSERT INTO dependencies (from_id, to_id, type, lag_ms, last_updated, is_deleted)
          VALUES (?1, ?2, ?3, ?4, ?5, 0)
          ON CONFLICT(from_id, to_id) DO UPDATE SET
            type = ?3,
            lag_ms = ?4,
            last_updated = ?5,
            is_deleted = 0
        ''';

        for (final dependency in dependencies) {
          await txn.execute(
            sql,
            [
              dependency.predecessorTaskId,
              dependency.successorTaskId,
              dependency.type.index,
              dependency.lag?.inMilliseconds,
              dependency.lastUpdated,
            ],
          );
        }
      });
    });
  }

  Future<void> deleteDependency(String fromId, String toId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE dependencies SET is_deleted = 1, last_updated = ? WHERE from_id = ? AND to_id = ?',
        [DateTime.now().millisecondsSinceEpoch, fromId, toId],
      );
    });
  }

  Future<void> deleteDependenciesForTask(String taskId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE dependencies SET is_deleted = 1, last_updated = ? WHERE from_id = ? OR to_id = ?',
        [DateTime.now().millisecondsSinceEpoch, taskId, taskId],
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

  Future<LegacyGanttTask?> getTask(String id) async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM tasks WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _rowToTask(rows.first);
  }

  Future<LegacyGanttTaskDependency?> getDependency(String fromId, String toId) async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM dependencies WHERE from_id = ? AND to_id = ?', [fromId, toId]);
    if (rows.isEmpty) return null;
    return _rowToDependency(rows.first);
  }

  Future<List<LegacyGanttTask>> getTasks() async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM tasks WHERE is_deleted = 0');
    return rows.map((row) => _rowToTask(row)).toList();
  }

  Future<List<LegacyGanttTaskDependency>> getDependencies() async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM dependencies WHERE is_deleted = 0');
    return rows.map((row) => _rowToDependency(row)).toList();
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
        originalId: row['resource_id'] as String?,
        lastUpdated: row['last_updated'] as int?,
      );

  LegacyGanttTaskDependency _rowToDependency(Map<String, Object?> row) => LegacyGanttTaskDependency(
        predecessorTaskId: row['from_id'] as String,
        successorTaskId: row['to_id'] as String,
        type: DependencyType.values[(row['type'] as int?) ?? 0],
        lag: row['lag_ms'] != null ? Duration(milliseconds: row['lag_ms'] as int) : null,
        lastUpdated: row['last_updated'] as int?,
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
    yield* db.watch('SELECT * FROM resources').map((rows) => rows.map((row) => _rowToResource(row)).toList());
  }

  Future<void> insertOrUpdateResource(LocalResource resource) async {
    await bulkInsertOrUpdateResources([resource]);
  }

  Future<void> bulkInsertOrUpdateResources(List<LocalResource> resources) async {
    if (resources.isEmpty) return;
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.transaction((txn) async {
        const sql = '''
          INSERT INTO resources (id, name, parent_id, is_expanded, last_updated)
          VALUES (?1, ?2, ?3, ?4, ?5)
          ON CONFLICT(id) DO UPDATE SET
            name = ?2,
            parent_id = ?3,
            is_expanded = ?4,
            last_updated = ?5
        ''';

        for (final resource in resources) {
          await txn.execute(
            sql,
            [resource.id, resource.name, resource.parentId, resource.isExpanded ? 1 : 0, resource.lastUpdated],
          );
        }
      });
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
      await db.execute('DELETE FROM resources WHERE id = ?', [id]);
    });
  }

  Future<LocalResource?> getResource(String id) async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM resources WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _rowToResource(rows.first);
  }

  Future<List<LocalResource>> getResources() async {
    final db = await GanttDb.db;
    final rows = await db.query('SELECT * FROM resources');
    return rows.map((row) => _rowToResource(row)).toList();
  }

  LocalResource _rowToResource(Map<String, Object?> row) => LocalResource(
        id: row['id'] as String,
        name: row['name'] as String?,
        parentId: row['parent_id'] as String?,
        isExpanded: (row['is_expanded'] as int?) == 1,
        lastUpdated: row['last_updated'] as int?,
      );
}

class LocalResource {
  final String id;
  final String? name;
  final String? parentId;
  final bool isExpanded;
  final int? lastUpdated;

  LocalResource({required this.id, this.name, this.parentId, this.isExpanded = true, this.lastUpdated});
}
