import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'gantt_sync_client.dart';

class WebSocketGanttSyncClient implements GanttSyncClient {
  final Uri uri;
  final String? authToken;
  WebSocketChannel? _channel;
  final _operationController = StreamController<Operation>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _inboundProgressController = StreamController<SyncProgress>.broadcast();
  final _outboundPendingCountController = StreamController<int>.broadcast();

  // Progress tracking state
  int _totalToSync = 0;
  int _processedSyncOps = 0;

  WebSocketGanttSyncClient({
    required this.uri,
    this.authToken,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _channelFactory = channelFactory ?? ((uri) => WebSocketChannel.connect(uri)) {
    // WebSocket client sends immediately, so pending count is effectively 0 (or ephemeral)
    // We can emit 0 initially.
    // Use Timer.run to emit after listen? Or just lazily.
    // For now we just emit 0 when listened to via onListen if we want, or just let it be.
  }

  final WebSocketChannel Function(Uri) _channelFactory;

  static Future<String> login({
    required Uri uri,
    required String username,
    required String password,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.post(
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
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  void connect(String tenantId, {int? lastSyncedTimestamp}) {
    // Append token to URL for handshake verification
    var finalUri = uri;
    if (authToken != null) {
      finalUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': authToken,
      });
    }

    try {
      _channel = _channelFactory(finalUri);

      // No longer sending 'auth' message explicitly.
      // Handshake handles it.

      // Send subscribe message immediately (will be processed after auth)
      _channel!.sink.add(jsonEncode({
        'type': 'subscribe', // ProtocolMessage.subscribe
        'channel': tenantId,
        'lastSyncedTimestamp': lastSyncedTimestamp,
      }));

      _channel!.stream.listen(
        (message) {
          try {
            final envelope = jsonDecode(message as String) as Map<String, dynamic>;
            final type = envelope['type'] as String;
            final dataMap = envelope['data'];

            if (type == 'SYNC_METADATA') {
              if (dataMap != null) {
                _totalToSync = dataMap['totalOperations'] as int? ?? 0;
                _processedSyncOps = 0;
                print('Sync Metadata received: total=$_totalToSync');
                _inboundProgressController.add(SyncProgress(processed: 0, total: _totalToSync));
              }
              return;
            }

            if (type == 'BATCH_UPDATE') {
              // OPTIMIZATION: Emit BATCH_UPDATE as a single operation so the UI can process it in bulk
              // instead of receiving hundreds of individual updates that trigger repaints.
              final op = Operation(
                type: 'BATCH_UPDATE',
                data: dataMap ?? {},
                timestamp: envelope['timestamp'] != null
                    ? envelope['timestamp'] as int
                    : DateTime.now().millisecondsSinceEpoch,
                actorId: envelope['actorId'] as String? ?? 'unknown',
              );
              _operationController.add(op);
              return;
            }

            // Normal single operation logic
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

            // Increment progress if we are in a sync phase (total > 0)
            // We assume ops coming after SYNC_METADATA are part of the sync until we reach total
            if (_totalToSync > 0) {
              _processedSyncOps++;
              _inboundProgressController.add(SyncProgress(processed: _processedSyncOps, total: _totalToSync));
              // Optimization: Maybe don't emit every single op if high volume?
              // But for now correct logic is fine.
              if (_processedSyncOps >= _totalToSync) {
                // Reset or keep at 100%?
                // Let's keep it until next sync starts.
              }
            }

            // Construct Operation from envelope fields
            var opData = dataMap != null ? dataMap as Map<String, dynamic> : <String, dynamic>{};

            // Auto-unwrap 'data' wrapper if present (Server sends {'data': {'id':...}})
            // This ensures CRDTEngine and other consumers get flat data
            if (opData.containsKey('data') && opData['data'] is Map) {
              final innerData = opData['data'] as Map<String, dynamic>;
              if (opData.containsKey('gantt_type')) {
                innerData['gantt_type'] = opData['gantt_type'];
              }
              opData = innerData;
            }

            final op = Operation(
              type: type,
              data: opData,
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
  Stream<int> get outboundPendingCount => Stream.value(0).asBroadcastStream();

  @override
  Stream<SyncProgress> get inboundProgress => _inboundProgressController.stream;

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

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    if (operations.isEmpty) return;

    // OPTIMIZATION: If only one operation, send it directly to avoid batch overhead
    if (operations.length == 1) {
      await sendOperation(operations.first);
      return;
    }

    // Convert operations to envelopes
    final envelopes = operations.map((operation) {
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

      return {
        'type': envelopeType,
        'data': operation.data,
        'timestamp': operation.timestamp,
        'actorId': operation.actorId,
      };
    }).toList();

    final batchEnvelope = {
      'type': 'BATCH_UPDATE',
      'data': {'operations': envelopes},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'actorId': operations.first.actorId, // Use first actor or generic
    };

    final encodedEnvelope = jsonEncode(batchEnvelope);
    print('WebSocketClient Sending Batch: ${operations.length} ops');
    _channel!.sink.add(encodedEnvelope);
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
    await _operationController.close();
    await _connectionStateController.close();
    await _inboundProgressController.close();
    await _outboundPendingCountController.close();
  }
}
