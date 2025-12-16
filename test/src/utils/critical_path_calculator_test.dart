import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('CriticalPathCalculator', () {
    final calculator = CriticalPathCalculator();

    test('Single task is critical', () {
      final task = LegacyGanttTask(
        id: '1',
        name: 'Task 1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5),
        rowId: 'r1',
      );

      final result = calculator.calculate(tasks: [task], dependencies: []);

      expect(result.criticalTaskIds, contains('1'));
      expect(result.criticalDependencies, isEmpty);
    });

    test('Two sequential tasks, both critical', () {
      final t1 = LegacyGanttTask(
        id: '1',
        name: 'Task 1',
        start: DateTime(2023, 1, 1),
        end: DateTime(2023, 1, 5), // 4 days (96 hours) - But duration calc uses difference
        rowId: 'r1',
      );
      final t2 = LegacyGanttTask(
        id: '2',
        name: 'Task 2',
        start: DateTime(2023, 1, 5),
        end: DateTime(2023, 1, 10),
        rowId: 'r1',
      );

      const dep = LegacyGanttTaskDependency(
        predecessorTaskId: '1',
        successorTaskId: '2',
        type: DependencyType.finishToStart,
      );

      final result = calculator.calculate(tasks: [t1, t2], dependencies: [dep]);

      expect(result.criticalTaskIds, containsAll(['1', '2']));
      expect(result.criticalDependencies, contains(dep));
    });

    test('Parallel paths, one critical', () {
      // T1 -> T2 (Long) -> T4
      // T1 -> T3 (Short) -> T4

      final t1 =
          LegacyGanttTask(id: '1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 2), rowId: 'r1', name: 'Start');

      final t2 = LegacyGanttTask(
          id: '2', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 10), rowId: 'r1', name: 'Long Path');

      final t3 = LegacyGanttTask(
          id: '3', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 5), rowId: 'r2', name: 'Short Path');

      final t4 =
          LegacyGanttTask(id: '4', start: DateTime(2023, 1, 10), end: DateTime(2023, 1, 12), rowId: 'r1', name: 'End');

      final deps = [
        const LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '2'),
        const LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '3'),
        const LegacyGanttTaskDependency(predecessorTaskId: '2', successorTaskId: '4'),
        const LegacyGanttTaskDependency(predecessorTaskId: '3', successorTaskId: '4'),
      ];

      final result = calculator.calculate(tasks: [t1, t2, t3, t4], dependencies: deps);

      expect(result.criticalTaskIds, containsAll(['1', '2', '4']));
      expect(result.criticalTaskIds, isNot(contains('3'))); // Short path not critical
    });

    test('Cycle detection handles gracefully', () {
      final t1 =
          LegacyGanttTask(id: '1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 2), rowId: 'r1', name: '1');
      final t2 =
          LegacyGanttTask(id: '2', start: DateTime(2023, 1, 2), end: DateTime(2023, 1, 3), rowId: 'r1', name: '2');

      final deps = [
        const LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '2'),
        const LegacyGanttTaskDependency(predecessorTaskId: '2', successorTaskId: '1'), // Cycle
      ];

      // Should not throw / crash
      final result = calculator.calculate(tasks: [t1, t2], dependencies: deps);

      // In case of cycle, behavior is undefined but should be safe.
      // Current impl might warn and return partial results or empty sets.
      // Just ensure it completes.
      expect(result, isNotNull);
    });

    test('Calculates project end date correctly', () {
      final t1 = LegacyGanttTask(
        id: '1',
        name: 'Task 1',
        start: DateTime(2023, 1, 1, 9, 0),
        end: DateTime(2023, 1, 1, 17, 0), // 8 hours
        rowId: 'r1',
      );

      final result = calculator.calculate(tasks: [t1], dependencies: []);

      // Project end date should match task end date for single task
      expect(result.projectEndDate, t1.end);
    });
  });
}
