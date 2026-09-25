import 'media_item_model.dart';

/// What the Stats screen shows, worked out from history play counts.
class ListeningStats {
  final int plays;
  final Duration time;
  final List<(AppMediaItem, int)> topSongs;
  final List<(String, int)> topArtists;

  const ListeningStats({
    required this.plays,
    required this.time,
    required this.topSongs,
    required this.topArtists,
  });

  /// [entries]: each song with its play count. Time assumes every play ran
  /// to the end (3.5 min when the length isn't known).
  factory ListeningStats.from(
    Iterable<({AppMediaItem item, int plays, int playedAt})> entries, {
    int top = 5,
  }) {
    var plays = 0;
    var seconds = 0;
    final artists = <String, int>{};
    for (final e in entries) {
      plays += e.plays;
      seconds += e.plays * (e.item.duration?.inSeconds ?? 210);
      final artist = mainArtist(e.item.artist);
      if (artist.isNotEmpty) {
        artists[artist] = (artists[artist] ?? 0) + e.plays;
      }
    }
    final songs = [for (final e in entries) (e.item, e.plays)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final byArtist = artists.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return ListeningStats(
      plays: plays,
      time: Duration(seconds: seconds),
      topSongs: songs.take(top).toList(),
      topArtists: byArtist.take(top).toList(),
    );
  }
}

/// "A, B & C" → "A": the lead artist, for counting and mixes.
String mainArtist(String artists) {
  final first = artists.split(RegExp(r',|&| feat\.? | ft\.? ')).first.trim();
  return first == 'Unknown Artist' ? '' : first;
}
