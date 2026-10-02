import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';
import 'track_tile.dart';

/// A song list with multi-select: long-press a song to start selecting, tap
/// to add or remove more, then play, queue or add them all to a playlist in
/// one go. Back (or ✕) leaves selection.
class SelectableTrackList extends StatefulWidget {
  final List<AppMediaItem> songs;

  /// Shown above the songs while not selecting (e.g. Play all / Shuffle).
  final Widget? header;

  /// Set where songs can be deleted (Downloads): a delete button on the
  /// selection bar (after a confirmation), and swipe left on a song.
  final Future<void> Function(List<AppMediaItem> songs)? onDelete;

  const SelectableTrackList({
    super.key,
    required this.songs,
    this.header,
    this.onDelete,
  });

  @override
  State<SelectableTrackList> createState() => _SelectableTrackListState();
}

class _SelectableTrackListState extends State<SelectableTrackList> {
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  /// In list order, and only songs still shown (a search may hide some).
  List<AppMediaItem> get _chosen =>
      widget.songs.where((s) => _selected.contains(s.id)).toList();

  void _toggle(AppMediaItem song) => setState(() {
    if (!_selected.remove(song.id)) _selected.add(song.id);
  });

  void _clear() => setState(_selected.clear);

  Future<void> _delete(List<AppMediaItem> chosen) async {
    if (chosen.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final n = chosen.length;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(n == 1 ? 'Delete this download?' : 'Delete $n downloads?'),
        content: const Text(
          'The files are removed from this device. You can download them '
          'again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.onDelete!(chosen);
    if (!mounted) return;
    _clear();
    showCompactSnack(
      messenger,
      'Deleted $n ${n == 1 ? 'download' : 'downloads'}',
      icon: Icons.delete_outline_rounded,
    );
  }

  void _done(String message) {
    final messenger = ScaffoldMessenger.of(context);
    _clear();
    showCompactSnack(messenger, message, icon: Icons.queue_music_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    final chosen = _chosen;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clear();
      },
      child: Column(
        children: [
          if (_selecting)
            _SelectionBar(
              count: chosen.length,
              allSelected: chosen.length == songs.length,
              onClose: _clear,
              onSelectAll: () => setState(() {
                if (chosen.length == songs.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(songs.map((s) => s.id));
                }
              }),
              onPlay: () {
                if (chosen.isEmpty) return; // all hidden by a search
                context.read<MusicPlayerProvider>().playTrack(
                  chosen.first,
                  playlist: chosen,
                );
                _clear();
              },
              onPlayNext: () {
                context.read<MusicPlayerProvider>().playNextAll(chosen);
                _done('Playing next: ${chosen.length} songs');
              },
              onQueue: () {
                context.read<MusicPlayerProvider>().addAllToQueue(chosen);
                _done('Added ${chosen.length} songs to the queue');
              },
              onAddToPlaylist: () {
                showAddToPlaylistSheet(context, chosen);
                _clear();
              },
              onDelete: widget.onDelete == null ? null : () => _delete(chosen),
            )
          else
            ?widget.header,
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 110),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                final tile = TrackTile(
                  item: song,
                  playlist: songs,
                  selected: _selecting ? _selected.contains(song.id) : null,
                  onTap: _selecting ? () => _toggle(song) : null,
                  onLongPress: () => _toggle(song),
                );
                final onDelete = widget.onDelete;
                if (onDelete == null || _selecting) return tile;
                return Dismissible(
                  key: ValueKey('delete_${song.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 32),
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                  onDismissed: (_) => onDelete([song]),
                  child: tile,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onPlay;
  final VoidCallback onPlayNext;
  final VoidCallback onQueue;
  final VoidCallback onAddToPlaylist;
  final VoidCallback? onDelete;

  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onSelectAll,
    required this.onPlay,
    required this.onPlayNext,
    required this.onQueue,
    required this.onAddToPlaylist,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return Material(
      color: AppTheme.primary.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: allSelected ? 'Select none' : 'Select all',
              icon: Icon(
                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                color: accent,
              ),
              onPressed: onSelectAll,
            ),
            IconButton(
              tooltip: 'Play selected',
              icon: Icon(Icons.play_arrow_rounded, color: accent),
              onPressed: onPlay,
            ),
            IconButton(
              tooltip: 'Play next',
              icon: Icon(Icons.playlist_play_rounded, color: accent),
              onPressed: onPlayNext,
            ),
            IconButton(
              tooltip: 'Add to queue',
              icon: Icon(Icons.queue_music_rounded, color: accent),
              onPressed: onQueue,
            ),
            IconButton(
              tooltip: 'Add to playlist',
              icon: Icon(Icons.playlist_add_rounded, color: accent),
              onPressed: onAddToPlaylist,
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
