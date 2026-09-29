import 'media_item_model.dart';

/// Represents a local album containing songs grouped from device storage.
class LocalAlbum {
  final String name;
  final String artist;
  final int? albumId;
  final List<AppMediaItem> songs;

  const LocalAlbum({
    required this.name,
    required this.artist,
    this.albumId,
    required this.songs,
  });

  int get length => songs.length;
}

/// Represents a local artist containing songs grouped from device storage.
class LocalArtist {
  final String name;
  final int? artistId;
  final List<AppMediaItem> songs;

  const LocalArtist({
    required this.name,
    this.artistId,
    required this.songs,
  });

  int get length => songs.length;

  int get albumCount {
    final albums = songs.map((s) => s.album).where((a) => a.trim().isNotEmpty && a != 'Local Storage').toSet();
    return albums.isEmpty ? 1 : albums.length;
  }
}

/// Represents a local genre containing songs grouped from device storage.
class LocalGenre {
  final String name;
  final List<AppMediaItem> songs;

  const LocalGenre({
    required this.name,
    required this.songs,
  });

  int get length => songs.length;
}

/// Group a list of local songs into [LocalAlbum]s.
List<LocalAlbum> groupByAlbum(List<AppMediaItem> songs) {
  final map = <String, List<AppMediaItem>>{};
  final albumIdMap = <String, int?>{};
  final artistMap = <String, String>{};

  for (final song in songs) {
    final albumName = (song.album.trim().isNotEmpty && song.album != 'Local Storage')
        ? song.album.trim()
        : 'Unknown Album';
    map.putIfAbsent(albumName, () => []).add(song);
    if (!albumIdMap.containsKey(albumName)) {
      albumIdMap[albumName] = song.extras?['albumId'] as int?;
      artistMap[albumName] = song.artist;
    }
  }

  final albums = map.entries.map((e) {
    return LocalAlbum(
      name: e.key,
      artist: artistMap[e.key] ?? 'Various Artists',
      albumId: albumIdMap[e.key],
      songs: e.value,
    );
  }).toList();

  albums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return albums;
}

/// Group a list of local songs into [LocalArtist]s.
List<LocalArtist> groupByArtist(List<AppMediaItem> songs) {
  final map = <String, List<AppMediaItem>>{};
  final artistIdMap = <String, int?>{};

  for (final song in songs) {
    final artistName = (song.artist.trim().isNotEmpty && song.artist != 'Local Track' && song.artist != '<unknown>')
        ? song.artist.trim()
        : 'Unknown Artist';
    map.putIfAbsent(artistName, () => []).add(song);
    if (!artistIdMap.containsKey(artistName)) {
      artistIdMap[artistName] = song.extras?['artistId'] as int?;
    }
  }

  final artists = map.entries.map((e) {
    return LocalArtist(
      name: e.key,
      artistId: artistIdMap[e.key],
      songs: e.value,
    );
  }).toList();

  artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return artists;
}

/// Group a list of local songs into [LocalGenre]s.
List<LocalGenre> groupByGenre(List<AppMediaItem> songs) {
  final map = <String, List<AppMediaItem>>{};

  for (final song in songs) {
    final genre = (song.extras?['genre'] as String?)?.trim();
    final genreName = (genre != null && genre.isNotEmpty) ? genre : 'Music';
    map.putIfAbsent(genreName, () => []).add(song);
  }

  final genres = map.entries.map((e) {
    return LocalGenre(name: e.key, songs: e.value);
  }).toList();

  genres.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return genres;
}

/// Return newly added tracks, newest first.
List<AppMediaItem> getNewlyAdded(List<AppMediaItem> songs, {int limit = 30}) {
  final copy = List<AppMediaItem>.from(songs);
  copy.sort((a, b) {
    final dateA = (a.extras?['dateAdded'] as int?) ?? 0;
    final dateB = (b.extras?['dateAdded'] as int?) ?? 0;
    return dateB.compareTo(dateA);
  });
  return copy.take(limit).toList();
}
