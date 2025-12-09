class RemoteGhost {
  final String userId;
  final String taskId;
  final DateTime start;
  final DateTime end;
  final DateTime lastUpdated;

  RemoteGhost({
    required this.userId,
    required this.taskId,
    required this.start,
    required this.end,
    required this.lastUpdated,
  });
}
