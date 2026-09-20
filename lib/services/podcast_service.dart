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

          // Extract image if available (try both namespaced and non-namespaced)
          String? image;
          try {
            image = item.findElements('itunes:image').firstOrNull?.getAttribute('href');
          } catch (_) {
            // Namespace not registered, try without namespace
            for (final element in item.childElements) {
              if (element.name.local == 'image' && element.getAttribute('href') != null) {
                image = element.getAttribute('href');
                break;
              }
            }
          }

          // Extract duration if available
          Duration? duration;
          try {
            final durationStr = item.findElements('itunes:duration').firstOrNull?.innerText;
            if (durationStr != null) {
              duration = _parseDuration(durationStr);
            }
          } catch (_) {}

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
