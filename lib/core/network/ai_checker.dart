import 'dart:async';

import '../geo/country_detector.dart';
import '../models/vpn_models.dart';
import 'speed_tester.dart';
import 'tunneled_http.dart';

class _WebProbeResult {
  final bool reachable;
  final bool online;
  final bool geoBlocked;
  final bool redirectedToRegions;
  final bool authRequired;
  final bool captcha;
  final bool cfChallenge;
  final bool isTimeout;
  final int statusCode;
  final int ms;
  final String error;

  const _WebProbeResult({
    required this.reachable,
    required this.online,
    required this.geoBlocked,
    required this.redirectedToRegions,
    required this.authRequired,
    required this.captcha,
    this.cfChallenge = false,
    required this.isTimeout,
    required this.statusCode,
    required this.ms,
    this.error = '',
  });
}

class AiChecker {
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static Future<AiCheckResult> checkAll({
    required int? activeProfileId,
    required int? proxyPort,
    bool requireVpnProxy = true,
    bool includeSpeed = true,
  }) async {
    if (requireVpnProxy && (proxyPort == null || proxyPort <= 0)) {
      throw const TunneledHttpException(
        'Cannot run AI/Exit check without an active VPN local proxy port.',
      );
    }

    final exitFuture = SpeedTester.checkExitIp(
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );
    final geminiFuture = _probeUrl(
      'https://gemini.google.com/app',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );
    final studioFuture = _probeUrl(
      'https://aistudio.google.com/u/0/prompts/new_chat',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
      checkStudioShell: true,
    );
    final googleApiFuture = _probeApi(
      'https://generativelanguage.googleapis.com/v1beta/models',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );
    final gptFuture = _probeUrl(
      'https://chatgpt.com/',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );
    final openaiApiFuture = _probeApi(
      'https://api.openai.com/v1/models',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );
    final claudeFuture = _probeUrl(
      'https://claude.ai/login',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );
    final anthropicApiFuture = _probeApi(
      'https://api.anthropic.com/v1/models',
      proxyPort: proxyPort,
      requireVpnProxy: requireVpnProxy,
    );

    final exit = await exitFuture;
    final gWeb = await geminiFuture;
    final sWeb = await studioFuture;
    final gApi = await googleApiFuture;
    final cWeb = await gptFuture;
    final oApi = await openaiApiFuture;
    final clWeb = await claudeFuture;
    final aApi = await anthropicApiFuture;

    final anyReachable = exit.ok ||
        gWeb.reachable ||
        sWeb.reachable ||
        cWeb.reachable ||
        clWeb.reachable ||
        gApi.reachable ||
        oApi.reachable ||
        aApi.reachable;

    double? speedMbps;
    if (includeSpeed && anyReachable) {
      final spd = await SpeedTester.measureThroughput(
        proxyPort: proxyPort,
        requireVpnProxy: requireVpnProxy,
      );
      if (spd.downloadBps > 0) speedMbps = spd.downloadMbps;
    }

    final country = exit.country;
    final blockedMap = CountryDetector.serviceBlockedCountries;

    return AiCheckResult(
      networkReachable: anyReachable,
      profileId: activeProfileId,
      exitIp: exit.ip,
      country: country,
      speedMbps: speedMbps,
      gemini: _classifyGoogle(
        gWeb,
        gApi,
        country.isNotEmpty && (blockedMap['gemini']?.contains(country) ?? false),
        country,
        anyReachable,
      ),
      aiStudio: _classifyGoogle(
        sWeb,
        gApi,
        country.isNotEmpty && (blockedMap['aistudio']?.contains(country) ?? false),
        country,
        anyReachable,
        requireAuthNotice: true,
      ),
      chatGpt: _classifyCf(
        cWeb,
        oApi,
        country.isNotEmpty && (blockedMap['chatgpt']?.contains(country) ?? false),
        country,
        anyReachable,
      ),
      claude: _classifyCf(
        clWeb,
        aApi,
        country.isNotEmpty && (blockedMap['claude']?.contains(country) ?? false),
        country,
        anyReachable,
      ),
    );
  }

