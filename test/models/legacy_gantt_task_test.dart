import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('LegacyGanttTask', () {
    test('instantiation works', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023),
        end: DateTime(2023, 1, 2),
        name: 'Task 1',
      );
      expect(task.id, '1');
      expect(task.name, 'Task 1');
    });

    test('copyWith works correctly', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023),
        end: DateTime(2023, 1, 2),
        name: 'Task 1',
        color: Colors.red,
      );

      final updated = task.copyWith(
        name: 'Updated Name',
        color: Colors.blue,
      );

      expect(updated.id, '1'); // Original property preserved
      expect(updated.name, 'Updated Name'); // Updated property
      expect(updated.color, Colors.blue); // Updated property
    });

    test('equality works', () {
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023),
        end: DateTime(2023, 1, 2),
      );
      final task2 = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023),
        end: DateTime(2023, 1, 2),
      );
      final task3 = LegacyGanttTask(
        id: '2',
        rowId: 'row1',
        start: DateTime(2023),
        end: DateTime(2023, 1, 2),
      );

      expect(task1, equals(task2));
      expect(task1, isNot(equals(task3)));
    });

    test('toJson serializes correctly', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        name: 'Task 1',
        color: const Color(0xFFFF0000), // Red
      );

      final json = task.toJson();
      expect(json['id'], '1');
      expect(json['rowId'], 'row1');
      expect(json['color'], 'ffff0000');
    });

    test('LegacyGanttTaskSegment JSON serialization and deserialization', () {
      final segment = LegacyGanttTaskSegment(
        start: DateTime.utc(2023, 1, 1),
        end: DateTime.utc(2023, 1, 2),
        color: const Color(0xFF00FF00),
      );

      final json = segment.toJson();
      expect(json['color'], 'ff00ff00');

      final restored = LegacyGanttTaskSegment.fromJson(json);
      expect(restored, equals(segment));
      expect(restored.hashCode, equals(segment.hashCode));
    });

    test('parseColor handles various formats', () {
      // Since _parseColor is private, we test it through LegacyGanttTask.fromProtocolTask or similar
      final taskWithHex = LegacyGanttTask.fromProtocolTask(ProtocolTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023),
        end: DateTime(2023),
        lastUpdated: Hlc.zero,
        metadata: {'color': '#ff0000'},
      ));
      expect(taskWithHex.color, equals(const Color(0xFFFF0000)));

      final taskWithInt = LegacyGanttTask.fromJson({
        'id': '1',
        'rowId': 'r1',
        'start': DateTime(2023).toIso8601String(),
        'end': DateTime(2023).toIso8601String(),
        'color': 0xFF00FF00,
      });
      expect(taskWithInt.color, equals(const Color(0xFF00FF00)));

      final taskWithInvalid = LegacyGanttTask.fromProtocolTask(ProtocolTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023),
        end: DateTime(2023),
        lastUpdated: Hlc.zero,
        metadata: {'color': 'invalid'},
      ));
      expect(taskWithInvalid.color, isNull);
    });

    test('toProtocolTask and fromProtocolTask are consistent', () {
      final task = LegacyGanttTask(
        id: 'task-1',
        rowId: 'row-1',
        start: DateTime.utc(2023, 1, 1),
        end: DateTime.utc(2023, 1, 5),
        name: 'Comprehensive Task',
        color: const Color(0xFF2196F3), // blue
        textColor: const Color(0xFFFFFFFF), // white
        isSummary: true,
        completion: 0.75,
        isMilestone: false,
        resourceId: 'res-1',
        parentId: 'parent-1',
        notes: 'Some notes',
        usesWorkCalendar: true,
        load: 0.5,
        isAutoScheduled: true,
        resizePolicy: ResizePolicy.elastic,
        baselineStart: DateTime.utc(2022, 12, 31),
        baselineEnd: DateTime.utc(2023, 1, 6),
        segments: [
          LegacyGanttTaskSegment(start: DateTime.utc(2023, 1, 1), end: DateTime.utc(2023, 1, 2)),
        ],
      );

      final protocolTask = task.toProtocolTask();
      final restored = LegacyGanttTask.fromProtocolTask(protocolTask);

      expect(restored, equals(task));
      expect(restored.isSummary, isTrue);
      expect(restored.resizePolicy, ResizePolicy.elastic);
    });

    test('fromJson and toJson are consistent', () {
      final task = LegacyGanttTask(
        id: 'json-1',
        rowId: 'row-1',
        start: DateTime.utc(2023, 1, 1),
        end: DateTime.utc(2023, 1, 5),
        name: 'JSON Task',
        color: const Color(0xFFFF0000), // red
      );

      final json = task.toJson();
      final restored = LegacyGanttTask.fromJson(json);

      if (restored != task) {
        print('JSON Task mismatch details:');
        print('id match: ${restored.id == task.id}');
        print('rowId match: ${restored.rowId == task.rowId}');
        print('start match: ${restored.start == task.start}');
        print('end match: ${restored.end == task.end}');
        print('name match: ${restored.name == task.name}');
        print('color match: ${restored.color == task.color}');
        if (restored.color != task.color) {
          print('  restored color: ${restored.color} (type: ${restored.color.runtimeType})');
          print('  task color: ${task.color} (type: ${task.color.runtimeType})');
        }
        print('isSummary match: ${restored.isSummary == task.isSummary}');
        print('lastUpdated match: ${restored.lastUpdated == task.lastUpdated}');
      }

      expect(restored, equals(task));
    });

    test('copyWithProtocol preserves nested structures', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023),
        end: DateTime(2023),
        cellBuilder: (date) => Container(),
      );

      final pt = ProtocolTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023),
        end: DateTime(2023, 1, 2),
        lastUpdated: Hlc.zero,
        name: 'Updated via Protocol',
      );

      final updated = task.copyWithProtocol(pt);
      expect(updated.name, 'Updated via Protocol');
      expect(updated.cellBuilder, isNotNull); // Preserved
    });

    test('complex equality covers segments and fieldTimestamps', () {
      final t1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023),
        end: DateTime(2023),
        segments: [LegacyGanttTaskSegment(start: DateTime(2023), end: DateTime(2023))],
      );
      final t2 = t1.copyWith();
      final t3 = t1.copyWith(segments: []);

      expect(t1, equals(t2));
      expect(t1, isNot(equals(t3)));
    });

    test('contentHash delegates to protocol task', () {
      final task = LegacyGanttTask(id: '1', rowId: 'r1', start: DateTime(2023), end: DateTime(2023));
      expect(task.contentHash, equals(task.toProtocolTask().contentHash));
    });

    test('empty factory creates base task', () {
      final empty = LegacyGanttTask.empty();
      expect(empty.id, isEmpty);
      expect(empty.start.year, 0);
    });
  });
}
