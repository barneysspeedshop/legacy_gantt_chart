import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:async';
import 'package:example/view_models/gantt_view_model.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:example/sync/websocket_gantt_sync_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

// Mock Sync Client to inject messages
class MockSyncClient extends WebSocketGanttSyncClient {
  final StreamController<Operation> _controller = StreamController<Operation>.broadcast();

  MockSyncClient()
      : super(
          uri: Uri.parse('ws://mock'),
          channelFactory: (uri) => _MockWebSocketChannel(), // Dummy
        );

  @override
  Stream<Operation> get operationStream => _controller.stream;

  @override
  void connect(String tenantId) {
    // No-op for real connection, but we pretend we connected
  }

  void simulateOperation(String type, Map<String, dynamic> data) {
    _controller.add(Operation(
      type: type,
      data: data,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      actorId: 'test-actor',
    ));
  }
}

class _MockWebSocketChannel with StreamChannelMixin implements WebSocketChannel {
  @override
  late final Stream stream = const Stream.empty();
  @override
  late final WebSocketSink sink = _MockWebSocketSink();

  @override
  String? protocol;
  @override
  int? closeCode;
  @override
  String? closeReason;
  dynamic readyState;

  @override
  Future<void> ready = Future.value();
}

class _MockWebSocketSink implements WebSocketSink {
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done => Future.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Setup FFI for SQLite (needed because GanttViewModel initializes LocalGanttRepository)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Mock path_provider
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationSupportDirectory') {
      return Directory.systemTemp.path;
    }
    return null;
  });

  group('GanttViewModel RESET_DATA', () {
    late GanttViewModel viewModel;
    late MockSyncClient mockSyncClient;

    setUp(() async {
      viewModel = GanttViewModel();

      // Inject our mock sync client
      mockSyncClient = MockSyncClient();
      viewModel.syncClientFactory = ({required uri, required authToken}) => mockSyncClient;
      viewModel.loginFunction = ({required uri, required username, required password}) async => 'mock-token';

      // Initialize with data
      await viewModel.fetchScheduleData();

      // Connect sync (this sets up the listener)
      await viewModel.connectSync(
        uri: 'ws://mock',
        tenantId: 'test-tenant',
        username: 'user',
        password: 'pass',
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('RESET_DATA clears in-memory state', () async {
      // 1. Verify we have data initially
      expect(viewModel.ganttTasks, isNotEmpty, reason: 'Should have tasks initially');

      // 2. Simulate RESET_DATA message directly
      await viewModel.handleIncomingOperationForTesting(Operation(
        type: 'RESET_DATA',
        data: {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'test',
      ));

      // 3. No need to wait for stream, but maybe for async handling inside
      // handleIncomingOperationForTesting returns Future, so we await it.

      // 4. Verify data is cleared
      expect(viewModel.ganttTasks.length, 0, reason: 'Tasks should be cleared');
      expect(viewModel.gridData.length, 0, reason: 'Grid data should be cleared');
      expect(viewModel.dependencies.length, 0, reason: 'Dependencies should be cleared');
      expect(viewModel.conflictIndicators.length, 0, reason: 'Conflict indicators should be cleared');
    });
  });
}
