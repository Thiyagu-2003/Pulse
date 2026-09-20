import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/media_item_model.dart';

class LocalMusicService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Request storage/audio permissions for Android & iOS
  Future<bool> requestPermission() async {
    // On Android 13+ (API 33+), use READ_MEDIA_AUDIO
    // On older Android, use READ_EXTERNAL_STORAGE
    final audioStatus = await Permission.audio.request();
    final notificationStatus = await Permission.notification.request();
    if (audioStatus.isGranted) return true;

    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) return true;

    return false;
  }

  /// Scan local device for audio tracks
  Future<List<AppMediaItem>> fetchLocalSongs() async {
    try {
      final List<SongModel> songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      return songs
          .where((song) => (song.duration ?? 0) > 10000) // Skip short sound effects <10s
          .map((song) => AppMediaItem(
                id: song.id.toString(),
                title: song.title.isNotEmpty ? song.title : 'Unknown Title',
                artist: song.artist != '<unknown>' && song.artist != null
                    ? song.artist!
                    : 'Local Track',
                album: song.album ?? 'Local Storage',
                // Prefer URI (content://) for Android, fallback to file path
                streamUrl: song.uri ?? song.data,
                duration: song.duration != null
                    ? Duration(milliseconds: song.duration!)
                    : null,
                sourceType: MediaSourceType.local,
                extras: {
                  'songId': song.id,
                  'filePath': song.data,
                  'uri': song.uri,
                },
              ))
          .toList();
    } catch (e) {
      return [];
    }
  }
}
