import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
// ignore: implementation_imports
// ignore: avoid_relative_lib_imports
import '../../lib/view_models/gantt_view_model.dart';

class FakeSyncClient implements WebSocketGanttSyncClient {
  final _operationController = StreamController<Operation>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final List<Operation> sentOperations = [];
  bool isConnected = false;
  bool isDisposed = false;

  @override
  Stream<Operation> get operationStream => _operationController.stream;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  void connect(String tenantId, {int? lastSyncedTimestamp}) {
    isConnected = true;
    _connectionStateController.add(true);
  }

  @override
  Future<void> sendOperation(Operation op) async {
    sentOperations.add(op);
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    _operationController.close();
    _connectionStateController.close();
  }

  // Helper to simulate connection drop
  void simulateConnectionDrop() {
    _connectionStateController.add(false);
  }

  // Implement other members as needed (stubs)
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GanttViewModel Sync Integration', () {
    late GanttViewModel viewModel;
    late FakeSyncClient fakeClient;

    setUp(() {
      viewModel = GanttViewModel(useLocalDatabase: false); // Use memory mode
      fakeClient = FakeSyncClient();

      // Inject factories
      viewModel.loginFunction = ({required uri, required username, required password}) async {
        if (username == 'valid') return 'fake_token';
        throw Exception('Invalid credentials');
      };

      viewModel.syncClientFactory = ({required uri, required authToken}) => fakeClient;

      // Ensure no database calls are made
      // viewModel.seedLocalDatabase();
    });

    test('connectSync success', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );

      expect(viewModel.isSyncConnected, isTrue);
      expect(fakeClient.isConnected, isTrue);
    });

    test('connectSync failure', () async {
      await expectLater(
        viewModel.connectSync(
          uri: 'http://localhost:8080',
          tenantId: 'tenant1',
          username: 'invalid', // Will throw exception
          password: 'password',
        ),
        throwsException,
      );

      expect(viewModel.isSyncConnected, isFalse);
    });

    test('detects connection drop', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );

      expect(viewModel.isSyncConnected, isTrue);

      // Simulate drop
      fakeClient.simulateConnectionDrop();

      // Wait for stream to propogate
      await Future.delayed(Duration.zero);

      expect(viewModel.isSyncConnected, isFalse);
    });

    test('disconnectSync', () async {
      await viewModel.connectSync(
        uri: 'http://localhost:8080',
        tenantId: 'tenant1',
        username: 'valid',
        password: 'password',
      );

      // FIX: Add await here
      await viewModel.disconnectSync();

      expect(viewModel.isSyncConnected, isFalse);
      expect(fakeClient.isDisposed, isTrue);
    });

    // Note: To test handleTaskUpdate sending operations, we need to ensure the task exists.
    // Since seedLocalDatabase populates data asynchronously or via method, we need to ensure it's ready.
    // However, in mock mode, it uses _apiResponse.
  });
}
