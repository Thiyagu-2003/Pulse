import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/lyrics.dart';

void main() {
  test('parses LRC: fractions, repeated stamps, metadata and blanks', () {
    final lines = Lyrics.parseLrc('[ar:Someone]\n'
        '[00:05.5]first\n'
        '[00:12.34][01:02.345]chorus\n'
        '[00:20.00]\n'
        'no stamp here\n'
        '[00:08]second');
    expect(lines.map((l) => l.text), ['first', 'second', 'chorus', 'chorus']);
    expect(lines.map((l) => l.time.inMilliseconds), [5500, 8000, 12340, 62345]);
  });

  test('finds the line being sung', () {
    final lyrics = Lyrics.synced(Lyrics.parseLrc('[00:05.00]a\n[00:10.00]b\n[00:15.00]c'), 'x');
    expect(lyrics.indexAt(const Duration(seconds: 2)), -1);
    expect(lyrics.indexAt(const Duration(seconds: 5)), 0);
    expect(lyrics.indexAt(const Duration(seconds: 12)), 1);
    expect(lyrics.indexAt(const Duration(minutes: 5)), 2);
    expect(lyrics.isSynced, isTrue);
    expect(lyrics.plain, 'a\nb\nc');
  });

  test('plain lyrics are not synced', () {
    final lyrics = Lyrics.plainText('just words', 'x');
    expect(lyrics.isSynced, isFalse);
    expect(lyrics.indexAt(const Duration(seconds: 3)), -1);
  });
}
