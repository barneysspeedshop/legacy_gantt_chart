import 'dart:convert';

import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;

import 'local_gantt_repository.dart';

class ProtocolSnapshot {
  final List<LegacyGanttTask> tasks;
  final List<LocalResource> resources;
  final List<LegacyGanttTaskDependency> dependencies;
  final Hlc? lastReset;
  final Hlc? latestClock;
  final bool hasState;

  ProtocolSnapshot({
    required List<LegacyGanttTask> tasks,
    required List<LocalResource> resources,
    required List<LegacyGanttTaskDependency> dependencies,
    this.lastReset,
    this.latestClock,
    this.hasState = false,
  }) : tasks = List.unmodifiable(tasks),
       resources = List.unmodifiable(resources),
       dependencies = List.unmodifiable(dependencies);
}

class ProtocolCommit {
  final ProtocolSnapshot state;
  final bool changed;
  final Hlc? acceptedReset;

  const ProtocolCommit({required this.state, required this.changed, this.acceptedReset});
}

/// Builds the read model from accepted CRDT entities, never from raw operations.
class ProtocolProjection {
  static ProtocolSnapshot snapshot(
    Iterable<ProtocolTask> tasks,
    Iterable<ProtocolResource> resources,
    Iterable<ProtocolDependency> dependencies,
    Hlc? lastReset,
  ) {
    Hlc? latest = lastReset;
    void observe(String value) {
      if (value.isEmpty) return;
      final clock = Hlc.parse(value);
      if (latest == null || clock > latest!) latest = clock;
    }

    for (final task in tasks) {
      observe(task.lastUpdated);
    }
    for (final resource in resources) {
      observe(resource.lastUpdated);
    }
    for (final dependency in dependencies) {
      observe(dependency.lastUpdated);
    }
    return ProtocolSnapshot(
      tasks: tasks.where((task) => !task.isDeleted).map(_task).toList()
        ..sort((a, b) {
          final dates = a.start.compareTo(b.start);
          return dates == 0 ? a.id.compareTo(b.id) : dates;
        }),
      resources: resources.where((resource) => !resource.isDeleted).map(_resource).toList()
        ..sort((a, b) {
          final order = (a.sortOrder ?? 100000000).compareTo(b.sortOrder ?? 100000000);
          return order == 0 ? a.id.compareTo(b.id) : order;
        }),
      dependencies: dependencies.where((dependency) => dependency.type != 'DELETE').map(_dependency).toList(),
      lastReset: lastReset,
      latestClock: latest,
      hasState: lastReset != null || tasks.isNotEmpty || resources.isNotEmpty || dependencies.isNotEmpty,
    );
  }

  static LegacyGanttTask _task(ProtocolTask task) {
    final metadata = ProtobufMapper.metadataFromJson({'metadataJson': task.metadataJson});
    const aliases = {
      'text_color': 'textColor',
      'stack_index': 'stackIndex',
      'uses_work_calendar': 'usesWorkCalendar',
      'is_auto_scheduled': 'isAutoScheduled',
      'propagates_move_to_children': 'propagatesMoveToChildren',
      'resize_policy': 'resizePolicy',
      'baseline_start': 'baselineStart',
      'baseline_end': 'baselineEnd',
      'is_time_range_highlight': 'isTimeRangeHighlight',
    };
    for (final entry in aliases.entries) {
      if (!metadata.containsKey(entry.value) && metadata.containsKey(entry.key)) {
        metadata[entry.value] = metadata[entry.key];
      }
    }
    final policy = metadata['resizePolicy'];
    final policyIndex = policy is num ? policy.toInt() : int.tryParse('$policy');
    if (policyIndex != null && policyIndex >= 0 && policyIndex < ResizePolicy.values.length) {
      metadata['resizePolicy'] = ResizePolicy.values[policyIndex].name;
    }
    for (final key in ['baselineStart', 'baselineEnd']) {
      final value = metadata[key];
      if (value == '') metadata[key] = null;
      if (value is num) metadata[key] = DateTime.fromMillisecondsSinceEpoch(value.toInt()).toUtc().toIso8601String();
    }
    return LegacyGanttTask.fromProtocolTask(task.deepCopy()..metadataJson = jsonEncode(metadata));
  }

  static LocalResource _resource(ProtocolResource resource) {
    final metadata = ProtobufMapper.metadataFromJson({'metadataJson': resource.metadataJson});
    final order = metadata['sort_order'] ?? metadata['sortOrder'];
    return LocalResource(
      id: resource.id,
      name: resource.name.isEmpty ? null : resource.name,
      parentId: resource.parentId.isEmpty ? null : resource.parentId,
      type: resource.type,
      extraMetadata: metadata,
      isExpanded: _boolean(metadata['isExpanded'] ?? metadata['is_expanded'], fallback: true),
      lastUpdated: resource.parsedLastUpdated,
      sortOrder: order is num ? order.toDouble() : double.tryParse('$order'),
    );
  }

