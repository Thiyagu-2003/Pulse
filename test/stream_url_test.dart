import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/youtube_service.dart';

void main() {
  final yt = YoutubeService();

  // Lookups read the quality setting (links are remembered per quality).
  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_url_')).path);
    await Hive.openBox<String>(StorageService.settingsBox);
  });
  tearDown(() {
    yt.debugExtractOverride = null;
    yt.clearStreamCache();
  });

  test('an uncached lookup completes (it used to wait on itself forever)',
      () async {
    yt.debugExtractOverride = (id, {required verify}) async => 'https://x/$id';
    final url = await yt
        .getAudioStreamUrl('abc')
        .timeout(const Duration(seconds: 2));
    expect(url, 'https://x/abc');
  });

  test('concurrent lookups for one video share a single extraction', () async {
    var calls = 0;
    yt.debugExtractOverride = (id, {required verify}) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 'https://x/$id';
    };
    final both = await Future.wait([
      yt.getAudioStreamUrl('v1'),
      yt.getAudioStreamUrl('v1'),
    ]).timeout(const Duration(seconds: 2));
    expect(both, ['https://x/v1', 'https://x/v1']);
    expect(calls, 1);
  });

  test('a failed lookup can be retried', () async {
    var calls = 0;
    yt.debugExtractOverride = (id, {required verify}) async {
      calls++;
      if (calls == 1) throw Exception('network');
      return 'https://x/$id';
    };
    await expectLater(yt.getAudioStreamUrl('v2'), throwsException);
    expect(await yt.getAudioStreamUrl('v2'), 'https://x/v2');
  });

  test('search prefetch warms all eight; a newer search stops the old queue',
      () async {
    final warmed = <String>[];
    yt.debugExtractOverride = (id, {required verify}) async {
      warmed.add(id);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return 'https://x/$id';
    };
    await yt.prefetchStreams([for (var i = 0; i < 8; i++) 'a$i']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(warmed.toSet(), {for (var i = 0; i < 8; i++) 'a$i'});

    warmed.clear();
    yt.clearStreamCache();
    final old = yt.prefetchStreams([for (var i = 0; i < 8; i++) 'b$i']);
    await yt.prefetchStreams(['c0']); // a new search
    await old;
    // The old run got its first three plus at most the one in flight.
    expect(warmed.where((id) => id.startsWith('b')).length, lessThanOrEqualTo(4));
    expect(warmed, contains('c0'));
  });

  group('cachedSearch', () {
    tearDown(() {
      yt.debugSearchOverride = null;
      yt.clearSearchCache();
    });

    test('runs at most 3 searches at once and finishes them all', () async {
      var running = 0, peak = 0;
      yt.debugSearchOverride = (q) async {
        running++;
        peak = running > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        running--;
        return [_song(q)];
      };
      final results = await Future.wait([
        for (var i = 0; i < 10; i++) yt.cachedSearch('q$i'),
      ]).timeout(const Duration(seconds: 5));
      expect(results.map((r) => r.single.id), [for (var i = 0; i < 10; i++) 'q$i']);
      expect(peak, 3);
    });

    test('an empty result is retried once, then forgotten', () async {
      yt.searchRetryDelay = Duration.zero;
      var calls = 0;
      yt.debugSearchOverride = (q) async {
        calls++;
        return calls == 2 ? [_song(q)] : <AppMediaItem>[];
      };
      expect(await yt.cachedSearch('x'), hasLength(1));
      expect(calls, 2);

      yt.debugSearchOverride = (q) async => <AppMediaItem>[];
      expect(await yt.cachedSearch('y'), isEmpty);
      // Not cached, so a later visit searches again.
      var later = 0;
      yt.debugSearchOverride = (q) async {
        later++;
        return [_song(q)];
      };
      expect(await yt.cachedSearch('y'), hasLength(1));
      expect(later, 1);
    });
  });
}

AppMediaItem _song(String id) =>
    AppMediaItem(id: id, title: id, artist: 'a', sourceType: MediaSourceType.youtube);
