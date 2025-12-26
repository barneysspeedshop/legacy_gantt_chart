import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/legacy_gantt_view_model.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_task.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_row.dart';

void main() {
  test('LegacyGanttViewModel formats tooltips with project timezone', () {
    final task = LegacyGanttTask(
      id: 'task1',
      rowId: 'row1',
      start: DateTime.utc(2025, 12, 26, 20, 0), // 8 PM UTC
      end: DateTime.utc(2025, 12, 26, 21, 0), // 9 PM UTC
    );

    final viewModel = LegacyGanttViewModel(
      data: [task],
      visibleRows: [const LegacyGanttRow(id: 'row1')],
      rowMaxStackDepth: {'row1': 1},
      rowHeight: 40.0,
      conflictIndicators: [],
      dependencies: [],
      projectTimezoneAbbreviation: 'EST',
      projectTimezoneOffset: const Duration(hours: -5),
    );

    final time = DateTime.utc(2025, 12, 26, 20, 0);
    final tooltip = viewModel.formatDateTimeWithTimezoneForTest(time);

    expect(tooltip, contains('(Local)'));
    expect(tooltip, contains('15:00')); // 8 PM UTC - 5 hours = 3 PM (15:00)
    expect(tooltip, contains('(EST)'));
  });
}
