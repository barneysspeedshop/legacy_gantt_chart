import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Decodes JSON in a background isolate to avoid jank on the UI thread.
///
/// If the JSON string is small (< 10KB), it is decoded on the main thread
/// to avoid the overhead of spawning an isolate.
Future<dynamic> decodeJsonInBackground(String jsonString) async {
  if (jsonString.length < 10240) {
    return jsonDecode(jsonString);
  }
  return compute(_jsonDecodeWrapper, jsonString);
}

/// Top-level function required for compute
dynamic _jsonDecodeWrapper(String jsonString) => jsonDecode(jsonString);
