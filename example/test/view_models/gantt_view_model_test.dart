// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../lib/view_models/gantt_view_model.dart';
import '../../lib/data/local/gantt_db.dart';
import '../../lib/data/local/local_gantt_repository.dart';

class MockWebSocketClient extends WebSocketGanttSyncClient {
  int? capturedLastSynced;

  MockWebSocketClient({required super.uri, required super.authToken});

  @override
  void connect(String tenantId, {int? lastSyncedTimestamp}) {
    capturedLastSynced = lastSyncedTimestamp;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('GanttViewModel passes lastSynced to client', () async {
    // Setup DB
    GanttDb.overridePath = ':memory:';
    await GanttDb.reset();

    // Pre-populate DB with a timestamp
    final repo = LocalGanttRepository();
    await repo.init();
    const expectedTs = 123456789;
    await repo.setLastServerSyncTimestamp(expectedTs);

    // Setup ViewModel
    final vm = GanttViewModel(useLocalDatabase: true);

    // Setup Mock Client
    final mockClient = MockWebSocketClient(uri: Uri.parse('ws://mock'), authToken: 'token');

    vm.syncClientFactory = ({required uri, required authToken}) => mockClient;
    vm.loginFunction = ({required uri, required username, required password}) async => 'mock_token';

    // Connect
    await vm.connectSync(
      uri: 'http://mock',
      tenantId: 'tenant',
      username: 'user',
      password: 'pass',
    );

    // Verify
    expect(mockClient.capturedLastSynced, equals(expectedTs));
  });
}
