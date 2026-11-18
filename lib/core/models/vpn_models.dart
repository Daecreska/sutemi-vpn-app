enum VpnProtocol { vless, vmess, trojan, ss, hy2, tuic }

enum VpnConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

enum RoutingMode { global, bypassLan, bypassRuCn }

enum DisconnectBehavior { blockLeak, reconnectLoop, fallbackDirect }

enum AiServiceStatus {
  available,
  regionRestricted,
  authRequired,
  challenge,
  connectionError,
  unknown,
}

class TransportParams {
  final String network;
  final String? path;
  final String? host;
  final String? serviceName;
  final String? headerType;

  const TransportParams({
    this.network = 'tcp',
    this.path,
    this.host,
    this.serviceName,
    this.headerType,
  });

  Map<String, dynamic> toJson() => {
        'network': network,
        if (path != null) 'path': path,
        if (host != null) 'host': host,
        if (serviceName != null) 'serviceName': serviceName,
        if (headerType != null) 'headerType': headerType,
      };

  factory TransportParams.fromJson(Map<String, dynamic> json) => TransportParams(
        network: (json['network'] as String?) ?? 'tcp',
        path: json['path'] as String?,
        host: json['host'] as String?,
        serviceName: json['serviceName'] as String?,
        headerType: json['headerType'] as String?,
      );
}

class TlsParams {
  final String security; // none | tls | reality
  final String? sni;
  final List<String> alpn;
  final String? fingerprint;
  final String? realityPublicKey;
  final String? realityShortId;
  final String? realitySpiderX;
  final bool allowInsecure;

  const TlsParams({
    this.security = 'none',
    this.sni,
    this.alpn = const [],
    this.fingerprint,
    this.realityPublicKey,
    this.realityShortId,
    this.realitySpiderX,
    this.allowInsecure = false,
  });

  Map<String, dynamic> toJson() => {
        'security': security,
        if (sni != null) 'sni': sni,
        if (alpn.isNotEmpty) 'alpn': alpn,
        if (fingerprint != null) 'fingerprint': fingerprint,
        if (realityPublicKey != null) 'realityPublicKey': realityPublicKey,
        if (realityShortId != null) 'realityShortId': realityShortId,
        if (realitySpiderX != null) 'realitySpiderX': realitySpiderX,
        'allowInsecure': allowInsecure,
      };

  factory TlsParams.fromJson(Map<String, dynamic> json) => TlsParams(
        security: (json['security'] as String?) ?? 'none',
        sni: json['sni'] as String?,
        alpn: (json['alpn'] as List<dynamic>?)?.cast<String>() ?? const [],
        fingerprint: json['fingerprint'] as String?,
        realityPublicKey: json['realityPublicKey'] as String?,
        realityShortId: json['realityShortId'] as String?,
        realitySpiderX: json['realitySpiderX'] as String?,
        allowInsecure: (json['allowInsecure'] as bool?) ?? false,
      );
}

class ProtocolParams {
  final String? uuid;
  final String? password;
  final String? flow;
  final String? encryption;
  final int alterId;
  final String? cipher;
  final String? plugin;
  final String? pluginOpts;
  final String? obfs;
  final String? obfsPassword;
  final String? mport;
  final int? upMbps;
  final int? downMbps;
  final String congestionControl;
  final String udpRelayMode;
  final bool disableSni;

  const ProtocolParams({
    this.uuid,
    this.password,
    this.flow,
    this.encryption,
    this.alterId = 0,
    this.cipher,
    this.plugin,
    this.pluginOpts,
    this.obfs,
    this.obfsPassword,
    this.mport,
    this.upMbps,
    this.downMbps,
    this.congestionControl = 'bbr',
    this.udpRelayMode = 'native',
    this.disableSni = false,
  });

  Map<String, dynamic> toJson() => {
        if (uuid != null) 'uuid': uuid,
        if (password != null) 'password': password,
        if (flow != null) 'flow': flow,
        if (encryption != null) 'encryption': encryption,
        'alterId': alterId,
        if (cipher != null) 'cipher': cipher,
        if (plugin != null) 'plugin': plugin,
        if (pluginOpts != null) 'pluginOpts': pluginOpts,
        if (obfs != null) 'obfs': obfs,
        if (obfsPassword != null) 'obfsPassword': obfsPassword,
        if (mport != null) 'mport': mport,
        if (upMbps != null) 'upMbps': upMbps,
        if (downMbps != null) 'downMbps': downMbps,
        'congestionControl': congestionControl,
        'udpRelayMode': udpRelayMode,
        'disableSni': disableSni,
      };

