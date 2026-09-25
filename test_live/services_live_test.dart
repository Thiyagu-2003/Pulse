// ignore_for_file: avoid_print
// Hits the real internet. Not part of `flutter test` (which runs test/);
// run explicitly: flutter test test_live
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/home_sections.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/lyrics_service.dart';
import 'package:music_player/services/podcast_service.dart';
import 'package:music_player/services/saavn_service.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';

void main() {
  // YoutubeService reads settings (audio quality, download folder).
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pulse_live_');
    Hive.init(dir.path);
    await Hive.openBox<String>(StorageService.settingsBox);
    // Downloads go through the app's own custom-folder setting: there is no
    // phone storage (path_provider) in a plain test.
    await StorageService().setCustomDownloadPath('${dir.path}/downloads');
  });

  final yt = YoutubeService();

  test('search returns songs (NewPipe is Android-only; explode fallback)', () async {
    final results = await yt.searchMusic('Anirudh hit songs', prefetch: false);
    print('search: ${results.length} results; first: ${results.firstOrNull?.title}');
    expect(results, isNotEmpty);
  });

  test('every Tamil home section query returns something', () async {
    final empty = <String>[];
    for (final s in homeSectionsFor('Tamil').where((s) => s.style == HomeSectionStyle.rows)) {
      // One retry: the fallback search occasionally times out.
      var r = await yt.searchMusic(s.query, prefetch: false);
      if (r.isEmpty) r = await yt.searchMusic(s.query, prefetch: false);
      final songs = r.where((t) => isSongLength(t.duration)).length;
      print('${s.title.padRight(24)} ${r.length} results, $songs song-length');
      if (songs == 0) empty.add(s.title);
    }
    expect(empty, isEmpty);
  });

  test('stream URL resolves fast and actually streams', () async {
    for (final id in ['kJQP7kiw5Fk', 'JGwWNGJdvx8', 'dQw4w9WgXcQ']) {
      yt.clearStreamCache();
      final sw = Stopwatch()..start();
      final url = await yt.getAudioStreamUrl(id);
      final fast = sw.elapsedMilliseconds;
      sw.reset();
      final verified = await yt.getAudioStreamUrl(id, verify: true);
      print('$id: unverified ${fast}ms (cached next: ${sw.elapsedMilliseconds}ms) -> ${url != null}');
      expect(url, isNotNull);
      expect(verified, url, reason: 'second call should hit the cache');
      final c = HttpClient();
      final req = await c.getUrl(Uri.parse(url!));
      req.headers.set('Range', 'bytes=0-1');
      final res = await req.close();
      await res.drain<void>();
      c.close(force: true);
      expect(res.statusCode, anyOf(200, 206));
    }
  });

  test('search suggestions come back for a partial query', () async {
    final s = await yt.searchSuggestions('anirudh');
    print('suggestions: $s');
    expect(s, isNotEmpty);
  });

  test('alternative sources each give a different, playable URL', () async {
    const id = 'JGwWNGJdvx8';
    final first = await yt.getAudioStreamUrl(id);
    final alts = await yt
        .alternativeStreamUrls(id, exclude: {first!})
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 60));
    print('alternatives: ${alts.length}');
    expect(alts, isNotEmpty);
    expect(alts, isNot(contains(first)));
  });

  test('download writes a complete audio file', () async {
    // A fixed video, so a flaky search can't fail the download test.
    final item = AppMediaItem(
      id: 'ew1fKCWb_M4',
      title: 'Vaseegara',
      artist: 'Harris Jayaraj',
      sourceType: MediaSourceType.youtube,
    );
    final sw = Stopwatch()..start();
    final path = await yt.downloadAudioTrack(item);
    print('downloaded ${item.title} in ${sw.elapsedMilliseconds}ms -> $path');
    expect(path, isNotNull);
    final f = File(path!);
    expect(await f.length(), greaterThan(500 * 1024));
    await f.delete();
  });

  test('an interrupted download resumes and ends byte-identical', () async {
    final item = AppMediaItem(
      id: 'ew1fKCWb_M4',
      title: 'Vaseegara',
      artist: 'Harris Jayaraj',
      sourceType: MediaSourceType.youtube,
    );
    final first = await yt.downloadAudioTrack(item);
    expect(first, isNotNull);
    final full = await File(first!).readAsBytes();

    // Pretend the app died 1 MB in.
    await File(first).delete();
    final part = YoutubeService.partFileFor(File(first), full.length);
    await part.writeAsBytes(full.sublist(0, 1024 * 1024));

    final sw = Stopwatch()..start();
    final second = await yt.downloadAudioTrack(item);
    print('resumed download in ${sw.elapsedMilliseconds}ms');
    expect(second, first);
    final resumed = await File(second!).readAsBytes();
    expect(resumed.length, full.length);
    expect(resumed, full);
    expect(part.existsSync(), isFalse);
    await File(second).delete();
  });

  group('JioSaavn (the Online source)', () {
    final saavn = SaavnService.instance;

    test('search, trending, playlist and suggestions answer fast', () async {
      final sw = Stopwatch()..start();
      final songs = await saavn.searchSongs('vaseegara');
      final tSearch = sw.elapsedMilliseconds;
      final trending = await saavn.trending('tamil');
      final playlist = await saavn.playlistSongs('Love Tamil');
      final suggestions = await saavn.suggestions('anir');
      print('saavn: search ${songs.length} in ${tSearch}ms, trending ${trending.length}, '
          'playlist ${playlist.length}, suggestions $suggestions');
      expect(songs, isNotEmpty);
      expect(trending, isNotEmpty);
      expect(playlist.length, greaterThan(10));
      expect(suggestions, isNotEmpty);
      expect(songs.first.streamUrl, startsWith('https://'));
    });

    test('every quality plays from the start and from 80% in', () async {
      final song = (await saavn.searchSongs('kannukulla')).first;
      for (final q in AudioQuality.values) {
        final url = SaavnService.withQuality(song.streamUrl!, q);
        final c = HttpClient();
        final head = await (await c.headUrl(Uri.parse(url))).close();
        await head.drain<void>();
        final at80 = (head.contentLength * 0.8).round();
        final req = await c.getUrl(Uri.parse(url));
        req.headers.set('Range', 'bytes=$at80-${at80 + 65535}');
        final res = await req.close();
        final got = await res.fold<int>(0, (n, b) => n + b.length);
        c.close(force: true);
        print('saavn ${q.name}: ${(head.contentLength / 1048576).toStringAsFixed(1)} MB, '
            '80% -> HTTP ${res.statusCode} $got bytes');
        expect(res.statusCode, 206);
        expect(got, 65536);
      }
    });

    test('a JioSaavn song downloads, and resumes byte-identical', () async {
      final song = (await saavn.searchSongs('vaseegara')).first;
      final sw = Stopwatch()..start();
      final path = await yt.downloadAudioTrack(song);
      print('saavn download ${sw.elapsedMilliseconds}ms -> $path');
      expect(path, isNotNull);
      final full = await File(path!).readAsBytes();
      await File(path).delete();
      final part = YoutubeService.partFileFor(File(path), full.length);
      await part.writeAsBytes(full.sublist(0, full.length ~/ 3));
      final again = await yt.downloadAudioTrack(song);
      expect(await File(again!).readAsBytes(), full);
      await File(again).delete();
    });

    test('a JioSaavn song gets lyrics', () async {
      final song = (await saavn.searchSongs('vaseegara')).first;
      final sw = Stopwatch()..start();
      final lyrics = (await LyricsService().fetch(song.title, song.artist,
              saavnId: song.id, duration: song.duration))
          ?.plain;
      print('saavn lyrics ${sw.elapsedMilliseconds}ms: '
          '${lyrics?.split('\n').take(2).join(' / ')}');
      // Synced (LRCLIB) when available, else JioSaavn's plain text;
      // either way real lines, in any script, with no HTML left in.
      expect(lyrics, isNotNull);
      expect(lyrics!.split('\n').length, greaterThan(5));
      expect(lyrics, isNot(contains('<br')));
    });

    test('trending Tamil songs get time-synced lyrics', () async {
      final songs = (await saavn.trending('tamil')).take(6).toList();
      var synced = 0;
      for (final song in songs) {
        final lyrics = await LyricsService().fetch(song.title, song.artist,
            saavnId: song.id, duration: song.duration);
        print('  lyrics ${lyrics == null ? 'none  ' : lyrics.isSynced ? 'SYNCED' : 'plain '} '
            '${lyrics?.lines.length ?? 0} lines  ${song.title}');
        if (lyrics?.isSynced ?? false) synced++;
      }
      expect(synced, greaterThanOrEqualTo(songs.length ~/ 2));
    });

    test('misspelled and descriptive searches still find the song', () async {
      const cases = {
        'vaseegara': 'vaseegara', // correct: must stay fast
        'vaseegra': 'vaseegara',
        'kamatchi song': 'kaamaatchi',
        'kannu kulla': 'kannukulla',
        'hukkum': 'hukum',
        'dippam dapam': 'dippam dappam',
        'thalapathi vijay beast song arabic': 'arabic kuthu',
      };
      var found = 0;
      for (final e in cases.entries) {
        final sw = Stopwatch()..start();
        final r = await yt.searchMusic(e.key, prefetch: false);
        final ok = r.take(3).any((t) => t.title
            .toLowerCase()
            .replaceAll(' ', '')
            .contains(e.value.replaceAll(' ', '')));
        if (ok) found++;
        print('  search ${ok ? 'OK  ' : 'MISS'} ${e.key.padRight(36)} '
            '${sw.elapsedMilliseconds}ms -> ${r.take(2).map((t) => t.title).toList()}');
      }
      expect(found, greaterThanOrEqualTo(cases.length - 1));
    });

    test('every Tamil home section fills from JioSaavn', () async {
      final empty = <String>[];
      for (final s in homeSectionsFor('Tamil')) {
        final queries = s.style == HomeSectionStyle.rows
            ? [s.query]
            : s.cards.map((c) => c.query);
        for (final q in queries) {
          final r = await YoutubeService.catalog(q);
          final tamil = r.where((t) => t.sourceType == MediaSourceType.saavn).length;
          print('  ${q.padRight(40)} ${r.length} songs ($tamil from JioSaavn)');
          if (r.isEmpty) empty.add(q);
        }
      }
      expect(empty, isEmpty);
    });
  });

  test('podcasts: search, then episodes from a real feed', () async {
    final ps = PodcastService();
    final channels = await ps.searchPodcasts('tamil');
    print('podcast channels: ${channels.length}');
    expect(channels, isNotEmpty);
    var episodes = 0;
    for (final c in channels.take(5)) {
      final eps = await ps.fetchEpisodes(c.feedUrl);
      print('  ${c.title}: ${eps.length} episodes; first: ${eps.firstOrNull?.title}');
      episodes += eps.length;
      if (eps.isNotEmpty) {
        final item = ps.episodeToMediaItem(eps.first, c);
        expect(item.streamUrl, startsWith('http'));
      }
    }
    expect(episodes, greaterThan(0));
  });

  test('lyrics found for a well-known song', () async {
    final lyrics = (await LyricsService().fetch('Shape of You', 'Ed Sheeran'))?.plain;
    print('lyrics: ${lyrics?.length ?? 0} chars');
    expect(lyrics, isNotNull);
  });
}
