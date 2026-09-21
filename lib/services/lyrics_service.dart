import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LyricsService {
  /// Fetch synced or plain lyrics from open LRCLIB API
  Future<String?> fetchLyrics(String title, String artist) async {
    try {
      final cleanTitle = _cleanQuery(title);
      final cleanArtist = _cleanQuery(artist);
      final url = Uri.parse(
          'https://lrclib.net/api/get?track_name=${Uri.encodeComponent(cleanTitle)}&artist_name=${Uri.encodeComponent(cleanArtist)}');

      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = _pickLyrics(data);
        if (result != null) return result;
      }

      // Fallback search API if exact match not found
      final searchUrl = Uri.parse(
          'https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanArtist $cleanTitle")}');
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode == 200) {
        final List searchData = jsonDecode(searchRes.body);
        if (searchData.isNotEmpty) {
          return _pickLyrics(searchData.first);
        }
      }
    } catch (e) {
      debugPrint('Error fetching lyrics: $e');
    }
    return null;
  }

  /// The UI renders lyrics as plain text, so prefer plainLyrics and strip the
  /// `[mm:ss.xx]` cues off syncedLyrics rather than showing them to the user.
  String? _pickLyrics(dynamic data) {
    final plain = data['plainLyrics'] as String?;
    if (plain != null && plain.trim().isNotEmpty) return plain;

    final synced = data['syncedLyrics'] as String?;
    if (synced == null || synced.trim().isEmpty) return null;
    final stripped = synced
        .replaceAll(RegExp(r'^\s*(\[\d+:\d+(\.\d+)?\]\s*)+', multiLine: true), '')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }

  String _cleanQuery(String input) {
    return input
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'Official Video|Official Audio|Lyric Video|HD|HQ|Audio|Video|MV',
            caseSensitive: false), '')
        .trim();
  }
}
