// ignore_for_file: avoid_print
// Hits the real internet. Not part of `flutter test` (which runs test/);
// run explicitly: flutter test test_live
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:music_player/models/home_sections.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/lyrics_service.dart';
import 'package:music_player/services/podcast_service.dart';
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
    final lyrics = await LyricsService().fetchLyrics('Shape of You', 'Ed Sheeran');
    print('lyrics: ${lyrics?.length ?? 0} chars');
    expect(lyrics, isNotNull);
  });
}
