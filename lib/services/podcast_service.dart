import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/podcast_model.dart';
import '../models/media_item_model.dart';

class PodcastService {
  /// Search top podcasts using Apple iTunes Search API (100% Free)
  Future<List<PodcastChannel>> searchPodcasts(String query) async {
    try {
      final url = Uri.parse(
          'https://itunes.apple.com/search?media=podcast&term=${Uri.encodeComponent(query)}&limit=25');
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'] ?? [];
        return results.map((item) => PodcastChannel.fromiTunesJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Error searching podcasts: $e');
    }
    return [];
  }

  /// Get trending podcasts
  Future<List<PodcastChannel>> getTopPodcasts() async {
    return searchPodcasts('technology news storytelling music');
  }

  /// Parse Podcast RSS feed XML to extract episode details
  Future<List<PodcastEpisode>> fetchEpisodes(String feedUrl) async {
    if (feedUrl.isEmpty) return [];
    try {
      final response = await http.get(Uri.parse(feedUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final items = document.findAllElements('item');
        final List<PodcastEpisode> episodes = [];

        for (final item in items) {
          final title = item.findElements('title').firstOrNull?.innerText ?? 'Episode';
          final description = item.findElements('description').firstOrNull?.innerText ?? '';
          final pubDate = item.findElements('pubDate').firstOrNull?.innerText;

          // Extract enclosure audio URL
          final enclosure = item.findElements('enclosure').firstOrNull;
          final audioUrl = enclosure?.getAttribute('url');
          if (audioUrl == null || audioUrl.isEmpty) continue;

          // Feeds use varying prefixes for the itunes namespace, so match on
          // the local name instead. (findElements never throws, so the old
          // try/catch fallback was dead code and images were usually lost.)
          final image = _episodeImage(item);

          final durationStr = _childByLocalName(item, 'duration')?.innerText;
          final duration =
              durationStr != null ? _parseDuration(durationStr) : null;

          episodes.add(
            PodcastEpisode(
              id: audioUrl.hashCode.toString(),
              title: title,
              description: description,
              audioUrl: audioUrl,
              pubDate: pubDate,
              duration: duration,
              artworkUrl: image,
            ),
          );
        }
        return episodes;
      }
    } catch (e) {
      debugPrint('Error parsing podcast RSS feed: $e');
    }
    return [];
  }

  /// Episode artwork: `<itunes:image href="...">` or plain RSS
  /// `<image><url>...</url></image>`, whatever prefix the feed uses.
  String? _episodeImage(XmlElement item) {
    for (final element in item.childElements) {
      if (element.name.local != 'image') continue;
      final href = element.getAttribute('href') ??
          _childByLocalName(element, 'url')?.innerText;
      if (href != null && href.trim().isNotEmpty) return href.trim();
    }
    return null;
  }

  /// Finds a direct child by local name, ignoring any namespace prefix.
  XmlElement? _childByLocalName(XmlElement parent, String localName) {
    for (final element in parent.childElements) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  /// Parse duration string like "1:23:45" or "3600" (seconds)
  Duration? _parseDuration(String str) {
    try {
      // Try seconds format first
      final seconds = int.tryParse(str);
      if (seconds != null) return Duration(seconds: seconds);

      // Try HH:MM:SS or MM:SS format
      final parts = str.split(':').map((e) => int.tryParse(e) ?? 0).toList();
      if (parts.length == 3) {
        return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
      } else if (parts.length == 2) {
        return Duration(minutes: parts[0], seconds: parts[1]);
      }
    } catch (_) {}
    return null;
  }

  /// Convert Podcast Episode to AppMediaItem
  AppMediaItem episodeToMediaItem(PodcastEpisode episode, PodcastChannel channel) {
    return AppMediaItem(
      id: episode.id,
      title: episode.title,
      artist: channel.author,
      album: channel.title,
      artUri: episode.artworkUrl ?? channel.artworkUrl,
      streamUrl: episode.audioUrl,
      duration: episode.duration,
      sourceType: MediaSourceType.podcast,
      extras: {
        'description': episode.description,
        'pubDate': episode.pubDate,
      },
    );
  }
}
