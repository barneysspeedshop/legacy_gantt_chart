import 'dart:async';
import 'dart:convert';

import 'package:legacy_gantt_chart/legacy_gantt_chart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketGanttSyncClient implements GanttSyncClient {
  final Uri uri;
  final String? authToken;
  WebSocketChannel? _channel;
  final _operationController = StreamController<Operation>.broadcast();

  WebSocketGanttSyncClient({required this.uri, this.authToken});

  void connect() {
    var finalUri = uri;
    if (authToken != null) {
      // Append token to query parameters
      final newQueryParams = Map<String, dynamic>.from(uri.queryParameters);
      newQueryParams['token'] = authToken;
      finalUri = uri.replace(queryParameters: newQueryParams);
    }

    _channel = WebSocketChannel.connect(finalUri);
    _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          final op = Operation.fromJson(data);
          _operationController.add(op);
        } catch (e) {
          print('Error parsing operation: $e');
        }
      },
      onDone: () {
        print('WebSocket connection closed');
      },
      onError: (error) {
        print('WebSocket error: $error');
      },
    );
  }

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
    _channel!.sink.add(jsonEncode(operation.toJson()));
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
    await _operationController.close();
  }
}
