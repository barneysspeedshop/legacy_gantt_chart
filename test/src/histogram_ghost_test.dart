import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/src/models/resource_bucket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Histogram Ghost with Work Calendar', () {
    test('Should NOT add load to non-working days during drag', () {
      const calendar = WorkCalendar(weekendDays: {DateTime.saturday, DateTime.sunday});

      // Task: 1 Day (Friday June 7)
      final start = DateTime(2024, 6, 7);
      final end = DateTime(2024, 6, 8); // Ends Sat 00:00

      final task = LegacyGanttTask(
        id: 't1',
        rowId: 'r1',
        start: start,
        end: end,
        resourceId: 'User1',
        load: 1.0,
        usesWorkCalendar: true,
      );

      final viewModel = LegacyGanttViewModel(
        data: [task],
        conflictIndicators: [],
        dependencies: [],
        visibleRows: [],
        rowMaxStackDepth: {},
        rowHeight: 30,
        workCalendar: calendar,
        enableDragAndDrop: true,
      );
      viewModel.updateLayout(1000, 500);

      // Verify Initial Bucket (Friday loaded)
      // Note: resourceBuckets includes _baseResourceBuckets if not dragging
      // But _baseResourceBuckets logic is in aggregateResourceLoad, let's trust it works or check it.
      // Actually, let's just jump to dragging.

      // Simulate Drag: Move to Saturday (June 8)
      // Duration is 1 day.
      // If we drag it to start on Saturday, June 8...
      // Since it's a dragging "Ghost", the user might literally put it ON Saturday visually.
      // But because it usesWorkCalendar, our new logic should see Saturday is non-working,
      // and thus NOT add load to it? Or should it?
      //
      // Wait, if I drag a task TO a weekend, and it usesWorkCalendar... well, usually the SNAP logic
      // prevents it from landing there. But the Histogram logic loops day by day.
      // If the ghost start IS Saturday, the loop runs for Saturday.
      // `isWorkingDay(Saturday)` is false. So we skip adding load.
      // Result: The bucket for Saturday should have 0 load (or not exist).

      // Let's force the ghost positions manually by hacking the private members via interactions
      // Parent/Child logic isn't needed here, just a simple drag.

      final sat = DateTime(2024, 6, 8);

      // We start a drag
      viewModel.onPanStart(DragStartDetails(globalPosition: Offset.zero, localPosition: Offset.zero),
          overrideTask: task, overridePart: TaskPart.body);

      // Move it 24 hours to the right (Friday -> Saturday)
      final startPx = viewModel.totalScale(start);
      final satPx = viewModel.totalScale(sat);
      final delta = satPx - startPx;

      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: Offset(delta, 0),
        delta: Offset(delta, 0),
        primaryDelta: delta,
      ));

      // Now check resourceBuckets
      final buckets = viewModel.resourceBuckets['User1']!;

      // We expect the original Friday load to be REMOVED (because we dragged away)
      // We expect the new Saturday load to be ... SKIPPED (because it's non-working)
      // So effectively, total load for Friday is 0, Saturday is 0.

      final fridayBucket = buckets.firstWhere((b) => b.date.day == 7,
          orElse: () => ResourceBucket(date: start, resourceId: 'User1', totalLoad: 0));
      final saturdayBucket = buckets.firstWhere((b) => b.date.day == 8,
          orElse: () => ResourceBucket(date: sat, resourceId: 'User1', totalLoad: 0));

      print('Friday Load: ${fridayBucket.totalLoad}');
      print('Saturday Load: ${saturdayBucket.totalLoad}');

      expect(fridayBucket.totalLoad, 0.0, reason: 'Original load should be removed');
      expect(saturdayBucket.totalLoad, 0.0, reason: 'Weekend load should be skipped');
    });
  });
}
