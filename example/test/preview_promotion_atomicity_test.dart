import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a failed first preview edit preserves the preview and can be retried', () async {
    final directory = await Directory.systemTemp.createTemp('gantt-preview-promotion-');
    final database = await GanttDb.open('${directory.path}/client.sqlite');
    final viewModel = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
    final preview = ProtocolStateStore(Future.value(database), scope: 'preview');
    final local = ProtocolStateStore(Future.value(database));
    try {
      await viewModel.initialized;
      final before = await preview.readState();
      final beforeRoot = (await preview.computeMerkleTree()).root.hash;
      final beforeTasks = {for (final task in viewModel.allTasks) task.id: task.name};
      final beforeCanonical = await database.query(
        'SELECT scope, entity_type, entity_id, payload FROM canonical_protocol_state ORDER BY scope, entity_type, entity_id',
      );
      final beforeProjection = await database.query('SELECT * FROM tasks ORDER BY id');
      final beforeOutbox = await database.query('SELECT * FROM offline_queue ORDER BY id');
      expect(beforeTasks, isNotEmpty);
      expect(beforeOutbox, isEmpty);
      expect((await local.readState()).hasState, isFalse);
      final original = viewModel.allTasks.first;
      final visibleCounts = <int>[];
      void recordVisibleCount() => visibleCounts.add(viewModel.allTasks.length);
      viewModel.addListener(recordVisibleCount);
      await database.execute(
        "CREATE TRIGGER reject_preview_promotion BEFORE INSERT ON offline_queue BEGIN SELECT RAISE(ABORT, 'injected preview promotion failure'); END",
      );

      await expectLater(viewModel.updateTask(original.copyWith(name: 'Rejected edit')), throwsA(anything));

      expect({for (final task in viewModel.allTasks) task.id: task.name}, beforeTasks);
      expect(visibleCounts, isNot(contains(0)));
      expect((await preview.computeMerkleTree()).root.hash, beforeRoot);
      expect((await local.readState()).hasState, isFalse);
      expect(
        await database.query(
          'SELECT scope, entity_type, entity_id, payload FROM canonical_protocol_state ORDER BY scope, entity_type, entity_id',
        ),
        beforeCanonical,
      );
      expect(await database.query('SELECT * FROM tasks ORDER BY id'), beforeProjection);
      expect(await database.query('SELECT * FROM offline_queue ORDER BY id'), beforeOutbox);

      await database.execute('DROP TRIGGER reject_preview_promotion');
      await viewModel.updateTask(original.copyWith(name: 'Promoted edit'));

      expect(viewModel.allTasks, hasLength(beforeTasks.length));
      expect(viewModel.allTasks.singleWhere((task) => task.id == original.id).name, 'Promoted edit');
      final promoted = await local.readState();
      expect(promoted.tasks, hasLength(before.tasks.length));
      expect(promoted.resources, hasLength(before.resources.length));
      expect(promoted.dependencies, hasLength(before.dependencies.length));
      expect(promoted.tasks.singleWhere((task) => task.id == original.id).name, 'Promoted edit');
      expect((await preview.computeMerkleTree()).root.hash, beforeRoot);
      final outbox = await database.query('SELECT type, data FROM offline_queue WHERE is_deleted = 0 ORDER BY id');
      expect(outbox, hasLength(before.tasks.length + before.resources.length + before.dependencies.length + 1));
      expect(outbox.last['type'], 'UPDATE_TASK');
      expect(jsonDecode(outbox.last['data']! as String)['name'], 'Promoted edit');
      expect(visibleCounts, isNot(contains(0)));
      viewModel.removeListener(recordVisibleCount);
    } finally {
      await viewModel.disposeAsync();
      await preview.close();
      await local.close();
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
