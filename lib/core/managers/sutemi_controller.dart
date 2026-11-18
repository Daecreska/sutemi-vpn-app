import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../filter/smart_filter.dart';
import '../models/vpn_models.dart';
import '../network/ai_checker.dart';
import '../network/ping_tester.dart';
import '../parser/share_link_parser.dart';
import '../sources/builtin_sources.dart';
import '../storage/secure_storage_service.dart';
import '../vpn/vpn_core.dart';
import '../vpn/vpn_engine_interface.dart';

class SutemiController extends ChangeNotifier {
  final VpnCore vpnCore;
  final SecureStorageService storage;
  final DiagnosticsLogger logger;
  final PingTester pingTester = PingTester();

  VpnEngine get engine => vpnCore.engine;

  List<VpnProfile> profiles = [];
  List<ServerGroup> groups = [];
  AppSettings settings = const AppSettings();
  VpnConnectionState connectionState = VpnConnectionState.disconnected;
  TrafficStats trafficStats = const TrafficStats();
  AiCheckResult? aiResult;
  int? selectedProfileId;
  int? connectedProfileId;
  DateTime? connectedAt;
  String coreVersion = 'sing-box/libbox';
  String? errorMessage;

  bool isImporting = false;
  String importStatusLabel = '';
  bool isScanningPing = false;
  int scanDone = 0;
  int scanTotal = 0;
  int scanOnline = 0;
  bool isCheckingAi = false;
  bool isTestingSpeed = false;

  Timer? _durationTimer;
  Duration connectionDuration = Duration.zero;

  SutemiController({
    required this.vpnCore,
    required this.storage,
    required this.logger,
  });

  VpnProfile? get selectedProfile {
    if (profiles.isEmpty) return null;
    if (connectedProfileId != null && connectionState == VpnConnectionState.connected) {
      for (final p in profiles) {
        if (p.id == connectedProfileId) return p;
      }
    }
    if (selectedProfileId != null) {
      for (final p in profiles) {
        if (p.id == selectedProfileId) return p;
      }
    }
    return profiles.first;
  }

  Future<void> initialize() async {
    profiles = await storage.loadProfiles();
    groups = await storage.loadGroups();
    settings = await storage.loadSettings();
    selectedProfileId = await storage.loadSelectedProfileId();
    coreVersion = await vpnCore.getCoreVersion();

    await vpnCore.initialize(
      onState: (nextState) {
        connectionState = nextState;
        if (nextState == VpnConnectionState.connected) {
          errorMessage = null;
          connectedAt ??= DateTime.now();
          _startDurationTicker();
        } else if (nextState == VpnConnectionState.error) {
          _stopDurationTicker();
          connectedAt = null;
          connectionDuration = Duration.zero;
          trafficStats = const TrafficStats();
          errorMessage = vpnCore.lastError ?? 'Connection failed';
        } else if (nextState == VpnConnectionState.disconnected) {
          _stopDurationTicker();
          connectedAt = null;
          connectionDuration = Duration.zero;
          trafficStats = const TrafficStats();
        }
        notifyListeners();
      },
      onTraffic: (stats) {
        trafficStats = stats;
        notifyListeners();
      },
      onLog: (_) {
        notifyListeners();
      },
    );

    if (settings.autoConnect &&
        connectionState == VpnConnectionState.disconnected &&
        selectedProfile != null) {
      await connect();
    }
    notifyListeners();
  }

