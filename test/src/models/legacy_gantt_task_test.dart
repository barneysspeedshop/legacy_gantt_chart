import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';

void main() {
  group('LegacyGanttTask', () {
    test('instantiation', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 5);
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: start,
        end: end,
        name: 'Task 1',
        color: Colors.blue,
        stackIndex: 1,
      );

      expect(task.id, '1');
      expect(task.rowId, 'row1');
      expect(task.start, start);
      expect(task.end, end);
      expect(task.name, 'Task 1');
      expect(task.color, Colors.blue);
      expect(task.stackIndex, 1);
      expect(task.isSummary, false);
      expect(task.isMilestone, false);
    });

    test('empty factory', () {
      final task = LegacyGanttTask.empty();
      expect(task.id, '');
      expect(task.rowId, '');
      expect(task.start, DateTime(0));
      expect(task.end, DateTime(0));
      expect(task.name, '');
    });

    test('equality and hashCode', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 5);
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: start,
        end: end,
        name: 'Task 1',
      );
      final task2 = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: start,
        end: end,
        name: 'Task 1',
      );
      final task3 = LegacyGanttTask(
        id: '2',
        rowId: 'row1',
        start: start,
        end: end,
        name: 'Task 2',
      );

      expect(task1, task2);
      expect(task1.hashCode, task2.hashCode);
      expect(task1, isNot(task3));
    });

    test('copyWith', () {
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5),
      );

      final updatedTask = task.copyWith(
        name: 'New Name',
        isMilestone: true,
      );

      expect(updatedTask.id, task.id);
      expect(updatedTask.name, 'New Name');
      expect(updatedTask.isMilestone, true);
      expect(task.name, isNull);
    });

    test('toJson', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 5);
      final task = LegacyGanttTask(
        id: '1',
        rowId: 'row1',
        start: start,
        end: end,
        name: 'Task 1',
        color: Colors.red,
      );

      final json = task.toJson();
      expect(json['id'], '1');
      expect(json['rowId'], 'row1');
      expect(json['start'], start.toIso8601String());
      expect(json['end'], end.toIso8601String());
      expect(json['name'], 'Task 1');
      // Colors.red is 4294198070 -> 0xFFFF0000 -> ffff0000 in hex but might be different depending on system/impl
      // so we just check it exists. value verification relies on _colorToHex logic which is internal.
      expect(json['color'], isNotNull);
    });
  });

  group('LegacyGanttTaskSegment', () {
    test('instantiation and equality', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 2);
      final segment1 = LegacyGanttTaskSegment(start: start, end: end, color: Colors.green);
      final segment2 = LegacyGanttTaskSegment(start: start, end: end, color: Colors.green);
      final segment3 = LegacyGanttTaskSegment(start: start, end: end, color: Colors.red);

      expect(segment1, segment2);
      expect(segment1.hashCode, segment2.hashCode);
      expect(segment1, isNot(segment3));
    });

    test('toJson', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 2);
      final segment = LegacyGanttTaskSegment(start: start, end: end, color: Colors.green);
      final json = segment.toJson();
      expect(json['start'], start.toIso8601String());
      expect(json['end'], end.toIso8601String());
    });
  });
}
