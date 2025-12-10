class RemoteGhost {
  final String userId;
  final String taskId;
  final DateTime? start;
  final DateTime? end;
  final DateTime lastUpdated;
  final DateTime? viewportStart;
  final DateTime? viewportEnd;
  final double? verticalScrollOffset;
  final String? userName;
  final String? userColor; // Hex string

  RemoteGhost({
    required this.userId,
    this.taskId = '',
    required this.lastUpdated,
    this.start,
    this.end,
    this.viewportStart,
    this.viewportEnd,
    this.verticalScrollOffset,
    this.userName,
    this.userColor,
  });
}