  void _startDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (connectedAt != null) {
        connectionDuration = DateTime.now().difference(connectedAt!);
        notifyListeners();
      }
    });
  }

  void _stopDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  Future<void> selectProfile(int id) async {
    selectedProfileId = id;
    await storage.saveSelectedProfileId(id);
    notifyListeners();
  }

  Future<void> connect([int? profileId]) async {
    final target = profileId != null
        ? profiles.firstWhere((p) => p.id == profileId, orElse: () => profiles.first)
        : selectedProfile;
    if (target == null) {
      errorMessage = 'Add a server first';
      notifyListeners();
      return;
    }

    errorMessage = null;
    connectedProfileId = target.id;
    selectedProfileId = target.id;
    aiResult = null;
    await storage.saveSelectedProfileId(target.id);

    connectionState = VpnConnectionState.connecting;
    notifyListeners();

    try {
      await vpnCore.connect(target, settings);
      connectionState = vpnCore.currentState;
      if (connectionState == VpnConnectionState.connected) {
        connectedAt = DateTime.now();
        _startDurationTicker();
      }
    } catch (e) {
      connectionState = VpnConnectionState.error;
      errorMessage = DiagnosticsLogger.redactSecrets(e.toString());
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await vpnCore.disconnect();
    connectionState = VpnConnectionState.disconnected;
    connectedProfileId = null;
    aiResult = null;
    errorMessage = null;
    _stopDurationTicker();
    connectionDuration = Duration.zero;
    trafficStats = const TrafficStats();
    notifyListeners();
  }

  Future<void> connectFastest() async {
    if (profiles.isEmpty) return;
    final sorted = [...profiles]..sort((a, b) {
        final la = (a.latencyMs != null && a.latencyMs! > 0) ? a.latencyMs! : 999999;
        final lb = (b.latencyMs != null && b.latencyMs! > 0) ? b.latencyMs! : 999999;
        return la.compareTo(lb);
      });
    await connect(sorted.first.id);
  }

  int _nextProfileId() =>
      profiles.isEmpty ? 1 : profiles.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1;

  int _nextGroupId() =>
      groups.isEmpty ? 1 : groups.map((g) => g.id).reduce((a, b) => a > b ? a : b) + 1;

  Future<String> importTextOrUrl(String input, {int? groupId}) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) throw ArgumentError('Paste a link or subscription URL');
    if (trimmed.length > 12 * 1024 * 1024) throw ArgumentError('Input exceeds 12 MB limit');

    if (RegExp(r'^https?:\/\/\S+$', caseSensitive: false).hasMatch(trimmed)) {
      final uri = Uri.parse(trimmed);
      final name = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? uri.host;
      return importSubscriptionUrl(url: trimmed, name: name);
    }

    isImporting = true;
    importStatusLabel = 'Parsing server configurations...';
    notifyListeners();

    try {
      final links = ShareLinkParser.extractShareLinks(trimmed) ?? const <String>[];
      if (links.isEmpty) throw StateError('No supported server links found');

      final gid = groupId ?? 0;
      var nextId = _nextProfileId();
      final existingKeys = profiles.map((p) => p.dedupKey).toSet();
      final added = <VpnProfile>[];

      if (settings.smartFilter && links.length > 50) {
        final curated = await SmartFilter.curate(
          rawLines: links,
          groupId: gid,
          startingId: nextId,
          strictTls: settings.strictTls,
        );
        for (final node in curated.selected) {
          if (existingKeys.add(node.dedupKey)) added.add(node);
        }
      } else {
        for (final line in links) {
          final parsed = ShareLinkParser.parse(
            line,
            id: nextId,
            groupId: gid,
            strictTls: settings.strictTls,
            allowBlockedCountries: !settings.smartFilter,
            allowInsecureTls: !settings.strictTls,
          );
          if (parsed != null && existingKeys.add(parsed.dedupKey)) {
            added.add(parsed);
            nextId++;
          }
        }
      }

      if (added.isEmpty) throw StateError('All servers were duplicates or rejected by filter');
      profiles = [...profiles, ...added];
      await storage.saveProfiles(profiles);
      logger.add('INFO', 'Import', 'Imported ${added.length} server(s)');
      return 'Imported ${added.length} server(s)';
    } finally {
      isImporting = false;
      importStatusLabel = '';
      notifyListeners();
    }
  }

  Future<String> addBuiltinSource(String sourceId) async {
    final src = kBuiltinSources.firstWhere((s) => s.id == sourceId);
    return importSubscriptionUrl(url: src.url, name: src.name, sourceId: src.id);
  }

  Future<String> importSubscriptionUrl({
    required String url,
    required String name,
    String? sourceId,
  }) async {
    isImporting = true;
    importStatusLabel = 'Downloading $name...';
    notifyListeners();

    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'SUTEMI-Mobile/1.0'},
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('Subscription HTTP ${res.statusCode}');
      }
      if (res.bodyBytes.length > 12 * 1024 * 1024) {
        throw StateError('Subscription exceeds 12 MB safety limit');
      }

      final links = ShareLinkParser.extractShareLinks(res.body);
      if (links == null || links.isEmpty) {
        throw StateError('No supported links found (previous servers kept)');
      }

      final existingGroup = groups.where((g) => g.url == url || g.name == name).firstOrNull;
      final gid = existingGroup?.id ?? _nextGroupId();

      importStatusLabel = 'Smart filtering ${links.length} servers...';
      notifyListeners();

      final curated = await SmartFilter.curate(
        rawLines: links,
        groupId: gid,
        startingId: _nextProfileId(),
        strictTls: settings.strictTls,
      );

      // Atomic update: never delete previously working servers if update returns 0 verified servers
      if (curated.selected.isEmpty) {
        throw StateError('No reachable servers found in update (previous servers kept)');
      }

      final updatedGroups = [...groups];
      final newGroup = ServerGroup(
        id: gid,
        name: name,
        url: url,
        sourceId: sourceId ?? existingGroup?.sourceId,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (existingGroup != null) {
        final idx = updatedGroups.indexWhere((g) => g.id == gid);
        updatedGroups[idx] = newGroup;
      } else {
        updatedGroups.add(newGroup);
      }

      final keptOthers = profiles.where((p) => p.groupId != gid).toList();
      profiles = [...keptOthers, ...curated.selected];
      groups = updatedGroups;
      await storage.saveGroups(groups);
      await storage.saveProfiles(profiles);

      logger.add('INFO', 'Subscription', 'Updated "$name": ${curated.selected.length} servers kept');
      return '$name: ${curated.selected.length} servers kept (${curated.aliveTcpCount} TCP-alive)';
    } finally {
      isImporting = false;
      importStatusLabel = '';
      notifyListeners();
    }
  }

  Future<void> runPingScan(List<VpnProfile> targets) async {
    if (isScanningPing || targets.isEmpty) return;
    isScanningPing = true;
    scanDone = 0;
    scanTotal = targets.length;
    scanOnline = 0;
    notifyListeners();

    try {
      final results = await pingTester.testProfiles(
        targets,
        onProgress: (p) {
          scanDone = p.done;
          scanTotal = p.total;
          scanOnline = p.onlineCount;
          for (final entry in p.latestResults.entries) {
            final idx = profiles.indexWhere((x) => x.id == entry.key);
            if (idx >= 0) profiles[idx] = profiles[idx].copyWith(latencyMs: entry.value);
          }
          notifyListeners();
        },
      );
      for (final entry in results.entries) {
        final idx = profiles.indexWhere((x) => x.id == entry.key);
        if (idx >= 0) profiles[idx] = profiles[idx].copyWith(latencyMs: entry.value);
      }
      await storage.saveProfiles(profiles);
    } finally {
      isScanningPing = false;
      notifyListeners();
    }
  }

  void cancelPingScan() {
    pingTester.cancel();
  }

  Future<void> deleteProfiles(Set<int> ids) async {
    if (connectedProfileId != null && ids.contains(connectedProfileId)) {
      await disconnect();
    }
    profiles = profiles.where((p) => !ids.contains(p.id)).toList();
    if (selectedProfileId != null && ids.contains(selectedProfileId)) {
      selectedProfileId = profiles.firstOrNull?.id;
      await storage.saveSelectedProfileId(selectedProfileId);
    }
    await storage.saveProfiles(profiles);
    notifyListeners();
  }

  Future<void> runAiAndSpeedCheck() async {
    if (connectionState != VpnConnectionState.connected || isCheckingAi) return;
    isCheckingAi = true;
    errorMessage = null;
    notifyListeners();
    try {
      final proxyPort = await vpnCore.requireActiveProxyPort();
      logger.add('INFO', 'Probe', 'Running Exit IP & AI check strictly through 127.0.0.1:$proxyPort');
      final res = await AiChecker.checkAll(
        activeProfileId: connectedProfileId,
        proxyPort: proxyPort,
        requireVpnProxy: true,
        includeSpeed: true,
      );
      aiResult = res;
      if (connectedProfileId != null) {
        final idx = profiles.indexWhere((p) => p.id == connectedProfileId);
        if (idx >= 0) {
          profiles[idx] = profiles[idx].copyWith(
            country: res.country.isNotEmpty ? res.country : profiles[idx].country,
            countryVerified: res.country.isNotEmpty,
            ipOut: res.exitIp,
            downloadBps: res.speedMbps != null ? (res.speedMbps! * 1e6).round() : profiles[idx].downloadBps,
          );
          await storage.saveProfiles(profiles);
        }
      }
    } catch (e) {
      errorMessage = DiagnosticsLogger.redactSecrets(e.toString());
      logger.add('ERROR', 'Probe', 'VPN tunnel probe failed: $errorMessage');
    } finally {
      isCheckingAi = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await storage.saveSettings(next);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopDurationTicker();
    vpnCore.dispose();
    super.dispose();
  }
}
