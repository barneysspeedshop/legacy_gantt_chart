import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/utils/legacy_gantt_conflict_detector.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';

void main() {
  group('LegacyGanttConflictDetector', () {
    final detector = LegacyGanttConflictDetector();

    test('no conflicts when tasks do not overlap', () {
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Task 1',
      );
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 11),
        name: 'Task 2',
      );

      final indicators = detector.run<String>(
        tasks: [task1, task2],
        taskGrouper: (t) => t.rowId,
      );

      expect(indicators, isEmpty);
    });

    test('detects simple overlap', () {
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 11),
        name: 'Task 1',
      );
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 12),
        name: 'Task 2',
      );

      final indicators = detector.run<String>(
        tasks: [task1, task2],
        taskGrouper: (t) => t.rowId,
      );

      // Should produce indicators for the overlap duration 10:00 - 11:00
      // One indicator for task 1, one for task 2
      expect(indicators.length, greaterThanOrEqualTo(2));

      final indicator1 = indicators.firstWhere((t) => t.id.contains('overlap-1-'));
      expect(indicator1.start, DateTime(2023, 1, 1, 10));
      expect(indicator1.end, DateTime(2023, 1, 1, 11));
      expect(indicator1.isOverlapIndicator, isTrue);

      final indicator2 = indicators.firstWhere((t) => t.id.contains('overlap-2-'));
      expect(indicator2.start, DateTime(2023, 1, 1, 10));
      expect(indicator2.end, DateTime(2023, 1, 1, 11));
    });

    test('detects overlap with segments', () {
      // Task 1 has two segments: 9-10 and 12-13
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 13),
        segments: [
          LegacyGanttTaskSegment(start: DateTime(2023, 1, 1, 9), end: DateTime(2023, 1, 1, 10)),
          LegacyGanttTaskSegment(start: DateTime(2023, 1, 1, 12), end: DateTime(2023, 1, 1, 13)),
        ],
      );
      // Task 2 overlaps only with the second segment: 12:30-13:30
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 12, 30),
        end: DateTime(2023, 1, 1, 13, 30),
      );

      final indicators = detector.run<String>(
        tasks: [task1, task2],
        taskGrouper: (t) => t.rowId,
      );

      // overlap should be 12:30 - 13:00
      expect(indicators, isNotEmpty);
      final indicator = indicators.first;
      expect(indicator.start, DateTime(2023, 1, 1, 12, 30));
      expect(indicator.end, DateTime(2023, 1, 1, 13));
    });

    test('summary task overlap indicators', () {
      final summary = LegacyGanttTask(
        id: 'summary',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 17),
        isSummary: true,
      );
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 12),
      );
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 11),
        end: DateTime(2023, 1, 1, 13),
      );

      final indicators = detector.run<String>(
        tasks: [summary, task1, task2],
        taskGrouper: (t) => t.rowId,
      );

      // Conflict is 11-12.
      // Should have indicators for task1, task2 AND summary.
      final summaryIndicators = indicators.where((t) => t.id.contains('overlap-parent-summary')).toList();
      expect(summaryIndicators, isNotEmpty);
      expect(summaryIndicators.first.start, DateTime(2023, 1, 1, 11));
      expect(summaryIndicators.first.end, DateTime(2023, 1, 1, 12));
    });

    test('ignores null groups', () {
      final task1 = LegacyGanttTask(
        id: '1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 12),
      );
      final task2 = LegacyGanttTask(
        id: '2',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 12),
      );

      // Grouper returns null -> ignore
      final indicators = detector.run<String>(
        tasks: [task1, task2],
        taskGrouper: (t) => null,
      );
      expect(indicators, isEmpty);
    });
  });
}
