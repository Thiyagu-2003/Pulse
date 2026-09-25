// The song menu links to the artist and album and shares a link — only
// when the song has them (JioSaavn songs do; device songs don't).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/saavn_service.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:music_player/ui/widgets/track_tile.dart';
import 'package:provider/provider.dart';

final _saavn = AppMediaItem(
  id: 'Egdcej1o',
  title: 'Vaseegara',
  artist: 'Bombay Jayashri',
  album: 'Minnalae',
  sourceType: MediaSourceType.saavn,
  extras: {
    SaavnService.artistIdKey: '458970',
    SaavnService.albumIdKey: '26737446',
    SaavnService.permaUrlKey: 'https://www.jiosaavn.com/song/vaseegara/x',
  },
);
final _device = AppMediaItem(
    id: '42', title: 'Local', artist: 'Me', sourceType: MediaSourceType.local);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  late MusicPlayerProvider provider;

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_menu_')).path);
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
  });

  test('share links', () {
    expect(shareLinkFor(_saavn), 'https://www.jiosaavn.com/song/vaseegara/x');
    expect(
      shareLinkFor(AppMediaItem(
          id: 'dQw4w9WgXcQ',
          title: 't',
          artist: 'a',
          sourceType: MediaSourceType.youtube)),
      'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(shareLinkFor(_device), isNull);
  });

  Future<void> openMenu(WidgetTester tester, AppMediaItem item) async {
    await tester.pumpWidget(ChangeNotifierProvider<MusicPlayerProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: TrackTile(item: item)),
      ),
    ));
    await tester.longPress(find.byType(TrackTile));
    await tester.pumpAndSettle();
  }

  testWidgets('a JioSaavn song links to artist, album and share',
      (tester) async {
    await openMenu(tester, _saavn);
    expect(find.text('Go to artist'), findsOneWidget);
    expect(find.text('Go to album'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('a device song has none of them', (tester) async {
    await openMenu(tester, _device);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Go to artist'), findsNothing);
    expect(find.text('Share'), findsNothing);
  });
}
