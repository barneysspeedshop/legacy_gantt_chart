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
  });
}
