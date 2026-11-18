import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../models/vpn_models.dart';
import '../parser/share_link_parser.dart';

class SmartFilterResult {
  final List<VpnProfile> selected;
  final int totalRaw;
  final int parsedCount;
  final int aliveTcpCount;

  const SmartFilterResult({
    required this.selected,
    required this.totalRaw,
    required this.parsedCount,
    required this.aliveTcpCount,
  });
}

class _ProbeItem {
  final VpnProfile profile;
  int tcpMs;
  _ProbeItem(this.profile, [this.tcpMs = -1]);
}

class SmartFilter {
  static const int smartImportLimit = 120;
  static const int tcpFastMs = 250;
  static const int maxPingMs = 2200;

  static Future<SmartFilterResult> curate({
    required List<String> rawLines,
    required int groupId,
    required int startingId,
    bool strictTls = false,
    int maxKeep = smartImportLimit,
    int concurrency = 18,
  }) async {
    // Parse, deduplicate, and score in a background Isolate so UI stays 60fps
    final parsed = await Isolate.run(() {
      final seen = <String>{};
      final list = <VpnProfile>[];
      var nextId = startingId;
      for (final raw in rawLines) {
        final node = ShareLinkParser.parse(
          raw,
          id: nextId,
          groupId: groupId,
          strictTls: strictTls,
        );
        if (node == null) continue;
        if (!seen.add(node.dedupKey)) continue;
        list.add(node);
        nextId++;
      }
      list.sort((a, b) => b.score.compareTo(a.score));
      return list;
    });

    if (parsed.isEmpty) {
      return SmartFilterResult(
        selected: const [],
        totalRaw: rawLines.length,
        parsedCount: 0,
        aliveTcpCount: 0,
      );
    }

    final tcpCandidates = <VpnProfile>[];
    final udpCandidates = <VpnProfile>[];
    for (final p in parsed) {
      final isUdp = p.protocol == VpnProtocol.hy2 || p.protocol == VpnProtocol.tuic;
      if (isUdp) {
        if (udpCandidates.length < 25) udpCandidates.add(p);
      } else if (tcpCandidates.length < 480) {
        tcpCandidates.add(p);
      }
    }

    final probed = await _probeTcpBatch(tcpCandidates, concurrency: concurrency, timeoutMs: 1800);
    final alive = probed.where((e) => e.tcpMs > 0).toList();
    final fast = alive.where((e) => e.tcpMs <= tcpFastMs).toList();
    final pool = fast.length >= 15 ? fast : alive;

    pool.sort(
      (a, b) => (b.profile.score - b.tcpMs * 0.35).compareTo(a.profile.score - a.tcpMs * 0.35),
    );

    final selected = <VpnProfile>[];
    final hostCounts = <String, int>{};
    final udpReserve = math.min(12, udpCandidates.length);
    final tcpQuota = math.max(20, maxKeep - udpReserve);

    for (final item in pool) {
      if (selected.length >= tcpQuota) break;
      final key = item.profile.address.toLowerCase();
      final cnt = hostCounts[key] ?? 0;
      if (cnt >= 4) continue;
      hostCounts[key] = cnt + 1;
      selected.add(item.profile.copyWith(latencyMs: item.tcpMs));
    }

    for (final udp in udpCandidates) {
      if (selected.length >= maxKeep) break;
      final key = udp.address.toLowerCase();
      final cnt = hostCounts[key] ?? 0;
      if (cnt >= 3) continue;
      hostCounts[key] = cnt + 1;
      selected.add(udp);
    }

    return SmartFilterResult(
      selected: selected,
      totalRaw: rawLines.length,
      parsedCount: parsed.length,
      aliveTcpCount: alive.length,
    );
  }

  static Future<List<_ProbeItem>> _probeTcpBatch(
    List<VpnProfile> candidates, {
    int concurrency = 18,
    int timeoutMs = 1800,
  }) async {
    if (candidates.isEmpty) return const [];
    final results = List<_ProbeItem?>.filled(candidates.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final idx = cursor++;
        if (idx >= candidates.length) break;
        final item = candidates[idx];
        final rtt = await _probeTcpOnce(item.address, item.port, timeoutMs);
        results[idx] = _ProbeItem(item, rtt);
      }
    }

    final count = math.min(concurrency, candidates.length);
    await Future.wait(List.generate(count, (_) => worker()));
    return results.whereType<_ProbeItem>().toList();
  }

  static Future<int> _probeTcpOnce(String host, int port, int timeoutMs) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs));
      sw.stop();
      await socket.close().catchError((_) {});
      socket.destroy();
      return math.max(1, sw.elapsedMilliseconds);
    } catch (_) {
      return -1;
    }
  }
}
