import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
// ignore: implementation_imports
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:http/http.dart' as http;

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

    test('login success returns token', () async {
      final mockClient = MockHttpClient((request) async => http.Response('{"accessToken": "fake-token"}', 200));

      final token = await WebSocketGanttSyncClient.login(
        uri: Uri.parse('http://localhost'),
        username: 'user',
        password: 'pass',
        client: mockClient,
      );

      expect(token, equals('fake-token'));
    });

    test('login failure throws exception', () async {
      final mockClient = MockHttpClient((request) async => http.Response('Unauthorized', 401));

      expect(
        () => WebSocketGanttSyncClient.login(
          uri: Uri.parse('http://localhost'),
          username: 'user',
          password: 'pass',
          client: mockClient,
        ),
        throwsException,
      );
    });

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
      expect(receivedOp.type, 'UPDATE_TASK');
      expect(receivedOp.actorId, equals('user-1'));
      expect(receivedOp.data['id'], equals('task-1'));
    });

    test('updates connection state on subscribe success', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: mockChannelFactory,
      );

      expectLater(client.connectionStateStream, emitsInOrder([true]));

      client.connect('tenant-123');

      final envelope = {'type': 'SUBSCRIBE_SUCCESS', 'channel': 'tenant-123'};
      incomingController.add(jsonEncode(envelope));
    });

    test('wraps outgoing operation in envelope', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: mockChannelFactory,
      );

      // Use take(2) because the first message is 'subscribe'
      final messagesFuture = outgoingController.stream.take(2).toList();

      client.connect('tenant-123');

      final op = Operation(
        type: 'UPDATE',
        data: {'foo': 'bar'},
        timestamp: 12345,
        actorId: 'me',
      );

      await client.sendOperation(op);

      final messages = await messagesFuture;
      expect(messages.length, 2);

      final envelopeJson = jsonDecode(messages[1] as String); // Second message
      expect(envelopeJson['type'], equals('UPDATE_TASK'));
      expect(envelopeJson['actorId'], equals('me'));
      expect(envelopeJson['data']['foo'], equals('bar'));
    });

    test('wraps INSERT operation correctly', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: mockChannelFactory,
      );
      final messagesFuture = outgoingController.stream.take(2).toList();
      client.connect('tenant-123');

      final op = Operation(type: 'INSERT', data: {}, timestamp: 1, actorId: 'me');
      await client.sendOperation(op);

      final messages = await messagesFuture;
      final envelope = jsonDecode(messages[1] as String);
      expect(envelope['type'], 'INSERT_TASK');
    });

    test('wraps DELETE operation correctly', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: mockChannelFactory,
      );
      final messagesFuture = outgoingController.stream.take(2).toList();
      client.connect('tenant-123');

      final op = Operation(type: 'DELETE', data: {}, timestamp: 1, actorId: 'me');
      await client.sendOperation(op);

      final messages = await messagesFuture;
      final envelope = jsonDecode(messages[1] as String);
      expect(envelope['type'], 'DELETE_TASK');
    });
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

class MockHttpClient extends Fake implements http.Client {
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  MockHttpClient(this._handler);

  @override
  Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final request = http.Request('POST', url);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      }
    }
    return _handler(request);
  }

  @override
  void close() {}
}
