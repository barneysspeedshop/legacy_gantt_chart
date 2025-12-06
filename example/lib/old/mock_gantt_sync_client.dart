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
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 500));

    // In a real app, the server would broadcast this to other clients.
    // Here, we just echo it back to simulate "confirmation" or other clients seeing it
    // if we were running multiple instances.
    // However, for a single client demo, we might want to simulate *another* user
    // making a conflicting change or a random change.

    // For now, let's just log it.
    print('MockClient: Sent operation ${operation.type}');
  }

  @override
  Future<List<Operation>> getInitialState() async => [];

  /// Simulates an incoming operation from another user.
  void simulateIncomingOperation(Operation op) {
    _operationController.add(op);
  }
}
