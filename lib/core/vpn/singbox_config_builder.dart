import 'dart:convert';
import 'dart:io';

import '../models/vpn_models.dart';

class SingBoxConfigBuilder {
  static Map<String, dynamic> buildConfig(
    VpnProfile profile,
    AppSettings settings, {
    int mixedPort = 2080,
    bool? isIosOverride,
  }) {
    final isIos = isIosOverride ?? Platform.isIOS;
    final outbound = _buildOutbound(profile, settings.strictTls);

    final routeRules = <Map<String, dynamic>>[
      {'protocol': 'dns', 'action': 'hijack-dns'},
    ];
    final ruleSets = <Map<String, dynamic>>[];

    if (settings.routingMode == RoutingMode.bypassLan) {
      routeRules.add({'ip_is_private': true, 'outbound': 'direct'});
    } else if (settings.routingMode == RoutingMode.bypassRuCn) {
      routeRules.add({'ip_is_private': true, 'outbound': 'direct'});
      routeRules.add({
        'rule_set': ['geosite-ru', 'geosite-cn'],
        'outbound': 'direct',
      });
      ruleSets.addAll([
        {
          'tag': 'geosite-ru',
          'type': 'remote',
          'format': 'binary',
          'url': 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs',
          'download_detour': 'proxy',
        },
        {
          'tag': 'geosite-cn',
          'type': 'remote',
          'format': 'binary',
          'url': 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs',
          'download_detour': 'proxy',
        },
      ]);
    }

    return {
      'log': {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          {
            'tag': 'dns-remote',
            'address': settings.dnsPrimary.isNotEmpty ? settings.dnsPrimary : 'https://1.1.1.1/dns-query',
            'detour': 'proxy',
          },
          {
            'tag': 'dns-direct',
            'address': settings.dnsSecondary.isNotEmpty ? settings.dnsSecondary : '223.5.5.5',
            'detour': 'direct',
          },
        ],
        'rules': [
          {'outbound': 'any', 'server': 'dns-direct'},
        ],
        'strategy': 'prefer_ipv4',
        'final': 'dns-remote',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': isIos ? 'utun' : 'tun0',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          'mtu': isIos ? 4064 : 9000,
          'auto_route': true,
          'strict_route': !isIos && settings.lockdownAndroid,
          'stack': isIos ? 'gvisor' : 'system',
          'sniff': true,
        },
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': mixedPort,
        },
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {
        'rules': routeRules,
        if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
        'auto_detect_interface': !isIos,
        'final': 'proxy',
      },
      // Required so libbox CommandServer attaches ClashServer TrafficManager
      // and avoids nil dereference in CommandServer.SetService().
      'experimental': {
        'clash_api': {
          'default_mode': 'rule',
        },
      },
    };
  }

  static String buildJson(
    VpnProfile profile,
    AppSettings settings, {
    int mixedPort = 2080,
    bool? isIosOverride,
  }) =>
      jsonEncode(
        buildConfig(
          profile,
          settings,
          mixedPort: mixedPort,
          isIosOverride: isIosOverride,
        ),
      );

  static Map<String, dynamic> _buildOutbound(VpnProfile p, bool strictTls) {
    final tlsBlock = _buildTls(p, strictTls);
    final transportBlock = _buildTransport(p.transport);

    switch (p.protocol) {
      case VpnProtocol.vless:
        return {
          'type': 'vless',
          'tag': 'proxy',
          'server': p.address,
          'server_port': p.port,
          'uuid': p.params.uuid,
          if (p.params.flow != null && p.params.flow!.isNotEmpty) 'flow': p.params.flow,
          if (tlsBlock != null) 'tls': tlsBlock,
          if (transportBlock != null) 'transport': transportBlock,
        };
      case VpnProtocol.vmess:
        return {
          'type': 'vmess',
          'tag': 'proxy',
          'server': p.address,
          'server_port': p.port,
          'uuid': p.params.uuid,
          'security': p.params.cipher ?? 'auto',
          'alter_id': p.params.alterId,
          if (tlsBlock != null) 'tls': tlsBlock,
          if (transportBlock != null) 'transport': transportBlock,
        };
      case VpnProtocol.trojan:
        return {
          'type': 'trojan',
          'tag': 'proxy',
          'server': p.address,
          'server_port': p.port,
          'password': p.params.password,
          if (tlsBlock != null) 'tls': tlsBlock,
          if (transportBlock != null) 'transport': transportBlock,
        };
      case VpnProtocol.ss:
        return {
          'type': 'shadowsocks',
          'tag': 'proxy',
          'server': p.address,
          'server_port': p.port,
          'method': p.params.cipher,
          'password': p.params.password,
          if (p.params.plugin != null) ...{
            'plugin': p.params.plugin,
            'plugin_opts': p.params.pluginOpts ?? '',
          },
        };
      case VpnProtocol.hy2:
        return {
          'type': 'hysteria2',
          'tag': 'proxy',
          'server': p.address,
          'server_port': p.port,
          'password': p.params.password,
          if (p.params.upMbps != null) 'up_mbps': p.params.upMbps,
          if (p.params.downMbps != null) 'down_mbps': p.params.downMbps,
          if (p.params.obfs != null)
            'obfs': {
              'type': p.params.obfs,
              'password': p.params.obfsPassword ?? '',
            },
          'tls': tlsBlock ??
              {
                'enabled': true,
                'server_name': p.address,
                'insecure': strictTls ? false : p.tls.allowInsecure,
              },
        };
      case VpnProtocol.tuic:
        return {
          'type': 'tuic',
          'tag': 'proxy',
          'server': p.address,
          'server_port': p.port,
          'uuid': p.params.uuid,
          'password': p.params.password ?? '',
          'congestion_control': p.params.congestionControl,
          'udp_relay_mode': p.params.udpRelayMode,
          'tls': tlsBlock ??
              {
                'enabled': true,
                'server_name': p.address,
                'insecure': strictTls ? false : p.tls.allowInsecure,
              },
        };
    }
  }

  static Map<String, dynamic>? _buildTls(VpnProfile p, bool strictTls) {
    if (p.tls.security == 'none') return null;
    final map = <String, dynamic>{
      'enabled': true,
      'server_name': p.tls.sni ?? p.address,
      'insecure': strictTls ? false : p.tls.allowInsecure,
    };
    if (p.tls.alpn.isNotEmpty) map['alpn'] = p.tls.alpn;
    if (p.tls.fingerprint != null && p.tls.fingerprint!.isNotEmpty) {
      map['utls'] = {'enabled': true, 'fingerprint': p.tls.fingerprint};
    }
    if (p.tls.security == 'reality') {
      map['reality'] = {
        'enabled': true,
        'public_key': p.tls.realityPublicKey,
        'short_id': p.tls.realityShortId ?? '',
      };
    }
    return map;
  }

  static Map<String, dynamic>? _buildTransport(TransportParams t) {
    if (t.network == 'tcp') return null;
    if (t.network == 'ws') {
      return {
        'type': 'ws',
        'path': t.path ?? '/',
        if (t.host != null && t.host!.isNotEmpty) 'headers': {'Host': t.host},
      };
    }
    if (t.network == 'grpc') {
      return {
        'type': 'grpc',
        'service_name': t.serviceName ?? t.path ?? '',
      };
    }
    if (t.network == 'httpupgrade') {
      return {
        'type': 'httpupgrade',
        'path': t.path ?? '/',
        if (t.host != null && t.host!.isNotEmpty) 'host': t.host,
      };
    }
    if (t.network == 'http') {
      return {
        'type': 'http',
        'path': t.path ?? '/',
        if (t.host != null && t.host!.isNotEmpty) 'host': [t.host],
      };
    }
    return null;
  }
}
