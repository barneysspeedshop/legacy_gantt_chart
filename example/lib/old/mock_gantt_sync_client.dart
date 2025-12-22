import 'dart:async';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

/// A mock implementation of [GanttSyncClient] for demonstration purposes.
/// It simulates a "remote" server that echoes back operations after a delay,
/// and can also simulate other users making changes.
class MockGanttSyncClient implements GanttSyncClient {
  final _operationController = StreamController<Operation>.broadcast();

  @override
  Stream<Operation> get operationStream => _operationController.stream;

  @override
  Future<void> sendOperation(Operation operation) async {
    // For now, let's just log it.
    print('MockClient: Sent operation ${operation.type}');
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    for (final op in operations) {
      await sendOperation(op);
    }
  }

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));

  /// Simulates an incoming operation from another user.
  void simulateIncomingOperation(Operation op) {
    _operationController.add(op);
  }
}
