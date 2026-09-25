import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the phone is on mobile data right now, kept current from
/// connectivity changes. Read synchronously wherever a download size
/// decision is made (stream quality, pre-caching the next song).
class NetworkStatus {
  NetworkStatus._();
  static final NetworkStatus instance = NetworkStatus._();

  bool _onMobileData = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// True only when mobile data is the connection in use. Wi-Fi or
  /// Ethernet alongside it (or not knowing) counts as not mobile.
  bool get onMobileData => _onMobileData;

  @visibleForTesting
  set onMobileData(bool value) => _onMobileData = value;

  /// Best-effort: without the plugin (tests, desktop) it stays "not mobile".
  Future<void> start() async {
    if (_subscription != null) return;
    try {
      final connectivity = Connectivity();
      _update(await connectivity.checkConnectivity());
      _subscription = connectivity.onConnectivityChanged.listen(_update);
    } catch (e) {
      debugPrint('Connectivity unavailable: $e');
    }
  }

  void _update(List<ConnectivityResult> results) {
    _onMobileData = results.contains(ConnectivityResult.mobile) &&
        !results.contains(ConnectivityResult.wifi) &&
        !results.contains(ConnectivityResult.ethernet);
  }
}
