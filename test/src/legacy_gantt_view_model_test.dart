import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_dependency.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:collection/collection.dart';

import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LegacyGanttViewModel', () {
    late LegacyGanttViewModel viewModel;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');
    const row2 = LegacyGanttRow(id: 'r2', label: 'Row 2');
    final task1 = LegacyGanttTask(
      id: 't1',
      rowId: 'r1',
      start: DateTime(2023, 1, 1, 8),
      end: DateTime(2023, 1, 1, 12),
      name: 'Task 1',
    );

    setUp(() {
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
        enableResize: true,
      );
    });

    test('initial state and layout calculation', () {
      viewModel.updateLayout(1000, 500);

      expect(viewModel.rowHeight, 50.0);
      // Row offsets are calculated:
      // Row 1: 0.0
      // Row 2: 50.0 (since depth is 1)
      expect(viewModel.getRowVerticalOffset(0), 0.0);
      expect(viewModel.getRowVerticalOffset(1), 50.0);
      expect(viewModel.getRowVerticalOffset(2), 100.0); // Total height
    });

    test('coordinate conversion', () {
      // Set a fixed range: 1000px width for 10 hours
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();
      viewModel.updateLayout(1000, 500);

      // t1 starts at 8:00, which is 80% of the way through 0:00-10:00 range
      // So expected X is 800.
      final xStart = viewModel.totalScale(task1.start);
      expect(xStart, closeTo(800, 1.0));

      final xEnd = viewModel.totalScale(task1.end); // 12:00 is outside, 1200px
      expect(xEnd, closeTo(1200, 1.0));
    });

    test('selection logic', () {
      bool notified = false;
      viewModel.addListener(() => notified = true);

      viewModel.setFocusedTask('t1');
      expect(viewModel.focusedTaskId, 't1');
      expect(notified, isTrue);

      // Select same should not notify
      notified = false;
      viewModel.setFocusedTask('t1');
      expect(notified, isFalse);
    });

    test('drag start - move', () {
      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Task t1 is at (800, 0) aprox, height roughly 35 (0.7 ratio)
      // Let's hit the center of the task
      // We need to fake the hit test or ensure helper methods return values.
      // Since `_getTaskPartAtPosition` is private and uses internal logic relying on rendering,
      // unit testing gesture interactions that depend on hit testing is hard without exposing internals or using integration tests.
      // However, we can use `onPanStart` with overrideTask to simulate programmatic drag start which is testable.

      viewModel.onPanStart(DragStartDetails(globalPosition: Offset.zero), overrideTask: task1);
      expect(viewModel.draggedTask, task1);
      // Default override drag mode is move
      // We can't easily check private _dragMode without reflection or if it was exposed.
      // But `notifyListeners` should have fired.
    });

    test('updateVisibleRows', () {
      final newRows = [row2]; // Just row 2
      viewModel.updateVisibleRows(newRows);
      expect(viewModel.visibleRows, newRows);
      // Check if offsets recalculated
      // Row 2 is now index 0
      expect(viewModel.getRowVerticalOffset(0), 0.0);
      expect(viewModel.getRowVerticalOffset(0), 0.0);
    });

    test('updateVisibleRows to empty prevents RangeError on interaction', () {
      // Regression test: when visibleRows becomes empty, if offsets aren't recalculated,
      // _findRowIndex might return a valid index (mapping to old rows) which is then used
      // to access visibleRows, causing RangeError.

      // 1. Initial state has rows (set in setUp)
      expect(viewModel.visibleRows, isNotEmpty);

      // 2. Clear rows
      viewModel.updateVisibleRows([]);
      expect(viewModel.visibleRows, isEmpty);

      // 3. Simulate tap. Should NOT throw RangeError.
      // 50px down would have been Row 1 or 2 previously.
      try {
        viewModel.onTapDown(TapDownDetails(
          kind: PointerDeviceKind.touch,
          globalPosition: const Offset(100, 25),
          localPosition: const Offset(100, 25),
        ));
        viewModel.onTap();
      } catch (e) {
        fail('Should not throw exception after clearing rows: $e');
      }
    });

    test('hover logic', () {
      // We can at least call onHover and check callbacks if mocked.
      // But again, hit testing is hard.
      // We can verify that onHoverExit clears state.
      viewModel.onHoverExit(const PointerExitEvent());
      expect(viewModel.cursor, SystemMouseCursors.basic);
    });

    test('sync client integration - receives updates', () async {
      final mockSyncClient = MockGanttSyncClient();
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
      );

      final op = Operation(
        type: 'UPDATE_TASK',
        data: {
          'id': 't1',
          'rowId': 'r1',
          'start': DateTime(2023, 1, 2).toIso8601String(),
          'end': DateTime(2023, 1, 3).toIso8601String(),
        },
        timestamp: Hlc.fromIntTimestamp(100),
        actorId: 'remote',
      );

      mockSyncClient.addOperation(op);
      await Future.delayed(Duration.zero); // Wait for stream listener

      // Task should be updated
      expect(viewModel.data.first.start, DateTime(2023, 1, 2));
    });

    test('sync client integration - sends operation on drag end', () {
      final mockSyncClient = MockGanttSyncClient();
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        enableDragAndDrop: true, // IMPORTANT
      );

      // Simulate drag end
      // We need dragging state setup first.
      // We can use the public `onPanStart` with override to setup state.
      viewModel.onPanStart(DragStartDetails(globalPosition: Offset.zero), overrideTask: task1);

      // We need to set ghostStart/End which happens in onHorizontalPanUpdate usually.
      // But those are private.
      // However, onHorizontalPanUpdate calls _handleHorizontalPan which updates them based on delta.
      // That's hard to trigger precisely without rendering.

      // BUT, we can inspect if `onHorizontalPanEnd` guards against null ghost tasks.
      // It does: `if (_draggedTask != null && _ghostTaskStart != null && _ghostTaskEnd != null)`

      // So we can't easily test the "send" part without being able to set ghost variables or simulating a full drag sequence that results in valid ghost variables.
      // Given constraints, I'll skip the "send" verification unless I can mock the ghost variables or use reflection, or trigger a real enough drag.

      // Let's try to trigger a real enough drag.
      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 2).millisecondsSinceEpoch.toDouble();

      viewModel.onPanStart(DragStartDetails(globalPosition: Offset.zero), overrideTask: task1);
      // Drag by 100 pixels
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(100, 0),
        delta: const Offset(100, 0),
        primaryDelta: 100,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // We expect an operation in mockSyncClient
      // Wait, did the drag actually update ghost vars?
      // _handleHorizontalPan logic:
      // double deltaX = details.delta.dx;
      // ... updates ghostTaskStart/End

      // So it should work!
      expect(mockSyncClient.sentOperations, isNotEmpty);
      expect(mockSyncClient.sentOperations.any((op) => op.type == 'UPDATE_TASK'), isTrue);
    });
  });

  group('LegacyGanttViewModel Interaction', () {
    late LegacyGanttViewModel viewModel;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Row 1');
    const row2 = LegacyGanttRow(id: 'r2', label: 'Row 2');
    final task1 = LegacyGanttTask(
      id: 't1',
      rowId: 'r1',
      start: DateTime(2023, 1, 1, 8),
      end: DateTime(2023, 1, 1, 12),
      name: 'Task 1',
    );

    setUp(() {
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
        enableResize: true,
      );
      // Setup layout: 1000x500. Axis gets 10% = 50px.
      // Grid: 0h to 10h. 1000px width. 100px/hour.
      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();
      // Force domain re-calc
      // gridMin/Max setter calls _calculateDomains but updateLayout might override or need both.
      // Calling updateVisibleRange to be sure logic runs.
      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble());
    });

    test('onTap hitting a task', () {
      LegacyGanttTask? tappedTask;
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        onPressTask: (t) => tappedTask = t,
      );
      viewModel.updateLayout(1000, 500);
      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble());

      // Task 1 is at 8:00 (800px) to 12:00 (1200px).
      // Row 1 is at y=50 (axis) to y=100.
      // Tap at (810, 75).
      viewModel.onTapDown(TapDownDetails(
        kind: PointerDeviceKind.touch,
        globalPosition: const Offset(810, 75),
        localPosition: const Offset(810, 75),
      ));
      viewModel.onTap();

      expect(tappedTask, equals(task1));
    });

    test('onTap hitting empty space', () {
      String? clickedRowId;
      DateTime? clickedTime;
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        onEmptySpaceClick: (rid, time) {
          clickedRowId = rid;
          clickedTime = time;
        },
      );
      viewModel.updateLayout(1000, 500);
      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble());

      // Tap at (100, 75). 100px = 1 hour -> 1:00.
      viewModel.onTapDown(TapDownDetails(
        kind: PointerDeviceKind.touch,
        globalPosition: const Offset(100, 75),
        localPosition: const Offset(100, 75),
      ));
      viewModel.onTap();

      expect(clickedRowId, 'r1');
      expect(clickedTime, isNotNull);
      // 100px / 1000px * 10h = 1h. Start 0:00. So 1:00.
      expect(clickedTime?.hour, 1);
    });

    test('onHover changes cursor over task', () {
      // Task 1 body at (810, 75).
      viewModel.onHover(const PointerHoverEvent(position: Offset(810, 75)));
      expect(viewModel.cursor, SystemMouseCursors.move);
    });

    test('onHover changes cursor over empty space', () {
      // Empty space at (100, 75).
      // Needs onEmptySpaceClick to be set for cursor change
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        onEmptySpaceClick: (_, __) {},
      );
      viewModel.updateLayout(1000, 500);
      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble());

      viewModel.onHover(const PointerHoverEvent(position: Offset(100, 75)));
      expect(viewModel.cursor, SystemMouseCursors.click);
      expect(viewModel.hoveredRowId, 'r1');
    });

    test('Drag logic - Horizontal Move', () {
      // 1. Hover/Start to detect pan type
      // Re-trigger layout with distinct width to force recalc
      viewModel.updateLayout(2000, 500);

      // Force gridMin/Max update to ensure domains are correct
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble() - 1; // Force change
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble(); // Restore

      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      print('Drag Debug Setup: Min X (0h) ${viewModel.totalScale(DateTime(2023, 1, 1, 0))}');
      print('Drag Debug Setup: Max X (10h) ${viewModel.totalScale(DateTime(2023, 1, 1, 10))}');
      print('Drag Debug Setup: Axis Height ${viewModel.timeAxisHeight}');
      print('Drag Debug Setup: Row 0 Top ${viewModel.getRowVerticalOffset(0)}');
      print('Drag Debug Setup: Row 0 Bottom ${viewModel.getRowVerticalOffset(1)}');
      print('Drag Debug Setup: Data Count ${viewModel.data.length}');
      print('Drag Debug Setup: Row 0 ID ${viewModel.visibleRows[0].id}');

      // Debug Scale
      print('Drag Debug Setup: Start X (8h) ${viewModel.totalScale(task1.start)}');

      // We simulate Pan Start.
      // Width 2000. Duration 10h. Scale 200px/h.
      // Task Start 8h from min. -> 1600px.
      // Hit at 1610.
      viewModel
          .onPanStart(DragStartDetails(globalPosition: const Offset(1610, 75), localPosition: const Offset(1610, 75)));

      // At this point, pan hasn't locked, so task is NOT set yet.
      expect(viewModel.draggedTask, isNull);

      // 2. Update Pan (Move right 10px to trigger lock)
      // This calls onPanUpdate which contains the hit test heuristic
      viewModel.onPanUpdate(DragUpdateDetails(
          globalPosition: const Offset(1620, 75),
          delta: const Offset(10, 0),
          primaryDelta: 10,
          localPosition: const Offset(1620, 75)));

      // NOW it should have detected horizontal pan and task
      expect(viewModel.draggedTask, equals(task1));

      // 3. Continue Update Pan (Move right another 190px -> Total +200px = +1 hour)
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
          globalPosition: const Offset(1810, 75),
          delta: const Offset(190, 0),
          primaryDelta: 190,
          localPosition: const Offset(1810, 75)));

      expect(viewModel.ghostTaskStart, isNotNull);
      // Original 8:00. +1h = 9:00.
      // 200px / 200px/h = 1h.
      expect(viewModel.ghostTaskStart!.hour, 9);
      expect(viewModel.showResizeTooltip, isTrue);

      // 4. End Pan
      bool updated = false;
      viewModel = LegacyGanttViewModel(
          conflictIndicators: [],
          data: [task1],
          dependencies: [],
          visibleRows: [row1],
          rowMaxStackDepth: {'r1': 1},
          rowHeight: 50.0,
          enableDragAndDrop: true,
          onTaskUpdate: (t, s, e) {
            updated = true;
            expect(t, task1);
            expect(s.hour, 9);
          });
      // Re-setup state for the new VM instance to test callback
      viewModel.updateLayout(2000, 500);

      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble());

      // Fast replay of state
      viewModel
          .onPanStart(DragStartDetails(globalPosition: const Offset(1610, 75), localPosition: const Offset(1610, 75)));

      // Trigger update/lock
      viewModel.onPanUpdate(DragUpdateDetails(
          globalPosition: const Offset(1620, 75),
          delta: const Offset(10, 0),
          primaryDelta: 10,
          localPosition: const Offset(1620, 75)));

      // Drag rest
      viewModel.onHorizontalPanUpdate(
          DragUpdateDetails(globalPosition: const Offset(1810, 75), delta: const Offset(190, 0)));

      viewModel.onHorizontalPanEnd(DragEndDetails());
      expect(updated, isTrue);
    });

    test('Vertical Scroll via Pan', () {
      // Start pan in empty space or vertical direction dominance
      // Tap at (100, 200) -> Row 2 is 100-150. Below?
      // Axis 50. Row 1: 50-100. Row 2: 100-150.
      // Tap at 200 is below rows. No task.

      viewModel
          .onPanStart(DragStartDetails(globalPosition: const Offset(100, 200), localPosition: const Offset(100, 200)));

      // Should be vertical or none initially until update
      // vm._panType is private.

      // Move vertical
      viewModel.onVerticalPanUpdate(DragUpdateDetails(
          globalPosition: const Offset(100, 150), // Moved up 50px
          delta: const Offset(0, -50),
          primaryDelta: -50));

      // TranslateY should change.
      // Initial was 0. Moved up (finger went up) -> scroll down -> translateY decreases?
      // Logic: newTranslateY = _initialTranslateY + (currentY - startY)
      // 0 + (150 - 200) = -50.
      // Content height: 150 (axis 50 + 2 rows * 50).
      // Viewport 500 (height).
      // Valid scroll range: maxNegative = max(0, 150 - 450) = 0.
      // So content fits in viewport. TranslateY should stay 0.

      expect(viewModel.translateY, 0.0);

      // Let's maximize content to enable scrolling
      // 20 rows
      final manyRows = List.generate(20, (i) => LegacyGanttRow(id: 'r$i'));
      final mapStack = {for (var r in manyRows) r.id: 1};

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [],
        dependencies: [],
        visibleRows: manyRows,
        rowMaxStackDepth: mapStack,
        rowHeight: 50.0,
      );
      viewModel.updateLayout(1000, 500);
      // Content height: 50 (axis) + 20*50 = 1050.
      // Viewport 500.
      // Max Scroll = 1050 - 500 = 550.
      // Max negative translateY = -550.

      viewModel
          .onPanStart(DragStartDetails(globalPosition: const Offset(100, 200), localPosition: const Offset(100, 200)));
      viewModel.onVerticalPanUpdate(DragUpdateDetails(
          globalPosition: const Offset(100, 100), // Moved up 100px
          delta: const Offset(0, -100)));

      // 0 + (100 - 200) = -100.
      expect(viewModel.translateY, -100.0);
    });

    test('disposal safety check', () {
      final task = LegacyGanttTask(
          id: 't1',
          name: 'Task 1',
          start: DateTime.now(),
          end: DateTime.now().add(const Duration(days: 1)),
          rowId: 'r1');
      viewModel.dispose();

      // Call various update methods. They should NOT throw "A LegacyGanttViewModel was used after being disposed"
      // because we guarded them. If they were valid calls, they would notify listeners, which throws if disposed.

      // 1. updateData
      viewModel.updateData([]);

      // 2. setFocusedTask
      viewModel.setFocusedTask('t1');

      // 3. updateLayout
      viewModel.updateLayout(100, 100);

      // 4. deleteTask
      viewModel.deleteTask(task);

      // 5. updateResizeTooltipDateFormat
      viewModel.updateResizeTooltipDateFormat((d) => '');

      // If we got here without error, we are good.
      expect(true, isTrue);
    });

    test('updateDependencies does NOT sync changes from external source', () {
      final mockSyncClient = MockGanttSyncClient();
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [task1],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
      );

      const dep1 = LegacyGanttTaskDependency(
        predecessorTaskId: 't1',
        successorTaskId: 't2',
      );

      // Simulate parent widget updating dependencies (e.g. from local DB)
      viewModel.updateDependencies([dep1]);

      expect(mockSyncClient.sentOperations, isEmpty);
    });

    test('Auto-scheduling: Parent shifts Child', () {
      final mockSyncClient = MockGanttSyncClient();
      final parentTask = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        name: 'Parent',
      );
      final childTask = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Child',
        parentId: 'parent',
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [parentTask, childTask],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        enableDragAndDrop: true,
      );

      viewModel.updateLayout(2000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();
      // Scale: 200px/hour. Parent Start (8h): 1600px.

      // Start Drag on Parent
      viewModel.onPanStart(
          DragStartDetails(
            globalPosition: const Offset(1610, 75), // Row 1 y=50-100
            localPosition: const Offset(1610, 75),
          ),
          overrideTask: parentTask);

      // Drag +200px (+1 hour)
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(1810, 75),
        delta: const Offset(200, 0),
        primaryDelta: 200,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // Check operations
      // Expect update for Parent AND Child
      expect(mockSyncClient.sentOperations.length, greaterThanOrEqualTo(2));

      final childUpdate = mockSyncClient.sentOperations.firstWhere((op) => op.data['id'] == 'child');
      final newStart = DateTime.parse(childUpdate.data['start']);
      // Child original 9:00. +1h -> 10:00.
      expect(newStart.hour, 10);
    });

    test('Auto-scheduling: Predecessor shifts Successor', () {
      final mockSyncClient = MockGanttSyncClient();
      final predTask = LegacyGanttTask(
        id: 'pred',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 9),
        name: 'Predecessor',
      );
      final succTask = LegacyGanttTask(
        id: 'succ',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 11),
        name: 'Successor',
      );
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 'pred',
        successorTaskId: 'succ',
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [predTask, succTask],
        dependencies: [dependency],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        enableDragAndDrop: true,
      );

      viewModel.updateLayout(2000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Start Drag on Predecessor
      viewModel.onPanStart(
          DragStartDetails(
            globalPosition: const Offset(1610, 75),
            localPosition: const Offset(1610, 75),
          ),
          overrideTask: predTask);

      // Drag +400px (+2 hours)
      // Original pred: 8-9. New pred: 10-11.
      // Original succ: 10-11. Hit at 10-11 range.
      // Succ must be >= pred.end (11:00).
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(2010, 75),
        delta: const Offset(400, 0),
        primaryDelta: 400,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // Check operations
      final succUpdate = mockSyncClient.sentOperations.firstWhere((op) => op.data['id'] == 'succ');
      final newStart = DateTime.parse(succUpdate.data['start']);
      // Succ original 10:00. Required start is pred.end (11:00).
      expect(newStart.hour, 11);
    });

    test('Auto-scheduling: Backward move does NOT pull successor', () {
      final mockSyncClient = MockGanttSyncClient();
      final predTask = LegacyGanttTask(
        id: 'pred',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 9),
        name: 'Predecessor',
      );
      final succTask = LegacyGanttTask(
        id: 'succ',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 10),
        end: DateTime(2023, 1, 1, 11),
        name: 'Successor',
      );
      const dependency = LegacyGanttTaskDependency(
        predecessorTaskId: 'pred',
        successorTaskId: 'succ',
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [predTask, succTask],
        dependencies: [dependency],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        enableDragAndDrop: true,
      );

      viewModel.updateLayout(2000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Start Drag on Predecessor
      viewModel.onPanStart(
          DragStartDetails(
            globalPosition: const Offset(1610, 75),
            localPosition: const Offset(1610, 75),
          ),
          overrideTask: predTask);

      // Drag -200px (-1 hour)
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(1410, 75),
        delta: const Offset(-200, 0),
        primaryDelta: -200,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // Check operations: Successor should NOT have an update operation
      final hasSuccUpdate = mockSyncClient.sentOperations.any((op) => op.data['id'] == 'succ');
      expect(hasSuccUpdate, isFalse, reason: 'Successor should not be pulled backward');
    });

    test('Auto-scheduling: Disabled Globally', () {
      final mockSyncClient = MockGanttSyncClient();
      final parentTask = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        name: 'Parent',
      );
      final childTask = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Child',
        parentId: 'parent',
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [parentTask, childTask],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        enableDragAndDrop: true,
        enableAutoScheduling: false, // Disabled!
      );

      viewModel.updateLayout(2000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Start Drag on Parent
      viewModel.onPanStart(
          DragStartDetails(
            globalPosition: const Offset(1610, 75), // Row 1
            localPosition: const Offset(1610, 75),
          ),
          overrideTask: parentTask);

      // Drag +200px (+1 hour)
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(1810, 75),
        delta: const Offset(200, 0),
        primaryDelta: 200,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // Check operations
      // Expect update for Parent ONLY
      final childUpdate = mockSyncClient.sentOperations.firstWhereOrNull((op) => op.data['id'] == 'child');
      expect(childUpdate, isNull);
    });

    test('Auto-scheduling: Disabled Per Task', () {
      final mockSyncClient = MockGanttSyncClient();
      final parentTask = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 1, 8),
        end: DateTime(2023, 1, 1, 12),
        name: 'Parent',
      );
      final childTask = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 1, 9),
        end: DateTime(2023, 1, 1, 10),
        name: 'Child',
        parentId: 'parent',
        isAutoScheduled: false, // Disabled for this task!
      );

      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [parentTask, childTask],
        dependencies: [],
        visibleRows: [row1, row2],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        syncClient: mockSyncClient,
        enableDragAndDrop: true,
        enableAutoScheduling: true, // Enabled globally
      );

      viewModel.updateLayout(2000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1, 0).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 10).millisecondsSinceEpoch.toDouble();

      // Start Drag on Parent
      viewModel.onPanStart(
          DragStartDetails(
            globalPosition: const Offset(1610, 75), // Row 1
            localPosition: const Offset(1610, 75),
          ),
          overrideTask: parentTask);

      // Drag +200px (+1 hour)
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(1810, 75),
        delta: const Offset(200, 0),
        primaryDelta: 200,
      ));

      viewModel.onHorizontalPanEnd(DragEndDetails());

      // Check operations
      // Expect update for Parent ONLY
      final childUpdate = mockSyncClient.sentOperations.firstWhereOrNull((op) => op.data['id'] == 'child');
      expect(childUpdate, isNull);
    });
  });
}

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
  Future<void> sendOperations(List<Operation> operations) async {
    for (final op in operations) {
      await sendOperation(op);
    }
  }

  @override
  Future<List<Operation>> getInitialState() async => [];

  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {}

  @override
  Hlc get currentHlc => Hlc.fromDate(DateTime.now(), 'mock');

  @override
  Stream<int> get outboundPendingCount => Stream.value(0);

  @override
  Stream<SyncProgress> get inboundProgress => Stream.value(const SyncProgress(processed: 0, total: 0));

  void addOperation(Operation op) {
    _controller.add(op);
  }

  @override
  Future<String> getMerkleRoot() async => '';

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {}

  @override
  String get actorId => 'mock-actor';
}
