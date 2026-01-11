import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LegacyGanttViewModel - Rolled Up Milestone Hit Testing', () {
    late LegacyGanttViewModel viewModel;
    const row1 = LegacyGanttRow(id: 'r1', label: 'Summary Row');
    // Summary task on Row 1
    final summaryTask = LegacyGanttTask(
      id: 's1',
      rowId: 'r1',
      start: DateTime(2023, 1, 1, 8),
      end: DateTime(2023, 1, 1, 12),
      name: 'Summary Task',
      isSummary: true,
    );
    // Milestone on a different row (or null row), but parentId is s1
    final milestoneTask = LegacyGanttTask(
      id: 'm1',
      rowId: 'r99', // Different row
      start: DateTime(2023, 1, 1, 10), // Middle of summary
      end: DateTime(2023, 1, 1, 10),
      name: 'Milestone',
      isMilestone: true,
      parentId: 's1',
    );

    setUp(() {
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [summaryTask, milestoneTask],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        enableDragAndDrop: true,
        enableResize: true,
        rollUpMilestones: true, // Enabled
      );
      // Layout: 1000x500. Axis 50px-ish (default implied or 0 if not set, let's assume height management logic)
      // Actually VM calculates axis height internally if not set? No, it's passed in.
      // We'll simulate a layout update.
      viewModel.updateLayout(1000, 500);
      // Grid from 8:00 to 12:00 -> 4 hours. 1000px. 250px/hour.
      viewModel.gridMin = DateTime(2023, 1, 1, 8).millisecondsSinceEpoch.toDouble();
      viewModel.gridMax = DateTime(2023, 1, 1, 12).millisecondsSinceEpoch.toDouble();

      // Force domains calc
      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 8).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 12).millisecondsSinceEpoch.toDouble());
    });

    test('onHover hits rolled-up milestone on summary row', () {
      LegacyGanttTask? hoveredTask;
      viewModel.onTaskHover = (task, _) {
        hoveredTask = task;
      };

      // Milestone at 10:00. Start is 8:00. Diff 2 hours.
      // 2 hours * 250px/hr = 500px from X start.
      // Row 1 starts at Y=0 (relative to content).
      // Axis height logic: check VM. If not set, maybe 0.
      // `timeAxisHeight` getter accesses `_axisHeight ?? 54.0`.
      // So Y start is 54.0.
      // Row 1 is 54.0 to 104.0.
      // Milestone diamond size is rowHeight * 0.8 = 40.
      // Center of row is 54 + 25 = 79.
      // Hit at X=510 (center of milestone), Y=79.

      // Note: Hit testing logic for milestone body:
      // `if (pointerXOnTotalContent >= barStartX && pointerXOnTotalContent <= barStartX + diamondSize)`
      // barStartX = 500. diamondSize = 40. Range [500, 540].

      viewModel.onHover(const PointerHoverEvent(position: Offset(510, 79)));

      expect(hoveredTask, isNotNull);
      expect(hoveredTask!.id, 'm1');
    });

    test('onHover does NOT hit rolled-up milestone if disabled', () {
      viewModel = LegacyGanttViewModel(
        conflictIndicators: [],
        data: [summaryTask, milestoneTask],
        dependencies: [],
        visibleRows: [row1],
        rowMaxStackDepth: {'r1': 1},
        rowHeight: 50.0,
        rollUpMilestones: false, // Disabled
      );
      viewModel.updateLayout(1000, 500);
      viewModel.updateVisibleRange(DateTime(2023, 1, 1, 8).millisecondsSinceEpoch.toDouble(),
          DateTime(2023, 1, 1, 12).millisecondsSinceEpoch.toDouble());

      LegacyGanttTask? hoveredTask;
      viewModel.onTaskHover = (task, _) {
        hoveredTask = task;
      };

      // Same position
      viewModel.onHover(const PointerHoverEvent(position: Offset(510, 79)));

      // Might hit summary task 's1' instead, or nothing if z-index logic prefers summary?
      // Actually `_getTaskPartAtPosition` iterates tasks in stack. Summary task is there.
      // If milestone is not "injected" into the check loop, hit test continues to summary task.

      expect(hoveredTask, isNotNull);
      expect(hoveredTask!.id, 's1'); // Should match summary task now
    });
  });
}
