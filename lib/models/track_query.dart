import 'media_item_model.dart';

/// Filtering and sorting for track lists. Pure and free of Flutter imports so
/// it can be unit tested directly.

enum TrackSort { title, artist, album, longest }

extension TrackSortLabel on TrackSort {
  String get label => switch (this) {
    TrackSort.title => 'Title',
    TrackSort.artist => 'Artist',
    TrackSort.album => 'Album',
    TrackSort.longest => 'Longest first',
  };
}

/// Case-insensitive match across title, artist and album. An empty or
/// whitespace-only query returns the list unchanged.
List<AppMediaItem> filterTracks(List<AppMediaItem> tracks, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return tracks;

  return tracks.where((track) {
    return track.title.toLowerCase().contains(needle) ||
        track.artist.toLowerCase().contains(needle) ||
        track.album.toLowerCase().contains(needle);
  }).toList();
}

/// Returns a sorted copy. Never sorts in place: callers hold the unfiltered
/// list as their source of truth and would otherwise see it reordered under
/// them.
List<AppMediaItem> sortTracks(List<AppMediaItem> tracks, TrackSort sort) {
  int byTitle(AppMediaItem a, AppMediaItem b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  final comparator = switch (sort) {
    TrackSort.title => byTitle,
    // Grouping sorts fall back to title so an artist's or album's tracks come
    // out in a stable, readable order rather than whatever order they loaded.
    TrackSort.artist => (AppMediaItem a, AppMediaItem b) {
      final result = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      return result != 0 ? result : byTitle(a, b);
    },
    TrackSort.album => (AppMediaItem a, AppMediaItem b) {
      final result = a.album.toLowerCase().compareTo(b.album.toLowerCase());
      return result != 0 ? result : byTitle(a, b);
    },
    TrackSort.longest =>
      (AppMediaItem a, AppMediaItem b) =>
          (b.duration ?? Duration.zero).compareTo(a.duration ?? Duration.zero),
  };

  return [...tracks]..sort(comparator);
}
