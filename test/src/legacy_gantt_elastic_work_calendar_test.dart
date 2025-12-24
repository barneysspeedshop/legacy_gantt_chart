import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:flutter/material.dart';

void main() {
  group('Elastic Scaling with WorkCalendar', () {
    late LegacyGanttViewModel viewModel;
    const workCalendar = WorkCalendar(
      weekendDays: {DateTime.saturday, DateTime.sunday},
    );

    test('Elastic scaling SHOULD use working days, not absolute duration', () {
      // Jan 2, 2023 is Monday.
      // Parent: Jan 2 (Mon) to Jan 7 (Sat). 5 working days (Mon-Fri).
      final parent = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 2),
        end: DateTime(2023, 1, 7),
        isSummary: true,
        resizePolicy: ResizePolicy.elastic,
        usesWorkCalendar: true,
      );

      // Child: Jan 4 (Wed) to Jan 6 (Fri). 2 working days (Wed, Thu).
      // Child starts at day 2 (offset 2). Duration 2.
      final child = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 4),
        end: DateTime(2023, 1, 6),
        parentId: 'parent',
        usesWorkCalendar: true,
      );

      viewModel = LegacyGanttViewModel(
        data: [parent, child],
        conflictIndicators: [],
        dependencies: [],
        visibleRows: [
          const LegacyGanttRow(id: 'r1', label: 'R1'),
          const LegacyGanttRow(id: 'r2', label: 'R2'),
        ],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        workCalendar: workCalendar,
        enableResize: true,
      );

      viewModel.updateLayout(1000, 500);
      // 1000px / 14 days ~ 71px/day
      viewModel.gridMin = DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 15).millisecondsSinceEpoch.toDouble();

      // Stretch Parent to 2 weeks (Jan 2 to Jan 14 Sat).
      // This is exactly 10 working days (2x).

      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(428, 0)), // ~Jan 7
        overrideTask: parent,
        overridePart: TaskPart.endHandle,
      );

      // Moved to Jan 14. delta = 7 days = 168 hours.
      // Offset calculation for Jan 14: (13 days / 14 days) * 1000 = 928
      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(928, 0),
        delta: const Offset(500, 0),
      ));

      final (cStart, cEnd) = viewModel.bulkGhostTasks['child']!;

      // EXPECTATION (Working Days):
      // Ratio = 10 / 5 = 2.0.
      // Original Child Start Offset (Work Days) = 2. New Offset = 2 * 2 = 4.
      // Jan 2 + 4 work days = Jan 6 (Fri).
      // Original Child Duration (Work Days) = 2. New Duration = 2 * 2 = 4.
      // Jan 6 + 4 work days = Mon, Tue, Wed -> Jan 11 (Wed).

      // CURRENT BEHAVIOR (Absolute):
      // P Original: Jan 2 to Jan 7 = 5 days.
      // P New: Jan 2 to Jan 14 = 12 days.
      // Ratio = 12 / 5 = 2.4.
      // C Original Start Offset: Jan 4 - Jan 2 = 2 days.
      // C New Start Offset = 2 * 2.4 = 4.8 days.
      // C New Start = Jan 2 + 4.8 days = Friday evening.

      expect(workCalendar.getWorkingDuration(cStart, cEnd), equals(4),
          reason: "Child should have 4 working days after 2x stretch of parent's working duration");
      expect(cStart, equals(DateTime(2023, 1, 6)), reason: 'Child should start on Friday Jan 6');
    });

    test('Elastic scaling from START handle should NOT push children outside parent', () {
      // Mon Jan 2 to Sat Jan 7. (5 working days: Mon, Tue, Wed, Thu, Fri).
      final parent = LegacyGanttTask(
        id: 'parent',
        rowId: 'r1',
        start: DateTime(2023, 1, 2),
        end: DateTime(2023, 1, 7),
        isSummary: true,
        resizePolicy: ResizePolicy.elastic,
        usesWorkCalendar: true,
      );

      // Child is at the very end of the parent.
      // Thu Jan 5 to Sat Jan 7. (2 working days: Thu, Fri).
      final child = LegacyGanttTask(
        id: 'child',
        rowId: 'r2',
        start: DateTime(2023, 1, 5),
        end: DateTime(2023, 1, 7),
        parentId: 'parent',
        usesWorkCalendar: true,
      );

      viewModel = LegacyGanttViewModel(
        data: [parent, child],
        conflictIndicators: [],
        dependencies: [],
        visibleRows: [
          const LegacyGanttRow(id: 'r1', label: 'R1'),
          const LegacyGanttRow(id: 'r2', label: 'R2'),
        ],
        rowMaxStackDepth: {'r1': 1, 'r2': 1},
        rowHeight: 50.0,
        workCalendar: workCalendar,
        enableResize: true,
      );

      viewModel.updateLayout(1000, 500);
      viewModel.gridMin = DateTime(2023, 1, 1).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 15).millisecondsSinceEpoch.toDouble();

      // Resize START handle of parent from Mon Jan 2 to Tue Jan 3.
      // Offset for Jan 2: (1 day / 14 days) * 1000 = 71.4
      // Offset for Jan 3: (2 days / 14 days) * 1000 = 142.8

      viewModel.onPanStart(
        DragStartDetails(globalPosition: const Offset(71, 0)),
        overrideTask: parent,
        overridePart: TaskPart.startHandle,
      );

      viewModel.onHorizontalPanUpdate(DragUpdateDetails(
        globalPosition: const Offset(143, 0),
        delta: const Offset(72, 0),
      ));

      final (cStart, cEnd) = viewModel.bulkGhostTasks['child']!;

      // Parent New: Tue Jan 3 to Sat Jan 7.
      expect(cEnd.isBefore(parent.end) || cEnd.isAtSameMomentAs(parent.end), isTrue,
          reason: 'Child end ($cEnd) should not be after parent end (${parent.end})');
      expect(cStart.isAfter(DateTime(2023, 1, 3)) || cStart.isAtSameMomentAs(DateTime(2023, 1, 3)), isTrue,
          reason: 'Child start ($cStart) should not be before parent start (Jan 3)');
    });
  });
}
