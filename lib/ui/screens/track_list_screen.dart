import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

/// The songs behind a home-page playlist card, an album or a playlist.
class TrackListScreen extends StatefulWidget {
  final String title;

  /// A search (home cards) — or give [load] instead.
  final String query;
  final Future<List<AppMediaItem>> Function()? load;

  const TrackListScreen({
    super.key,
    required this.title,
    this.query = '',
    this.load,
  });

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  late Future<List<AppMediaItem>> _tracks = _fetch();

  Future<List<AppMediaItem>> _fetch() =>
      (widget.load?.call() ?? YoutubeService().cachedSearch(widget.query))
          .catchError((Object _) => <AppMediaItem>[]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      // Pushed over the tabs, so it needs its own mini player.
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: FutureBuilder<List<AppMediaItem>>(
        future: _tracks,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SpinKitDoubleBounce(color: AppTheme.primary, size: 50),
            );
          }
          final tracks = snapshot.data ?? const <AppMediaItem>[];
          if (tracks.isEmpty) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _tracks = _fetch()),
                child: const Text("Couldn't load these songs. Tap to retry."),
              ),
            );
          }
          return ListView.builder(
            itemCount: tracks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play all'),
                        onPressed: () => context
                            .read<MusicPlayerProvider>()
                            .playTrack(tracks.first, playlist: tracks),
                      ),
                      const Spacer(),
                      // The whole playlist, for offline.
                      DownloadAllButton(items: tracks),
                    ],
                  ),
                );
              }
              return TrackTile(item: tracks[index - 1], playlist: tracks);
            },
          );
        },
      ),
    );
  }
}
