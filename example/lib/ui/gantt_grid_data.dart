import '../data/models.dart';

// GanttGridData for the left-hand side grid
class GanttGridData {
  final String id;
  final String name;
  final bool isParent;
  final String? taskName;
  final double? completion;
  final List<GanttGridData> children;
  bool isExpanded; // State for expansion

  GanttGridData({
    required this.id,
    required this.name,
    required this.isParent,
    this.taskName,
    this.completion,
    this.children = const [],
    this.isExpanded = false,
  });

  factory GanttGridData.fromJob(GanttJobData job) => GanttGridData(
        id: job.id,
        name: job.name,
        isParent: false,
        taskName: job.taskName ?? job.name,
        completion: job.completion,
      );

  GanttGridData copyWith({
    String? id,
    String? name,
    bool? isParent,
    String? taskName,
    double? completion,
    List<GanttGridData>? children,
    bool? isExpanded,
  }) =>
      GanttGridData(
        id: id ?? this.id,
        name: name ?? this.name,
        isParent: isParent ?? this.isParent,
        children: children ?? this.children,
        isExpanded: isExpanded ?? this.isExpanded,
      );
}
