import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'storage_service.dart';

/// Download progress in the notification shade: visible after leaving the
/// app, and it doesn't cover the song list the way a SnackBar did.
///
/// Every call is best-effort — a notification that can't be shown (the
/// permission was refused, or in tests) must never fail the download itself.
class DownloadNotifications {
  DownloadNotifications._();
  static final DownloadNotifications instance = DownloadNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  Future<bool> _init() async {
    try {
      final ok = await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_pulse'),
        ),
      );
      return ok ?? false;
    } catch (e) {
      debugPrint('Download notifications unavailable: $e');
      return false;
    }
  }

  static int _idFor(String trackId) => trackId.hashCode & 0x7fffffff;

  static AndroidNotificationDetails _details({
    required String icon,
    required bool ongoing,
    int progress = 0,
    bool showProgress = false,
    bool indeterminate = false,
  }) =>
      AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'Songs being saved for offline listening',
        importance: Importance.low, // no sound or pop-up for progress
        priority: Priority.low,
        icon: icon,
        // The app icon in the style chosen in Settings (the small icon
        // beside it is always a one-colour silhouette on Android).
        largeIcon: DrawableResourceAndroidBitmap(
          StorageService().getDarkLauncherIcon()
              ? 'app_icon_dark'
              : 'app_icon_light',
        ),
        onlyAlertOnce: true,
        // Never pinned: if Android kills the app mid-download, a pinned
        // "Downloading" notification could not be swiped away.
        ongoing: false,
        autoCancel: !ongoing,
        showProgress: showProgress,
        maxProgress: 100,
        progress: progress,
        indeterminate: indeterminate,
      );

  Future<void> _show(String trackId, String title, String body,
      AndroidNotificationDetails details) async {
    try {
      if (!await (_ready ??= _init())) return;
      await _plugin.show(
        _idFor(trackId),
        title,
        body,
        NotificationDetails(android: details),
      );
    } catch (e) {
      debugPrint('Could not show download notification: $e');
    }
  }

  /// [fraction] 0.0–1.0, or null while the size isn't known yet.
  Future<void> progress(String trackId, String songTitle, double? fraction) =>
      _show(
        trackId,
        'Downloading',
        songTitle,
        _details(
          icon: 'ic_stat_download',
          ongoing: true,
          showProgress: true,
          progress: ((fraction ?? 0) * 100).round(),
          indeterminate: fraction == null,
        ),
      );

  /// Replaces the progress notification. It is cancelled first, so the
  /// result still shows even if Android rate-limited the last update.
  Future<void> finished(String trackId, String songTitle,
      {required bool succeeded}) async {
    try {
      if (await (_ready ??= _init())) await _plugin.cancel(_idFor(trackId));
    } catch (_) {}
    await _show(
        trackId,
        succeeded ? 'Downloaded' : 'Download failed',
        succeeded ? songTitle : '$songTitle — tap download to try again',
        _details(
          icon: succeeded ? 'ic_stat_done' : 'ic_stat_download',
          ongoing: false,
        ),
      );
  }
}
