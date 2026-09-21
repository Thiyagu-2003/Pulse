import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/playback_mode.dart';

/// The index arithmetic behind queue edits. QueueState composes these; these
/// tests pin down the pieces so a failure says which rule broke.
void main() {
  group('indexAfterMove', () {
    test('the moved item lands on its target', () {
      expect(indexAfterMove(1, 1, 3), 3);
      expect(indexAfterMove(3, 3, 0), 0);
    });

    test('items between shift back when moving forward', () {
      // Moving 1 -> 3: items at 2 and 3 slide down to 1 and 2.
      expect(indexAfterMove(2, 1, 3), 1);
      expect(indexAfterMove(3, 1, 3), 2);
    });

    test('items between shift forward when moving backward', () {
      // Moving 3 -> 1: items at 1 and 2 slide up to 2 and 3.
      expect(indexAfterMove(1, 3, 1), 2);
      expect(indexAfterMove(2, 3, 1), 3);
    });

    test('items outside the moved range are untouched', () {
      expect(indexAfterMove(0, 1, 3), 0);
      expect(indexAfterMove(5, 1, 3), 5);
      expect(indexAfterMove(0, 3, 1), 0);
      expect(indexAfterMove(5, 3, 1), 5);
    });

    test('a no-op move and an unset index change nothing', () {
      expect(indexAfterMove(2, 2, 2), 2);
      expect(indexAfterMove(-1, 0, 3), -1);
    });

    test('a move is a permutation — no index collides or disappears', () {
      for (final from in [0, 1, 2, 3, 4]) {
        for (final to in [0, 1, 2, 3, 4]) {
          final moved = [0, 1, 2, 3, 4]
              .map((i) => indexAfterMove(i, from, to))
              .toList();
          expect(
            moved.toSet().length,
            5,
            reason: 'move $from -> $to produced duplicates: $moved',
          );
          expect(moved.every((i) => i >= 0 && i < 5), isTrue);
        }
      }
    });
  });

  group('orderAfterRemoval', () {
    test('drops the removed index and shifts later ones down', () {
      expect(orderAfterRemoval([0, 1, 2, 3], 1), [0, 1, 2]);
      expect(orderAfterRemoval([3, 1, 0, 2], 1), [2, 0, 1]);
    });

    test('removing the last index leaves the rest alone', () {
      expect(orderAfterRemoval([0, 1, 2], 2), [0, 1]);
    });

    test('an index not in the order still shifts the ones above it', () {
      expect(orderAfterRemoval([2, 3], 0), [1, 2]);
    });

    test('the result stays a valid permutation', () {
      final result = orderAfterRemoval([4, 0, 2, 1, 3], 2);
      expect(result.length, 4);
      expect(result.toSet().length, 4);
      expect(result.every((i) => i >= 0 && i < 4), isTrue);
    });
  });

  group('orderAfterInsertion', () {
    test('shifts indices at or after the insertion point up', () {
      expect(orderAfterInsertion([0, 1, 2], 1), [0, 2, 3]);
    });

    test('inserting at the end leaves everything alone', () {
      expect(orderAfterInsertion([0, 1, 2], 3), [0, 1, 2]);
    });

    test('inserting at the front shifts everything', () {
      expect(orderAfterInsertion([0, 1], 0), [1, 2]);
    });

    test('does not add the new item — the caller places it', () {
      expect(orderAfterInsertion([0, 1, 2], 1).length, 3);
    });
  });
}
