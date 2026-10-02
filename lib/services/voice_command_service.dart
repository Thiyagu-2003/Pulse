import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// The action a voice command maps to.
enum VoiceAction {
  play,
  pause,
  resume,
  stop,
  next,
  previous,
  shuffle,
  repeat,
  search,
  favorite,
  volumeUp,
  volumeDown,
  none,
}

/// A parsed voice command with its action and optional payload (e.g. song name).
class VoiceCommand {
  final VoiceAction action;
  final String? query;
  final String rawText;

  const VoiceCommand({
    required this.action,
    this.query,
    required this.rawText,
  });

  @override
  String toString() => 'VoiceCommand($action, query: $query, raw: $rawText)';
}

/// Service that handles speech recognition and command parsing.
///
/// Lifecycle: create → [initialize] → [startListening] / [stopListening].
/// Dispose when the widget that owns it unmounts.
class VoiceCommandService {
  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;

  /// The most recent partial or final transcript.
  final _transcriptController = StreamController<String>.broadcast();

  /// Emitted when the speech engine stops and a final command is parsed.
  final _commandController = StreamController<VoiceCommand>.broadcast();

  /// Emitted on errors (permission denied, no speech detected, etc.).
  final _errorController = StreamController<String>.broadcast();

  /// Whether the engine is actively recording right now.
  final _listeningController = StreamController<bool>.broadcast();

  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<VoiceCommand> get commandStream => _commandController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<bool> get listeningStream => _listeningController.stream;
  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// True when the platform supports speech recognition (mobile only).
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Call once before any listening.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (!isSupported) return false;

