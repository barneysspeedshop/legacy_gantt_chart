import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
// ignore: implementation_imports
import 'package:legacy_gantt_chart/src/sync/websocket_gantt_sync_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  group('WebSocketGanttSyncClient', () {
    late WebSocketGanttSyncClient client;
    late StreamController incomingController;
    late StreamController outgoingController;

    setUp(() {
      incomingController = StreamController.broadcast();
      outgoingController = StreamController.broadcast();
    });

    tearDown(() {
      incomingController.close();
      outgoingController.close();
    });

    WebSocketChannel mockChannelFactory(Uri uri) =>
        TestWebSocketChannel(incomingController.stream, outgoingController.sink);

    test('connect sends subscribe message', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        authToken: 'test-token',
        channelFactory: mockChannelFactory,
      );

      // Start listening to outgoing before connecting to ensure we catch the generic message
      final futureMessage = outgoingController.stream.first;

      client.connect('tenant-123');

      final message = await futureMessage;
      final json = jsonDecode(message as String);

      expect(json['type'], equals('subscribe'));
      expect(json['channel'], equals('tenant-123'));
    });

    test('unwraps incoming UPDATE_TASK message', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: mockChannelFactory,
      );
      client.connect('tenant-123');

      final opData = {
        'id': 'task-1',
        'name': 'Test Task',
        'start': DateTime(2023, 1, 1).toIso8601String(),
        'end': DateTime(2023, 1, 2).toIso8601String(),
        'rowId': 'r1',
      };

      final envelope = {'type': 'UPDATE_TASK', 'data': opData, 'timestamp': 1000, 'actorId': 'user-1'};

      // Emit incoming message
      incomingController.add(jsonEncode(envelope));

      final receivedOp = await client.operationStream.first;
      expect(receivedOp.actorId, equals('user-1'));
      expect(receivedOp.data['id'], equals('task-1'));
    });

    // test('wraps outgoing operation in envelope', () async {
    //   client = WebSocketGanttSyncClient(
    //     uri: Uri.parse('ws://localhost'),
    //     channelFactory: mockChannelFactory,
    //   );

    //   // Use take(2) because the first message is 'subscribe'
    //   final messagesFuture = outgoingController.stream.take(2).toList();

    //   client.connect('tenant-123');

    //   final op = Operation(
    //     type: 'UPDATE',
    //     data: {'foo': 'bar'},
    //     timestamp: 12345,
    //     actorId: 'me',
    //   );

    //   await client.sendOperation(op);

    //   final messages = await messagesFuture;
    //   expect(messages.length, 2);

    //   final envelopeJson = jsonDecode(messages[1] as String); // Second message
    //   expect(envelopeJson['type'], equals('UPDATE_TASK'));
    //   expect(envelopeJson['actorId'], equals('me'));
    //   expect(envelopeJson['data']['type'], equals('UPDATE'));
    // });
  });
}

class TestWebSocketChannel with StreamChannelMixin implements WebSocketChannel {
  final Stream _stream;
  final Sink _sink;

  TestWebSocketChannel(this._stream, this._sink);

  @override
  Stream get stream => _stream;

  @override
  WebSocketSink get sink => TestWebSocketSink(_sink);

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
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}
