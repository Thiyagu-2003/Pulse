import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/services/youtube_service.dart';
import 'package:music_player/ui/screens/online_search_screen.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  late MusicPlayerProvider provider;
  final yt = YoutubeService();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pulse_suggest_');
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
    provider = MusicPlayerProvider(CustomAudioHandler(), StorageService());
  });

  tearDown(() {
    yt.debugSuggestionsOverride = null;
    yt.clearSearchCache();
  });

  testWidgets('typing shows suggestions and songs; ↖ refines', (tester) async {
    final asked = <String>[];
    yt.debugSuggestionsOverride = (q) async {
      asked.add(q);
      return ['$q ravichander', '$q hits', '$q songs'];
    };
    yt.seedSearch('anirudh', [
      for (var i = 0; i < 6; i++)
        AppMediaItem(
          id: 's$i',
          title: 'Preview song $i',
          artist: 'Anirudh',
          duration: const Duration(minutes: 4),
          sourceType: MediaSourceType.youtube,
        ),
    ]);

    await tester.pumpWidget(ChangeNotifierProvider<MusicPlayerProvider>.value(
      value: provider,
      child: MaterialApp(
          theme: AppTheme.darkTheme, home: const OnlineSearchScreen()),
    ));

    // Fast typing: only the pause at the end asks for suggestions.
    for (final partial in ['a', 'an', 'ani', 'anir', 'anirudh']) {
      await tester.enterText(find.byType(TextField), partial);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(asked, ['anirudh']);
    expect(find.text('anirudh ravichander'), findsOneWidget);
    expect(find.text('Search for "anirudh"'), findsOneWidget);

    // Songs arrive after the longer pause: top 4 only.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Preview song 3'), findsOneWidget);
    expect(find.text('Preview song 4'), findsNothing);

    // ↖ puts the suggestion in the box and asks again.
    await tester.tap(find.byTooltip('Edit this search').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'anirudh ravichander ',
    );
    expect(asked.last, 'anirudh ravichander');

    // Clearing the box goes back to recent searches.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Songs'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
