import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'tunneled_http.dart';

class ExitIpInfo {
  final bool ok;
  final String ip;
  final String country;
  final int rttMs;
  final String error;

  const ExitIpInfo({
    required this.ok,
    required this.ip,
    required this.country,
    required this.rttMs,
    this.error = '',
  });
}

class SpeedMeasurement {
  final int downloadBps;
  final int uploadBps;
  final String error;

  const SpeedMeasurement({
    required this.downloadBps,
    required this.uploadBps,
    this.error = '',
  });

  double get downloadMbps => double.parse(((downloadBps * 8) / 1e6).toStringAsFixed(1));
  double get uploadMbps => double.parse(((uploadBps * 8) / 1e6).toStringAsFixed(1));
}

class SpeedTester {
  static Future<ExitIpInfo> checkExitIp({
    required int? proxyPort,
    bool requireVpnProxy = true,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await TunneledHttp.get(
        Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
        proxyPort: proxyPort,
        requireVpnProxy: requireVpnProxy,
        timeout: timeout,
      );
      sw.stop();
      if (res.statusCode == 200) {
        final lines = res.body.split('\n');
        var ip = '';
        var loc = '';
        for (final line in lines) {
          final eq = line.indexOf('=');
          if (eq <= 0) continue;
          final k = line.substring(0, eq).trim();
          final v = line.substring(eq + 1).trim();
          if (k == 'ip') ip = v;
          if (k == 'loc') loc = v.toUpperCase();
        }
        if (ip.isNotEmpty) {
          return ExitIpInfo(ok: true, ip: ip, country: loc, rttMs: sw.elapsedMilliseconds);
        }
      }
    } on TunneledHttpException catch (e) {
      return ExitIpInfo(ok: false, ip: '', country: '', rttMs: 0, error: e.message);
    } catch (_) {}

    try {
      final sw2 = Stopwatch()..start();
      final res = await TunneledHttp.get(
        Uri.parse('https://ipinfo.io/json'),
        proxyPort: proxyPort,
        requireVpnProxy: requireVpnProxy,
        timeout: timeout,
      );
      sw2.stop();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final ip = (data['ip'] ?? '').toString();
        final country = (data['country'] ?? '').toString().toUpperCase();
        if (ip.isNotEmpty) {
          return ExitIpInfo(ok: true, ip: ip, country: country, rttMs: sw2.elapsedMilliseconds);
        }
      }
    } on TunneledHttpException catch (e) {
      return ExitIpInfo(ok: false, ip: '', country: '', rttMs: 0, error: e.message);
    } catch (e) {
      return ExitIpInfo(ok: false, ip: '', country: '', rttMs: 0, error: e.toString());
    }

    return const ExitIpInfo(
      ok: false,
      ip: '',
      country: '',
      rttMs: 0,
      error: 'Exit IP lookup failed through VPN proxy',
    );
  }

  /// Measures real download & upload throughput strictly through the active VPN
  /// tunnel (`127.0.0.1:proxyPort`) with zero fallback to direct ISP sockets.
  static Future<SpeedMeasurement> measureThroughput({
    required int? proxyPort,
    bool requireVpnProxy = true,
    Duration downloadWindow = const Duration(milliseconds: 3500),
    Duration uploadWindow = const Duration(milliseconds: 2500),
  }) async {
    var downBps = 0;
    var upBps = 0;
    var lastError = '';

    final downClient = TunneledHttp.createClient(
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
      connectionTimeout: const Duration(seconds: 7),
    );
    try {
      final req = await downClient
          .getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=6000000'))
          .timeout(const Duration(seconds: 7));
      final sw = Stopwatch()..start();
      final res = await req.close().timeout(const Duration(seconds: 7));
      var totalBytes = 0;
      await for (final chunk in res) {
        totalBytes += chunk.length;
        if (sw.elapsed >= downloadWindow) break;
      }
      sw.stop();
      final sec = sw.elapsedMilliseconds / 1000.0;
      if (totalBytes > 4096 && sec > 0.05) {
        downBps = (totalBytes / sec).round();
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      downClient.close(force: true);
    }

    final upClient = TunneledHttp.createClient(
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
      connectionTimeout: uploadWindow + const Duration(seconds: 3),
    );
    try {
      final payload = Uint8List.fromList(List<int>.filled(512 * 1024, 0x41));
      final sw = Stopwatch()..start();
      final req = await upClient
          .postUrl(Uri.parse('https://speed.cloudflare.com/__up'))
          .timeout(uploadWindow + const Duration(seconds: 3));
      req.headers.contentLength = payload.length;
      req.add(payload);
      final res = await req.close().timeout(uploadWindow + const Duration(seconds: 3));
      await res.drain<void>().catchError((_) {});
      sw.stop();
      if (res.statusCode >= 200 && res.statusCode < 400 && sw.elapsedMilliseconds > 20) {
        upBps = (payload.length / (sw.elapsedMilliseconds / 1000.0)).round();
      }
    } catch (e) {
      if (lastError.isEmpty) lastError = e.toString();
    } finally {
      upClient.close(force: true);
    }

    return SpeedMeasurement(
      downloadBps: downBps,
      uploadBps: upBps,
      error: (downBps == 0 && upBps == 0) ? lastError : '',
    );
  }
}
