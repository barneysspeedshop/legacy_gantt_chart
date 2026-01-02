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

        // Simple Linear Waterfall Dependency (Previous -> Current)
        if (j > 0) {
          final prevJob = 'job-$i-${j - 1}';
          final prevEvent = 'event-$prevJob';

          mockDependencies.add({
            'id': 'dep-$prevEvent-$eventId',
            'predecessorId': prevEvent,
            'successorId': eventId,
            'type': 'FinishToStart',
          });
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
