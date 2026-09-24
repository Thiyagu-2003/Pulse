import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../models/media_item_model.dart';
import '../models/playback_mode.dart';
import '../models/playlist.dart';
import '../models/queue_state.dart';
import '../services/audio_handler.dart';
import '../services/storage_service.dart';
import '../services/lyrics_service.dart';
import '../services/youtube_service.dart';

class MusicPlayerProvider extends ChangeNotifier {
  final CustomAudioHandler _audioHandler;
  final StorageService _storageService;
  final LyricsService _lyricsService = LyricsService();
  final YoutubeService ytService = YoutubeService();

  final QueueState _queueState = QueueState();
  QueueRepeat _repeat = QueueRepeat.off;

  AppMediaItem? _currentTrack;
  String? _currentLyrics;
  String? _lyricsKey;
  bool _isLoadingLyrics = false;
  final Set<String> _downloadingIds = {};
  final Map<String, double> _downloadProgress = {};

  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;
  Duration _lastSavedPosition = Duration.zero;

  MusicPlayerProvider(this._audioHandler, this._storageService) {
    // The handler receives notification/headset/completion events but has no
    // queue of its own — route them back into this queue.
    _audioHandler.onSkipNext = skipToNext;
    _audioHandler.onSkipPrevious = skipToPrevious;
    _audioHandler.onTrackCompleted = _advanceOnCompletion;
    _initListeners();
  }

  CustomAudioHandler get audioHandler => _audioHandler;
  List<AppMediaItem> get queue => _queueState.items;
  int get currentIndex => _queueState.currentIndex;
  AppMediaItem? get currentTrack => _currentTrack;
  String? get currentLyrics => _currentLyrics;
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
      }
    });

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

  /// Download YouTube/Online track locally for offline playback
  Future<String?> downloadTrack(AppMediaItem item) async {
    _downloadingIds.add(item.id);
    _downloadProgress[item.id] = 0;
    notifyListeners();

    try {
      final path = await ytService.downloadAudioTrack(
        item,
        onProgress: (value) {
          // Repaint per percent, not per chunk — a 5MB file arrives in
          // hundreds of chunks and each notify rebuilds the list.
          final percent = (value * 100).floor();
          if (percent == ((_downloadProgress[item.id] ?? 0) * 100).floor()) {
            return;
          }
          _downloadProgress[item.id] = value;
          notifyListeners();
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
          ),
        );
      }
      return path;
    } catch (e) {
      debugPrint('Download failed: $e');
      return null;
    } finally {
      _downloadingIds.remove(item.id);
      _downloadProgress.remove(item.id);
      notifyListeners();
    }
  }

  List<AppMediaItem> getDownloads() => _storageService.getDownloads();
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
    // If it's already on disk, play that: instant, offline, and no risk of an
    // expired stream URL. This is the whole point of downloading.
    final track = _storageService.getDownload(requested.id) ?? requested;
    _currentTrack = track;
    notifyListeners();

    final resumeAt = _resumePositionFor(track);
    _lastSavedPosition = resumeAt ?? Duration.zero;

    // Fire-and-forget the audio handler — it handles errors internally
    _audioHandler.playAppMediaItem(track, startAt: resumeAt);

    // Save to history in background
    _storageService.addToHistory(track);

    _prefetchUpcoming();
  }

  /// Resolve the next track's stream URL while this one plays, so pressing
  /// next doesn't pay the extraction cost from scratch.
  void _prefetchUpcoming() {
    final next = _queueState.peekNext(repeat: _repeat);
    if (next?.sourceType == MediaSourceType.youtube) {
      ytService.warmStreamUrl(next!.id);
    }
  }

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
      await _audioHandler.stop();
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
    if (_audioHandler.player.playing) {
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
      final lyrics = await _lyricsService.fetchLyrics(
        _currentTrack!.title,
        _currentTrack!.artist,
      );

      if (_lyricsKey != key) return; // track changed while fetching
      _currentLyrics = lyrics ?? 'Lyrics not available for this track.';
    } catch (_) {
      if (_lyricsKey != key) return;
      _currentLyrics = 'Lyrics not available for this track.';
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