    try {
      _isInitialized = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
      );
    } catch (e) {
      debugPrint('Voice init failed: $e');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  /// Start listening. Returns false if the engine couldn't start.
  Future<bool> startListening() async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        _errorController.add('Voice recognition is not available on this device');
        return false;
      }
    }

    if (_isListening) return true;

    try {
      await _speech.listen(
        onResult: _onResult,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        partialResults: true,
        listenMode: ListenMode.dictation,
      );
      _isListening = true;
      _listeningController.add(true);
      return true;
    } catch (e) {
      debugPrint('Voice listen failed: $e');
      _errorController.add('Could not start listening');
      return false;
    }
  }

  /// Stop listening and process whatever was recognised so far.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    _isListening = false;
    _listeningController.add(false);
  }

  /// Cancel without processing.
  Future<void> cancel() async {
    if (!_isListening) return;
    await _speech.cancel();
    _isListening = false;
    _listeningController.add(false);
  }

  void _onResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords;
    _transcriptController.add(text);
    if (result.finalResult && text.isNotEmpty) {
      final command = parseCommand(text);
      _commandController.add(command);
      _isListening = false;
      _listeningController.add(false);
    }
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('Voice error: ${error.errorMsg} (${error.permanent})');
    // "error_no_match" just means silence; don't scare the user.
    if (error.errorMsg != 'error_no_match') {
      _errorController.add(_friendlyError(error.errorMsg));
    }
    _isListening = false;
    _listeningController.add(false);
  }

  void _onStatus(String status) {
    debugPrint('Voice status: $status');
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      _listeningController.add(false);
    }
  }

  static String _friendlyError(String code) => switch (code) {
    'error_speech_timeout' => 'No speech detected. Tap to try again.',
    'error_no_match' => 'Couldn\'t understand that. Tap to try again.',
    'error_permission' => 'Microphone permission is required for voice commands.',
    'error_busy' => 'Voice recognition is busy. Try again in a moment.',
    'error_network' => 'Network error. Check your connection and try again.',
    _ => 'Voice recognition error. Tap to try again.',
  };

  // ───── Command parsing ─────

  /// Parse a raw transcript into a [VoiceCommand].
  ///
  /// The parser is intentionally generous — it recognises natural variations
  /// ("play", "put on", "start playing") and treats any unrecognised phrase
  /// as a search query, which is the most useful fallback for a music app.
  static VoiceCommand parseCommand(String raw) {
    final text = raw.trim();
    final lower = text.toLowerCase();

    // ── Playback controls ──
    if (_matches(lower, _pausePatterns)) {
      return VoiceCommand(action: VoiceAction.pause, rawText: text);
    }
    if (_matches(lower, _resumePatterns)) {
      return VoiceCommand(action: VoiceAction.resume, rawText: text);
    }
    if (_matches(lower, _stopPatterns)) {
      return VoiceCommand(action: VoiceAction.stop, rawText: text);
    }
    if (_matches(lower, _nextPatterns)) {
      return VoiceCommand(action: VoiceAction.next, rawText: text);
    }
    if (_matches(lower, _previousPatterns)) {
      return VoiceCommand(action: VoiceAction.previous, rawText: text);
    }
    if (_matches(lower, _shufflePatterns)) {
      return VoiceCommand(action: VoiceAction.shuffle, rawText: text);
    }
    if (_matches(lower, _repeatPatterns)) {
      return VoiceCommand(action: VoiceAction.repeat, rawText: text);
    }
    if (_matches(lower, _favoritePatterns)) {
      return VoiceCommand(action: VoiceAction.favorite, rawText: text);
    }
    if (_matches(lower, _volumeUpPatterns)) {
      return VoiceCommand(action: VoiceAction.volumeUp, rawText: text);
    }
    if (_matches(lower, _volumeDownPatterns)) {
      return VoiceCommand(action: VoiceAction.volumeDown, rawText: text);
    }

    // ── "Play <something>" ──
    final playQuery = _extractPlayQuery(lower);
    if (playQuery != null) {
      return VoiceCommand(
        action: VoiceAction.play,
        query: playQuery,
        rawText: text,
      );
    }

    // ── "Search for <something>" ──
    final searchQuery = _extractSearchQuery(lower);
    if (searchQuery != null) {
      return VoiceCommand(
        action: VoiceAction.search,
        query: searchQuery,
        rawText: text,
      );
    }

    // ── Bare "play" (no query) ──
    if (_matches(lower, _barePlayPatterns)) {
      return VoiceCommand(action: VoiceAction.resume, rawText: text);
    }

    // ── Fallback: treat the whole thing as a search ──
    return VoiceCommand(
      action: VoiceAction.search,
      query: text,
      rawText: text,
    );
  }

  static bool _matches(String input, List<RegExp> patterns) =>
      patterns.any((p) => p.hasMatch(input));

  static String? _extractPlayQuery(String lower) {
    for (final prefix in _playPrefixes) {
      final match = prefix.firstMatch(lower);
      if (match != null) {
        final query = lower.substring(match.end).trim();
        if (query.isNotEmpty) return query;
      }
    }
    return null;
  }

  static String? _extractSearchQuery(String lower) {
    for (final prefix in _searchPrefixes) {
      final match = prefix.firstMatch(lower);
      if (match != null) {
        final query = lower.substring(match.end).trim();
        if (query.isNotEmpty) return query;
      }
    }
    return null;
  }

  // ── Pattern tables ──

  static final _pausePatterns = [
    RegExp(r'^pause$'),
    RegExp(r'^pause ?(the )?(music|song|track|playback|audio)$'),
  ];

  static final _resumePatterns = [
    RegExp(r'^resume$'),
    RegExp(r'^resume ?(the )?(music|song|track|playback|audio)$'),
    RegExp(r'^continue ?(the )?(music|song|track|playback|audio)?$'),
    RegExp(r'^unpause$'),
  ];

  static final _stopPatterns = [
    RegExp(r'^stop$'),
    RegExp(r'^stop ?(the )?(music|song|track|playback|audio)$'),
  ];

  static final _nextPatterns = [
    RegExp(r'^(next|skip)$'),
    RegExp(r'^(next|skip) ?(the )?(song|track)$'),
    RegExp(r'^skip ?(to )?(the )?next$'),
    RegExp(r'^play ?(the )?next ?(song|track)?$'),
  ];

  static final _previousPatterns = [
    RegExp(r'^(previous|back)$'),
    RegExp(r'^(previous|back) ?(the )?(song|track)$'),
    RegExp(r'^(go )?back$'),
    RegExp(r'^play ?(the )?previous ?(song|track)?$'),
  ];

  static final _shufflePatterns = [
    RegExp(r'^shuffle$'),
    RegExp(r'^shuffle ?(the )?(songs|tracks|queue|playlist|music)?$'),
    RegExp(r'^(turn on|enable) ?shuffle$'),
  ];

  static final _repeatPatterns = [
    RegExp(r'^repeat$'),
    RegExp(r'^repeat ?(the )?(song|track|queue|playlist|music)?$'),
    RegExp(r'^(turn on|enable) ?repeat$'),
    RegExp(r'^loop$'),
    RegExp(r'^loop ?(the )?(song|track)?$'),
  ];

  static final _favoritePatterns = [
    RegExp(r'^(like|love|favorite|favourite)$'),
    RegExp(r'^(like|love|favorite|favourite) ?(this )?(song|track)?$'),
    RegExp(r'^add ?(this )?(song|track)? ?to ?(my )?favorites?$'),
    RegExp(r'^add ?(this )?(song|track)? ?to ?(my )?favourites?$'),
  ];

  static final _volumeUpPatterns = [
    RegExp(r'^volume up$'),
    RegExp(r'^(turn|crank|pump) ?(it|the volume) ?up$'),
    RegExp(r'^(increase|raise|louder) ?(the )?(volume)?$'),
  ];

  static final _volumeDownPatterns = [
    RegExp(r'^volume down$'),
    RegExp(r'^(turn|bring) ?(it|the volume) ?down$'),
    RegExp(r'^(decrease|lower|softer|quieter) ?(the )?(volume)?$'),
  ];

  static final _playPrefixes = [
    RegExp(r'^play '),
    RegExp(r'^put on '),
    RegExp(r'^start playing '),
    RegExp(r'^i (want|wanna) ?(to )?(hear|listen to) '),
    RegExp(r'^can you play '),
  ];

  static final _searchPrefixes = [
    RegExp(r'^search (for )?'),
    RegExp(r'^find '),
    RegExp(r'^look up '),
    RegExp(r'^look for '),
  ];

  static final _barePlayPatterns = [
    RegExp(r'^play$'),
    RegExp(r'^play ?(the )?(music|song|track|audio)$'),
    RegExp(r'^start$'),
    RegExp(r'^start ?(the )?(music|song|track|audio)$'),
  ];

  // ── Cleanup ──

  void dispose() {
    _speech.cancel();
    _transcriptController.close();
    _commandController.close();
    _errorController.close();
    _listeningController.close();
  }
}
