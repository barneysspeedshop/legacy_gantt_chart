import 'package:flutter/material.dart';

class RemoteCursor {
  final String userId;
  final DateTime time;
  final String rowId;
  final Color color;
  final DateTime lastUpdated;

  RemoteCursor({
    required this.userId,
    required this.time,
    required this.rowId,
    required this.color,
    required this.lastUpdated,
  });
}
