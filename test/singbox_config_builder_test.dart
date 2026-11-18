import 'package:flutter_test/flutter_test.dart';
import 'package:sutemi_vpn/core/models/vpn_models.dart';
import 'package:sutemi_vpn/core/parser/share_link_parser.dart';
import 'package:sutemi_vpn/core/vpn/singbox_config_builder.dart';

void main() {
  group('SingBoxConfigBuilder', () {
    final profile = ShareLinkParser.parse(
      'vless://11111111-2222-3333-4444-555555555555@91.108.56.10:443?security=reality&pbk=PUBKEY999&sid=1a2b&fp=chrome&flow=xtls-rprx-vision&sni=www.apple.com#🇩🇪 DE',
      id: 1,
      groupId: 1,
    )!;

    test('includes experimental.clash_api for libbox CommandServer stats and TUN + mixed inbounds', () {
      final cfg = SingBoxConfigBuilder.buildConfig(
        profile,
        const AppSettings(routingMode: RoutingMode.bypassLan),
        isIosOverride: false,
      );

      final experimental = cfg['experimental'] as Map<String, dynamic>?;
      expect(experimental, isNotNull);
      expect((experimental!['clash_api'] as Map<String, dynamic>)['default_mode'], 'rule');

      final inbounds = cfg['inbounds'] as List<dynamic>;
      expect((inbounds[0] as Map<String, dynamic>)['type'], 'tun');
      expect((inbounds[0] as Map<String, dynamic>)['interface_name'], 'tun0');
      expect((inbounds[1] as Map<String, dynamic>)['type'], 'mixed');
      expect((inbounds[1] as Map<String, dynamic>)['listen_port'], 2080);

      final outbounds = cfg['outbounds'] as List<dynamic>;
      final proxy = outbounds.first as Map<String, dynamic>;
      expect(proxy['type'], 'vless');
      expect(proxy['uuid'], '11111111-2222-3333-4444-555555555555');
    });

    test('declares remote binary rule_set definitions when routingMode is bypassRuCn', () {
      final cfg = SingBoxConfigBuilder.buildConfig(
        profile,
        const AppSettings(routingMode: RoutingMode.bypassRuCn),
        isIosOverride: true,
      );

      final route = cfg['route'] as Map<String, dynamic>;
      final ruleSets = route['rule_set'] as List<dynamic>?;
      expect(ruleSets, isNotNull);
      expect(ruleSets!.length, 2);

      final inbounds = cfg['inbounds'] as List<dynamic>;
      expect((inbounds[0] as Map<String, dynamic>)['stack'], 'gvisor');
      expect((inbounds[0] as Map<String, dynamic>)['mtu'], 4064);
    });
  });
}
