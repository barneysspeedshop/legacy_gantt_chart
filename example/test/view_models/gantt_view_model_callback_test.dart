import 'package:flutter/material.dart';
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

  testWidgets('GanttViewModel calls onGridExpansionChange on local toggle', (tester) async {
    // 1. Setup DB
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();

    // 2. Insert initial data
    final repo = LocalGanttRepository();
    await repo.init();
    await repo.insertOrUpdateResource(LocalResource(id: 'p1', name: 'Parent 1', isExpanded: false));
    await repo.insertOrUpdateResource(LocalResource(id: 'c1', name: 'Child 1', parentId: 'p1', isExpanded: true));
    await repo.insertOrUpdateTask(LegacyGanttTask(
        id: 't1',
        rowId: 'c1',
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 1)),
        name: 'Task 1'));

    // 3. Init ViewModel
    final vm = GanttViewModel(useLocalDatabase: true);
    // Allow async init to start
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });

    // Pump widget to attach controller
    await tester.pumpWidget(MaterialApp(
      home: ListView(controller: vm.gridScrollController),
    ));
    await tester.pumpAndSettle();

    // 4. Setup callback tracker
    String? callbackRowId;
    bool? callbackIsExpanded;
    vm.onGridExpansionChange = (rowId, isExpanded) {
      callbackRowId = rowId;
      callbackIsExpanded = isExpanded;
    };

    // 5. Toggle Expansion
    vm.toggleExpansion('p1');

    // 6. Verify callback fired
    expect(callbackRowId, equals('p1'), reason: 'Row ID mismatch');
    expect(callbackIsExpanded, isTrue, reason: 'Expansion state mismatch');

    vm.dispose();
  });
}
