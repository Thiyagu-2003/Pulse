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
}
