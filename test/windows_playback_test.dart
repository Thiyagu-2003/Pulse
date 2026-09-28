// Windows: an online song is fetched whole (Dart's HTTP client) and the
// player opens the file — the path that replaced the player streaming the
// link itself, which failed on Windows.
@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/playback_log.dart';
import 'package:music_player/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a JioSaavn song plays from the fetched file', () async {
    HttpOverrides.global = null; // a real local server, below
    final loads = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Its own folder: a copy fetched by an earlier run would play instead.
    final temp = await Directory.systemTemp.createTemp('pulse_win_tmp_');
    addTearDown(() => temp.delete(recursive: true));
    const codec = StandardMethodCodec();
    // Stands in for just_audio_windows: answers each call, and after a load
    // reports "ready" the way the plugin's PlaybackStateChanged event does.
    messenger.allMessagesHandler = (channel, handler, message) async {
      final call = codec.decodeMethodCall(message);
      if (channel == 'plugins.flutter.io/path_provider') {
        return codec.encodeSuccessEnvelope(temp.path);
      }
      if (call.method == 'androidEqualizerGetParameters') {
        // Only asked under test: just_audio enables Android effects there.
        return codec.encodeSuccessEnvelope({
          'parameters': {'minDecibels': -15.0, 'maxDecibels': 15.0, 'bands': []},
        });
      }
      if (call.method == 'load') {
        final source = (call.arguments as Map)['audioSource'] as Map;
        final child = (source['children'] as List? ?? [source]).first as Map;
        loads.add('${child['uri']}');
        final id = channel.substring(channel.lastIndexOf('.') + 1);
        Future<void>.delayed(const Duration(milliseconds: 5), () {
          messenger.handlePlatformMessage(
            'com.ryanheise.just_audio.events.$id',
            codec.encodeSuccessEnvelope({
              'processingState': 3, // ready
              'updatePosition': 0,
              'updateTime': DateTime.now().millisecondsSinceEpoch,
              'bufferedPosition': 0,
              'duration': 1000000,
              'currentIndex': 0,
            }),
            (_) {},
          );
        });
      }
      return codec.encodeSuccessEnvelope(<String, dynamic>{});
    };
    addTearDown(() => messenger.allMessagesHandler = null);

    final dir = await Directory.systemTemp.createTemp('pulse_win_');
    Hive.init(dir.path);
    for (final box in [
      StorageService.settingsBox,
      StorageService.playbackLogBox,
    ]) {
      await Hive.openBox<String>(box);
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType('audio', 'mp4')
        ..contentLength = 4096
        ..add(List.filled(4096, 1));
      req.response.close();
    });

    final handler = CustomAudioHandler();
    await handler.playAppMediaItem(AppMediaItem(
      id: 'winTest1',
      title: 'Windows song',
      artist: 'A',
      streamUrl: 'http://127.0.0.1:${server.port}/song_160.mp4',
      sourceType: MediaSourceType.saavn,
    ));

    expect(loads, isNotEmpty);
    expect(loads.first, startsWith('file:'), reason: 'played from disk');
    expect(PlaybackLog.instance.attempts.first.steps,
        contains(startsWith('playing fetched file')));
  });
}
