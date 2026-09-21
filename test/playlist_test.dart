import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/playlist.dart';

AppMediaItem track(String id, {MediaSourceType? source}) => AppMediaItem(
      id: id,
      title: 'Track $id',
      artist: 'Artist $id',
      sourceType: source ?? MediaSourceType.local,
    );

void main() {
  test('starts empty', () {
    const playlist = Playlist(id: '1', name: 'Road trip');
    expect(playlist.length, 0);
    expect(playlist.contains('a'), isFalse);
  });

  test('withItem adds a track without mutating the original', () {
    const original = Playlist(id: '1', name: 'Road trip');
    final updated = original.withItem(track('a'));

    expect(updated.length, 1);
    expect(updated.contains('a'), isTrue);
    expect(original.length, 0, reason: 'playlists are immutable values');
  });

  test('withItem is a no-op for a track already present', () {
    final playlist =
        const Playlist(id: '1', name: 'Road trip').withItem(track('a'));
    final again = playlist.withItem(track('a'));

    expect(again.length, 1, reason: 're-adding must not duplicate');
    expect(identical(again, playlist), isTrue);
  });

  test('withoutItem removes only the named track', () {
    final playlist = const Playlist(id: '1', name: 'Road trip')
        .withItem(track('a'))
        .withItem(track('b'))
        .withoutItem('a');

    expect(playlist.length, 1);
    expect(playlist.contains('a'), isFalse);
    expect(playlist.contains('b'), isTrue);
  });

  test('removing a track that is not there changes nothing', () {
    final playlist =
        const Playlist(id: '1', name: 'Road trip').withItem(track('a'));

    expect(playlist.withoutItem('zzz').length, 1);
  });

  test('copyWith renames without touching the tracks', () {
    final playlist =
        const Playlist(id: '1', name: 'Old').withItem(track('a'));
    final renamed = playlist.copyWith(name: 'New');

    expect(renamed.name, 'New');
    expect(renamed.id, '1');
    expect(renamed.length, 1);
  });

  test('survives the JSON round-trip used by Hive', () {
    final playlist = const Playlist(id: '1', name: 'Road trip')
        .withItem(track('a', source: MediaSourceType.youtube))
        .withItem(track('b', source: MediaSourceType.podcast));

    final restored =
        Playlist.fromJson(jsonDecode(jsonEncode(playlist.toJson())));

    expect(restored.id, '1');
    expect(restored.name, 'Road trip');
    expect(restored.length, 2);
    expect(restored.items[0].id, 'a');
    // The whole point of storing items rather than ids: a YouTube entry has
    // no library to be joined back to.
    expect(restored.items[0].sourceType, MediaSourceType.youtube);
    expect(restored.items[1].sourceType, MediaSourceType.podcast);
  });

  test('decodes a playlist saved before it had any tracks', () {
    final restored = Playlist.fromJson({'id': '1', 'name': 'Empty'});

    expect(restored.length, 0);
    expect(restored.name, 'Empty');
  });
}
