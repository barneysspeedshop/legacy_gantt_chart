import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Elastic Resize with Work Calendar', () {
    test('Should scale child task based on WORKING duration, not absolute time', () {
      // 1. Setup Calendar: Weekends (Sat/Sun) are non-working
      const calendar = WorkCalendar(weekendDays: {DateTime.saturday, DateTime.sunday});

      // 2. Setup Data
      // Parent: 1 Week (Mon June 3 -> Sat June 8). Duration: 5 Working Days.
      final parentStart = DateTime(2024, 6, 3); // Monday
      final parentEnd = DateTime(2024, 6, 8); // Saturday (00:00)

      // Child: 1 Day (Tue June 4 -> Wed June 5).
      // Position: Starts on Day 2 of Parent. Duration: 1 Working Day.
      final childStart = DateTime(2024, 6, 4);
      final childEnd = DateTime(2024, 6, 5);

      final parent = LegacyGanttTask(
        id: 'p1',
        rowId: 'r1',
        start: parentStart,
        end: parentEnd,
        isSummary: true,
        resizePolicy: ResizePolicy.elastic,
        usesWorkCalendar: true,
      );

      final child = LegacyGanttTask(
        id: 'c1',
        rowId: 'r2',
        start: childStart,
        end: childEnd,
        parentId: 'p1',
        usesWorkCalendar: true, // Important!
      );

      final viewModel = LegacyGanttViewModel(
        data: [parent, child],
        conflictIndicators: [],
        dependencies: [],
        visibleRows: [], // Not needed for logic test
        rowMaxStackDepth: {},
        rowHeight: 30,
        workCalendar: calendar,
        enableResize: true,
      );

      // 3. Simulate Drag: Stretch Parent to 2 Weeks
      // New End: Sat June 15.
      // Old Working Duration: 5 days.
      // New Working Duration: 10 days.
      // Scale Factor: 2.0x.
      final newParentEnd = DateTime(2024, 6, 15);

      // We simulate the drag logic (internally calls _handleHorizontalPan logic)
      // Since _handleHorizontalPan is private/complex to mock with gestures,
      // we will manually invoke the logic we expect, or expose a helper.
      // Ideally, we test the logic inside the ViewModel.
      // Since we can't easily drag in a unit test without widget testers,
      // let's verify the math logic directly if we can, or simulate the state.

      // 3. Initialize Layout to establish coordinate system
      viewModel.updateLayout(1000, 500);

      // Verify scale is working
      expect(viewModel.totalScale, isNotNull);

      // 4. Calculate Drag Delta required
      // We want to drag Parent End from June 8 to June 15.
      final startPx = viewModel.totalScale(parentEnd);
      final newEndPx = viewModel.totalScale(newParentEnd);
      final deltaPx = newEndPx - startPx;

      // 5. TRIGGER THE GHOST STATE (Simulate Drag)
      viewModel.onPanStart(
        DragStartDetails(globalPosition: Offset.zero, localPosition: Offset.zero),
        overrideTask: parent,
        overridePart: TaskPart.endHandle,
      );

      // 6. Pan Update to new position
      // _dragStartGlobalX was 0. We move to deltaPx.
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: Offset(deltaPx, 0),
        delta: Offset(deltaPx, 0),
        primaryDelta: deltaPx,
      ));

      // 7. Assertions
      // The child ghost should be in bulkGhostTasks
      expect(viewModel.bulkGhostTasks.containsKey('c1'), isTrue);

      final (ghostStart, ghostEnd) = viewModel.bulkGhostTasks['c1']!;

      // Expected Working Logic dates:
      // Start: Mon June 3 + 2 working days = Wed June 5.
      // End: Wed June 5 + 2 working days = Fri June 7.
      final expectedStart = DateTime(2024, 6, 5);
      final expectedEnd = DateTime(2024, 6, 7);

      print('Actual: $ghostStart -> $ghostEnd');
      expect(ghostStart, equals(expectedStart), reason: 'Child Start should effectively scale by 2x working days');
      expect(ghostEnd, equals(expectedEnd), reason: 'Child End should effectively scale by 2x working days');
    });
  });
}
