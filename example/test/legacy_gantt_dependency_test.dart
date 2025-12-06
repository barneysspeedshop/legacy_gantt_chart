import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';

void main() {
  group('LegacyGanttTaskDependency', () {
    test('constructor sets properties correctly with default values', () {
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 'taskA',
        successorTaskId: 'taskB',
      );

      expect(dependency.predecessorTaskId, 'taskA');
      expect(dependency.successorTaskId, 'taskB');
      expect(dependency.type, DependencyType.finishToStart);
      expect(dependency.lag, isNull);
    });

    test('constructor sets all properties correctly when provided', () {
      const lagDuration = Duration(days: 2);
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 'taskC',
        successorTaskId: 'taskD',
        type: DependencyType.contained,
        lag: lagDuration,
      );

      expect(dependency.predecessorTaskId, 'taskC');
      expect(dependency.successorTaskId, 'taskD');
      expect(dependency.type, DependencyType.contained);
      expect(dependency.lag, lagDuration);
    });

    test('should support equality', () {
      const dep1 = LegacyGanttTaskDependency(
        predecessorTaskId: '1',
        successorTaskId: '2',
      );
      const dep2 = LegacyGanttTaskDependency(
        predecessorTaskId: '1',
        successorTaskId: '2',
      );
      const dep3 = LegacyGanttTaskDependency(
        predecessorTaskId: '1',
        successorTaskId: '3',
      );
      const dep4 = LegacyGanttTaskDependency(
        predecessorTaskId: '1',
        successorTaskId: '2',
        type: DependencyType.finishToFinish,
      );

      expect(dep1, equals(dep2));
      expect(dep1.hashCode, equals(dep2.hashCode));
      expect(dep1, isNot(equals(dep3)));
      expect(dep1, isNot(equals(dep4)));
    });

    test('equality should account for all properties', () {
      // Lag
      const depNoLag = LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '2');
      const depWithLag =
          LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '2', lag: Duration(days: 1));

      expect(depNoLag, isNot(equals(depWithLag)));
    });

    test('DependencyType enum has correct values', () {
      expect(DependencyType.values, contains(DependencyType.finishToStart));
      expect(DependencyType.values, contains(DependencyType.startToStart));
      expect(DependencyType.values, contains(DependencyType.finishToFinish));
      expect(DependencyType.values, contains(DependencyType.startToFinish));
      expect(DependencyType.values, contains(DependencyType.contained));
    });
  });
}
