import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/media_item_model.dart';

class LocalMusicService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Request storage/audio permissions for Android & iOS.
  ///
  /// Uses the plugin's own permission API so the permission set matches
  /// exactly what `querySongs` checks natively (READ_MEDIA_AUDIO +
  /// READ_MEDIA_IMAGES on Android 13+, READ/WRITE_EXTERNAL_STORAGE on older).
  Future<bool> requestPermission() async {
    // Needed for the playback notification; not fatal if refused.
    await Permission.notification.request();

    // Use the plugin's unified check-and-request which handles both
    // READ_MEDIA_AUDIO and READ_MEDIA_IMAGES on API 33+.
    final granted = await _audioQuery.checkAndRequest();
    return granted;
  }

  /// Scan local device for audio tracks
  Future<List<AppMediaItem>> fetchLocalSongs() async {
    try {
      // Guard: only call querySongs when the plugin considers permissions
      // granted.  The native side has a bug where it sends both result.error
      // AND result.success when permissions are missing, crashing the app with
      // "Reply already submitted" (fixed via a return in the Kotlin source,
      // but this guard is kept as a safety net).
      final hasAccess = await _audioQuery.permissionsStatus();
      if (!hasAccess) {
        debugPrint('fetchLocalSongs: skipped — plugin reports no permission');
        return [];
      }

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
      debugPrint('Local song scan failed: $e');
      return [];
    }
  }
}

