import 'dart:async';

import '../models/vpn_models.dart';
import '../storage/secure_storage_service.dart';
import 'vpn_engine_interface.dart';

class VpnTunnelUnavailableException implements Exception {
  final String message;
  const VpnTunnelUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Clean VPN core coordinator separating lifecycle state, timeout validation,
/// reconnect debounce, and active proxy endpoint resolution from UI state.
class VpnCore {
  final VpnEngine engine;
  final DiagnosticsLogger logger;

  VpnConnectionState _state = VpnConnectionState.disconnected;
  int _cachedProxyPort = 2080;
  DateTime? _lastReconnectAt;
  Timer? _connectTimeoutTimer;
  String? lastError;

  final StreamController<VpnConnectionState> _stateController =
      StreamController<VpnConnectionState>.broadcast();

  StreamSubscription<VpnConnectionState>? _engineStateSub;
  StreamSubscription<TrafficStats>? _engineTrafficSub;
  StreamSubscription<String>? _engineLogSub;

  VpnCore({
    required this.engine,
    required this.logger,
  });

  VpnConnectionState get currentState => _state;
  bool get isConnected => _state == VpnConnectionState.connected;
  int get localProxyPort => _cachedProxyPort;

  Stream<VpnConnectionState> get stateStream => _stateController.stream;
  Stream<TrafficStats> get trafficStream => engine.trafficStream;

  Future<void> initialize({
    required void Function(VpnConnectionState state) onState,
    required void Function(TrafficStats stats) onTraffic,
    required void Function(String line) onLog,
  }) async {
    _state = await engine.queryCurrentState();
    _cachedProxyPort = await engine.getLocalProxyPort();
    onState(_state);

    _engineStateSub = engine.stateStream.listen((next) async {
      if (next != VpnConnectionState.connecting) {
        _connectTimeoutTimer?.cancel();
        _connectTimeoutTimer = null;
      }
      _state = next;
      if (next == VpnConnectionState.error) {
        final nativeErr = await engine.getLastError().catchError((_) => null);
        if (nativeErr != null && nativeErr.isNotEmpty) {
          lastError = DiagnosticsLogger.redactSecrets(nativeErr);
        }
        lastError ??= 'VPN core stopped with an error';
      } else if (next == VpnConnectionState.connected) {
        lastError = null;
      }
      _stateController.add(next);
      onState(next);
    });

    _engineTrafficSub = engine.trafficStream.listen(onTraffic);

    _engineLogSub = engine.logStream.listen((raw) {
      logger.add('INFO', 'libbox', raw);
      if (raw.toLowerCase().contains('error') || raw.toLowerCase().contains('fatal')) {
        lastError = DiagnosticsLogger.redactSecrets(raw);
      }
      onLog(raw);
    });
  }

  Future<String> getCoreVersion() => engine.getCoreVersion();

  Future<void> connect(
    VpnProfile profile,
    AppSettings settings, {
    Duration timeout = const Duration(seconds: 18),
  }) async {
    lastError = null;
    _setState(VpnConnectionState.connecting);
    logger.add(
      'INFO',
      'VpnCore',
      'Starting ${profile.protocol.name.toUpperCase()} tunnel to ${profile.address}:${profile.port}',
    );

    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(timeout, () async {
      if (_state == VpnConnectionState.connecting) {
        lastError = 'Tunnel handshake timed out (${timeout.inSeconds}s)';
        logger.add('ERROR', 'VpnCore', lastError!);
        _setState(VpnConnectionState.error);
        try {
          await engine.disconnect();
        } catch (_) {}
      }
    });

    try {
      await engine.connect(profile, settings);
      _cachedProxyPort = await engine.getLocalProxyPort();
      final reported = await engine.queryCurrentState();
      if (reported == VpnConnectionState.error) {
        throw const VpnTunnelUnavailableException('Native VPN core reported startup error');
      }
      if (reported == VpnConnectionState.connected) {
        _connectTimeoutTimer?.cancel();
        _setState(VpnConnectionState.connected);
      }
    } catch (e) {
      _connectTimeoutTimer?.cancel();
      lastError = DiagnosticsLogger.redactSecrets(e.toString());
      logger.add('ERROR', 'VpnCore', 'Connect failed: $lastError');
      _setState(VpnConnectionState.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    logger.add('INFO', 'VpnCore', 'Stopping VPN tunnel');
    await engine.disconnect();
    _setState(VpnConnectionState.disconnected);
  }

  Future<void> reconnect() async {
    final now = DateTime.now();
    if (_lastReconnectAt != null && now.difference(_lastReconnectAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastReconnectAt = now;
    _setState(VpnConnectionState.reconnecting);
    logger.add('INFO', 'VpnCore', 'Triggering tunnel reconnect');
    await engine.reconnect();
  }

  /// Resolves the active local `mixed-in` proxy port (`127.0.0.1:port`) when VPN
  /// is connected. Throws [VpnTunnelUnavailableException] if the tunnel is not
  /// active so in-app probes never silently fall back to direct ISP traffic.
  Future<int> requireActiveProxyPort() async {
    final liveState = await engine.queryCurrentState();
    _state = liveState;
    if (liveState != VpnConnectionState.connected) {
      throw const VpnTunnelUnavailableException(
        'VPN tunnel is not connected; refusing direct unencrypted check.',
      );
    }
    final port = await engine.getLocalProxyPort();
    if (port <= 0) {
      throw const VpnTunnelUnavailableException(
        'Local libbox proxy port is unavailable.',
      );
    }
    _cachedProxyPort = port;
    return port;
  }

  Future<bool> isAlwaysOnSupported() => engine.isAlwaysOnSupported();
  Future<bool> isLockdownEnabled() => engine.isLockdownEnabled();
  Future<void> openSystemVpnSettings() => engine.openSystemVpnSettings();

  void _setState(VpnConnectionState next) {
    _state = next;
    _stateController.add(next);
  }

  Future<void> dispose() async {
    _connectTimeoutTimer?.cancel();
    await _engineStateSub?.cancel();
    await _engineTrafficSub?.cancel();
    await _engineLogSub?.cancel();
    await _stateController.close();
  }
}
