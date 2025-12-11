import 'dart:async';
import 'dart:convert';
import 'package:synchronized/synchronized.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'gantt_sync_client.dart';
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
  final Future<SqliteCrdt> _dbFuture;

  OfflineGanttSyncClient(this._dbFuture, [this._innerClient]) {
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
      _db = await _dbFuture; // Wait for the passed future

      // Ensure the offline queue table exists
      await _db.execute('''
          CREATE TABLE IF NOT EXISTS offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            data TEXT,
            timestamp INTEGER,
            actor_id TEXT
          )
        ''');

      print('OfflineClient: GanttDb initialized');
      _isDbReady = true;
    } catch (e) {
      print('OfflineClient: Error initializing GanttDb: $e');
    }
  }

  Future<void> _flushQueue() async {
    print('OfflineClient: _flushQueue called. isConnected: $_isConnected, innerClient: $_innerClient');
    if (_activeFlushFuture != null) {
      print('OfflineClient: Flush already active, waiting for it...');
      return _activeFlushFuture;
    }
    _activeFlushFuture = _performFlush();
    try {
      await _activeFlushFuture;
      print('OfflineClient: Flush completed.');
    } catch (e, st) {
      print('OfflineClient: Flush failed with error: $e\n$st');
    } finally {
      _activeFlushFuture = null;
    }
  }

  Future<void> _performFlush() async {
    // Only flush if we think we are connected.
    if (!_isConnected || _innerClient == null) {
      print('OfflineClient: Aborting flush because not connected or no inner client.');
      return;
    }

    print('OfflineClient: Starting flush loop...');

    while (_isConnected && _innerClient != null) {
      if (!_isDbReady) {
        print('OfflineClient: DB not ready, waiting...');
        await _dbInitFuture;
      }

      // Read next batch (with lock)

      // WAIT. If I create the table here, SqliteCrdt might not have picked it up if it was opened BEFORE this execute?
      // No, SqliteCrdt hooks `onCreate` and `onUpgrade`. If _db is already open, and I run `execute`, does it hook it?
      // SqliteCrdt wraps the db. `execute` calls `_db.execute`.
      // The CRDT logic (triggers) are usually set up on creation.
      // If I add a table dynamically, I might need to ensure triggers are added.
      // However, `offline_queue` is LOCAL ONLY. We don't want to sync the queue itself. We want to sync constraints.
      // Actually, we probably DON'T want `offline_queue` to be a CRDT table because we don't sync IT.
      // But if `SqliteCrdt` wrapper keeps it that way, we have to live with it.
      // If `SqliteCrdt` adds overhead, we might want to avoid it.
      // But we are passing `SqliteCrdt` object.
      // Ideally, we should check if `is_deleted` column exists or just select all.
      // Since it's a queue, we delete rows after sending.
      // If it's a CRDT, `DELETE` sets `is_deleted=1`. So we MUST filter.
      // If it's NOT a CRDT, `DELETE` removes the row. `is_deleted` column won't exist.
      // Strategy: Try catching the query error, or check table info.
      // BETTER: Just try query with `is_deleted = 0`. If it fails, fallback to `SELECT *`.

      // OR: Since this is specific to `OfflineGanttSyncClient`, maybe we assume the user sets up the table correctly?
      // My `_initDb` tries to create it.
      // If I use `SqliteCrdt`, any table created via `execute` MIGHT be instrumented.
      // Let's stick to the code from example which used `is_deleted = 0`. It implies it WAS instrumented.

      List<Map<String, Object?>> rows;
      try {
        rows = await _lock
            .synchronized(() => _db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC LIMIT 50'));
      } catch (e) {
        // Fallback if is_deleted doesn't exist (not a CRDT table)
        rows = await _lock.synchronized(() => _db.query('SELECT * FROM offline_queue ORDER BY id ASC LIMIT 50'));
      }

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
    // Ephemeral operations should bypass persistence if possible to avoid DB contention.
    // They are only useful in real-time.
    const transientOps = {'CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE'};
    if (transientOps.contains(operation.type)) {
      if (_innerClient != null && _isConnected) {
        // Send directly, skip queue
        await _innerClient!.sendOperation(operation);
        return;
      }
      // If offline, we just drop them, as they are real-time only.
      print('OfflineClient: Dropping transient operation ${operation.type} because offline');
      return;
    }

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
