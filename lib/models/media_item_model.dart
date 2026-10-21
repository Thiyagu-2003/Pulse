import 'package:audio_service/audio_service.dart';

/// Where a track comes from.
///
/// The `youtube` value name is persisted — it is written into every saved
/// favorite, playlist, download and history entry as `sourceType.name`, and
/// `fromJson` falls back to `local` for anything it doesn't recognise. So it
/// must not be renamed: doing so would quietly turn every stored online track
/// into a local one pointing at a file that isn't there. User-facing wording
/// lives in [MediaSourceLabel] instead.
enum MediaSourceType {
  local,
  youtube,
  podcast,

  /// JioSaavn: the Online source since 2026-09-25. Its CDN URLs don't
  /// expire, so the URL saved on the item is played directly.
  saavn,
}

extension MediaSourceLabel on MediaSourceType {
  /// What the user sees. The app presents three libraries — what's on the
  /// device, what's online, and podcasts — and naming the provider tells them
  /// nothing useful about a track.
  String get label => switch (this) {
    MediaSourceType.local => 'Local',
    MediaSourceType.youtube => 'Online',
    MediaSourceType.saavn => 'Online',
    MediaSourceType.podcast => 'Podcast',
  };
}

extension MediaSourceOnline on MediaSourceType {
  /// Online songs (YouTube or JioSaavn).
  bool get isOnline =>
      this == MediaSourceType.youtube || this == MediaSourceType.saavn;

  /// Can be saved to the device: online songs and podcast episodes.
  bool get isDownloadable => isOnline || this == MediaSourceType.podcast;
}

/// The album shown for online tracks that have no real album of their own.
const String onlineAlbumLabel = 'Online Music';

class AppMediaItem {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? artUri;
  final String? streamUrl;
  final Duration? duration;
  final MediaSourceType sourceType;
  final String? lyrics;
  final Map<String, dynamic>? extras;

  AppMediaItem({
    required this.id,
    required this.title,
    required this.artist,
    this.album = 'Unknown Album',
    this.artUri,
    this.streamUrl,
    this.duration,
    required this.sourceType,
    this.lyrics,
    this.extras,
  });

  MediaItem toAudioServiceMediaItem({String? cachedArtPath}) {
    final artPath = cachedArtPath ??
        (artUri != null && artUri!.startsWith('file://') ? Uri.parse(artUri!).toFilePath() : null);

    Uri? resolvedArtUri;
    if (artPath != null && artPath.isNotEmpty) {
      resolvedArtUri = Uri.file(artPath);
    } else if (artUri != null && artUri!.isNotEmpty) {
      resolvedArtUri = Uri.tryParse(artUri!);
    } else if (sourceType == MediaSourceType.local) {
      final songId = (extras?['songId'] as int?) ?? int.tryParse(id);
      if (songId != null && songId > 0) {
        resolvedArtUri = Uri.parse('content://media/external/audio/media/$songId/albumart');
      }
    }

    return MediaItem(
      id: id,
      album: album,
      title: title,
      artist: artist,
      duration: duration,
      artUri: resolvedArtUri,
      // Canonical fields last: extras copied from an earlier MediaItem carry
      // their own stale 'streamUrl', which must not override the resolved one.
      extras: {
        ...?extras,
        'sourceType': sourceType.name,
        'streamUrl': streamUrl,
        // The broadcast artUri is a local file for the notification; this
        // keeps the item's own (web) art for the UI and anything that saves it.
        'artUrl': artUri,
      },
    );
  }

  factory AppMediaItem.fromAudioServiceMediaItem(MediaItem item) {
    return AppMediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown Artist',
      album: item.album ?? 'Unknown Album',
      artUri: item.extras != null && item.extras!.containsKey('artUrl')
          ? item.extras!['artUrl'] as String?
          : _savedArt(item.artUri?.toString()),
      duration: item.duration,
      streamUrl: item.extras?['streamUrl'] as String?,
      sourceType: MediaSourceType.values.firstWhere(
        (e) => e.name == item.extras?['sourceType'],
        orElse: () => MediaSourceType.local,
      ),
      extras: item.extras,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'artUri': artUri,
    'streamUrl': streamUrl,
    'durationMs': duration?.inMilliseconds,
    'sourceType': sourceType.name,
    'lyrics': lyrics,
    'extras': extras,
  };

  /// Favorites, playlists, history and downloads saved before the UI stopped
  /// naming the provider still carry the old album label in their stored
  /// JSON. Normalising on read fixes entries already on the device, rather
  /// than only affecting newly fetched tracks.
  static String _displayAlbum(String? stored) {
    if (stored == null || stored.isEmpty) return 'Unknown Album';
    return stored == 'YouTube Music' ? onlineAlbumLabel : stored;
  }

  /// Items saved from Now Playing before 'artUrl' existed stored the
  /// notification's cached/placeholder file as their art; that file is not
  /// the track's art, so it's dropped and the art is resolved afresh.
  static String? _savedArt(String? stored) =>
      stored != null && stored.contains('/pulse_artwork/') ? null : stored;

  factory AppMediaItem.fromJson(Map<String, dynamic> json) => AppMediaItem(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: _displayAlbum(json['album'] as String?),
    artUri: _savedArt(json['artUri'] as String?),
    streamUrl: json['streamUrl'] as String?,
    duration: json['durationMs'] != null
        ? Duration(milliseconds: json['durationMs'] as int)
        : null,
    sourceType: MediaSourceType.values.firstWhere(
      (e) => e.name == json['sourceType'],
      orElse: () => MediaSourceType.local,
    ),
    lyrics: json['lyrics'] as String?,
    extras: json['extras'] as Map<String, dynamic>?,
  );
}
