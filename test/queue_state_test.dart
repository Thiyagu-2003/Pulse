import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/playback_mode.dart';
import 'package:music_player/models/queue_state.dart';

AppMediaItem track(String id) => AppMediaItem(
      id: id,
      title: 'Track $id',
      artist: 'Artist $id',
      sourceType: MediaSourceType.local,
    );

List<AppMediaItem> tracks(List<String> ids) => ids.map(track).toList();

List<String> idsOf(QueueState queue) => queue.items.map((t) => t.id).toList();

void main() {
  group('basic queueing', () {
    test('replaceWith points at the chosen track and stays consistent', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('b'));

      expect(queue.length, 3);
      expect(queue.currentTrack?.id, 'b');
      expect(queue.currentIndex, 1);
      expect(queue.isConsistent, isTrue);
    });

    test('replaceWith inserts a track missing from the list', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b']), track('z'));

      expect(idsOf(queue), ['z', 'a', 'b']);
      expect(queue.currentTrack?.id, 'z');
      expect(queue.isConsistent, isTrue);
    });

    test('selectOrAppend appends an unknown track and selects it', () {
      final queue = QueueState()..replaceWith(tracks(['a', 'b']), track('a'));
      queue.selectOrAppend(track('c'));

      expect(idsOf(queue), ['a', 'b', 'c']);
      expect(queue.currentTrack?.id, 'c');
      expect(queue.isConsistent, isTrue);
    });

    test('selectOrAppend re-selects an already queued track', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));
      queue.selectOrAppend(track('c'));

      expect(queue.length, 3, reason: 'must not duplicate');
      expect(queue.currentTrack?.id, 'c');
      expect(queue.isConsistent, isTrue);
    });
  });

  group('advance and previous', () {
    test('walks the queue in order and stops at the end', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));

      expect(
        queue.advance(repeat: QueueRepeat.off, auto: true)?.id,
        'b',
      );
      expect(
        queue.advance(repeat: QueueRepeat.off, auto: true)?.id,
        'c',
      );
      expect(
        queue.advance(repeat: QueueRepeat.off, auto: true),
        isNull,
        reason: 'a finished queue stops rather than looping',
      );
      expect(queue.isConsistent, isTrue);
    });

    test('the next button wraps where auto-advance stops', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b']), track('b'));

      expect(queue.advance(repeat: QueueRepeat.off, auto: false)?.id, 'a');
      expect(queue.isConsistent, isTrue);
    });

    test('previous steps back and wraps', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));

      expect(queue.previous()?.id, 'c');
      expect(queue.previous()?.id, 'b');
      expect(queue.isConsistent, isTrue);
    });

    test('advancing an empty queue is safe', () {
      final queue = QueueState();
      expect(queue.advance(repeat: QueueRepeat.all, auto: false), isNull);
      expect(queue.previous(), isNull);
      expect(queue.isConsistent, isTrue);
    });
  });

  group('shuffle', () {
    test('keeps the current track playing when switched on', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd', 'e']), track('c'));

      queue.setShuffled(true);

      expect(queue.currentTrack?.id, 'c', reason: 'must not jump tracks');
      expect(queue.orderPos, 0, reason: 'current track leads the new order');
      expect(queue.isConsistent, isTrue);
    });

    test('plays every track exactly once before running out', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd', 'e']), track('a'))
        ..setShuffled(true);

      final played = <String>{queue.currentTrack!.id};
      for (var i = 0; i < 4; i++) {
        final next = queue.advance(repeat: QueueRepeat.off, auto: true);
        expect(next, isNotNull, reason: 'ran out early at step $i');
        expect(played.add(next!.id), isTrue, reason: '${next.id} played twice');
      }

      expect(played.length, 5);
      expect(
        queue.advance(repeat: QueueRepeat.off, auto: true),
        isNull,
        reason: 'shuffle is a permutation, not random with replacement',
      );
      expect(queue.isConsistent, isTrue);
    });

    test('switching shuffle back off restores queue order', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'))
        ..setShuffled(true)
        ..setShuffled(false);

      expect(queue.currentTrack?.id, 'a');
      expect(queue.orderPos, 0);
      expect(queue.advance(repeat: QueueRepeat.off, auto: true)?.id, 'b');
      expect(queue.isConsistent, isTrue);
    });
  });

  group('peekNext', () {
    test('reports the upcoming track without moving the cursor', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));

      expect(queue.peekNext(repeat: QueueRepeat.off)?.id, 'b');
      expect(
        queue.currentTrack?.id,
        'a',
        reason: 'prefetching must not advance playback',
      );
      expect(queue.isConsistent, isTrue);
    });

    test('wraps at the end and is null for an empty queue', () {
      final queue = QueueState()..replaceWith(tracks(['a', 'b']), track('b'));
      expect(queue.peekNext(repeat: QueueRepeat.off)?.id, 'a');
      expect(QueueState().peekNext(repeat: QueueRepeat.off), isNull);
    });

    test('agrees with what advance actually plays', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd']), track('a'))
        ..setShuffled(true);

      final predicted = queue.peekNext(repeat: QueueRepeat.off)?.id;
      final actual = queue.advance(repeat: QueueRepeat.off, auto: false)?.id;
      expect(predicted, actual, reason: 'prefetching the wrong track is waste');
    });
  });

  group('move', () {
    test('reorders and follows the playing track', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd']), track('b'));

      queue.move(1, 3); // b to the end

      expect(idsOf(queue), ['a', 'c', 'd', 'b']);
      expect(queue.currentTrack?.id, 'b', reason: 'still playing the same track');
      expect(queue.currentIndex, 3);
      expect(queue.isConsistent, isTrue);
    });

    test('moving another track does not change what is playing', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd']), track('b'));

      queue.move(3, 0); // d to the front

      expect(idsOf(queue), ['d', 'a', 'b', 'c']);
      expect(queue.currentTrack?.id, 'b');
      expect(queue.currentIndex, 2, reason: 'shifted right by the insertion');
      expect(queue.isConsistent, isTrue);
    });

    test('playback order survives a move under shuffle', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd', 'e']), track('a'))
        ..setShuffled(true);

      queue.move(4, 0);

      expect(queue.isConsistent, isTrue);
      expect(queue.currentTrack?.id, 'a');

      final played = <String>{'a'};
      for (var i = 0; i < 4; i++) {
        final next = queue.advance(repeat: QueueRepeat.off, auto: true);
        expect(next, isNotNull);
        expect(played.add(next!.id), isTrue, reason: 'duplicate after move');
      }
      expect(played.length, 5);
    });

    test('out-of-range moves are ignored', () {
      final queue = QueueState()..replaceWith(tracks(['a', 'b']), track('a'));

      queue.move(-1, 1);
      queue.move(0, 5);
      queue.move(0, 0);

      expect(idsOf(queue), ['a', 'b']);
      expect(queue.isConsistent, isTrue);
    });
  });

  group('removeAt', () {
    test('removing a later track leaves playback alone', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));

      expect(queue.removeAt(2), isFalse);
      expect(idsOf(queue), ['a', 'b']);
      expect(queue.currentTrack?.id, 'a');
      expect(queue.isConsistent, isTrue);
    });

    test('removing an earlier track keeps the cursor on the same song', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('c'));

      expect(queue.removeAt(0), isFalse);
      expect(idsOf(queue), ['b', 'c']);
      expect(queue.currentTrack?.id, 'c');
      expect(queue.currentIndex, 1);
      expect(queue.isConsistent, isTrue);
    });

    test('removing the playing track moves to what follows it', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('b'));

      expect(queue.removeAt(1), isTrue, reason: 'reports it was playing');
      expect(idsOf(queue), ['a', 'c']);
      expect(queue.currentTrack?.id, 'c');
      expect(queue.isConsistent, isTrue);
    });

    test('removing the playing last track falls back onto the new last', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('c'));

      expect(queue.removeAt(2), isTrue);
      expect(idsOf(queue), ['a', 'b']);
      expect(queue.currentTrack?.id, 'b');
      expect(queue.isConsistent, isTrue);
    });

    test('emptying the queue clears the cursors', () {
      final queue = QueueState()..replaceWith(tracks(['a']), track('a'));

      expect(queue.removeAt(0), isTrue);
      expect(queue.isEmpty, isTrue);
      expect(queue.currentTrack, isNull);
      expect(queue.currentIndex, -1);
      expect(queue.isConsistent, isTrue);
    });

    test('out-of-range removals are ignored', () {
      final queue = QueueState()..replaceWith(tracks(['a', 'b']), track('a'));

      expect(queue.removeAt(-1), isFalse);
      expect(queue.removeAt(9), isFalse);
      expect(queue.length, 2);
      expect(queue.isConsistent, isTrue);
    });

    test('stays consistent when removing under shuffle', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd', 'e']), track('c'))
        ..setShuffled(true);

      queue.removeAt(0);
      expect(queue.isConsistent, isTrue);
      queue.removeAt(queue.length - 1);
      expect(queue.isConsistent, isTrue);
      queue.removeAt(queue.currentIndex);
      expect(queue.isConsistent, isTrue);
    });
  });

  group('insertNext and append', () {
    test('play next lands immediately after the current track', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));

      queue.insertNext(track('z'));

      expect(idsOf(queue), ['a', 'z', 'b', 'c']);
      expect(queue.currentTrack?.id, 'a', reason: 'does not interrupt');
      expect(queue.advance(repeat: QueueRepeat.off, auto: true)?.id, 'z');
      expect(queue.isConsistent, isTrue);
    });

    test('play next plays next under shuffle too', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd']), track('a'))
        ..setShuffled(true);

      queue.insertNext(track('z'));

      expect(queue.isConsistent, isTrue);
      expect(
        queue.advance(repeat: QueueRepeat.off, auto: true)?.id,
        'z',
        reason: 'shuffle must not scatter an explicit play-next',
      );
    });

    test('append goes to the end of the queue', () {
      final queue = QueueState()..replaceWith(tracks(['a', 'b']), track('a'));

      queue.append(track('z'));

      expect(idsOf(queue), ['a', 'b', 'z']);
      expect(queue.currentTrack?.id, 'a');
      expect(queue.isConsistent, isTrue);
    });

    test('append then advance reaches the appended track last', () {
      final queue = QueueState()..replaceWith(tracks(['a', 'b']), track('a'));
      queue.append(track('z'));

      expect(queue.advance(repeat: QueueRepeat.off, auto: true)?.id, 'b');
      expect(queue.advance(repeat: QueueRepeat.off, auto: true)?.id, 'z');
      expect(queue.isConsistent, isTrue);
    });
  });

  group('no duplicates', () {
    test('play next on a queued track moves it instead of copying it', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd']), track('a'));
      expect(queue.insertNext(track('d')), isTrue);

      expect(idsOf(queue), ['a', 'd', 'b', 'c']);
      expect(queue.advance(repeat: QueueRepeat.off, auto: false)?.id, 'd');
      expect(queue.isConsistent, isTrue);
    });

    test('play next on a track *before* the current one keeps the cursor', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('b'));
      queue.insertNext(track('a'));

      expect(idsOf(queue), ['b', 'a', 'c']);
      expect(queue.currentTrack?.id, 'b');
      expect(queue.advance(repeat: QueueRepeat.off, auto: false)?.id, 'a');
      expect(queue.isConsistent, isTrue);
    });

    test('play next / add to queue on the playing track is a no-op', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b']), track('a'));

      expect(queue.insertNext(track('a')), isFalse);
      expect(queue.append(track('a')), isFalse);
      expect(idsOf(queue), ['a', 'b']);
      expect(queue.isConsistent, isTrue);
    });

    test('add to queue on a queued track moves it to the end', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));
      queue.append(track('b'));

      expect(idsOf(queue), ['a', 'c', 'b']);
      expect(queue.isConsistent, isTrue);
    });

    test('dedupe stays consistent under shuffle', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c', 'd', 'e']), track('c'))
        ..setShuffled(true);
      queue.insertNext(track('a'));
      expect(queue.advance(repeat: QueueRepeat.off, auto: false)?.id, 'a');
      queue.append(track('e'));
      expect(queue.items.where((t) => t.id == 'e').length, 1);
      expect(queue.isConsistent, isTrue);
    });
  });

  group('selectAt', () {
    test('selects the exact row tapped', () {
      final queue = QueueState()
        ..replaceWith(tracks(['a', 'b', 'c']), track('a'));

      expect(queue.selectAt(2)?.id, 'c');
      expect(queue.currentIndex, 2);
      expect(queue.advance(repeat: QueueRepeat.all, auto: false)?.id, 'a');
      expect(queue.isConsistent, isTrue);
    });

    test('ignores out-of-range rows', () {
      final queue = QueueState()..replaceWith(tracks(['a']), track('a'));
      expect(queue.selectAt(5), isNull);
      expect(queue.selectAt(-1), isNull);
      expect(queue.currentIndex, 0);
    });
  });

  test('survives a long mixed sequence of edits', () {
    final queue = QueueState()
      ..replaceWith(tracks(['a', 'b', 'c', 'd', 'e']), track('c'));

    void check(String step) {
      expect(queue.isConsistent, isTrue, reason: 'inconsistent after $step');
    }

    queue.setShuffled(true);
    check('shuffle on');
    queue.insertNext(track('x'));
    check('insertNext');
    queue.append(track('y'));
    check('append');
    queue.move(0, 3);
    check('move');
    queue.removeAt(2);
    check('remove');
    queue.advance(repeat: QueueRepeat.all, auto: true);
    check('advance');
    queue.setShuffled(false);
    check('shuffle off');
    queue.previous();
    check('previous');
    queue.move(queue.length - 1, 0);
    check('move to front');
    queue.removeAt(queue.currentIndex);
    check('remove current');

    expect(queue.length, 5);
  });
}
