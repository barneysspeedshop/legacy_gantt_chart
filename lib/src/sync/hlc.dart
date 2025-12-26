import 'dart:math';

/// A Hybrid Logical Clock implementation.
///
/// Combines physical time with a logical counter to provide a unique, monotonically
/// increasing timestamp for distributed systems.
class Hlc implements Comparable<Hlc> {
  final int millis;
  final int counter;
  final String nodeId;

  const Hlc({
    required this.millis,
    required this.counter,
    required this.nodeId,
  });

  /// Creates a generic HLC for initialization (e.g. time 0).
  static const zero = Hlc(millis: 0, counter: 0, nodeId: 'node');

  /// Creates an HLC from a DateTime and nodeId.
  factory Hlc.fromDate(DateTime dateTime, String nodeId) =>
      Hlc(millis: dateTime.toUtc().millisecondsSinceEpoch, counter: 0, nodeId: nodeId);

  /// Creates an HLC from a legacy int timestamp.
  factory Hlc.fromIntTimestamp(int timestamp) => Hlc(millis: timestamp, counter: 0, nodeId: 'legacy');

  /// Parses an HLC string in the format:
  /// `2023-10-27T10:00:00.123Z-0000-nodeId`
  factory Hlc.parse(String hlc) {
    if (RegExp(r'^\d+$').hasMatch(hlc)) {
      return Hlc.fromIntTimestamp(int.parse(hlc));
    }

    // Try standard format: ISO-Counter(hex)-NodeId
    // Counter is typically 4 hex digits.
    // Use non-greedy match for ISO part to ensure we pick up the distinct separators
    final standardRegex = RegExp(r'^(.+)-([0-9a-fA-F]{4})-(.+)$');
    var match = standardRegex.firstMatch(hlc);

    if (match != null) {
      final isoTimestamp = match.group(1)!;
      final counterString = match.group(2)!;
      final nodeId = match.group(3)!;

      // Ensure UTC parsing by appending Z if missing
      final normalizedIso = isoTimestamp.endsWith('Z') ? isoTimestamp : '${isoTimestamp}Z';
      final dateTime = DateTime.parse(normalizedIso);
      return Hlc(millis: dateTime.millisecondsSinceEpoch, counter: int.parse(counterString, radix: 16), nodeId: nodeId);
    }

    // Try format without NodeId: ISO-Counter(hex)
    final noNodeRegex = RegExp(r'^(.+)-([0-9a-fA-F]{4})$');
    match = noNodeRegex.firstMatch(hlc);

    if (match != null) {
      final isoTimestamp = match.group(1)!;
      final counterString = match.group(2)!;
      try {
        final normalizedIso = isoTimestamp.endsWith('Z') ? isoTimestamp : '${isoTimestamp}Z';
        final dateTime = DateTime.parse(normalizedIso);
        return Hlc(
            millis: dateTime.millisecondsSinceEpoch, counter: int.parse(counterString, radix: 16), nodeId: 'unknown');
      } catch (_) {
        // Validation for date parse failure
      }
    }

    // Fallback: Try parsing as pure ISO timestamp
    try {
      final normalizedIso = hlc.endsWith('Z') ? hlc : '${hlc}Z';
      final dateTime = DateTime.parse(normalizedIso);
      return Hlc(millis: dateTime.millisecondsSinceEpoch, counter: 0, nodeId: 'unknown');
    } catch (_) {
      // Ignore
    }

    throw FormatException('Invalid HLC format: $hlc');
  }

  /// Generates the next HLC for a local event with the given wall time.
  Hlc send(int wallTimeMillis) {
    final newMillis = max(millis, wallTimeMillis);

    final newCounter = (newMillis == millis) ? counter + 1 : 0;

    return Hlc(millis: newMillis, counter: newCounter, nodeId: nodeId);
  }

  /// Merges a remote HLC to update the local clock.
  Hlc receive(Hlc remote, int wallTimeMillis) {
    final newMillis = max(max(millis, remote.millis), wallTimeMillis);

    int newCounter;
    if (newMillis == millis && newMillis == remote.millis) {
      newCounter = max(counter, remote.counter) + 1;
    } else if (newMillis == millis) {
      newCounter = counter + 1;
    } else if (newMillis == remote.millis) {
      newCounter = remote.counter + 1;
    } else {
      newCounter = 0;
    }

    return Hlc(millis: newMillis, counter: newCounter, nodeId: nodeId);
  }

  @override
  int compareTo(Hlc other) {
    final millisComp = millis.compareTo(other.millis);
    if (millisComp != 0) return millisComp;

    final counterComp = counter.compareTo(other.counter);
    if (counterComp != 0) return counterComp;

    return nodeId.compareTo(other.nodeId);
  }

  @override
  String toString() {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    final iso = dateTime.toIso8601String();

    final counterHex = counter.toRadixString(16).padLeft(4, '0').toUpperCase();

    return '$iso-$counterHex-$nodeId';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          runtimeType == other.runtimeType &&
          millis == other.millis &&
          counter == other.counter &&
          nodeId == other.nodeId;

  @override
  int get hashCode => millis.hashCode ^ counter.hashCode ^ nodeId.hashCode;

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;
}
