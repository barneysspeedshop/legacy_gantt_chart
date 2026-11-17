Map<String, dynamic> immutableMetadata(Map<String, dynamic> metadata) =>
    Map<String, dynamic>.unmodifiable(metadata.map((key, value) => MapEntry(key, _immutableValue(value))));

dynamic _immutableValue(dynamic value) {
  if (value is Map<String, dynamic>) return immutableMetadata(value);
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_immutableValue));
  }
  return value;
}
