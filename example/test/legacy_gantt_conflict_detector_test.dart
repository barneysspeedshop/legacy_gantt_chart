import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('LegacyGanttConflictDetector', () {
    late LegacyGanttConflictDetector detector;

    setUp(() {
      detector = LegacyGanttConflictDetector();
    });

    test('returns no conflicts for non-overlapping tasks', () {
      final tasks = [
        LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 5)),
        LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime(2023, 1, 6), end: DateTime(2023, 1, 10)),
      ];

      final conflicts = detector.run(tasks: tasks, taskGrouper: (task) => task.rowId);

      expect(conflicts, isEmpty);
    });

    test('detects simple overlap between two tasks in the same group', () {
      final tasks = [
        LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 7)),
        LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime(2023, 1, 5), end: DateTime(2023, 1, 10)),
      ];

      final conflicts = detector.run(tasks: tasks, taskGrouper: (task) => task.rowId);

      expect(conflicts.length, 2);
      expect(conflicts.every((t) => t.isOverlapIndicator), isTrue);

      // Check the first indicator (for t1)
      final conflict1 = conflicts.firstWhere((c) => c.id.contains('t1'));
      expect(conflict1.start, DateTime(2023, 1, 5));
      expect(conflict1.end, DateTime(2023, 1, 7));
      expect(conflict1.rowId, 'r1');

      // Check the second indicator (for t2)
      final conflict2 = conflicts.firstWhere((c) => c.id.contains('t2'));
      expect(conflict2.start, DateTime(2023, 1, 5));
      expect(conflict2.end, DateTime(2023, 1, 7));
      expect(conflict2.rowId, 'r1');
    });

    test('ignores tasks in different groups', () {
      final tasks = [
        LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 7)),
        LegacyGanttTask(id: 't2', rowId: 'r2', start: DateTime(2023, 1, 5), end: DateTime(2023, 1, 10)),
      ];

      final conflicts = detector.run(tasks: tasks, taskGrouper: (task) => task.rowId);

      expect(conflicts, isEmpty);
    });

    test('detects conflicts on summary tasks', () {
      final tasks = [
        // Summary task for the group
        LegacyGanttTask(
            id: 'summary1',
            rowId: 'summaryRow',
            start: DateTime(2023, 1, 1),
            end: DateTime(2023, 1, 15),
            isSummary: true),
        // Child tasks that conflict
        LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 7)),
        LegacyGanttTask(id: 't2', rowId: 'r1', start: DateTime(2023, 1, 5), end: DateTime(2023, 1, 10)),
      ];

      final conflicts = detector.run(
        tasks: tasks,
        taskGrouper: (task) {
          // Group t1 and t2 together, and also with the summary task
          if (task.id == 't1' || task.id == 't2' || task.id == 'summary1') {
            return 'groupA';
          }
          return null;
        },
      );

      // Expect 3 indicators: one for t1, one for t2, and one for the summary task
      expect(conflicts.length, 3);
      final summaryConflict = conflicts.firstWhere((c) => c.id.contains('summary1'));
      expect(summaryConflict.isOverlapIndicator, isTrue);
      expect(summaryConflict.rowId, 'summaryRow');
      expect(summaryConflict.start, DateTime(2023, 1, 5));
      expect(summaryConflict.end, DateTime(2023, 1, 7));
    });

    test('detects conflicts with segmented tasks', () {
      final tasks = [
        LegacyGanttTask(
          id: 't1-segmented',
          rowId: 'r1',
          start: DateTime(2023, 1, 1),
          end: DateTime(2023, 1, 10),
          segments: [
            LegacyGanttTaskSegment(start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 3)),
            LegacyGanttTaskSegment(start: DateTime(2023, 1, 8), end: DateTime(2023, 1, 10)),
          ],
        ),
        LegacyGanttTask(
          id: 't2',
          rowId: 'r1',
          start: DateTime(2023, 1, 2),
          end: DateTime(2023, 1, 9),
        ),
      ];

      final conflicts = detector.run(tasks: tasks, taskGrouper: (task) => task.rowId);

      // Should be 4 indicators: 2 for the first overlap, 2 for the second
      expect(conflicts.length, 4);

      // First overlap: t1[0] with t2 (2023-01-02 to 2023-01-03)
      final conflict1a = conflicts.firstWhere((c) => c.id.contains('t1-segmented') && c.start == DateTime(2023, 1, 2));
      expect(conflict1a.end, DateTime(2023, 1, 3));

      // Second overlap: t1[1] with t2 (2023-01-08 to 2023-01-09)
      final conflict2a = conflicts.firstWhere((c) => c.id.contains('t1-segmented') && c.start == DateTime(2023, 1, 8));
      expect(conflict2a.end, DateTime(2023, 1, 9));
    });
  });
}
