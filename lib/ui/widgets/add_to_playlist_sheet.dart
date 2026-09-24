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
    backgroundColor: context.colors.surface,
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
                leading: Icon(Icons.add_rounded, color: context.colors.accent),
                title: const Text('New playlist'),
                onTap: () async {
                  final name = await promptForPlaylistName(sheetContext);
                  if (name == null || name.isEmpty) return;
                  final playlist = await provider.createPlaylist(name);
                  await provider.addToPlaylist(playlist.id, item);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  _confirm(messenger, 'Added to "$name"');
                },
              ),
              if (playlists.isNotEmpty) Divider(color: context.colors.mist.withValues(alpha: 0.10)),
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
                        color: already ? context.colors.mist.withValues(alpha: 0.30) : context.colors.accent,
                      ),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: already ? context.colors.mist.withValues(alpha: 0.38) : context.colors.mist,
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
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: context.colors.mist),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: context.colors.mist.withValues(alpha: 0.38)),
        ),
        onSubmitted: (value) =>
            Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('Cancel', style: TextStyle(color: context.colors.mist.withValues(alpha: 0.54))),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text('Save', style: TextStyle(color: context.colors.accent)),
        ),
      ],
    ),
  );
  Future.delayed(const Duration(milliseconds: 300), () {
    controller.dispose();
  });
  return result;
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
