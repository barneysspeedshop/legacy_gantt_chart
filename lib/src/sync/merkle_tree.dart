import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'hlc.dart';

/// Represents a node in the Merkle Tree.
class MerkleNode {
  final String hash;
  final Hlc? rangeStart; // Null for leaf nodes if we treat them specifically, but for time-based, it's the range
  final Hlc? rangeEnd;
  final List<MerkleNode> children;
  final int count; // Number of items in this subtree

  MerkleNode({
    required this.hash,
    this.rangeStart,
    this.rangeEnd,
    this.children = const [],
    this.count = 0,
  });

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'rangeStart': rangeStart?.toString(),
        'rangeEnd': rangeEnd?.toString(),
        'children': children.map((c) => c.toJson()).toList(),
        'count': count,
      };
}

/// A simplified time-based Merkle Tree implementation.
/// It buckets items based on their last updated HLC timestamp.
class MerkleTree {
  // We'll use a fixed depth for simplicity in this initial version.
  // Depth 0 = Root (covers all time)
  // Depth 1 = Buckets (e.g., minutes/hours/days depending on implementation)

  // For this simplified version, let's just implement the hashing logic.
  // Real implementation will require building the tree from a list of tasks.

  static String hash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static String combineHashes(List<String> hashes) {
    if (hashes.isEmpty) return hash('');
    hashes.sort(); // Ensure deterministic order
    return hash(hashes.join(','));
  }

  static String computeRoot(List<String> validContentHashes) => combineHashes(validContentHashes);
}
