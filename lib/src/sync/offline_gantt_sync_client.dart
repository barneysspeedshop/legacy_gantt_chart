import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:synchronized/synchronized.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';

import 'websocket_gantt_sync_client.dart';

class OfflineGanttSyncClient implements GanttSyncClient {
  late Hlc _clock = Hlc(
    millis: 0,
    counter: 0,
    nodeId:
        'offline-client-${Random.secure().nextInt(0x100000000).toRadixString(16)}-${Random.secure().nextInt(0x100000000).toRadixString(16)}',
  );
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
  bool _flushRequested = false;
  bool _disposed = false;
  int _connectionGeneration = 0;

  Future<void> get ready => _dbInitFuture;

  bool get isConnected => _isConnected && !_disposed;

  int get connectionGeneration => _connectionGeneration;

  void observeClock(Hlc clock) {
    _clock = _clock.receive(clock, DateTime.now().millisecondsSinceEpoch);
  }

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
    _connectionGeneration++;
    await _detachInnerClient();
    await _innerClient?.dispose();
    _innerClient = client;
    _attachInnerClient(client);
  }

  Future<void> removeInnerClient() async {
    _connectionGeneration++;
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
        _scheduleFlush();
      }
    });

    _innerOperationSubscription = client.operationStream.listen((op) {
      observeClock(op.timestamp);
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

      final rows = await _db.query('SELECT timestamp FROM offline_queue WHERE is_deleted = 0');
      for (final row in rows) {
        try {
          observeClock(Hlc.parse(row['timestamp'] as String));
        } catch (_) {
          // Keep malformed entries for recovery; never discard durable edits.
        }
      }
      print('OfflineClient: GanttDb initialized');
      _isDbReady = true;
    } catch (e) {
      print('OfflineClient: Error initializing GanttDb: $e');
      rethrow;
    }
  }

  @override
  Stream<SyncProgress> get inboundProgress =>
      _innerClient?.inboundProgress ?? Stream.value(const SyncProgress(processed: 0, total: 0));

  @override
  Hlc get currentHlc {
    final inner = _innerClient;
    _clock = inner == null
        ? _clock.send(DateTime.now().millisecondsSinceEpoch)
        : _clock.receive(inner.currentHlc, inner.correctedTimestamp);
    return _clock;
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
      final result = await _lock.synchronized(
        () => _db.query('SELECT COUNT(*) FROM offline_queue WHERE is_deleted = 0'),
      );
      final count = result.firstOrNull?['COUNT(*)'] as int? ?? result.firstOrNull?.values.first as int? ?? 0;
      if (!_outboundPendingCountController.isClosed) _outboundPendingCountController.add(count);
    } catch (e) {
      print('OfflineClient: Error updating pending count: $e');
    }
  }

  /// Attempts socket handoff of persisted operations. This protocol has no
  /// server acknowledgement; successful handoff is not durable server receipt.
  Future<void> flushPending() async {
    if (_disposed) return;
    _flushRequested = true;
    while (_flushRequested && !_disposed) {
      final active = _activeFlushFuture;
      if (active != null) {
        await active;
        continue;
      }
      final drain = _drainRequestedFlushes();
      _activeFlushFuture = drain;
      try {
        await drain;
      } finally {
        if (identical(_activeFlushFuture, drain)) _activeFlushFuture = null;
      }
    }
    await _updatePendingCount();
  }

  Future<void> _drainRequestedFlushes() async {
    while (_flushRequested && !_disposed) {
      _flushRequested = false;
      await _performFlush();
    }
  }

  void _scheduleFlush() {
    unawaited(
      flushPending().catchError((Object error) {
        print('OfflineClient: Flush failed; durable queue retained: $error');
      }),
    );
  }

  @protected
  Future<List<Map<String, Object?>>> loadPendingOperations() =>
      _db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC LIMIT 500');

  Future<void> _performFlush() async {
    print('OfflineClient: Starting flush perform...');
    while (true) {
      // Re-check conditions at start of each iteration
      if (_disposed || !_isConnected || _innerClient == null) {
        print('OfflineClient: Not connected or no inner client, stopping flush.');
        break;
      }

      if (!_isDbReady) {
        await _dbInitFuture;
      }

      List<Map<String, Object?>> rows;
      try {
        rows = await _lock.synchronized(loadPendingOperations);
      } catch (e) {
        print('OfflineClient: Error querying queue: $e');
        break;
      }

      if (rows.isEmpty) {
        print('OfflineClient: Queue is empty, breaking flush.');
        break;
      }
      print('OfflineClient: Found ${rows.length} rows to flush.');

      final sendingClient = _innerClient;
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

          opsToSend.add(Operation(type: type, data: data, timestamp: timestamp, actorId: actorId));
          idsToDelete.add(id);
        } catch (e) {
          print('OfflineClient: Cannot send queued op id $id; retained for recovery: $e');
          return;
        }
      }

      if (idsToDelete.isNotEmpty) {
        final placeholder = List.filled(idsToDelete.length, '?').join(',');
        try {
          if (!_isConnected || sendingClient == null || _innerClient != sendingClient || _disposed) return;
          await sendingClient.sendOperations(opsToSend);
          if (!_isConnected || _innerClient != sendingClient || _disposed) return;

          await _lock.synchronized(
            () => _db.execute('DELETE FROM offline_queue WHERE id IN ($placeholder)', idsToDelete),
          );
          print('OfflineClient: Successfully deleted ${idsToDelete.length} operations from queue.');

          // CRITICAL: Update pending count immediately after delete so listeners see progress
          _updatePendingCount();
        } catch (e) {
          print('OfflineClient: Error during flush batch/delete: $e');
          break;
        }
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
  Future<void> syncWithMerkle({required MerkleTree localTree}) async {
    if (_innerClient != null) {
      await _innerClient!.syncWithMerkle(localTree: localTree);
    }
  }

  @override
  Future<void> sendOperation(Operation operation) => sendOperations([operation]);

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
    if (_disposed) throw StateError('Offline client is disposed');
    const transientOps = {'CURSOR_MOVE', 'GHOST_UPDATE', 'PRESENCE_UPDATE'};
    final durable = <Operation>[];
    for (final operation in operations) {
      if (transientOps.contains(operation.type)) {
        final inner = _innerClient;
        if (inner != null && _isConnected) await inner.sendOperation(operation);
      } else {
        durable.add(operation);
      }
    }
    if (durable.isEmpty) return;
    await ready;
    await persistOperations(durable);
    await _updatePendingCount();
    _scheduleFlush();
  }

  /// Subclasses may atomically persist canonical state and the same outbox.
  /// This must finish before any durable operation is handed to the network.
  @protected
  Future<void> persistOperations(List<Operation> operations) async {
    await ready;
    final rows = operations
        .map(
          (operation) => {
            'type': operation.type,
            'data': operation.data,
            'timestamp': operation.timestamp.toString(),
            'actor_id': operation.actorId,
          },
        )
        .toList();
    await _lock.synchronized(
      () => _db.execute(
        r'''INSERT INTO offline_queue (type, data, timestamp, actor_id)
      SELECT json_extract(value, '$.type'), json_extract(value, '$.data'),
             json_extract(value, '$.timestamp'), json_extract(value, '$.actor_id')
      FROM json_each(?)''',
        [jsonEncode(rows)],
      ),
    );
    for (final operation in operations) {
      observeClock(operation.timestamp);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connectionGeneration++;
    print('OfflineClient: Disposing...');
    await _detachInnerClient();
    final inner = _innerClient;
    _innerClient = null;
    await inner?.dispose();
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
    await _outboundPendingCountController.close();
    print('OfflineClient: Disposal complete.');
  }
}

const bool kIsWeb = identical(0, 0.0);
