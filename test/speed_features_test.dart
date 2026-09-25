import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/playback_cache.dart';
import 'package:music_player/services/playback_log.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';

AppMediaItem _song(String id, {String title = 't', String artist = 'a'}) =>
    AppMediaItem(
        id: id, title: title, artist: artist, sourceType: MediaSourceType.youtube);

void main() {
  final yt = YoutubeService();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pulse_speed_');
    Hive.init(dir.path);
    for (final b in [
      StorageService.settingsBox,
      StorageService.streamUrlsBox,
      StorageService.searchCacheBox,
      StorageService.playbackLogBox,
    ]) {
      await Hive.openBox<String>(b);
    }
  });

  tearDown(() {
    yt.debugExtractOverride = null;
    yt.debugSearchOverride = null;
    yt.clearStreamCache();
    yt.clearSearchCache();
  });

  group('link expiry', () {
    final now = DateTime(2026, 9, 25, 12);
    test('read from the URL, ten minutes early', () {
      final expire =
          now.add(const Duration(hours: 5)).millisecondsSinceEpoch ~/ 1000;
      expect(streamUrlExpiry('https://x/v?expire=$expire&a=1', now: now),
          now.add(const Duration(hours: 4, minutes: 50)));
    });
    test('never trusted beyond 6 hours', () {
      final expire =
          now.add(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000;
      expect(streamUrlExpiry('https://x/v?expire=$expire', now: now),
          now.add(const Duration(hours: 6)));
    });
    test('30 minutes when the URL does not say', () {
      expect(streamUrlExpiry('https://x/v', now: now),
          now.add(const Duration(minutes: 30)));
    });
  });

  test('a link saved on an earlier run is used without a lookup', () async {
    final future = DateTime.now().add(const Duration(hours: 3));
    // Links are remembered per quality (default: balanced, not on mobile).
    Hive.box<String>(StorageService.streamUrlsBox).put('saved1@balanced',
        jsonEncode({'url': 'https://saved', 'exp': future.millisecondsSinceEpoch}));
    var lookups = 0;
    yt.debugExtractOverride = (id, {required verify}) async {
      lookups++;
      return 'https://fresh';
    };
    expect(await yt.getAudioStreamUrl('saved1'), 'https://saved');
    expect(lookups, 0);
  });

  test('an expired saved link is ignored and replaced', () async {
    final box = Hive.box<String>(StorageService.streamUrlsBox);
    box.put('old1@balanced', jsonEncode({'url': 'https://old', 'exp': 1}));
    yt.debugExtractOverride = (id, {required verify}) async => 'https://fresh';
    expect(await yt.getAudioStreamUrl('old1'), 'https://fresh');
  });

  test('startup prune drops expired saved links, keeps valid ones', () {
    final box = Hive.box<String>(StorageService.streamUrlsBox);
    final exp = DateTime.now().add(const Duration(hours: 1));
    box.put('rt1', jsonEncode({'url': 'https://rt', 'exp': exp.millisecondsSinceEpoch}));
    yt.pruneStreamCache();
    expect(box.containsKey('rt1'), isTrue);
    box.put('rt2', jsonEncode({'url': 'https://rt', 'exp': 1}));
    yt.pruneStreamCache();
    expect(box.containsKey('rt2'), isFalse);
  });

  group('home results saved across restarts', () {
    void store(String q, Duration age) =>
        Hive.box<String>(StorageService.searchCacheBox).put(
          q,
          jsonEncode({
            'at': DateTime.now().subtract(age).millisecondsSinceEpoch,
            'items': [_song('s1').toJson()],
          }),
        );

    test('recent: shown straight away, no search', () async {
      store('fresh q', const Duration(minutes: 5));
      var searches = 0;
      yt.debugSearchOverride = (q) async {
        searches++;
        return [_song('n1')];
      };
      expect((await yt.cachedSearch('fresh q')).single.id, 's1');
      expect(searches, 0);
    });

    test('older: shown straight away, refreshed behind it', () async {
      store('stale q', const Duration(hours: 5));
      yt.debugSearchOverride = (q) async => [_song('n1')];
      expect((await yt.cachedSearch('stale q')).single.id, 's1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await yt.cachedSearch('stale q')).single.id, 'n1');
    });

    test('too old: searched again, and the result saved', () async {
      store('ancient q', const Duration(days: 3));
      yt.debugSearchOverride = (q) async => [_song('n2')];
      expect((await yt.cachedSearch('ancient q')).single.id, 'n2');
      final saved = jsonDecode(
              Hive.box<String>(StorageService.searchCacheBox).get('ancient q')!)
          as Map<String, dynamic>;
      expect((saved['items'] as List).single['id'], 'n2');
    });
  });

  group('playback cache', () {
    test('ids containing underscores are read correctly', () {
      expect(PlaybackCache.idOf('ab_cd-EF_12_ab_cd-EF_12.stream.m4a'),
          'ab_cd-EF_12');
      expect(PlaybackCache.idOf('xyz_xyz.m4a.part'), 'xyz');
      expect(PlaybackCache.idOf('random.txt'), isNull);
    });

    test('finds finished files only', () async {
      final dir = await Directory.systemTemp.createTemp('pulse_pc_');
      File('${dir.path}/a1_a1.stream.m4a.part').writeAsStringSync('x');
      File('${dir.path}/a1_a1.stream.m4a.mime').writeAsStringSync('x');
      expect(PlaybackCache.findIn(dir, 'a1'), isNull);
      File('${dir.path}/a1_a1.stream.m4a').writeAsStringSync('x');
      expect(PlaybackCache.findIn(dir, 'a1'), endsWith('a1_a1.stream.m4a'));
      expect(PlaybackCache.findIn(dir, 'a'), isNull);
      await dir.delete(recursive: true);
    });

    test('trim drops oldest songs first, never the one playing', () async {
      final dir = await Directory.systemTemp.createTemp('pulse_trim_');
      final base = DateTime.now().subtract(const Duration(hours: 1));
      for (final (i, id) in ['old', 'mid', 'new'].indexed) {
        final f = File('${dir.path}/${id}_$id.m4a')
          ..writeAsBytesSync(List.filled(100, 0));
        f.setLastModifiedSync(base.add(Duration(minutes: i)));
      }
      final stalePart = File('${dir.path}/zz_zz.m4a.part')
        ..writeAsStringSync('x');
      stalePart.setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 2)));

      await PlaybackCache.trimIn(dir, keep: {'old'}, limit: 200);
      final left = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
      expect(left, {'old_old.m4a', 'new_new.m4a'}); // mid went; old is playing
      await dir.delete(recursive: true);
    });
  });

  test('download names are readable and keep non-Latin titles', () {
    final name = YoutubeService.downloadFileName(_song('ew1fKCWb_M4',
        title: 'வசீகரா: Vaseegara? <HD>', artist: 'Harris/Bombay'));
    expect(name, 'வசீகரா Vaseegara HD - Harris Bombay [ew1fKCWb_M4]');
    final long = YoutubeService.downloadFileName(_song('id', title: 'x' * 300));
    expect(utf8.encode(long).length, lessThanOrEqualTo(200));
  });

  test('diagnostics keep the newest 50 attempts across restarts', () {
    final log = PlaybackLog.instance..clear();
    for (var i = 0; i < 55; i++) {
      final a = log.begin('song $i', 'youtube');
      a.step('link via test');
      log.finish(a, 'playing');
    }
    expect(log.attempts.length, PlaybackLog.limit);
    expect(log.attempts.first.title, 'song 54');
    final stored = jsonDecode(Hive.box<String>(StorageService.playbackLogBox)
        .get('attempts')!) as List;
    expect(stored.length, PlaybackLog.limit);
    expect(log.export(), contains('link via test'));
  });

  test('long Tamil titles stay under the 255-byte file-name limit', () {
    final name = YoutubeService.downloadFileName(
        _song('ew1fKCWb_M4', title: 'வசீகரா' * 60, artist: 'ஹாரிஸ்'));
    final full = '$name.m4a.4790979.part';
    expect(utf8.encode(full).length, lessThanOrEqualTo(255));
    expect(name, endsWith('[ew1fKCWb_M4]'));
  });

  test('part files carry the stream size, so resumes never mix streams', () {
    final target = File('/x/song.m4a');
    expect(YoutubeService.partFileFor(target, 123).path,
        isNot(YoutubeService.partFileFor(target, 456).path));
  });

  test('a replay refreshes a saved song; clear spares what is in use', () async {
    final dir = await Directory.systemTemp.createTemp('pulse_use_');
    final cache = PlaybackCache.instance..directory = dir;
    final old = DateTime.now().subtract(const Duration(days: 3));
    final song = File('${dir.path}/p1_p1.m4a')..writeAsStringSync('x');
    song.setLastModifiedSync(old);
    expect(await cache.find('p1'), endsWith('p1_p1.m4a'));
    expect(song.lastModifiedSync().isAfter(old), isTrue);

    File('${dir.path}/q1_q1.stream1.m4a.part').writeAsStringSync('x'); // writing
    File('${dir.path}/r1_r1.m4a').writeAsStringSync('x'); // plain old song
    cache.playingId = 'p1';
    await cache.clear();
    final left = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(left, {'p1_p1.m4a', 'q1_q1.stream1.m4a.part'});
    cache.playingId = null;
    await dir.delete(recursive: true);
  });
}
