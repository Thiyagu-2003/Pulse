import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';

AppMediaItem _local(String id, String path) => AppMediaItem(
      id: id,
      title: 't',
      artist: 'a',
      streamUrl: path,
      sourceType: MediaSourceType.local,
    );

void main() {
  test('a saved download whose file is gone streams again', () {
    final item = _local('ew1fKCWb_M4', '/nope/Vaseegara_ew1fKCWb_M4.m4a');
    final fixed = MusicPlayerProvider.streamableFallback(item);
    expect(fixed.sourceType, MediaSourceType.youtube);
    expect(fixed.streamUrl, isNull);
    expect(fixed.id, item.id);
  });

  test('a download whose file exists stays local', () async {
    final dir = await Directory.systemTemp.createTemp('pulse_dl_');
    final f = File('${dir.path}/x.m4a')..writeAsStringSync('x');
    final item = _local('ew1fKCWb_M4', f.path);
    expect(MusicPlayerProvider.streamableFallback(item), same(item));
    await dir.delete(recursive: true);
  });

  test('device songs are never turned into online ones', () {
    final item = _local('4521', 'content://media/external/audio/media/4521');
    expect(MusicPlayerProvider.streamableFallback(item), same(item));
  });

  test('a downloaded JioSaavn song whose file is gone streams from JioSaavn',
      () {
    final item = AppMediaItem(
      id: 'bo7KIXAM',
      title: 'Vaseegara',
      artist: 'Harris Jayaraj',
      streamUrl: '/gone/Vaseegara [bo7KIXAM].m4a',
      sourceType: MediaSourceType.local,
      extras: {
        MusicPlayerProvider.originKey: 'saavn',
        MusicPlayerProvider.originUrlKey: 'https://aac.saavncdn.com/x_160.mp4',
      },
    );
    final fixed = MusicPlayerProvider.streamableFallback(item);
    expect(fixed.sourceType, MediaSourceType.saavn);
    expect(fixed.streamUrl, 'https://aac.saavncdn.com/x_160.mp4');
  });

  test('an older JioSaavn copy (no origin recorded) is recognised by its id',
      () {
    final fixed =
        MusicPlayerProvider.streamableFallback(_local('icJam_5l', '/gone/x.m4a'));
    expect(fixed.sourceType, MediaSourceType.saavn);
    expect(fixed.streamUrl, isNull); // the player fetches a fresh link
  });

  test('a device song with a missing file is never turned into an online one',
      () {
    final item = _local('12345678', '/gone/x.mp3');
    expect(MusicPlayerProvider.streamableFallback(item), same(item));
  });
}
