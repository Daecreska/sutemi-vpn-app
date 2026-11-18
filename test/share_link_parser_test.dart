import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sutemi_vpn/core/geo/country_detector.dart';
import 'package:sutemi_vpn/core/models/vpn_models.dart';
import 'package:sutemi_vpn/core/parser/share_link_parser.dart';

void main() {
  group('ShareLinkParser', () {
    test('parses VLESS Reality with all transport and TLS fields', () {
      const uri =
          'vless://11111111-2222-3333-4444-555555555555@91.108.56.10:443?security=reality&encryption=none&pbk=PUBKEY123&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=www.microsoft.com&sid=ab12cd34&spx=%2F#🇩🇪 Frankfurt-Reality';
      final parsed = ShareLinkParser.parse(uri, id: 1, groupId: 1);
      expect(parsed, isNotNull);
      expect(parsed!.protocol, VpnProtocol.vless);
      expect(parsed.address, '91.108.56.10');
      expect(parsed.port, 443);
      expect(parsed.country, 'DE');
      expect(parsed.params.uuid, '11111111-2222-3333-4444-555555555555');
      expect(parsed.params.flow, 'xtls-rprx-vision');
      expect(parsed.tls.security, 'reality');
      expect(parsed.tls.sni, 'www.microsoft.com');
      expect(parsed.tls.realityPublicKey, 'PUBKEY123');
      expect(parsed.tls.realityShortId, 'ab12cd34');
      expect(parsed.tls.fingerprint, 'chrome');
    });

    test('parses VMess Base64 JSON, Trojan gRPC, SS SIP002, Hysteria2, and TUIC', () {
      final vmessB64 = base64Encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': '🇳🇱 Amsterdam WS',
        'add': 'nl.example.org',
        'port': '443',
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'aid': '0',
        'scy': 'auto',
        'net': 'ws',
        'path': '/ws-path',
        'host': 'cdn.example.org',
        'tls': 'tls',
        'sni': 'cdn.example.org',
      })));
      final vmess = ShareLinkParser.parse('vmess://$vmessB64', id: 2, groupId: 1);
      expect(vmess, isNotNull);
      expect(vmess!.protocol, VpnProtocol.vmess);
      expect(vmess.country, 'NL');
      expect(vmess.transport.network, 'ws');
      expect(vmess.transport.path, '/ws-path');

      final trojan = ShareLinkParser.parse(
        'trojan://secretpass99@fi.example.org:443?security=tls&type=grpc&serviceName=tun&sni=fi.example.org#🇫🇮 Helsinki',
        id: 3,
        groupId: 1,
      );
      expect(trojan, isNotNull);
      expect(trojan!.protocol, VpnProtocol.trojan);
      expect(trojan.country, 'FI');
      expect(trojan.transport.network, 'grpc');
      expect(trojan.transport.serviceName, 'tun');

      final ssCred = base64Encode(utf8.encode('aes-256-gcm:my-ss-pass'));
      final ss = ShareLinkParser.parse('ss://$ssCred@pl.example.org:8388#🇵🇱 Warsaw SS', id: 4, groupId: 1);
      expect(ss, isNotNull);
      expect(ss!.protocol, VpnProtocol.ss);
      expect(ss.params.cipher, 'aes-256-gcm');
      expect(ss.params.password, 'my-ss-pass');

      final hy2 = ShareLinkParser.parse(
        'hy2://hy2pass@se.example.org?mport=20000-20100&sni=se.example.org&obfs=salamander&obfs-password=obfpass&insecure=1#🇸🇪 Stockholm',
        id: 5,
        groupId: 1,
      );
      expect(hy2, isNotNull);
      expect(hy2!.protocol, VpnProtocol.hy2);
      expect(hy2.port, 20000);
      expect(hy2.params.obfs, 'salamander');

      final tuic = ShareLinkParser.parse(
        'tuic://cccccccc-dddd-eeee-ffff-000000000000:tuicpass@us.example.org:8443?congestion_control=bbr&udp_relay_mode=quic&sni=us.example.org&alpn=h3#🇺🇸 New York',
        id: 6,
        groupId: 1,
      );
      expect(tuic, isNotNull);
      expect(tuic!.protocol, VpnProtocol.tuic);
      expect(tuic.country, 'US');
      expect(tuic.tls.alpn, ['h3']);
    });

    test('Strict TLS rejects allowInsecure nodes and private/blocked hosts', () {
      const hy2Insecure = 'hy2://pass@de.example.org:443?sni=de.example.org&insecure=1#🇩🇪 DE-Insecure';
      expect(ShareLinkParser.parse(hy2Insecure, id: 1, groupId: 1, strictTls: false), isNotNull);
      expect(ShareLinkParser.parse(hy2Insecure, id: 1, groupId: 1, strictTls: true), isNull);

      expect(ShareLinkParser.isPrivateOrInvalidHost('127.0.0.1'), isTrue);
      expect(ShareLinkParser.isPrivateOrInvalidHost('10.10.0.1'), isTrue);
      expect(ShareLinkParser.isPrivateOrInvalidHost('192.168.1.5'), isTrue);
      expect(ShareLinkParser.isPrivateOrInvalidHost('91.108.56.10'), isFalse);

      expect(
        ShareLinkParser.parse(
          'vless://11111111-2222-3333-4444-555555555555@127.0.0.1:443?security=tls#DE',
          id: 1,
          groupId: 1,
        ),
        isNull,
      );
      expect(
        ShareLinkParser.parse(
          'vless://11111111-2222-3333-4444-555555555555@91.108.56.10:443?security=tls#🇷🇺 Moscow',
          id: 1,
          groupId: 1,
        ),
        isNull,
      );
    });

    test('extractShareLinks decodes base64 subscriptions and ignores YAML Clash configs', () {
      const raw = 'vless://11111111-2222-3333-4444-555555555555@91.108.56.10:443?security=tls#DE\n'
          'trojan://pass@91.108.56.20:443#PL';
      final encoded = base64Encode(utf8.encode(raw));
      final links = ShareLinkParser.extractShareLinks(encoded);
      expect(links, isNotNull);
      expect(links!.length, 2);

      expect(ShareLinkParser.extractShareLinks('mixed-port: 7890\nproxies:\n  - name: a'), isNull);
    });
  });

  group('CountryDetector', () {
    test('separates RU target audience markers from physical Russian endpoints', () {
      expect(CountryDetector.detect('BLACK_VLESS_RUS #12 Frankfurt'), 'DE');
      expect(CountryDetector.detect('FOR_RU_NL_Node'), 'NL');
      expect(CountryDetector.detect('🇷🇺 Moscow Fast'), 'RU');
      expect(CountryDetector.detect('Edge Node', 'fra.de'), 'DE');
    });
  });
}
