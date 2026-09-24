import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_item_model.dart';
import 'storage_service.dart';
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

  /// Extractions in progress. Prefetch starts one, then the user taps the
  /// same track: without this they ran two full extractions side by side.
  final Map<String, Future<String?>> _inFlight = {};

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
  ///
  /// [prefetch] resolves the top results' streams in the background, which
  /// suits a search the user is about to pick from — but not the home page,
  /// where a dozen sections would start dozens of extractions.
  Future<List<AppMediaItem>> searchMusic(
    String query, {
    bool prefetch = true,
  }) async {
    final viaNewPipe = await _searchWithNewPipe(query);
    final results =
        viaNewPipe.isNotEmpty ? viaNewPipe : await _searchWithExplode(query);
    if (prefetch) _prefetchStreams(results.take(3).map((e) => e.id).toList());
    return results;
  }

  final Map<String, Future<List<AppMediaItem>>> _searchCache = {};

  /// Search results kept for the session, so home sections don't reload
  /// every time they scroll back into view or the tab is revisited. Failed or
  /// empty searches are forgotten, so they can be retried.
  Future<List<AppMediaItem>> cachedSearch(String query) =>
      _searchCache[query] ??= searchMusic(query, prefetch: false).then(
        (results) {
          if (results.isEmpty) _searchCache.remove(query);
          return results;
        },
        onError: (Object e) {
          _searchCache.remove(query);
          throw e;
        },
      );

  void clearSearchCache() => _searchCache.clear();

  @visibleForTesting
  void seedSearch(String query, List<AppMediaItem> results) =>
      _searchCache[query] = Future.value(results);

  /// Forget every resolved stream URL — "Clear stream cache" in Settings,
  /// and after the audio quality changes.
  void clearStreamCache() => _streamCache.clear();

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


  /// Invalidate cached stream URL (e.g., if playback fails with 403)
  void invalidateStreamUrl(String videoId) {
    _streamCache.remove(videoId);
  }

  /// Get direct playable audio stream URL — tries multiple strategies
  Future<String?> getAudioStreamUrl(String videoId) async {
    // 1. Check in-memory cache (instant)
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      debugPrint('✅ Cache hit for $videoId');
      return cached.url;
    }
    return _inFlight[videoId] ??=
        _extract(videoId).whenComplete(() => _inFlight.remove(videoId));
  }

  /// Tries each way of getting a stream URL until one actually plays.
  ///
  /// Every candidate is checked with a two-byte request first. YouTube
  /// intermittently hands out URLs that pass youtube_explode's own HEAD check
  /// but answer the real GET with 403; the old chain only fell through to the
  /// next method when extraction *failed*, so a dead URL went straight to the
  /// player and nothing played.
  ///
  /// The two direct client calls are cheap (~200ms each) and race each other,
  /// so a dead URL from one costs nothing while the other is still going.
  /// The slow paths — the watch page, and NewPipe's on-device JavaScript
  /// deciphering — only run if both lose.
  Future<String?> _extract(String videoId) async {
    Future<String?> verified(String name, Future<String?> candidate) async {
      final url = await candidate;
      if (url == null) return null;
      if (await _isPlayable(url)) {
        debugPrint('✅ $name gave a playable stream for $videoId');
        return url;
      }
      debugPrint('⚠️ $name returned a dead stream URL for $videoId');
      return null;
    }

    final fast = await firstSuccess([
      verified('explode/androidSdkless',
          _tryYoutubeExplode(videoId, YoutubeApiClient.androidSdkless)),
      verified('explode/android',
          _tryYoutubeExplode(videoId, YoutubeApiClient.android)),
    ]);
    if (fast != null) return _remember(videoId, fast);

    final slow = await verified('explode/watch page',
            _tryYoutubeExplode(videoId, null)) ??
        await verified('NewPipe', _tryNewPipeExtractor(videoId));
    if (slow != null) return _remember(videoId, slow);

    debugPrint('❌ All extraction methods failed for $videoId');
    return null;
  }

  /// A real two-byte GET — not HEAD, which is exactly what passes on URLs
  /// that then refuse to stream.
  static Future<bool> _isPlayable(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      final response =
          await request.close().timeout(const Duration(seconds: 6));
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
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
  /// [client] null means youtube_explode's default path, which also
  /// downloads the watch page — slower, but it sometimes gets through when
  /// the direct client calls don't.
  Future<String?> _tryYoutubeExplode(
    String videoId,
    YoutubeApiClient? client,
  ) async {
    try {
      final streams = _yt.videos.streamsClient;
      final manifest = client == null
          ? await streams.getManifest(videoId).timeout(const Duration(seconds: 15))
          : await streams
              .getManifest(videoId, ytClients: [client], requireWatchPage: false)
              .timeout(const Duration(seconds: 8));
      final quality = StorageService().getAudioQuality();
      return _audioStreamFor(manifest, quality)?.url.toString();
    } catch (e) {
      debugPrint('youtube_explode (${client == null ? 'watch page' : 'direct'}) failed for $videoId: $e');
    }
    return null;
  }




  /// By default youtube_explode first downloads and parses the whole watch
  /// page (~1MB of HTML) before the player API call. With no JS challenge
  /// solver configured that page only supplies cookies, so try without it
  /// first and fall back to the full path only if YouTube insists.
  Future<StreamManifest> _getManifest(String videoId) async {
    final client = _yt.videos.streamsClient;
    try {
      return await client
          .getManifest(videoId, requireWatchPage: false)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Fast manifest failed for $videoId, retrying with watch page: $e');
      return client.getManifest(videoId).timeout(const Duration(seconds: 15));
    }
  }

  /// Download YouTube audio stream locally for offline listening.
  /// Tries NewPipe first (faster, more reliable on Android), then falls back
  /// to youtube_explode. [onProgress] reports 0.0–1.0 when the total size is
  /// known, so the UI can show a real bar rather than a spinner.
  Future<Directory> _getDownloadDirectory() async {
    final customPath = StorageService().getCustomDownloadPath();
    if (customPath != null && customPath.isNotEmpty) {
      try {
        final customDir = Directory(customPath);
        if (await isWritableDirectory(customDir)) return customDir;
        debugPrint('Custom download dir not writable, using default');
      } catch (e) {
        debugPrint('Custom download dir invalid, falling back to default: $e');
      }
    }

    if (Platform.isAndroid) {
      try {
        final externalDirs = await getExternalStorageDirectories(
          type: StorageDirectory.music,
        );
        if (externalDirs != null && externalDirs.isNotEmpty) {
          final dir = externalDirs.first;
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir;
        }
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final musicDir = Directory('${externalDir.path}/Music');
          if (!await musicDir.exists()) await musicDir.create(recursive: true);
          return musicDir;
        }
      } catch (e) {
        debugPrint('Failed to resolve external music dir: $e');
      }
    }
    return await getApplicationDocumentsDirectory();
  }

  /// Whether files can actually be written into [dir]. Under Android 11+
  /// scoped storage a folder from the picker usually exists but rejects
  /// direct File writes, so exists() alone says nothing.
  static Future<bool> isWritableDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File('${dir.path}/.pulse_write_test');
      await probe.writeAsString('');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> downloadAudioTrack(
    AppMediaItem item, {
    void Function(double)? onProgress,
  }) async {
    try {
      final dir = await _getDownloadDirectory();
      final cleanTitle = item.title.replaceAll(RegExp(r'[^\w\s\-]'), '_');

      // 1. Try youtube_explode first — unthrottled InnerTube streaming (1-2s total)
      final explodePath = await _downloadViaExplode(
        item, dir.path, cleanTitle, onProgress,
      );
      if (explodePath != null) return explodePath;

      // 2. Fall back to NewPipe with browser headers to prevent CDN bandwidth throttling
      return await _downloadViaNewPipe(
        item, dir.path, cleanTitle, onProgress,
      );
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  /// Download using NewPipe extractor with unthrottled headers.
  Future<String?> _downloadViaNewPipe(
    AppMediaItem item,
    String dirPath,
    String cleanTitle,
    void Function(double)? onProgress,
  ) async {
    try {
      final video = await VideoExtractor.getStream(
        'https://www.youtube.com/watch?v=${item.id}',
      ).timeout(const Duration(seconds: 5));

      final bestAudio = video.audioWithBestAacQuality ??
          video.audioWithHighestQuality;
      if (bestAudio?.url == null) return null;

      final url = bestAudio!.url!;
      final ext = (bestAudio.formatSuffix ?? 'm4a').replaceAll('.', '');
      final file = File('$dirPath/${cleanTitle}_${item.id}.$ext');

      // Download the stream using HttpClient with browser headers to bypass CDN throttling
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

      final response = await request.close().timeout(const Duration(seconds: 15));
      final total = response.contentLength;
      final sink = file.openWrite();
      var received = 0;

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        await sink.close().catchError((_) {});
        if (await file.exists()) await file.delete();
        rethrow;
      } finally {
        client.close();
      }

      return file.path;
    } catch (e) {
      debugPrint('NewPipe download failed: $e');
      return null;
    }
  }

  /// Download using youtube_explode (slower but more portable).
  Future<String?> _downloadViaExplode(
    AppMediaItem item,
    String dirPath,
    String cleanTitle,
    void Function(double)? onProgress,
  ) async {
    try {
      final manifest = await _getManifest(item.id);

      // Audio only — a video stream is never fetched or written to disk.
      final audioStreamInfo = _bestAudioStream(manifest);
      if (audioStreamInfo == null) {
        debugPrint('No audio stream to download for ${item.id}');
        return null;
      }

      // Name the file after what is actually in it.
      final file = File(
        '$dirPath/${cleanTitle}_${item.id}.${_extensionFor(audioStreamInfo)}',
      );

      // Written chunk by chunk rather than piped, so progress can be
      // reported. (pipe() also closes the sink itself, which is what made
      // the old flush-after-pipe throw and report every download as failed.)
      final total = audioStreamInfo.size.totalBytes;
      final sink = file.openWrite();
      var received = 0;

      try {
        await for (final chunk
            in _yt.videos.streamsClient.get(audioStreamInfo)) {
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
      debugPrint('youtube_explode download failed: $e');
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

  /// The stream to *play* at the chosen quality. Downloads stay on
  /// [_bestAudioStream].
  AudioOnlyStreamInfo? _audioStreamFor(
    StreamManifest manifest,
    AudioQuality quality,
  ) {
    final streams = manifest.audioOnly;
    if (streams.isEmpty) return null;
    return switch (quality) {
      AudioQuality.dataSaver => streams.sortByBitrate().last,
      AudioQuality.balanced => _bestAudioStream(manifest),
      AudioQuality.best => streams.withHighestBitrate(),
    };
  }

  /// File extension matching the stream's real container.
  String _extensionFor(AudioOnlyStreamInfo stream) =>
      stream.container == StreamContainer.mp4 ? 'm4a' : stream.container.name;

}

/// Cached stream URL with 30-minute expiry (YouTube URLs expire)
class _CachedStream {
  final String url;
  final DateTime cachedAt;

  _CachedStream(this.url) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt).inMinutes > 30;
}
