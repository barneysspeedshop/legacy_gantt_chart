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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RemoteGhost &&
        other.userId == userId &&
        other.taskId == taskId &&
        other.start == start &&
        other.end == end &&
        other.lastUpdated == lastUpdated &&
        other.viewportStart == viewportStart &&
        other.viewportEnd == viewportEnd &&
        other.verticalScrollOffset == verticalScrollOffset &&
        other.userName == userName &&
        other.userColor == userColor;
  }

  @override
  int get hashCode =>
      userId.hashCode ^
      taskId.hashCode ^
      start.hashCode ^
      end.hashCode ^
      lastUpdated.hashCode ^
      viewportStart.hashCode ^
      viewportEnd.hashCode ^
      verticalScrollOffset.hashCode ^
      userName.hashCode ^
      userColor.hashCode;
}
