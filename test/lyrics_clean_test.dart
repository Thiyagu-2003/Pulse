import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/lyrics_service.dart';

void main() {
  test('noise words go, but only as whole words', () {
    expect(LyricsService.cleanQuery('Vaseegara (Official Video) HD'), 'Vaseegara');
    expect(LyricsService.cleanQuery('Song Lyric Video'), 'Song');
    expect(LyricsService.cleanQuery('Audioslave'), 'Audioslave');
    expect(LyricsService.cleanQuery('HDMI Blues'), 'HDMI Blues');
    expect(LyricsService.cleanQuery('Pavazha Malli [4K]'), 'Pavazha Malli');
  });
}
