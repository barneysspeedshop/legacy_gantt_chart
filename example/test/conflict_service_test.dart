import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:example/services/gantt_schedule_service.dart';
import 'package:example/data/models.dart';

void main() {
  test('GanttScheduleService detects conflicts on summary tasks when children are hidden', () {
    final service = GanttScheduleService();
    final now = DateTime.now();
    final start = now;
    final end = now.add(const Duration(hours: 2));

    // 1. Setup Data
    // Parent Resource
    final parentResource = GanttResourceData(
      id: 'parent1',
      name: 'Parent',
      children: [
        GanttJobData(id: 'child1', name: 'Child 1'),
        GanttJobData(id: 'child2', name: 'Child 2'),
      ],
    );

    // Events causing conflict
    // Both children have tasks at the same time
    final event1 = GanttEventData(
      id: 'event1',
      utcStartDate: start.toIso8601String(),
      utcEndDate: end.toIso8601String(),
      resourceId: 'parent1', // Linked to parent for grouping
    );
    final event2 = GanttEventData(
      id: 'event2',
      utcStartDate: start.toIso8601String(),
      utcEndDate: end.toIso8601String(),
      resourceId: 'parent1',
    );

    // Assignments
    final assignment1 = GanttAssignmentData(id: 'a1', event: 'event1', resource: 'child1');
    final assignment2 = GanttAssignmentData(id: 'a2', event: 'event2', resource: 'child2');

    final apiResponse = GanttResponse(
      success: true,
      resourcesData: [parentResource],
      eventsData: [event1, event2],
      assignmentsData: [assignment1, assignment2],
      resourceTimeRangesData: [],
    );

    // 2. Create Tasks manually (simulating what fetchAndProcessSchedule does before stacking)
    final task1 = LegacyGanttTask(
      id: 'a1',
      rowId: 'child1',
      start: start,
      end: end,
      originalId: 'event1',
    );
    final task2 = LegacyGanttTask(
      id: 'a2',
      rowId: 'child2',
      start: start,
      end: end,
      originalId: 'event2',
    );
    final summaryTask = LegacyGanttTask(
      id: 'summary-parent1',
      rowId: 'parent1',
      start: start,
      end: end,
      isSummary: true,
    );

    final tasks = [task1, task2, summaryTask];

    // 3. Test with visibleRowIds containing ONLY the parent (collapsed state)
    final visibleRowIds = {'parent1'};

    final (stackedTasks, maxDepth, conflictIndicators) = service.publicCalculateTaskStacking(
      tasks,
      apiResponse,
      showConflicts: true,
      visibleRowIds: visibleRowIds,
    );

    // 4. Assertions
    // We expect a conflict indicator on the parent summary task
    // The indicator ID format is 'overlap-parent-{summaryTaskId}-{index}'
    final hasSummaryConflict = conflictIndicators.any((t) => t.rowId == 'parent1' && t.isOverlapIndicator);

    expect(hasSummaryConflict, isTrue, reason: 'Should have conflict indicator on summary task');
  });
}
