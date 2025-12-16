// --- Mock Data Models (Simplified from flutter_flex5 examples) ---

class GanttResponse {
  final bool success;
  final String? error;
  final List<GanttResourceData> resourcesData;
  final List<GanttEventData> eventsData;
  final List<GanttAssignmentData> assignmentsData;
  final List<GanttResourceTimeRangeData> resourceTimeRangesData;

  GanttResponse({
    required this.success,
    this.error,
    required this.resourcesData,
    required this.eventsData,
    required this.assignmentsData,
    required this.resourceTimeRangesData,
  });

  static GanttResponse fromJson(Map<String, dynamic> json) => GanttResponse(
        success: json['success'] as bool,
        error: json['error'] as String?,
        resourcesData: (json['resourcesData'] as List<dynamic>?)
                ?.map((e) => GanttResourceData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        eventsData: (json['eventsData'] as List<dynamic>?)
                ?.map((e) => GanttEventData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        assignmentsData: (json['assignmentsData'] as List<dynamic>?)
                ?.map((e) => GanttAssignmentData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        resourceTimeRangesData: (json['resourceTimeRangesData'] as List<dynamic>?)
                ?.map((e) => GanttResourceTimeRangeData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
        'resourcesData': resourcesData.map((e) => e.toJson()).toList(),
        'eventsData': eventsData.map((e) => e.toJson()).toList(),
        'assignmentsData': assignmentsData.map((e) => e.toJson()).toList(),
        'resourceTimeRangesData': resourceTimeRangesData.map((e) => e.toJson()).toList(),
      };
}

class GanttResourceData {
  final String id;
  final String name;
  final String? taskName;
  final List<GanttJobData> children; // Jobs under this resource

  GanttResourceData({
    required this.id,
    required this.name,
    this.taskName,
    this.children = const [],
  });

  static GanttResourceData fromJson(Map<String, dynamic> json) => GanttResourceData(
        id: json['id'] as String,
        name: json['name'] as String,
        taskName: json['taskName'] as String?,
        children: (json['children'] as List<dynamic>?)
                ?.map((e) => GanttJobData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'taskName': taskName,
        'children': children.map((j) => j.toJson()).toList(),
      };
}

class GanttJobData {
  final String id;
  final String name;
  final String? status;
  final String? taskColor; // Hex string without #
  final String? taskName; // E.g., 'Pilot', 'Co-Pilot'
  final double? completion;

  GanttJobData({
    required this.id,
    required this.name,
    this.status,
    this.taskColor,
    this.taskName,
    this.completion,
  });

  static GanttJobData fromJson(Map<String, dynamic> json) => GanttJobData(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String?,
        taskColor: json['taskColor'] as String?,
        taskName: json['taskName'] as String?,
        completion: (json['completion'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'taskColor': taskColor,
        'taskName': taskName,
        'completion': completion,
      };

  GanttJobData copyWith({
    String? id,
    String? name,
    String? status,
    String? taskColor,
    String? taskName,
    double? completion,
  }) =>
      GanttJobData(
        id: id ?? this.id,
        name: name ?? this.name,
        status: status ?? this.status,
        taskColor: taskColor ?? this.taskColor,
        taskName: taskName ?? this.taskName,
        completion: completion ?? this.completion,
      );
}

class GanttEventData {
  final String id;
  final String? name;
  final String? utcStartDate;
  final String? utcEndDate;
  final GanttReferenceData? referenceData;
  final String? resourceId; // Used to link a child event to its parent summary event

  GanttEventData({
    required this.id,
    this.name,
    this.utcStartDate,
    this.utcEndDate,
    this.referenceData,
    this.resourceId,
  });

  static GanttEventData fromJson(Map<String, dynamic> json) => GanttEventData(
        id: json['id'] as String,
        name: json['name'] as String?,
        utcStartDate: json['utcStartDate'] as String?,
        utcEndDate: json['utcEndDate'] as String?,
        referenceData: json['referenceData'] != null
            ? GanttReferenceData.fromJson(json['referenceData'] as Map<String, dynamic>)
            : null,
        resourceId: json['resourceId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'utcStartDate': utcStartDate,
        'utcEndDate': utcEndDate,
        'referenceData': referenceData?.toJson(),
        'resourceId': resourceId,
      };
}

class GanttReferenceData {
  final String? taskName;
  final String? taskColor; // Hex string without #
  final String? taskIcon; // URL or identifier for an icon
  final String? taskTextColor; // Added: Text color for the status option

  GanttReferenceData({
    this.taskName,
    this.taskColor,
    this.taskIcon,
    this.taskTextColor, // Added to constructor
  });

  static GanttReferenceData fromJson(Map<String, dynamic> json) => GanttReferenceData(
        taskName: json['taskName'] as String?,
        taskColor: json['taskColor'] as String?,
        taskIcon: json['taskIcon'] as String?,
        taskTextColor: json['taskTextColor'] as String?, // Added fromJson
      );

  Map<String, dynamic> toJson() => {
        'taskName': taskName,
        'taskColor': taskColor,
        'taskIcon': taskIcon,
        'taskTextColor': taskTextColor,
      };
}

class GanttAssignmentData {
  final String id;
  final String event; // Event ID
  final String resource; // Resource (person or job) ID

  GanttAssignmentData({
    required this.id,
    required this.event,
    required this.resource,
  });

  static GanttAssignmentData fromJson(Map<String, dynamic> json) => GanttAssignmentData(
        id: json['id'] as String,
        event: json['event'] as String,
        resource: json['resource'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'event': event,
        'resource': resource,
      };
}

class GanttResourceTimeRangeData {
  final String id;
  final String resourceId;
  final String utcStartDate;
  final String utcEndDate;

  GanttResourceTimeRangeData({
    required this.id,
    required this.resourceId,
    required this.utcStartDate,
    required this.utcEndDate,
  });

  static GanttResourceTimeRangeData fromJson(Map<String, dynamic> json) => GanttResourceTimeRangeData(
        id: json['id'] as String,
        resourceId: json['resourceId'] as String,
        utcStartDate: json['utcStartDate'] as String,
        utcEndDate: json['utcEndDate'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'resourceId': resourceId,
        'utcStartDate': utcStartDate,
        'utcEndDate': utcEndDate,
      };
}
