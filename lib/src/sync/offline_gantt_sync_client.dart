import 'dart:async';
import 'dart:convert';
import 'package:synchronized/synchronized.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:legacy_gantt_protocol/legacy_gantt_protocol.dart';
import 'websocket_gantt_sync_client.dart';
import '../utils/json_isolate.dart';

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
      print('Error updating pending count: $e');
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
      _updatePendingCount();
    }
  }

  Future<void> _performFlush() async {
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

      List<Map<String, Object?>> rows;
      try {
        rows = await _lock.synchronized(
            () => _db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC LIMIT 500'));
      } catch (e) {
        rows = await _lock.synchronized(() => _db.query('SELECT * FROM offline_queue ORDER BY id ASC LIMIT 500'));
      }

      if (rows.isEmpty) break;

      print('Flushing ${rows.length} offline operations...');

      final opsToSend = <Operation>[];
      final idsToDelete = <int>[];

      for (final row in rows) {
        if (!_isConnected || _innerClient == null) break;

        final id = row['id'] as int;
        try {
          final dataDynamic = await decodeJsonInBackground(row['data'] as String);
          if (dataDynamic == null) {
            print('Skipping queued op with null data: $id');
            idsToDelete.add(id);
            continue;
          }
          final Map<String, dynamic> dataMap = Map<String, dynamic>.from(dataDynamic as Map);

          // Legacy: Normalize data if it uses old keys or formats, but keep them robust
          if (dataMap.containsKey('start')) {
            final startVal = dataMap['start'];
            if (startVal is String || startVal is int) {
              dataMap['start_date'] = startVal;
              dataMap.remove('start');
            }
          }
          if (dataMap.containsKey('end')) {
            final endVal = dataMap['end'];
            if (endVal is String || endVal is int) {
              dataMap['end_date'] = endVal;
              dataMap.remove('end');
            }
          }

          final op = Operation(
            type: row['type'] as String,
            data: dataMap,
            timestamp: Hlc.parse(row['timestamp'] as String),
            actorId: row['actor_id'] as String,
          );
          opsToSend.add(op);
          idsToDelete.add(id);
        } catch (e) {
          print('Failed to convert queued op id $id: $e');
          if (e.toString().contains('FormatException') || e.toString().contains('subtype')) {
            print('Deleting malformed op $id');
            idsToDelete.add(id);
          }
        }
      }

      if (opsToSend.isNotEmpty && _innerClient != null && _isConnected) {
        try {
          print('Flushing batch of ${opsToSend.length} operations...');
          await _innerClient!.sendOperations(opsToSend);

          if (idsToDelete.isNotEmpty) {
            final placeholder = List.filled(idsToDelete.length, '?').join(',');
            await _lock
                .synchronized(() => _db.execute('DELETE FROM offline_queue WHERE id IN ($placeholder)', idsToDelete));
          }
        } catch (e) {
          print('Error flushing batch: $e');
          break;
        }
      } else if (idsToDelete.isNotEmpty) {
        final placeholder = List.filled(idsToDelete.length, '?').join(',');
        await _lock
            .synchronized(() => _db.execute('DELETE FROM offline_queue WHERE id IN ($placeholder)', idsToDelete));
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

    // Legacy: Normalize data if it uses old keys or formats, but keep them robust
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
      if (kIsWeb && opsToQueue.length > 100 && (!_isConnected || _innerClient == null)) {
        print('OfflineClient: Large batch on Web ($opsToQueue.length ops) and not connected. Waiting up to 2s...');
        try {
          // Wait for true on connection stream
          await _connectionStateController.stream
              .firstWhere((isConnected) => isConnected)
              .timeout(const Duration(seconds: 2));
          print('OfflineClient: Connected after wait! Proceeding to try direct send.');
        } catch (_) {
          print('OfflineClient: Connection wait timed out. Falling back to queue.');
        }
      }

      bool sentDirectly = false;

      if (_isConnected && _innerClient != null && _isDbReady) {
        try {
          await _lock.synchronized(() async {
            final countResult = await _db.query('SELECT COUNT(*) FROM offline_queue WHERE is_deleted = 0');
            final count =
                countResult.firstOrNull?['COUNT(*)'] as int? ?? countResult.firstOrNull?.values.first as int? ?? 0;

            if (count == 0) {
              print('OfflineClient: Queue is empty, sending ${opsToQueue.length} ops directly bypass DB.');
              await _innerClient!.sendOperations(opsToQueue);
              sentDirectly = true;
            } else if (count < 100) {
              print('OfflineClient: Queue has $count items (small). Draining and bundling...');

              final rows = await _db.query('SELECT * FROM offline_queue WHERE is_deleted = 0 ORDER BY id ASC');
              final idsToDelete = <int>[];
              final stragglers = <Operation>[];

              for (final row in rows) {
                final id = row['id'] as int;
                try {
                  final dataDynamic = await decodeJsonInBackground(row['data'] as String);
                  if (dataDynamic != null) {
                    final Map<String, dynamic> dataMap = Map<String, dynamic>.from(dataDynamic as Map);
                    if (dataMap.containsKey('start')) {
                      dataMap['start_date'] = dataMap['start'];
                      dataMap.remove('start');
                    }
                    if (dataMap.containsKey('end')) {
                      dataMap['end_date'] = dataMap['end'];
                      dataMap.remove('end');
                    }

                    stragglers.add(Operation(
                      type: row['type'] as String,
                      data: dataMap,
                      timestamp: Hlc.parse(row['timestamp'] as String),
                      actorId: row['actor_id'] as String,
                    ));
                  }
                  idsToDelete.add(id);
                } catch (e) {
                  print('Error decoding straggler $id: $e');
                  idsToDelete.add(id);
                }
              }

              final combinedBatch = [...stragglers, ...opsToQueue];
              print('OfflineClient: Sending combined batch of ${combinedBatch.length} (Swallowed $count queued)');
              await _innerClient!.sendOperations(combinedBatch);

              if (idsToDelete.isNotEmpty) {
                final placeholder = List.filled(idsToDelete.length, '?').join(',');
                await _db.execute('DELETE FROM offline_queue WHERE id IN ($placeholder)', idsToDelete);
              }
              sentDirectly = true;
            }
          });
        } catch (e) {
          print('OfflineClient: Direct send failed, falling back to queue. Error: $e');
          sentDirectly = false;
        }
      }

      if (!sentDirectly) {
        await _queueOperations(opsToQueue);
        _flushQueue();
      }
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
    if (kIsWeb && operations.length > 200) {
      const chunkSize = 100;
      for (var i = 0; i < operations.length; i += chunkSize) {
        final end = (i + chunkSize < operations.length) ? i + chunkSize : operations.length;
        final chunk = operations.sublist(i, end);

        await _lock.synchronized(() async {
          final batch = _db.batch();
          for (final operation in chunk) {
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
        await Future.delayed(Duration.zero);
      }
    } else {
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
    }
    _updatePendingCount();
  }

  Future<void> dispose() async {
    await _detachInnerClient();
    if (_activeFlushFuture != null) {
      try {
        await _activeFlushFuture;
      } catch (e) {
        print('OfflineClient: Error awaiting flush during dispose: $e');
      }
    }
    await _operationController.close();
    await _connectionStateController.close();
  }
}

const bool kIsWeb = identical(0, 0.0);
