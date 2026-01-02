import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/sync/merkle_tree.dart';

void main() {
  group('MerkleTree', () {
    test('hash should be deterministic', () {
      final h1 = MerkleTree.hash('content');
      final h2 = MerkleTree.hash('content');
      expect(h1, equals(h2));
    });

    test('hash should change with content', () {
      final h1 = MerkleTree.hash('content1');
      final h2 = MerkleTree.hash('content2');
      expect(h1, isNot(equals(h2)));
    });

    test('combineHashes should be order independent (if we sort inside)', () {
      final h1 = MerkleTree.hash('a');
      final h2 = MerkleTree.hash('b');

      final combined1 = MerkleTree.combineHashes([h1, h2]);
      final combined2 = MerkleTree.combineHashes([h2, h1]);

      expect(combined1, equals(combined2));
    });

    test('combineHashes should handle empty list', () {
      final h = MerkleTree.combineHashes([]);
      expect(h, isNotNull);
    });
  });
}
