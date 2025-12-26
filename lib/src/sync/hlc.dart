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
      Hlc(millis: dateTime.millisecondsSinceEpoch, counter: 0, nodeId: nodeId);

  /// Creates an HLC from a legacy int timestamp.
  factory Hlc.fromIntTimestamp(int timestamp) => Hlc(millis: timestamp, counter: 0, nodeId: 'legacy');

  /// Parses an HLC string in the format:
  /// `2023-10-27T10:00:00.123Z-0000-nodeId`
  factory Hlc.parse(String hlc) {
    if (RegExp(r'^\d+$').hasMatch(hlc)) {
      return Hlc.fromIntTimestamp(int.parse(hlc));
    }

    final parts = hlc.split('-');
    if (parts.length < 3) {
      throw FormatException('Invalid HLC format: $hlc');
    }

    final lastDashIndex = hlc.lastIndexOf('-');
    if (lastDashIndex == -1) throw FormatException('Invalid HLC format: $hlc');

    final secondLastDashIndex = hlc.lastIndexOf('-', lastDashIndex - 1);
    if (secondLastDashIndex == -1) throw FormatException('Invalid HLC format: $hlc');

    final isoTimestamp = hlc.substring(0, secondLastDashIndex);
    final counterString = hlc.substring(secondLastDashIndex + 1, lastDashIndex);
    final nodeId = hlc.substring(lastDashIndex + 1);

    final dateTime = DateTime.parse(isoTimestamp);
    final millis = dateTime.millisecondsSinceEpoch;

    final counter = int.parse(counterString, radix: 16);

    return Hlc(millis: millis, counter: counter, nodeId: nodeId);
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
