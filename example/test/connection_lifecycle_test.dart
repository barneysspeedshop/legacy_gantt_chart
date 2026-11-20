import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:example/data/local/gantt_db.dart';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _PassiveClient implements GanttSyncClient {
  final String actor;
  _PassiveClient(this.actor);
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
  String get actorId => actor;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final dispose in [false, true]) {
    test('${dispose ? 'dispose' : 'disconnect'} cancels a connection still awaiting login', () async {
      final directory = await Directory.systemTemp.createTemp('gantt-connect-lifecycle-');
      final database = await GanttDb.open('${directory.path}/client.sqlite');
      await database.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
        'canonical_scope',
        'local',
      ]);
      final model = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
      await model.initialized;
      final loginEntered = Completer<void>();
      final loginResult = Completer<String>();
      var clientsCreated = 0;
      model.loginFunction = ({required uri, required username, required password}) {
        loginEntered.complete();
        return loginResult.future;
      };
      model.syncClientFactory = ({required uri, required authToken}) {
        clientsCreated++;
        return _PassiveClient(authToken);
      };
      final connecting = model.connectSync(
        uri: 'http://example.test',
        tenantId: 'new-tenant',
        username: 'demo',
        password: 'demo',
      );
      await loginEntered.future;
      try {
        if (dispose) {
          await model.disposeAsync();
        } else {
          await model.disconnectSync();
        }
        loginResult.complete('delayed-login');
        await connecting;
        expect(clientsCreated, 0);
        expect(model.isSyncConnected, isFalse);
        final metadata = await database.query(
          "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
        );
        expect(metadata.single['meta_value'], 'local');
      } finally {
        if (!loginResult.isCompleted) loginResult.complete('delayed-login');
        if (!dispose) await model.disposeAsync();
        await database.close();
        await directory.delete(recursive: true);
      }
    });
  }

  test('a slower earlier login cannot replace the most recently requested tenant', () async {
    final directory = await Directory.systemTemp.createTemp('gantt-connect-order-');
    final database = await GanttDb.open('${directory.path}/client.sqlite');
    await database.execute('INSERT INTO sync_metadata (meta_key, meta_value) VALUES (?, ?)', [
      'canonical_scope',
      'local',
    ]);
    final model = GanttViewModel(database: Future.value(database), useLocalDatabase: true);
    await model.initialized;
    final firstEntered = Completer<void>();
    final firstResult = Completer<String>();
    final secondEntered = Completer<void>();
    final secondResult = Completer<String>();
    final created = <String>[];
    model.loginFunction = ({required uri, required username, required password}) {
      if (username == 'first') {
        firstEntered.complete();
        return firstResult.future;
      }
      secondEntered.complete();
      return secondResult.future;
    };
    model.syncClientFactory = ({required uri, required authToken}) {
      created.add(authToken);
      return _PassiveClient(authToken);
    };
    final first = model.connectSync(
      uri: 'http://example.test',
      tenantId: 'first-tenant',
      username: 'first',
      password: 'demo',
    );
    await firstEntered.future;
    final second = model.connectSync(
      uri: 'http://example.test',
      tenantId: 'second-tenant',
      username: 'second',
      password: 'demo',
    );
    await secondEntered.future;
    try {
      secondResult.complete('second-login');
      await second;
      firstResult.complete('first-login');
      await first;
      expect(created, ['second-login']);
      expect(model.syncClient?.actorId, 'second-login');
      expect(model.isSyncConnected, isTrue);
      final metadata = await database.query(
        "SELECT meta_value FROM sync_metadata WHERE meta_key = 'canonical_scope' AND is_deleted = 0",
      );
      expect(metadata.single['meta_value'], jsonEncode(['ws://example.test/ws', 'second-tenant']));
    } finally {
      if (!firstResult.isCompleted) firstResult.complete('first-login');
      if (!secondResult.isCompleted) secondResult.complete('second-login');
      await model.disposeAsync();
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
