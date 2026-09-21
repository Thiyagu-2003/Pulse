import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_folder.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

/// The tracks inside one device folder — Music, Recordings, Call recordings.
class FolderSongsScreen extends StatelessWidget {
  final MediaFolder folder;

  const FolderSongsScreen({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              '${folder.length} ${folder.length == 1 ? 'track' : 'tracks'}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent),
            tooltip: 'Play all',
            onPressed: folder.items.isEmpty
                ? null
                : () => context.read<MusicPlayerProvider>().playTrack(
                      folder.items.first,
                      playlist: folder.items,
                    ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: folder.items.length,
        itemBuilder: (context, index) => TrackTile(
          item: folder.items[index],
          // Queue only this folder, so a call recording can't run on into
          // the next one just because it happened to be next on disk.
          playlist: folder.items,
        ),
      ),
    );
  }
}
