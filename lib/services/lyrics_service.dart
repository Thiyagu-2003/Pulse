import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/lyrics.dart';
import 'saavn_service.dart';

class LyricsService {
  /// Lyrics for a song, time-synced whenever possible.
  ///
  /// LRCLIB (the open lyrics database) is asked first because it has
  /// *synced* lyrics — measured: all 15 of the day's Tamil trending songs —
  /// which let Now Playing highlight and follow the line being sung.
  /// JioSaavn's own lyrics ([saavnId]) are plain text; they're fetched at the
  /// same time and used when LRCLIB has nothing synced. A synced match is
  /// only trusted if its length agrees with [duration] (±5s), so another
  /// song's lyrics never scroll past.
  Future<Lyrics?> fetch(
    String title,
    String artist, {
    String? saavnId,
    Duration? duration,
  }) async {
    final saavn = saavnId == null
        ? Future<String?>.value(null)
        : SaavnService.instance.lyrics(saavnId).catchError((Object e) {
            debugPrint('JioSaavn lyrics failed: $e');
            return null;
          });

    final candidates = await _lrclibCandidates(title, artist);
    for (final c in candidates) {
      final synced = c['syncedLyrics'];
      if (synced is String && synced.trim().isNotEmpty && _sameLength(c, duration)) {
        final lines = Lyrics.parseLrc(synced);
        if (lines.isNotEmpty) return Lyrics.synced(lines, 'LRCLIB');
      }
    }

    final fromSaavn = await saavn;
    if (fromSaavn != null && fromSaavn.trim().isNotEmpty) {
      return Lyrics.plainText(fromSaavn, 'JioSaavn');
    }
    for (final c in candidates) {
      if (!_sameLength(c, duration)) continue;
      final plain = _pickLyrics(c);
      if (plain != null) return Lyrics.plainText(plain, 'LRCLIB');
    }
    return null;
  }

  /// LRCLIB records that might be this song: exact matches (all artists,
  /// then the first — JioSaavn lists "A, B, C", LRCLIB usually just "A"),
  /// then search results.
  Future<List<Map<String, dynamic>>> _lrclibCandidates(
      String title, String artist) async {
    final cleanTitle = cleanQuery(title);
    final cleanArtist = cleanQuery(artist);
    final firstArtist = cleanArtist.split(',').first.trim();
    final out = <Map<String, dynamic>>[];
    try {
      for (final a in {cleanArtist, firstArtist}) {
        final res = await http
            .get(Uri.https('lrclib.net', '/api/get',
                {'track_name': cleanTitle, 'artist_name': a}))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data is Map<String, dynamic>) out.add(data);
        }
      }
      final res = await http
          .get(Uri.https(
              'lrclib.net', '/api/search', {'q': '$firstArtist $cleanTitle'}))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is List) out.addAll(data.whereType<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('LRCLIB lookup failed: $e');
    }
    return out;
  }

  static bool _sameLength(Map<String, dynamic> c, Duration? duration) {
    final theirs = c['duration'];
    if (duration == null || theirs is! num) return true;
    return (theirs - duration.inSeconds).abs() <= 5;
  }

  /// Plain text from an LRCLIB record: its plain lyrics, or its synced ones
  /// with the `[mm:ss.xx]` cues stripped.
  String? _pickLyrics(Map<String, dynamic> data) {
    final plain = data['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) return plain;

    final synced = data['syncedLyrics'];
    if (synced is! String || synced.trim().isEmpty) return null;
    final stripped = synced
        .replaceAll(RegExp(r'^\s*(\[\d+:\d+(\.\d+)?\]\s*)+', multiLine: true), '')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }

  @visibleForTesting
  static String cleanQuery(String input) {
    return input
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        // Whole words only: "Audioslave" and "HDMI" are not noise.
        .replaceAll(RegExp(r'\b(Official Video|Official Audio|Lyric Video|HD|HQ|Audio|Video|MV)\b',
            caseSensitive: false), '')
        .trim();
  }
}
