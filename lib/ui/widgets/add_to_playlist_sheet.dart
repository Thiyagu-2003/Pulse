import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';

/// Pick a playlist to add [item] to, or create one on the spot.
void showAddToPlaylistSheet(BuildContext context, AppMediaItem item) {
  final provider = context.read<MusicPlayerProvider>();
  // Captured up front: every confirmation below happens after an await, and
  // reaching back through a BuildContext at that point is unsound.
  final messenger = ScaffoldMessenger.of(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Consumer<MusicPlayerProvider>(
        builder: (_, watched, _) {
          final playlists = watched.getPlaylists();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Add to playlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_rounded, color: AppTheme.accent),
                title: const Text('New playlist'),
                onTap: () async {
                  final name = await promptForPlaylistName(context);
                  if (name == null || name.isEmpty) return;
                  final playlist = await provider.createPlaylist(name);
                  await provider.addToPlaylist(playlist.id, item);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  _confirm(messenger, 'Added to "$name"');
                },
              ),
              if (playlists.isNotEmpty) const Divider(color: Colors.white10),
              // Bounded so a long list scrolls instead of overflowing.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (_, index) {
                    final playlist = playlists[index];
                    final already = playlist.contains(item.id);
                    return ListTile(
                      leading: Icon(
                        already
                            ? Icons.playlist_add_check_rounded
                            : Icons.queue_music_rounded,
                        color: already ? Colors.white30 : AppTheme.accent,
                      ),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: already ? Colors.white38 : Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        already
                            ? 'Already in this playlist'
                            : '${playlist.length} tracks',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: already
                          ? null
                          : () async {
                              await provider.addToPlaylist(playlist.id, item);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              _confirm(
                                messenger,
                                'Added to "${playlist.name}"',
                              );
                            },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Shared by the sheet above and the Playlists tab's create/rename actions.
Future<String?> promptForPlaylistName(
  BuildContext context, {
  String initial = '',
  String title = 'New playlist',
}) {
  final controller = TextEditingController(text: initial);
  // Disposed when the dialog closes — otherwise every create/rename leaks one.
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: Colors.white38),
        ),
        onSubmitted: (value) =>
            Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Save', style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

void _confirm(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
