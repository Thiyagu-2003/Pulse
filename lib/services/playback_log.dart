import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// One song start, step by step, for Settings > Diagnostics — so a slow or
/// failed start on a real phone can be seen (and shared) without USB logs.
class PlaybackAttempt {
  final DateTime startedAt;
  final String title;
  final String source; // local / youtube / podcast
  final List<String> steps;
  String outcome; // playing / failed / superseded

  PlaybackAttempt({
    required this.startedAt,
    required this.title,
    required this.source,
    List<String>? steps,
    this.outcome = 'loading',
  }) : steps = steps ?? [];

  final Stopwatch _clock = Stopwatch()..start();

  /// Record a step with the time since the tap, e.g. "stream URL: 312ms".
  void step(String what) => steps.add('$what @${_clock.elapsedMilliseconds}ms');

  Map<String, dynamic> toJson() => {
        'at': startedAt.toIso8601String(),
        'title': title,
        'source': source,
        'steps': steps,
        'outcome': outcome,
      };

  factory PlaybackAttempt.fromJson(Map<String, dynamic> json) =>
      PlaybackAttempt(
        startedAt: DateTime.parse(json['at'] as String),
        title: json['title'] as String,
        source: json['source'] as String,
        steps: (json['steps'] as List).cast<String>(),
        outcome: json['outcome'] as String,
      );

  @override
  String toString() {
    final time = startedAt.toIso8601String().substring(11, 19);
    return '$time  $outcome  [$source] $title\n  ${steps.join('\n  ')}';
  }
}

/// The last [limit] attempts, newest first, kept across restarts.
class PlaybackLog extends ChangeNotifier {
  PlaybackLog._();
  static final PlaybackLog instance = PlaybackLog._();

  static const int limit = 50;
  static const String _key = 'attempts';

  List<PlaybackAttempt>? _attempts;

  List<PlaybackAttempt> get attempts => List.unmodifiable(_load());

  List<PlaybackAttempt> _load() {
    if (_attempts != null) return _attempts!;
    final stored =
        StorageService.cacheBox(StorageService.playbackLogBox)?.get(_key);
    try {
      _attempts = stored == null
          ? []
          : (jsonDecode(stored) as List)
              .map((e) => PlaybackAttempt.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {
      _attempts = [];
    }
    return _attempts!;
  }

  PlaybackAttempt begin(String title, String source) {
    final attempt =
        PlaybackAttempt(startedAt: DateTime.now(), title: title, source: source);
    final list = _load()..insert(0, attempt);
    if (list.length > limit) list.removeRange(limit, list.length);
    // Saved now, not only at the end: a start that hangs until the app is
    // force-stopped is exactly the one worth seeing.
    _save();
    notifyListeners();
    return attempt;
  }

  /// Close an attempt and persist the log.
  void finish(PlaybackAttempt attempt, String outcome) {
    attempt.outcome = outcome;
    attempt.step(outcome);
    _save();
    notifyListeners();
  }

  void clear() {
    _attempts = [];
    _save();
    notifyListeners();
  }

  void _save() {
    final box = StorageService.cacheBox(StorageService.playbackLogBox);
    box?.put(_key, jsonEncode(_load().map((a) => a.toJson()).toList()));
  }

  /// Plain text for sharing.
  String export() => _load().map((a) => a.toString()).join('\n\n');
}
