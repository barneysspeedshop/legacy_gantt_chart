import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/data/local/persisted_gantt_sync_client.dart';
import 'package:example/data/local/protocol_state_store.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:legacy_gantt_chart/offline_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _PausedPersistence extends PersistedGanttSyncClient {
  final entered = Completer<void>();
  final release = Completer<void>();

  _PausedPersistence(super.db, {required super.protocolState});

  @override
  Future<void> persistOperations(List<Operation> operations) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.persistOperations(operations);
  }
}

class _PassiveClient implements GanttSyncClient {
  @override
  Stream<Operation> get operationStream => const Stream.empty();
  @override
  Future<void> sendOperation(Operation operation) async {}
  @override
  Future<void> sendOperations(List<Operation> operations) async {}
  @override
  Future<List<Operation>> getInitialState() async => [];
  @override
  Stream<int> get outboundPendingCount => Stream.value(0);
  @override
  Stream<SyncProgress> get inboundProgress => const Stream.empty();
  @override
  Future<String> getMerkleRoot() async => '';
  @override
  Future<void> syncWithMerkle({required MerkleTree localTree}) async {}
  @override
  Hlc get currentHlc => Hlc.fromIntTimestamp(1);
  @override
  String get actorId => 'passive';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a tenant switch cannot overtake a local commit awaiting persistence', () async {
    final directory = await Directory.systemTemp.createTemp('gantt-scope-race-');
    final database = await GanttDb.open('${directory.path}/client.sqlite');
    final originalScope = jsonEncode(['ws://example.test/ws', 'original-tenant']);
    await database.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
      'canonical_scope',
      originalScope,
    ]);
    final model = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
    await model.initialized;
    await (model.syncClient as OfflineGanttSyncClient).dispose();
    final state = ProtocolStateStore(Future.value(database), scope: originalScope);
    final client = _PausedPersistence(Future.value(database), protocolState: () => state);
    model.setSyncClient(client);
    var clientsCreated = 0;
    model.loginFunction = ({required uri, required username, required password}) async => 'test-token';
    model.syncClientFactory = ({required uri, required authToken}) {
      clientsCreated++;
      return _PassiveClient();
    };
    final edit = model.addTask(
      LegacyGanttTask(
        id: 'original-tenant-task',
        rowId: 'row',
        name: 'Must stay in original tenant',
        start: DateTime.utc(2026, 11, 20),
        end: DateTime.utc(2026, 11, 21),
      ),
    );
    await client.entered.future;
    final switching = model.connectSync(
      uri: 'http://example.test',
      tenantId: 'other-tenant',
      username: 'demo',
      password: 'demo',
    );
    final rejected = expectLater(
      switching,
      throwsA(isA<StateError>().having((error) => error.message, 'message', contains('original tenant'))),
    );
    try {
      // Give the switch a chance to reach its queue check while persistence is paused.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      client.release.complete();
      await edit;
      await rejected;
      expect(clientsCreated, 0);
      final metadata = await database.query(
        "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
      );
      expect(metadata.single['meta_value'], originalScope);
      final pending = await database.query('SELECT type, data FROM offline_queue WHERE is_deleted = 0');
      expect(pending, hasLength(1));
      expect(pending.single['type'], 'INSERT_TASK');
      expect(jsonDecode(pending.single['data'] as String)['id'], 'original-tenant-task');
    } finally {
      if (!client.release.isCompleted) client.release.complete();
      await edit;
      await model.disposeAsync();
      await state.close();
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
