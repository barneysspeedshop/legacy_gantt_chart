import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_controller.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';

void main() {
  group('LegacyGanttController', () {
    test('initial state', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 7);
      final controller = LegacyGanttController(
        initialVisibleStartDate: start,
        initialVisibleEndDate: end,
      );

      expect(controller.visibleStartDate, start);
      expect(controller.visibleEndDate, end);
      expect(controller.tasks, isEmpty);
      expect(controller.holidays, isEmpty);
    });

    test('setVisibleRange updates state and notifies listeners', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 7);
      final controller = LegacyGanttController(
        initialVisibleStartDate: start,
        initialVisibleEndDate: end,
      );

      bool notified = false;
      controller.addListener(() => notified = true);

      final newStart = DateTime(2023, 1, 2);
      final newEnd = DateTime(2023, 1, 8);
      controller.setVisibleRange(newStart, newEnd);

      expect(controller.visibleStartDate, newStart);
      expect(controller.visibleEndDate, newEnd);
      expect(notified, isTrue);
    });

    test('next and prev move the range', () {
      final start = DateTime(2023, 1, 1);
      final end = DateTime(2023, 1, 8); // 7 days
      final controller = LegacyGanttController(
        initialVisibleStartDate: start,
        initialVisibleEndDate: end,
      );

      controller.next(duration: const Duration(days: 1));
      expect(controller.visibleStartDate, DateTime(2023, 1, 2));
      expect(controller.visibleEndDate, DateTime(2023, 1, 9));

      controller.prev(duration: const Duration(days: 1));
      expect(controller.visibleStartDate, start);
      expect(controller.visibleEndDate, end);
    });

    test('manual data setters', () {
      final controller = LegacyGanttController(
        initialVisibleStartDate: DateTime(2023, 1, 1),
        initialVisibleEndDate: DateTime(2023, 1, 7),
      );

      final task =
          LegacyGanttTask(id: '1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 2), name: 'T1');
      controller.setTasks([task]);
      expect(controller.tasks, [task]);
      bool notified = false;
      controller.addListener(() => notified = true);
      controller.setTasks([task]);
      expect(notified, isTrue);
    });

    test('async tasks loading', () async {
      final task = LegacyGanttTask(
          id: '1', rowId: 'r1', start: DateTime(2023, 1, 1), end: DateTime(2023, 1, 2), name: 'Async Task');

      final controller = LegacyGanttController(
        initialVisibleStartDate: DateTime(2023, 1, 1),
        initialVisibleEndDate: DateTime(2023, 1, 7),
        tasksAsync: (start, end) async {
          await Future.delayed(const Duration(milliseconds: 10));
          return [task];
        },
      );

      // Initial load happens in constructor constructor but it's async, so we might need to wait
      // Actually constructor calls the async method without awaiting, but we can await the result if we expose a Future or just wait here.
      // However, to test `setVisibleRange` triggering load:

      expect(controller.isLoading, isTrue); // Should be loading initially due to constructor call
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.isLoading, isFalse);
      expect(controller.tasks, [task]);

      // Change range
      bool notified = false;
      controller.addListener(() => notified = true);

      controller.setVisibleRange(DateTime(2023, 2, 1), DateTime(2023, 2, 7));
      expect(controller.isLoading, isTrue);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.isLoading, isFalse);
      expect(notified, isTrue);
    });

    test('error handling in async fetch', () async {
      final controller = LegacyGanttController(
        initialVisibleStartDate: DateTime(2023, 1, 1),
        initialVisibleEndDate: DateTime(2023, 1, 7),
        tasksAsync: (start, end) async {
          throw Exception('Network error');
        },
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(controller.isLoading, isFalse);
      expect(controller.tasks, isEmpty); // Should fall back to empty list
    });
  });
}
