// A desktop-sized window: the home page must lay out without overflow, with
// Recently played in more than two columns and song pages side by side.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/home_sections.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';
import 'package:music_player/ui/screens/online_music_screen.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

AppMediaItem _song(String id) => AppMediaItem(
    id: id,
    title: 'Song $id',
    artist: 'Artist',
    duration: const Duration(minutes: 4),
    sourceType: MediaSourceType.saavn);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  late MusicPlayerProvider provider;

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_wide_')).path);
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
    for (var i = 0; i < 8; i++) {
      await StorageService().addToHistory(_song('h$i'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    provider = MusicPlayerProvider(CustomAudioHandler(), StorageService());
  });

  testWidgets('1366x768 window', (tester) async {
    final yt = YoutubeService();
    for (final section in [
      ...homeSectionsFor('Tamil'),
      ...provider.madeForYouSections,
    ]) {
      final queries = section.style == HomeSectionStyle.rows
          ? [section.query]
          : section.cards.map((c) => c.query);
      for (final q in queries) {
        yt.seedSearch(q, [for (var i = 0; i < 12; i++) _song('$q#$i')]);
      }
    }
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<MusicPlayerProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const OnlineMusicScreen(prefetch: false),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Recently played: 4 across, not 2.
    final y = tester.getTopLeft(find.text('Song h7')).dy;
    expect(tester.getTopLeft(find.text('Song h4')).dy, y);
    // Song pages ~420 wide: the second page is on screen beside the first.
    final row = provider.madeForYouSections.first.query; // first row on screen
    final first = 'Song $row#0';
    final fifth = 'Song $row#4';
    expect(tester.getTopLeft(find.text(first)).dx, lessThan(100));
    expect(tester.getTopLeft(find.text(fifth)).dx, lessThan(900));
    expect(tester.takeException(), isNull);
  });
}