  static Future<_WebProbeResult> _probeUrl(
    String url, {
    required int? proxyPort,
    required bool requireVpnProxy,
    bool checkStudioShell = false,
  }) async {
    final sw = Stopwatch()..start();
    try {
      var currentUrl = Uri.parse(url);
      final chain = <String>[currentUrl.toString()];
      TunneledHttpResponse? lastRes;

      for (var i = 0; i < 5; i++) {
        lastRes = await TunneledHttp.get(
          currentUrl,
          proxyPort: proxyPort,
          requireVpnProxy: requireVpnProxy,
          followRedirects: false,
          headers: const {
            'User-Agent': _userAgent,
            'Accept-Language': 'en-US,en;q=0.9',
          },
          timeout: const Duration(seconds: 7),
        );
        if (lastRes.statusCode >= 300 && lastRes.statusCode < 400) {
          final loc = lastRes.headers['location'];
          if (loc == null || loc.isEmpty) break;
          currentUrl = currentUrl.resolve(loc);
          chain.add(currentUrl.toString());
        } else {
          break;
        }
      }

      sw.stop();
      if (lastRes == null) {
        return const _WebProbeResult(
          reachable: false,
          online: false,
          geoBlocked: false,
          redirectedToRegions: false,
          authRequired: false,
          captcha: false,
          isTimeout: false,
          statusCode: 0,
          ms: 0,
        );
      }

      final chainStr = chain.join(' ').toLowerCase();
      final finalLow = currentUrl.toString().toLowerCase();
      final bodyLow = lastRes.body.toLowerCase();

      final redirectedToRegions = chainStr.contains('available-regions') ||
          chainStr.contains('available_regions') ||
          chainStr.contains('/unavailable') ||
          chainStr.contains('unsupported_country');

      final geoBlocked = redirectedToRegions ||
          lastRes.statusCode == 451 ||
          bodyLow.contains("isn't currently supported") ||
          bodyLow.contains('not available in your country') ||
          bodyLow.contains('location is not supported') ||
          bodyLow.contains('unsupported_country');

      final authRequired = finalLow.contains('accounts.google.com') ||
          finalLow.contains('/servicelogin') ||
          finalLow.contains('/signin') ||
          lastRes.statusCode == 401;

      final cfChallenge = (lastRes.statusCode == 403 && lastRes.headers.containsKey('cf-mitigated')) ||
          bodyLow.contains('cf-chl-') ||
          bodyLow.contains('just a moment...');

      final captcha = chainStr.contains('sorry/index') || lastRes.statusCode == 429 || cfChallenge;
      final studioOk = !checkStudioShell ||
          RegExp(r'aistudio|makersuite|ng-version|wiz_global_data', caseSensitive: false).hasMatch(lastRes.body);
      final online = lastRes.statusCode >= 200 &&
          lastRes.statusCode < 300 &&
          studioOk &&
          !geoBlocked &&
          !authRequired &&
          !captcha;

      return _WebProbeResult(
        reachable: lastRes.statusCode > 0,
        online: online,
        geoBlocked: geoBlocked,
        redirectedToRegions: redirectedToRegions,
        authRequired: authRequired,
        captcha: captcha,
        cfChallenge: cfChallenge,
        isTimeout: false,
        statusCode: lastRes.statusCode,
        ms: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      return const _WebProbeResult(
        reachable: false,
        online: false,
        geoBlocked: false,
        redirectedToRegions: false,
        authRequired: false,
        captcha: false,
        isTimeout: true,
        statusCode: 0,
        ms: 0,
        error: 'Timeout',
      );
    } catch (e) {
      return _WebProbeResult(
        reachable: false,
        online: false,
        geoBlocked: false,
        redirectedToRegions: false,
        authRequired: false,
        captcha: false,
        isTimeout: false,
        statusCode: 0,
        ms: 0,
        error: e.toString(),
      );
    }
  }

  static Future<({bool reachable, bool geoBlocked, bool authorized, bool authRequired, int status, int ms})> _probeApi(
    String url, {
    required int? proxyPort,
    required bool requireVpnProxy,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final res = await TunneledHttp.get(
        Uri.parse(url),
        proxyPort: proxyPort,
        requireVpnProxy: requireVpnProxy,
        headers: const {'User-Agent': _userAgent},
        timeout: const Duration(seconds: 7),
      );
      sw.stop();
      final low = res.body.toLowerCase();
      final geoBlocked = res.statusCode == 451 ||
          low.contains('location is not supported') ||
          low.contains('unsupported_country') ||
          low.contains('country, region, or territory');
      return (
        reachable: res.statusCode > 0,
        geoBlocked: geoBlocked,
        authorized: !geoBlocked && res.statusCode == 200,
        authRequired: !geoBlocked && res.statusCode == 401,
        status: res.statusCode,
        ms: sw.elapsedMilliseconds,
      );
    } catch (_) {
      return (reachable: false, geoBlocked: false, authorized: false, authRequired: false, status: 0, ms: 0);
    }
  }

  static AiServiceReport _classifyGoogle(
    _WebProbeResult web,
    ({bool reachable, bool geoBlocked, bool authorized, bool authRequired, int status, int ms}) api,
    bool countryBlocked,
    String country,
    bool anyReachable, {
    bool requireAuthNotice = false,
  }) {
    if (countryBlocked || api.geoBlocked || web.geoBlocked) {
      return AiServiceReport(
        status: AiServiceStatus.regionRestricted,
        ms: web.ms > 0 ? web.ms : api.ms,
        reason: web.redirectedToRegions ? 'available_regions_redirect' : 'region_blocked',
        note: 'Region restricted${country.isNotEmpty ? ' ($country)' : ''}',
      );
    }
    if (web.captcha) {
      return AiServiceReport(status: AiServiceStatus.challenge, ms: web.ms, reason: 'captcha', note: 'CAPTCHA / Rate limit');
    }
    if (web.authRequired) {
      return AiServiceReport(status: AiServiceStatus.authRequired, ms: web.ms, reason: 'auth_required', note: 'Google sign-in required');
    }
    if (web.online) {
      if (requireAuthNotice) {
        return AiServiceReport(
          status: AiServiceStatus.authRequired,
          ms: web.ms,
          reason: 'account_unverified',
          note: 'Shell reachable; account required',
        );
      }
      return AiServiceReport(status: AiServiceStatus.available, ms: web.ms, reason: 'ok', note: 'Available (${web.ms} ms)');
    }
    if (!anyReachable) {
      return const AiServiceReport(status: AiServiceStatus.unknown, ms: 0, reason: 'unreachable', note: 'Could not determine');
    }
    return AiServiceReport(status: AiServiceStatus.connectionError, ms: web.ms, reason: 'http_error', note: 'HTTP ${web.statusCode}');
  }

  static AiServiceReport _classifyCf(
    _WebProbeResult web,
    ({bool reachable, bool geoBlocked, bool authorized, bool authRequired, int status, int ms}) api,
    bool countryBlocked,
    String country,
    bool anyReachable,
  ) {
    if (countryBlocked || api.geoBlocked || web.geoBlocked) {
      return AiServiceReport(
        status: AiServiceStatus.regionRestricted,
        ms: web.ms > 0 ? web.ms : api.ms,
        reason: 'region_blocked',
        note: 'Region restricted${country.isNotEmpty ? ' ($country)' : ''}',
      );
    }
    if (web.online) {
      return AiServiceReport(status: AiServiceStatus.available, ms: web.ms, reason: 'ok', note: 'Available (${web.ms} ms)');
    }
    if (web.cfChallenge || web.captcha) {
      return AiServiceReport(status: AiServiceStatus.challenge, ms: web.ms, reason: 'challenge', note: 'CAPTCHA / Cloudflare check');
    }
    if (api.authRequired) {
      return AiServiceReport(status: AiServiceStatus.authRequired, ms: api.ms, reason: 'auth_required', note: 'Authentication required');
    }
    if (!anyReachable) {
      return const AiServiceReport(status: AiServiceStatus.unknown, ms: 0, reason: 'unreachable', note: 'Could not determine');
    }
    return AiServiceReport(status: AiServiceStatus.connectionError, ms: web.ms, reason: 'http_error', note: 'HTTP ${web.statusCode}');
  }
}
