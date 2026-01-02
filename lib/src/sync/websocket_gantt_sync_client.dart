import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/json_isolate.dart';
import 'gantt_sync_client.dart';
import 'hlc.dart';

class WebSocketGanttSyncClient implements GanttSyncClient {
  final Uri uri;
  final String? authToken;
  WebSocketChannel? _channel;
  final _operationController = StreamController<Operation>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _inboundProgressController = StreamController<SyncProgress>.broadcast();
  final _outboundPendingCountController = StreamController<int>.broadcast();

  int _totalToSync = 0;
  int _processedSyncOps = 0;

  int _clockSkew = 0;
  bool _isClockSynced = false;

  String get _nodeId => 'client-${uri.hashCode}';

  WebSocketGanttSyncClient({
    required this.uri,
    this.authToken,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _channelFactory = channelFactory ?? ((uri) => WebSocketChannel.connect(uri));

  final WebSocketChannel Function(Uri) _channelFactory;

  /// Returns the current time adjusted to match the server's clock.
  /// This prevents "Time Traveler" bugs where a client with a future clock
  /// overwrites valid data.
  int get correctedTimestamp => DateTime.now().millisecondsSinceEpoch + _clockSkew;

  late Hlc _lastHlc = Hlc(millis: 0, counter: 0, nodeId: _nodeId);

  /// Helper to generate a current Hlc based on corrected time.
  /// Uses 'send' logic to ensure monotonicity and prevent collisions (counter increments).
  @override
  Hlc get currentHlc {
    final wallTime = correctedTimestamp;

    _lastHlc = _lastHlc.send(wallTime);

    return _lastHlc;
  }

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

  void connect(String tenantId, {Hlc? lastSyncedTimestamp}) {
    var finalUri = uri;
    if (authToken != null) {
      finalUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': authToken,
      });
    }

    try {
      _channel = _channelFactory(finalUri);
      _isClockSynced = false;

      _channel!.sink.add(jsonEncode({
        'type': 'subscribe',
        'channel': tenantId,
        'lastSyncedTimestamp': lastSyncedTimestamp?.toString(),
      }));

      _channel!.stream.listen(
        (message) async {
          try {
            final envelope = (await decodeJsonInBackground(message as String)) as Map<String, dynamic>;
            if (envelope.containsKey('error')) {
              print('Server error received: ${envelope['error']}');
              return;
            }

            final type = envelope['type'] as String?;
            if (type == null) {
              print('Invalid message format: missing type');
              return;
            }
            final dataMap = envelope['data'];

            if (!_isClockSynced && envelope.containsKey('timestamp')) {
              final val = envelope['timestamp'];
              int serverTime;
              if (val is int) {
                serverTime = val;
              } else if (val is String) {
                try {
                  serverTime = Hlc.parse(val).millis;
                } catch (_) {
                  serverTime = DateTime.now().millisecondsSinceEpoch;
                }
              } else {
                serverTime = DateTime.now().millisecondsSinceEpoch; // Fallback
              }

              final localTime = DateTime.now().millisecondsSinceEpoch;
              _clockSkew = serverTime - localTime;
              _isClockSynced = true;
              print('Time Sync: Local=$localTime, Server=$serverTime, Skew=$_clockSkew');
            }

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
              Hlc batchTimestamp;
              final rawTs = envelope['timestamp'];
              if (rawTs is String) {
                batchTimestamp = Hlc.parse(rawTs);
              } else if (rawTs is int) {
                batchTimestamp = Hlc(millis: rawTs, counter: 0, nodeId: 'server');
              } else {
                batchTimestamp = currentHlc;
              }

              // Update local clock using receive
              _lastHlc = _lastHlc.receive(batchTimestamp, correctedTimestamp);

              final op = Operation(
                type: 'BATCH_UPDATE',
                data: dataMap ?? {},
                timestamp: batchTimestamp,
                actorId: envelope['actorId'] as String? ?? 'unknown',
              );

              if (_totalToSync > 0 && dataMap != null && dataMap['operations'] is List) {
                final ops = dataMap['operations'] as List;
                _processedSyncOps += ops.length;
                _inboundProgressController.add(SyncProgress(processed: _processedSyncOps, total: _totalToSync));
              }

              _operationController.add(op);
              return;
            }

            if (type == 'MERKLE_ROOT') {
              if (dataMap != null && dataMap['root'] is String) {
                final root = dataMap['root'] as String;
                if (_merkleRootCompleter != null && !_merkleRootCompleter!.isCompleted) {
                  _merkleRootCompleter!.complete(root);
                }
              }
              return;
            }

            final timestamp = envelope['timestamp'];
            final actorId = envelope['actorId'];

            if (timestamp == null || actorId == null) {
              if (type == 'SUBSCRIBE_SUCCESS') {
                print('Subscription confirmed: ${envelope['channel']}');
                _connectionStateController.add(true);
              } else {
                print('Skipping message without timestamp/actorId: $type');
              }
              return;
            }

            if (_totalToSync > 0) {
              _processedSyncOps++;
              _inboundProgressController.add(SyncProgress(processed: _processedSyncOps, total: _totalToSync));
              if (_processedSyncOps >= _totalToSync) {}
            }

            var opData = dataMap != null ? dataMap as Map<String, dynamic> : <String, dynamic>{};

            if (opData.containsKey('data') && opData['data'] is Map) {
              final innerData = opData['data'] as Map<String, dynamic>;
              if (opData.containsKey('gantt_type')) {
                innerData['gantt_type'] = opData['gantt_type'];
              }
              opData = innerData;
            }

            Hlc parsedTimestamp;
            if (timestamp is String) {
              parsedTimestamp = Hlc.parse(timestamp);
            } else if (timestamp is int) {
              parsedTimestamp = Hlc(millis: timestamp, counter: 0, nodeId: actorId as String);
            } else {
              parsedTimestamp = currentHlc;
            }

            // Update local clock using receive
            _lastHlc = _lastHlc.receive(parsedTimestamp, correctedTimestamp);

            final op = Operation(
              type: type,
              data: opData,
              timestamp: parsedTimestamp,
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
          _connectionStateController.add(false);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _connectionStateController.add(false);
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

  Completer<String>? _merkleRootCompleter;

  @override
  Future<String> getMerkleRoot() async {
    if (_channel == null) {
      throw Exception('Not connected');
    }
    _merkleRootCompleter = Completer<String>();
    _channel!.sink.add(jsonEncode({
      'type': 'GET_MERKLE_ROOT',
    }));
    // Timeout after 10s
    return _merkleRootCompleter!.future.timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {
    // For now, if we detect drift, we could just log it or trigger a refresh?
    // Since buckets receive isn't implemented server-side, we can't do partial sync.
    // Ideally we would send 'REQUEST_SYNC' here.
    print('Syncing with Merkle: remoteRoot=$remoteRoot (Not fully implemented yet)');
  }

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

    final envelope = {
      'type': envelopeType,
      'data': operation.data,
      'timestamp': operation.timestamp.toString(), // HLC String
      'actorId': operation.actorId,
    };

    final encodedEnvelope = jsonEncode(envelope);
    _channel!.sink.add(encodedEnvelope);
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    if (_channel == null) {
      throw Exception('Not connected');
    }

    if (operations.isEmpty) return;

    if (operations.length == 1) {
      await sendOperation(operations.first);
      return;
    }

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
        'timestamp': operation.timestamp.toString(), // HLC String
        'actorId': operation.actorId,
      };
    }).toList();

    final batchEnvelope = {
      'type': 'BATCH_UPDATE',
      'data': {'operations': envelopes},
      'timestamp': currentHlc.toString(), // Batch timestamp HLC
      'actorId': operations.first.actorId,
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
