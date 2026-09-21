import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/track_query.dart';

AppMediaItem song(
  String title, {
  String artist = 'Unknown',
  String album = 'Unknown Album',
  Duration? duration,
}) =>
    AppMediaItem(
      id: title,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      sourceType: MediaSourceType.local,
    );

List<String> titles(List<AppMediaItem> tracks) =>
    tracks.map((t) => t.title).toList();

void main() {
  final library = [
    song('Yesterday', artist: 'The Beatles', album: 'Help'),
    song('Come Together', artist: 'The Beatles', album: 'Abbey Road'),
    song('Bohemian Rhapsody', artist: 'Queen', album: 'A Night at the Opera'),
  ];

  group('filterTracks', () {
    test('an empty query returns everything', () {
      expect(filterTracks(library, '').length, 3);
      expect(filterTracks(library, '   ').length, 3);
    });

    test('matches on title, ignoring case', () {
      expect(titles(filterTracks(library, 'yester')), ['Yesterday']);
      expect(titles(filterTracks(library, 'BOHEMIAN')), ['Bohemian Rhapsody']);
    });

    test('matches on artist', () {
      expect(filterTracks(library, 'beatles').length, 2);
    });

    test('matches on album', () {
      expect(titles(filterTracks(library, 'abbey')), ['Come Together']);
    });

    test('ignores surrounding whitespace', () {
      expect(titles(filterTracks(library, '  queen  ')), ['Bohemian Rhapsody']);
    });

    test('returns nothing when there is no match', () {
      expect(filterTracks(library, 'zzzz'), isEmpty);
    });
  });

  group('sortTracks', () {
    test('sorts by title, ignoring case', () {
      final sorted = sortTracks(
        [song('banana'), song('Apple'), song('cherry')],
        TrackSort.title,
      );
      expect(titles(sorted), ['Apple', 'banana', 'cherry']);
    });

    test('groups by artist, then orders by title within the artist', () {
      final sorted = sortTracks(library, TrackSort.artist);
      // "Queen" sorts before "The Beatles"; within The Beatles, "Come
      // Together" before "Yesterday" — that secondary ordering is the point.
      expect(titles(sorted), [
        'Bohemian Rhapsody',
        'Come Together',
        'Yesterday',
      ]);
    });

    test('groups by album, then orders by title', () {
      final sorted = sortTracks(library, TrackSort.album);
      expect(titles(sorted).first, 'Bohemian Rhapsody');
    });

    test('longest first puts the longest track at the top', () {
      final sorted = sortTracks(
        [
          song('short', duration: const Duration(minutes: 2)),
          song('long', duration: const Duration(minutes: 9)),
          song('middle', duration: const Duration(minutes: 5)),
        ],
        TrackSort.longest,
      );
      expect(titles(sorted), ['long', 'middle', 'short']);
    });

    test('treats an unknown duration as zero rather than throwing', () {
      final sorted = sortTracks(
        [song('unknown'), song('known', duration: const Duration(minutes: 3))],
        TrackSort.longest,
      );
      expect(titles(sorted), ['known', 'unknown']);
    });

    test('does not reorder the caller list', () {
      final original = [song('b'), song('a')];
      sortTracks(original, TrackSort.title);

      expect(
        titles(original),
        ['b', 'a'],
        reason: 'screens hold the unsorted list as their source of truth',
      );
    });

    test('every sort option has a label for the menu', () {
      for (final option in TrackSort.values) {
        expect(option.label, isNotEmpty);
      }
    });
  });

  test('filter and sort compose the way the screens use them', () {
    final result = sortTracks(
      filterTracks(library, 'beatles'),
      TrackSort.title,
    );
    expect(titles(result), ['Come Together', 'Yesterday']);
  });
}
