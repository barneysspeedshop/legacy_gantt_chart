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

  test('ViewModel correctly infers isSummary from ganttType=project in metadata', () async {
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

    const taskId = 'project-task-1';

    // IMPORTANT: We do NOT set isSummary here, or set it to false if possible in some contexts.
    // We rely on metadata 'ganttType'

    // To properly simulate the "metadata" field coming from ProtocolTask.fromJson,
    // we need to match how LegacyGanttTask deserializes.
    // However, Operation data is passed to `_processOperation` -> `_safeMergeTasks` -> `_crdtEngine.mergeTasks`.
    // The CRDT engine deals with `ProtocolTask`.
    // `Operation` structure for `INSERT_TASK` typically flattens fields.
    // Let's verify how `Operation` converts to `ProtocolTask` or how `_safeMergeTasks` consumes it.
    // _safeMergeTasks calls `_crdtEngine.mergeTasks`. `mergeTasks` takes `currentProtocolTasks` and `ops`.
    // It returns `List<ProtocolTask>`.
    // Then `LegacyGanttTask.fromProtocolTask(pt)` is called.
    // ProtocolTask preserves 'metadata'.
    // So if we send 'ganttType' in the operation's data, it needs to end up in `ProtocolTask.metadata`.
    // By convention, extra fields in Operation data often end up in metadata if CRDT handles them that way,
    // OR we should explicitly put them in a 'metadata' map in the operation if that's the protocol.
    // Looking at `LegacyGanttTask.toJson`, it merges metadata into the main map.
    // So 'ganttType' at the top level of the map should be treated as metadata by `ProtocolTask.fromJson` if it's not a standard field.
    // Let's verify `ProtocolTask.fromJson` behavior (not visible here but implied).
    // Assuming standard behavior: fields not in the named args go into metadata.

    final opWithFlattenedMetadata = Operation(
      type: 'INSERT_TASK',
      data: {
        'id': taskId,
        'name': 'Project Task',
        'start': DateTime.now().toIso8601String(),
        'end': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
        'ganttType': 'project', // This should flow into metadata
        'rowId': 'r1',
      },
      timestamp: Hlc.fromDate(DateTime.now(), 'server'),
      actorId: 'server',
    );

    mockSyncClient.emit(opWithFlattenedMetadata);

    await Future.delayed(Duration.zero);

    expect(viewModel.data.length, 1);
    final task = viewModel.data.first;
    expect(task.id, taskId);
    expect(task.isSummary, isTrue, reason: 'Task with ganttType="project" should have isSummary=true');
  });
}
