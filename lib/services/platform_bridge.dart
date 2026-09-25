import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Calls into MainActivity's `pulse/platform` channel: the home-screen
/// widget and the launcher icon switch.
///
/// Best-effort: when the channel isn't there (tests, or the engine started
/// by a media button with no activity) nothing should break.
class PlatformBridge {
  static const _channel = MethodChannel('pulse/platform');

  static Future<void> updateWidget({
    String? title,
    String? artist,
    String? artPath,
    required bool playing,
  }) =>
      _call('updateWidget', {
        'title': title,
        'artist': artist,
        'artPath': artPath,
        'playing': playing,
      });

  static Future<void> setLauncherIcon({required bool dark}) =>
      _call('setLauncherIcon', {'dark': dark});

  /// The icon style for everything Pulse draws natively — widget
  /// placeholder, notification large icons, the recent-apps entry. Applied
  /// at once (the launcher entry waits until the app is left).
  static Future<void> setIconStyle({required bool dark}) =>
      _call('setIconStyle', {'dark': dark});

  /// The installed version ("1.0.0"), or null off Android.
  static Future<String?> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion');
    } catch (_) {
      return null;
    }
  }

  /// Open [url] in the browser (e.g. an update's download).
  static Future<void> openUrl(String url) => _call('openUrl', {'url': url});

  /// Android's share sheet with [text].
  static Future<void> share(String text) => _call('share', {'text': text});

  /// Tell Android's media index about a new file. Only matters for a custom
  /// download folder (e.g. Music/): the default folder is app-private, which
  /// Android 11+ never indexes, so other apps won't list those files.
  static Future<void> scanFile(String path) => _call('scanFile', {'path': path});

  /// Keep the app process alive while downloads run, via a foreground
  /// service with its own notification — otherwise Android may kill the
  /// app, and the download with it, soon after the user leaves.
  static Future<void> setDownloadsRunning(bool running) =>
      _call('setDownloadsRunning', {'running': running});

  static Future<void> _call(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No activity-backed engine (e.g. widget tests).
    } catch (e) {
      debugPrint('pulse/platform $method failed: $e');
    }
  }
}
