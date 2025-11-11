import 'models.dart';

// --- Mock API Service ---
class MockApiService {
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    // Determine the date range for mock data generation
    DateTime startDate = DateTime.now();
    int rangeDays = 14;
    if (params?['startDateIso'] != null) {
      startDate = DateTime.parse(params!['startDateIso'] as String);
    }
    if (params?['endDateIso'] != null) {
      final endDate = DateTime.parse(params!['endDateIso'] as String);
      rangeDays = endDate.difference(startDate).inDays;
    }

    final int personCount = params?['personCount'] as int? ?? 10;
    final int jobCount = params?['jobCount'] as int? ?? 16;

    final List<GanttResourceData> mockResources = [];
    final List<Map<String, dynamic>> mockEvents = [];
    final List<Map<String, dynamic>> mockAssignments = [];
    final List<Map<String, dynamic>> mockResourceTimeRanges = [];

    for (int i = 0; i < personCount; i++) {
      final personId = 'person-$i';
      final List<GanttJobData> jobs = [];
      for (int j = 0; j < jobCount; j++) {
        final jobId = 'job-$i-$j';
        jobs.add(GanttJobData(
            id: jobId, name: 'Job $j', taskName: 'Task $j', status: 'Active', taskColor: '4CAF50', completion: 0.5));
        final eventStart = startDate.add(Duration(days: (i * jobCount + j) % rangeDays, hours: 9));
        final eventEnd = eventStart.add(const Duration(hours: 8));
        final eventId = 'event-$jobId';

        mockEvents.add({
          'id': eventId,
          'name': 'Task $i-$j',
          'utcStartDate': eventStart.toIso8601String(),
          'utcEndDate': eventEnd.toIso8601String(),
          'resourceId': 'event-$personId-summary',
          'referenceData': {'taskName': 'Active', 'taskColor': '8BC34A'},
        });
        mockAssignments.add({
          'id': 'assignment-$jobId',
          'event': eventId,
          'resource': jobId,
        });
      }

      mockResources.add(GanttResourceData(
        id: personId,
        name: 'Person $i',
        taskName: 'Person $i Summary',
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
      'resourceId': 'event-person-0-summary',
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
      'resourceTimeRangesData': mockResourceTimeRanges,
    };
  }
}
