import 'dart:async';
import 'package:flutter/services.dart';

import '../models/vpn_models.dart';
import 'singbox_config_builder.dart';
import 'vpn_engine_interface.dart';

class LibboxVpnEngine implements VpnEngine {
  static const MethodChannel _control = MethodChannel('sutemi.vpn/control');
  static const EventChannel _stateEvents = EventChannel('sutemi.vpn/state');
  static const EventChannel _trafficEvents = EventChannel('sutemi.vpn/traffic');
  static const EventChannel _logEvents = EventChannel('sutemi.vpn/logs');

  @override
  Stream<VpnConnectionState> get stateStream =>
      _stateEvents.receiveBroadcastStream().map((raw) {
        final s = raw?.toString().toLowerCase() ?? 'disconnected';
        return VpnConnectionState.values.firstWhere(
          (e) => e.name == s,
          orElse: () => VpnConnectionState.disconnected,
        );
      });

  @override
  Stream<TrafficStats> get trafficStream =>
      _trafficEvents.receiveBroadcastStream().map((raw) {
        if (raw is Map) {
          return TrafficStats(
            downloadBps: (raw['downBps'] as num?)?.toInt() ?? 0,
            uploadBps: (raw['upBps'] as num?)?.toInt() ?? 0,
            totalDownBytes: (raw['totalDown'] as num?)?.toInt() ?? 0,
            totalUpBytes: (raw['totalUp'] as num?)?.toInt() ?? 0,
          );
        }
        return const TrafficStats();
      });

  @override
  Stream<String> get logStream =>
      _logEvents.receiveBroadcastStream().map((raw) => raw?.toString() ?? '');

  @override
  Future<String> getCoreVersion() async {
    final res = await _control.invokeMethod<String>('getCoreVersion');
    return res ?? 'sing-box/libbox';
  }

  @override
  Future<void> connect(VpnProfile profile, AppSettings settings) async {
    final configJson = SingBoxConfigBuilder.buildJson(profile, settings, mixedPort: 2080);
    await _control.invokeMethod<void>('connect', {
      'profileId': profile.id,
      'profileName': profile.name,
      'serverHost': profile.address,
      'configJson': configJson,
      'autoReconnect': settings.autoReconnect,
      'disconnectBehavior': settings.disconnectBehavior.name,
      'notificationsEnabled': settings.notificationsEnabled,
    });
  }

  @override
  Future<void> disconnect() async {
    await _control.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> reconnect() async {
    await _control.invokeMethod<void>('reconnect');
  }

  @override
  Future<VpnConnectionState> queryCurrentState() async {
    final s = await _control.invokeMethod<String>('getState') ?? 'disconnected';
    return VpnConnectionState.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => VpnConnectionState.disconnected,
    );
  }

  @override
  Future<String?> getLastError() async {
    return _control.invokeMethod<String>('getLastError');
  }

  @override
  Future<bool> isAlwaysOnSupported() async {
    return (await _control.invokeMethod<bool>('isAlwaysOnSupported')) ?? false;
  }

  @override
  Future<bool> isLockdownEnabled() async {
    return (await _control.invokeMethod<bool>('isLockdownEnabled')) ?? false;
  }

  @override
  Future<void> openSystemVpnSettings() async {
    await _control.invokeMethod<void>('openSystemVpnSettings');
  }

  @override
  Future<int> getLocalProxyPort() async {
    return (await _control.invokeMethod<int>('getLocalProxyPort')) ?? 2080;
  }
}
