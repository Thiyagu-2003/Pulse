import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/media_item_model.dart';
import 'storage_service.dart';

class LocalScanProgress {
  final bool isScanning;
  final int count;
  final String message;

  const LocalScanProgress({
    required this.isScanning,
    required this.count,
    required this.message,
  });
}

class LocalMusicService {
  static final LocalMusicService instance = LocalMusicService._();
  factory LocalMusicService() => instance;
  LocalMusicService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();
  List<AppMediaItem> _cachedSongs = [];

  final StreamController<LocalScanProgress> _progressController =
      StreamController<LocalScanProgress>.broadcast();

  Stream<LocalScanProgress> get scanProgress => _progressController.stream;
  List<AppMediaItem> get cachedSongs => _cachedSongs;

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

  /// Scan local device and SD card for audio tracks with fast caching.
  Future<List<AppMediaItem>> fetchLocalSongs({bool forceRescan = false}) async {
    if (!forceRescan && _cachedSongs.isNotEmpty) {
      return _cachedSongs;
    }

    _progressController.add(const LocalScanProgress(
      isScanning: true,
      count: 0,
      message: 'Scanning storage & SD card...',
    ));

    // The media index (on_audio_query) is Android's; elsewhere, read the
    // Music folder directly.
    if (!Platform.isAndroid) {
      final custom = StorageService().getCustomDownloadPath();
      final songs = await scanFolder(musicFolder(), skip: custom);
      _cachedSongs = songs;
      _progressController.add(LocalScanProgress(
        isScanning: false,
        count: songs.length,
        message: 'Scan complete (${songs.length} songs)',
      ));
      return songs;
    }

    try {
      final List<SongModel> songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final List<AppMediaItem> result = songs
          .where((song) => (song.duration ?? 0) > 10000) // Skip short sound effects <10s
          .map((song) => AppMediaItem(
                id: song.id.toString(),
                title: song.title.isNotEmpty ? song.title : 'Unknown Title',
                artist: song.artist != '<unknown>' && song.artist != null
                    ? song.artist!
                    : 'Local Track',
                album: song.album ?? 'Local Storage',
                streamUrl: song.uri ?? song.data,
                duration: song.duration != null
                    ? Duration(milliseconds: song.duration!)
                    : null,
                sourceType: MediaSourceType.local,
                extras: {
                  'songId': song.id,
                  'albumId': song.albumId,
                  'artistId': song.artistId,
                  'genre': song.genre,
                  'dateAdded': song.dateAdded,
                  'filePath': song.data,
                  'uri': song.uri,
                },
              ))
          .toList();

      _progressController.add(LocalScanProgress(
        isScanning: true,
        count: result.length,
        message: 'Checking SD card storage...',
      ));

      // Direct SD card scan check for unindexed tracks:
      try {
        final storageDir = Directory('/storage');
        if (await storageDir.exists()) {
          final entries = await storageDir.list().toList();
          final existingPaths = result
              .map((s) => (s.extras?['filePath'] as String?)?.toLowerCase())
              .where((p) => p != null)
              .toSet();

          for (final entry in entries) {
            final name = entry.path.split('/').where((s) => s.isNotEmpty).last;
            if (name != 'emulated' && name != 'self' && name != 'enc_emulated') {
              final sdSongs = await scanFolder(Directory(entry.path));
              for (final sdSong in sdSongs) {
                final p = (sdSong.extras?['filePath'] as String?)?.toLowerCase();
                if (p != null && !existingPaths.contains(p)) {
                  result.add(sdSong);
                  existingPaths.add(p);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('SD card probe error: $e');
      }

      result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _cachedSongs = result;

      _progressController.add(LocalScanProgress(
        isScanning: false,
        count: result.length,
        message: 'Scan complete (${result.length} songs)',
      ));

      return result;
    } catch (e) {
      debugPrint('Local song scan failed: $e');
      _progressController.add(LocalScanProgress(
        isScanning: false,
        count: _cachedSongs.length,
        message: 'Scan failed: $e',
      ));
      return _cachedSongs;
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
