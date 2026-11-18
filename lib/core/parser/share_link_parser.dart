import 'dart:convert';
import 'dart:io';

import '../geo/country_detector.dart';
import '../models/vpn_models.dart';

class ShareLinkParser {
  static String decodeBase64Safe(String input) {
    var clean = input.trim().replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return '';
    final mod = clean.length % 4;
    if (mod == 2) {
      clean += '==';
    } else if (mod == 3) {
      clean += '=';
    } else if (mod == 1) {
      return '';
    }
    try {
      return utf8.decode(base64.decode(clean));
    } catch (_) {
      return '';
    }
  }

  static bool isPrivateOrInvalidHost(String host) {
    final h = host.trim().toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '').replaceAll(RegExp(r'\.+$'), '');
    if (h.isEmpty || h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal')) {
      return true;
    }
    if (h.contains('%')) return true;

    final addr = InternetAddress.tryParse(h);
    if (addr != null) {
      if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
      if (addr.type == InternetAddressType.IPv4) {
        final raw = addr.rawAddress;
        final a = raw[0], b = raw[1], c = raw[2];
        if (a == 0 || a == 10 || a == 127) return true;
        if (a == 100 && b >= 64 && b <= 127) return true;
        if (a == 169 && b == 254) return true;
        if (a == 172 && b >= 16 && b <= 31) return true;
        if (a == 192 && b == 168) return true;
        if (a == 192 && b == 0) return true;
        if (a == 192 && b == 88 && c == 99) return true;
        if (a == 198 && (b == 18 || b == 19)) return true;
        if (a == 198 && b == 51 && c == 100) return true;
        if (a == 203 && b == 0 && c == 113) return true;
        if (a >= 224) return true;
      } else {
        final raw = addr.rawAddress;
        // Require global unicast 2000::/3
        if ((raw[0] & 0xe0) != 0x20) return true;
      }
    }
    return false;
  }

  static bool _parseBoolFlag(dynamic v) {
    final s = v?.toString().trim().toLowerCase() ?? '';
    return v == true || v == 1 || s == '1' || s == 'true';
  }

  static String _safeDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  static List<String>? extractShareLinks(String bodyText) {
    final trimmed = bodyText.trim();
    if (trimmed.isEmpty) return [];
    if (RegExp(r'^\s*(proxies:|outbounds:|mixed-port:|port:)', multiLine: true).hasMatch(trimmed)) {
      return null;
    }
    var text = trimmed;
    final linkCheck = RegExp(r'(?:vless|vmess|trojan|ss|hy2|hysteria2|tuic):\/\/', caseSensitive: false);
    if (!linkCheck.hasMatch(text)) {
      final decoded = decodeBase64Safe(text);
      if (decoded.isNotEmpty && linkCheck.hasMatch(decoded)) {
        text = decoded;
      }
    }
    return text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => RegExp(r'^(?:vless|vmess|trojan|ss|hy2|hysteria2|tuic):\/\/', caseSensitive: false).hasMatch(l))
        .toList();
  }

  static VpnProfile? parse(
    String rawLine, {
    required int id,
    required int groupId,
    bool strictTls = false,
    bool allowBlockedCountries = false,
    bool allowInsecureTls = false,
  }) {
    final line = rawLine.trim().replaceAll('&amp;', '&');
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) return null;

    final match = RegExp(r'^(vless|vmess|trojan|ss|hy2|hysteria2|tuic):\/\/', caseSensitive: false).firstMatch(line);
    if (match == null) return null;
    final rawProto = match.group(1)!.toLowerCase();

    late final VpnProtocol protocol;
    switch (rawProto) {
      case 'vmess':
        protocol = VpnProtocol.vmess;
      case 'trojan':
        protocol = VpnProtocol.trojan;
      case 'ss':
        protocol = VpnProtocol.ss;
      case 'hy2':
      case 'hysteria2':
        protocol = VpnProtocol.hy2;
      case 'tuic':
        protocol = VpnProtocol.tuic;
      default:
        protocol = VpnProtocol.vless;
    }

    var host = '';
    var port = 0;
    var name = '';
    var sni = '';
    var pathVal = '';
    var allowInsecure = false;
    var tls = const TlsParams();
    var transport = const TransportParams();
    var params = const ProtocolParams();

    try {
      if (rawProto == 'vmess') {
        final bodyAndHash = line.substring('vmess://'.length);
        final hashIdx = bodyAndHash.indexOf('#');
        final rawB64 = hashIdx >= 0 ? bodyAndHash.substring(0, hashIdx) : bodyAndHash;
        if (hashIdx >= 0) name = _safeDecode(bodyAndHash.substring(hashIdx + 1));

        if (rawB64.contains('@')) {
          final u = Uri.parse(line);
          host = u.host.replaceAll(RegExp(r'^\[|\]$'), '');
          port = u.port;
          if (name.isEmpty && u.fragment.isNotEmpty) name = _safeDecode(u.fragment);
          final uuid = _safeDecode(u.userInfo);
          if (uuid.isEmpty) return null;
          final sec = (u.queryParameters['security'] ?? u.queryParameters['tls'] ?? '').toLowerCase();
          sni = u.queryParameters['sni'] ?? u.queryParameters['host'] ?? '';
          pathVal = u.queryParameters['path'] ?? '';
          allowInsecure = _parseBoolFlag(u.queryParameters['allowInsecure'] ?? u.queryParameters['insecure']);
          tls = TlsParams(
            security: sec == 'tls' ? 'tls' : 'none',
            sni: sni.isNotEmpty ? sni : null,
            fingerprint: u.queryParameters['fp'],
            alpn: u.queryParameters['alpn']?.split(',').where((e) => e.trim().isNotEmpty).toList() ?? const [],
            allowInsecure: allowInsecure,
          );
          transport = TransportParams(
            network: (u.queryParameters['type'] ?? 'tcp').toLowerCase(),
            path: pathVal.isNotEmpty ? pathVal : null,
            host: u.queryParameters['host'],
          );
          params = ProtocolParams(uuid: uuid);
        } else {
          final decoded = decodeBase64Safe(rawB64);
          if (decoded.isEmpty) return null;
          final cfg = jsonDecode(decoded) as Map<String, dynamic>;
          host = (cfg['add'] ?? cfg['host_ip'] ?? '').toString().trim().replaceAll(RegExp(r'^\[|\]$'), '');
          port = int.tryParse((cfg['port'] ?? '0').toString()) ?? 0;
          name = (cfg['ps'] ?? name).toString();
          final uuid = (cfg['id'] ?? '').toString().trim();
          if (uuid.isEmpty) return null;
          final sec = (cfg['tls'] ?? '').toString().toLowerCase();
          sni = (cfg['sni'] ?? cfg['host'] ?? '').toString().trim();
          pathVal = (cfg['path'] ?? '').toString();
          allowInsecure = _parseBoolFlag(cfg['allowInsecure']) || _parseBoolFlag(cfg['insecure']);
          tls = TlsParams(
            security: sec == 'tls' ? 'tls' : 'none',
            sni: sni.isNotEmpty ? sni : null,
            fingerprint: cfg['fp']?.toString(),
            alpn: cfg['alpn']?.toString().split(',').where((e) => e.trim().isNotEmpty).toList() ?? const [],
            allowInsecure: allowInsecure,
          );
          transport = TransportParams(
            network: (cfg['net'] ?? 'tcp').toString().toLowerCase(),
            path: pathVal.isNotEmpty ? pathVal : null,
            host: cfg['host']?.toString(),
            headerType: cfg['type']?.toString(),
          );
          params = ProtocolParams(
            uuid: uuid,
            alterId: int.tryParse((cfg['aid'] ?? '0').toString()) ?? 0,
            cipher: (cfg['scy'] ?? 'auto').toString(),
          );
        }
      } else if (rawProto == 'ss') {
        final rest = line.substring('ss://'.length);
        final hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) name = _safeDecode(rest.substring(hashIdx + 1));
        final noHash = hashIdx >= 0 ? rest.substring(0, hashIdx) : rest;
        final qIdx = noHash.indexOf('?');
        final mainPart = qIdx >= 0 ? noHash.substring(0, qIdx) : noHash;
        final queryPart = qIdx >= 0 ? noHash.substring(qIdx + 1) : '';
        String? pluginName;
        String? pluginOpts;
        if (queryPart.isNotEmpty) {
          final qp = Uri.splitQueryString(queryPart);
          final plugin = qp['plugin'];
          if (plugin != null && plugin.isNotEmpty) {
            final parts = plugin.split(';');
            pluginName = parts.first;
            if (parts.length > 1) pluginOpts = parts.sublist(1).join(';');
          }
        }

        final atIdx = mainPart.lastIndexOf('@');
        var hostPort = '';
        var cipher = '';
        var password = '';
        if (atIdx >= 0) {
          final userInfo = mainPart.substring(0, atIdx);
          hostPort = mainPart.substring(atIdx + 1);
          final decodedUser = userInfo.contains(':') ? _safeDecode(userInfo) : decodeBase64Safe(userInfo);
          final colonIdx = decodedUser.indexOf(':');
          if (colonIdx > 0) {
            cipher = decodedUser.substring(0, colonIdx);
            password = decodedUser.substring(colonIdx + 1);
          }
        } else {
          final decoded = decodeBase64Safe(mainPart);
          final dAt = decoded.lastIndexOf('@');
          if (dAt >= 0) {
            final cred = decoded.substring(0, dAt);
            hostPort = decoded.substring(dAt + 1);
            final colonIdx = cred.indexOf(':');
            if (colonIdx > 0) {
              cipher = cred.substring(0, colonIdx);
              password = cred.substring(colonIdx + 1);
            }
          }
        }

        hostPort = hostPort.replaceAll(RegExp(r'\/+$'), '');
        if (hostPort.startsWith('[')) {
          final closeIdx = hostPort.indexOf(']');
          if (closeIdx > 0) {
            host = hostPort.substring(1, closeIdx);
            port = int.tryParse(hostPort.substring(closeIdx + 2)) ?? 0;
          }
        } else {
          final colonIdx = hostPort.lastIndexOf(':');
          if (colonIdx > 0) {
            host = hostPort.substring(0, colonIdx);
            port = int.tryParse(hostPort.substring(colonIdx + 1)) ?? 0;
          }
        }
        if (cipher.isEmpty || password.isEmpty) return null;
        params = ProtocolParams(
          cipher: cipher,
          password: password,
          plugin: pluginName,
          pluginOpts: pluginOpts,
        );
      } else {
        final u = Uri.parse(line);
        host = u.host.replaceAll(RegExp(r'^\[|\]$'), '');
        port = u.hasPort ? u.port : 0;
        if (port == 0 && (rawProto == 'hy2' || rawProto == 'hysteria2')) {
          final mport = u.queryParameters['mport'] ?? '';
          final firstPort = RegExp(r'\d+').firstMatch(mport)?.group(0);
          port = firstPort != null ? int.parse(firstPort) : 443;
        }
        if (u.fragment.isNotEmpty) name = _safeDecode(u.fragment);

        final qp = u.queryParameters;
        final rawSec = (qp['security'] ?? '').toLowerCase();
        sni = qp['sni'] ?? qp['peer'] ?? qp['host'] ?? '';
        allowInsecure = _parseBoolFlag(qp['allowInsecure'] ?? qp['allow_insecure'] ?? qp['insecure']);
        final alpnList = qp['alpn']?.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? const <String>[];

        if (rawProto == 'vless') {
          final userParts = u.userInfo;
          final uuid = _safeDecode(userParts);
          if (uuid.isEmpty) return null;
          final sec = rawSec == 'reality' ? 'reality' : (rawSec == 'tls' ? 'tls' : 'none');
          if (sec == 'reality' && (qp['pbk'] == null || qp['pbk']!.isEmpty)) return null;
          tls = TlsParams(
            security: sec,
            sni: sni.isNotEmpty ? sni : null,
            fingerprint: qp['fp'],
            alpn: alpnList,
            realityPublicKey: qp['pbk'],
            realityShortId: qp['sid'],
            realitySpiderX: qp['spx'],
            allowInsecure: allowInsecure,
          );
          pathVal = qp['path'] ?? qp['serviceName'] ?? '';
          transport = TransportParams(
            network: (qp['type'] ?? 'tcp').toLowerCase(),
            path: qp['path'],
            host: qp['host'],
            serviceName: qp['serviceName'],
            headerType: qp['headerType'],
          );
          params = ProtocolParams(
            uuid: uuid,
            flow: qp['flow'],
            encryption: qp['encryption'] ?? 'none',
          );
        } else if (rawProto == 'trojan') {
          final password = _safeDecode(u.userInfo);
          if (password.isEmpty) return null;
          tls = TlsParams(
            security: rawSec == 'none' ? 'none' : 'tls',
            sni: sni.isNotEmpty ? sni : null,
            fingerprint: qp['fp'],
            alpn: alpnList,
            allowInsecure: allowInsecure,
          );
          pathVal = qp['path'] ?? qp['serviceName'] ?? '';
          transport = TransportParams(
            network: (qp['type'] ?? 'tcp').toLowerCase(),
            path: qp['path'],
            host: qp['host'],
            serviceName: qp['serviceName'],
          );
          params = ProtocolParams(password: password);
        } else if (rawProto == 'hy2' || rawProto == 'hysteria2') {
          final password = u.userInfo.isNotEmpty ? _safeDecode(u.userInfo) : (qp['auth'] ?? '');
          if (password.isEmpty) return null;
          tls = TlsParams(
            security: 'tls',
            sni: sni.isNotEmpty ? sni : null,
            alpn: alpnList,
            allowInsecure: allowInsecure,
          );
          params = ProtocolParams(
            password: password,
            obfs: qp['obfs'],
            obfsPassword: qp['obfs-password'],
            mport: qp['mport'],
            upMbps: int.tryParse(qp['upmbps'] ?? ''),
            downMbps: int.tryParse(qp['downmbps'] ?? ''),
          );
        } else if (rawProto == 'tuic') {
          final colon = u.userInfo.indexOf(':');
          final uuid = _safeDecode(colon >= 0 ? u.userInfo.substring(0, colon) : u.userInfo);
          final pass = colon >= 0 ? _safeDecode(u.userInfo.substring(colon + 1)) : '';
          if (uuid.isEmpty) return null;
          tls = TlsParams(
            security: 'tls',
            sni: sni.isNotEmpty ? sni : null,
            alpn: alpnList,
            allowInsecure: allowInsecure,
          );
          params = ProtocolParams(
            uuid: uuid,
            password: pass,
            congestionControl: (qp['congestion_control'] ?? 'bbr').toLowerCase(),
            udpRelayMode: (qp['udp_relay_mode'] ?? 'native').toLowerCase(),
            disableSni: _parseBoolFlag(qp['disable_sni']),
          );
        }
      }
    } catch (_) {
      return null;
    }

    if (host.isEmpty || port < 1 || port > 65535) return null;
    if (isPrivateOrInvalidHost(host)) return null;

    final hostLower = host.toLowerCase();
    if (!allowBlockedCountries &&
        (hostLower.endsWith('.ru') ||
            hostLower.endsWith('.by') ||
            hostLower.endsWith('.cn') ||
            hostLower.endsWith('.ir') ||
            hostLower.endsWith('.kp'))) {
      return null;
    }

    final country = CountryDetector.detect(name, host);
    if (!allowBlockedCountries && CountryDetector.blockedAiCountries.contains(country)) {
      return null;
    }

    final isUdp = protocol == VpnProtocol.hy2 || protocol == VpnProtocol.tuic;
    if (allowInsecure && !allowInsecureTls && (strictTls || !isUdp)) {
      return null;
    }

    double score = 0;
    switch (protocol) {
      case VpnProtocol.vless:
        score += tls.security == 'reality' ? 55 : (tls.security == 'tls' ? 38 : 12);
      case VpnProtocol.hy2:
        score += 36;
      case VpnProtocol.tuic:
        score += 34;
      case VpnProtocol.trojan:
        score += 28;
      case VpnProtocol.vmess:
        score += tls.security == 'tls' ? 20 : 8;
      case VpnProtocol.ss:
        score += 2;
    }
    if (allowInsecure) score -= 22;
    if (CountryDetector.euTier1.contains(country)) {
      score += 45;
    } else if (CountryDetector.euTier2.contains(country)) {
      score += 28;
    } else if (CountryDetector.aiTier3.contains(country)) {
      score += 14;
    }
    if (port == 443 || port == 8443 || port == 2053 || port == 2083 || port == 2087 || port == 2096) {
      score += 6;
    }

    final dedupKey = '$rawProto|$hostLower|$port|${sni.toLowerCase()}|$pathVal';
    return VpnProfile(
      id: id,
      groupId: groupId,
      name: name.isNotEmpty ? name : '$host:$port',
      protocol: protocol,
      address: host,
      port: port,
      rawUri: line,
      dedupKey: dedupKey,
      country: country,
      score: score,
      tls: tls,
      transport: transport,
      params: params,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
