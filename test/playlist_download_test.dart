// Downloading a collection as a playlist: its songs go into a folder of
// that name and a Library playlist; renaming the playlist moves the folder.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('folder names drop what filesystems refuse', () {
    expect(YoutubeService.safeFolderName('Hits: 2024/Best?'), 'Hits 2024 Best');
    expect(YoutubeService.safeFolderName('  ..  '), 'Playlist');
    expect(YoutubeService.safeFolderName('Tamil hits'), 'Tamil hits');
  });

  test('a playlist downloads into its own folder; rename moves it', () async {
    HttpOverrides.global = null; // the local server below
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.allMessagesHandler =
        (channel, handler, message) async => const StandardMethodCodec()
            .encodeSuccessEnvelope(<String, dynamic>{});
    final root = await Directory.systemTemp.createTemp('pulse_pl_');
    Hive.init('${root.path}/hive');
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
    final storage = StorageService();
    final music = await Directory('${root.path}/music').create();
    await storage.setCustomDownloadPath(music.path);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..contentLength = 2048
        ..add(List.filled(2048, 7));
      req.response.close();
    });
    AppMediaItem song(String id) => AppMediaItem(
          id: id,
          title: 'Song $id',
          artist: 'Artist',
          streamUrl: 'http://127.0.0.1:${server.port}/$id/x_160.mp4',
          sourceType: MediaSourceType.saavn,
        );

    final provider = MusicPlayerProvider(CustomAudioHandler(), storage);
    final failed = await provider
        .downloadPlaylist('Tamil hits', [song('s1abcdef'), song('s2abcdef')]);
    expect(failed, 0);

    final playlist = provider.getPlaylists().single;
    expect(playlist.name, 'Tamil hits');
    expect(playlist.folder, 'Tamil hits');
    expect(playlist.items.map((s) => s.id), ['s1abcdef', 's2abcdef']);
    final folder = Directory('${music.path}/Tamil hits');
    expect(folder.listSync().whereType<File>().length, 2);
    expect(storage.getDownload('s1abcdef')!.streamUrl,
        startsWith('${folder.path}/'));

    await provider.renamePlaylist(playlist.id, 'Road trip');
    expect(folder.existsSync(), isFalse);
    final moved = Directory('${music.path}/Road trip');
    expect(moved.listSync().whereType<File>().length, 2);
    final path = storage.getDownload('s1abcdef')!.streamUrl!;
    expect(path, startsWith('${moved.path}/'));
    expect(File(path).existsSync(), isTrue);
    expect(provider.getPlaylist(playlist.id)!.folder, 'Road trip');

    await server.close(force: true);
  });
}
