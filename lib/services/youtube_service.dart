import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_item_model.dart';
import '../models/search_match.dart';
import 'network_status.dart';
import 'platform_bridge.dart';
import 'playback_cache.dart';
import 'saavn_service.dart';
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
    // JioSaavn first: its results carry their playable URL, so nothing needs
    // resolving or prefetching.
    final viaSaavn = await catalog(query);
    // Radio rows ("Made for you") are JioSaavn's alone.
    if (query.startsWith('radio:')) return viaSaavn;
    final isHomeRow =
        query.startsWith('trending:') || query.startsWith('playlist:');
    if (isHomeRow) {
      if (viaSaavn.isNotEmpty) return viaSaavn;
      // A home row's "playlist:Love Tamil" searched on YouTube as literal
      // text gave junk that was then cached for a day: search the words.
      return _youtubeSearch(youtubeFallbackQuery(query), prefetch: prefetch);
    }
    // Typed searches: JioSaavn matches titles literally, so a typo, an extra
    // word or a description can return *something* that isn't the song.
    if (looksRelevant(query, viaSaavn)) return viaSaavn;
    return _forgivingSearch(query, viaSaavn, prefetch: prefetch);
  }

  /// When JioSaavn's answer doesn't match what was typed, try — stopping at
  /// the first that finds the song:
  /// 1. without filler words ("kamatchi song" → "kamatchi");
  /// 2. YouTube's spelling correction (its autocomplete fixes typos);
  /// 3. YouTube search, which understands descriptions ("vijay beast arabic
  ///    song"): its top video's song name, looked up on JioSaavn;
  /// 4. the YouTube results themselves.
  /// A correctly spelled search never gets here, so it costs nothing extra.
  Future<List<AppMediaItem>> _forgivingSearch(
    String query,
    List<AppMediaItem> direct, {
    required bool prefetch,
  }) async {
    final cleaned = stripFiller(query);
    if (cleaned != query.trim().toLowerCase()) {
      final r = await catalog(cleaned);
      if (looksRelevant(cleaned, r)) return r;
    }

    final corrected = await _spellingFix(cleaned);
    if (corrected != null) {
      final r = await catalog(stripFiller(corrected));
      if (looksRelevant(corrected, r)) return r;
    }

    final youtube = await _youtubeSearch(corrected ?? cleaned, prefetch: false);
    if (youtube.isNotEmpty) {
      final name = songNameFromVideoTitle(youtube.first.title);
      if (name.isNotEmpty) {
        final r = await catalog(name);
        if (looksRelevant(name, r)) return r;
      }
      if (prefetch) prefetchStreams(youtube.take(8).map((e) => e.id).toList());
      return youtube;
    }
    return direct;
  }

  /// YouTube's autocomplete top suggestion for [query] when it differs —
  /// in effect a spelling fix ("vasegara" → "vaseegara").
  Future<String?> _spellingFix(String query) async {
    List<String> suggestions = const [];
    try {
      suggestions = await SearchExtractor.getSearchSuggestions(query)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (suggestions.isEmpty) {
      try {
        suggestions = await _yt.search
            .getQuerySuggestions(query)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    if (suggestions.isEmpty) return null;
    final top = suggestions.first.trim();
    return top.toLowerCase() == query.toLowerCase() ? null : top;
  }

  Future<List<AppMediaItem>> _youtubeSearch(String text,
      {required bool prefetch}) async {
    final viaNewPipe = await _searchWithNewPipe(text);
    final results =
        viaNewPipe.isNotEmpty ? viaNewPipe : await _searchWithExplode(text);
    if (prefetch) prefetchStreams(results.take(8).map((e) => e.id).toList());
    return results;
  }

  /// [query] as a YouTube search: the catalog prefixes become words.
  @visibleForTesting
  static String youtubeFallbackQuery(String query) {
    if (query.startsWith('trending:')) {
      return '${query.substring('trending:'.length)} trending songs'.trim();
    }
    if (query.startsWith('playlist:')) {
      return '${query.substring('playlist:'.length)} songs';
    }
    return query;
  }

  /// A JioSaavn listing for [query]. Home rows use two prefixes:
  /// `trending:<language>` (JioSaavn's trending songs) and
  /// `playlist:<text>` (the best-matching editorial playlist — curated and
  /// in one language, unlike an artist search). Anything else is a song
  /// search. Never throws: an empty list means "try YouTube".
  static Future<List<AppMediaItem>> catalog(String query) async {
    final saavn = SaavnService.instance;
    try {
      if (query.startsWith('trending:')) {
        final language = query.substring('trending:'.length);
        return await saavn.trending(language.isEmpty ? null : language);
      }
      if (query.startsWith('playlist:')) {
        return await saavn.playlistSongs(query.substring('playlist:'.length));
      }
      if (query.startsWith('radio:')) {
        return await saavn.radio(query.substring('radio:'.length));
      }
      return await saavn.searchSongs(query);
    } catch (e) {
      debugPrint('JioSaavn listing failed for "$query": $e');
      return const [];
    }
  }

  final Map<String, Future<List<AppMediaItem>>> _searchCache = {};

  /// Search results kept for the session, so home sections don't reload
  /// every time they scroll back into view or the tab is revisited. Failed or
  /// empty searches are forgotten, so they can be retried.
  Future<List<AppMediaItem>> cachedSearch(String query) {
    final cached = _searchCache[query];
    if (cached != null) return cached;

    // Saved from an earlier run: show it at once, refresh behind it when
    // it's getting old — so the home page appears instantly on launch.
    final stored = _storedSearch(query);
    if (stored != null) {
      final (results, savedAt) = stored;
      final age = DateTime.now().difference(savedAt);
      if (age < _searchKeepFor) {
        if (age > _searchRefreshAfter) _refreshStoredSearch(query);
        return _searchCache[query] = Future.value(results);
      }
    }

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
      if (results.isEmpty) {
        forget();
      } else {
        _storeSearch(query, results);
      }
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

  /// Pull-to-refresh: forget saved results too, or it would show them again.
  void clearSearchCache() {
    _searchCache.clear();
    StorageService.cacheBox(StorageService.searchCacheBox)?.clear();
  }

  static const _searchKeepFor = Duration(hours: 24);
  static const _searchRefreshAfter = Duration(hours: 2);

  (List<AppMediaItem>, DateTime)? _storedSearch(String query) {
    final raw = StorageService.cacheBox(StorageService.searchCacheBox)?.get(query);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final items = (json['items'] as List)
          .map((e) => AppMediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (items.isEmpty) return null;
      return (items, DateTime.fromMillisecondsSinceEpoch(json['at'] as int));
    } catch (_) {
      return null;
    }
  }

  void _storeSearch(String query, List<AppMediaItem> results) {
    StorageService.cacheBox(StorageService.searchCacheBox)?.put(
      query,
      jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'items': results.map((t) => t.toJson()).toList(),
      }),
    );
  }

  final Set<String> _refreshing = {};

  /// Fetch a saved query again in the background (one at a time per query,
  /// through the same 3-slot queue); the next visit shows the new results.
  void _refreshStoredSearch(String query) {
    if (!_refreshing.add(query)) return;
    _limited(() async {
      final run = debugSearchOverride ??
          (String q) => searchMusic(q, prefetch: false);
      final results = await run(query);
      if (results.isNotEmpty) {
        _storeSearch(query, results);
        _searchCache[query] = Future.value(results);
      }
    }).catchError((Object _) {}).whenComplete(() {
      _refreshing.remove(query);
    });
  }

  @visibleForTesting
  void seedSearch(String query, List<AppMediaItem> results) =>
      _searchCache[query] = Future.value(results);

  /// Forget every resolved stream URL — "Clear stream cache" in Settings,
  /// and after the audio quality changes.
  void clearStreamCache() {
    _streamCache.clear();
    StorageService.cacheBox(StorageService.streamUrlsBox)?.clear();
    _cacheEpoch++;
  }

  /// A still-valid stream URL for [videoId]: memory first, then the copy
  /// saved on an earlier run (links stay valid for hours, so this makes
  /// recently played and pre-fetched songs start instantly after a restart).
  /// Links are remembered per quality: one found on Wi-Fi at full quality
  /// must not play on mobile data where Data saver applies (and the reverse
  /// would save a low-bitrate copy for good).
  String _urlKey(String videoId) => '$videoId@${playbackQuality().name}';

  String? _cachedUrl(String videoId) {
    final key = _urlKey(videoId);
    final inMemory = _streamCache[key];
    if (inMemory != null) {
      if (!inMemory.isExpired) return inMemory.url;
      _streamCache.remove(key);
    }
    final box = StorageService.cacheBox(StorageService.streamUrlsBox);
    final raw = box?.get(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final entry = _CachedStream(json['url'] as String,
          DateTime.fromMillisecondsSinceEpoch(json['exp'] as int));
      if (entry.isExpired) {
        box!.delete(key);
        return null;
      }
      _streamCache[key] = entry;
      return entry.url;
    } catch (_) {
      box!.delete(key);
      return null;
    }
  }

  /// Startup housekeeping: drop expired links and old saved searches. The
  /// search box would otherwise grow forever — the search screen's live
  /// preview saves results for every prefix typed.
  void pruneCaches() {
    pruneStreamCache();
    final searches = StorageService.cacheBox(StorageService.searchCacheBox);
    if (searches == null) return;
    final cutoff =
        DateTime.now().subtract(_searchKeepFor).millisecondsSinceEpoch;
    searches.deleteAll(searches.keys.where((k) {
      try {
        final json = jsonDecode(searches.get(k)!) as Map<String, dynamic>;
        return (json['at'] as int) < cutoff;
      } catch (_) {
        return true;
      }
    }).toList());
  }

  /// Drop saved links that have expired.
  void pruneStreamCache() {
    final box = StorageService.cacheBox(StorageService.streamUrlsBox);
    if (box == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dead = box.keys.where((k) {
      try {
        final json = jsonDecode(box.get(k)!) as Map<String, dynamic>;
        return (json['exp'] as int) <= now;
      } catch (_) {
        return true;
      }
    }).toList();
    box.deleteAll(dead);
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
      final viaSaavn = await SaavnService.instance.suggestions(q);
      if (viaSaavn.isNotEmpty) return viaSaavn;
    } catch (e) {
      debugPrint('JioSaavn suggestions failed: $e');
    }
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
    for (final q in AudioQuality.values) {
      final key = '$videoId@${q.name}';
      _streamCache.remove(key);
      StorageService.cacheBox(StorageService.streamUrlsBox)?.delete(key);
    }
  }

  /// Get direct playable audio stream URL — tries multiple strategies
  ///
  /// By default the URL is *not* test-fetched first: the player's own request
  /// is that test, and skipping a separate one saves a round trip on every
  /// tap. [verify] is for the retry after the player got a dead URL.
  Future<String?> getAudioStreamUrl(String videoId, {bool verify = false}) async {
    final cached = _cachedUrl(videoId);
    if (cached != null) {
      debugPrint('✅ Cache hit for $videoId');
      return cached;
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
        lastSource[videoId] = name;
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
      lastSource[videoId] = name;
      yield _remember(videoId, url);
    }
  }

  final Map<String, Future<String?>> _caching = {};

  /// Fetch the whole song into the playback cache and return the file.
  /// Used as the last resort when no stream URL will play (downloading takes
  /// a different, more forgiving path that keeps working when streaming
  /// doesn't) and to fetch the next song ahead of time.
  Future<String?> cacheForPlayback(AppMediaItem item) async {
    final existing = await PlaybackCache.instance.find(item.id);
    if (existing != null) return existing;
    return _caching[item.id] ??= () async {
      try {
        final path = item.sourceType == MediaSourceType.saavn
            // At the quality it would stream at, not the 320 of a download.
            ? await _downloadSaavn(
                item,
                await PlaybackCache.instance.fetchFileFor(item.id, 'm4a'),
                null,
                qualities: [playbackQuality()],
              )
            : await _downloadViaExplode(
                item,
                (ext) => PlaybackCache.instance.fetchFileFor(item.id, ext),
                null,
              );
        if (path != null) await PlaybackCache.instance.trim(keep: item.id);
        return path;
      } catch (e) {
        debugPrint('Playback cache failed for ${item.id}: $e');
        return null;
      }
    }()
        .whenComplete(() {
      _caching.remove(item.id);
    });
  }

  /// Fetch [item] in the background so pressing Next plays it from disk.
  /// Wi-Fi only: a whole song ahead is data the user may never use.
  void precacheForPlayback(AppMediaItem item) {
    if (!item.sourceType.isOnline) return;
    if (NetworkStatus.instance.onMobileData) return;
    cacheForPlayback(item).catchError((Object _) => null);
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
      final key = _urlKey(videoId);
      final entry = _CachedStream(url, streamUrlExpiry(url));
      _streamCache[key] = entry;
      StorageService.cacheBox(StorageService.streamUrlsBox)?.put(
        key,
        jsonEncode(
            {'url': url, 'exp': entry.expiresAt.millisecondsSinceEpoch}),
      );
    }
    return url;
  }

  /// Which source answered each recent lookup, for Diagnostics.
  final Map<String, String> lastSource = {};

  /// Resolve a stream URL ahead of time so tapping the track is instant.
  void warmStreamUrl(String videoId) {
    warmStreamUrlNow(videoId);
  }

  /// [warmStreamUrl] that can be awaited, so a batch can be warmed one at a
  /// time instead of firing a burst of requests at YouTube.
  Future<void> warmStreamUrlNow(String videoId) async {
    if (_cachedUrl(videoId) != null) return;
    await getAudioStreamUrl(videoId).catchError((_) => null);
  }

  /// The quality to stream at: the chosen one, or Data saver while on
  /// mobile data if that setting is on (a third of the bytes, so songs
  /// start sooner on a weak signal).
  AudioQuality playbackQuality() {
    final storage = StorageService();
    if (storage.getDataSaverOnMobile() && NetworkStatus.instance.onMobileData) {
      return AudioQuality.dataSaver;
    }
    return storage.getAudioQuality();
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
      return _audioStreamFor(manifest, playbackQuality())?.url.toString();
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
      Future<File> nameFor(String ext) async =>
          File('${dir.path}/${downloadFileName(item)}.$ext');

      if (item.sourceType == MediaSourceType.saavn) {
        final path = await _downloadSaavn(item, await nameFor('m4a'), onProgress);
        if (path != null) PlatformBridge.scanFile(path);
        return path;
      }

      // 1. Try youtube_explode first — unthrottled InnerTube streaming (1-2s total)
      final path = await _downloadViaExplode(item, nameFor, onProgress) ??
          // 2. Fall back to NewPipe with browser headers
          await _downloadViaNewPipe(item, nameFor, onProgress);
      // In a custom public folder, lets other music apps list it.
      if (path != null) PlatformBridge.scanFile(path);
      return path;
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  /// "Title - Artist" as a file name: readable in any file manager or music
  /// app, keeping non-Latin titles (the old name replaced every Tamil letter
  /// with `_`). Only characters no filesystem allows are removed; the video
  /// id is kept at the end so two songs with the same title can't collide.
  @visibleForTesting
  static String downloadFileName(AppMediaItem item) {
    String clean(String s) => s
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Filesystems cap names at 255 *bytes*; a Tamil letter is 3 bytes in
    // UTF-8, so cut by bytes (whole characters only), leaving room for the
    // id, extension and ".<size>.part".
    var name = clean('${item.title} - ${item.artist}');
    final runes = name.runes.toList();
    while (utf8.encode(String.fromCharCodes(runes)).length > 180) {
      runes.removeLast();
    }
    name = String.fromCharCodes(runes).trim();
    return '$name [${item.id}]';
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
    void Function(double)? onProgress, {
    int resumeFrom = 0,
  }) async {
    final part = partFileFor(target, total);
    // Appending continues an interrupted download instead of starting over.
    final sink =
        part.openWrite(mode: resumeFrom > 0 ? FileMode.append : FileMode.write);
    var received = resumeFrom;
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
      // The .part stays: a retry resumes from it. (Leftovers are ignored by
      // every lookup, and the playback cache clears them after a day.)
      await sink.close().catchError((_) {});
      rethrow;
    }
  }

  /// The unfinished file for [target]. Named with the stream's size, so a
  /// resume only ever continues the *same* stream — never appends one
  /// format's bytes to another's.
  static File partFileFor(File target, int total) =>
      File('${target.path}.$total.part');

  /// The rest of a stream from byte [from], or null if the server won't
  /// serve a range (then the caller starts over).
  Future<(Stream<List<int>>, HttpClient)?> _rangeFrom(Uri url, int from) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode == 206) return (response, client);
      await response.drain<void>().catchError((_) {});
    } catch (e) {
      debugPrint('Resume refused: $e');
    }
    client.close(force: true);
    return null;
  }

  /// A JioSaavn song is one plain file on its CDN: fetched at 320 kbps
  /// (falling back to 160 where a song has no 320 version), resumable.
  Future<String?> _downloadSaavn(
    AppMediaItem item,
    File target,
    void Function(double)? onProgress, {
    List<AudioQuality> qualities = const [
      AudioQuality.best,
      AudioQuality.balanced,
      AudioQuality.dataSaver,
    ],
  }) async {
    var url = item.streamUrl;
    if (url == null || !url.startsWith('http')) {
      url = (await SaavnService.instance.song(item.id))?.streamUrl;
    }
    if (url == null) return null;
    for (final quality in qualities) {
      final path = await _downloadHttp(
          SaavnService.withQuality(url, quality), target, onProgress);
      if (path != null) return path;
    }
    return null;
  }

  /// Download [url] to [target] — resuming an earlier `.part` when there is
  /// one and the server honours ranges.
  Future<String?> _downloadHttp(
    String url,
    File target,
    void Function(double)? onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final head = await (await client.headUrl(Uri.parse(url)))
          .close()
          .timeout(const Duration(seconds: 15));
      await head.drain<void>().catchError((_) {});
      if (head.statusCode != 200) return null;
      final total = head.contentLength;

      final part = partFileFor(target, total);
      final have = part.existsSync() ? part.lengthSync() : 0;
      final request = await client.getUrl(Uri.parse(url));
      if (have > 0 && have < total) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      final resumed = response.statusCode == 206;
      if (response.statusCode != 200 && !resumed) {
        await response.drain<void>().catchError((_) {});
        return null;
      }
      return await _writeAudioFile(response, target, total, onProgress,
          resumeFrom: resumed ? have : 0);
    } catch (e) {
      debugPrint('Download failed for $url: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Download using NewPipe extractor with unthrottled headers.
  Future<String?> _downloadViaNewPipe(
    AppMediaItem item,
    Future<File> Function(String ext) fileFor,
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
      final file = await fileFor(ext);

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
    Future<File> Function(String ext) fileFor,
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
      final file = await fileFor(_extensionFor(audioStreamInfo));
      final total = audioStreamInfo.size.totalBytes;

      // An interrupted earlier attempt left a .part: continue it.
      final part = partFileFor(file, total);
      final have = part.existsSync() ? part.lengthSync() : 0;
      if (have > 0 && have < total) {
        final rest = await _rangeFrom(audioStreamInfo.url, have);
        if (rest != null) {
          final (bytes, client) = rest;
          try {
            debugPrint('Resuming ${item.id} from $have of $total bytes');
            return await _writeAudioFile(bytes, file, total, onProgress,
                resumeFrom: have);
          } finally {
            client.close(force: true);
          }
        }
      }

      return await _writeAudioFile(
        _yt.videos.streamsClient.get(audioStreamInfo),
        file,
        total,
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

/// A resolved stream URL and when it stops working.
class _CachedStream {
  final String url;
  final DateTime expiresAt;

  _CachedStream(this.url, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// When a stream URL stops working. googlevideo URLs carry it themselves
/// (`expire=`, unix seconds, typically ~6 hours out); it's treated as ten
/// minutes earlier so a song never starts on a link about to die. Without
/// the parameter, 30 minutes.
@visibleForTesting
DateTime streamUrlExpiry(String url, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final expire = int.tryParse(Uri.tryParse(url)?.queryParameters['expire'] ?? '');
  if (expire == null) return at.add(const Duration(minutes: 30));
  final expiry = DateTime.fromMillisecondsSinceEpoch(expire * 1000)
      .subtract(const Duration(minutes: 10));
  // Never trust more than 6h, and never less than "already expired".
  final cap = at.add(const Duration(hours: 6));
  return expiry.isAfter(cap) ? cap : expiry;
}