  factory ProtocolParams.fromJson(Map<String, dynamic> json) => ProtocolParams(
        uuid: json['uuid'] as String?,
        password: json['password'] as String?,
        flow: json['flow'] as String?,
        encryption: json['encryption'] as String?,
        alterId: (json['alterId'] as int?) ?? 0,
        cipher: json['cipher'] as String?,
        plugin: json['plugin'] as String?,
        pluginOpts: json['pluginOpts'] as String?,
        obfs: json['obfs'] as String?,
        obfsPassword: json['obfsPassword'] as String?,
        mport: json['mport'] as String?,
        upMbps: json['upMbps'] as int?,
        downMbps: json['downMbps'] as int?,
        congestionControl: (json['congestionControl'] as String?) ?? 'bbr',
        udpRelayMode: (json['udpRelayMode'] as String?) ?? 'native',
        disableSni: (json['disableSni'] as bool?) ?? false,
      );
}

class VpnProfile {
  final int id;
  final int groupId;
  final String name;
  final VpnProtocol protocol;
  final String address;
  final int port;
  final String rawUri;
  final String dedupKey;
  final String country;
  final bool countryVerified;
  final String ipOut;
  final int? latencyMs;
  final int downloadBps;
  final int uploadBps;
  final double score;
  final TlsParams tls;
  final TransportParams transport;
  final ProtocolParams params;
  final int createdAt;

  const VpnProfile({
    required this.id,
    required this.groupId,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
    required this.rawUri,
    required this.dedupKey,
    required this.country,
    this.countryVerified = false,
    this.ipOut = '',
    this.latencyMs,
    this.downloadBps = 0,
    this.uploadBps = 0,
    this.score = 0,
    required this.tls,
    required this.transport,
    required this.params,
    required this.createdAt,
  });

  VpnProfile copyWith({
    int? groupId,
    String? name,
    String? country,
    bool? countryVerified,
    String? ipOut,
    int? latencyMs,
    int? downloadBps,
    int? uploadBps,
  }) =>
      VpnProfile(
        id: id,
        groupId: groupId ?? this.groupId,
        name: name ?? this.name,
        protocol: protocol,
        address: address,
        port: port,
        rawUri: rawUri,
        dedupKey: dedupKey,
        country: country ?? this.country,
        countryVerified: countryVerified ?? this.countryVerified,
        ipOut: ipOut ?? this.ipOut,
        latencyMs: latencyMs ?? this.latencyMs,
        downloadBps: downloadBps ?? this.downloadBps,
        uploadBps: uploadBps ?? this.uploadBps,
        score: score,
        tls: tls,
        transport: transport,
        params: params,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'name': name,
        'protocol': protocol.name,
        'address': address,
        'port': port,
        'rawUri': rawUri,
        'dedupKey': dedupKey,
        'country': country,
        'countryVerified': countryVerified,
        'ipOut': ipOut,
        'latencyMs': latencyMs,
        'downloadBps': downloadBps,
        'uploadBps': uploadBps,
        'score': score,
        'tls': tls.toJson(),
        'transport': transport.toJson(),
        'params': params.toJson(),
        'createdAt': createdAt,
      };

  factory VpnProfile.fromJson(Map<String, dynamic> json) => VpnProfile(
        id: json['id'] as int,
        groupId: json['groupId'] as int,
        name: json['name'] as String,
        protocol: VpnProtocol.values.byName(json['protocol'] as String),
        address: json['address'] as String,
        port: json['port'] as int,
        rawUri: json['rawUri'] as String,
        dedupKey: json['dedupKey'] as String,
        country: (json['country'] as String?) ?? 'WW',
        countryVerified: (json['countryVerified'] as bool?) ?? false,
        ipOut: (json['ipOut'] as String?) ?? '',
        latencyMs: json['latencyMs'] as int?,
        downloadBps: (json['downloadBps'] as int?) ?? 0,
        uploadBps: (json['uploadBps'] as int?) ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
        tls: TlsParams.fromJson(json['tls'] as Map<String, dynamic>),
        transport: TransportParams.fromJson(json['transport'] as Map<String, dynamic>),
        params: ProtocolParams.fromJson(json['params'] as Map<String, dynamic>),
        createdAt: (json['createdAt'] as int?) ?? 0,
      );
}

class ServerGroup {
  final int id;
  final String name;
  final String url;
  final String? sourceId;
  final int updatedAt;

  const ServerGroup({
    required this.id,
    required this.name,
    required this.url,
    this.sourceId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (sourceId != null) 'sourceId': sourceId,
        'updatedAt': updatedAt,
      };

  factory ServerGroup.fromJson(Map<String, dynamic> json) => ServerGroup(
        id: json['id'] as int,
        name: json['name'] as String,
        url: (json['url'] as String?) ?? '',
        sourceId: json['sourceId'] as String?,
        updatedAt: (json['updatedAt'] as int?) ?? 0,
      );
}

class BuiltinSource {
  final String id;
  final String name;
  final String desc;
  final String url;

