import '../models/vpn_models.dart';

abstract class VpnEngine {
  Stream<VpnConnectionState> get stateStream;
  Stream<TrafficStats> get trafficStream;
  Stream<String> get logStream;

  Future<String> getCoreVersion();
  Future<void> connect(VpnProfile profile, AppSettings settings);
  Future<void> disconnect();
  Future<void> reconnect();
  Future<VpnConnectionState> queryCurrentState();
  Future<String?> getLastError();
  Future<bool> isAlwaysOnSupported();
  Future<bool> isLockdownEnabled();
  Future<void> openSystemVpnSettings();
  Future<int> getLocalProxyPort();
}
