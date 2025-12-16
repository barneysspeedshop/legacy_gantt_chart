import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/local_gantt_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('GanttViewModel updates flatGridData on remote update', () async {
    // 1. Setup DB
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();

    // 2. Insert initial data (Collapsed parent)
    final repo = LocalGanttRepository();
    await repo.init();
    await repo.insertOrUpdateResource(LocalResource(id: 'p1', name: 'Parent 1', isExpanded: false));
    await repo.insertOrUpdateResource(LocalResource(id: 'c1', name: 'Child 1', parentId: 'p1', isExpanded: true));

    // Add task so _processLocalData runs
    await repo.insertOrUpdateTask(LegacyGanttTask(
        id: 't1',
        rowId: 'c1',
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 1)),
        name: 'Task 1'));

    // 3. Init ViewModel
    final vm = GanttViewModel(useLocalDatabase: true);
    // Wait for init
    await Future.delayed(const Duration(milliseconds: 200));

    // 4. Verify initial state
    var p1 = vm.flatGridData.firstWhere((item) => item['id'] == 'p1');
    expect(p1['isExpanded'], isFalse);

    // 5. Simulate Remote Update (Expand p1)
    // Directly update the repository. This should trigger the stream listener -> _processLocalData.
    await repo.insertOrUpdateResource(LocalResource(id: 'p1', name: 'Parent 1', isExpanded: true));

    // Wait for stream to process
    await Future.delayed(const Duration(milliseconds: 200));

    // 6. Verify ViewModel state updated
    p1 = vm.flatGridData.firstWhere((item) => item['id'] == 'p1');
    expect(p1['isExpanded'], isTrue, reason: 'Remote Expansion state mismatch in flatGridData');

    vm.dispose();
  });
}
