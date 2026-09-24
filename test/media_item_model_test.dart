import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';

/// AppMediaItem is the single currency of the app: local songs, YouTube
/// results and podcast episodes all become one. It round-trips through
/// audio_service's MediaItem (via `extras`) on every play and through JSON on
/// every favorite/history write — dropping a field in either direction means
/// a track that can't be played back.
void main() {
  final track = AppMediaItem(
    id: 'abc123',
    title: 'Test Track',
    artist: 'Test Artist',
    album: 'Test Album',
    artUri: 'https://example.com/art.jpg',
    streamUrl: 'https://example.com/audio.m4a',
    duration: const Duration(minutes: 3, seconds: 42),
    sourceType: MediaSourceType.youtube,
    extras: {'songId': 7},
  );

  test('survives the audio_service MediaItem round-trip', () {
    final restored =
        AppMediaItem.fromAudioServiceMediaItem(track.toAudioServiceMediaItem());

    expect(restored.id, track.id);
    expect(restored.title, track.title);
    expect(restored.artist, track.artist);
    expect(restored.album, track.album);
    expect(restored.duration, track.duration);
    // These two live only in `extras` — the easiest pair to lose.
    expect(restored.streamUrl, track.streamUrl);
    expect(restored.sourceType, MediaSourceType.youtube);
  });

  test('survives the JSON round-trip used by favorites and history', () {
    final restored =
        AppMediaItem.fromJson(jsonDecode(jsonEncode(track.toJson())));

    expect(restored.id, track.id);
    expect(restored.title, track.title);
    expect(restored.artUri, track.artUri);
    expect(restored.streamUrl, track.streamUrl);
    expect(restored.duration, track.duration);
    expect(restored.sourceType, MediaSourceType.youtube);
  });

  group('user-facing source labels', () {
    test('never name the provider', () {
      for (final source in MediaSourceType.values) {
        expect(
          source.label.toLowerCase(),
          isNot(anyOf(contains('youtube'), contains('yt'))),
          reason: '${source.name} label leaks the provider name',
        );
      }
    });

    test('name the three libraries the app actually presents', () {
      expect(MediaSourceType.local.label, 'Local');
      expect(MediaSourceType.youtube.label, 'Online');
      expect(MediaSourceType.podcast.label, 'Podcast');
    });

    test('the persisted enum name is unchanged', () {
      // Stored favorites, playlists and downloads are keyed on this string.
      // Renaming it would make fromJson fall back to `local` and point every
      // saved online track at a file that does not exist.
      expect(MediaSourceType.youtube.name, 'youtube');
    });

    test('rewrites the old album label on stored items', () {
      final restored = AppMediaItem.fromJson({
        'id': 'a',
        'title': 'T',
        'artist': 'A',
        'album': 'YouTube Music',
        'sourceType': 'youtube',
      });

      expect(restored.album, onlineAlbumLabel);
      expect(restored.sourceType, MediaSourceType.youtube,
          reason: 'the track must still resolve as an online source');
    });

    test('leaves a real album name alone', () {
      final restored = AppMediaItem.fromJson({
        'id': 'a',
        'title': 'T',
        'artist': 'A',
        'album': 'Abbey Road',
        'sourceType': 'local',
      });

      expect(restored.album, 'Abbey Road');
    });
  });

  test('falls back rather than throwing on partial or unknown data', () {
    final restored = AppMediaItem.fromJson({
      'id': 'x',
      'title': 'T',
      'artist': 'A',
      'sourceType': 'some_future_source',
    });

    expect(restored.album, 'Unknown Album');
    expect(restored.duration, isNull);
    expect(restored.sourceType, MediaSourceType.local);
  });

  test('a stale streamUrl in extras does not override the resolved one', () {
    final item = AppMediaItem(
      id: 'abc',
      title: 't',
      artist: 'a',
      streamUrl: 'https://fresh',
      sourceType: MediaSourceType.youtube,
      extras: {'streamUrl': 'https://stale', 'sourceType': 'local'},
    );
    final restored =
        AppMediaItem.fromAudioServiceMediaItem(item.toAudioServiceMediaItem());
    expect(restored.streamUrl, 'https://fresh');
    expect(restored.sourceType, MediaSourceType.youtube);
  });
}
