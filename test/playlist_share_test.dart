import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/playlist.dart';
import 'package:music_player/providers/music_player_provider.dart';

void main() {
  test('a shared playlist keeps streamable songs and drops device-only ones', () {
    final playlist = Playlist(
      id: '1',
      name: 'Road trip',
      items: [
        AppMediaItem(
          id: 'abcd1234',
          title: 'Online',
          artist: 'A',
          streamUrl: 'https://cdn.example/a.mp4',
          sourceType: MediaSourceType.saavn,
        ),
        // A download: shared as the JioSaavn song it was saved from.
        AppMediaItem(
          id: 'wxyz9876',
          title: 'Downloaded',
          artist: 'B',
          streamUrl: '/storage/Music/b.m4a',
          sourceType: MediaSourceType.local,
          extras: {
            MusicPlayerProvider.originKey: 'saavn',
            MusicPlayerProvider.originUrlKey: 'https://cdn.example/b.mp4',
          },
        ),
        // Only on this phone.
        AppMediaItem(
          id: '42',
          title: 'Device',
          artist: 'C',
          streamUrl: 'content://media/external/audio/media/42',
          sourceType: MediaSourceType.local,
        ),
      ],
    );

    final (:json, :skipped) = MusicPlayerProvider.exportPlaylist(playlist);

    expect(skipped, 1);
    expect(json['type'], 'playlist');
    expect(json['name'], 'Road trip');
    final items = (json['items'] as List)
        .map((t) => AppMediaItem.fromJson(t as Map<String, dynamic>))
        .toList();
    expect(items.map((t) => t.id), ['abcd1234', 'wxyz9876']);
    expect(items[1].sourceType, MediaSourceType.saavn);
    expect(items[1].streamUrl, 'https://cdn.example/b.mp4');
  });
}
