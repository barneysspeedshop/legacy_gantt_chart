import 'dart:async';
import 'dart:convert';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:synchronized/synchronized.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import '../data/local/gantt_db.dart';
import 'websocket_gantt_sync_client.dart';

class OfflineGanttSyncClient implements GanttSyncClient {
  WebSocketGanttSyncClient? _innerClient;
  final _connectionStateController = StreamController<bool>.broadcast();
  final _operationController = StreamController<Operation>.broadcast();
  late SqliteCrdt _db;
  bool _isDbReady = false;
  bool _isConnected = false;
  final _lock = Lock();
  StreamSubscription? _innerConnectionSubscription;
  StreamSubscription? _innerOperationSubscription;
  Future<void>? _activeFlushFuture;

  late Future<void> _dbInitFuture;

  OfflineGanttSyncClient([this._innerClient]) {
    _dbInitFuture = _initDb();
    if (_innerClient != null) {
      _attachInnerClient(_innerClient!);
    } else {
      // Start in disconnected state
      _connectionStateController.add(false);
    }
  }

  Future<void> setInnerClient(WebSocketGanttSyncClient client) async {
    if (_innerClient == client) return;
    await _detachInnerClient();
    _innerClient?.dispose(); // Close previous connection
    _innerClient = client;
    _attachInnerClient(client);
  }

  Future<void> removeInnerClient() async {
    await _detachInnerClient();
    await _innerClient?.dispose();
    _innerClient = null;
    _isConnected = false;
    _connectionStateController.add(false);
  }

  void _attachInnerClient(WebSocketGanttSyncClient client) {
    _innerConnectionSubscription = client.connectionStateStream.listen((isConnected) {
      print('OfflineClient: Connection state changed to $isConnected');
      _isConnected = isConnected;
      _connectionStateController.add(isConnected);
      if (isConnected) {
        print('OfflineClient: Connected, triggering flush...');
        _flushQueue();
      }
    });

    _innerOperationSubscription = client.operationStream.listen((op) {
      _operationController.add(op);
    });
  }

  Future<void> _detachInnerClient() async {
    await _innerConnectionSubscription?.cancel();
    _innerConnectionSubscription = null;
    await _innerOperationSubscription?.cancel();
    _innerOperationSubscription = null;
    _isConnected = false;
  }

  Future<void> _initDb() async {
    try {
      final db = await GanttDb.db;
      _db = db;
      print('OfflineClient: GanttDb initialized');
      _isDbReady = true;
    } catch (e) {
      print('OfflineClient: Error initializing GanttDb: $e');
    }
  }

  Future<void> _flushQueue() async {
    if (_activeFlushFuture != null) {
      return _activeFlushFuture;
    }
    _activeFlushFuture = _performFlush();
    try {
      await _activeFlushFuture;
    } finally {
      _activeFlushFuture = null;
    }
  }

  Future<void> _performFlush() async {
    // Only flush if we think we are connected.
    if (!_isConnected || _innerClient == null) return;

    while (_isConnected && _innerClient != null) {
      if (!_isDbReady) {
        print('OfflineClient: DB not ready, waiting...');
        await _dbInitFuture;
      }

      // Read next batch (with lock)
      final rows = await _lock
          .synchronized(() => _db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC LIMIT 50'));

      if (rows.isEmpty) break;

      print('Flushing ${rows.length} offline operations...');

      for (final row in rows) {
        // Double check connection before each send to allow abort
        if (!_isConnected || _innerClient == null) break;

        final id = row['id'] as int;
        try {
          final dataDynamic = jsonDecode(row['data'] as String);
          if (dataDynamic == null) {
            print('Skipping queued op with null data: $id');
            await _lock.synchronized(() => _db.execute('DELETE FROM offline_queue WHERE id = ?', [id]));
            continue;
          }
          final Map<String, dynamic> dataMap = Map<String, dynamic>.from(dataDynamic as Map);

          final op = Operation(
            type: row['type'] as String,
            data: dataMap,
            timestamp: row['timestamp'] as int,
            actorId: row['actor_id'] as String,
          );

          print('Flushing OP: ${op.type}, Timestamp: ${op.timestamp}');
          if (_innerClient != null) {
            await _innerClient!.sendOperation(op);
            await _lock.synchronized(() => _db.execute('DELETE FROM offline_queue WHERE id = ?', [id]));
          }
        } catch (e) {
          print('Failed to convert/send queued op id $id: $e');
          if (e.toString().contains('FormatException') || e.toString().contains('subtype')) {
            print('Deleting malformed op $id');
            await _lock.synchronized(() => _db.execute('DELETE FROM offline_queue WHERE id = ?', [id]));
          } else {
            break;
          }
        }
      }
    }
  }

  @override
  Stream<Operation> get operationStream => _operationController.stream;

  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  Future<List<Operation>> getInitialState() async {
    if (_innerClient != null) {
      return _innerClient!.getInitialState();
    }
    return [];
  }

  @override
  Future<void> sendOperation(Operation operation) async {
    // Outbox pattern: Always queue first to ensure persistence against crashes/network loss
    await _queueOperation(operation);

    // Then attempt to flush (send to server)
    _flushQueue();
  }

  Future<void> _queueOperation(Operation operation) async {
    if (!_isDbReady) await _dbInitFuture;
    print('OfflineClient: Queuing operation ${operation.type}');
    await _lock.synchronized(() async {
      await _db.execute(
        'INSERT INTO offline_queue (type, data, timestamp, actor_id) VALUES (?, ?, ?, ?)',
        [
          operation.type,
          jsonEncode(operation.data),
          operation.timestamp,
          operation.actorId,
        ],
      );
    });
  }

  Future<void> dispose() async {
    _detachInnerClient();
    await _operationController.close();
    await _connectionStateController.close();
  }
}

// Helper for web check
const bool kIsWeb = identical(0, 0.0);
