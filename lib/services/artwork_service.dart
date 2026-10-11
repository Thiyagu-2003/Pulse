import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_item_model.dart';

/// Manages resolution and local file caching of artwork for media items.
///
/// Ensures that both Android/MIUI media notifications and home screen widgets
/// have access to a valid local image file on disk. This prevents OEM ROMs
/// (such as MIUI 14 on Android 13) from falling back to low-contrast Dynamic
/// Monet colors that cause white-on-light unreadable / washed-out notification cards.
class ArtworkService {
  ArtworkService._();
  static final ArtworkService instance = ArtworkService._();

  final OnAudioQuery _audioQuery = OnAudioQuery();
  String? _defaultArtPath;
  Directory? _cacheDir;
  final Map<String, String> _memoryPathCache = {};

  String? get defaultArtPath => _defaultArtPath;

  /// Initializes the artwork cache and extracts the bundled dark Pulse album art.
  Future<void> init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${supportDir.path}/pulse_artwork');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      final defaultArtFile = File('${_cacheDir!.path}/default_album_art.jpg');
      if (!await defaultArtFile.exists()) {
        try {
          final byteData = await rootBundle.load('icons/default_album_art.jpg');
          await defaultArtFile.writeAsBytes(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
            flush: true,
          );
        } catch (e) {
          debugPrint('Failed to extract default_album_art asset: $e');
        }
      }

      if (await defaultArtFile.exists()) {
        _defaultArtPath = defaultArtFile.path;
      }
    } catch (e) {
      debugPrint('ArtworkService init failed: $e');
    }
  }

  /// Synchronously returns an already-cached file path if available,
  /// otherwise returns [_defaultArtPath].
  String? getCachedArtPath(AppMediaItem item) {
    if (_memoryPathCache.containsKey(item.id)) {
      final path = _memoryPathCache[item.id]!;
      if (File(path).existsSync()) return path;
    }

    if (_cacheDir != null) {
      if (item.sourceType == MediaSourceType.local) {
        final songId =
            (item.extras?['songId'] as int?) ?? int.tryParse(item.id);
        if (songId != null && songId > 0) {
          final file = File('${_cacheDir!.path}/local_$songId.jpg');
          if (file.existsSync()) {
            _memoryPathCache[item.id] = file.path;
            return file.path;
          }
        }
      } else if (item.artUri != null && item.artUri!.isNotEmpty) {
        final url = item.artUri!;
        if (url.startsWith('file://')) {
          final filePath = Uri.parse(url).toFilePath();
          if (File(filePath).existsSync()) return filePath;
        } else if (File(url).existsSync()) {
          return url;
        } else {
          final hash = url.hashCode.abs();
          final file = File('${_cacheDir!.path}/net_$hash.jpg');
          if (file.existsSync()) {
            _memoryPathCache[item.id] = file.path;
            return file.path;
          }
        }
      }
    }

    return _defaultArtPath;
  }

  /// Asynchronously resolves the highest quality artwork file for [item].
  /// Guaranteed to return either the track's extracted/downloaded art file,
  /// or [_defaultArtPath].
  Future<String?> resolveArtwork(AppMediaItem item) async {
    try {
      if (_cacheDir == null) {
        await init();
      }
      if (_cacheDir == null) return _defaultArtPath;

      // 1. Check local audio track
      if (item.sourceType == MediaSourceType.local) {
        final songId =
            (item.extras?['songId'] as int?) ?? int.tryParse(item.id);
        if (songId != null && songId > 0) {
          final target = File('${_cacheDir!.path}/local_$songId.jpg');
          if (await target.exists() && (await target.length()) > 0) {
            _memoryPathCache[item.id] = target.path;
            return target.path;
          }

          if (Platform.isAndroid) {
            try {
              final bytes = await _audioQuery.queryArtwork(
                songId,
                ArtworkType.AUDIO,
                format: ArtworkFormat.JPEG,
                size: 512,
                quality: 85,
              );
              if (bytes != null && bytes.isNotEmpty) {
                await target.writeAsBytes(bytes, flush: true);
                _memoryPathCache[item.id] = target.path;
                return target.path;
              }

              // Fallback to album artwork query
              final albumId = item.extras?['albumId'] as int?;
              if (albumId != null && albumId > 0) {
                final albumBytes = await _audioQuery.queryArtwork(
                  albumId,
                  ArtworkType.ALBUM,
                  format: ArtworkFormat.JPEG,
                  size: 512,
                  quality: 85,
                );
                if (albumBytes != null && albumBytes.isNotEmpty) {
                  await target.writeAsBytes(albumBytes, flush: true);
                  _memoryPathCache[item.id] = target.path;
                  return target.path;
                }
              }
            } catch (e) {
              debugPrint('AudioQuery artwork error for song $songId: $e');
            }
          }
        }
      }

      // 2. Check network / remote artwork
      final url = item.artUri;
      if (url != null && url.isNotEmpty) {
        if (url.startsWith('file://')) {
          final path = Uri.parse(url).toFilePath();
          if (await File(path).exists()) return path;
        } else if (await File(url).exists()) {
          return url;
        } else if (url.startsWith('http://') || url.startsWith('https://')) {
          final hash = url.hashCode.abs();
          final target = File('${_cacheDir!.path}/net_$hash.jpg');
          if (await target.exists() && (await target.length()) > 0) {
            _memoryPathCache[item.id] = target.path;
            return target.path;
          }

          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await target.writeAsBytes(response.bodyBytes, flush: true);
            _memoryPathCache[item.id] = target.path;
            return target.path;
          }
        }
      }
    } catch (e) {
      debugPrint('Error resolving artwork for "${item.title}": $e');
    }

    return _defaultArtPath;
  }
}
