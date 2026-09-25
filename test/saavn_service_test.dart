import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/saavn_service.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';

// Captured from a live search.getResults for "vaseegara".
const _encrypted =
    'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDysKIz4Fh14qPdJZPYkKfqA+4ua0AzLA3FmBOw0ArFPjr/k9QUdr0RNPhveXdhRkFeGBTsxqxbyf8=';

Map<String, dynamic> _song({Object? artistMap, String type = 'song'}) => {
      'id': 'bo7KIXAM',
      'title': 'Vaseegara (From &quot;Minnale&quot;)',
      'subtitle': 'Bombay Jayashri - Minnalae',
      'type': type,
      'image': 'https://c.saavncdn.com/137/Minnalae-150x150.jpg',
      'language': 'tamil',
      'more_info': {
        'music': 'Harris Jayaraj',
        'album': 'Minnalae',
        'duration': '299',
        'encrypted_media_url': _encrypted,
        'artistMap': artistMap ??
            {
              'primary_artists': [
                {'name': 'Bombay Jayashri'},
                {'name': 'Harris Jayaraj'},
              ],
            },
      },
    };

void main() {
  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_saavn_')).path);
    await Hive.openBox<String>(StorageService.settingsBox);
  });

  test('media URL decrypts to the CDN file', () {
    final url = SaavnService.decryptMediaUrl(_encrypted);
    expect(url, startsWith('https://aac.saavncdn.com/'));
    expect(url, endsWith('_96.mp4'));
  });

  test('bitrate follows the quality setting', () {
    const url = 'https://aac.saavncdn.com/137/abc_sar_96.mp4';
    expect(SaavnService.withQuality(url, AudioQuality.best),
        'https://aac.saavncdn.com/137/abc_sar_320.mp4');
    expect(SaavnService.withQuality(url, AudioQuality.balanced), endsWith('_160.mp4'));
    expect(SaavnService.withQuality(url, AudioQuality.dataSaver), endsWith('_96.mp4'));
  });

  test('a song maps to a playable online item', () {
    final item = SaavnService.toItem(_song())!;
    expect(item.sourceType, MediaSourceType.saavn);
    expect(item.sourceType.isOnline, isTrue);
    expect(item.title, 'Vaseegara (From "Minnale")');
    expect(item.artist, 'Bombay Jayashri, Harris Jayaraj');
    expect(item.album, 'Minnalae');
    expect(item.duration, const Duration(seconds: 299));
    expect(item.artUri, contains('500x500'));
    expect(item.streamUrl, startsWith('https://aac.saavncdn.com/'));
  });

  test('loosely typed fields never throw', () {
    // artistMap as a string instead of a map: falls back to "music".
    final item = SaavnService.toItem(_song(artistMap: ''))!;
    expect(item.artist, 'Harris Jayaraj');
    // Not a song, or no media URL: skipped, not a crash.
    expect(SaavnService.toItem(_song(type: 'album')), isNull);
    expect(SaavnService.toItem({'id': 'x', 'more_info': 'oops'}), isNull);
    expect(SaavnService.toItem(null), isNull);
  });

  test('HTML entities are decoded', () {
    expect(SaavnService.unescape('Rock &amp; Roll &#039;99 &quot;x&quot;'),
        'Rock & Roll \'99 "x"');
  });

  test('saved JioSaavn items survive the storage and player round trips', () {
    final item = SaavnService.toItem(_song())!;
    final back = AppMediaItem.fromJson(item.toJson());
    expect(back.sourceType, MediaSourceType.saavn);
    expect(back.streamUrl, item.streamUrl);
    final viaPlayer =
        AppMediaItem.fromAudioServiceMediaItem(item.toAudioServiceMediaItem());
    expect(viaPlayer.sourceType, MediaSourceType.saavn);
  });

  test('home-row queries reach YouTube as words, never as prefixes', () {
    expect(YoutubeService.youtubeFallbackQuery('playlist:Love Tamil'),
        'Love Tamil songs');
    expect(YoutubeService.youtubeFallbackQuery('trending:tamil'),
        'tamil trending songs');
    expect(YoutubeService.youtubeFallbackQuery('anirudh'), 'anirudh');
  });
}
