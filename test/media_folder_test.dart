import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_folder.dart';
import 'package:music_player/models/media_item_model.dart';

AppMediaItem local(String id, String path) => AppMediaItem(
      id: id,
      title: id,
      artist: 'Artist',
      streamUrl: path,
      sourceType: MediaSourceType.local,
      extras: {'filePath': path},
    );

AppMediaItem streamed(String id) => AppMediaItem(
      id: id,
      title: id,
      artist: 'Artist',
      streamUrl: 'https://example.com/$id.m4a',
      sourceType: MediaSourceType.youtube,
    );

void main() {
  group('folderPathOf', () {
    test('returns the containing directory', () {
      expect(
        folderPathOf(local('a', '/storage/emulated/0/Music/track.mp3')),
        '/storage/emulated/0/Music',
      );
    });

    test('falls back to streamUrl when extras carry no path', () {
      final track = AppMediaItem(
        id: 'a',
        title: 'a',
        artist: 'Artist',
        streamUrl: '/storage/emulated/0/Recordings/call.m4a',
        sourceType: MediaSourceType.local,
      );
      expect(folderPathOf(track), '/storage/emulated/0/Recordings');
    });

    test('gives up on streamed and content-uri tracks', () {
      expect(folderPathOf(streamed('a')), isNull);

      final contentUri = AppMediaItem(
        id: 'b',
        title: 'b',
        artist: 'Artist',
        streamUrl: 'content://media/external/audio/media/42',
        sourceType: MediaSourceType.local,
        extras: const {'filePath': null},
      );
      expect(folderPathOf(contentUri), isNull);
    });

    test('handles a bare filename and an empty path', () {
      expect(folderPathOf(local('a', 'track.mp3')), isNull);
      expect(folderPathOf(local('b', '')), isNull);
    });
  });

  group('MediaFolder', () {
    test('name is the last path segment', () {
      const folder = MediaFolder(
        path: '/storage/emulated/0/Music/Albums',
        items: [],
      );
      expect(folder.name, 'Albums');
    });

    test('recognises recording folders by name', () {
      for (final name in [
        'Recordings',
        'Call recordings',
        'Voice Recorder',
        'voice_memos',
      ]) {
        expect(
          MediaFolder(path: '/storage/$name', items: const []).isRecordings,
          isTrue,
          reason: '$name should be treated as recordings',
        );
      }
    });

    test('does not mistake music folders for recordings', () {
      for (final name in ['Music', 'Download', 'Albums', 'Podcasts']) {
        expect(
          MediaFolder(path: '/storage/$name', items: const []).isRecordings,
          isFalse,
          reason: '$name should not be treated as recordings',
        );
      }
    });
  });

  group('groupByFolder', () {
    test('splits recordings out of music instead of one flat list', () {
      final folders = groupByFolder([
        local('song1', '/storage/emulated/0/Music/song1.mp3'),
        local('call1', '/storage/emulated/0/Recordings/Call/call1.m4a'),
        local('song2', '/storage/emulated/0/Music/song2.mp3'),
        local('memo1', '/storage/emulated/0/Recordings/memo1.m4a'),
      ]);

      expect(folders.length, 3);
      expect(folders.map((f) => f.name).toList(), ['Music', 'Call', 'Recordings']);
      expect(folders.first.length, 2);
    });

    test('music folders sort before recording folders', () {
      final folders = groupByFolder([
        local('a', '/storage/Recordings/a.m4a'),
        local('b', '/storage/Zebra/b.mp3'),
      ]);

      // Alphabetically Recordings < Zebra, but music wins the top slot.
      expect(folders.map((f) => f.name).toList(), ['Zebra', 'Recordings']);
    });

    test('music folders sort alphabetically among themselves', () {
      final folders = groupByFolder([
        local('a', '/storage/Music/a.mp3'),
        local('b', '/storage/Albums/b.mp3'),
        local('c', '/storage/downloads/c.mp3'),
      ]);

      expect(folders.map((f) => f.name).toList(),
          ['Albums', 'downloads', 'Music']);
    });

    test('tracks with no resolvable path land in a catch-all folder', () {
      final folders = groupByFolder([
        local('a', '/storage/Music/a.mp3'),
        streamed('b'),
      ]);

      expect(folders.any((f) => f.name == unknownFolderLabel), isTrue);
      expect(
        folders.firstWhere((f) => f.name == unknownFolderLabel).length,
        1,
      );
    });

    test('keeps every track — nothing is silently hidden', () {
      final tracks = [
        local('a', '/storage/Music/a.mp3'),
        local('b', '/storage/Recordings/b.m4a'),
        local('c', '/storage/Recordings/c.m4a'),
        streamed('d'),
      ];

      final total =
          groupByFolder(tracks).fold<int>(0, (sum, f) => sum + f.length);
      expect(total, tracks.length);
    });

    test('an empty library produces no folders', () {
      expect(groupByFolder([]), isEmpty);
    });
  });
}
