import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../models/media_item_model.dart';
import '../services/audio_handler.dart';
import '../services/storage_service.dart';
import '../services/lyrics_service.dart';
import '../services/youtube_service.dart';

class MusicPlayerProvider extends ChangeNotifier {
  final CustomAudioHandler _audioHandler;
  final StorageService _storageService;
  final LyricsService _lyricsService = LyricsService();
  final YoutubeService ytService = YoutubeService();

  List<AppMediaItem> _queue = [];
  int _currentIndex = -1;
  AppMediaItem? _currentTrack;
  String? _currentLyrics;
  bool _isLoadingLyrics = false;
  final Set<String> _downloadingIds = {};

  MusicPlayerProvider(this._audioHandler, this._storageService) {
    _initListeners();
  }

  CustomAudioHandler get audioHandler => _audioHandler;
  List<AppMediaItem> get queue => _queue;
  int get currentIndex => _currentIndex;
  AppMediaItem? get currentTrack => _currentTrack;
  String? get currentLyrics => _currentLyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;

  Stream<PlaybackState> get playbackState => _audioHandler.playbackState;
  Stream<MediaItem?> get currentMediaItem => _audioHandler.mediaItem;

  bool isDownloading(String id) => _downloadingIds.contains(id);

  void _initListeners() {
    _audioHandler.mediaItem.listen((item) {
      if (item != null) {
        _currentTrack = AppMediaItem.fromAudioServiceMediaItem(item);
        _fetchLyricsForCurrentTrack();
        notifyListeners();
      }
    });

    // Listen to playback state changes to keep UI reactive
    _audioHandler.playbackState.listen((_) {
      notifyListeners();
    });
  }

  /// Download YouTube/Online track locally for offline playback
  Future<String?> downloadTrack(AppMediaItem item) async {
    _downloadingIds.add(item.id);
    notifyListeners();

    try {
      final path = await ytService.downloadAudioTrack(item);
      if (path != null) {
        final localItem = AppMediaItem(
          id: item.id,
          title: item.title,
          artist: item.artist,
          album: item.album,
          artUri: item.artUri,
          streamUrl: path,
          sourceType: MediaSourceType.local,
        );
        await _storageService.toggleFavorite(localItem);
      }
      return path;
    } catch (e) {
      debugPrint('Download failed: $e');
      return null;
    } finally {
      _downloadingIds.remove(item.id);
      notifyListeners();
    }
  }

  /// Play a track directly or from a list
  Future<void> playTrack(AppMediaItem track, {List<AppMediaItem>? playlist}) async {
    if (playlist != null && playlist.isNotEmpty) {
      _queue = List.from(playlist);
      _currentIndex = _queue.indexWhere((t) => t.id == track.id);
      if (_currentIndex == -1) {
        _queue.insert(0, track);
        _currentIndex = 0;
      }
    } else {
      if (!_queue.any((t) => t.id == track.id)) {
        _queue.add(track);
      }
      _currentIndex = _queue.indexWhere((t) => t.id == track.id);
    }

    _currentTrack = track;
    notifyListeners();

    // Fire-and-forget the audio handler — it handles errors internally
    _audioHandler.playAppMediaItem(track);

    // Save to history in background
    _storageService.addToHistory(track);
  }

  /// Skip to next track in queue
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _queue.length;
    await playTrack(_queue[_currentIndex]);
  }

  /// Skip to previous track in queue
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    // If more than 3 seconds into track, restart it. Otherwise, go previous.
    if (_audioHandler.player.position.inSeconds > 3) {
      await _audioHandler.seek(Duration.zero);
      return;
    }
    _currentIndex = (_currentIndex - 1 + _queue.length) % _queue.length;
    await playTrack(_queue[_currentIndex]);
  }

  /// Toggle Play/Pause — fast, no async loading delays
  Future<void> togglePlayPause() async {
    if (_audioHandler.player.playing) {
      await _audioHandler.pause();
    } else {
      if (_audioHandler.player.audioSource == null && _currentTrack != null) {
        // No audio source loaded, re-play the current track
        await _audioHandler.playAppMediaItem(_currentTrack!);
      } else {
        await _audioHandler.play();
      }
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

  /// Fetch Synced Lyrics
  Future<void> _fetchLyricsForCurrentTrack() async {
    if (_currentTrack == null) return;
    _isLoadingLyrics = true;
    _currentLyrics = null;
    notifyListeners();

    try {
      final lyrics = await _lyricsService.fetchLyrics(
        _currentTrack!.title,
        _currentTrack!.artist,
      );

      _currentLyrics = lyrics ?? 'Lyrics not available for this track.';
    } catch (_) {
      _currentLyrics = 'Lyrics not available for this track.';
    }
    _isLoadingLyrics = false;
    notifyListeners();
  }
}
