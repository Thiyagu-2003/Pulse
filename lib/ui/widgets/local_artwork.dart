import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import '../../models/media_item_model.dart';
import '../theme/app_theme.dart';

/// Renders embedded artwork from local songs/albums via OnAudioQuery on Android,
/// or a sleek themed placeholder on desktop or when no artwork is embedded.
class LocalArtwork extends StatelessWidget {
  final int? id;
  final ArtworkType type;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final Widget? fallback;
  final BoxFit fit;

  LocalArtwork({
    super.key,
    int? id,
    AppMediaItem? item,
    this.type = ArtworkType.AUDIO,
    double? size,
    double width = 48,
    double height = 48,
    this.borderRadius,
    this.fallback,
    this.fit = BoxFit.cover,
  })  : id = id ?? (item != null ? (int.tryParse(item.id) ?? (item.extras?['audioId'] as int?)) : null),
        width = size ?? width,
        height = size ?? height;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(10);

    final defaultFallback = fallback ??
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: context.colors.mist.withValues(alpha: 0.08),
          ),
          child: Icon(
            type == ArtworkType.ALBUM
                ? Icons.album_rounded
                : type == ArtworkType.ARTIST
                    ? Icons.person_rounded
                    : Icons.music_note_rounded,
            color: AppTheme.primary.withValues(alpha: 0.7),
            size: width * 0.45,
          ),
        );

    if (!Platform.isAndroid || id == null || id! <= 0) {
      return defaultFallback;
    }

    return ClipRRect(
      borderRadius: radius,
      child: QueryArtworkWidget(
        id: id!,
        type: type,
        artworkWidth: width,
        artworkHeight: height,
        artworkFit: fit,
        artworkBorder: BorderRadius.zero,
        keepOldArtwork: true,
        nullArtworkWidget: defaultFallback,
      ),
    );
  }
}

/// Renders a 2x2 collage artwork from up to 4 tracks for folders, playlists, or albums,
/// exactly matching modern local music players like Musicolet.
class CollageArtwork extends StatelessWidget {
  final List<AppMediaItem> items;
  final double size;
  final BorderRadius? borderRadius;
  final IconData? defaultIcon;

  const CollageArtwork({
    super.key,
    required this.items,
    this.size = 100,
    this.borderRadius,
    this.defaultIcon,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(14);

    if (items.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary.withValues(alpha: 0.25),
              AppTheme.primary.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: Icon(
          defaultIcon ?? Icons.folder_rounded,
          color: AppTheme.primary,
          size: size * 0.4,
        ),
      );
    }

    // 1 item: full size single art
    if (items.length == 1) {
      final songId = (items.first.extras?['songId'] as int?) ?? int.tryParse(items.first.id);
      return LocalArtwork(
        id: songId,
        width: size,
        height: size,
        borderRadius: radius,
      );
    }

    // 2x2 Collage from up to 4 items
    final cell = size / 2;
    final displayItems = items.take(4).toList();
    while (displayItems.length < 4) {
      displayItems.add(items[displayItems.length % items.length]);
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(
              children: [
                _buildCell(displayItems[0], cell),
                _buildCell(displayItems[1], cell),
              ],
            ),
            Row(
              children: [
                _buildCell(displayItems[2], cell),
                _buildCell(displayItems[3], cell),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(AppMediaItem item, double cellSize) {
    final songId = (item.extras?['songId'] as int?) ?? int.tryParse(item.id);
    return LocalArtwork(
      id: songId,
      width: cellSize,
      height: cellSize,
      borderRadius: BorderRadius.zero,
    );
  }
}
