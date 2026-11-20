import 'dart:convert';
import 'dart:async';

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
      final subMsgFuture = expectLater(
        outgoingController.stream,
        emits(
          predicate((subMsg) {
            final subJson = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(subMsg as List<int>));
            return subJson['type'] == 'subscribe' && subJson['channel'] == 'tenant-123';
          }),
        ),
      );

      client.connect('tenant-123');

      await subMsgFuture;
    });

    test('Merkle root requests ignore broadcasts and correlate serialized responses', () async {
      client = WebSocketGanttSyncClient(uri: Uri.parse('ws://localhost'), channelFactory: mockChannelFactory);
      client.connect('tenant-123');
      final requests = <Map<String, dynamic>>[];
      final subscription = outgoingController.stream.listen((message) {
        final envelope = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(message as List<int>));
        if (envelope['type'] == 'GET_MERKLE_ROOT') requests.add(envelope);
      });
      addTearDown(subscription.cancel);
      var firstDone = false;
      final first = client.getMerkleRoot().then((value) {
        firstDone = true;
        return value;
      });
      final second = client.getMerkleRoot();
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
      void response(String root, [String? channel]) {
        incomingController.add(
          ProtobufMapper.toProtobuf({
            'type': 'MERKLE_ROOT',
            'data': {'root': root},
            'channel': ?channel,
          }).writeToBuffer(),
        );
      }

      response('broadcast-root');
      response('wrong-request-root', 'other-request');
      await Future<void>.delayed(Duration.zero);
      expect(firstDone, false);
      response('committed-root', requests.first['channel'] as String);
      expect(await first, 'committed-root');
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(2));
      expect(requests[1]['channel'], isNot(requests[0]['channel']));
      response('second-committed-root', requests[1]['channel'] as String);
      expect(await second, 'second-committed-root');
    });

    test('Merkle traversal retrieves missing server tasks from minute leaves', () async {
      client = WebSocketGanttSyncClient(uri: Uri.parse('ws://localhost'), channelFactory: mockChannelFactory);
      final timestamp = Hlc.fromDate(DateTime.utc(2026, 11, 20, 12, 34), 'server');
      final remoteTree = MerkleTree.build([MapEntry(timestamp.toString(), MerkleTree.hash('server-only-task'))]);
      final requestedRanges = <String>[];
      void respond(Map<String, dynamic> envelope) {
        incomingController.add(ProtobufMapper.toProtobuf(envelope).writeToBuffer());
      }

      final subscription = outgoingController.stream.listen((message) {
        final request = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(message as List<int>));
        final data = request['data'] as Map<String, dynamic>? ?? {};
        if (request['type'] == 'GET_MERKLE_ROOT') {
          respond({
            'type': 'MERKLE_ROOT',
            'channel': request['channel'],
            'data': {'root': remoteTree.root.hash},
          });
        } else if (request['type'] == 'GET_MERKLE_NODE') {
          final prefix = data['prefix'] as String;
          respond({
            'type': 'MERKLE_NODE',
            'data': {
              'prefix': prefix,
              'children': remoteTree.getNode(prefix)?.children.map((key, node) => MapEntry(key, node.hash)) ?? {},
            },
          });
        } else if (request['type'] == 'GET_ENTITIES_IN_RANGE') {
          final prefix = data['prefix'] as String;
          requestedRanges.add(prefix);
          respond({
            'type': 'BATCH_UPDATE',
            'channel': request['channel'],
            'timestamp': timestamp.toString(),
            'data': {
              'operations': [
                Operation(
                  type: 'UPDATE_TASK',
                  data: {'id': 'server-only-task', 'name': 'Recovered'},
                  timestamp: timestamp,
                  actorId: 'server',
                ).toJson(),
              ],
            },
          });
        }
      });
      addTearDown(subscription.cancel);
      client.connect('tenant-123');
      final recovered = client.operationStream.firstWhere((operation) => operation.type == 'BATCH_UPDATE');
      await client.syncWithMerkle(localTree: MerkleTree.build([]));
      final batch = await recovered;
      expect(requestedRanges, ['2026-11-20T12:34']);
      final operations = batch.data['operations'] as List;
      expect((operations.single as Map)['data']['id'], 'server-only-task');
      expect((operations.single as Map)['data']['name'], 'Recovered');
    });

    test('failed traversal discards abandoned ranges before retry', () async {
      var failSecondDay = true;
      final requestedRanges = <String>[];
      final remoteTree = MerkleTree.build([
        MapEntry(Hlc.fromDate(DateTime.utc(2026, 11, 20, 12, 34), 'server').toString(), MerkleTree.hash('first')),
        MapEntry(Hlc.fromDate(DateTime.utc(2026, 11, 21, 12, 34), 'server').toString(), MerkleTree.hash('second')),
      ]);
      client = WebSocketGanttSyncClient(
        uri: Uri.parse('ws://localhost'),
        channelFactory: (_) => TestWebSocketChannel(
          incomingController.stream,
          _CallbackSink((message) {
            final request = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(message as List<int>));
            if (failSecondDay &&
                request['type'] == 'GET_MERKLE_NODE' &&
                (request['data'] as Map)['prefix'] == '2026-11-21') {
              throw StateError('injected traversal failure');
            }
            outgoingController.add(message);
          }),
        ),
      );
      void respond(Map<String, dynamic> response) {
        incomingController.add(ProtobufMapper.toProtobuf(response).writeToBuffer());
      }

      final subscription = outgoingController.stream.listen((message) {
        final request = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(message as List<int>));
        final data = request['data'] as Map<String, dynamic>? ?? {};
        if (request['type'] == 'GET_MERKLE_ROOT') {
          respond({
            'type': 'MERKLE_ROOT',
            'channel': request['channel'],
            'data': {'root': remoteTree.root.hash},
          });
        } else if (request['type'] == 'GET_MERKLE_NODE') {
          final prefix = data['prefix'] as String;
          respond({
            'type': 'MERKLE_NODE',
            'data': {
              'prefix': prefix,
              'children': remoteTree.getNode(prefix)?.children.map((key, node) => MapEntry(key, node.hash)) ?? {},
            },
          });
        } else if (request['type'] == 'GET_ENTITIES_IN_RANGE') {
          requestedRanges.add(data['prefix'] as String);
          if (!failSecondDay) {
            respond({
              'type': 'BATCH_UPDATE',
              'channel': request['channel'],
              'data': {'operations': []},
            });
          }
        }
      });
      addTearDown(subscription.cancel);
      client.connect('tenant-123');
      await expectLater(client.syncWithMerkle(localTree: MerkleTree.build([])), throwsStateError);
      expect(requestedRanges, ['2026-11-20T12:34']);
      failSecondDay = false;
      await client.syncWithMerkle(localTree: MerkleTree.build([])).timeout(const Duration(seconds: 1));
      expect(requestedRanges, ['2026-11-20T12:34', '2026-11-20T12:34', '2026-11-21T12:34']);
    });

    test('preserves gantt_type in unwrapped UPDATE_TASK message', () async {
      client = WebSocketGanttSyncClient(uri: Uri.parse('ws://localhost'), channelFactory: mockChannelFactory);
      client.connect('tenant-123');

      final innerData = {'id': 'task-1', 'name': 'Test Task'};

      // Server sends data wrapped with sibling gantt_type
      final serverData = {'data': innerData, 'gantt_type': 'milestone'};

      final envelope = {
        'type': 'UPDATE_TASK',
        'data': serverData,
        'timestamp': Hlc.fromIntTimestamp(1000).toString(),
        'actorId': 'user-1',
      };

      // Emit incoming message
      incomingController.add(ProtobufMapper.toProtobuf(envelope).writeToBuffer());

      final receivedOp = await client.operationStream.first;
      expect(receivedOp.type, 'UPDATE_TASK');
      expect(receivedOp.data['id'], equals('task-1'));
      expect(receivedOp.data['gantt_type'], equals('milestone'));
    });

    test('unwraps incoming UPDATE_TASK message', () async {
      client = WebSocketGanttSyncClient(uri: Uri.parse('ws://localhost'), channelFactory: mockChannelFactory);
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
        'actorId': 'user-1',
      };

      // Emit incoming message
      incomingController.add(ProtobufMapper.toProtobuf(envelope).writeToBuffer());

      final receivedOp = await client.operationStream.first;
      expect(receivedOp.type, 'UPDATE_TASK');
      expect(receivedOp.actorId, equals('user-1'));
      expect(receivedOp.data['id'], equals('task-1'));
    });

    test('updates connection state on subscribe success', () async {
      client = WebSocketGanttSyncClient(uri: Uri.parse('ws://localhost'), channelFactory: mockChannelFactory);

      expectLater(client.connectionStateStream, emitsInOrder([true]));

      client.connect('tenant-123');

      final envelope = {'type': 'SUBSCRIBE_SUCCESS', 'channel': 'tenant-123'};
      incomingController.add(ProtobufMapper.toProtobuf(envelope).writeToBuffer());
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
        data: {'id': 'task-1', 'name': 'Changed task'},
        timestamp: Hlc.fromIntTimestamp(12345),
        actorId: 'me',
      );

      await client.sendOperation(op);

      final messages = await messagesFuture;
      expect(messages.length, 2);

      final envelopeJson = ProtobufMapper.toJson(
        ProtocolMessage.fromBuffer(messages[1] as List<int>),
      ); // Second message
      expect(envelopeJson['type'], equals('UPDATE_TASK'));
      expect(envelopeJson['actorId'], equals('me'));
      expect(envelopeJson['data']['id'], equals('task-1'));
      expect(envelopeJson['data']['name'], equals('Changed task'));
      expect(messages[1], isA<List<int>>());
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
      final envelope = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(messages[1] as List<int>));
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
      final envelope = ProtobufMapper.toJson(ProtocolMessage.fromBuffer(messages[1] as List<int>));
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

class _CallbackSink implements Sink<dynamic> {
  final void Function(dynamic) onAdd;
  _CallbackSink(this.onAdd);
  @override
  void add(dynamic value) => onAdd(value);
  @override
  void close() {}
}
