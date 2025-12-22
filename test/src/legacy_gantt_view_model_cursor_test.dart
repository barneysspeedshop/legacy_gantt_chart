import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/sync/gantt_sync_client.dart';

class MockGanttSyncClient extends GanttSyncClient {
  final _controller = StreamController<Operation>.broadcast();
  final List<Operation> sentOperations = [];

  @override
  Stream<Operation> get operationStream => _controller.stream;

  @override
  Future<void> sendOperation(Operation operation) async {
    sentOperations.add(operation);
  }

  @override
  Future<List<Operation>> getInitialState() async => [];

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    for (final op in operations) {
      await sendOperation(op);
    }
  }

  void addOperation(Operation op) {
    _controller.add(op);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegacyGanttViewModel Cursor Sync', () {
    late LegacyGanttViewModel viewModel;
    late MockGanttSyncClient mockSyncClient;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');
    final task1 = LegacyGanttTask(
      id: 't1',
      rowId: 'r1',
      start: DateTime(2023, 1, 1, 8),
      end: DateTime(2023, 1, 1, 12),
      name: 'Task 1',
    );

    setUp(() {
      mockSyncClient = MockGanttSyncClient();
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        axisHeight: 50.0,
      );
      // Layout setup to ensure coordinate mapping works
      viewModel.updateLayout(1000, 500);
      // Grid: 0h to 10h. 1000px width. 100px/hour.
      final min = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      final max = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();
      viewModel.updateVisibleRange(min, max);

      // Verification of setup
      print('GridMin: ${viewModel.gridMin}'); // Should be 0h
      print('GridMax: ${viewModel.gridMax}'); // Should be 10h
      print('Width: 1000');
      print('Start Time (0h): ${DateTime(2023, 1, 1, 0)}');
      print('Scale(2h) = ${viewModel.totalScale(DateTime(2023, 1, 1, 2))}'); // Expected 200

      expect(viewModel.totalScale(DateTime(2023, 1, 1, 2)), closeTo(200, 0.1), reason: 'Scale layout incorrect');
    });

    test('sends CURSOR_MOVE on hover', () async {
      // Hover at 200px (2h -> 2:00) and 75px (Row 1 is 50-100)
      viewModel.onHover(const PointerHoverEvent(
        position: Offset(200, 75),
      ));

      // Wait for throttle (50ms)
      await Future.delayed(const Duration(milliseconds: 110));

      expect(mockSyncClient.sentOperations.isNotEmpty, isTrue);
      final op = mockSyncClient.sentOperations.last;

      expect(op.type, 'CURSOR_MOVE');
      expect(op.data['rowId'], 'r1');
      // 2h from start (0:00) is 2:00.
      final timeMs = op.data['time'] as int;
      final time = DateTime.fromMillisecondsSinceEpoch(timeMs);
      expect(time.hour, 2);
    });

    test('updates remoteCursors on incoming CURSOR_MOVE', () async {
      final op = Operation(
        type: 'CURSOR_MOVE',
        data: {
          'time': DateTime(2023, 1, 1, 3).millisecondsSinceEpoch,
          'rowId': 'r1',
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'remote_user_1',
      );

      mockSyncClient.addOperation(op);
      await Future.delayed(Duration.zero); // Wait for stream

      expect(viewModel.remoteCursors.containsKey('remote_user_1'), isTrue);
      final cursor = viewModel.remoteCursors['remote_user_1']!;
      expect(cursor.rowId, 'r1');
      expect(cursor.time.hour, 3);
      expect(cursor.userId, 'remote_user_1');
    });

    test('throttles cursor updates', () async {
      // Send multiple hovers quickly
      for (int i = 0; i < 5; i++) {
        viewModel.onHover(PointerHoverEvent(
          position: Offset(100.0 + i, 75),
        ));
      }

      // Wait for throttle
      await Future.delayed(const Duration(milliseconds: 110));

      // Should only have sent 1 operation (or very few, but definitely not 5 if throttled correctly)
      // Actually the throttle logic is:
      // if (isActive) return;
      // else timer = Timer(...)
      // So the FIRST one starts a timer, subsequent ones are ignored until timer fires.
      // So we expect exactly 1 operation for the first batch.

      expect(mockSyncClient.sentOperations.length, 1);
    });
  });
}
