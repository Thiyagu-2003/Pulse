import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_item_model.dart';
import '../util/first_success.dart';

class YoutubeService {
  // Shared instance: the audio handler, the provider and the search screen all
  // construct a YoutubeService. Separate instances meant the search screen's
  // prefetched stream URLs never reached the handler that actually plays them,
  // so the cache never hit.
  static final YoutubeService _instance = YoutubeService._internal();
  factory YoutubeService() => _instance;
  YoutubeService._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, _CachedStream> _streamCache = {};

  /// Search for music tracks.
  ///
  /// NewPipe runs first. youtube_explode's search parser no longer matches
  /// what YouTube returns — verified against live YouTube, it throws
  /// `NoSuchMethodError ... getT<String>("text")` inside its own search page
  /// parser — and 3.1.0 is the latest release, so there is no upgrade to take.
  /// That failure was swallowed and shown as "No results found", which made
  /// the whole Online tab look empty.
  ///
  /// It stays as a fallback: NewPipe is Android-only, and upstream may fix
  /// the parser later.
  Future<List<AppMediaItem>> searchMusic(String query) async {
    final viaNewPipe = await _searchWithNewPipe(query);
    if (viaNewPipe.isNotEmpty) {
      _prefetchStreams(viaNewPipe.take(3).map((e) => e.id).toList());
      return viaNewPipe;
    }
    return _searchWithExplode(query);
  }

  /// Native Android search through the NewPipe extractor.
  Future<List<AppMediaItem>> _searchWithNewPipe(String query) async {
    try {
      final search = await SearchExtractor.searchYoutube(query, const [])
          .timeout(const Duration(seconds: 12));

      final items = <AppMediaItem>[];
      for (final video in search.result.videos) {
        final id = video.id;
        final seconds = video.duration ?? 0;
        // Shorts and stings aren't music; skip them as the old search did.
        if (id == null || id.isEmpty || video.isShort || seconds < 10) continue;

        items.add(
          AppMediaItem(
            id: id,
            title: video.name ?? 'Unknown Title',
            artist: video.uploaderName ?? 'Unknown Artist',
            album: onlineAlbumLabel,
            // Thumbnails come back smallest-first.
            artUri: video.thumbnails.isNotEmpty ? video.thumbnails.last : null,
            duration: Duration(seconds: seconds),
            sourceType: MediaSourceType.youtube,
          ),
        );
      }
      return items;
    } catch (e) {
      debugPrint('NewPipe search failed: $e');
      return [];
    }
  }

  Future<List<AppMediaItem>> _searchWithExplode(String query) async {
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
            album: onlineAlbumLabel,
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
      warmStreamUrl(id);
    }
  }

  /// How long NewPipe gets on its own before the slower extractor joins in.
  static const Duration _headStart = Duration(seconds: 3);

  /// Get direct playable audio stream URL — tries multiple strategies
  Future<String?> getAudioStreamUrl(String videoId) async {
    // 1. Check in-memory cache (instant)
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      debugPrint('✅ Cache hit for $videoId');
      return cached.url;
    }

    // 2. NewPipe is native and usually fastest, so give it a short head start
    // by itself rather than firing two extractors at YouTube for every track.
    final newPipe = _tryNewPipeExtractor(videoId);
    final quick = await newPipe.timeout(_headStart, onTimeout: () => null);
    if (quick != null) {
      debugPrint('✅ NewPipe Extractor success for $videoId');
      return _remember(videoId, quick);
    }

    // 3. Slow or failed — race the still-running NewPipe against
    // youtube_explode instead of waiting out NewPipe's full timeout first,
    // which used to make a failure cost 10s before the fallback even started.
    final url = await firstSuccess([newPipe, _tryYoutubeExplode(videoId)]);
    if (url != null) return _remember(videoId, url);

    debugPrint('❌ All extraction methods failed for $videoId');
    return null;
  }

  String _remember(String videoId, String url) {
    _streamCache[videoId] = _CachedStream(url);
    return url;
  }

  /// Resolve a stream URL ahead of time so tapping the track is instant.
  void warmStreamUrl(String videoId) {
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) return;
    getAudioStreamUrl(videoId).catchError((_) => null);
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
      return _bestAudioStream(manifest)?.url.toString();
    } catch (e) {
      debugPrint('youtube_explode failed for $videoId: $e');
    }
    return null;
  }



  /// Download YouTube audio stream locally for offline listening using
  /// youtube_explode. [onProgress] reports 0.0–1.0 when the total size is
  /// known, so the UI can show a real bar rather than a spinner.
  Future<String?> downloadAudioTrack(
    AppMediaItem item, {
    void Function(double)? onProgress,
  }) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(item.id).timeout(
        const Duration(seconds: 15),
      );
      
      // Audio only — a video stream is never fetched or written to disk.
      final audioStreamInfo = _bestAudioStream(manifest);
      if (audioStreamInfo == null) {
        debugPrint('No audio stream to download for ${item.id}');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final cleanTitle = item.title.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      // Name the file after what is actually in it. The extension used to be
      // hardcoded .m4a while the bytes were usually Opus-in-WebM, producing a
      // mislabelled file that iOS can't open and the media scanner misreads.
      // Include the video id: different videos can clean down to the same title.
      final file = File(
        '${dir.path}/${cleanTitle}_${item.id}.${_extensionFor(audioStreamInfo)}',
      );

      // Written chunk by chunk rather than piped, so progress can be
      // reported. (pipe() also closes the sink itself, which is what made
      // the old flush-after-pipe throw and report every download as failed.)
      final total = audioStreamInfo.size.totalBytes;
      final sink = file.openWrite();
      var received = 0;

      try {
        await for (final chunk in _yt.videos.streamsClient.get(audioStreamInfo)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        // Don't leave a truncated file behind masquerading as a download.
        await sink.close().catchError((_) {});
        if (await file.exists()) await file.delete();
        rethrow;
      }

      return file.path;
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  /// Picks the audio-only stream to play or download.
  ///
  /// Prefers AAC in an MP4 container over the raw highest bitrate, which is
  /// normally Opus in WebM — higher quality on paper, but Opus doesn't decode
  /// on iOS at all and isn't a safe thing to leave on disk.
  ///
  /// The previous filter compared `container.name` against `'m4a'`, but that
  /// value is only ever `mp4`, `webm`, `3gpp` or `m3u8`, so it never matched
  /// and the preference never actually applied.
  AudioOnlyStreamInfo? _bestAudioStream(StreamManifest manifest) {
    final streams = manifest.audioOnly;
    if (streams.isEmpty) return null;

    final mp4 = streams
        .where((s) => s.container == StreamContainer.mp4)
        .toList();
    return mp4.isNotEmpty
        ? mp4.withHighestBitrate()
        : streams.withHighestBitrate();
  }

  /// File extension matching the stream's real container.
  String _extensionFor(AudioOnlyStreamInfo stream) =>
      stream.container == StreamContainer.mp4 ? 'm4a' : stream.container.name;

  /// Get curated trending music tracks
  Future<List<AppMediaItem>> getTrendingMusic() async {
    return searchMusic('top hits 2024 2025 official audio');
  }
}

/// Cached stream URL with 30-minute expiry (YouTube URLs expire)
class _CachedStream {
  final String url;
  final DateTime cachedAt;

  _CachedStream(this.url) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes > 30;
}
