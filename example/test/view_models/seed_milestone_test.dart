import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/local_gantt_repository.dart';

class BlockingSyncClient implements GanttSyncClient {
  final sending = Completer<void>();
  final release = Completer<void>();
  final sentOperations = <Operation>[];

  Hlc _clock = Hlc.fromDate(DateTime.now(), 'blocked');

  @override
  Hlc get currentHlc => _clock = _clock.send(DateTime.now().millisecondsSinceEpoch);

  @override
  String get actorId => 'blocked';

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    sentOperations.addAll(operations);
    if (!sending.isCompleted) sending.complete();
    await release.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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

    expect(vm.localResources, hasLength(171));
    expect(vm.gridData.map((row) => row.name).toList(), List.generate(10, (i) => 'Person $i'));

    final queue = await (await GanttDb.db).query('SELECT * FROM offline_queue WHERE is_deleted = 0');
    expect(queue, isEmpty, reason: 'Automatic sample data must not reset a shared tenant on connection');

    // 3. Verify Milestone exists in VM memory
    final milestone = vm.allGanttTasks.firstWhere(
      (t) => t.isMilestone && t.id == 'milestone_demo_1',
      orElse: () => throw Exception('Milestone not found'),
    );
    expect(milestone, isNotNull);
    expect(milestone.name, 'Project Kick-off');

    // 4. Verify Milestone exists in Local DB
    final repo = LocalGanttRepository();
    await repo.init();
    final tasks = await repo.getAllTasks();
    final dbMilestone = tasks.firstWhere((t) => t.id == 'milestone_demo_1');
    expect(dbMilestone, isNotNull);

    await vm.disposeAsync();
    await GanttDb.reset();
  });
  test('an empty bound tenant does not automatically generate replacement data', () async {
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();
    final db = await GanttDb.db;
    await db.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
      'canonical_scope',
      'bound-tenant',
    ]);
    final vm = GanttViewModel(useLocalDatabase: true);
    final ready = Completer<void>();
    void onChange() {
      if (!vm.isLoading && !ready.isCompleted) ready.complete();
    }

    vm.addListener(onChange);
    try {
      onChange();
      await ready.future.timeout(const Duration(seconds: 5));
      expect(vm.allTasks, isEmpty);
      expect(vm.localResources, isEmpty);
      expect(await db.query('SELECT * FROM offline_queue WHERE is_deleted = 0'), isEmpty);
    } finally {
      vm.removeListener(onChange);
      await vm.disposeAsync();
      await GanttDb.reset();
    }
  });

  test('local reseed builds its resource hierarchy before synchronization completes', () async {
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();
    final vm = GanttViewModel();
    await vm.setUseLocalDatabase(true);
    await vm.seedLocalDatabase();
    final client = BlockingSyncClient();
    vm.setSyncClient(client);
    final reseed = vm.seedLocalDatabase();
    try {
      await client.sending.future.timeout(const Duration(seconds: 5));
      final resources = await LocalGanttRepository().getAllResources();
      expect(resources, hasLength(171));
      expect(vm.gridData.map((row) => row.name).toList(), List.generate(10, (i) => 'Person $i'));
    } finally {
      client.release.complete();
      await reseed;
      final dependencyTypes = client.sentOperations
          .where((op) => op.type == 'INSERT_DEPENDENCY')
          .map((op) => ProtobufMapper.toJson(ProtobufMapper.toProtobuf(op.toJson()))['data']['type'])
          .toSet();
      expect(dependencyTypes, containsAll(['contained', 'finishToStart']));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await vm.disposeAsync();
      await GanttDb.reset();
    }
  });
}
