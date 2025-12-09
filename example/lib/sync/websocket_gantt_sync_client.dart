import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketGanttSyncClient implements GanttSyncClient {
  final Uri uri;
  final String? authToken;
  WebSocketChannel? _channel;
  final _operationController = StreamController<Operation>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  WebSocketGanttSyncClient({
    required this.uri,
    this.authToken,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _channelFactory = channelFactory ?? ((uri) => WebSocketChannel.connect(uri));

  final WebSocketChannel Function(Uri) _channelFactory;

  // ... login method stays same ...

  static Future<String> login({
    required Uri uri,
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      uri.replace(path: '/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['accessToken'] as String;
    } else {
      throw Exception('Login failed: ${response.statusCode} - ${response.body}');
    }
  }

  void connect(String tenantId) {
    var finalUri = uri;
    if (authToken != null) {
      // Append token to query parameters for browser compatibility
      final newQueryParams = Map<String, dynamic>.from(uri.queryParameters);
      newQueryParams['token'] = authToken;
      finalUri = uri.replace(queryParameters: newQueryParams);
    }

    try {
      _channel = _channelFactory(finalUri);
      // _connectionStateController.add(true); // Don't allow send until subscribed

      // Send subscribe message immediately upon connection
      _channel!.sink.add(jsonEncode({
        'type': 'subscribe',
        'channel': tenantId,
      }));

      _channel!.stream.listen(
        (message) {
          try {
            final envelope = jsonDecode(message as String) as Map<String, dynamic>;
            final type = envelope['type'] as String;
            final dataMap = envelope['data'];

            final timestamp = envelope['timestamp'];
            final actorId = envelope['actorId'];

            if (timestamp == null || actorId == null) {
              if (type == 'SUBSCRIBE_SUCCESS') {
                print('Subscription confirmed: ${envelope['channel']}');
                _connectionStateController.add(true); // Now we are ready
              } else {
                print('Skipping message without timestamp/actorId: $type');
              }
              return;
            }

            // Construct Operation from envelope fields
            final op = Operation(
              type: type,
              data: dataMap != null ? dataMap as Map<String, dynamic> : <String, dynamic>{},
              timestamp: timestamp as int,
              actorId: actorId as String,
            );
            _operationController.add(op);
          } catch (e) {
            print('Error parsing operation: $e');
            print('Raw message was: $message');
          }
        },
        onDone: () {
          print('WebSocket connection closed');
          _connectionStateController.add(false); // Disconnected
        },
        onError: (error) {
          print('WebSocket error: $error');
          _connectionStateController.add(false); // Disconnected
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
      _connectionStateController.add(false);
      rethrow;
    }
  }

  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  Stream<Operation> get operationStream => _operationController.stream;

  @override

  /// In this simple implementation, the server sends history immediately upon connection
  /// as individual messages. So we don't fetch a snapshot explicitly.
  /// Returns empty list as stream handles history.
  Future<List<Operation>> getInitialState() async => [];

  @override
  Future<void> sendOperation(Operation operation) async {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    String envelopeType;
    if (operation.type == 'INSERT') {
      envelopeType = 'INSERT_TASK';
    } else if (operation.type == 'DELETE') {
      envelopeType = 'DELETE_TASK';
    } else if (operation.type == 'UPDATE') {
      envelopeType = 'UPDATE_TASK';
    } else {
      envelopeType = operation.type;
    }

    // Wrap operation data in envelope
    // The server expects the task data directly in the 'data' field, with 'id' at the top level
    final envelope = {
      'type': envelopeType,
      'data': operation.data, // Send operation.data directly, not the full operation
      'timestamp': operation.timestamp,
      'actorId': operation.actorId,
    };

    final encodedEnvelope = jsonEncode(envelope);
    print('WebSocketClient Sending: $encodedEnvelope');
    _channel!.sink.add(encodedEnvelope);
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
    await _operationController.close();
    await _connectionStateController.close();
  }
}
