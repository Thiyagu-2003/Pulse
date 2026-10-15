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
  Directory? _cacheDir;
  final Map<String, String> _memoryPathCache = {};

  /// The placeholder follows the app icon style (Settings > App icon); the
  /// provider keeps this in step with the setting.
  bool dark = false;
  final Map<bool, String> _placeholders = {};

  String? get defaultArtPath => _placeholders[dark];

  /// Initializes the artwork cache and extracts both app-icon placeholders.
  Future<void> init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${supportDir.path}/pulse_artwork');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      for (final isDark in const [true, false]) {
        final name = isDark ? 'app_icon_dark.png' : 'app_icon_light.png';
        final file = File('${_cacheDir!.path}/$name');
        if (!await file.exists()) {
          try {
            final byteData = await rootBundle.load('icons/$name');
            await file.writeAsBytes(
              byteData.buffer.asUint8List(
                byteData.offsetInBytes,
                byteData.lengthInBytes,
              ),
              flush: true,
            );
          } catch (e) {
            debugPrint('Failed to extract $name asset: $e');
          }
        }
        if (await file.exists()) _placeholders[isDark] = file.path;
      }
    } catch (e) {
      debugPrint('ArtworkService init failed: $e');
    }
  }

  /// The art the notification gets at once: a cached file; else, for a web
  /// image, nothing here — the broadcast keeps the URL and audio_service
  /// fetches it itself (our own fetch-then-swap left the placeholder showing
  /// on phones); else the placeholder.
  String? notificationArt(AppMediaItem item) {
    final cached = getCachedArtPath(item);
    if (cached != null) return cached;
    if (item.artUri?.startsWith('http') ?? false) return null;
    return defaultArtPath;
  }

  /// Synchronously returns an already-cached file path, or null.
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

    return null;
  }

  /// Asynchronously resolves the highest quality artwork file for [item].
  /// Guaranteed to return either the track's extracted/downloaded art file,
  /// or [defaultArtPath].
  Future<String?> resolveArtwork(AppMediaItem item) async {
    try {
      if (_cacheDir == null) {
        await init();
      }
      if (_cacheDir == null) return defaultArtPath;

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

    return defaultArtPath;
  }
}
