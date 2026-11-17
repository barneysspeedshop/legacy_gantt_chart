import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'package:legacy_gantt_chart/src/sync/websocket_gantt_sync_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

// Minimal implementation of WebSocketChannel for testing
class TestWebSocketChannel with StreamChannelMixin implements WebSocketChannel {
  final StreamController _incomingController;
  final StreamController _outgoingController;

  TestWebSocketChannel(this._incomingController, this._outgoingController);

  @override
  Stream get stream => _incomingController.stream;

  @override
  WebSocketSink get sink => TestWebSocketSink(_outgoingController.sink);

  @override
  String? protocol;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Future get ready => Future.value();
}

class TestWebSocketSink implements WebSocketSink {
  final Sink _sink;
  TestWebSocketSink(this._sink);

  @override
  void add(dynamic data) {
    _sink.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // no-op or forward
  }

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done => Future.value();
}

void main() {
  group('Batch Update Test', () {
    late StreamController incomingController;
    late StreamController outgoingController;
    late WebSocketGanttSyncClient client;

    setUp(() {
      incomingController = StreamController.broadcast();
      // Outgoing is NOT broadcast by default if we want to listen to it once?
      // But TestWebSocketChannel uses it as a sink.
      // Let's use broadcast so we can listen multiple times if needed, or just StreamController.
      outgoingController = StreamController.broadcast();

      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost:8080/ws'),
        channelFactory: (uri) => TestWebSocketChannel(incomingController, outgoingController),
      );
    });

    tearDown(() async {
      await client.dispose();
      incomingController.close();
      outgoingController.close();
    });

    test('sendOperations sends BATCH_UPDATE message verification', () async {
      // Setup listener
      final batchMessage = outgoingController.stream
          .map((frame) => ProtocolMessage.fromBuffer(frame as List<int>))
          .firstWhere((message) => message.type == 'BATCH_UPDATE');

      client.connect('test_tenant');
      // Should have 'subscribe'

      final ops = [
        Operation(type: 'INSERT_TASK', data: {'id': '1'}, timestamp: Hlc.fromIntTimestamp(100), actorId: 'user1'),
        Operation(type: 'UPDATE_TASK', data: {'id': '2'}, timestamp: Hlc.fromIntTimestamp(101), actorId: 'user1'),
      ];

      await client.sendOperations(ops);

      final decoded = ProtobufMapper.toJson(await batchMessage);
      expect(decoded['type'], 'BATCH_UPDATE');
      final operations = decoded['data']['operations'] as List;
      expect(operations, hasLength(2));
      expect(operations[0]['data']['id'], '1');
      expect(operations[1]['data']['id'], '2');
      expect(operations[0]['type'], 'UPDATE_TASK');
      expect(operations[1]['type'], 'UPDATE_TASK');
    });

    test('receiving BATCH_UPDATE emits single batch operation', () async {
      client.connect('test_tenant');

      final updateOps = <Operation>[];
      final sub = client.operationStream.listen((op) => updateOps.add(op));

      final batchMsg = ProtobufMapper.toProtobuf({
        'type': 'BATCH_UPDATE',
        'data': {
          'operations': [
            {
              'type': 'INSERT_TASK',
              'data': {'id': '1'},
              'timestamp': Hlc.fromIntTimestamp(100).toString(),
              'actorId': 'server'
            },
            {
              'type': 'UPDATE_TASK',
              'data': {'id': '2'},
              'timestamp': Hlc.fromIntTimestamp(101).toString(),
              'actorId': 'server'
            },
          ]
        },
        'timestamp': Hlc.fromIntTimestamp(200).toString(),
        'actorId': 'server'
      }).writeToBuffer();

      incomingController.add(batchMsg);

      // Wait for stream processing
      await Future.delayed(const Duration(milliseconds: 10));

      expect(updateOps, hasLength(1));
      expect(updateOps[0].type, 'BATCH_UPDATE');
      expect(updateOps[0].data['operations'], hasLength(2));

      final opsList = updateOps[0].data['operations'] as List;
      expect(opsList[0]['type'], 'UPDATE_TASK');
      expect(opsList[0]['data']['id'], '1');
      expect(opsList[1]['data']['id'], '2');
      expect(opsList[1]['type'], 'UPDATE_TASK');

      await sub.cancel();
    });
  });
}
