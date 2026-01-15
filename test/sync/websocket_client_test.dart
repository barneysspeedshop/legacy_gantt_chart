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

    tearDown(() async {
      incomingController.close();
      outgoingController.close();
      try {
        await client.dispose();
      } catch (_) {}
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

    test('connect sends token in query and subscribe message', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        authToken: 'test-token',
        channelFactory: (uri) {
          expect(uri.queryParameters['token'], equals('test-token'));
          return mockChannelFactory(uri);
        },
      );

      // Start listening to outgoing before connecting
      // Expect 1 message: subscribe (auth is in handshake)
      // 1. Subscribe Message (Auth verified in handshake)
      final subMsgFuture = expectLater(outgoingController.stream, emits(predicate((subMsg) {
        final subJson = jsonDecode(subMsg as String);
        return subJson['type'] == 'subscribe' && subJson['channel'] == 'tenant-123';
      })));

      client.connect('tenant-123');

      await subMsgFuture;
    });

    test('preserves gantt_type in unwrapped UPDATE_TASK message', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: mockChannelFactory,
      );
      client.connect('tenant-123');

      final innerData = {
        'id': 'task-1',
        'name': 'Test Task',
      };

      // Server sends data wrapped with sibling gantt_type
      final serverData = {
        'data': innerData,
        'gantt_type': 'milestone',
      };

      final envelope = {
        'type': 'UPDATE_TASK',
        'data': serverData,
        'timestamp': Hlc.fromIntTimestamp(1000).toString(),
        'actorId': 'user-1'
      };

      // Emit incoming message
      incomingController.add(jsonEncode(envelope));

      final receivedOp = await client.operationStream.first;
      expect(receivedOp.type, 'UPDATE_TASK');
      expect(receivedOp.data['id'], equals('task-1'));
      expect(receivedOp.data['gantt_type'], equals('milestone'));
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

      final envelope = {
        'type': 'UPDATE_TASK',
        'data': opData,
        'timestamp': Hlc.fromIntTimestamp(1000).toString(),
        'actorId': 'user-1'
      };

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
        authToken: 'test-token',
        channelFactory: mockChannelFactory,
      );

      // Use take(2) because messages are: subscribe, operation
      final messagesFuture = outgoingController.stream.take(2).toList();

      client.connect('tenant-123');

      final op = Operation(
        type: 'UPDATE',
        data: {'foo': 'bar'},
        timestamp: Hlc.fromIntTimestamp(12345),
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
        authToken: 'test-token',
        channelFactory: mockChannelFactory,
      );
      final messagesFuture = outgoingController.stream.take(2).toList();
      client.connect('tenant-123');

      final op = Operation(type: 'INSERT', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'me');
      await client.sendOperation(op);

      final messages = await messagesFuture;
      final envelope = jsonDecode(messages[1] as String);
      expect(envelope['type'], 'INSERT_TASK');
    });

    test('wraps DELETE operation correctly', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        authToken: 'test-token',
        channelFactory: mockChannelFactory,
      );
      final messagesFuture = outgoingController.stream.take(2).toList();
      client.connect('tenant-123');

      final op = Operation(type: 'DELETE', data: {}, timestamp: Hlc.fromIntTimestamp(1), actorId: 'me');
      await client.sendOperation(op);

      final messages = await messagesFuture;
      final envelope = jsonDecode(messages[1] as String);
      expect(envelope['type'], 'DELETE_TASK');
    });

    test('currentHlc produces monotonic timestamps', () async {
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        authToken: 'test-token',
        channelFactory: mockChannelFactory,
      );
      // Wait for initial sync/connect logic if any (none required for currentHlc access)

      final hlc1 = client.currentHlc;
      final hlc2 = client.currentHlc;
      final hlc3 = client.currentHlc;

      // Check strict ordering
      expect(hlc1 < hlc2, isTrue, reason: 'HLC1 should be less than HLC2');
      expect(hlc2 < hlc3, isTrue, reason: 'HLC2 should be less than HLC3');

      // Check logic: if time didn't advance, counter should increment
      if (hlc1.millis == hlc2.millis) {
        expect(hlc2.counter, equals(hlc1.counter + 1));
      }
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