  static bool _boolean(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value == 1 || value == '1' || value == 'true') return true;
    if (value == 0 || value == '0' || value == 'false') return false;
    return fallback;
  }

  static LegacyGanttTaskDependency _dependency(ProtocolDependency dependency) {
    final numericType = int.tryParse(dependency.type);
    final type = numericType != null && numericType >= 0 && numericType < DependencyType.values.length
        ? DependencyType.values[numericType]
        : DependencyType.values.firstWhere(
            (value) => value.name.toLowerCase() == dependency.type.toLowerCase(),
            orElse: () => DependencyType.finishToStart,
          );
    return LegacyGanttTaskDependency(
      predecessorTaskId: dependency.predecessorTaskId,
      successorTaskId: dependency.successorTaskId,
      type: type,
      lag: Duration(milliseconds: dependency.lag.toInt()),
      lastUpdated: dependency.parsedLastUpdated,
    );
  }

  static Future<void> write(
    CrdtExecutor transaction,
    ProtocolSnapshot snapshot, {
    required Set<String> taskIds,
    required Set<String> resourceIds,
    required Set<String> dependencyKeys,
    bool replace = false,
  }) async {
    if (replace) {
      await transaction.execute('DELETE FROM dependencies');
      await transaction.execute('DELETE FROM tasks');
      await transaction.execute('DELETE FROM resources');
    } else {
      if (taskIds.isNotEmpty) {
        await transaction.execute('DELETE FROM tasks WHERE id IN (SELECT value FROM json_each(?))', [
          jsonEncode(taskIds.toList()),
        ]);
      }
      if (resourceIds.isNotEmpty) {
        await transaction.execute('DELETE FROM resources WHERE id IN (SELECT value FROM json_each(?))', [
          jsonEncode(resourceIds.toList()),
        ]);
      }
      if (dependencyKeys.isNotEmpty) {
        await transaction.execute(
          r'''DELETE FROM dependencies WHERE EXISTS (SELECT 1 FROM json_each(?1)
          WHERE from_id = json_extract(value, '$[0]') AND to_id = json_extract(value, '$[1]'))''',
          [jsonEncode(dependencyKeys.map(jsonDecode).toList())],
        );
      }
    }
    final taskRows = snapshot.tasks
        .where((task) => replace || taskIds.contains(task.id))
        .map(
          (task) => {
            'id': task.id,
            'row_id': task.rowId,
            'start_date': task.start.toIso8601String(),
            'end_date': task.end.toIso8601String(),
            'name': task.name,
            'color': task.color?.toARGB32().toRadixString(16),
            'text_color': task.textColor?.toARGB32().toRadixString(16),
            'stack_index': task.stackIndex,
            'is_summary': task.isSummary ? 1 : 0,
            'is_milestone': task.isMilestone ? 1 : 0,
            'resource_id': task.resourceId ?? task.originalId,
            'last_updated': task.lastUpdated.toString(),
            'completion': task.completion,
            'baseline_start': task.baselineStart?.toIso8601String(),
            'baseline_end': task.baselineEnd?.toIso8601String(),
            'notes': task.notes,
            'uses_work_calendar': task.usesWorkCalendar ? 1 : 0,
            'parent_id': task.parentId,
            'is_auto_scheduled': task.isAutoScheduled == false ? 0 : 1,
            'propagates_move_to_children': task.propagatesMoveToChildren ? 1 : 0,
            'resize_policy': task.resizePolicy.index,
            'last_updated_by': task.lastUpdatedBy,
            'is_time_range_highlight': task.isTimeRangeHighlight ? 1 : 0,
            'deleted_at': null,
            'is_deleted': 0,
          },
        )
        .toList();
    final resourceRows = snapshot.resources
        .where((resource) => replace || resourceIds.contains(resource.id))
        .map(
          (resource) => {
            'id': resource.id,
            'name': resource.name,
            'parent_id': resource.parentId,
            'is_expanded': resource.isExpanded ? 1 : 0,
            'last_updated': resource.lastUpdated?.toString(),
            'sort_order': resource.sortOrder,
            'deleted_at': null,
            'is_deleted': 0,
          },
        )
        .toList();
    final dependencyRows = snapshot.dependencies
        .where(
          (dependency) =>
              replace ||
              dependencyKeys.contains(jsonEncode([dependency.predecessorTaskId, dependency.successorTaskId])),
        )
        .map(
          (dependency) => {
            'from_id': dependency.predecessorTaskId,
            'to_id': dependency.successorTaskId,
            'type': dependency.type.index,
            'lag_ms': dependency.lag?.inMilliseconds,
            'last_updated': dependency.lastUpdated?.toString(),
            'deleted_at': null,
            'is_deleted': 0,
          },
        )
        .toList();
    await _writeRows(transaction, 'tasks', taskRows);
    await _writeRows(transaction, 'resources', resourceRows);
    await _writeRows(transaction, 'dependencies', dependencyRows);
  }

  static Future<void> _writeRows(CrdtExecutor transaction, String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final columns = rows.first.keys.toList();
    await transaction.execute(
      'INSERT OR REPLACE INTO $table (${columns.join(', ')}) SELECT ${columns.map((column) => "json_extract(value, '\$.$column')").join(', ')} FROM json_each(?1)',
      [jsonEncode(rows)],
    );
  }
}
