import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/playlist.dart';
import 'package:music_player/ui/theme/app_theme.dart';
import 'package:music_player/ui/widgets/share_playlist_sheet.dart';

void main() {
  final sampleItems = [
    AppMediaItem(
      id: 'song-1',
      title: 'Midnight City',
      artist: 'M83',
      streamUrl: 'https://cdn.example/1.mp4',
      duration: const Duration(minutes: 4, seconds: 3),
      sourceType: MediaSourceType.saavn,
    ),
    AppMediaItem(
      id: 'song-2',
      title: 'Starboy',
      artist: 'The Weeknd',
      streamUrl: 'https://cdn.example/2.mp4',
      duration: const Duration(minutes: 3, seconds: 50),
      sourceType: MediaSourceType.saavn,
    ),
  ];

  final samplePlaylist = Playlist(
    id: 'p-1',
    name: 'Synthwave Nights',
    items: sampleItems,
  );

  testWidgets('SharePlaylistSheet displays options and playlist title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSharePlaylistSheet(context, samplePlaylist),
              child: const Text('Open Share'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Share'));
    await tester.pumpAndSettle();

    expect(find.text('Share Playlist'), findsOneWidget);
    expect(find.text('Synthwave Nights'), findsOneWidget);
    expect(find.text('Share Playlist File'), findsOneWidget);
    expect(find.text('Copy Share Link'), findsOneWidget);
    expect(find.text('Share as Message'), findsOneWidget);
  });

  testWidgets('SharePlaylistSheet displays large playlist warning for >100 tracks', (tester) async {
    final largeItems = List.generate(
      105,
      (i) => AppMediaItem(
        id: 'track-$i',
        title: 'Track $i',
        artist: 'Artist $i',
        streamUrl: 'https://cdn.example/$i.mp4',
        sourceType: MediaSourceType.saavn,
      ),
    );
    final largePlaylist = Playlist(id: 'large', name: 'Massive', items: largeItems);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSharePlaylistSheet(context, largePlaylist),
              child: const Text('Open Large'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Large'));
    await tester.pumpAndSettle();

    expect(
      find.text('Large playlist (>100 songs). Sharing as a file is recommended.'),
      findsOneWidget,
    );
  });
}
