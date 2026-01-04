import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../example/lib/view_models/gantt_view_model.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

class FakeGanttSyncClient implements GanttSyncClient {
  @override
  Stream<Operation> get operationStream => const Stream.empty();

  @override
  Future<void> sendOperation(Operation operation) async {}

  @override
  Future<void> sendOperations(List<Operation> operations) async {}

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();

  @override
  Hlc get currentHlc => Hlc.zero;

  @override
  Future<String> getMerkleRoot() async => '';

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {}

  @override
  String get actorId => 'test-actor';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GanttViewModel Initial Sync 0-Duration Reproduction', () {
    late GanttViewModel viewModel;
    late FakeGanttSyncClient fakeSyncClient;

    setUp(() {
      fakeSyncClient = FakeGanttSyncClient();
      viewModel = GanttViewModel(useLocalDatabase: false);
      viewModel.setSyncClient(fakeSyncClient);
    });

    test('Initial Sync should correctly parse underscored keys and numeric strings', () async {
      final now = DateTime.now();
      final startMillis = now.millisecondsSinceEpoch;
      final endMillis = now.add(const Duration(days: 2)).millisecondsSinceEpoch;

      final batchOp = Operation(
        type: 'BATCH_UPDATE',
        data: {
          'operations': [
            {
              'type': 'INSERT_RESOURCE',
              'data': {
                'id': 'row-1',
                'name': 'Resource 1',
              },
              'timestamp': Hlc.fromDate(DateTime.now(), 'server').toString(),
              'actorId': 'server',
            },
            {
              'type': 'INSERT_TASK',
              'data': {
                'data': {
                  'id': 'task-1',
                  'name': 'Test Task',
                  'start_date': startMillis.toString(),
                  'end_date': endMillis.toString(),
                  'rowId': 'row-1',
                }
              },
              'timestamp': Hlc.fromDate(DateTime.now(), 'server').toString(),
              'actorId': 'server',
            }
          ]
        },
        timestamp: Hlc.fromDate(DateTime.now(), 'server'),
        actorId: 'server',
      );

      await viewModel.handleIncomingOperationForTesting(batchOp);

      expect(viewModel.allGanttTasks.any((t) => t.id == 'task-1'), isTrue);
      final task = viewModel.allGanttTasks.firstWhere((t) => t.id == 'task-1');
      expect(task.id, 'task-1');

      final duration = task.end.difference(task.start);
      expect(duration.inDays, 2);
    });

    test('Initial Sync with null dates should default to 1 day, not 0', () async {
      final batchOp = Operation(
        type: 'BATCH_UPDATE',
        data: {
          'operations': [
            {
              'type': 'INSERT_RESOURCE',
              'data': {
                'id': 'row-2',
                'name': 'Resource 2',
              },
              'timestamp': Hlc.fromDate(DateTime.now(), 'server').toString(),
              'actorId': 'server',
            },
            {
              'type': 'INSERT_TASK',
              'data': {
                'data': {
                  'id': 'task-2',
                  'name': 'Null Dates Task',
                  'rowId': 'row-2',
                }
              },
              'timestamp': Hlc.fromDate(DateTime.now(), 'server').toString(),
              'actorId': 'server',
            }
          ]
        },
        timestamp: Hlc.fromDate(DateTime.now(), 'server'),
        actorId: 'server',
      );

      await viewModel.handleIncomingOperationForTesting(batchOp);

      expect(viewModel.allGanttTasks.any((t) => t.id == 'task-2'), isTrue);
      final task = viewModel.allGanttTasks.firstWhere((t) => t.id == 'task-2');
      final duration = task.end.difference(task.start);
      expect(duration.inDays, 1);
    });

    test('Regression: Should handle double-nested data envelope', () async {
      final batchOp = Operation(
        type: 'BATCH_UPDATE',
        data: {
          'operations': [
            {
              'type': 'INSERT_RESOURCE',
              'data': {
                'id': 'row-double',
                'name': 'Resource Double',
              },
              'timestamp': Hlc.fromDate(DateTime.now(), 'server').toString(),
              'actorId': 'server',
            },
            {
              'type': 'INSERT_TASK',
              'data': {
                'data': {
                  'id': 'task-double',
                  'name': 'Double Nested',
                  'start': DateTime.now().toIso8601String(),
                  'end': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
                  'rowId': 'row-double',
                }
              },
              'timestamp': Hlc.fromDate(DateTime.now(), 'server').toString(),
              'actorId': 'server',
            }
          ]
        },
        timestamp: Hlc.fromDate(DateTime.now(), 'server'),
        actorId: 'server',
      );

      await viewModel.handleIncomingOperationForTesting(batchOp);

      expect(viewModel.allGanttTasks.any((t) => t.id == 'task-double'), isTrue);
      final task = viewModel.allGanttTasks.firstWhere((t) => t.id == 'task-double');
      expect(task.name, 'Double Nested');
    });
  });
}
