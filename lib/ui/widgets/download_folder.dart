import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../providers/music_player_provider.dart';
import '../../services/youtube_service.dart';

/// Where downloads go, for display.
String downloadFolderLabel(MusicPlayerProvider provider) {
  final custom = provider.customDownloadPath;
  if (custom != null && custom.isNotEmpty) return custom;
  return Platform.isWindows
      ? r'Music\Pulse'
      : 'Internal Storage / Android / data / com.pulse.music / files / Music';
}

/// Let the user pick any folder for downloads (Settings, Library).
///
/// Android 11+ lets an app write outside its own folders only with "All
/// files access" — without it even Music/ refuses Pulse's temporary
/// `.part` files. So when the chosen folder isn't writable, explain and
/// open that switch, then check the folder again.
Future<void> chooseDownloadFolder(BuildContext context) async {
  final provider = context.read<MusicPlayerProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final path = await FilePicker.getDirectoryPath(
    dialogTitle: 'Choose a folder for downloads',
  );
  if (path == null || path.isEmpty) return;
  final dir = Directory(path);

  var writable = await YoutubeService.isWritableDirectory(dir);
  if (!writable && Platform.isAndroid && context.mounted) {
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow saving anywhere?'),
        content: const Text(
          'Android only lets Pulse save outside its own folder with '
          '"All files access". Turn it on for Pulse on the next screen, '
          'then come back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (allow == true) {
      // Android 11+ uses the first, Android 10 and older the second; each
      // is a no-op where it doesn't apply. The folder check below is what
      // decides.
      await [Permission.manageExternalStorage, Permission.storage].request();
      writable = await YoutubeService.isWritableDirectory(dir);
    }
  }

  if (!writable) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          "Pulse can't save to that folder. Pick another, or allow "
          '"All files access" for Pulse and try again.',
        ),
      ),
    );
    return;
  }
  await provider.setCustomDownloadPath(path);
  messenger.showSnackBar(
    SnackBar(content: Text('Downloads will be saved to $path')),
  );
}
