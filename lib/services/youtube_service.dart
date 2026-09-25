import 'dart:async';
import 'dart:collection';
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

  /// Stands in for the network extraction in tests.
  @visibleForTesting
  Future<String?> Function(String videoId, {required bool verify})?
      debugExtractOverride;

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
    if (prefetch) prefetchStreams(results.take(8).map((e) => e.id).toList());
    return results;
  }

  final Map<String, Future<List<AppMediaItem>>> _searchCache = {};

  /// Search results kept for the session, so home sections don't reload
  /// every time they scroll back into view or the tab is revisited. Failed or
  /// empty searches are forgotten, so they can be retried.
  Future<List<AppMediaItem>> cachedSearch(String query) {
    final cached = _searchCache[query];
    if (cached != null) return cached;
    late final Future<List<AppMediaItem>> search;
    // Only ever evict *this* search: after a refresh, a stale one finishing
    // late must not throw out the newer entry for the same query.
    void forget() {
      if (identical(_searchCache[query], search)) _searchCache.remove(query);
    }

    search = _limited(() async {
      final run = debugSearchOverride ??
          (String q) => searchMusic(q, prefetch: false);
      var results = await run(query);
      if (results.isEmpty) {
        // Usually YouTube briefly refusing a burst; one calm retry.
        await Future<void>.delayed(searchRetryDelay);
        results = await run(query);
      }
      if (results.isEmpty) forget();
      return results;
    }).catchError((Object e, StackTrace st) {
      forget();
      Error.throwWithStackTrace(e, st);
    });
    return _searchCache[query] = search;
  }

  /// The home page asks for a dozen searches at once; fired together,
  /// YouTube answers with redirect loops and empty pages. At most
  /// [_maxSearches] run at a time, the rest wait their turn in order.
  static const _maxSearches = 3;

  @visibleForTesting
  Duration searchRetryDelay = const Duration(milliseconds: 1500);

  /// Stands in for the network suggestions in tests.
  @visibleForTesting
  Future<List<String>> Function(String query)? debugSuggestionsOverride;

  /// Stands in for the network search in tests.
  @visibleForTesting
  Future<List<AppMediaItem>> Function(String query)? debugSearchOverride;
  int _activeSearches = 0;
  final _waitingSearches = Queue<Completer<void>>();

  Future<T> _limited<T>(Future<T> Function() task) async {
    if (_activeSearches >= _maxSearches) {
      final turn = Completer<void>();
      _waitingSearches.add(turn);
      await turn.future; // the finishing search hands over its slot
    } else {
      _activeSearches++;
    }
    try {
      return await task();
    } finally {
      if (_waitingSearches.isNotEmpty) {
        _waitingSearches.removeFirst().complete();
      } else {
        _activeSearches--;
      }
    }
  }

  void clearSearchCache() => _searchCache.clear();

  @visibleForTesting
  void seedSearch(String query, List<AppMediaItem> results) =>
      _searchCache[query] = Future.value(results);

  /// Forget every resolved stream URL — "Clear stream cache" in Settings,
  /// and after the audio quality changes.
  void clearStreamCache() {
    _streamCache.clear();
    _cacheEpoch++;
  }

  /// Bumped by [clearStreamCache]; a lookup that started before the bump
  /// (e.g. at the old audio quality) must not repopulate the cache.
  int _cacheEpoch = 0;

  /// Autocomplete for the search box — the same suggestions YouTube shows.
  /// NewPipe on Android; youtube_explode where NewPipe isn't available.
  /// Never throws: no suggestions is an acceptable answer.
  Future<List<String>> searchSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final override = debugSuggestionsOverride;
    if (override != null) return override(q);
    try {
      final viaNewPipe = await SearchExtractor.getSearchSuggestions(q)
          .timeout(const Duration(seconds: 4));
      if (viaNewPipe.isNotEmpty) return viaNewPipe.take(8).toList();
    } catch (e) {
      debugPrint('NewPipe suggestions failed: $e');
    }
    try {
      final viaExplode = await _yt.search
          .getQuerySuggestions(q)
          .timeout(const Duration(seconds: 4));
      return viaExplode.take(8).toList();
    } catch (e) {
      debugPrint('Suggestions unavailable: $e');
      return const [];
    }
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

      return items;
    } catch (e) {
      debugPrint('YouTube search error: $e');
      return [];
    }
  }

  int _prefetchRun = 0;

  /// The top three results at once (the likeliest taps), the rest of the
  /// first screen one at a time behind them — so tapping any visible result
  /// starts fast without a burst of requests. A newer search stops the
  /// older one's queue.
  @visibleForTesting
  Future<void> prefetchStreams(List<String> videoIds) async {
    final run = ++_prefetchRun;
    for (final id in videoIds.take(3)) {
      warmStreamUrl(id);
    }
    for (final id in videoIds.skip(3)) {
      if (run != _prefetchRun) return;
      await warmStreamUrlNow(id);
    }
  }


  /// Invalidate cached stream URL (e.g., if playback fails with 403)
  void invalidateStreamUrl(String videoId) {
    _streamCache.remove(videoId);
  }

  /// Get direct playable audio stream URL — tries multiple strategies
  ///
  /// By default the URL is *not* test-fetched first: the player's own request
  /// is that test, and skipping a separate one saves a round trip on every
  /// tap. [verify] is for the retry after the player got a dead URL.
  Future<String?> getAudioStreamUrl(String videoId, {bool verify = false}) async {
    // 1. Check in-memory cache (instant)
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) {
      debugPrint('✅ Cache hit for $videoId');
      return cached.url;
    }
    final key = '$videoId/$verify';
    // Block body on purpose: `=> _inFlight.remove(key)` would return this
    // very future, and whenComplete waits on a returned future — so it
    // waited on itself and never completed. Every uncached first tap hung.
    final extract = debugExtractOverride ?? _extract;
    return _inFlight[key] ??=
        extract(videoId, verify: verify).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  /// Tries each way of getting a stream URL until one actually plays.
  ///
  /// With [verify], every candidate is checked with a two-byte request first. YouTube
  /// intermittently hands out URLs that pass youtube_explode's own HEAD check
  /// but answer the real GET with 403; the old chain only fell through to the
  /// next method when extraction *failed*, so a dead URL went straight to the
  /// player and nothing played.
  ///
  /// The two direct client calls are cheap (~200ms each) and race each other,
  /// so a dead URL from one costs nothing while the other is still going.
  /// The slow paths — the watch page, and NewPipe's on-device JavaScript
  /// deciphering — only run if both lose.
  Future<String?> _extract(String videoId, {required bool verify}) async {
    final epoch = _cacheEpoch;
    Future<String?> verified(String name, Future<String?> candidate) async {
      final url = await candidate;
      if (url == null) return null;
      if (!verify || await _isPlayable(url)) {
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
    if (fast != null) return _remember(videoId, fast, epoch);

    final slow = await verified('explode/watch page',
            _tryYoutubeExplode(videoId, null)) ??
        await verified('NewPipe', _tryNewPipeExtractor(videoId));
    if (slow != null) return _remember(videoId, slow, epoch);

    debugPrint('❌ All extraction methods failed for $videoId');
    return null;
  }

  /// Checked stream URLs from each source in turn — both YouTube clients,
  /// the watch-page path, then NewPipe — skipping any in [exclude]. For when
  /// the player failed on a URL: the next one comes from a *different*
  /// source, rather than asking the same one again.
  Stream<String> alternativeStreamUrls(
    String videoId, {
    Set<String> exclude = const {},
  }) async* {
    final sources = <(String, Future<String?> Function())>[
      ('explode/androidSdkless',
          () => _tryYoutubeExplode(videoId, YoutubeApiClient.androidSdkless)),
      ('explode/android',
          () => _tryYoutubeExplode(videoId, YoutubeApiClient.android)),
      ('explode/watch page', () => _tryYoutubeExplode(videoId, null)),
      ('NewPipe', () => _tryNewPipeExtractor(videoId)),
    ];
    for (final (name, source) in sources) {
      final url = await source();
      if (url == null || exclude.contains(url)) continue;
      if (!await _isPlayable(url)) {
        debugPrint('⚠️ $name alternative is dead for $videoId');
        continue;
      }
      debugPrint('↪️ trying $name for $videoId');
      yield _remember(videoId, url);
    }
  }

  /// Last resort when no stream URL will play: fetch the whole song and play
  /// the file. Downloading goes through a different, more forgiving path
  /// (chunked requests that re-resolve on 403), and it keeps working when
  /// streaming doesn't. Kept in a small cache, so a replay starts at once.
  Future<String?> cacheForPlayback(AppMediaItem item) async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/playback');
      if (!await dir.exists()) await dir.create(recursive: true);
      final existing = cachedPlaybackFile(item.id, dir);
      if (existing != null) return existing;

      final path = await _downloadViaExplode(item, dir.path, item.id, null);
      if (path == null) return null;
      // Keep the five most recent songs.
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final old in files.skip(5)) {
        old.deleteSync();
      }
      return path;
    } catch (e) {
      debugPrint('Playback cache failed for ${item.id}: $e');
      return null;
    }
  }

  /// Path of a song [cacheForPlayback] already fetched, if any.
  Future<String?> cachedPlaybackPath(String videoId) async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/playback');
      return cachedPlaybackFile(videoId, dir);
    } catch (_) {
      return null; // no app storage (tests)
    }
  }

  /// A song already fetched by [cacheForPlayback].
  String? cachedPlaybackFile(String videoId, Directory dir) {
    if (!dir.existsSync()) return null;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('${videoId}_$videoId.') && !name.endsWith('.part')) {
        return f.path;
      }
    }
    return null;
  }

  /// A real two-byte GET — not HEAD, which is exactly what passes on URLs
  /// that then refuse to stream.
  static Future<bool> _isPlayable(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
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

  String _remember(String videoId, String url, [int? epoch]) {
    if (epoch == null || epoch == _cacheEpoch) {
      _streamCache[videoId] = _CachedStream(url);
    }
    return url;
  }

  /// Resolve a stream URL ahead of time so tapping the track is instant.
  void warmStreamUrl(String videoId) {
    warmStreamUrlNow(videoId);
  }

  /// [warmStreamUrl] that can be awaited, so a batch can be warmed one at a
  /// time instead of firing a burst of requests at YouTube.
  Future<void> warmStreamUrlNow(String videoId) async {
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) return;
    await getAudioStreamUrl(videoId).catchError((_) => null);
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

  /// Writes [bytes] to [target] via a `.part` file, renamed only once
  /// complete: a song still being fetched, or cut off by the app being
  /// killed, must never look like a finished file (the playback cache and
  /// the downloads list both treat any file with the right name as done).
  /// A connection that stops sending for 20s counts as failed instead of
  /// hanging the download forever. Written chunk by chunk, not piped, so
  /// progress can be reported.
  Future<String> _writeAudioFile(
    Stream<List<int>> bytes,
    File target,
    int total,
    void Function(double)? onProgress,
  ) async {
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk
          in bytes.timeout(const Duration(seconds: 20))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      return (await part.rename(target.path)).path;
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
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
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        );
        request.headers.set(HttpHeaders.acceptHeader, '*/*');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

        final response =
            await request.close().timeout(const Duration(seconds: 15));
        // A 403 page written out as "song.m4a" was recorded as a finished
        // download that could then never play.
        if (response.statusCode != 200 && response.statusCode != 206) {
          await response.drain<void>().catchError((_) {});
          debugPrint('NewPipe download refused: HTTP ${response.statusCode}');
          return null;
        }
        return await _writeAudioFile(
            response, file, response.contentLength, onProgress);
      } finally {
        client.close(force: true);
      }
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

      return await _writeAudioFile(
        _yt.videos.streamsClient.get(audioStreamInfo),
        file,
        audioStreamInfo.size.totalBytes,
        onProgress,
      );
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
