import 'models.dart';

// --- Mock API Service ---
class MockApiService {
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    // Determine the date range for mock data generation
    DateTime startDate = DateTime.now();
    if (params?['startDateIso'] != null) {
      startDate = DateTime.parse(params!['startDateIso'] as String);
    }
    if (params?['endDateIso'] != null) {
      DateTime.parse(params!['endDateIso'] as String);
    }

    final int personCount = params?['personCount'] as int? ?? 10;
    final int jobCount = params?['jobCount'] as int? ?? 16;

    final List<GanttResourceData> mockResources = [];
    final List<Map<String, dynamic>> mockEvents = [];
    final List<Map<String, dynamic>> mockAssignments = [];
    final List<Map<String, dynamic>> mockDependencies = [];
    final List<Map<String, dynamic>> mockResourceTimeRanges = [];

    for (int i = 0; i < personCount; i++) {
      final personId = 'person-$i';
      final List<GanttJobData> jobs = [];
      for (int j = 0; j < jobCount; j++) {
        final jobId = 'job-$i-$j';
        jobs.add(GanttJobData(
            id: jobId, name: 'Job $j', taskName: 'Task $j', status: 'Active', taskColor: '4CAF50', completion: 0.5));
        // Even tasks (Critical Path candidates) take 8 hours. Odd tasks (Offshoots) take 2 hours.
        final durationHours = (j % 2 == 0) ? 8 : 2;

        // Base start time based on the "Step" (j/2)
        DateTime eventStart = startDate.add(Duration(days: i * jobCount + (j ~/ 2), hours: 9));

        // If Odd (Offshoot), shift it to start AFTER the Even task (which takes 8 hours)
        // Even: 09:00 - 17:00. Odd: 17:00 - 19:00.
        if (j % 2 != 0) {
          eventStart = eventStart.add(const Duration(hours: 8));
        }

        final eventEnd = eventStart.add(Duration(hours: durationHours));
        final eventId = 'event-$jobId';

        mockEvents.add({
          'id': eventId,
          'name': 'Task $i-$j',
          'utcStartDate': eventStart.toIso8601String(),
          'utcEndDate': eventEnd.toIso8601String(),
          'resourceId': 'summary-task-$personId',
          'parentId': 'summary-task-$personId',
          'referenceData': {'taskName': 'Active', 'taskColor': '8BC34A'},
        });
        mockAssignments.add({
          'id': 'assignment-$jobId',
          'event': eventId,
          'resource': jobId,
        });

        // Create branching execution:
        // Main path: Task 0 -> Task 2 -> Task 4 (Sequential 8h tasks)
        // Side path: Task 1 (starts after Task 0, must finish before Task 2 starts? No, that would make it blocking)
        // Better:
        // A (Task 0, 8h) -> Depends on nothing
        // B (Task 1, 2h) -> Depends on A
        // C (Task 2, 8h) -> Depends on B AND A? No.

        // Let's do:
        // Task 0 (8h) -> Task 2 (8h) -> Task 4 (8h) ...
        // Task 1 (2h) -> Starts after Task 0, must finish before Task 2.
        //   Dep: 0 -> 1. Dep 1 -> 2.
        //   Path 0->2 is 8+8=16 (if 0 finishes, 2 starts).
        //   Path 0->1->2 is 8+2+?
        //   If 0->2 is FinishToStart, then 2 starts when 0 finishes.
        //   If 1 depends on 0 (FinishToStart), 1 starts when 0 finishes.
        //   If 2 depends on 1 (FinishToStart), 2 cannot start until 1 finishes.
        //   This makes 0->1->2 the critical path if (0->2) is not explicitly constrained or is looser.

        // Correct Slack Structure:
        // A (Task 0) splits into B (Task 1, short) and C (Task 2, long).
        // Both merge into D (Task 3).

        // Revised Loop Logic:
        // Groups of 3:
        // J=0 (Start node, 8h)
        // J=1 (Short branch, 2h) depends on J=0
        // J=2 (Long branch, 8h) depends on J=0
        // J=3 (Merge node, 8h) depends on J=1 AND J=2.

        // Critical path is 0->2->3. Slack is on 1.

        // Simple Linear Waterfall Dependency (Previous -> Current) by default
        if (j > 0) {
          // Default chain
          final prevEvent = 'event-job-$i-${j - 1}';
          mockDependencies.add({
            'id': 'dep-$prevEvent-$eventId',
            'predecessorId': prevEvent,
            'successorId': eventId,
            'type': 'FinishToStart',
          });

          // Inject artificial slack for every 4th task
          // Make Task j (where j%4 == 2) a "long parallel" to Task j-1?

          // Let's try the Diamond Pattern explicitly for the first few tasks of each person
          if (j == 2 && jobCount >= 4) {
            // Task 2 is "Long Branch" (8h). Task 1 is "Short Branch" (2h).
            // Both usually depend on Task 0.
            // Currently loop says 1 depends on 0. 2 depends on 1.
            // We want 1 depends on 0. 2 depends on 0. 3 depends on 1 AND 2.

            // Remove 1->2 dependency (it was added in prev iteration? No, current iteration adds prev->curr)
            // In j=2 iteration, default adds 1->2. We want 0->2 instead.

            mockDependencies.removeLast(); // Remove 1->2

            final prevEvent0 = 'event-job-$i-0'; // Task 0
            mockDependencies.add({
              'id': 'dep-$prevEvent0-$eventId',
              'predecessorId': prevEvent0,
              'successorId': eventId,
              'type': 'FinishToStart',
            });
          }

          if (j == 3 && jobCount >= 4) {
            // Task 3 is Merge Node.
            // Default adds 2->3.
            // We also want 1->3.
            // Task 1 was the short one (2h). Task 2 was long (8h).
            // Both start after 0.
            // So 3 waits for both.

            final prevEvent1 = 'event-job-$i-1'; // Task 1
            mockDependencies.add({
              'id': 'dep-$prevEvent1-$eventId',
              'predecessorId': prevEvent1,
              'successorId': eventId,
              'type': 'FinishToStart',
            });
          }
        }
      }

      mockResources.add(GanttResourceData(
        id: personId,
        name: 'Person $i',
        taskName: 'Project A for Person $i',
        children: jobs,
      ));
    }

    // Add one more task
    const extraJobId = 'job-extra';
    mockResources.first.children.add(GanttJobData(
        id: extraJobId,
        name: 'Extra Job',
        taskName: 'Extra Task',
        status: 'Active',
        taskColor: '4CAF50',
        completion: 0.5));

    final eventStart = startDate.add(const Duration(days: 1, hours: 9));
    final eventEnd = eventStart.add(const Duration(hours: 8));
    const eventId = 'event-$extraJobId';

    mockEvents.add({
      'id': eventId,
      'name': 'Extra Task',
      'utcStartDate': eventStart.toIso8601String(),
      'utcEndDate': eventEnd.toIso8601String(),
      'resourceId': 'summary-task-person-0',
      'parentId': 'summary-task-person-0',
      'referenceData': {'taskName': 'Active', 'taskColor': '8BC34A'},
    });
    mockAssignments.add({
      'id': 'assignment-$extraJobId',
      'event': eventId,
      'resource': extraJobId,
    });

    return {
      'success': true,
      'resourcesData': mockResources.map((r) => r.toJson()).toList(),
      'eventsData': mockEvents,
      'assignmentsData': mockAssignments,
      'dependenciesData': mockDependencies,
      'resourceTimeRangesData': mockResourceTimeRanges,
    };
  }
}
