import 'dart:async'; // Added for StreamController
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

class MockGanttSyncClient implements GanttSyncClient {
  final StreamController<Operation> _controller = StreamController<Operation>.broadcast();

  @override
  Stream<Operation> get operationStream => _controller.stream;

  void emitOperation(Operation op) {
    _controller.add(op);
  }

  @override
  Future<void> sendOperation(Operation operation) async {}

  @override
  Future<void> sendOperations(List<Operation> operations) async {}

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(total: 0, processed: 0));
}

void main() {
  test('LegacyGanttViewModel handles bulk remote ghost updates', () async {
    final mockClient = MockGanttSyncClient();
    final viewModel = LegacyGanttViewModel(
      data: [],
      conflictIndicators: [],
      dependencies: [],
      visibleRows: [],
      rowMaxStackDepth: {},
      rowHeight: 50.0,
      syncClient: mockClient,
    );

    // Verify initial state
    expect(viewModel.remoteGhosts, isEmpty);

    // Simulate incoming bulk ghost update
    final payload = {
      'taskId': 't1',
      'start': 1000,
      'end': 2000,
      'ghosts': [
        // t1 is primary
        {'taskId': 't1', 'start': 1000, 'end': 2000},
        // t2 is secondary
        {'taskId': 't2', 'start': 1500, 'end': 2500},
      ]
    };

    final op = Operation(
      type: 'GHOST_UPDATE',
      data: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      actorId: 'user1',
    );

    mockClient.emitOperation(op);

    // Wait for stream to process
    await Future.delayed(Duration.zero);

    expect(viewModel.remoteGhosts.length, 1);
    final ghost = viewModel.remoteGhosts['user1']!;

    // Check primary fields (backward compatibility)
    expect(ghost.taskId, 't1');
    expect(ghost.start, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(ghost.end, DateTime.fromMillisecondsSinceEpoch(2000));

    // Check bulk tasks
    expect(ghost.tasks.length, 2);
    expect(ghost.tasks['t1']!.start, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(ghost.tasks['t2']!.start, DateTime.fromMillisecondsSinceEpoch(1500));
    expect(ghost.tasks['t2']!.end, DateTime.fromMillisecondsSinceEpoch(2500));
  });

  test('LegacyGanttViewModel handles backward-compatible remote ghost updates', () async {
    final mockClient = MockGanttSyncClient();
    final viewModel = LegacyGanttViewModel(
      data: [],
      conflictIndicators: [],
      dependencies: [],
      visibleRows: [],
      rowMaxStackDepth: {},
      rowHeight: 50.0,
      syncClient: mockClient,
    );

    final payload = {
      'taskId': 't3',
      'start': 3000,
      'end': 4000,
      // No 'ghosts' field
    };

    final op = Operation(
      type: 'GHOST_UPDATE',
      data: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      actorId: 'user2',
    );

    mockClient.emitOperation(op);
    await Future.delayed(Duration.zero);

    final ghost = viewModel.remoteGhosts['user2']!;
    expect(ghost.taskId, 't3');
    expect(ghost.tasks.length, 1);
    expect(ghost.tasks['t3']!.start, DateTime.fromMillisecondsSinceEpoch(3000));
  });
}
