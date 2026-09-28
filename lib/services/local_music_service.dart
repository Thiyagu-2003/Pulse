import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/media_item_model.dart';
import 'storage_service.dart';

class LocalMusicService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Request storage/audio permissions safely using permission_handler
  /// to avoid on_audio_query_pluse's "Reply already submitted" crash.
  ///
  /// Once Android marks the permission permanently denied, request() returns
  /// without showing anything; [openSettingsIfBlocked] sends the user to app
  /// settings instead, so "Grant Access" isn't a dead button.
  Future<bool> requestPermission({bool openSettingsIfBlocked = false}) async {
    // Desktop: files are readable as they are; nothing to ask.
    if (!Platform.isAndroid) return true;
    try {
      await Permission.notification.request();

      if (Platform.isAndroid) {
        final audioStatus = await Permission.audio.status;
        if (audioStatus.isGranted) return true;

        final storageStatus = await Permission.storage.status;
        if (storageStatus.isGranted) return true;

        final reqAudio = await Permission.audio.request();
        if (reqAudio.isGranted) return true;

        final reqStorage = await Permission.storage.request();
        if (reqStorage.isGranted) return true;

        if (openSettingsIfBlocked &&
            (reqAudio.isPermanentlyDenied || reqStorage.isPermanentlyDenied)) {
          await openAppSettings();
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  /// Whether audio can be read, without asking.
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await Permission.audio.status).isGranted ||
          (await Permission.storage.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Scan local device for audio tracks
  Future<List<AppMediaItem>> fetchLocalSongs() async {
    // The media index (on_audio_query) is Android's; elsewhere, read the
    // Music folder directly.
    if (!Platform.isAndroid) {
      // Downloads are in Library already; a download folder inside Music
      // would list them twice.
      final custom = StorageService().getCustomDownloadPath();
      return scanFolder(musicFolder(), skip: custom);
    }
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
      debugPrint('Local song scan failed: $e');
      return [];
    }
  }

  /// The user's Music folder (Windows: %USERPROFILE%\Music).
  static Directory musicFolder() => Directory(
        '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.'}'
        '${Platform.pathSeparator}Music',
      );

  static const _audioExtensions = {
    '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma',
  };

  /// Every audio file under [root], sorted by title. Pulse's own downloads
  /// (the "Pulse" subfolder) are left out: they're in Library already.
  @visibleForTesting
  static Future<List<AppMediaItem>> scanFolder(
    Directory root, {
    String? skip,
  }) async {
    // Compared with "/" separators and case-folded: the saved folder and the
    // scanned paths may spell the same place differently on Windows.
    String norm(String p) => p.replaceAll('\\', '/').toLowerCase();
    final skipped = skip == null || skip.isEmpty
        ? null
        : '${norm(Directory(skip).absolute.path)}/';
    final songs = <AppMediaItem>[];
    if (!await root.exists()) return songs;
    final sep = Platform.pathSeparator;
    await for (final entity in root
        .list(recursive: true, followLinks: false)
        // A folder that can't be read is skipped, not the whole scan.
        .handleError((Object e) => debugPrint('Skipping unreadable: $e'))) {
      if (entity is! File) continue;
      final path = entity.path;
      final lower = path.toLowerCase();
      final dot = lower.lastIndexOf('.');
      if (dot < 0 || !_audioExtensions.contains(lower.substring(dot))) continue;
      if (path.contains('$sep${'Pulse'}$sep')) continue;
      if (skipped != null && norm(path).startsWith(skipped)) continue;
      final name = path.substring(path.lastIndexOf(sep) + 1, dot);
      // "Artist - Title" is the usual file naming.
      final split = name.indexOf(' - ');
      songs.add(AppMediaItem(
        id: '${path.hashCode & 0x7fffffff}', // digits: a device song
        title: split > 0 ? name.substring(split + 3).trim() : name,
        artist: split > 0 ? name.substring(0, split).trim() : 'Local Track',
        album: entity.parent.path.substring(entity.parent.path.lastIndexOf(sep) + 1),
        streamUrl: path,
        sourceType: MediaSourceType.local,
        extras: {'filePath': path},
      ));
    }
    songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return songs;
  }
}
