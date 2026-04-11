import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  group('LegacyGanttTaskDependency', () {
    test('should initialize correctly with defaults', () {
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
      );

      expect(dependency.predecessorTaskId, 't1');
      expect(dependency.successorTaskId, 't2');
      expect(dependency.type, DependencyType.finishToStart);
      expect(dependency.lag, isNull);
    });

    test('should initialize correctly with all parameters', () {
      const duration = Duration(days: 2);
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
        type: DependencyType.startToStart,
        lag: duration,
      );

      expect(dependency.predecessorTaskId, 't1');
      expect(dependency.successorTaskId, 't2');
      expect(dependency.type, DependencyType.startToStart);
      expect(dependency.lag, duration);
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
      // Checking enum again: finishToFinish
      const depFinishToFinish = LegacyGanttTaskDependency(
        predecessorTaskId: '1',
        successorTaskId: '2',
        type: DependencyType.finishToFinish,
      );

      expect(dep1, equals(dep2));
      expect(dep1.hashCode, equals(dep2.hashCode));
      expect(dep1, isNot(equals(dep3)));
      expect(dep1, isNot(equals(dep4)));
      expect(dep1, isNot(equals(depFinishToFinish)));
    });

    test('equality should account for all properties', () {
      const depNoLag = LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '2');
      const depWithLag =
          LegacyGanttTaskDependency(predecessorTaskId: '1', successorTaskId: '2', lag: Duration(days: 1));
      const depWithLastUpdated = LegacyGanttTaskDependency(
          predecessorTaskId: '1', successorTaskId: '2', lastUpdated: Hlc(millis: 12345, counter: 0, nodeId: 'test'));

      expect(depNoLag, isNot(equals(depWithLag)));
      expect(depNoLag, isNot(equals(depWithLastUpdated)));
      expect(depWithLastUpdated.hashCode, isNot(equals(depNoLag.hashCode)));
    });

    test('DependencyType enum has correct values', () {
      expect(DependencyType.values, contains(DependencyType.finishToStart));
      expect(DependencyType.values, contains(DependencyType.startToStart));
      expect(DependencyType.values, contains(DependencyType.finishToFinish));
      expect(DependencyType.values, contains(DependencyType.startToFinish));
      expect(DependencyType.values, contains(DependencyType.contained));
    });

    test('maps to and from protocol dependency correctly for all types', () {
      for (final type in DependencyType.values) {
        final dependency = LegacyGanttTaskDependency(
          predecessorTaskId: 'p-$type',
          successorTaskId: 's-$type',
          type: type,
          lag: const Duration(hours: 1),
          lastUpdated: const Hlc(millis: 999, counter: 0, nodeId: 'test'),
        );

        final protocolDep = dependency.toProtocolDependency();
        expect(protocolDep.predecessorTaskId, dependency.predecessorTaskId);
        expect(protocolDep.successorTaskId, dependency.successorTaskId);
        expect(protocolDep.lag, dependency.lag);
        expect(protocolDep.lastUpdated, dependency.lastUpdated);

        final backAgain = LegacyGanttTaskDependency.fromProtocolDependency(protocolDep);
        expect(backAgain, equals(dependency));
      }
    });

    test('contentHash delegate to protocol dependency', () {
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
      );
      final protocolDep = dependency.toProtocolDependency();
      expect(dependency.contentHash, equals(protocolDep.contentHash));
    });
  });
}
