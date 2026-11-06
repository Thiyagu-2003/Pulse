import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item_model.dart';
import '../../models/playlist.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import 'local_artwork.dart';

/// Displays the import preview sheet for a shared playlist.
///
/// Shows editable playlist name, conflict resolution options when a playlist
/// with the same name exists, and a scrollable preview of incoming tracks.
/// Returns the imported [Playlist] on success, or `null` if cancelled.
Future<Playlist?> showImportPlaylistSheet(
  BuildContext context, {
  required String initialName,
  required List<AppMediaItem> items,
}) {
  return showModalBottomSheet<Playlist?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _ImportPlaylistSheet(
      initialName: initialName,
      items: items,
    ),
  );
}

class _ImportPlaylistSheet extends StatefulWidget {
  final String initialName;
  final List<AppMediaItem> items;

  const _ImportPlaylistSheet({
    required this.initialName,
    required this.items,
  });

  @override
  State<_ImportPlaylistSheet> createState() => _ImportPlaylistSheetState();
}

class _ImportPlaylistSheetState extends State<_ImportPlaylistSheet> {
  late final TextEditingController _nameController;
  PlaylistConflictResolution _resolution = PlaylistConflictResolution.keepBoth;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatTotalDuration(List<AppMediaItem> items) {
    var totalSeconds = 0;
    for (final item in items) {
      if (item.duration != null) {
        totalSeconds += item.duration!.inSeconds;
      }
    }
    if (totalSeconds <= 0) return '0 min';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes min';
  }

  String _formatTrackDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final currentName = _nameController.text.trim();
    final hasConflict = currentName.isNotEmpty &&
        provider.playlists.any(
          (p) => p.name.trim().toLowerCase() == currentName.toLowerCase(),
        );

    final totalDuration = _formatTotalDuration(widget.items);
    final subtitleText = '${widget.items.length} songs • $totalDuration';

    return Padding(
      // Keep sheet responsive when virtual keyboard is open
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.mist.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Import Playlist',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Playlist Name Input & Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Playlist Name',
                    prefixIcon: const Icon(Icons.playlist_play_rounded),
                    suffixIcon: _nameController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _nameController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: context.colors.lift.withValues(alpha: 0.25),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: context.colors.mist.withValues(alpha: 0.12),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: context.colors.mist.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppTheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.mist.withValues(alpha: 0.65),
                  ),
                ),
              ),
              // Conflict resolution section
              if (hasConflict) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.lift.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: context.colors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A playlist named "$currentName" already exists',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.mist,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<PlaylistConflictResolution>(
                            segments: const [
                              ButtonSegment(
                                value: PlaylistConflictResolution.keepBoth,
                                label: Text(
                                  'Keep Both',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: PlaylistConflictResolution.replace,
                                label: Text(
                                  'Replace',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: PlaylistConflictResolution.merge,
                                label: Text(
                                  'Merge',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            selected: {_resolution},
                            showSelectedIcon: false,
                            onSelectionChanged: (selected) {
                              setState(() {
                                _resolution = selected.first;
                              });
                            },
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _resolution == PlaylistConflictResolution.keepBoth
                              ? '• Keep Both: creates "$currentName (1)"'
                              : _resolution == PlaylistConflictResolution.replace
                                  ? '• Replace: overwrites tracks in existing playlist'
                                  : '• Merge: adds new songs without duplicates',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.mist.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Track Preview header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  'Preview (${widget.items.length} tracks)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.mist.withValues(alpha: 0.60),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Scrollable Track Preview list
              Flexible(
                child: widget.items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No tracks to preview',
                            style: TextStyle(
                              color: context.colors.mist.withValues(alpha: 0.50),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        itemCount: widget.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          return _buildTrackPreviewTile(context, item);
                        },
                      ),
              ),
              // Bottom Action Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor:
                              context.colors.mist.withValues(alpha: 0.70),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: currentName.isEmpty || _isImporting
                            ? null
                            : () => _handleImport(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.colors.accent,
                          foregroundColor: AppTheme.background,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isImporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.background,
                                ),
                              )
                            : const Text(
                                'Import Playlist',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackPreviewTile(BuildContext context, AppMediaItem item) {
    Widget artwork;
    if (item.artUri != null && item.artUri!.startsWith('http')) {
      artwork = CachedNetworkImage(
        imageUrl: item.artUri!,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        placeholder: (_, _) => _buildArtworkPlaceholder(context),
        errorWidget: (_, _, _) => _buildArtworkPlaceholder(context),
      );
    } else if (item.sourceType == MediaSourceType.local) {
      artwork = LocalArtwork(
        item: item,
        width: 44,
        height: 44,
        fallback: _buildArtworkPlaceholder(context),
      );
    } else {
      artwork = _buildArtworkPlaceholder(context);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.lift.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: artwork,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.mist,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.mist.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
          if (item.duration != null && item.duration!.inSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                _formatTrackDuration(item.duration!),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.mist.withValues(alpha: 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArtworkPlaceholder(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.mist.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: AppTheme.primary,
        size: 20,
      ),
    );
  }

  Future<void> _handleImport(BuildContext sheetContext) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final provider = sheetContext.read<MusicPlayerProvider>();
      final hasConflict = provider.playlists.any(
        (p) => p.name.trim().toLowerCase() == name.toLowerCase(),
      );

      final imported = await provider.importPlaylistWithResolution(
        name: name,
        items: widget.items,
        resolution:
            hasConflict ? _resolution : PlaylistConflictResolution.keepBoth,
      );

      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop(imported);
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(
            content: Text(
              'Imported "${imported.name}" (${imported.length} songs)',
            ),
          ),
        );
      }
    } catch (e) {
      if (sheetContext.mounted) {
        setState(() {
          _isImporting = false;
        });
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text('Failed to import playlist: $e')),
        );
      }
    }
  }
}
