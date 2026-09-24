import 'package:audio_service/audio_service.dart';

/// Where a track comes from.
///
/// The `youtube` value name is persisted — it is written into every saved
/// favorite, playlist, download and history entry as `sourceType.name`, and
/// `fromJson` falls back to `local` for anything it doesn't recognise. So it
/// must not be renamed: doing so would quietly turn every stored online track
/// into a local one pointing at a file that isn't there. User-facing wording
/// lives in [MediaSourceLabel] instead.
enum MediaSourceType { local, youtube, podcast }

extension MediaSourceLabel on MediaSourceType {
  /// What the user sees. The app presents three libraries — what's on the
  /// device, what's online, and podcasts — and naming the provider tells them
  /// nothing useful about a track.
  String get label => switch (this) {
        MediaSourceType.local => 'Local',
        MediaSourceType.youtube => 'Online',
        MediaSourceType.podcast => 'Podcast',
      };
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

  MediaItem toAudioServiceMediaItem() {
    return MediaItem(
      id: id,
      album: album,
      title: title,
      artist: artist,
      duration: duration,
      artUri: artUri != null && artUri!.isNotEmpty ? Uri.tryParse(artUri!) : null,
      // Canonical fields last: extras copied from an earlier MediaItem carry
      // their own stale 'streamUrl', which must not override the resolved one.
      extras: {
        ...?extras,
        'sourceType': sourceType.name,
        'streamUrl': streamUrl,
      },
    );
  }

  factory AppMediaItem.fromAudioServiceMediaItem(MediaItem item) {
    return AppMediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown Artist',
      album: item.album ?? 'Unknown Album',
      artUri: item.artUri?.toString(),
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

  factory AppMediaItem.fromJson(Map<String, dynamic> json) => AppMediaItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: _displayAlbum(json['album'] as String?),
        artUri: json['artUri'] as String?,
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
