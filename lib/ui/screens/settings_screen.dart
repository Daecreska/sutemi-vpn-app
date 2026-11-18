import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/managers/sutemi_controller.dart';
import '../../core/models/vpn_models.dart';
import '../theme/sutemi_theme.dart';

class SettingsScreen extends StatefulWidget {
  final SutemiController controller;
  const SettingsScreen({super.key, required this.controller});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _alwaysOnSupported = false;
  bool _lockdownEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPlatformCapabilities();
  }

  Future<void> _loadPlatformCapabilities() async {
    final alwaysOn = await widget.controller.engine.isAlwaysOnSupported();
    final lockdown = await widget.controller.engine.isLockdownEnabled();
    if (mounted) {
      setState(() {
        _alwaysOnSupported = alwaysOn;
        _lockdownEnabled = lockdown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.settings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const Text('Settings & Diagnostics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        GlassCard(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Auto-connect on launch'),
                value: s.autoConnect,
                onChanged: (v) => widget.controller.updateSettings(s.copyWith(autoConnect: v)),
              ),
              SwitchListTile(
                title: const Text('Auto-reconnect on network drop'),
                subtitle: const Text('Handles Wi-Fi ↔ Cellular handoff'),
                value: s.autoReconnect,
                onChanged: (v) => widget.controller.updateSettings(s.copyWith(autoReconnect: v)),
              ),
              SwitchListTile(
                title: const Text('Strict TLS (reject insecure HY2/TUIC)'),
                value: s.strictTls,
                onChanged: (v) => widget.controller.updateSettings(s.copyWith(strictTls: v)),
              ),
              SwitchListTile(
                title: const Text('Persistent VPN notifications'),
                value: s.notificationsEnabled,
                onChanged: (v) => widget.controller.updateSettings(s.copyWith(notificationsEnabled: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ROUTING & DNS', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: SutemiColors.textSecondary)),
              const SizedBox(height: 10),
              SegmentedButton<RoutingMode>(
                segments: const [
                  ButtonSegment(value: RoutingMode.global, label: Text('Global')),
                  ButtonSegment(value: RoutingMode.bypassLan, label: Text('Bypass LAN')),
                  ButtonSegment(value: RoutingMode.bypassRuCn, label: Text('Bypass RU/CN')),
                ],
                selected: {s.routingMode},
                onSelectionChanged: (next) => widget.controller.updateSettings(s.copyWith(routingMode: next.first)),
              ),
              const SizedBox(height: 12),
              Text('Primary DNS: ${s.dnsPrimary}', style: const TextStyle(fontSize: 12)),
              Text('Bootstrap DNS: ${s.dnsSecondary}', style: const TextStyle(fontSize: 12, color: SutemiColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isAndroid ? 'ANDROID SYSTEM VPN' : 'IOS NETWORK EXTENSION',
                style: const TextStyle(fontSize: 10, letterSpacing: 1.5, color: SutemiColors.textSecondary),
              ),
              const SizedBox(height: 8),
              if (Platform.isAndroid) ...[
                Text('Always-on VPN supported: ${_alwaysOnSupported ? 'Yes' : 'No'}'),
                Text('Block connections without VPN (Lockdown): ${_lockdownEnabled ? 'Active' : 'Off'}'),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: widget.controller.engine.openSystemVpnSettings,
                  child: const Text('Open Android VPN Settings'),
                ),
              ] else ...[
                const Text(
                  'Uses NEPacketTunnelProvider. Always-on / On-Demand VPN is managed via iOS VPN Settings or MDM profiles as permitted by Apple NetworkExtension.',
                  style: TextStyle(fontSize: 12, color: SutemiColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('App v1.0.0 · Core: ${widget.controller.coreVersion}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              const Text('DIAGNOSTIC LOGS (SECRETS REDACTED)', style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: SutemiColors.textSecondary)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 180,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.controller.logger.lines.isEmpty
                        ? 'No events recorded yet.'
                        : widget.controller.logger.lines.join('\n'),
                    style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 10.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
