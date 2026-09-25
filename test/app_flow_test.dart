// Drives the real app shell — real provider, storage and audio handler —
// through every tab and the main flows, in both themes. There is no
// phone here, so platform plugins (audio, NewPipe, permissions) are absent;
// the app must cope with that without throwing, which is itself worth
// checking. Any exception or layout overflow fails the test.
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
import 'package:music_player/ui/screens/main_navigation_screen.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

AppMediaItem _song(String id, int i) => AppMediaItem(
      id: id,
      title: 'Song $i with a title long enough to need truncating somewhere',
      artist: 'Composer, Singer One, Singer Two',
      duration: const Duration(minutes: 4),
      sourceType: MediaSourceType.youtube,
    );

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  late MusicPlayerProvider provider;
  final storage = StorageService();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pulse_flow_');
    Hive.init(dir.path);
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
    for (var i = 0; i < 6; i++) {
      await storage.addToHistory(_song('h$i', i));
    }
    await storage.toggleFavorite(_song('fav', 99));
    provider = MusicPlayerProvider(CustomAudioHandler(), storage);
  });

  /// Seeded inside the test zone; a future made outside it never delivers.
  void seedHome() {
    final yt = YoutubeService();
    yt.searchRetryDelay = Duration.zero;
    for (final section in [
      for (final l in [...homeLanguages, null]) ...homeSectionsFor(l),
      ...provider.madeForYouSections,
    ]) {
      final queries = section.style == HomeSectionStyle.rows
          ? [section.query]
          : section.cards.map((c) => c.query);
      for (final q in queries) {
        yt.seedSearch(q, [for (var i = 0; i < 9; i++) _song('$q#$i', i)]);
      }
    }
  }

  Future<void> launch(WidgetTester tester, ThemeMode mode) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    seedHome();
    await tester.pumpWidget(
      ChangeNotifierProvider<MusicPlayerProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const MainNavigationScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Let real async work (plugin calls failing, Hive) settle, then pump.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> tabTo(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await settle(tester);
  }

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('every tab renders ($mode)', (tester) async {
      await launch(tester, mode);
      expect(find.byTooltip('Customize home'), findsOneWidget);

      await tabTo(tester, Icons.folder_outlined);
      await tabTo(tester, Icons.podcasts_outlined);
      await tabTo(tester, Icons.library_music_outlined);
      for (final (i, tab) in ['Favorites', 'History', 'Playlists', 'Downloads'].indexed) {
        await tester.tap(find.descendant(
            of: find.byType(TabBar), matching: find.text(tab)));
        await settle(tester);
        final controller = DefaultTabController.maybeOf(
                tester.element(find.byType(TabBar))) ??
            tester.widget<TabBar>(find.byType(TabBar)).controller!;
        expect(controller.index, i, reason: tab);
      }
      await tabTo(tester, Icons.explore_outlined);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search and settings open and close', (tester) async {
    await launch(tester, ThemeMode.dark);

    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
    expect(find.text('Songs, artists, albums...'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    for (final label in ['Theme', 'App icon', 'Audio quality', 'Home language']) {
      await tester.tap(find.text(label));
      await settle(tester);
      // Close the option sheet without choosing.
      await tester.tapAt(const Offset(200, 60));
      await settle(tester);
    }
    await tester.pageBack();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('play a song, open Now Playing, its sheets, and come back',
      (tester) async {
    await launch(tester, ThemeMode.light);

    // First row of the first section.
    final first = find.text('Song 0 with a title long enough to need '
        'truncating somewhere');
    await tester.tap(first.first);
    await settle(tester);
    expect(provider.currentTrack, isNotNull);

    // The mini player shows the track; open Now Playing from it.
    await tester.tap(find.text(provider.currentTrack!.title).last);
    await settle(tester);
    expect(find.byTooltip('Sleep timer'), findsOneWidget);

    for (final icon in [Icons.shuffle_rounded, Icons.repeat_rounded]) {
      await tester.tap(find.byIcon(icon));
      await settle(tester);
    }
    // Lyrics panel (no network: falls back to the "not available" text).
    await tester.tap(find.byIcon(Icons.lyrics));
    await settle(tester);

    await tester.tap(find.byTooltip('Sleep timer'));
    await settle(tester);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.queue_music_rounded).last);
    await settle(tester);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await settle(tester);
    expect(find.byTooltip('Customize home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('track menu and create-playlist dialog', (tester) async {
    await launch(tester, ThemeMode.dark);
    await tester.tap(find.byTooltip('More').first);
    await settle(tester);
    for (final item in ['Play next', 'Add to queue', 'Add to playlist', 'Download']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('Add to queue'));
    await settle(tester);

    await tabTo(tester, Icons.library_music_outlined);
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('Playlists')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
