import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';

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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      decoration: BoxDecoration(
        color: isPlayingCurrent
            ? AppTheme.primary.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: isPlayingCurrent
            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: onTap ?? () => playerProvider.playTrack(item, playlist: playlist),
        leading: ClipRRect(
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
            if (item.sourceType != MediaSourceType.local)
              playerProvider.isDownloading(item.id)
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.download_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () async {
                        final path = await playerProvider.downloadTrack(item);
                        if (context.mounted && path != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Downloaded "${item.title}" for offline playback!'),
                              backgroundColor: AppTheme.primary,
                            ),
                          );
                        }
                      },
                    ),
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.redAccent : Colors.white38,
                size: 20,
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
        color = Colors.redAccent;
        label = 'YT';
        break;
      case MediaSourceType.local:
        color = AppTheme.accent;
        label = 'Local';
        break;
      case MediaSourceType.podcast:
        color = Colors.orangeAccent;
        label = 'Podcast';
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
