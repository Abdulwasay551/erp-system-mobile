import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks network-interface connectivity (WiFi/mobile data present) and fires
/// `onRegained` when it flips from offline to online, so SyncService can trigger a
/// drain attempt without a screen having to poll.
///
/// This is interface-level, not a true internet-reachability check (a device can be on
/// WiFi with no actual internet) - that gap is covered on the write side instead: any
/// queueable write attempts the real request first regardless of what this reports, and
/// only falls back to queuing if that attempt actually fails with a network error. This
/// service is what drives the UI's offline banner and background sync retries.
class ConnectivityService extends ChangeNotifier {
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  void Function()? onRegained;

  ConnectivityService({this.onRegained}) {
    _init();
  }

  Future<void> _init() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _isOnline = !initial.contains(ConnectivityResult.none);
    } catch (_) {
      _isOnline = true;
    }
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final nowOnline = !results.contains(ConnectivityResult.none);
      final wasOffline = !_isOnline;
      if (nowOnline != _isOnline) {
        _isOnline = nowOnline;
        notifyListeners();
      }
      if (nowOnline && wasOffline) {
        onRegained?.call();
      }
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
