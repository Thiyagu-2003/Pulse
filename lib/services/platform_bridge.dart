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
