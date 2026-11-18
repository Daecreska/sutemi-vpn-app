import '../models/vpn_models.dart';

const List<BuiltinSource> kBuiltinSources = [
  BuiltinSource(
    id: 'radikal-top100',
    name: 'Raydikalx Top 100 (15m)',
    desc: '100 fastest 3x HTTP-verified nodes (every 15 min)',
    url: 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt',
  ),
  BuiltinSource(
    id: 'radikal-fast',
    name: 'Raydikalx Fast <800ms (15m)',
    desc: '750+ fast verified nodes <800ms (every 15 min)',
    url: 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/fast/configs.txt',
  ),
  BuiltinSource(
    id: 'radikal-secure',
    name: 'Raydikalx Secure TLS (15m)',
    desc: '1000+ verified Reality/TLS nodes (every 15 min)',
    url: 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/secure/configs.txt',
  ),
  BuiltinSource(
    id: 'openray-top100',
    name: 'OpenRay Top 100 (1h)',
    desc: 'Top 100 Xray/sing-box checked nodes (hourly)',
    url: 'https://raw.githubusercontent.com/sakha1370/OpenRay/refs/heads/main/output/main_top100_checked.txt',
  ),
  BuiltinSource(
    id: 'openray-valid',
    name: 'OpenRay Global Valid (1h)',
    desc: 'Full Xray-verified global pool (hourly)',
    url: 'https://raw.githubusercontent.com/sakha1370/OpenRay/refs/heads/main/output/all_valid_proxies.txt',
  ),
  BuiltinSource(
    id: 'delta-vless',
    name: 'Delta Xray-Tested VLESS',
    desc: '700+ Xray-validated VLESS & Reality nodes',
    url: 'https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/refs/heads/main/config/protocols/vless.txt',
  ),
  BuiltinSource(
    id: 'igareck-black-all',
    name: 'Igareck Black SS+All (RU)',
    desc: 'Most resilient multi-protocol mix for Russia (2-4h)',
    url: 'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS%2BAll_RUS.txt',
  ),
  BuiltinSource(
    id: 'igareck-black-vless',
    name: 'Igareck Black VLESS (RU)',
    desc: 'Full VLESS list tested in Russia (2-4h)',
    url: 'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt',
  ),
];
