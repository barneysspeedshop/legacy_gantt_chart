import 'package:flutter/material.dart';
import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';

void main() {
  runApp(const MinimalSyncApp());
}

class MinimalSyncApp extends StatelessWidget {
  const MinimalSyncApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Minimal Sync Tester')),
          body: const MinimalSyncView(),
        ),
      );
}

class MinimalSyncView extends StatefulWidget {
  const MinimalSyncView({super.key});

  @override
  State<MinimalSyncView> createState() => _MinimalSyncViewState();
}

class _MinimalSyncViewState extends State<MinimalSyncView> {
  final _uriController = TextEditingController(text: 'http://localhost:8080');
  final _userController = TextEditingController(text: 'debug');
  final _passController = TextEditingController(text: 'debug');
  final _tenantController = TextEditingController(text: 'debug');

  WebSocketGanttSyncClient? _client;
  final List<String> _logs = [];
  bool _isConnected = false;

  final List<LegacyGanttRow> _rows = [
    const LegacyGanttRow(id: 'r1'),
    const LegacyGanttRow(id: 'r2'),
    const LegacyGanttRow(id: 'r3'),
  ];
  final Map<String, int> _rowDepths = {'r1': 1, 'r2': 1, 'r3': 1};

  // We use a controller for the chart logic
  late final LegacyGanttController _controller;
  final List<LegacyGanttTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _controller = LegacyGanttController(
      initialVisibleStartDate: DateTime.now().subtract(const Duration(days: 1)),
      initialVisibleEndDate: DateTime.now().add(const Duration(days: 10)),
    );
  }

  @override
  void dispose() {
    _client?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String().split('T').last} $message');
    });
  }

  Future<void> _connect() async {
    final uriStr = _uriController.text;
    final username = _userController.text;
    final password = _passController.text;
    final tenant = _tenantController.text;

    try {
      _log('Logging in...');
      final uri = Uri.parse(uriStr);

      // 1. Login to get token
      final token = await WebSocketGanttSyncClient.login(
        uri: uri,
        username: username,
        password: password,
      );
      _log('Login successful.');

      // WS URI
      var wsUri = uri;
      if (uri.scheme == 'http') {
        wsUri = uri.replace(scheme: 'ws', path: '/ws');
      } else if (uri.scheme == 'https') {
        wsUri = uri.replace(scheme: 'wss', path: '/ws');
      }

      _client = WebSocketGanttSyncClient(
        uri: wsUri,
        authToken: token,
      );

      // 3. Listen to stream
      _client!.operationStream.listen((op) {
        _handleIncomingOp(op);
      });

      _client!.connectionStateStream.listen((connected) {
        setState(() => _isConnected = connected);
        _log('Connection State: $connected');
      });

      // 4. Connect
      _log('Connecting WS...');
      _client!.connect(tenant);
    } catch (e) {
      _log('Error: $e');
    }
  }

  void _handleIncomingOp(Operation op) {
    _log('RCVD: ${op.type}');
    setState(() {
      if (op.type == 'INSERT_TASK' || op.type == 'INSERT') {
        final data = op.data;
        if (data['id'] != null) {
          // Remove existing if any (upsert)
          _tasks.removeWhere((t) => t.id == data['id']);
          _tasks.add(_taskFromData(data));
        }
      } else if (op.type == 'UPDATE_TASK' || op.type == 'UPDATE') {
        final data = op.data;
        final idx = _tasks.indexWhere((t) => t.id == data['id']);
        if (idx != -1) {
          final old = _tasks[idx];
          // Merge data
          _tasks[idx] = _taskFromData({..._taskToData(old), ...data});
        }
      } else if (op.type == 'DELETE_TASK' || op.type == 'DELETE') {
        final id = op.data['id'];
        _tasks.removeWhere((t) => t.id == id);
      }
      _controller.setTasks(List.of(_tasks)); // Trigger update
    });
  }

  LegacyGanttTask _taskFromData(Map<String, dynamic> data) => LegacyGanttTask(
        id: data['id'],
        name: data['name'] ?? 'Unnamed',
        start: DateTime.parse(data['start']),
        end: DateTime.parse(data['end']),
        rowId: data['rowId'] ?? 'r1',
        color: Colors.blue,
      );

  Map<String, dynamic> _taskToData(LegacyGanttTask task) => {
        'id': task.id,
        'name': task.name,
        'start': task.start.toIso8601String(),
        'end': task.end.toIso8601String(),
        'rowId': task.rowId,
      };

  Future<void> _sendInsert() async {
    if (_client == null || !_isConnected) {
      _log('Not connected');
      return;
    }
    final id = 'task-${DateTime.now().millisecondsSinceEpoch}';
    final op = Operation(
      type: 'INSERT',
      data: {
        'id': id,
        'name': 'Task $id',
        'start': DateTime.now().toIso8601String(),
        'end': DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
        'rowId': 'r1',
      },
      timestamp: DateTime.now().millisecondsSinceEpoch,
      actorId: 'minimal-client',
    );
    try {
      await _client!.sendOperation(op);
      _log('SENT: ${op.type}');
    } catch (e) {
      _log('Send Error: $e');
    }
  }

  // Handle chart edits
  void _onTaskUpdate(LegacyGanttTask task, DateTime start, DateTime end) {
    // Optimistic update
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx != -1) {
      setState(() {
        _tasks[idx] = task.copyWith(start: start, end: end);
        _controller.setTasks(List.of(_tasks));
      });
    }

    // Send OP
    if (_client != null && _isConnected) {
      final op = Operation(
        type: 'UPDATE',
        data: {
          'id': task.id,
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
        actorId: 'minimal-client',
      );
      _client!.sendOperation(op);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _buildControls(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rows list (simple text)
                SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      const SizedBox(height: 50), // header space
                      ..._rows.map((r) => Container(
                            height: 30, // Default row height
                            alignment: Alignment.center,
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
                            child: Text(r.id),
                          )),
                    ],
                  ),
                ),
                // Chart
                Expanded(
                  child: LegacyGanttChartWidget(
                    controller: _controller,
                    visibleRows: _rows,
                    rowMaxStackDepth: _rowDepths,
                    onTaskUpdate: _onTaskUpdate,
                    enableDragAndDrop: true,
                    enableResize: true,
                    rowHeight: 30.0,
                    axisHeight: 50.0,
                    syncClient: _client,
                    showCursors: true,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(_logs[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ),
        ],
      );

  Widget _buildControls() => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            TextField(controller: _uriController, decoration: const InputDecoration(labelText: 'URI')),
            Row(
              children: [
                Expanded(
                    child:
                        TextField(controller: _userController, decoration: const InputDecoration(labelText: 'User'))),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        TextField(controller: _passController, decoration: const InputDecoration(labelText: 'Pass'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _tenantController, decoration: const InputDecoration(labelText: 'Tenant'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(onPressed: _isConnected ? null : _connect, child: const Text('Connect')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _isConnected ? _sendInsert : null, child: const Text('Add Task')),
              ],
            ),
          ],
        ),
      );
}
