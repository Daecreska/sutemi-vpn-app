import 'package:flutter/material.dart';

import '../../core/managers/sutemi_controller.dart';
import '../../core/models/vpn_models.dart';
import '../theme/sutemi_theme.dart';
import '../widgets/connect_button.dart';
import '../widgets/country_badge.dart';
import '../widgets/sutemi_logo.dart';

class HomeScreen extends StatelessWidget {
  final SutemiController controller;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenSettings;

  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenServers,
    required this.onOpenSettings,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatRate(int bps) {
    if (bps >= 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bps / 1024).round()} KB/s';
  }

  String _headline(VpnConnectionState s) {
    switch (s) {
      case VpnConnectionState.connected:
        return 'You are protected';
      case VpnConnectionState.connecting:
        return 'Connecting...';
      case VpnConnectionState.reconnecting:
        return 'Reconnecting...';
      case VpnConnectionState.error:
        return 'Connection error';
      case VpnConnectionState.disconnected:
        return 'Not connected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = controller.selectedProfile;
    final state = controller.connectionState;
    final isConnected = state == VpnConnectionState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        children: [
          // Top Brand Bar
          Row(
            children: [
              const SutemiLogo(size: 40),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SUTEMI',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 4),
                  ),
                  Text(
                    'PRIVATE CONNECTION',
                    style: TextStyle(fontSize: 8, letterSpacing: 2, color: SutemiColors.textSecondary),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings & Diagnostics',
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Status Headline + Connection Timer
          const Text(
            'YOUR PRIVATE NETWORK',
            style: TextStyle(fontSize: 9, letterSpacing: 3, color: SutemiColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            _headline(state),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            isConnected
                ? 'Active tunnel · ${_formatDuration(controller.connectionDuration)}'
                : (controller.errorMessage ?? 'Select a server and start a secure connection'),
            style: TextStyle(
              fontSize: 12,
              color: state == VpnConnectionState.error ? SutemiColors.rose : SutemiColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Central Animated Connect Button
          SutemiConnectButton(
            state: state,
            onPressed: () {
              if (isConnected || state == VpnConnectionState.connecting) {
                controller.disconnect();
              } else {
                controller.connect();
              }
            },
          ),
          Text(
            isConnected ? 'DISCONNECT' : (state == VpnConnectionState.connecting ? 'CONNECTING' : 'CONNECT'),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 4,
              fontWeight: FontWeight.w600,
              color: isConnected ? SutemiColors.mint : SutemiColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),

          // Selected Server Card
          InkWell(
            onTap: onOpenServers,
            borderRadius: BorderRadius.circular(20),
            child: GlassCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      CountryBadge(
                        code: profile?.country ?? 'WW',
                        verified: profile?.countryVerified ?? false,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SELECTED SERVER',
                              style: TextStyle(fontSize: 8.5, letterSpacing: 1.6, color: SutemiColors.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              profile?.name ?? 'No servers added',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              profile != null
                                  ? '${profile.protocol.name.toUpperCase()} · ${profile.address}:${profile.port}'
                                  : 'Tap to import links or curated servers',
                              style: const TextStyle(fontSize: 11, color: SutemiColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: SutemiColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0x18FFFFFF)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MetricCell(
                        label: 'PING',
                        value: (profile?.latencyMs != null && profile!.latencyMs! > 0)
                            ? '${profile.latencyMs} ms'
                            : (profile?.latencyMs != null && profile!.latencyMs! < 0 ? 'ERR' : '— ms'),
                      ),
                      _MetricCell(
                        label: '↓ DOWN',
                        value: _formatRate(controller.trafficStats.downloadBps),
                      ),
                      _MetricCell(
                        label: '↑ UP',
                        value: _formatRate(controller.trafficStats.uploadBps),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // AI Services & Exit IP Verification Card
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'EXIT: ${controller.aiResult?.exitIp.isNotEmpty == true ? '${controller.aiResult!.exitIp} · ${controller.aiResult!.country}' : '—'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    if (controller.aiResult?.speedMbps != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· ${controller.aiResult!.speedMbps} Mbps',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SutemiColors.mint),
                      ),
                    ],
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: isConnected && !controller.isCheckingAi ? controller.runAiAndSpeedCheck : null,
                      child: Text(controller.isCheckingAi ? 'Checking...' : 'Check AI & Speed'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AiStatusItem(label: 'Gemini', report: controller.aiResult?.gemini),
                    _AiStatusItem(label: 'AI Studio', report: controller.aiResult?.aiStudio),
                    _AiStatusItem(label: 'ChatGPT', report: controller.aiResult?.chatGpt),
                    _AiStatusItem(label: 'Claude', report: controller.aiResult?.claude),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  const _MetricCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8.5, letterSpacing: 1.4, color: SutemiColors.textSecondary)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _AiStatusItem extends StatelessWidget {
  final String label;
  final AiServiceReport? report;

  const _AiStatusItem({required this.label, this.report});

  @override
  Widget build(BuildContext context) {
    final status = report?.status;
    Color dotColor = SutemiColors.textSecondary;
    String statusText = 'Unchecked';
    if (status == AiServiceStatus.available) {
      dotColor = SutemiColors.mint;
      statusText = 'Available';
    } else if (status == AiServiceStatus.regionRestricted) {
      dotColor = SutemiColors.rose;
      statusText = 'Restricted';
    } else if (status == AiServiceStatus.authRequired) {
      dotColor = SutemiColors.amber;
      statusText = 'Auth req';
    } else if (status == AiServiceStatus.challenge) {
      dotColor = SutemiColors.amber;
      statusText = 'CAPTCHA';
    } else if (status == AiServiceStatus.connectionError) {
      dotColor = SutemiColors.rose;
      statusText = 'Error';
    } else if (status == AiServiceStatus.unknown) {
      dotColor = SutemiColors.textSecondary;
      statusText = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dotColor.withValues(alpha: 0.35)),
        color: dotColor.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 6),
          Text('$label · $statusText', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
