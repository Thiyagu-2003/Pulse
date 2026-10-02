import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item_model.dart';
import 'playback_cache.dart';
import 'youtube_service.dart';

/// The type of sound the user wants to replace on the device.
enum RingtoneType { ringtone, notification, alarm }

/// Handles trimming and setting a song as the device ringtone, notification
/// sound, or alarm tone.  Android-only — guarded by [Platform.isAndroid] at
/// the call site.
class RingtoneService {
  static const _channel = MethodChannel('pulse/platform');

  final YoutubeService _ytService = YoutubeService();

  /// A lightweight preview player used by the trimmer screen.
  AudioPlayer? _previewPlayer;

  AudioPlayer get previewPlayer {
    _previewPlayer ??= AudioPlayer();
    return _previewPlayer!;
  }

  /// Release the preview player once the trimmer is closed.
  void disposePreview() {
    _previewPlayer?.dispose();
    _previewPlayer = null;
  }

  // ── Resolve a playable file path ──────────────────────────────────────

  /// Returns a local file path that can be read by Android's RingtoneManager.
  /// For local tracks, this resolves either a direct filesystem path or caches
  /// the MediaStore content URI into a temporary audio file. For online tracks,
  /// the audio is cached or downloaded to a temporary file first.
  Future<String?> resolveFilePath(AppMediaItem item) async {
    // 1. Direct local file path that already exists and is readable on disk.
    final candidatePaths = <String?>[
      item.streamUrl,
      item.extras?['filePath'] as String?,
      if (item.id.startsWith('/') || item.id.contains(Platform.pathSeparator))
        item.id
      else
        null,
    ];

    for (final path in candidatePaths) {
      if (path != null &&
          path.isNotEmpty &&
          !path.startsWith('http') &&
          !path.startsWith('content://')) {
        final file = File(path);
        if (await file.exists()) {
          try {
            // Verify readability (guards against Android 11+ Scoped Storage restriction)
            final raf = await file.open(mode: FileMode.read);
            await raf.close();
            return path;
          } catch (e) {
            debugPrint('RingtoneService: direct file access restricted for $path: $e');
          }
        }
      }
    }

    // 2. Check if this is a local track with a content:// URI or MediaStore ID.
    final rawSongId = item.extras?['songId']?.toString() ??
        (RegExp(r'^\d+$').hasMatch(item.id) ? item.id : null);
    final contentUri = (item.streamUrl?.startsWith('content://') ?? false)
        ? item.streamUrl
        : (item.extras?['uri'] as String? ??
            (rawSongId != null
                ? 'content://media/external/audio/media/$rawSongId'
                : null));

    if (contentUri != null && contentUri.startsWith('content://')) {
      final cachedLocal = await _cacheLocalContentUri(item, contentUri);
      if (cachedLocal != null) {
        return cachedLocal;
      }
    }

    // 3. Check if already stored in PlaybackCache.
    final cached = await PlaybackCache.instance.find(item.id);
    if (cached != null && await File(cached).exists()) {
      return cached;
    }

    // 4. Cache via YoutubeService (handles both JioSaavn and YouTube).
    try {
      final cachedPath = await _ytService.cacheForPlayback(item);
      if (cachedPath != null && await File(cachedPath).exists()) {
        return cachedPath;
      }
    } catch (e) {
      debugPrint('RingtoneService: cacheForPlayback failed: $e');
    }

    // 5. Fallback: if we have or can extract a direct stream URL, download it.
    try {
      String? url = item.streamUrl;
      if (url == null || url.isEmpty) {
        if (item.sourceType == MediaSourceType.youtube) {
          url = await _ytService.getAudioStreamUrl(item.id);
        }
      }
      if (url != null && url.startsWith('http')) {
        final dir = await getTemporaryDirectory();
        final safeName = item.title
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_');
        final file = File('${dir.path}/ringtone_${item.id}_$safeName.m4a');
        if (await file.exists()) return file.path;

        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
          return file.path;
        }
      }
    } catch (e) {
      debugPrint('RingtoneService: direct download fallback failed: $e');
    }

    return null;
  }

  /// Copies a local MediaStore content URI into a temporary file so that
  /// just_audio and Android's RingtoneManager can read it directly.
  Future<String?> _cacheLocalContentUri(
    AppMediaItem item,
    String contentUri,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = item.extras?['filePath'] as String? ?? item.streamUrl;
      String ext = 'mp3';
      if (filePath != null && filePath.contains('.')) {
        final candidateExt = filePath.split('.').last.toLowerCase();
        if (candidateExt.length <= 5 &&
            RegExp(r'^[a-z0-9]+$').hasMatch(candidateExt)) {
          ext = candidateExt;
        }
      }
      final safeTitle = item.title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final targetFile = File(
        '${dir.path}/ringtone_local_${item.id}_$safeTitle.$ext',
      );

      if (await targetFile.exists() && (await targetFile.length()) > 0) {
        return targetFile.path;
      }

      final success = await _channel.invokeMethod<bool>('copyUriToFile', {
        'uri': contentUri,
        'destPath': targetFile.path,
      });

      if (success == true &&
          await targetFile.exists() &&
          (await targetFile.length()) > 0) {
        return targetFile.path;
      }
    } catch (e) {
      debugPrint('RingtoneService: _cacheLocalContentUri failed: $e');
    }
    return null;
  }

  // ── Set ringtone via platform channel ─────────────────────────────────

  /// Trims the audio from [startMs] to [endMs] (in milliseconds) and sets it
  /// as the given [type].  Returns true on success.
  Future<bool> setAsRingtone({
    required String filePath,
    required String title,
    required String artist,
    required int startMs,
    required int endMs,
    required RingtoneType type,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('setRingtone', {
        'filePath': filePath,
        'title': title,
        'artist': artist,
        'startMs': startMs,
        'endMs': endMs,
        'type': type.name,    // "ringtone" | "notification" | "alarm"
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('setRingtone PlatformException: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Check whether the app has the WRITE_SETTINGS permission (required on
  /// Android to change the default ringtone).
  Future<bool> hasWriteSettingsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasWriteSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system screen that lets the user grant WRITE_SETTINGS.
  Future<void> requestWriteSettingsPermission() async {
    try {
      await _channel.invokeMethod<void>('requestWriteSettings');
    } catch (_) {
      // best-effort
    }
  }
}
