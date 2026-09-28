import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';

/// Pick a playlist to add [items] to (one song or a multi-selection), or
/// create one on the spot. Songs already in the playlist are skipped.
void showAddToPlaylistSheet(BuildContext context, List<AppMediaItem> items) {
  final what = items.length == 1 ? 'Added' : 'Added ${items.length} songs';
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  items.length == 1
                      ? 'Add to playlist'
                      : 'Add ${items.length} songs to playlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.add_rounded,
                  color: sheetContext.colors.accent,
                ),
                title: const Text('New playlist'),
                onTap: () async {
                  final name = await promptForPlaylistName(sheetContext);
                  if (name == null || name.isEmpty) return;
                  final playlist = await provider.createPlaylist(name);
                  await provider.addAllToPlaylist(playlist.id, items);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  _confirm(messenger, '$what to "$name"');
                },
              ),
              if (playlists.isNotEmpty)
                Divider(
                  color: sheetContext.colors.mist.withValues(alpha: 0.10),
                ),
              // Bounded so a long list scrolls instead of overflowing.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (_, index) {
                    final playlist = playlists[index];
                    final already = items.every(
                      (item) => playlist.contains(item.id),
                    );
                    return ListTile(
                      leading: Icon(
                        already
                            ? Icons.playlist_add_check_rounded
                            : Icons.queue_music_rounded,
                        color: already
                            ? sheetContext.colors.mist.withValues(alpha: 0.30)
                            : sheetContext.colors.accent,
                      ),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: already
                              ? sheetContext.colors.mist.withValues(alpha: 0.38)
                              : sheetContext.colors.mist,
                        ),
                      ),
                      subtitle: Text(
                        already
                            ? (items.length == 1
                                  ? 'Already in this playlist'
                                  : 'All already in this playlist')
                            : '${playlist.length} tracks',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: already
                          ? null
                          : () async {
                              final added = await provider.addAllToPlaylist(
                                playlist.id,
                                items,
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              _confirm(
                                messenger,
                                items.length == 1 || added == items.length
                                    ? '$what to "${playlist.name}"'
                                    : 'Added $added to "${playlist.name}" '
                                          '(${items.length - added} already there)',
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
      backgroundColor: dialogContext.colors.surface,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: dialogContext.colors.mist),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(
            color: dialogContext.colors.mist.withValues(alpha: 0.38),
          ),
        ),
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: dialogContext.colors.mist.withValues(alpha: 0.54),
            ),
          ),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(
            'Save',
            style: TextStyle(color: dialogContext.colors.accent),
          ),
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
