import 'package:flutter_test/flutter_test.dart';
import 'package:example/view_models/gantt_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('GanttViewModel State Persistence', () {
    late GanttViewModel viewModel;

    setUp(() async {
      viewModel = GanttViewModel();
      // Wait for initial data load
      await viewModel.fetchScheduleData();
    });

    test('Moving a second task does not revert the first task position', () async {
      // 1. Get initial tasks
      expect(viewModel.ganttTasks, isNotEmpty);
      final task1 = viewModel.ganttTasks[0];
      final task2 = viewModel.ganttTasks[1];

      final initialStart1 = task1.start;
      final initialStart2 = task2.start;

      // 2. Move Task 1
      final newStart1 = initialStart1.add(const Duration(days: 2));
      final newEnd1 = task1.end.add(const Duration(days: 2));

      viewModel.handleTaskUpdate(task1, newStart1, newEnd1);

      // Verify Task 1 moved in the view model
      final task1AfterMove = viewModel.ganttTasks.firstWhere((t) => t.id == task1.id);
      expect(task1AfterMove.start, newStart1);

      // 3. Move Task 2
      final newStart2 = initialStart2.add(const Duration(days: 3));
      final newEnd2 = task2.end.add(const Duration(days: 3));

      viewModel.handleTaskUpdate(task2, newStart2, newEnd2);

      // Verify Task 2 moved
      final task2AfterMove = viewModel.ganttTasks.firstWhere((t) => t.id == task2.id);
      expect(task2AfterMove.start, newStart2);

      // 4. CRITICAL: Verify Task 1 is STILL at its new position
      final task1AfterSecondMove = viewModel.ganttTasks.firstWhere((t) => t.id == task1.id);
      expect(task1AfterSecondMove.start, newStart1, reason: 'Task 1 should NOT snap back after Task 2 is moved');
    });
  });
}
