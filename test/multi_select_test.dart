// Local songs: long-press starts selecting, taps add more, and the bar acts
// on all of them at once.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/providers/music_player_provider.dart';
import 'package:music_player/services/audio_handler.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:music_player/ui/widgets/download_playlist_sheet.dart';
import 'package:music_player/ui/widgets/selectable_track_list.dart';
import 'package:provider/provider.dart';

AppMediaItem _song(int i) => AppMediaItem(
    id: '$i', title: 'Song $i', artist: 'Me', sourceType: MediaSourceType.local);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  late MusicPlayerProvider provider;
  final songs = [for (var i = 0; i < 5; i++) _song(i)];

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_multi_')).path);
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

  test('adding many to a playlist skips ones already there', () async {
    final playlist = await provider.createPlaylist('Mix');
    await provider.addToPlaylist(playlist.id, songs[1]);
    expect(await provider.addAllToPlaylist(playlist.id, songs.take(3).toList()),
        2);
    expect(provider.getPlaylist(playlist.id)!.items.map((s) => s.id),
        ['1', '0', '2']);
  });

  testWidgets('long-press selects; the bar queues every selected song',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<MusicPlayerProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SelectableTrackList(
            songs: songs,
            header: const Text('Header'),
          ),
        ),
      ),
    ));
    expect(find.text('Header'), findsOneWidget);

    await tester.longPress(find.text('Song 3'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Header'), findsNothing);

    await tester.tap(find.text('Song 1')); // tap now selects, not plays
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(provider.currentTrack, isNull);

    await tester.tap(find.byTooltip('Add to queue'));
    await tester.pump();
    // In list order, not tap order.
    expect(provider.queue.map((s) => s.id), ['1', '3']);
    expect(find.text('Header'), findsOneWidget); // selection ended

    await tester.longPress(find.text('Song 0'));
    await tester.pump();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pump();
    expect(find.text('5 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();
    expect(find.text('Header'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // snackbar timers
  });

  Widget host(Widget child) => ChangeNotifierProvider<MusicPlayerProvider>.value(
        value: provider,
        child: MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: child)),
      );

  testWidgets('downloads: pick several, confirm, all deleted', (tester) async {
    List<AppMediaItem>? deleted;
    await tester.pumpWidget(host(SelectableTrackList(
      songs: songs,
      onDelete: (chosen) async => deleted = chosen,
    )));
    await tester.longPress(find.text('Song 0'));
    await tester.pump();
    await tester.tap(find.text('Song 4'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 downloads?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted!.map((s) => s.id), ['0', '4']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('download sheet: untick songs, rename, get the rest',
      (tester) async {
    final online = [
      for (var i = 0; i < 4; i++)
        AppMediaItem(
            id: 'o$i',
            title: 'Online $i',
            artist: 'A',
            sourceType: MediaSourceType.saavn),
    ];
    (String, List<AppMediaItem>)? result;
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await showDownloadPlaylistSheet(
            context, name: 'Tamil hits', items: online),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 4 songs'), findsOneWidget);
    expect(find.text('Download 4 songs'), findsOneWidget);

    await tester.tap(find.text('Online 1'));
    await tester.tap(find.text('Online 3'));
    await tester.pump();
    expect(find.text('2 of 4 songs'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My mix');
    await tester.tap(find.text('Download 2 songs'));
    await tester.pumpAndSettle();
    expect(result!.$1, 'My mix');
    expect(result!.$2.map((s) => s.id), ['o0', 'o2']);
  });
}
