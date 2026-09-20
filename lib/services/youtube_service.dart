import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_item_model.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, _CachedStream> _streamCache = {};

  /// Search for music tracks on YouTube
  Future<List<AppMediaItem>> searchMusic(String query) async {
    try {
      final searchResults = await _yt.search.search(query).timeout(
        const Duration(seconds: 10),
      );
      final List<AppMediaItem> items = [];

      for (final video in searchResults) {
        if (video.duration == null || video.duration! < const Duration(seconds: 10)) {
          continue;
        }
        items.add(
          AppMediaItem(
            id: video.id.value,
            title: video.title,
            artist: video.author,
            album: 'YouTube Music',
            artUri: video.thumbnails.highResUrl,
            duration: video.duration,
            sourceType: MediaSourceType.youtube,
          ),
        );
      }

      // Pre-fetch stream URLs in background for top 3 results
      _prefetchStreams(items.take(3).map((e) => e.id).toList());

      return items;
    } catch (e) {
      debugPrint('YouTube search error: $e');
      return [];
    }
  }

  void _prefetchStreams(List<String> videoIds) {
    for (final id in videoIds) {
      if (!_streamCache.containsKey(id) || _streamCache[id]!.isExpired) {
        getAudioStreamUrl(id).catchError((_) => null);
      }
    }
  }

  /// Get direct playable audio stream URL — tries multiple strategies
  Future<String?> getAudioStreamUrl(String videoId) async {
    // 1. Check in-memory cache (instant)
    if (_streamCache.containsKey(videoId) && !_streamCache[videoId]!.isExpired) {
      debugPrint('✅ Cache hit for $videoId');
      return _streamCache[videoId]!.url;
    }

    // 2. Try NewPipe Extractor (Native Android - Very Fast & Reliable)
    final newPipeUrl = await _tryNewPipeExtractor(videoId);
    if (newPipeUrl != null) {
      _streamCache[videoId] = _CachedStream(newPipeUrl);
      debugPrint('✅ NewPipe Extractor success for $videoId');
      return newPipeUrl;
    }

    // 3. Last resort: client-side InnerTube via youtube_explode
    final ytExplodeUrl = await _tryYoutubeExplode(videoId);
    if (ytExplodeUrl != null) {
      _streamCache[videoId] = _CachedStream(ytExplodeUrl);
      debugPrint('✅ youtube_explode success for $videoId');
      return ytExplodeUrl;
    }

    debugPrint('❌ All extraction methods failed for $videoId');
    return null;
  }

  /// NewPipe native extraction (Fast on Android)
  Future<String?> _tryNewPipeExtractor(String videoId) async {
    try {
      final video = await VideoExtractor.getStream('https://www.youtube.com/watch?v=$videoId').timeout(
        const Duration(seconds: 10),
      );
      final bestAudio = video.audioWithBestAacQuality ?? video.audioWithHighestQuality;
      if (bestAudio != null && bestAudio.url != null) {
        return bestAudio.url;
      }
    } catch (e) {
      debugPrint('NewPipe extraction failed for $videoId: $e');
    }
    return null;
  }

  /// Client-side InnerTube extraction via youtube_explode_dart (slowest but most reliable)
  Future<String?> _tryYoutubeExplode(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId).timeout(
        const Duration(seconds: 15), // Give it more time on mobile
      );
      final audioOnlyStreams = manifest.audioOnly;
      if (audioOnlyStreams.isNotEmpty) {
        final m4aStreams = audioOnlyStreams.where(
          (s) => s.container.name.toLowerCase() == 'm4a',
        );
        return m4aStreams.isNotEmpty
            ? m4aStreams.withHighestBitrate().url.toString()
            : audioOnlyStreams.withHighestBitrate().url.toString();
      }
    } catch (e) {
      debugPrint('youtube_explode failed for $videoId: $e');
    }
    return null;
  }

  /// Download YouTube audio stream locally for offline listening (NewPipe style)
  Future<String?> downloadAudioTrack(AppMediaItem item) async {
    try {
      final video = await VideoExtractor.getStream('https://www.youtube.com/watch?v=${item.id}').timeout(
        const Duration(seconds: 15),
      );
      final bestAudio = video.audioWithBestAacQuality ?? video.audioWithHighestQuality;
      final streamUrl = bestAudio?.url;

      if (streamUrl == null) {
        throw Exception('No stream URL found for downloading');
      }

      final dir = await getApplicationDocumentsDirectory();
      final cleanTitle = item.title.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final filePath = '${dir.path}/$cleanTitle.m4a';

      final file = File(filePath);
      final response = await http.get(Uri.parse(streamUrl));
      
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        throw Exception('HTTP ${response.statusCode} while downloading');
      }
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  /// Get curated trending music tracks
  Future<List<AppMediaItem>> getTrendingMusic() async {
    return searchMusic('top hits 2024 2025 official audio');
  }

  void dispose() {
    _yt.close();
  }
}

/// Cached stream URL with 30-minute expiry (YouTube URLs expire)
class _CachedStream {
  final String url;
  final DateTime cachedAt;

  _CachedStream(this.url) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes > 30;
}
