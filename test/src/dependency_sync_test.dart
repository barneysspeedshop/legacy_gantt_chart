import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';

import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart'; // Added import
import 'package:legacy_gantt_chart/src/sync/gantt_sync_client.dart';

class MockGanttSyncClient extends GanttSyncClient {
  final _controller = StreamController<Operation>.broadcast();
  final List<Operation> sentOperations = [];

  @override
  Stream<Operation> get operationStream => _controller.stream;

  @override
  Future<void> sendOperation(Operation operation) async {
    sentOperations.add(operation);
    _controller.add(operation);
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

  void addOperation(Operation op) {
    _controller.add(op);
  }
}

void main() {
  group('LegacyGanttViewModel Dependency Sync', () {
    late LegacyGanttViewModel viewModel;
    late MockGanttSyncClient mockSyncClient;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');

    setUp(() {
      mockSyncClient = MockGanttSyncClient();
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
      );
    });

    test('receives INSERT_DEPENDENCY operation', () async {
      final op = Operation(
        type: 'INSERT_DEPENDENCY',
        data: {
          'predecessorTaskId': 't1',
          'successorTaskId': 't2',
          'type': 'finishToStart',
        },
        timestamp: 100,
        actorId: 'remote',
      );

      mockSyncClient.addOperation(op);
      await Future.delayed(Duration.zero);

      expect(viewModel.dependencies.length, 1);
      final dep = viewModel.dependencies.first;
      expect(dep.predecessorTaskId, 't1');
      expect(dep.successorTaskId, 't2');
      expect(dep.type, DependencyType.finishToStart);
    });

    test('receives DELETE_DEPENDENCY operation', () async {
      // Add initial dependency
      const dep = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');
      viewModel.addDependency(dep);
      // Clear sent ops to start fresh
      mockSyncClient.sentOperations.clear();

      final op = Operation(
        type: 'DELETE_DEPENDENCY',
        data: {
          'predecessorTaskId': 't1',
          'successorTaskId': 't2',
        },
        timestamp: 101,
        actorId: 'remote',
      );

      mockSyncClient.addOperation(op);
      await Future.delayed(Duration.zero);

      expect(viewModel.dependencies, isEmpty);
    });

    test('addDependency sends INSERT_DEPENDENCY operation', () {
      const dep = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');
      viewModel.addDependency(dep);

      expect(mockSyncClient.sentOperations.length, 1);
      final op = mockSyncClient.sentOperations.first;
      expect(op.type, 'INSERT_DEPENDENCY');
      expect(op.data['predecessorTaskId'], 't1');
      expect(op.data['successorTaskId'], 't2');
      expect(op.data['type'], 'finishToStart');
    });

    test('removeDependency sends DELETE_DEPENDENCY operation', () {
      const dep = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');
      viewModel.addDependency(dep);
      mockSyncClient.sentOperations.clear();

      viewModel.removeDependency(dep);

      expect(viewModel.dependencies, isEmpty);
      expect(mockSyncClient.sentOperations.length, 1);
      final op = mockSyncClient.sentOperations.first;
      expect(op.type, 'DELETE_DEPENDENCY');
      expect(op.data['predecessorTaskId'], 't1');
      expect(op.data['successorTaskId'], 't2');
    });

    // Test disabled: updateDependencies no longer sends operations to prevent feedback loops.
    // See LegacyGanttViewModel.updateDependencies implementation.
    /*
    test('updateDependencies diffs and sends operations', () {
      const dep1 = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');
      const dep2 = LegacyGanttTaskDependency(predecessorTaskId: 't3', successorTaskId: 't4');

      // Add dep1 initially
      viewModel.addDependency(dep1);
      mockSyncClient.sentOperations.clear();

      // Update to [dep2] (remove dep1, add dep2)
      viewModel.updateDependencies([dep2]);

      expect(viewModel.dependencies.length, 1);
      expect(viewModel.dependencies.first, dep2);

      // Should have sent DELETE for dep1 and INSERT for dep2
      expect(mockSyncClient.sentOperations.length, 2);

      final deleteOp = mockSyncClient.sentOperations.firstWhere((o) => o.type == 'DELETE_DEPENDENCY');
      expect(deleteOp.data['predecessorTaskId'], 't1');

      final insertOp = mockSyncClient.sentOperations.firstWhere((o) => o.type == 'INSERT_DEPENDENCY');
      expect(insertOp.data['predecessorTaskId'], 't3');
    });
    */

    test('Incoming sync does NOT cause echo in updateDependencies', () async {
      const dep = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');

      // 1. Receive incoming op
      final op = Operation(
        type: 'INSERT_DEPENDENCY',
        data: {
          'predecessorTaskId': 't1',
          'successorTaskId': 't2',
          'type': 'finishToStart',
        },
        timestamp: 100,
        actorId: 'remote',
      );
      mockSyncClient.addOperation(op);
      await Future.delayed(Duration.zero);
      expect(viewModel.dependencies, [dep]);

      // 2. updateDependencies called with same list (simulating Parent update)
      viewModel.updateDependencies([dep]);

      // 3. Should NOT send operation
      expect(mockSyncClient.sentOperations, isEmpty);
    });

    test('clearDependenciesForTask sends CLEAR_DEPENDENCIES operation', () {
      const dep1 = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');
      const dep2 = LegacyGanttTaskDependency(predecessorTaskId: 't3', successorTaskId: 't1');
      viewModel.dependencies.addAll([dep1, dep2]);
      mockSyncClient.sentOperations.clear();

      final task = LegacyGanttTask(id: 't1', rowId: 'r1', start: DateTime.now(), end: DateTime.now());
      viewModel.clearDependenciesForTask(task);

      expect(viewModel.dependencies, isEmpty);
      expect(mockSyncClient.sentOperations.length, 1);
      final op = mockSyncClient.sentOperations.first;
      expect(op.type, 'CLEAR_DEPENDENCIES');
      expect(op.data['taskId'], task.id);
    });

    test('ViewModel handles RESET_DATA operation', () async {
      // Add some initial data
      const dep = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
      );
      viewModel.addDependency(dep); // Use addDependency with LegacyGanttTaskDependency object
      expect(viewModel.dependencies.length, 1);

      // Simulate incoming RESET_DATA
      final resetOp = Operation(
        type: 'RESET_DATA',
        data: {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'remote-user',
      );

      mockSyncClient.addOperation(resetOp);
      await Future.delayed(Duration.zero); // Allow stream to process

      // Verify that dependencies are cleared
      expect(viewModel.dependencies, isEmpty);
    });

    test('receives CLEAR_DEPENDENCIES operation', () async {
      const dep1 = LegacyGanttTaskDependency(predecessorTaskId: 't1', successorTaskId: 't2');
      const dep2 = LegacyGanttTaskDependency(predecessorTaskId: 't3', successorTaskId: 't4');
      viewModel.dependencies.addAll([dep1, dep2]);

      final op = Operation(
        type: 'CLEAR_DEPENDENCIES',
        data: {'taskId': 't1'},
        timestamp: 100,
        actorId: 'remote',
      );

      mockSyncClient.addOperation(op);
      await Future.delayed(Duration.zero);

      // t1 dependencies should be gone, t3->t4 should remain
      expect(viewModel.dependencies.length, 1);
      expect(viewModel.dependencies.first, dep2);
    });
  });
}
