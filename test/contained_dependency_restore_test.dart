import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:mocktail/mocktail.dart';

class MockGanttSyncClient extends Mock implements GanttSyncClient {
  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'server-sync');

  final StreamController<Operation> _opController = StreamController<Operation>.broadcast();

  @override
  Stream<Operation> get operationStream => _opController.stream;

  void emit(Operation op) {
    _opController.add(op);
  }

  @override
  Future<void> sendOperation(Operation operation) async {}

  @override
  Future<void> sendOperations(List<Operation> operations) async {}

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {}

  Future<void> connect({String? since}) async {}

  Future<void> disconnect() async {}

  bool get isConnected => true;

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Future<String> getMerkleRoot() async => '';

  @override
  String get actorId => 'mock-client';

  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  Future<void> dispose() async {
    _opController.close();
  }
}

void main() {
  test('ViewModel restores contained dependencies and tasks from BATCH_UPDATE correctly', () async {
    final mockSyncClient = MockGanttSyncClient();
    final viewModel = LegacyGanttViewModel(
      syncClient: mockSyncClient,
      data: [],
      conflictIndicators: [],
      dependencies: [],
      visibleRows: [],
      rowMaxStackDepth: {},
      rowHeight: 32,
    );

    // Initial state: empty
    expect(viewModel.data, isEmpty); // use public getter .data for tasks
    expect(viewModel.dependencies, isEmpty);

    const taskId1 = 'summary-1';
    const taskId2 = 'child-1';

    // Simulate BATCH_UPDATE from server
    // Note: We use toIso8601String() for dates as protocol expects strings in JSON maps usually
    // But Operation.data is Map<String, dynamic>.
    // ProtocolTask.fromJson expects specific fields.
    final batchOp = Operation(
      type: 'BATCH_UPDATE',
      data: {
        'operations': [
          // Insert Task 1 (Summary)
          Operation(
            type: 'INSERT_TASK',
            data: {
              'id': taskId1,
              'name': 'Summary Task',
              'start': DateTime.now().toIso8601String(),
              'end': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
              'isSummary': true,
              'rowId': 'r1',
            },
            timestamp: Hlc.fromDate(DateTime.now(), 'server'),
            actorId: 'server',
          ).toJson(),
          // Insert Task 2 (Child)
          Operation(
            type: 'INSERT_TASK',
            data: {
              'id': taskId2,
              'name': 'Child Task',
              'start': DateTime.now().toIso8601String(),
              'end': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
              'rowId': 'r1',
            },
            timestamp: Hlc.fromDate(DateTime.now(), 'server'),
            actorId: 'server',
          ).toJson(),
          // Insert Contained Dependency
          Operation(
            type: 'INSERT_DEPENDENCY',
            data: {'predecessorTaskId': taskId1, 'successorTaskId': taskId2, 'type': 'contained'},
            timestamp: Hlc.fromDate(DateTime.now(), 'server'),
            actorId: 'server',
          ).toJson(),
        ],
      },
      timestamp: Hlc.fromDate(DateTime.now(), 'server'),
      actorId: 'server',
    );

    // Act: Emit the operation
    mockSyncClient.emit(batchOp);

    // Await strictly a microtask or small delay for the stream listener to fire and process
    await Future.delayed(Duration.zero);

    // Assert
    expect(viewModel.data.length, 2, reason: 'Should have 2 tasks restored');
    expect(viewModel.data.any((t) => t.id == taskId1 && t.isSummary), isTrue, reason: 'Summary task should exist');
    expect(viewModel.dependencies.length, 1, reason: 'Should have 1 dependency');

    final dep = viewModel.dependencies.first;
    expect(dep.predecessorTaskId, taskId1);
    expect(dep.successorTaskId, taskId2);
    expect(dep.type, DependencyType.contained);
  });
}
