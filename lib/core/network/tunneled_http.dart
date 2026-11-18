import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TunneledHttpException implements Exception {
  final String message;
  const TunneledHttpException(this.message);

  @override
  String toString() => message;
}

class TunneledHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  const TunneledHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}

/// Strictly routes HTTP/HTTPS requests through libbox's local `mixed-in` proxy
/// (`127.0.0.1:mixedPort`). Because Android excludes the app's own UID via
/// `addDisallowedApplication(packageName)` to avoid TUN routing loops, direct
/// `HttpClient` requests on Android would bypass the VPN unless explicitly pinned
/// to `PROXY 127.0.0.1:<mixedPort>`.
class TunneledHttp {
  static HttpClient createClient({
    required int? proxyPort,
    bool requireVpnProxy = true,
    Duration connectionTimeout = const Duration(seconds: 7),
  }) {
    if (requireVpnProxy && (proxyPort == null || proxyPort <= 0 || proxyPort > 65535)) {
      throw const TunneledHttpException(
        'VPN local proxy port is unavailable; direct connection fallback is disabled.',
      );
    }

    final client = HttpClient()..connectionTimeout = connectionTimeout;
    if (proxyPort != null && proxyPort > 0) {
      // Strictly specify PROXY only (no `; DIRECT`) so Dart never falls back to direct ISP sockets.
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
    }
    return client;
  }

  static Future<TunneledHttpResponse> get(
    Uri uri, {
    required int? proxyPort,
    bool requireVpnProxy = true,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 7),
    bool followRedirects = true,
  }) async {
    final client = createClient(
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
      connectionTimeout: timeout,
    );
    try {
      final req = await client.getUrl(uri).timeout(timeout);
      req.followRedirects = followRedirects;
      headers.forEach((k, v) => req.headers.set(k, v));

      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final resHeaders = <String, String>{};
      res.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          resHeaders[name.toLowerCase()] = values.join(', ');
        }
      });

      return TunneledHttpResponse(
        statusCode: res.statusCode,
        headers: resHeaders,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }
}
