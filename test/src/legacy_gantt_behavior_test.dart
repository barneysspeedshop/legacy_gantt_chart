import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/sync/gantt_sync_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegacyGanttViewModel Advanced Behaviors', () {
    late LegacyGanttViewModel viewModel;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');
    const row2 = LegacyGanttRow(id: 'r2', label: 'Row 2');

    MockGanttSyncClient? mockSyncClient;

    setUp(() {
      mockSyncClient = MockGanttSyncClient();
    });

    test('Type 1: Locked Parent - Cannot drag auto-scheduled summary task', () {
      final task = LegacyGanttTask(
        id: 't1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        name: 'Summary',
        isSummary: true,
        isAutoScheduled: true,
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
      );

      // Simulate Pan Start on the task body
      // We use overrideTask/Part to simulate hit testing passing
      viewModel.onPanStart(
        DragStartDetails(globalPosition: Offset.zero),
        overrideTask: task,
        overridePart: TaskPart.body,
      );

      // Should be blocked
      expect(viewModel.draggedTask, isNull);
    });

    test('Type 1: Locked Parent - Can drag manual summary task', () {
      final task = LegacyGanttTask(
        id: 't1',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        name: 'Summary',
        isSummary: true,
        isAutoScheduled: false, // Manual
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
      );

      viewModel.onPanStart(
        DragStartDetails(globalPosition: Offset.zero),
        overrideTask: task,
        overridePart: TaskPart.body,
      );

      expect(viewModel.draggedTask, equals(task));
    });

    test('Type 2: Static Bucket - Does not propagate move to children', () {
      final parent = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        name: 'Parent',
        propagatesMoveToChildren: false, // Type 2
      );
      final child = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Child',
        parentId: 'parent',
        isAutoScheduled: true,
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [parent, child],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
        syncClient: mockSyncClient,
      );

      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Start Drag
      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(800, 0)), // 8h = 800px
        overrideTask: parent,
        overridePart: TaskPart.body,
      );

      // Move +100px (+1h)
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(900, 0),
        delta: const Offset(100, 0),
        primaryDelta: 100,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // Check Ops
      // Expect update for Parent
      expect(mockSyncClient!.sentOperations.any((op) => op.data['id'] == 'parent'), isTrue);
      // Expect NO update for Child
      expect(mockSyncClient!.sentOperations.any((op) => op.data['id'] == 'child'), isFalse);
    });

    test('Type 5: Elastic - Scales children', () {
      final parent = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12), // 4h duration
        name: 'Parent',
        isSummary: true,
        resizePolicy: ResizePolicy.elastic,
      );
      // Child starts at 9 (1h offset, 25%) and ends at 10 (2h offset, 50%)
      final child = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Child',
        parentId: 'parent',
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [parent, child],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableResize: true,
      );

      viewModel.updateLayout(1000, 500); // 100px/h
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Start Resize End
      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(1200, 0)), // 12h
        overrideTask: parent,
        overridePart: TaskPart.endHandle,
      );

      // Resize +400px (+4h). New Duration 8h (double).
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(1600, 0),
        delta: const Offset(400, 0),
        primaryDelta: 400,
      ));

      // Check Bulk Ghosts
      expect(viewModel.bulkGhostTasks, contains('child'));
      final (cStart, cEnd) = viewModel.bulkGhostTasks['child']!;

      // Expected: Child scaled relative to parent.
      // Parent 0-100% -> Child 25%-50%
      // New Parent: 8h-16h (8h duration).
      // Child Start: 8h + (0.25 * 8h) = 10h
      // Child End: 8h + (0.50 * 8h) = 12h
      // But wait...
      // Original Parent: 8:00 - 12:00.
      // Child: 9:00 (1h offset) - 10:00 (2h offset).
      // Ratios: 1/4 = 0.25, 2/4 = 0.5.

      // New Parent Start: 8:00 (unchanged, resize end).
      // New Parent End: 12:00 + 4h = 16:00. Duration 8h.

      // Child New Start = 8:00 + (0.25 * 8h) = 8:00 + 2h = 10:00.
      // Child New End = 8:00 + (0.5 * 8h) = 8:00 + 4h = 12:00.

      expect(cStart.hour, 10);
      expect(cEnd.hour, 12);
    });

    test('Type 4: Constrain - Clamps children', () {
      final parent = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12), // 4h duration
        name: 'Parent',
        isSummary: true,
        resizePolicy: ResizePolicy.constrain,
      );
      // Child at 9-10.
      final child = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Child',
        parentId: 'parent',
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [parent, child],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableResize: true,
      );

      viewModel.updateLayout(1000, 500); // 100px/h
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Resize Start (Shrink from left)
      // Pull start handle right by 200px (+2h). New Start 10:00.
      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(800, 0)),
        overrideTask: parent,
        overridePart: TaskPart.startHandle,
      );

      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(1000, 0),
        delta: const Offset(200, 0),
        primaryDelta: 200,
      ));

      // Parent New Start: 10:00.
      // Child Original: 9:00 - 10:00.
      // Child Start (9:00) is before Parent New Start (10:00).
      // Child should be clamped/pushed.
      // Child New Start = 10:00.
      // Child New End = 10:00 + 1h = 11:00 (Duration preserved? or clamped end?)
      // My implementation:
      // if (childNewStart.isBefore(newStart)) {
      //    final duration = childNewEnd.difference(childNewStart);
      //    childNewStart = newStart;
      //    childNewEnd = childNewStart.add(duration);
      // }
      // So yes, it preserves duration and pushes.

      // But wait!
      // My implementation also checks:
      // if (childNewEnd.isAfter(newEnd)) { ... }
      // New End is 12:00 (unchanged).
      // 11:00 is fine.

      expect(viewModel.bulkGhostTasks, contains('child'));
      final (cStart, cEnd) = viewModel.bulkGhostTasks['child']!;

      expect(cStart.hour, 10);
      expect(cEnd.hour, 11);
    });
  });
}

class MockGanttSyncClient extends GanttSyncClient {
  List<Operation> sentOperations = [];

  @override
  Future<void> sendOperation(Operation operation) async {
    sentOperations.add(operation);
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    sentOperations.addAll(operations);
  }

  @override
  Stream<Operation> get operationStream => const Stream.empty();
  void dispose() {}

  @override
  Stream<int> get outboundPendingCount => const Stream.empty();

  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();

  @override
  Future<List<Operation>> getInitialState() async => [];
}
