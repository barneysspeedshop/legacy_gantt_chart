import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/legacy_projection_migration.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:example/data/local/local_gantt_repository.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('resource metadata and type survive public edits, restart and wire encoding', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final setup = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('gantt-resource-metadata-');
      final database = await GanttDb.open('${directory.path}/client.sqlite');
      await database.execute('INSERT OR REPLACE INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
        'canonical_scope',
        'local',
      ]);
      final vm = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
      await vm.initialized;
      return (directory, database, vm);
    }))!;
    final directory = setup.$1;
    var database = setup.$2;
    var vm = setup.$3;
    try {
      await tester.runAsync(() async {
        await vm.initialized;
        final clock = vm.syncClient!.currentHlc;
        await vm.handleIncomingOperationForTesting(
          Operation(
            type: 'INSERT_RESOURCE',
            data: {
              'id': 'tool',
              'name': 'Crane',
              'type': 'tool',
              'isExpanded': true,
              'sort_order': 10.0,
              'custom': {
                'rate': 3,
                'tags': ['rental', 'heavy'],
              },
            },
            timestamp: clock,
            actorId: 'remote',
          ),
        );
        await vm.addResources([LocalResource(id: 'other', name: 'Other', sortOrder: 20)]);
        await vm.addTask(
          LegacyGanttTask(
            id: 'task',
            rowId: 'tool',
            name: 'Lift',
            start: DateTime.utc(2026, 11, 20),
            end: DateTime.utc(2026, 11, 21),
          ),
        );
        await vm.addTask(
          LegacyGanttTask(
            id: 'other-task',
            rowId: 'other',
            name: 'Other task',
            start: DateTime.utc(2026, 11, 20),
            end: DateTime.utc(2026, 11, 21),
          ),
        );
        expect(vm.localResources.firstWhere((r) => r.id == 'tool').type, 'tool');
        final metadata = vm.localResources.firstWhere((r) => r.id == 'tool').extraMetadata;
        expect(() => (metadata['custom'] as Map)['rate'] = 99, throwsUnsupportedError);
        expect(() => ((metadata['custom'] as Map)['tags'] as List).add('changed'), throwsUnsupportedError);
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(controller: vm.gridScrollController, child: const SizedBox(height: 2000)),
        ),
      );
      await tester.runAsync(() async {
        final collapsed = Completer<void>();
        void changed() {
          if (!vm.localResources.firstWhere((r) => r.id == 'tool').isExpanded && !collapsed.isCompleted) {
            collapsed.complete();
          }
        }

        vm.addListener(changed);
        try {
          vm.toggleExpansion('tool', false);
          await collapsed.future.timeout(const Duration(seconds: 5));
        } finally {
          vm.removeListener(changed);
        }
        await vm.reorderResources('tool', 'other', true);
        await vm.addResources([vm.localResources.firstWhere((r) => r.id == 'tool').copyWith(name: 'Renamed crane')]);
        final resource = vm.localResources.firstWhere((r) => r.id == 'tool');
        expect(resource.sortOrder, 21.0);
        expect(resource.type, 'tool');
        expect(resource.name, 'Renamed crane');
        expect(resource.isExpanded, false);
        expect(resource.extraMetadata['custom'], {
          'rate': 3,
          'tags': ['rental', 'heavy'],
        });
        final queued = await database.query(
          'SELECT data, timestamp, actor_id FROM offline_queue WHERE is_deleted = 0 AND type = ? ORDER BY id',
          ['INSERT_RESOURCE'],
        );
        final row = queued.last;
        final operation = Operation.fromJson({
          'type': 'INSERT_RESOURCE',
          'data': jsonDecode(row['data']! as String),
          'timestamp': row['timestamp'],
          'actorId': row['actor_id'],
        });
        final wire = Operation.fromJson(
          ProtobufMapper.toJson(
            ProtocolMessage.fromBuffer(ProtobufMapper.toProtobuf(operation.toJson()).writeToBuffer()),
          ),
        );
        expect(wire.data['type'], 'tool');
        expect(wire.data['custom'], {
          'rate': 3,
          'tags': ['rental', 'heavy'],
        });
        expect(wire.data['isExpanded'], false);
        expect(wire.data['lastUpdated'], wire.timestamp.toString());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await vm.disposeAsync();
        await database.close();
        database = await GanttDb.open('${directory.path}/client.sqlite');
        vm = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
        await vm.initialized;
        final reopened = vm.localResources.firstWhere((r) => r.id == 'tool');
        expect(reopened.type, 'tool');
        expect(reopened.name, 'Renamed crane');
        expect(reopened.isExpanded, false);
        expect(reopened.sortOrder, 21.0);
        expect(reopened.extraMetadata['custom'], {
          'rate': 3,
          'tags': ['rental', 'heavy'],
        });
      });
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await vm.disposeAsync();
        await database.close();
        await directory.delete(recursive: true);
      });
    }
  });
  test('legacy projection upgrade retains canonical resource type and unknown metadata', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('gantt-resource-upgrade-');
    final database = await GanttDb.open('${directory.path}/legacy.sqlite');
    final state = ProtocolStateStore(Future.value(database));
    const oldClock = Hlc(millis: 1000, counter: 0, nodeId: 'legacy');
    const newClock = Hlc(millis: 2000, counter: 0, nodeId: 'legacy');
    try {
      await state.applyOperations([
        Operation(
          type: 'INSERT_RESOURCE',
          data: {
            'id': 'tool',
            'name': 'Crane',
            'type': 'tool',
            'custom': {
              'rate': 3,
              'tags': ['rental', 'heavy'],
            },
            'isExpanded': true,
          },
          timestamp: oldClock,
          actorId: 'legacy',
        ),
      ]);
      final repository = LocalGanttRepository(database: Future.value(database));
      await repository.insertOrUpdateResource(
        LocalResource(id: 'tool', name: 'Legacy rename', isExpanded: false, lastUpdated: newClock),
      );
      expect(await migrateLegacyProjection(database: database, state: state, enqueue: true), 1);
      final resource = (await state.readState()).resources.single;
      expect(resource.name, 'Legacy rename');
      expect(resource.isExpanded, false);
      expect(resource.type, 'tool');
      expect(resource.extraMetadata['custom'], {
        'rate': 3,
        'tags': ['rental', 'heavy'],
      });
      expect(await migrateLegacyProjection(database: database, state: state, enqueue: true), 0);
    } finally {
      await state.close();
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
