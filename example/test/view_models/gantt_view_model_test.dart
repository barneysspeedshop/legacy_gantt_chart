import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart'; // From package
import 'package:example/view_models/gantt_view_model.dart';
import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/local_gantt_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('GanttViewModel updates expansionSignature on remote expansion change', () async {
    // 1. Setup DB
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();

    // 2. Insert initial data (One parent, collapsed)
    final repo = LocalGanttRepository();
    await repo.init();
    await repo.insertOrUpdateResource(LocalResource(id: 'p1', name: 'Parent 1', isExpanded: false));
    await repo.insertOrUpdateResource(LocalResource(id: 'c1', name: 'Child 1', parentId: 'p1', isExpanded: true));

    // Add a task to ensure grid data is built (otherwise logic might skip)
    await repo.insertOrUpdateTask(LegacyGanttTask(
        id: 't1',
        rowId: 'c1',
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 1)),
        name: 'Task 1'));

    // 3. Init ViewModel
    final vm = GanttViewModel(useLocalDatabase: true);

    // Wait for initial load (seedVersion increments on init)
    await Future.delayed(const Duration(milliseconds: 500));
    final initialSignature = vm.expansionSignature;
    expect(vm.gridData.length, greaterThan(0));
    expect(vm.gridData.first.isExpanded, isFalse);

    // 4. Simulate Remote Update (Update DB directly)
    // Expand p1
    await repo.updateResourceExpansion('p1', true, Hlc.fromDate(DateTime.now(), 'test'));

    // Wait for listener to fire
    await Future.delayed(const Duration(milliseconds: 500));

    // 5. Verify expansionSignature changed
    // If it changed, the main.dart ValueKey will change and grid will rebuild.
    expect(vm.expansionSignature, isNot(equals(initialSignature)));

    // Verify grid data updated
    expect(vm.gridData.first.isExpanded, isTrue);

    vm.dispose();
  });
}
