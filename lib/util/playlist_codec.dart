import 'dart:convert';
import 'dart:io';

import '../models/media_item_model.dart';
import '../models/playlist.dart';
import '../providers/music_player_provider.dart';

class PlaylistCodec {
  PlaylistCodec._();

  /// Serializes [playlist] to a Pulse JSON map, stripping device-only tracks.
  ///
  /// Returns the JSON map and the number of device-only tracks skipped.
  static ({Map<String, dynamic> json, int skipped}) exportToJson(
    Playlist playlist,
  ) {
    final items = playlist.items
        .map(MusicPlayerProvider.onlineCopy)
        .nonNulls
        .toList();
    return (
      json: {
        'app': 'pulse',
        'type': 'playlist',
        'version': 2,
        'name': playlist.name,
        'items': items.map((t) => t.toJson()).toList(),
      },
      skipped: playlist.length - items.length,
    );
  }

  /// Exports [playlist] to a compact compressed share code string (`pulse://playlist?d=...`).
  static String exportToCode(Playlist playlist) {
    final exported = exportToJson(playlist);
    final jsonString = jsonEncode(exported.json);
    final bytes = utf8.encode(jsonString);
    final compressed = gzip.encode(bytes);
    final base64 = base64Url.encode(compressed);
    return 'pulse://playlist?d=$base64';
  }

  /// Parses a share code, URL, or chat message containing a code into playlist JSON.
  static Map<String, dynamic> parseCodeOrText(String text) {
    final payload = _extractPayload(text);
    final normalized = _padBase64(payload);
    final bytes = _decodeBase64(normalized);
    final decompressed = gzip.decode(bytes);
    final jsonString = utf8.decode(decompressed);
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const FormatException('Decoded data is not a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Validates a Pulse playlist JSON map and parses downloadable tracks.
  static ({String name, List<AppMediaItem> items}) validatePlaylistJson(
    Map<String, dynamic> json,
  ) {
    final app = json['app'];
    final type = json['type'];
    final name = json['name'];
    final items = json['items'];

    if (app != 'pulse' ||
        type != 'playlist' ||
        name is! String ||
        name.trim().isEmpty ||
        items is! List) {
      throw const FormatException('Invalid Pulse playlist format');
    }

    final tracks = [
      for (final item in items)
        if (item is Map) AppMediaItem.fromJson(Map<String, dynamic>.from(item)),
    ].where((t) => t.sourceType.isDownloadable).toList();

    return (name: name, items: tracks);
  }

  /// Safely parses a raw string that could be a JSON playlist document,
  /// a `pulse://playlist?d=...` URL, or a compressed code/message.
  /// Returns `null` if parsing fails.
  static ({String name, List<AppMediaItem> items})? parseAny(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. Try direct JSON parsing
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return validatePlaylistJson(decoded);
        } else if (decoded is Map) {
          return validatePlaylistJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }

    // 2. Try URL / compressed share code parsing
    try {
      final jsonMap = parseCodeOrText(trimmed);
      return validatePlaylistJson(jsonMap);
    } catch (_) {}

    // 3. Fallback: try decoding as raw JSON if not matching exact braces
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return validatePlaylistJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}

    return null;
  }

  /// Whether a playlist is large enough to show a warning or progress indicator.
  static bool isLargePlaylist(int count) => count > 100;

  static String _extractPayload(String text) {
    final linkMatch = RegExp(
      r'pulse:\/\/playlist[^\s]*[?&]d=([A-Za-z0-9_-]+={0,2})',
    ).firstMatch(text);
    if (linkMatch != null) return linkMatch.group(1)!;

    final pulseMatch = RegExp(
      r'PULSE:\s*([A-Za-z0-9_-]+={0,2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (pulseMatch != null) return pulseMatch.group(1)!;

    final gzipMatch = RegExp(r'(H4sI[A-Za-z0-9_-]+={0,2})').firstMatch(text);
    if (gzipMatch != null) return gzipMatch.group(1)!;

    final wordMatch = RegExp(r'([A-Za-z0-9_-]{20,}={0,2})').firstMatch(text);
    if (wordMatch != null) return wordMatch.group(1)!;

    return text.trim();
  }

  static String _padBase64(String input) {
    final remainder = input.length % 4;
    if (remainder == 2) return '$input==';
    if (remainder == 3) return '$input=';
    return input;
  }

  static List<int> _decodeBase64(String payload) {
    try {
      return base64Url.decode(payload);
    } catch (_) {
      return base64.decode(payload);
    }
  }
}
