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

  const TrackTile({
    super.key,
    required this.item,
    this.playlist,
    this.onTap,
  });

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
            : AppTheme.mist.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPlayingCurrent
              ? AppTheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: onTap ?? () => playerProvider.playTrack(item, playlist: playlist),
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
                      placeholder: (context, url) => _buildPlaceholder(),
                      errorWidget: (context, url, error) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
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
            color: isPlayingCurrent ? AppTheme.accent : Colors.white,
          ),
        ),
        subtitle: Row(
          children: [
            _buildSourceBadge(item.sourceType),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Downloads go through YouTube extraction; a podcast id is a
            // hash of its URL, so that could only ever fail.
            if (item.sourceType == MediaSourceType.youtube)
              DownloadButton(item: item),
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
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(isFav),
                  color: isFav
                      ? const Color(0xFFFF5C7A)
                      : AppTheme.mist.withValues(alpha: 0.35),
                  size: 20,
                ),
              ),
              onPressed: () => playerProvider.toggleFavorite(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: AppTheme.primary),
    );
  }

  Widget _buildSourceBadge(MediaSourceType type) {
    Color color;
    String label;
    switch (type) {
      case MediaSourceType.youtube:
        // Violet, not the provider's red — the badge says where the track
        // lives, not which service it came from.
        color = AppTheme.primarySoft;
        label = type.label;
        break;
      case MediaSourceType.local:
        color = AppTheme.accent;
        label = type.label;
        break;
      case MediaSourceType.podcast:
        color = Colors.orangeAccent;
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
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// Play next / add to queue / add to playlist / download for [item] — the
/// long-press menu on a track tile, and the ⋮ menu on home rows.
void showTrackActions(BuildContext context, AppMediaItem item) {
  final provider = context.read<MusicPlayerProvider>();
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surface,
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
            leading: const Icon(Icons.playlist_play_rounded, color: AppTheme.accent),
            title: const Text('Play next'),
            onTap: () {
              final added = provider.playNext(item);
              Navigator.pop(sheetContext);
              _confirm(context, added
                  ? 'Playing next: ${item.title}'
                  : 'Already playing: ${item.title}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded, color: AppTheme.accent),
            title: const Text('Add to queue'),
            onTap: () {
              final added = provider.addToQueue(item);
              Navigator.pop(sheetContext);
              _confirm(context, added
                  ? 'Added to queue: ${item.title}'
                  : 'Already playing: ${item.title}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: AppTheme.accent),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.pop(sheetContext);
              showAddToPlaylistSheet(context, item);
            },
          ),
          if (item.sourceType == MediaSourceType.youtube)
            provider.isDownloaded(item.id)
                ? ListTile(
                    leading: const Icon(Icons.download_done_rounded,
                        color: AppTheme.accent),
                    title: const Text('Remove download'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      removeDownload(context, item);
                    },
                  )
                : ListTile(
                    leading: const Icon(Icons.download_rounded,
                        color: AppTheme.accent),
                    title: Text(provider.isDownloading(item.id)
                        ? 'Downloading…'
                        : 'Download'),
                    enabled: !provider.isDownloading(item.id),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      startDownload(context, item);
                    },
                  ),
        ],
      ),
    ),
  );
}

void _confirm(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Download [item] and say how it went. A failed download used to leave the
/// user with a spinner that just vanished, with no explanation.
Future<void> startDownload(BuildContext context, AppMediaItem item) async {
  final provider = context.read<MusicPlayerProvider>();
  if (provider.isDownloading(item.id)) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Downloading "${item.title}"…'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  final path = await provider.downloadTrack(item);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(path != null
            ? 'Downloaded "${item.title}" for offline playback!'
            : 'Could not download "${item.title}". Check your connection and try again.'),
        backgroundColor: path != null ? AppTheme.primary : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

Future<void> removeDownload(BuildContext context, AppMediaItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  await context.read<MusicPlayerProvider>().deleteDownload(item);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Removed download: ${item.title}'),
        behavior: SnackBarBehavior.floating,
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
            color: AppTheme.accent,
            // Null until the first chunk arrives, so it spins rather than
            // sitting at a dead 0%.
            value: provider.downloadProgress(item.id),
          ),
        ),
      );
    }

    if (provider.isDownloaded(item.id)) {
      return IconButton(
        icon: Icon(Icons.download_done_rounded, color: AppTheme.accent, size: size),
        tooltip: 'Downloaded — tap to remove',
        onPressed: () => removeDownload(context, item),
      );
    }

    return IconButton(
      icon: Icon(Icons.download_rounded, color: Colors.white54, size: size),
      tooltip: 'Download for offline',
      onPressed: () => startDownload(context, item),
    );
  }
}
