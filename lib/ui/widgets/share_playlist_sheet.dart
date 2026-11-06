import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/playlist.dart';
import '../../services/platform_bridge.dart';
import '../../services/youtube_service.dart';
import '../../util/playlist_codec.dart';
import '../theme/app_theme.dart';

/// Displays the sharing options sheet for a [playlist].
///
/// Supports sharing as a `.pulse` file, copying a compact link, or
/// sending a preformatted message with link and song summary.
Future<void> showSharePlaylistSheet(
  BuildContext context,
  Playlist playlist,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _SharePlaylistSheet(playlist: playlist),
  );
}

class _SharePlaylistSheet extends StatelessWidget {
  final Playlist playlist;

  const _SharePlaylistSheet({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final isLarge = PlaylistCodec.isLargePlaylist(playlist.items.length);
    final messenger = ScaffoldMessenger.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.mist.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share Playlist',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                playlist.name,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.mist.withValues(alpha: 0.65),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            if (isLarge)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: context.colors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Large playlist (>100 songs). Sharing as a file is recommended.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.mist.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _buildActionTile(
              context: context,
              icon: Icons.file_present_rounded,
              title: 'Share Playlist File',
              subtitle: 'Send as a .pulse file for any Pulse app',
              onTap: () => _handleShareFile(context, messenger),
            ),
            _buildActionTile(
              context: context,
              icon: Icons.link_rounded,
              title: 'Copy Share Link',
              subtitle: 'Fast link for WhatsApp, Telegram, or chat',
              onTap: () => _handleCopyLink(context, messenger),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.lift.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: context.colors.mist.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: AppTheme.primarySoft,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.colors.mist,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.mist.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.mist.withValues(alpha: 0.35),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleShareFile(
    BuildContext sheetContext,
    ScaffoldMessengerState messenger,
  ) async {
    Navigator.of(sheetContext).pop();

    final export = PlaylistCodec.exportToJson(playlist);
    final streamableItems = export.json['items'] as List;

    if (streamableItems.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Only songs on this phone — there's nothing to share"),
        ),
      );
      return;
    }

    final safeName = YoutubeService.safeFolderName(playlist.name);
    final fileName = '$safeName.pulse';
    final bytes = utf8.encode(jsonEncode(export.json));

    try {
      if (Platform.isAndroid) {
        final cacheDir = await getTemporaryDirectory();
        final dir = Directory('${cacheDir.path}/shared');
        await dir.create(recursive: true);
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await PlatformBridge.shareFile(file.path, 'application/octet-stream');
      } else {
        final saved = await FilePicker.saveFile(
          dialogTitle: 'Save playlist',
          fileName: fileName,
          mimeType: 'application/octet-stream',
          bytes: bytes,
        );
        if (saved != null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Playlist file saved')),
          );
        }
      }

      if (export.skipped > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${export.skipped} song${export.skipped == 1 ? '' : 's'} only on this phone left out',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share file: $e')),
      );
    }
  }

  Future<void> _handleCopyLink(
    BuildContext sheetContext,
    ScaffoldMessengerState messenger,
  ) async {
    Navigator.of(sheetContext).pop();

    final export = PlaylistCodec.exportToJson(playlist);
    final streamableItems = export.json['items'] as List;

    if (streamableItems.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Only songs on this phone — there's nothing to share"),
        ),
      );
      return;
    }

    try {
      final code = PlaylistCodec.exportToCode(playlist);
      await Clipboard.setData(ClipboardData(text: code));
      messenger.showSnackBar(
        const SnackBar(content: Text('Copied playlist link')),
      );
      if (export.skipped > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${export.skipped} device-only track${export.skipped == 1 ? '' : 's'} left out',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not copy link: $e')),
      );
    }
  }
}
