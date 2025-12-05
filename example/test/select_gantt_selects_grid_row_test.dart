import 'package:flutter_test/flutter_test.dart';
import 'package:example/view_models/gantt_view_model.dart';

void main() {
  group('GanttViewModel Selection Reproduction', () {
    late GanttViewModel viewModel;

    setUp(() {
      viewModel = GanttViewModel();
    });

    test('setFocusedTaskId updates selectedRowId', () async {
      await Future.delayed(const Duration(milliseconds: 100));

      expect(viewModel.ganttTasks, isNotEmpty, reason: 'Tasks should be loaded');

      final firstTask = viewModel.ganttTasks.first;
      final expectedRowId = firstTask.rowId;

      expect(viewModel.selectedRowId, isNull, reason: 'Initially no row selected');

      viewModel.setFocusedTaskId(firstTask.id);

      expect(viewModel.focusedTaskId, firstTask.id);
      expect(viewModel.selectedRowId, expectedRowId, reason: 'selectedRowId should match the row of the focused task');
    });

    test('flatGridData is cached and invalidated', () async {
      await Future.delayed(const Duration(milliseconds: 100));

      final data1 = viewModel.flatGridData;
      final data2 = viewModel.flatGridData;

      expect(identical(data1, data2), isTrue, reason: 'flatGridData should be cached');

      // Trigger an update that invalidates cache
      // We can use setPersonCount which triggers fetchScheduleData
      viewModel.setPersonCount(5);

      // Wait for fetch
      await Future.delayed(const Duration(milliseconds: 100));

      final data3 = viewModel.flatGridData;
      expect(identical(data1, data3), isFalse, reason: 'flatGridData should be new after data update');
    });
  });
}
