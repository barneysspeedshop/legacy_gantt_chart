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

    test('LegacyGanttTaskSegment JSON serialization', () {
      final segment = LegacyGanttTaskSegment(
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 2),
        color: const Color(0xFF00FF00),
      );

      final json = segment.toJson();
      expect(json['color'], 'ff00ff00');
    });
  });
}
