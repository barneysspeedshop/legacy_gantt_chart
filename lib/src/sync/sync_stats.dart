class SyncProgress {
  final int processed;
  final int total;

  const SyncProgress({required this.processed, required this.total});

  double get percentage => total == 0 ? 1.0 : processed / total;

  @override
  String toString() => '$processed / $total';
}
