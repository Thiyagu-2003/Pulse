import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';
import 'playing_indicator.dart';

class TrackTile extends StatelessWidget {
  final AppMediaItem item;
  final List<AppMediaItem>? playlist;
  final VoidCallback? onTap;

  const TrackTile({super.key, required this.item, this.playlist, this.onTap});

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(context);
    final isPlayingCurrent = playerProvider.currentTrack?.id == item.id;
    final isFav = playerProvider.isFavorite(item.id);

    // Animated so selection glides in when the track changes under you —
    // from the notification, from auto-advance — rather than snapping.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
      decoration: BoxDecoration(
        color: isPlayingCurrent
            ? AppTheme.primary.withValues(alpha: 0.16)
            : context.colors.mist.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPlayingCurrent
              ? AppTheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
        ),
      ),
      // The row's own Material: ListTile paints its tap ripple on the nearest
      // Material, and the decorated container above would hide it — taps
      // gave no visual feedback at all.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          onTap:
              onTap ?? () => playerProvider.playTrack(item, playlist: playlist),
          onLongPress: () => showTrackActions(context, item),
          leading: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item.artUri != null && item.artUri!.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: item.artUri!,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            _buildPlaceholder(context),
                        errorWidget: (context, url, error) =>
                            _buildPlaceholder(context),
                      )
                    : _buildPlaceholder(context),
              ),
              // The pulse sits on the artwork of the track you can hear.
              if (isPlayingCurrent)
                Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: StreamBuilder<PlaybackState>(
                    stream: playerProvider.playbackState,
                    builder: (context, snapshot) => PlayingIndicator(
                      isPlaying: snapshot.data?.playing ?? false,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isPlayingCurrent
                  ? context.colors.accent
                  : context.colors.mist,
            ),
          ),
          subtitle: Row(
            children: [
              _buildSourceBadge(context, item.sourceType),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.mist.withValues(alpha: 0.60),
                  ),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Downloads go through YouTube extraction; a podcast id is a
              // hash of its URL, so that could only ever fail.
              if (item.sourceType.isOnline) DownloadButton(item: item),
              IconButton(
                // Scales up as it fills in, so the tap has a result you can see
                // without moving your eyes to a toast.
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: child,
                  ),
                  child: Icon(
                    isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    key: ValueKey(isFav),
                    color: isFav
                        ? const Color(0xFFFF5C7A)
                        : context.colors.mist.withValues(alpha: 0.35),
                    size: 20,
                  ),
                ),
                tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () => playerProvider.toggleFavorite(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      color: context.colors.mist.withValues(alpha: 0.10),
      child: const Icon(Icons.music_note, color: AppTheme.primary),
    );
  }

  Widget _buildSourceBadge(BuildContext context, MediaSourceType type) {
    final light = Theme.of(context).brightness == Brightness.light;
    Color color;
    String label;
    switch (type) {
      case MediaSourceType.youtube:
      case MediaSourceType.saavn:
        // Violet, not the provider's red — the badge says where the track
        // lives, not which service it came from.
        // The soft violet and bright orange are unreadable on light
        // backgrounds (~2:1); darker shades there.
        color = light ? AppTheme.primary : AppTheme.primarySoft;
        label = type.label;
        break;
      case MediaSourceType.local:
        color = context.colors.accent;
        label = type.label;
        break;
      case MediaSourceType.podcast:
        color = light ? Colors.orange.shade800 : Colors.orangeAccent;
        label = type.label;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Play next / add to queue / add to playlist / download for [item] — the
/// long-press menu on a track tile, and the ⋮ menu on home rows.
void showTrackActions(BuildContext context, AppMediaItem item) {
  final provider = context.read<MusicPlayerProvider>();
  // The row that opened this menu can be rebuilt away while the sheet is
  // up (search suggestions arriving late shift the list). Follow-up actions
  // use the navigator's context, which lives as long as the app, and the
  // sheet styles itself from its own context.
  final rootContext = Navigator.of(context).context;
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.playlist_play_rounded,
              color: sheetContext.colors.accent,
            ),
            title: const Text('Play next'),
            onTap: () {
              final added = provider.playNext(item);
              Navigator.pop(sheetContext);
              _confirm(
                rootContext,
                added
                    ? 'Playing next: ${item.title}'
                    : 'Already playing: ${item.title}',
              );
            },
          ),
          ListTile(
            leading: Icon(
              Icons.queue_music_rounded,
              color: sheetContext.colors.accent,
            ),
            title: const Text('Add to queue'),
            onTap: () {
              final added = provider.addToQueue(item);
              Navigator.pop(sheetContext);
              _confirm(
                rootContext,
                added
                    ? 'Added to queue: ${item.title}'
                    : 'Already playing: ${item.title}',
              );
            },
          ),
          ListTile(
            leading: Icon(
              Icons.playlist_add_rounded,
              color: sheetContext.colors.accent,
            ),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.pop(sheetContext);
              showAddToPlaylistSheet(rootContext, item);
            },
          ),
          if (item.sourceType.isOnline)
            provider.isDownloaded(item.id)
                ? ListTile(
                    leading: Icon(
                      Icons.download_done_rounded,
                      color: sheetContext.colors.accent,
                    ),
                    title: const Text('Remove download'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      removeDownload(rootContext, item);
                    },
                  )
                : ListTile(
                    leading: Icon(
                      Icons.download_rounded,
                      color: sheetContext.colors.accent,
                    ),
                    title: Text(
                      provider.isDownloading(item.id)
                          ? 'Downloading…'
                          : 'Download',
                    ),
                    enabled: !provider.isDownloading(item.id),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      startDownload(rootContext, item);
                    },
                  ),
        ],
      ),
    ),
  );
}

