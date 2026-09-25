// Autoplay: when the queue's last song starts, similar songs are queued
// behind it — and not when it's off, repeating, or mid-queue.
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/saavn_service.dart';
import 'package:music_player/services/storage_service.dart';

AppMediaItem _song(String id) => AppMediaItem(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      streamUrl: 'https://example.invalid/$id.mp4',
      sourceType: MediaSourceType.saavn,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MusicPlayerProvider provider;
  final seeds = <String>[];

  setUpAll(() async {
    // No phone: answer every plugin call (the audio player opens a channel
    // per player) so playing doesn't throw.
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.allMessagesHandler =
        (channel, handler, message) async => const StandardMethodCodec()
            .encodeSuccessEnvelope(<String, dynamic>{});
    Hive.init((await Directory.systemTemp.createTemp('pulse_auto_')).path);
    for (final box in [
      StorageService.favoritesBox,
      StorageService.historyBox,
      StorageService.playlistsBox,
      StorageService.downloadsBox,
      StorageService.settingsBox,
    ]) {
      await Hive.openBox<String>(box);
    }
    await Hive.openBox<int>(StorageService.positionsBox);
    provider = MusicPlayerProvider(CustomAudioHandler(), StorageService());
    SaavnService.debugRadioOverride = (id) async {
      seeds.add(id);
      return [_song('r1'), _song('a'), _song('r2')]; // 'a' is already queued
    };
  });

  tearDownAll(() => SaavnService.debugRadioOverride = null);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('queues similar songs when the last song starts', () async {
    final list = [_song('a'), _song('b')];
    await provider.playTrack(list[0], playlist: list);
    await settle();
    expect(seeds, isEmpty, reason: 'not the last song');

    await provider.playTrack(list[1], playlist: list);
    await settle();
    expect(seeds, ['b']);
    expect(provider.queue.map((t) => t.id), ['a', 'b', 'r1', 'r2']);
  });

  test('not when autoplay is off, or for device songs', () async {
    seeds.clear();
    await provider.setAutoplay(false);
    await provider.playTrack(_song('x'), playlist: [_song('x')]);
    await settle();
    await provider.setAutoplay(true);
    final local = AppMediaItem(
        id: '42', title: 't', artist: 'a', sourceType: MediaSourceType.local);
    await provider.playTrack(local, playlist: [local]);
    await settle();
    expect(seeds, isEmpty);
  });

  test('each podcast show keeps its own speed; songs their own', () async {
    AppMediaItem episode(String show) => AppMediaItem(
        id: 'ep-$show',
        title: 'Episode',
        artist: 'Host',
        album: show,
        streamUrl: 'https://example.invalid/$show.mp3',
        sourceType: MediaSourceType.podcast);
    await provider.playTrack(episode('Show A'));
    await provider.setSpeed(1.5);
    await provider.playTrack(_song('song'));
    expect(provider.speed, 1.0);
    await provider.playTrack(episode('Show B'));
    expect(provider.speed, 1.0);
    await provider.playTrack(episode('Show A'));
    expect(provider.speed, 1.5);
  });

  test('clear up next keeps the song playing; save queue as playlist',
      () async {
    await provider.setAutoplay(false);
    final list = [_song('q1'), _song('q2'), _song('q3')];
    await provider.playTrack(list[1], playlist: list);

    final saved = await provider.saveQueueAsPlaylist('My queue');
    expect(provider.getPlaylist(saved.id)!.items.map((t) => t.id),
        ['q1', 'q2', 'q3']);

    provider.clearUpNext();
    expect(provider.queue.map((t) => t.id), ['q2']);
    expect(provider.currentIndex, 0);
    await provider.setAutoplay(true);
  });

  test('Android Auto browses folders and plays a song with its folder',
      () async {
    await provider.setAutoplay(false);
    final fav1 = _song('f1'), fav2 = _song('f2');
    await provider.toggleFavorite(fav1);
    await provider.toggleFavorite(fav2);

    final root = await provider.browseForAuto(AudioService.browsableRootId);
    expect(root.map((m) => m.title),
        containsAll(['Recently played', 'Favorites', 'Downloads', 'My queue']));
    expect(root.every((m) => m.playable == false), isTrue);

    final favorites = await provider.browseForAuto('auto_favorites');
    expect(favorites.map((m) => m.id),
        containsAll(['auto_favorites|f1', 'auto_favorites|f2']));

    await provider.playFromAuto('auto_favorites|f2');
    expect(provider.currentTrack?.id, 'f2');
    expect(provider.queue.map((t) => t.id).toSet(), {'f1', 'f2'});
    await provider.setAutoplay(true);
  });
}
