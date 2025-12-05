import 'dart:async';

/// Represents a single operation in the CRDT system.
class Operation {
  final String type;
  final Map<String, dynamic> data;
  final int timestamp;
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
        'timestamp': timestamp,
        'actorId': actorId,
      };

  factory Operation.fromJson(Map<String, dynamic> json) => Operation(
        type: json['type'] as String,
        data: json['data'] as Map<String, dynamic>,
        timestamp: json['timestamp'] as int,
        actorId: json['actorId'] as String,
      );
}

/// Interface for the synchronization client.
/// Users must implement this to provide their own backend.
abstract class GanttSyncClient {
  /// Stream of incoming operations from the server/peers.
  Stream<Operation> get operationStream;

  /// Sends an operation to the server/peers.
  Future<void> sendOperation(Operation operation);

  /// Fetches the initial state or full state from the server.
  /// Returns a list of operations representing the history or current state.
  Future<List<Operation>> getInitialState();
}
