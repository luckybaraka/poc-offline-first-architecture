/// Connectivity monitoring. "Online" means all three are true:
///  - the phone has a network (Wi-Fi or mobile data),
///  - the backend answers a health check (having a network doesn't mean the server is reachable),
///  - the demo "force offline" switch is off.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'local_db.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService(this._db);

  final LocalDb _db;
  bool networkUp = true;
  bool serverReachable = false;
  bool forceOffline = false;

  bool get online => networkUp && serverReachable && !forceOffline;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _pingTimer;

  Future<void> start() async {
    // Remembered across restarts, so you can kill the app while "offline" and show the queue survive.
    forceOffline = (await _db.getMeta('forceOffline')) == '1';
    _setNetwork(await Connectivity().checkConnectivity());
    _sub = Connectivity().onConnectivityChanged.listen(_setNetwork);
    _pingTimer = Timer.periodic(kPingInterval, (_) => ping());
    await ping();
  }

  void _setNetwork(List<ConnectivityResult> results) {
    final up = results.any((r) => r != ConnectivityResult.none);
    if (up == networkUp) return;
    networkUp = up;
    if (!up) serverReachable = false;
    notifyListeners();
    if (up) ping();
  }

  Future<void> toggleForceOffline() async {
    forceOffline = !forceOffline;
    await _db.setMeta('forceOffline', forceOffline ? '1' : '0');
    notifyListeners();
    if (!forceOffline) await ping();
  }

  Future<void> ping() async {
    if (!networkUp || forceOffline) return;
    bool reachable;
    try {
      final res = await http.get(Uri.parse('$kApiBase/health/')).timeout(const Duration(seconds: 3));
      reachable = res.statusCode == 200;
    } catch (_) {
      reachable = false;
    }
    if (reachable != serverReachable) {
      serverReachable = reachable;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }
}
