import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/playback_mode.dart';

void main() {
  group('nextPosition', () {
    test('advances through the list', () {
      expect(
        nextPosition(position: 0, length: 3, repeat: QueueRepeat.off, auto: true),
        1,
      );
      expect(
        nextPosition(position: 1, length: 3, repeat: QueueRepeat.off, auto: false),
        2,
      );
    });

    test('stops at the end when a track finishes and repeat is off', () {
      expect(
        nextPosition(position: 2, length: 3, repeat: QueueRepeat.off, auto: true),
        isNull,
      );
    });

    test('the next button still wraps at the end with repeat off', () {
      expect(
        nextPosition(position: 2, length: 3, repeat: QueueRepeat.off, auto: false),
        0,
      );
    });

    test('repeat-all wraps on completion', () {
      expect(
        nextPosition(position: 2, length: 3, repeat: QueueRepeat.all, auto: true),
        0,
      );
    });

    test('repeat-one replays on completion but not on the next button', () {
      expect(
        nextPosition(position: 1, length: 3, repeat: QueueRepeat.one, auto: true),
        1,
      );
      expect(
        nextPosition(position: 1, length: 3, repeat: QueueRepeat.one, auto: false),
        2,
      );
    });

    test('a single-track queue does not loop forever on completion', () {
      // The whole reason completion is separate from the next button.
      expect(
        nextPosition(position: 0, length: 1, repeat: QueueRepeat.off, auto: true),
        isNull,
      );
      expect(
        nextPosition(position: 0, length: 1, repeat: QueueRepeat.all, auto: true),
        0,
      );
    });

    test('handles an empty queue and an unset position', () {
      expect(
        nextPosition(position: 0, length: 0, repeat: QueueRepeat.all, auto: false),
        isNull,
      );
      expect(
        nextPosition(position: -1, length: 3, repeat: QueueRepeat.off, auto: false),
        0,
      );
    });
  });

  group('shouldResume', () {
    test('resumes from a position well into the track', () {
      expect(
        shouldResume(
          saved: const Duration(minutes: 20),
          total: const Duration(minutes: 60),
        ),
        isTrue,
      );
    });

    test('ignores a position near the start', () {
      expect(shouldResume(saved: const Duration(seconds: 3)), isFalse);
      // Exactly at the threshold counts as worth resuming.
      expect(shouldResume(saved: const Duration(seconds: 10)), isTrue);
    });

    test('ignores a position near the end — the track was finished', () {
      expect(
        shouldResume(
          saved: const Duration(minutes: 59, seconds: 55),
          total: const Duration(minutes: 60),
        ),
        isFalse,
      );
    });

    test('resumes when the total duration is unknown', () {
      expect(shouldResume(saved: const Duration(minutes: 20)), isTrue);
    });

    test('does not choke on a zero-length track', () {
      expect(
        shouldResume(saved: const Duration(minutes: 5), total: Duration.zero),
        isTrue,
      );
    });
  });

  group('previousPosition', () {
    test('steps back and wraps to the end', () {
      expect(previousPosition(position: 2, length: 3), 1);
      expect(previousPosition(position: 0, length: 3), 2);
    });

    test('handles an empty queue and an unset position', () {
      expect(previousPosition(position: 0, length: 0), 0);
      expect(previousPosition(position: -1, length: 3), 0);
    });
  });
}
