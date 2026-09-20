import 'package:audio_service/audio_service.dart';

enum MediaSourceType { local, youtube, podcast }

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
      extras: {
        'sourceType': sourceType.name,
        'streamUrl': streamUrl,
        ...?extras,
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

  factory AppMediaItem.fromJson(Map<String, dynamic> json) => AppMediaItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: (json['album'] as String?) ?? 'Unknown Album',
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
