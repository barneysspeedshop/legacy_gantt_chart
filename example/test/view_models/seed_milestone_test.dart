import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'package:legacy_gantt_chart/legacy_gantt_chart.dart'; // Unused
import 'package:example/view_models/gantt_view_model.dart';
import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/local_gantt_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('GanttViewModel seeds milestone in local mode', () async {
    // 1. Setup DB
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();

    // 2. Init ViewModel in local mode
    // Using true for useLocalDatabase to trigger auto-seeding
    final vm = GanttViewModel();
    // Use a public setter or verify interaction.
    // The default is false, so we need to set it.
    await vm.setUseLocalDatabase(true);

    // Wait for async seeding (triggered by empty tasks detection in _initLocalMode)
    // Seeding takes some time as it generates data.
    await Future.delayed(const Duration(seconds: 2));

    // 3. Verify Milestone exists in VM memory
    final milestone = vm.allGanttTasks.firstWhere((t) => t.isMilestone && t.id == 'milestone_demo_1',
        orElse: () => throw Exception('Milestone not found'));
    expect(milestone, isNotNull);
    expect(milestone.name, 'Project Kick-off');

    // 4. Verify Milestone exists in Local DB
    final repo = LocalGanttRepository();
    await repo.init();
    final tasks = await repo.getAllTasks();
    final dbMilestone = tasks.firstWhere((t) => t.id == 'milestone_demo_1');
    expect(dbMilestone, isNotNull);

    vm.dispose();
  });
}
