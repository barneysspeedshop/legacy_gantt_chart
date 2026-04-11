import 'dart:async';
import 'dart:convert';
import 'package:synchronized/synchronized.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
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

      await _db.execute('''
          CREATE TABLE IF NOT EXISTS offline_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            data TEXT,

            timestamp TEXT,
            actor_id TEXT
          )
        ''');

      print('OfflineClient: GanttDb initialized');
      _isDbReady = true;
    } catch (e) {
      print('OfflineClient: Error initializing GanttDb: $e');
    }
  }

  @override
  Stream<SyncProgress> get inboundProgress =>
      _innerClient?.inboundProgress ?? Stream.value(const SyncProgress(processed: 0, total: 0));

  @override
  Hlc get currentHlc {
    if (_innerClient != null) {
      return _innerClient!.currentHlc;
    }
    return Hlc.fromDate(DateTime.now(), 'offline-client');
  }

  @override
  String get actorId {
    if (_innerClient != null) {
      return _innerClient!.actorId;
    }
    return 'offline-user';
  }

  final _outboundPendingCountController = StreamController<int>.broadcast();

  @override
  Stream<int> get outboundPendingCount {
    _updatePendingCount();
    return _outboundPendingCountController.stream;
  }

  Future<void> _updatePendingCount() async {
    if (!_isDbReady) return;
    try {
      final result =
          await _lock.synchronized(() => _db.query('SELECT COUNT(*) FROM offline_queue WHERE is_deleted = 0'));
      final count = result.firstOrNull?['COUNT(*)'] as int? ?? result.firstOrNull?.values.first as int? ?? 0;
      _outboundPendingCountController.add(count);
    } catch (e) {
      print('OfflineClient: Error updating pending count: $e');
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
      _updatePendingCount();
    }
  }

  Future<void> _performFlush() async {
    print('OfflineClient: Starting flush perform...');
    while (true) {
      // Re-check conditions at start of each iteration
      if (!_isConnected || _innerClient == null) {
        print('OfflineClient: Not connected or no inner client, stopping flush.');
        break;
      }

      if (!_isDbReady) {
        await _dbInitFuture;
      }

      List<Map<String, Object?>> rows;
      try {
        rows = await _lock.synchronized(
            () => _db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC LIMIT 500'));
      } catch (e) {
        print('OfflineClient: Error querying queue: $e');
        break;
      }

      if (rows.isEmpty) {
        print('OfflineClient: Queue is empty, breaking flush.');
        break;
      }
      print('OfflineClient: Found ${rows.length} rows to flush.');

      final opsToSend = <Operation>[];
      final idsToDelete = <int>[];

      for (final row in rows) {
        // We don't break mid-batch processing for connectivity,
        // but we verify innerClient still exists.
        if (_innerClient == null) break;

        final id = row['id'] as int;
        try {
          final type = row['type'] as String;
          final dataString = row['data'] as String;
          final data = jsonDecode(dataString) as Map<String, dynamic>;
          final timestamp = Hlc.parse(row['timestamp'] as String);
          final actorId = row['actor_id'] as String;

          // Map start/end to start_date/end_date if present
          if (data.containsKey('start')) {
            data['start_date'] = data.remove('start');
          }
          if (data.containsKey('end')) {
            data['end_date'] = data.remove('end');
          }

          opsToSend.add(Operation(
            type: type,
            data: data,
            timestamp: timestamp,
            actorId: actorId,
          ));
          idsToDelete.add(id);
        } catch (e) {
          print('OfflineClient: Failed to convert queued op id $id: $e');
          if (e.toString().contains('FormatException') || e.toString().contains('subtype')) {
            print('OfflineClient: Deleting malformed op $id');
            idsToDelete.add(id);
          }
        }
      }

      if (idsToDelete.isNotEmpty) {
        final placeholder = List.filled(idsToDelete.length, '?').join(',');
        try {
          if (opsToSend.isNotEmpty && _innerClient != null && _isConnected) {
            print('OfflineClient: Flushing batch of ${opsToSend.length} operations...');
            await _innerClient!.sendOperations(opsToSend);
          }

          await _lock
              .synchronized(() => _db.execute('DELETE FROM offline_queue WHERE id IN ($placeholder)', idsToDelete));
          print('OfflineClient: Successfully deleted ${idsToDelete.length} operations from queue.');

          // CRITICAL: Update pending count immediately after delete so listeners see progress
          _updatePendingCount();
        } catch (e) {
          print('OfflineClient: Error during flush batch/delete: $e');
          break;
        }
      }

      // If we got exactly 500 rows, there might be more. Otherwise, we are done.
      if (rows.length < 500) {
        print('OfflineClient: Processed last batch, breaking.');
        break;
      }
    }
    print('OfflineClient: Flush perform finished.');
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
  Future<String> getMerkleRoot() async {
    if (_innerClient != null) {
      return _innerClient!.getMerkleRoot();
    }
    return '';
  }

  @override
  Future<void> syncWithMerkle({required String remoteRoot, required int depth}) async {
    if (_innerClient != null) {
      await _innerClient!.syncWithMerkle(remoteRoot: remoteRoot, depth: depth);
    }
  }

  @override
  Future<void> sendOperation(Operation operation) async {
    const transientOps = {'CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE'};
    if (transientOps.contains(operation.type)) {
      if (_innerClient != null && _isConnected) {
        await _innerClient!.sendOperation(operation);
        return;
      }
      print('OfflineClient: Dropping transient operation ${operation.type} because offline');
      return;
    }

    if (operation.data.containsKey('start')) {
      final startVal = operation.data['start'];
      if (startVal is String || startVal is int) {
        operation.data['start_date'] = startVal;
        operation.data.remove('start');
      }
    }
    if (operation.data.containsKey('end')) {
      final endVal = operation.data['end'];
      if (endVal is String || endVal is int) {
        operation.data['end_date'] = endVal;
        operation.data.remove('end');
      }
    }

    await _queueOperation(operation);

    _flushQueue();
  }

  Future<void> clearQueue() async {
    if (!_isDbReady) await _dbInitFuture;
    await _lock.synchronized(() async {
      await _db.execute('DELETE FROM offline_queue');
      print('OfflineClient: Cleared offline queue.');
    });
    _updatePendingCount();
  }

  @override
  Future<void> sendOperations(List<Operation> operations) async {
    const transientOps = {'CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE'};
    final opsToQueue = <Operation>[];

    for (final op in operations) {
      if (transientOps.contains(op.type)) {
        if (_innerClient != null && _isConnected) {
          await _innerClient!.sendOperation(op);
        } else {
          print('OfflineClient: Dropping transient operation ${op.type} because offline');
        }
      } else {
        opsToQueue.add(op);
      }
    }

    if (opsToQueue.isNotEmpty) {
      // Simplified: Always queue and then flush.
      // The _performFlush handles batching automatically.
      // This avoids complex and race-prone bundling logic here.
      await _queueOperations(opsToQueue);
      _flushQueue();
    }
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
          operation.timestamp.toString(),
          operation.actorId,
        ],
      );
    });
    _updatePendingCount();
  }

  Future<void> _queueOperations(List<Operation> operations) async {
    if (!_isDbReady) await _dbInitFuture;
    print('OfflineClient: Queuing ${operations.length} operations');
    await _lock.synchronized(() async {
      final batch = _db.batch();
      for (final operation in operations) {
        batch.execute(
          'INSERT INTO offline_queue (type, data, timestamp, actor_id) VALUES (?, ?, ?, ?)',
          [
            operation.type,
            jsonEncode(operation.data),
            operation.timestamp.toString(),
            operation.actorId,
          ],
        );
      }
      await batch.commit();
    });
    _updatePendingCount();
  }

  Future<void> dispose() async {
    print('OfflineClient: Disposing...');
    await _detachInnerClient();
    if (_activeFlushFuture != null) {
      try {
        print('OfflineClient: Waiting for active flush to finish during dispose...');
        await _activeFlushFuture;
      } catch (e) {
        print('OfflineClient: Error awaiting flush during dispose: $e');
      }
    }
    await _operationController.close();
    await _connectionStateController.close();
    print('OfflineClient: Disposal complete.');
  }
}

const bool kIsWeb = identical(0, 0.0);
