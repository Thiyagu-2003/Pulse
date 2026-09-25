import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/home_sections.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/network_status.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';
import 'package:music_player/ui/screens/customize_home_screen.dart';
import 'package:music_player/ui/screens/online_music_screen.dart';
import 'package:music_player/ui/screens/settings_screen.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

AppMediaItem _song(String id, {String? title}) => AppMediaItem(
      id: id,
      title: title ?? 'A fairly long song title that has to truncate $id',
      artist: 'Some Composer, Another Singer, A Third Person',
      duration: const Duration(minutes: 4),
      sourceType: MediaSourceType.youtube,
    );

void main() {
  // No network in tests; fall back to the default font quietly.
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory dir;
  late MusicPlayerProvider provider;
  final storage = StorageService();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse_ui_');
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

    provider = MusicPlayerProvider(CustomAudioHandler(), storage);
  });

  tearDown(() async {
    YoutubeService().clearSearchCache();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester, Widget screen,
      {ThemeData? theme}) async {
    // Seeded here, not in setUp: a future completed outside the test's
    // fake-async zone never delivers inside it, leaving rows loading.
    final yt = YoutubeService();
    for (final section in [
      for (final l in [...homeLanguages, null]) ...homeSectionsFor(l),
      ...provider.madeForYouSections,
    ]) {
      final queries = section.style == HomeSectionStyle.rows
          ? [section.query]
          : section.cards.map((c) => c.query);
      for (final q in queries) {
        yt.seedSearch(q, [for (var i = 0; i < 9; i++) _song('$q#$i')]);
      }
    }
    tester.view.physicalSize = const Size(1080, 2400); // common phone
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<MusicPlayerProvider>.value(
        value: provider,
        child: MaterialApp(theme: theme ?? AppTheme.darkTheme, home: screen),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('home lays out top to bottom without overflowing',
      (tester) async {
    // Real disk I/O never completes inside the fake-async test zone.
    await tester.runAsync(() async {
      for (var i = 0; i < 8; i++) {
        await storage.addToHistory(_song('h$i', title: 'Recent $i'));
      }
    });
    await pumpHome(tester, const OnlineMusicScreen(prefetch: false));

    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.text('Recent 0'), findsOneWidget); // quick picks
    expect(find.text('Tamil'), findsOneWidget); // language chips
    expect(find.text('Trending in Tamil'), findsOneWidget);
    // Real rows, not loading skeletons, with the ⋮ menu on each.
    final firstSong = 'A fairly long song title that has to truncate '
        '${homeSectionsFor('Tamil').first.query}#0';
    expect(find.text(firstSong), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);

    // Scroll through every section; any overflow fails the test.
    for (final title in ['Tamil love songs', '90s Tamil', 'Top playlists']) {
      await tester.scrollUntilVisible(find.text(title), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
    }
    expect(find.text('Tamil romance'), findsOneWidget);
  });

  testWidgets('home renders in the light theme on a light background',
      (tester) async {
    await pumpHome(tester, const OnlineMusicScreen(prefetch: false),
        theme: AppTheme.lightTheme);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final bg = scaffold.backgroundColor ??
        Theme.of(tester.element(find.byType(Scaffold).first))
            .scaffoldBackgroundColor;
    expect(bg.computeLuminance(), greaterThan(0.8));
    for (final title in ['Tamil love songs', 'Top playlists']) {
      await tester.scrollUntilVisible(find.text(title), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
    }
  });

  testWidgets('the home page follows the saved layout', (tester) async {
    await tester.runAsync(() => provider.setHomeLayout(const HomeLayout(
          order: ['top_playlists', 'custom_1'],
          hidden: {'trending'},
          custom: [('custom_1', 'Yuvan hits')],
        )));
    YoutubeService().seedSearch('playlist:Yuvan hits',
        [for (var i = 0; i < 5; i++) _song('yuvan$i')]);
    await pumpHome(tester, const OnlineMusicScreen(prefetch: false));

    expect(find.text('Trending in Tamil'), findsNothing); // hidden
    final top = tester.getTopLeft(find.text('Top playlists')).dy;
    final mine = tester.getTopLeft(find.text('Yuvan hits')).dy;
    expect(top, lessThan(mine));
    // The standard sections follow, further down.
    await tester.scrollUntilVisible(find.text('Tamil hits'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(find.text('Tamil hits')).dy,
        greaterThan(tester.getTopLeft(find.text('Yuvan hits')).dy));

    await tester.runAsync(() => provider.setHomeLayout(HomeLayout.standard));
    await tester.pump();
  });

  testWidgets('the editor lists every section, hidden ones too',
      (tester) async {
    await tester.runAsync(() => provider.setHomeLayout(
        const HomeLayout(hidden: {'recent'})));
    await pumpHome(tester, const CustomizeHomeScreen());
    expect(find.text('Recently played'), findsOneWidget);
    expect(find.text('Trending in Tamil'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.first.value, isFalse); // Recently played, hidden
    expect(find.text('Add section'), findsOneWidget);
    await tester.runAsync(() => provider.setHomeLayout(HomeLayout.standard));
    await tester.pump();
  });

  testWidgets('the header logo follows the app icon setting', (tester) async {
    bool shows(String asset) => tester
        .widgetList<Image>(find.byType(Image))
        .any((i) => i.image is AssetImage && (i.image as AssetImage).assetName == asset);

    await pumpHome(tester, const OnlineMusicScreen(prefetch: false));
    expect(shows('icons/app_icon_light.png'), isTrue);

    await tester.runAsync(() => provider.setDarkLauncherIcon(true));
    await tester.pump();
    expect(shows('icons/app_icon_dark.png'), isTrue);

    await tester.runAsync(() => provider.setDarkLauncherIcon(false));
    await tester.pump();
  });

  testWidgets('offline, the home shows downloads; back online, the rows',
      (tester) async {
    await tester.runAsync(() => storage.saveDownload(
        _song('d1', title: 'Saved song')));
    NetworkStatus.instance.offline.value = true;
    addTearDown(() => NetworkStatus.instance.offline.value = false);
    await pumpHome(tester, const OnlineMusicScreen(prefetch: false));
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('Saved song'), findsOneWidget);
    expect(find.text('Trending in Tamil'), findsNothing);

    NetworkStatus.instance.offline.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("You're offline"), findsNothing);
    expect(find.text('Trending in Tamil'), findsOneWidget);
  });

  testWidgets('picking a language chip switches the sections',
      (tester) async {
    await pumpHome(tester, const OnlineMusicScreen(prefetch: false));
    expect(find.widgetWithText(ChoiceChip, 'Hindi'), findsOneWidget);
    await tester.runAsync(() => provider.setHomeLanguage('Hindi'));
    await tester.pump();
    expect(provider.homeLanguage, 'Hindi');
    expect(find.text('Trending in Hindi'), findsOneWidget);
  });

  testWidgets('settings shows quality, language and history', (tester) async {
    await tester.runAsync(() => storage.addToHistory(_song('x')));
    await pumpHome(tester, const SettingsScreen());
    expect(find.text('Audio quality'), findsOneWidget);
    expect(find.text('Tamil rows on the home screen'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 entry'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('1 entry'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Home language'), -200,
        scrollable: find.byType(Scrollable).first);

    await tester.tap(find.text('Home language'));
    await tester.pump(); // sheet route starts
    await tester.pump(const Duration(seconds: 1)); // and finishes sliding up
    expect(find.text('No language rows'), findsOneWidget);
    // Pick it through the provider: a Hive write started from a tap inside
    // the fake-async zone never finishes, and teardown then hangs on it.
    await tester.runAsync(() => provider.setHomeLanguage(null));
    await tester.pump(const Duration(seconds: 1));
    expect(provider.homeLanguage, isNull);
    expect(find.text('No language rows on the home screen'), findsOneWidget);
  });
}
