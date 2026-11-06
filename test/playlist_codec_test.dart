import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/playlist.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/util/playlist_codec.dart';

void main() {
  group('PlaylistCodec', () {
    final samplePlaylist = Playlist(
      id: 'pl-1',
      name: 'Vibes',
      items: [
        AppMediaItem(
          id: 'online-1',
          title: 'Song One',
          artist: 'Artist A',
          album: 'Album A',
          artUri: 'https://cdn.example/art1.jpg',
          streamUrl: 'https://cdn.example/1.mp4',
          duration: const Duration(minutes: 3, seconds: 20),
          sourceType: MediaSourceType.saavn,
        ),
        // Downloaded item (origin recorded)
        AppMediaItem(
          id: 'dl-2',
          title: 'Song Two',
          artist: 'Artist B',
          album: 'Album B',
          streamUrl: '/data/music/dl2.m4a',
          duration: const Duration(minutes: 4, seconds: 15),
          sourceType: MediaSourceType.local,
          extras: {
            MusicPlayerProvider.originKey: 'saavn',
            MusicPlayerProvider.originUrlKey: 'https://cdn.example/2.mp4',
          },
        ),
        // Device-only item (should be skipped)
        AppMediaItem(
          id: 'local-3',
          title: 'Local Only',
          artist: 'Me',
          streamUrl: 'content://media/external/audio/3',
          sourceType: MediaSourceType.local,
        ),
      ],
    );

    test('exportToJson serializes correctly and drops device-only tracks', () {
      final (:json, :skipped) = PlaylistCodec.exportToJson(samplePlaylist);

      expect(skipped, 1);
      expect(json['app'], 'pulse');
      expect(json['type'], 'playlist');
      expect(json['version'], 2);
      expect(json['name'], 'Vibes');

      final items = json['items'] as List;
      expect(items.length, 2);
      expect(items[0]['id'], 'online-1');
      expect(items[0]['title'], 'Song One');
      expect(items[1]['id'], 'dl-2');
      expect(items[1]['sourceType'], 'saavn');
      expect(items[1]['streamUrl'], 'https://cdn.example/2.mp4');
    });

    test('exportToCode and parseCodeOrText roundtrips accurately', () {
      final code = PlaylistCodec.exportToCode(samplePlaylist);
      expect(code.startsWith('pulse://playlist?d='), isTrue);

      final parsed = PlaylistCodec.parseCodeOrText(code);
      expect(parsed['name'], 'Vibes');
      expect((parsed['items'] as List).length, 2);

      final validated = PlaylistCodec.validatePlaylistJson(parsed);
      expect(validated.name, 'Vibes');
      expect(validated.items.length, 2);
      expect(validated.items.first.title, 'Song One');
      expect(validated.items.first.duration, const Duration(minutes: 3, seconds: 20));
    });

    test('parseCodeOrText accepts message text containing a pulse link or PULSE: prefix', () {
      final code = PlaylistCodec.exportToCode(samplePlaylist);
      final rawBase64 = code.split('?d=').last;

      final messageWithLink = 'Hey check out this playlist!\npulse://playlist?d=$rawBase64\nEnjoy!';
      final parsedFromLink = PlaylistCodec.parseCodeOrText(messageWithLink);
      expect(parsedFromLink['name'], 'Vibes');

      final legacyPrefix = 'PULSE:$rawBase64';
      final parsedFromPrefix = PlaylistCodec.parseCodeOrText(legacyPrefix);
      expect(parsedFromPrefix['name'], 'Vibes');
    });

    test('validatePlaylistJson rejects non-pulse or malformed data', () {
      expect(
        () => PlaylistCodec.validatePlaylistJson({'app': 'other', 'name': 'Test'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PlaylistCodec.validatePlaylistJson({'app': 'pulse', 'type': 'backup'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PlaylistCodec.validatePlaylistJson({'app': 'pulse', 'type': 'playlist', 'name': ''}),
        throwsA(isA<FormatException>()),
      );
    });

    test('isLargePlaylist threshold detects >100 songs', () {
      expect(PlaylistCodec.isLargePlaylist(50), isFalse);
      expect(PlaylistCodec.isLargePlaylist(100), isFalse);
      expect(PlaylistCodec.isLargePlaylist(101), isTrue);
    });
  });
}