void _confirm(BuildContext context, String message) {
  if (!context.mounted) return;
  showCompactSnack(
    ScaffoldMessenger.of(context),
    message,
    icon: Icons.queue_music_rounded,
  );
}

/// Download [item]. Progress lives in the notification shade; in the app
/// there's only a one-line confirmation, so a long title can't cover the list.
Future<void> startDownload(BuildContext context, AppMediaItem item) async {
  final provider = context.read<MusicPlayerProvider>();
  if (provider.isDownloading(item.id)) return;
  final messenger = ScaffoldMessenger.of(context);
  final path = await provider.downloadTrack(item);
  showCompactSnack(
    messenger,
    path != null
        ? 'Downloaded: ${item.title}'
        : "Couldn't download: ${item.title}",
    icon: path != null
        ? Icons.download_done_rounded
        : Icons.error_outline_rounded,
    error: path == null,
  );
}

Future<void> removeDownload(BuildContext context, AppMediaItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  await context.read<MusicPlayerProvider>().deleteDownload(item);
  showCompactSnack(
    messenger,
    'Removed download: ${item.title}',
    icon: Icons.delete_outline_rounded,
  );
}

/// One line, icon first, gone in two seconds.
void showCompactSnack(
  ScaffoldMessengerState messenger,
  String message, {
  IconData icon = Icons.check_circle_outline_rounded,
  bool error = false,
}) {
  final colors = messenger.context.colors;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 20, color: error ? Colors.white : colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: error ? Colors.redAccent : colors.lift,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// Download / progress / downloaded toggle for one track.
class DownloadButton extends StatelessWidget {
  final AppMediaItem item;
  final double size;
  const DownloadButton({super.key, required this.item, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();

    if (provider.isDownloading(item.id)) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: size - 2,
          height: size - 2,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.colors.accent,
            // Null until the first chunk arrives, so it spins rather than
            // sitting at a dead 0%.
            value: provider.downloadProgress(item.id),
          ),
        ),
      );
    }

    if (provider.isDownloaded(item.id)) {
      return IconButton(
        icon: Icon(
          Icons.download_done_rounded,
          color: context.colors.accent,
          size: size,
        ),
        tooltip: 'Downloaded — tap to remove',
        onPressed: () => removeDownload(context, item),
      );
    }

    return IconButton(
      icon: Icon(
        Icons.download_rounded,
        color: context.colors.mist.withValues(alpha: 0.54),
        size: size,
      ),
      tooltip: 'Download for offline',
      onPressed: () => startDownload(context, item),
    );
  }
}

/// Downloads every online song in [items] that isn't on the phone yet.
/// Hidden when there's nothing left to download.
class DownloadAllButton extends StatefulWidget {
  final List<AppMediaItem> items;
  const DownloadAllButton({super.key, required this.items});

  @override
  State<DownloadAllButton> createState() => _DownloadAllButtonState();
}

class _DownloadAllButtonState extends State<DownloadAllButton> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final missing = provider.notDownloaded(widget.items).length;
    if (_running) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (missing == 0) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Download all ($missing)',
      icon: const Icon(Icons.download_for_offline_outlined),
      onPressed: () async {
        if (_running) return; // a second tap in the same frame
        final messenger = ScaffoldMessenger.of(context);
        setState(() => _running = true);
        final failed = await provider.downloadAll(widget.items);
        if (mounted) setState(() => _running = false);
        showCompactSnack(
          messenger,
          failed == 0
              ? 'Downloaded $missing ${missing == 1 ? 'song' : 'songs'}'
              : "$failed couldn't download — tap again to retry",
          icon: failed == 0
              ? Icons.download_done_rounded
              : Icons.error_outline_rounded,
          error: failed > 0,
        );
      },
    );
  }
}
