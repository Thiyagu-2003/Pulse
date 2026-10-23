import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item_model.dart';
import '../../models/track_query.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';
import 'track_filter_bar.dart';
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

  /// Custom bottom padding for the scrollable list. Defaults to 110 (to float
  /// cleanly above main navigation's floating mini player).
  final double? bottomPadding;

  /// A search field above the list (a collection or folder screen). Tapping
  /// a match still queues the whole list, from that song.
  final bool searchable;

  const SelectableTrackList({
    super.key,
    required this.songs,
    this.header,
    this.onDelete,
    this.bottomPadding,
    this.searchable = false,
  });

  @override
  State<SelectableTrackList> createState() => _SelectableTrackListState();
}

class _SelectableTrackListState extends State<SelectableTrackList> {
  final Set<String> _selected = {};
  String _query = '';

  bool get _selecting => _selected.isNotEmpty;

  /// The songs shown: all of them, or the matches to [_query].
  List<AppMediaItem> get _shown =>
      widget.searchable ? filterTracks(widget.songs, _query) : widget.songs;

  /// In list order, and only songs still shown (a search may hide some).
  List<AppMediaItem> get _chosen =>
      _shown.where((s) => _selected.contains(s.id)).toList();

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
    final songs = _shown;
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
          if (widget.searchable && !_selecting)
            TrackFilterBar(
              query: _query,
              onQueryChanged: (q) => setState(() => _query = q),
            ),
          if (widget.searchable && songs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nothing matches your search.',
                style: TextStyle(
                  color: context.colors.mist.withValues(alpha: 0.54),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: widget.bottomPadding ?? 110),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                final tile = TrackTile(
                  item: song,
                  playlist: widget.songs,
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
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.lift,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Close button, Count, and Select All / Deselect All button
          Padding(
            padding: const EdgeInsets.only(
              left: 6,
              right: 10,
              top: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: onClose,
                ),
                const SizedBox(width: 4),
                Text(
                  '$count selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primarySoft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onSelectAll,
                  icon: Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    size: 18,
                  ),
                  label: Text(
                    allSelected ? 'Deselect all' : 'Select all',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.mist.withValues(alpha: 0.08)),
          // Actions Row: Each button has explicit text, relevant icon, and distinct styling
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _SelectionActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  tooltip: 'Play selected songs',
                  isPrimary: true,
                  onPressed: onPlay,
                ),
                const SizedBox(width: 8),
                _SelectionActionButton(
                  icon: Icons.playlist_play_rounded,
                  label: 'Play next',
                  tooltip: 'Play selected songs next',
                  onPressed: onPlayNext,
                ),
                const SizedBox(width: 8),
                _SelectionActionButton(
                  icon: Icons.queue_music_rounded,
                  label: 'Add to queue',
                  tooltip: 'Add selected songs to queue',
                  onPressed: onQueue,
                ),
                const SizedBox(width: 8),
                _SelectionActionButton(
                  icon: Icons.playlist_add_rounded,
                  label: 'Add to playlist',
                  tooltip: 'Add selected songs to playlist',
                  onPressed: onAddToPlaylist,
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 8),
                  _SelectionActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    tooltip: 'Delete selected songs',
                    isDestructive: true,
                    onPressed: onDelete!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isDestructive;

  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color bgColor;
    final Color fgColor;
    final Border? border;

    if (isPrimary) {
      bgColor = AppTheme.primary;
      fgColor = Colors.white;
      border = null;
    } else if (isDestructive) {
      bgColor = Colors.redAccent.withValues(alpha: 0.12);
      fgColor = Colors.redAccent;
      border = Border.all(
        color: Colors.redAccent.withValues(alpha: 0.35),
        width: 1,
      );
    } else {
      bgColor = colors.surface;
      fgColor = colors.mist;
      border = Border.all(color: colors.mist.withValues(alpha: 0.10), width: 1);
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: isPrimary
                      ? Colors.white
                      : isDestructive
                      ? Colors.redAccent
                      : AppTheme.primarySoft,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w600,
                    color: fgColor,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
