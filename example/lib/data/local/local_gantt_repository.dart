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
    // Use lock to prevent concurrent writes that cause "database is locked" errors
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        '''
      INSERT INTO tasks (id, row_id, start_date, end_date, name, color, text_color, stack_index, is_summary, is_milestone, resource_id, is_deleted)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 0)
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
        is_deleted = 0
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
          task.originalId, // Storing originalId/resourceId here for now
        ],
      );
    });
  }

  Future<void> deleteTask(String taskId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE tasks SET is_deleted = 1 WHERE id = ?',
        [taskId],
      );
    });
  }

  Future<void> insertOrUpdateDependency(LegacyGanttTaskDependency dependency) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        '''
      INSERT INTO dependencies (from_id, to_id, type, lag_ms, is_deleted)
      VALUES (?1, ?2, ?3, ?4, 0)
      ON CONFLICT(from_id, to_id) DO UPDATE SET
        type = ?3,
        lag_ms = ?4,
        is_deleted = 0
      ''',
        [
          dependency.predecessorTaskId,
          dependency.successorTaskId,
          dependency.type.index,
          dependency.lag?.inMilliseconds,
        ],
      );
    });
  }

  Future<void> deleteDependency(String fromId, String toId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE dependencies SET is_deleted = 1 WHERE from_id = ? AND to_id = ?',
        [fromId, toId],
      );
    });
  }

  Future<void> deleteDependenciesForTask(String taskId) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE dependencies SET is_deleted = 1 WHERE from_id = ? OR to_id = ?',
        [taskId, taskId],
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
        originalId: row['resource_id'] as String?,
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
    yield* db.watch('SELECT * FROM resources').map((rows) => rows.map((row) => _rowToResource(row)).toList());
  }

  Future<void> insertOrUpdateResource(LocalResource resource) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        '''
      INSERT INTO resources (id, name, parent_id, is_expanded)
      VALUES (?1, ?2, ?3, ?4)
      ON CONFLICT(id) DO UPDATE SET
        name = ?2,
        parent_id = ?3,
        is_expanded = ?4
      ''',
        [resource.id, resource.name, resource.parentId, resource.isExpanded ? 1 : 0],
      );
    });
  }

  Future<void> updateResourceExpansion(String id, bool isExpanded) async {
    await _lock.synchronized(() async {
      final db = await GanttDb.db;
      await db.execute(
        'UPDATE resources SET is_expanded = ? WHERE id = ?',
        [isExpanded ? 1 : 0, id],
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

  LocalResource _rowToResource(Map<String, Object?> row) => LocalResource(
        id: row['id'] as String,
        name: row['name'] as String?,
        parentId: row['parent_id'] as String?,
        isExpanded: (row['is_expanded'] as int?) == 1,
      );
}

class LocalResource {
  final String id;
  final String? name;
  final String? parentId;
  final bool isExpanded;

  LocalResource({required this.id, this.name, this.parentId, this.isExpanded = true});
}