  const BuiltinSource({
    required this.id,
    required this.name,
    required this.desc,
    required this.url,
  });
}

class TrafficStats {
  final int downloadBps;
  final int uploadBps;
  final int totalDownBytes;
  final int totalUpBytes;

  const TrafficStats({
    this.downloadBps = 0,
    this.uploadBps = 0,
    this.totalDownBytes = 0,
    this.totalUpBytes = 0,
  });
}

class AiServiceReport {
  final AiServiceStatus status;
  final int ms;
  final String reason;
  final String note;

  const AiServiceReport({
    required this.status,
    required this.ms,
    required this.reason,
    required this.note,
  });
}

class AiCheckResult {
  final bool networkReachable;
  final int? profileId;
  final String exitIp;
  final String country;
  final double? speedMbps;
  final AiServiceReport gemini;
  final AiServiceReport aiStudio;
  final AiServiceReport chatGpt;
  final AiServiceReport claude;

  const AiCheckResult({
    required this.networkReachable,
    required this.profileId,
    required this.exitIp,
    required this.country,
    this.speedMbps,
    required this.gemini,
    required this.aiStudio,
    required this.chatGpt,
    required this.claude,
  });
}

class AppSettings {
  final bool autoConnect;
  final bool autoReconnect;
  final DisconnectBehavior disconnectBehavior;
  final RoutingMode routingMode;
  final String dnsPrimary;
  final String dnsSecondary;
  final bool notificationsEnabled;
  final bool smartFilter;
  final bool strictTls;
  final bool alwaysOnAndroid;
  final bool lockdownAndroid;

  const AppSettings({
    this.autoConnect = false,
    this.autoReconnect = true,
    this.disconnectBehavior = DisconnectBehavior.blockLeak,
    this.routingMode = RoutingMode.bypassLan,
    this.dnsPrimary = 'https://1.1.1.1/dns-query',
    this.dnsSecondary = '223.5.5.5',
    this.notificationsEnabled = true,
    this.smartFilter = true,
    this.strictTls = false,
    this.alwaysOnAndroid = false,
    this.lockdownAndroid = false,
  });

  AppSettings copyWith({
    bool? autoConnect,
    bool? autoReconnect,
    DisconnectBehavior? disconnectBehavior,
    RoutingMode? routingMode,
    String? dnsPrimary,
    String? dnsSecondary,
    bool? notificationsEnabled,
    bool? smartFilter,
    bool? strictTls,
    bool? alwaysOnAndroid,
    bool? lockdownAndroid,
  }) =>
      AppSettings(
        autoConnect: autoConnect ?? this.autoConnect,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        disconnectBehavior: disconnectBehavior ?? this.disconnectBehavior,
        routingMode: routingMode ?? this.routingMode,
        dnsPrimary: dnsPrimary ?? this.dnsPrimary,
        dnsSecondary: dnsSecondary ?? this.dnsSecondary,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        smartFilter: smartFilter ?? this.smartFilter,
        strictTls: strictTls ?? this.strictTls,
        alwaysOnAndroid: alwaysOnAndroid ?? this.alwaysOnAndroid,
        lockdownAndroid: lockdownAndroid ?? this.lockdownAndroid,
      );

  Map<String, dynamic> toJson() => {
        'autoConnect': autoConnect,
        'autoReconnect': autoReconnect,
        'disconnectBehavior': disconnectBehavior.name,
        'routingMode': routingMode.name,
        'dnsPrimary': dnsPrimary,
        'dnsSecondary': dnsSecondary,
        'notificationsEnabled': notificationsEnabled,
        'smartFilter': smartFilter,
        'strictTls': strictTls,
        'alwaysOnAndroid': alwaysOnAndroid,
        'lockdownAndroid': lockdownAndroid,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        autoConnect: (json['autoConnect'] as bool?) ?? false,
        autoReconnect: (json['autoReconnect'] as bool?) ?? true,
        disconnectBehavior: DisconnectBehavior.values.firstWhere(
          (e) => e.name == json['disconnectBehavior'],
          orElse: () => DisconnectBehavior.blockLeak,
        ),
        routingMode: RoutingMode.values.firstWhere(
          (e) => e.name == json['routingMode'],
          orElse: () => RoutingMode.bypassLan,
        ),
        dnsPrimary: (json['dnsPrimary'] as String?) ?? 'https://1.1.1.1/dns-query',
        dnsSecondary: (json['dnsSecondary'] as String?) ?? '223.5.5.5',
        notificationsEnabled: (json['notificationsEnabled'] as bool?) ?? true,
        smartFilter: (json['smartFilter'] as bool?) ?? true,
        strictTls: (json['strictTls'] as bool?) ?? false,
        alwaysOnAndroid: (json['alwaysOnAndroid'] as bool?) ?? false,
        lockdownAndroid: (json['lockdownAndroid'] as bool?) ?? false,
      );
}
