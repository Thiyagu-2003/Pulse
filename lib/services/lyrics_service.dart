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
        final result = data['syncedLyrics'] ?? data['plainLyrics'];
        if (result != null) return result;
      }

      // Fallback search API if exact match not found
      final searchUrl = Uri.parse(
          'https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanArtist $cleanTitle")}');
      final searchRes = await http.get(searchUrl).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode == 200) {
        final List searchData = jsonDecode(searchRes.body);
        if (searchData.isNotEmpty) {
          final item = searchData.first;
          return item['syncedLyrics'] ?? item['plainLyrics'];
        }
      }
    } catch (e) {
      debugPrint('Error fetching lyrics: $e');
    }
    return null;
  }

  String _cleanQuery(String input) {
    return input
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'Official Video|Official Audio|Lyric Video|HD|HQ|Audio|Video|MV',
            caseSensitive: false), '')
        .trim();
  }
}
