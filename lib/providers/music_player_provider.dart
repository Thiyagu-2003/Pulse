import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../models/lyrics.dart';
import '../models/media_item_model.dart';
import '../models/playback_mode.dart';
import '../models/playlist.dart';
import '../models/queue_state.dart';
import '../services/audio_handler.dart';
import '../services/storage_service.dart';
import '../services/lyrics_service.dart';
import '../services/youtube_service.dart';
import '../services/download_notifications.dart';
import '../services/platform_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MusicPlayerProvider extends ChangeNotifier {
  final CustomAudioHandler _audioHandler;
  final StorageService _storageService;
  final LyricsService _lyricsService = LyricsService();
  final YoutubeService ytService = YoutubeService();

  final QueueState _queueState = QueueState();
  QueueRepeat _repeat = QueueRepeat.off;

  AppMediaItem? _currentTrack;
  Lyrics? _currentLyrics;
  String? _lyricsKey;
  bool _isLoadingLyrics = false;
  final Set<String> _downloadingIds = {};
  final Map<String, double> _downloadProgress = {};

  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;
  Duration _lastSavedPosition = Duration.zero;

  MusicPlayerProvider(this._audioHandler, this._storageService) {
    ytService.pruneCaches();
    // The handler receives notification/headset/completion events but has no
    // queue of its own — route them back into this queue.
    _audioHandler.onSkipNext = skipToNext;
    _audioHandler.onSkipPrevious = skipToPrevious;
    _audioHandler.onTrackCompleted = _advanceOnCompletion;
    // A reload after Stop or an error resumes a podcast where it was.
    _audioHandler.resumePositionFor = (track) {
      final at = _resumePositionFor(track);
      _lastSavedPosition = at ?? Duration.zero;
      return at;
    };
    _initListeners();
  }

  CustomAudioHandler get audioHandler => _audioHandler;
  List<AppMediaItem> get queue => _queueState.items;
  int get currentIndex => _queueState.currentIndex;
  AppMediaItem? get currentTrack => _currentTrack;
  /// Null once loaded means no lyrics were found.
  Lyrics? get currentLyrics => _currentLyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;

  Stream<PlaybackState> get playbackState => _audioHandler.playbackState;
  Stream<MediaItem?> get currentMediaItem => _audioHandler.mediaItem;

  /// User-facing playback failures, for whoever is showing the SnackBar.
  Stream<String> get playbackErrors => _audioHandler.errors;

  /// PlaybackState is only broadcast when something changes, so seek bars must
  /// follow the player's own ticking position stream instead.
  Stream<Duration> get positionStream => _audioHandler.player.positionStream;
  Duration? get currentDuration =>
      _audioHandler.player.duration ?? _currentTrack?.duration;

  bool get isShuffled => _queueState.isShuffled;
  QueueRepeat get repeatMode => _repeat;

  bool get hasSleepTimer => _sleepTimer?.isActive ?? false;

  /// Time left before playback pauses, or null if no timer is running.
  Duration? get sleepTimeRemaining {
    if (!hasSleepTimer || _sleepEndsAt == null) return null;
    final left = _sleepEndsAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Pause playback after [duration]. Starting a new timer replaces any
  /// running one — otherwise both would fire.
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      _audioHandler.pause();
      _sleepEndsAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
    notifyListeners();
  }

  bool isDownloading(String id) => _downloadingIds.contains(id);

  /// Shuffle keeps the current track in place and reshuffles everything else,
  /// so turning it on doesn't yank the user off the song they're listening to.
  void toggleShuffle() {
    _queueState.setShuffled(!_queueState.isShuffled);
    notifyListeners();
  }

  /// Cycles off → repeat queue → repeat one track.
  void cycleRepeat() {
    _repeat = QueueRepeat
        .values[(_repeat.index + 1) % QueueRepeat.values.length];
    // Repeat-one is handled by the player itself so the loop is seamless.
    // Repeat-all needs our own queue, so the player stays unlooped for it.
    _audioHandler.setLoopOne(_repeat == QueueRepeat.one);
    notifyListeners();
  }

  void _initListeners() {
    _audioHandler.mediaItem.listen((item) {
      if (item != null) {
        _currentTrack = AppMediaItem.fromAudioServiceMediaItem(item);
        _invalidateLyrics();
        notifyListeners();
        _syncWidget();
      }
    });

    // The home-screen widget's play/pause icon.
    _audioHandler.playbackState
        .map((s) => s.playing)
        .distinct()
        .listen((_) => _syncWidget());

    // Deliberately NOT notifying on every playbackState event. Those fire many
    // times a second while buffering — precisely when a track is tapped — and
    // each notify rebuilt every visible TrackTile and all four tabs at once
    // (the IndexedStack keeps them alive), which is what made tapping a song
    // feel slow. Everything that needs live playback state uses a
    // StreamBuilder on playbackState/positionStream instead.

    // Remember where we are in podcast episodes. positionStream ticks several
    // times a second, so only write every 5s of actual progress.
    _audioHandler.player.positionStream.listen((position) {
      final track = _currentTrack;
      if (track == null || track.sourceType != MediaSourceType.podcast) return;
      if (!_audioHandler.player.playing) return;
      if ((position - _lastSavedPosition).abs() < const Duration(seconds: 5)) {
        return;
      }
      _lastSavedPosition = position;
      _storageService.savePosition(track.id, position);
    });
  }

  String? _widgetArtUrl;
  Future<String?>? _widgetArt;

  /// Push the current track to the home-screen widget. The widget can only
  /// show a local file, so network artwork is fetched once per track.
  Future<void> _syncWidget() async {
    final track = _currentTrack;
    final url = track?.artUri;
    String? artPath;
    if (url != null && url.startsWith('http')) {
      if (url != _widgetArtUrl) {
        _widgetArtUrl = url;
        _widgetArt = _fetchWidgetArt(url);
      }
      artPath = await _widgetArt;
      // A failed fetch shouldn't stick for this track; try again next time.
      if (artPath == null && url == _widgetArtUrl) _widgetArtUrl = null;
    }
    if (!identical(track, _currentTrack)) return; // changed while fetching
    await PlatformBridge.updateWidget(
      title: track?.title,
      artist: track?.artist,
      artPath: artPath,
      playing: _audioHandler.playbackState.value.playing,
    );
  }

  Future<String?> _fetchWidgetArt(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      // One file per image, so the widget never reads a half-written one.
      final file = File('${dir.path}/widget_art_${url.hashCode}.jpg');
      await file.writeAsBytes(response.bodyBytes);
      // Only the newest fetch cleans up: a slow, older one finishing last
      // would otherwise delete the current track's artwork.
      if (url != _widgetArtUrl) return file.path;
      for (final old in dir.listSync().whereType<File>()) {
        if (old.path.contains('widget_art_') && old.path != file.path) {
          old.deleteSync();
        }
      }
      return file.path;
    } catch (e) {
      debugPrint('Widget artwork unavailable: $e');
      return null;
    }
  }

  /// Download YouTube/Online track locally for offline playback
  Future<String?> downloadTrack(AppMediaItem item) async {
    if (_downloadingIds.contains(item.id)) return null;
    _downloadingIds.add(item.id);
    _holdKeepAlive();
    _downloadProgress[item.id] = 0;
    notifyListeners();
    final notifications = DownloadNotifications.instance;
    notifications.progress(item.id, item.title, null);
    var lastNotified = DateTime.now();
    var lastRepaint = DateTime.now();

    String? path;
    try {
      path = await ytService.downloadAudioTrack(
        item,
        onProgress: (value) {
          _downloadProgress[item.id] = value;
          final now = DateTime.now();
          // Repaint at most four times a second: every notify rebuilds the
          // Library (decoding all favorites) and every visible tile, and a
          // download-all runs two of these at once.
          if (now.difference(lastRepaint) >= const Duration(milliseconds: 250)) {
            lastRepaint = now;
            notifyListeners();
          }
          // The shade at most once a second: Android drops notification
          // updates sent faster than that, and could drop the final one.
          if (now.difference(lastNotified) >= const Duration(seconds: 1)) {
            lastNotified = now;
            notifications.progress(item.id, item.title, value);
          }
        },
      );

      if (path != null) {
        await _storageService.saveDownload(
          AppMediaItem(
            id: item.id,
            title: item.title,
            artist: item.artist,
            album: item.album,
            artUri: item.artUri,
            streamUrl: path,
            duration: item.duration,
            sourceType: MediaSourceType.local,
            // Where it came from, so a copy whose file is later deleted can
            // go back to streaming from that same source.
            extras: {
              originKey: item.sourceType.name,
              if (item.streamUrl?.startsWith('http') ?? false)
                originUrlKey: item.streamUrl,
            },
          ),
        );
      }
      return path;
    } catch (e) {
      debugPrint('Download failed: $e');
      path = null;
      return null;
    } finally {
      notifications.finished(item.id, item.title, succeeded: path != null);
      _downloadingIds.remove(item.id);
      _releaseKeepAlive();
      _downloadProgress.remove(item.id);
      notifyListeners();
    }
  }

  List<AppMediaItem> getDownloads() => _storageService.getDownloads();

  /// Online tracks in [items] not yet downloaded (or downloading).
  List<AppMediaItem> notDownloaded(List<AppMediaItem> items) => items
      .where((t) =>
          t.sourceType.isOnline &&
          !isDownloaded(t.id) &&
          !isDownloading(t.id))
      .toList();

  /// Download every online track in [items] that isn't on disk yet, two at a
  /// time — faster than one by one, without the burst that gets YouTube
  /// refusing requests. Returns how many failed.
  Future<int> downloadAll(List<AppMediaItem> items) async {
    final queue = notDownloaded(items);
    var failed = 0;
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final item = queue.removeAt(0);
        // Re-checked at its turn: another batch or a single download button
        // may have got to it meanwhile — that's not a failure, and not a
        // second download.
        if (isDownloaded(item.id) || isDownloading(item.id)) continue;
        if (await downloadTrack(item) == null) failed++;
      }
    }

    // Held for the whole batch: between two songs no download is running,
    // and a keep-alive dropped then can't be restarted from the background.
    _holdKeepAlive();
    try {
      await Future.wait([worker(), worker()]);
    } finally {
      _releaseKeepAlive();
    }
    return failed;
  }

  /// Everything that needs the app alive in the background (each download,
  /// a whole download-all batch) holds the keep-alive service; it stops
  /// when the last one lets go.
  int _keepAliveHolds = 0;

  void _holdKeepAlive() {
    if (_keepAliveHolds++ == 0) PlatformBridge.setDownloadsRunning(true);
  }

  void _releaseKeepAlive() {
    if (--_keepAliveHolds == 0) PlatformBridge.setDownloadsRunning(false);
  }
  bool isDownloaded(String id) => _storageService.isDownloaded(id);

  /// 0.0–1.0 while downloading, null otherwise.
  double? downloadProgress(String id) => _downloadProgress[id];

  /// Removes the entry *and* the file it owns — otherwise deleting a download
  /// would silently leave the bytes on disk forever.
  Future<void> deleteDownload(AppMediaItem item) async {
    final stored = _storageService.getDownload(item.id);
    final path = stored?.streamUrl;

    // Drop the entry before the file I/O: a swiped-away Dismissible still in
    // the list on the next rebuild throws.
    await _storageService.deleteDownload(item.id);
    notifyListeners();

    if (path != null && path.isNotEmpty && !path.startsWith('http')) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Could not delete downloaded file: $e');
      }
    }
  }

  /// Total bytes held by downloads, for the storage line in the UI.
  Future<int> downloadedBytes() async {
    var total = 0;
    for (final item in _storageService.getDownloads()) {
      final path = item.streamUrl;
      if (path == null || path.isEmpty || path.startsWith('http')) continue;
      try {
        final file = File(path);
        if (await file.exists()) total += await file.length();
      } catch (_) {
        // A file removed outside the app just doesn't count toward the total.
      }
    }
    return total;
  }

  /// Play a track directly or from a list
  Future<void> playTrack(
    AppMediaItem requested, {
    List<AppMediaItem>? playlist,
  }) async {
    if (playlist != null && playlist.isNotEmpty) {
      _queueState.replaceWith(playlist, requested);
    } else {
      _queueState.selectOrAppend(requested);
    }
    await _play(requested);
  }

  /// Start [requested], which the queue already points at.
  Future<void> _play(AppMediaItem requested) async {
    final online = streamableFallback(requested);
    // If it's on disk, play that: instant, offline, and no risk of an
    // expired stream URL. This is the whole point of downloading. Only if
    // the file is really still there — a removed SD card or deleted file
    // must fall back to streaming, not fail.
    final download = _storageService.getDownload(online.id);
    final track = download != null && _fileExists(download.streamUrl)
        ? download
        : online;
    _currentTrack = track;
    notifyListeners();

    final resumeAt = _resumePositionFor(track);
    _lastSavedPosition = resumeAt ?? Duration.zero;

    // Fire-and-forget the audio handler — it handles errors internally
    _audioHandler.playAppMediaItem(track, startAt: resumeAt);

    // History keeps the online track, not the on-disk copy: the copy stops
    // working once the download is removed.
    _storageService.addToHistory(online);

    _prefetchUpcoming();
  }

  /// Resolve the next track's stream URL while this one plays, so pressing
  /// next doesn't pay the extraction cost from scratch.
  void _prefetchUpcoming() {
    final next = _queueState.peekNext(repeat: _repeat);
    if (next == null || !next.sourceType.isOnline) return;
    // JioSaavn songs carry their link; YouTube ones need it resolved.
    if (next.sourceType == MediaSourceType.youtube) {
      ytService.warmStreamUrl(next.id);
    }
    // On Wi-Fi, fetch the whole next song too: Next and auto-advance then
    // play it from disk with no network wait at all.
    ytService.precacheForPlayback(next);
  }

  static bool _fileExists(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  /// Favorites and history saved by older versions hold the on-disk copy
  /// of a download (a local path, YouTube id). Once that file is gone, play
  /// the song online again instead of failing on a missing file.
  @visibleForTesting
  static AppMediaItem streamableFallback(AppMediaItem item) {
    final url = item.streamUrl;
    if (item.sourceType != MediaSourceType.local ||
        url == null ||
        url.startsWith('content://') ||
        _fileExists(url)) {
      return item;
    }
    // Downloads record their origin. Older ones don't: those were all
    // YouTube, recognisable by the 11-character video id.
    final origin = item.extras?[originKey] as String? ?? _originFromId(item.id);
    final source = origin == MediaSourceType.saavn.name
        ? MediaSourceType.saavn
        : origin == MediaSourceType.youtube.name
            ? MediaSourceType.youtube
            : null;
    if (source == null) return item;
    return AppMediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: item.album == 'Unknown Album' ? onlineAlbumLabel : item.album,
      artUri: item.artUri,
      // JioSaavn links don't expire, so the one recorded still plays; YouTube
      // ones do, and are looked up again.
      streamUrl: source == MediaSourceType.saavn
          ? (item.extras?[originUrlKey] as String?)
          : null,
      duration: item.duration,
      sourceType: source,
    );
  }

  /// For records saved before downloads noted their origin: YouTube ids are
  /// 11 characters, JioSaavn ids 8; device (MediaStore) ids are all digits.
  static String? _originFromId(String id) {
    if (RegExp(r'^\d+$').hasMatch(id)) return null;
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return MediaSourceType.youtube.name;
    }
    if (RegExp(r'^[A-Za-z0-9_-]{8}$').hasMatch(id)) {
      return MediaSourceType.saavn.name;
    }
    return null;
  }

  /// Keys in a download record's extras naming its online source.
  static const originKey = 'origin';
  static const originUrlKey = 'originUrl';

  /// Podcasts only: dropping back into a 90-minute episode where you left off
  /// is the expectation, whereas a song you tapped should start from the top.
  Duration? _resumePositionFor(AppMediaItem track) {
    if (track.sourceType != MediaSourceType.podcast) return null;
    final saved = _storageService.getPosition(track.id);
    if (saved == null) return null;
    return shouldResume(saved: saved, total: track.duration) ? saved : null;
  }

  /// Move a queue item. [from] and [to] are positions in the final list —
  /// callers using ReorderableListView must apply its off-by-one first.
  void moveInQueue(int from, int to) {
    _queueState.move(from, to);
    notifyListeners();
  }

  /// Remove a queue item. Removing the track that is playing skips to whatever
  /// takes its place, which is what every other player does.
  Future<void> removeFromQueue(int index) async {
    final wasPlaying = _queueState.removeAt(index);
    notifyListeners();

    if (!wasPlaying) return;

    final next = _queueState.currentTrack;
    if (next == null) {
      _currentTrack = null;
      notifyListeners();
      // Clears the handler's track too, so a headset or widget Play can't
      // bring back the song that was just removed.
      await _audioHandler.clear();
      return;
    }
    await _play(next);
  }

  /// Queue [item] directly after whatever is playing. False if [item] is
  /// what's playing, so the UI doesn't claim it was queued.
  bool playNext(AppMediaItem item) {
    final added = _queueState.insertNext(item);
    notifyListeners();
    _prefetchUpcoming();
    return added;
  }

  /// Append [item] to the end of the queue. False if it's what's playing.
  bool addToQueue(AppMediaItem item) {
    final added = _queueState.append(item);
    notifyListeners();
    return added;
  }

  /// Play the queue row at [index] — the row itself, even if a lookup by id
  /// would find a different one.
  Future<void> playQueueItem(int index) async {
    final item = _queueState.selectAt(index);
    if (item != null) await _play(item);
  }

  /// Skip to next track in queue
  Future<void> skipToNext() => _moveTo(auto: false);

  /// Advance when a track finishes on its own. Unlike [skipToNext] this
  /// honours repeat-one and stops at the end of a non-repeating queue.
  Future<void> _advanceOnCompletion() async {
    // A finished episode must not resume at its own outro next time.
    final finished = _currentTrack;
    if (finished != null) await _storageService.clearPosition(finished.id);
    await _moveTo(auto: true);
  }

  Future<void> _moveTo({required bool auto}) async {
    final next = _queueState.advance(repeat: _repeat, auto: auto);
    if (next == null) return;
    await _play(next);
  }

  /// Skip to previous track in queue
  Future<void> skipToPrevious() async {
    if (_queueState.isEmpty) return;
    // If more than 3 seconds into track, restart it. Otherwise, go previous.
    if (_audioHandler.player.position.inSeconds > 3) {
      await _audioHandler.seek(Duration.zero);
      return;
    }
    final previous = _queueState.previous();
    if (previous != null) await _play(previous);
  }

  /// Toggle Play/Pause. Resuming (and reloading after a failure) is the
  /// handler's job, so the notification and headset get the same behaviour.
  Future<void> togglePlayPause() async {
    // The handler's state, not the raw player: while a track loads the
    // player is still the old one, paused, but the user sees "playing".
    if (_audioHandler.playbackState.value.playing) {
      await _audioHandler.pause();
    } else if (_currentTrack != null) {
      await _audioHandler.play();
    }
  }

  /// Toggle Favorites
  Future<void> toggleFavorite(AppMediaItem item) async {
    await _storageService.toggleFavorite(item);
    notifyListeners();
  }

  bool isFavorite(String id) => _storageService.isFavorite(id);

  List<AppMediaItem> getFavorites() => _storageService.getFavorites();
  List<AppMediaItem> getHistory() => _storageService.getHistory();

  /// Custom Download Location
  String? get customDownloadPath => _storageService.getCustomDownloadPath();

  Future<void> setCustomDownloadPath(String? path) async {
    await _storageService.setCustomDownloadPath(path);
    notifyListeners();
  }

  /// Settings
  String? get homeLanguage => _storageService.getHomeLanguage();

  Future<void> setHomeLanguage(String? language) async {
    await _storageService.setHomeLanguage(language);
    notifyListeners();
  }

  AudioQuality get audioQuality => _storageService.getAudioQuality();

  /// Cached stream URLs were picked at the old quality, so drop them.
  Future<void> setAudioQuality(AudioQuality quality) async {
    await _storageService.setAudioQuality(quality);
    ytService.clearStreamCache();
    notifyListeners();
  }

  ThemeMode get themeMode => _storageService.getThemeMode();

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storageService.setThemeMode(mode);
    notifyListeners();
  }

  bool get darkLauncherIcon => _storageService.getDarkLauncherIcon();

  /// Saved now, applied when the app goes to the background: swapping the
  /// launcher entry while the app is open closes it on some phones.
  Future<void> setDarkLauncherIcon(bool dark) async {
    await _storageService.setDarkLauncherIcon(dark);
    notifyListeners();
  }

  bool get dataSaverOnMobile => _storageService.getDataSaverOnMobile();

  Future<void> setDataSaverOnMobile(bool on) async {
    await _storageService.setDataSaverOnMobile(on);
    ytService.clearStreamCache(); // links were picked at the other quality
    notifyListeners();
  }

  int get historyCount => _storageService.historyCount;

  Future<void> clearHistory() async {
    await _storageService.clearHistory();
    notifyListeners();
  }

  List<String> get recentSearches => _storageService.getRecentSearches();

  Future<void> addRecentSearch(String query) async {
    await _storageService.addRecentSearch(query);
    notifyListeners();
  }

  Future<void> clearRecentSearches() async {
    await _storageService.clearRecentSearches();
    notifyListeners();
  }

  /// Playlists
  List<Playlist> getPlaylists() => _storageService.getPlaylists();
  Playlist? getPlaylist(String id) => _storageService.getPlaylist(id);

  Future<Playlist> createPlaylist(String name) async {
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
    );
    await _storageService.savePlaylist(playlist);
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final playlist = _storageService.getPlaylist(id);
    if (playlist == null) return;
    await _storageService.savePlaylist(playlist.copyWith(name: name.trim()));
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    await _storageService.deletePlaylist(id);
    notifyListeners();
  }

  /// Returns false if the track was already there, so the UI can say so.
  Future<bool> addToPlaylist(String playlistId, AppMediaItem item) async {
    final playlist = _storageService.getPlaylist(playlistId);
    if (playlist == null || playlist.contains(item.id)) return false;
    await _storageService.savePlaylist(playlist.withItem(item));
    notifyListeners();
    return true;
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    final playlist = _storageService.getPlaylist(playlistId);
    if (playlist == null) return;
    await _storageService.savePlaylist(playlist.withoutItem(trackId));
    notifyListeners();
  }

  /// Drop lyrics for the previous track without fetching new ones — the
  /// request only happens if the user actually opens the lyrics panel.
  void _invalidateLyrics() {
    final key = _lyricsKeyFor(_currentTrack);
    if (key == _lyricsKey) return;
    _lyricsKey = null;
    _currentLyrics = null;
    _isLoadingLyrics = false;
  }

  String? _lyricsKeyFor(AppMediaItem? track) =>
      track == null ? null : '${track.title}|${track.artist}';

  /// Called when the lyrics panel opens. Fetching on every track change
  /// instead put an HTTP request on the wire at the exact moment the stream
  /// URL was being resolved, competing with the thing the user is waiting for.
  Future<void> ensureLyricsLoaded() async {
    if (_currentTrack == null) return;

    final key = _lyricsKeyFor(_currentTrack);
    if (key == _lyricsKey) return;
    _lyricsKey = key;

    _isLoadingLyrics = true;
    _currentLyrics = null;
    notifyListeners();

    try {
      final track = _currentTrack!;
      final lyrics = await _lyricsService.fetch(
        track.title,
        track.artist,
        duration: track.duration,
        saavnId: track.sourceType == MediaSourceType.saavn ||
                track.extras?[originKey] == MediaSourceType.saavn.name
            ? track.id
            : null,
      );

      if (_lyricsKey != key) return; // track changed while fetching
      _currentLyrics = lyrics;
    } catch (_) {
      if (_lyricsKey != key) return;
      _currentLyrics = null;
    }
    _isLoadingLyrics = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }
}
