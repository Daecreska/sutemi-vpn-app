import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/models/vpn_models.dart';
import '../theme/sutemi_theme.dart';

class SutemiConnectButton extends StatefulWidget {
  final VpnConnectionState state;
  final VoidCallback onPressed;

  const SutemiConnectButton({
    super.key,
    required this.state,
    required this.onPressed,
  });

  @override
  State<SutemiConnectButton> createState() => _SutemiConnectButtonState();
}

class _SutemiConnectButtonState extends State<SutemiConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.state == VpnConnectionState.connected;
    final isConnecting = widget.state == VpnConnectionState.connecting ||
        widget.state == VpnConnectionState.reconnecting;

    return GestureDetector(
      onTap: widget.onPressed,
      child: SizedBox(
        width: 210,
        height: 210,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value * 2 * math.pi;
            final scale = isConnected
                ? 1.0 + 0.03 * math.sin(t * 2)
                : 1.0 + 0.015 * math.sin(t);

            return Stack(
              alignment: Alignment.center,
              children: [
                // Ambient Liquid Orbs
                Container(
                  width: 205,
                  height: 205,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (isConnected ? SutemiColors.mint : SutemiColors.violet)
                            .withValues(alpha: isConnected ? 0.30 : 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Outer Spinning Ring when Connecting
                if (isConnecting)
                  Transform.rotate(
                    angle: t * 4,
                    child: Container(
                      width: 164,
                      height: 164,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SutemiColors.cyan.withValues(alpha: 0.75),
                          width: 2.5,
                        ),
                      ),
                    ),
                  )
                else
                  Transform.rotate(
                    angle: t * 0.5,
                    child: Container(
                      width: 166,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(82),
                        border: Border.all(
                          color: (isConnected ? SutemiColors.mint : Colors.white)
                              .withValues(alpha: 0.25),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                // Main Liquid Glass Core Button
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 144,
                    height: 144,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.92), width: 1.2),
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        colors: isConnected
                            ? const [
                                Color(0xFFFFFFFF),
                                Color(0xFFF4FFFC),
                                Color(0xFFE2F8F1),
                                Color(0xFFCCEEE3),
                              ]
                            : const [
                                Color(0xFFFFFFFF),
                                Color(0xFFF6F8FF),
                                Color(0xFFE7ECFB),
                                Color(0xFFD4DCF3),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected ? SutemiColors.mint : Colors.white)
                              .withValues(alpha: isConnected ? 0.46 : 0.32),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: 48,
                      color: isConnected ? const Color(0xFF0D8563) : const Color(0xFF242138),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
