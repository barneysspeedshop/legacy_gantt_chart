import 'dart:async';

import 'package:flutter/foundation.dart';
import 'sync_stats.dart';
export 'sync_stats.dart';

import 'hlc.dart';

/// Represents a single operation in the CRDT system.
class Operation {
  final String type;
  final Map<String, dynamic> data;
  final Hlc timestamp;
  final String actorId;

  Operation({
    required this.type,
    required this.data,
    required this.timestamp,
    required this.actorId,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'data': data,
        'timestamp': timestamp.toString(),
        'actorId': actorId,
      };

  factory Operation.fromJson(Map<String, dynamic> json) {
    Hlc parsedTimestamp;
    final rawTimestamp = json['timestamp'];
    if (rawTimestamp is String) {
      parsedTimestamp = Hlc.parse(rawTimestamp);
    } else if (rawTimestamp is int) {
      parsedTimestamp = Hlc(millis: rawTimestamp, counter: 0, nodeId: 'legacy');
    } else {
      parsedTimestamp = Hlc.zero;
    }

    return Operation(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>,
      timestamp: parsedTimestamp,
      actorId: json['actorId'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Operation &&
        other.type == type &&
        mapEquals(other.data, data) &&
        other.timestamp == timestamp &&
        other.actorId == actorId;
  }

  @override
  int get hashCode {
    int dataHash = 0;
    data.forEach((key, value) {
      dataHash ^= key.hashCode ^ value.hashCode;
    });

    return type.hashCode ^ dataHash ^ timestamp.hashCode ^ actorId.hashCode;
  }
}

/// Interface for the synchronization client.
/// Users must implement this to provide their own backend.
abstract class GanttSyncClient {
  /// Stream of incoming operations from the server/peers.
  Stream<Operation> get operationStream;

  /// Sends an operation to the server/peers.
  Future<void> sendOperation(Operation operation);

  /// Sends multiple operations to the server/peers efficiently.
  Future<void> sendOperations(List<Operation> operations);

  /// Fetches the initial state or full state from the server.
  /// Returns a list of operations representing the history or current state.
  Future<List<Operation>> getInitialState();

  /// Stream of pending outbound operations count (e.g. offline queue size).
  Stream<int> get outboundPendingCount;

  /// Stream of inbound sync progress.
  /// Stream of inbound sync progress.
  Stream<SyncProgress> get inboundProgress;

  /// returns the current local Merkle Root hash.
  Future<String> getMerkleRoot();

  /// Initiates a Merkle-tree based synchronization with a remote peer/server.
  Future<void> syncWithMerkle({required String remoteRoot, required int depth});

  /// Returns the current Hybrid Logical Clock timestamp.
  /// Implementations should return the latest known HLC, creating one if necessary.
  Hlc get currentHlc;
}
