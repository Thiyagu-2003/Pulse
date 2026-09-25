import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'platform_bridge.dart';

/// A newer Pulse on GitHub Releases.
class AppUpdate {
  final String version;
  final String notes;

  /// The release's APK, or its page when it has none.
  final String url;

  const AppUpdate(this.version, this.notes, this.url);
}

/// Settings > Check for updates, and a quiet daily check at launch.
/// Releases are tagged "v1.2.0" with the APK attached.
class UpdateService {
  static const _latest =
      'https://api.github.com/repos/Thiyagu-2003/Pulse/releases/latest';

  /// The newer release, or null when up to date (or unreachable).
  static Future<AppUpdate?> check() async {
    final current = await PlatformBridge.appVersion();
    if (current == null) return null;
    try {
      final res = await http.get(Uri.parse(_latest), headers: {
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return fromRelease(jsonDecode(res.body) as Map<String, dynamic>,
          current: current);
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  @visibleForTesting
  static AppUpdate? fromRelease(
    Map<String, dynamic> release, {
    required String current,
  }) {
    final tag = '${release['tag_name'] ?? ''}';
    if (!isNewer(tag, current)) return null;
    final apks = (release['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((a) => '${a['browser_download_url'] ?? ''}')
        .where((u) => u.endsWith('.apk'))
        .toList();
    // Split per ABI (flutter build apk --split-per-abi): nearly every phone
    // is arm64.
    final apk = apks.where((u) => u.contains('arm64')).firstOrNull ??
        apks.firstOrNull;
    return AppUpdate(
      tag.replaceFirst(RegExp('^v'), ''),
      '${release['body'] ?? ''}'.trim(),
      apk ?? '${release['html_url'] ?? ''}',
    );
  }

  /// "v1.10.0" vs "1.9.2": compared number by number.
  @visibleForTesting
  static bool isNewer(String latest, String current) {
    List<int> parts(String v) => v
        .replaceFirst(RegExp('^v'), '')
        .split(RegExp(r'[.+-]'))
        .take(3)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
