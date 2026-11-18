import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../models/vpn_models.dart';

class PingProgress {
  final int total;
  final int done;
  final int onlineCount;
  final bool cancelled;
  final Map<int, int> latestResults;

  const PingProgress({
    required this.total,
    required this.done,
    required this.onlineCount,
    required this.cancelled,
    required this.latestResults,
  });
}

class PingTester {
  bool _cancelled = false;
  bool _running = false;

  bool get isRunning => _running;

  void cancel() {
    _cancelled = true;
  }

  /// Measures direct TCP handshake latency to the remote VPN server host:port.
  /// On Android, SutemiVpnService adds the app package via addDisallowedApplication
  /// so TCP probes reach the upstream endpoint directly even while connected.
  /// Concurrency is capped at 8 sockets to prevent battery drain and OS fd exhaustion.
  Future<Map<int, int>> testProfiles(
    List<VpnProfile> profiles, {
    int concurrency = 8,
    int timeoutMs = 2400,
    void Function(PingProgress progress)? onProgress,
  }) async {
    if (_running) throw StateError('Ping scan already in progress');
    if (profiles.isEmpty) return {};

    _running = true;
    _cancelled = false;
    final results = <int, int>{};
    var done = 0;
    var online = 0;
    var cursor = 0;

    try {
      Future<void> worker() async {
        while (!_cancelled) {
          final idx = cursor++;
          if (idx >= profiles.length) break;
          final profile = profiles[idx];
          final ms = await measureTcpLatency(profile.address, profile.port, timeoutMs: timeoutMs);
          results[profile.id] = ms;
          done++;
          if (ms > 0) online++;
          onProgress?.call(PingProgress(
            total: profiles.length,
            done: done,
            onlineCount: online,
            cancelled: _cancelled,
            latestResults: {profile.id: ms},
          ));
        }
      }

      final workers = math.min(concurrency, profiles.length);
      await Future.wait(List.generate(workers, (_) => worker()));
      return results;
    } finally {
      _running = false;
    }
  }

  static Future<int> measureTcpLatency(
    String host,
    int port, {
    int timeoutMs = 2400,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs));
      sw.stop();
      socket.destroy();
      return math.max(1, sw.elapsedMilliseconds);
    } catch (_) {
      return -1;
    }
  }
}
