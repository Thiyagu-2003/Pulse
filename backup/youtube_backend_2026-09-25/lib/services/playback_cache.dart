import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Songs saved for instant, offline replay.
///
/// Two writers share the folder, with different names so their in-progress
/// files never collide:
/// - `<id>_<id>.stream.m4a` — saved by the player while it streams
///   (just_audio's LockCachingAudioSource, with `.part`/`.mime` beside it);
/// - `<id>_<id>.<ext>` — a whole song fetched ahead of time (the next track)
///   or as the last-resort fallback, written via `.part` + rename.
/// Either counts as "cached" once complete.
class PlaybackCache {
  PlaybackCache._();
  static final PlaybackCache instance = PlaybackCache._();

  /// Oldest songs go first once the folder passes this.
  static const int maxBytes = 400 * 1024 * 1024;

  Directory? _dir;

  @visibleForTesting
  set directory(Directory dir) => _dir = dir;

  Future<Directory> dir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = Directory('${(await getTemporaryDirectory()).path}/playback');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Where the player saves a song while streaming it. A fresh name per
  /// load: an abandoned load (timed out, or skipped) keeps writing in the
  /// background, and two writers on one file corrupted the saved song.
  Future<File> streamFileFor(String videoId) async => File(
      '${(await dir()).path}/${videoId}_$videoId.stream${DateTime.now().microsecondsSinceEpoch}.m4a');

  /// The song playing now; [trim] never deletes it (the player reopens the
  /// file on every seek).
  String? playingId;

  /// Where a whole-song fetch writes, given the container's extension.
  Future<File> fetchFileFor(String videoId, String ext) async =>
      File('${(await dir()).path}/${videoId}_$videoId.$ext');

  /// A complete cached copy of [videoId], if there is one.
  Future<String?> find(String videoId) async {
    try {
      final path = findIn(await dir(), videoId);
      // A replay counts as use: eviction goes by least recently played,
      // not by when the song was first saved.
      if (path != null) File(path).setLastModifiedSync(DateTime.now());
      return path;
    } catch (_) {
      return null; // no app storage (tests)
    }
  }

  @visibleForTesting
  static String? findIn(Directory dir, String videoId) {
    if (!dir.existsSync()) return null;
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('${videoId}_$videoId.') && !_isSidecar(name)) {
        return f.path;
      }
    }
    return null;
  }

  /// The video id in a cache file name (`<id>_<id>.…`). Ids can contain
  /// `_` themselves, so it's found by the repeat, not by splitting.
  @visibleForTesting
  static String? idOf(String name) {
    for (var k = 1; k * 2 + 2 <= name.length; k++) {
      final id = name.substring(0, k);
      if (name.startsWith('${id}_$id.')) return id;
    }
    return null;
  }

  static bool _isSidecar(String name) =>
      name.endsWith('.part') || name.endsWith('.mime');

  /// Bytes on disk, for Settings.
  Future<int> sizeBytes() async {
    try {
      final d = await dir();
      return d
          .listSync()
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + f.lengthSync());
    } catch (_) {
      return 0;
    }
  }

  /// Delete every saved copy of [videoId] (e.g. one that won't play).
  Future<void> remove(String videoId) async {
    try {
      for (final f in (await dir()).listSync().whereType<File>()) {
        if (idOf(f.uri.pathSegments.last) == videoId) f.deleteSync();
      }
    } catch (e) {
      debugPrint('Could not remove cached $videoId: $e');
    }
  }

  /// Settings > Saved songs > Clear. Files still being written are left
  /// alone — deleting them breaks the song playing right now.
  Future<void> clear() async {
    try {
      final d = await dir();
      final recent = DateTime.now().subtract(const Duration(minutes: 5));
      for (final f in d.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (_isSidecar(name) && f.statSync().modified.isAfter(recent)) continue;
        // The player reopens the playing song's file on every seek.
        if (playingId != null && idOf(name) == playingId) continue;
        f.deleteSync();
      }
    } catch (e) {
      debugPrint('Could not clear playback cache: $e');
    }
  }

  /// Keep the folder under [maxBytes]: whole songs (with their sidecars)
  /// are deleted oldest-first. Unfinished files older than a day are
  /// leftovers from an interrupted download and go too. [keep] (the song
  /// playing now) is never touched.
  Future<void> trim({String? keep, int? limit}) async {
    try {
      await trimIn(await dir(),
          keep: {?keep, ?playingId}, limit: limit ?? maxBytes);
    } catch (e) {
      debugPrint('Playback cache trim failed: $e');
    }
  }

  @visibleForTesting
  static Future<void> trimIn(Directory dir,
      {Set<String> keep = const {}, required int limit}) async {
    if (!dir.existsSync()) return;
    final groups = <String, List<File>>{};
    final now = DateTime.now();
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final id = idOf(name) ?? name;
      if (name.endsWith('.part') &&
          now.difference(f.statSync().modified) > const Duration(days: 1)) {
        f.deleteSync();
        continue;
      }
      (groups[id] ??= []).add(f);
    }

    int sizeOf(List<File> files) =>
        files.fold(0, (sum, f) => sum + f.lengthSync());
    DateTime usedAt(List<File> files) => files
        .map((f) => f.statSync().modified)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    var total = groups.values.fold(0, (sum, g) => sum + sizeOf(g));
    final oldestFirst = groups.entries.toList()
      ..sort((a, b) => usedAt(a.value).compareTo(usedAt(b.value)));
    for (final entry in oldestFirst) {
      if (total <= limit) break;
      if (keep.contains(entry.key)) continue;
      total -= sizeOf(entry.value);
      for (final f in entry.value) {
        f.deleteSync();
      }
    }
  }
}
