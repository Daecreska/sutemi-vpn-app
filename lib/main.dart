import 'package:flutter/material.dart';

import 'core/managers/sutemi_controller.dart';
import 'core/storage/secure_storage_service.dart';
import 'core/vpn/libbox_vpn_engine.dart';
import 'core/vpn/vpn_core.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/servers_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme/sutemi_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = DiagnosticsLogger();
  final controller = SutemiController(
    vpnCore: VpnCore(
      engine: LibboxVpnEngine(),
      logger: logger,
    ),
    storage: SecureStorageService(),
    logger: logger,
  );
  controller.initialize();
  runApp(SutemiMobileApp(controller: controller));
}

class SutemiMobileApp extends StatefulWidget {
  final SutemiController controller;
  const SutemiMobileApp({super.key, required this.controller});

  @override
  State<SutemiMobileApp> createState() => _SutemiMobileAppState();
}

class _SutemiMobileAppState extends State<SutemiMobileApp> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SUTEMI VPN',
      debugShowCheckedModeBanner: false,
      theme: buildSutemiTheme(),
      home: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.25),
                  radius: 1.15,
                  colors: [
                    Color(0xFF19223B),
                    SutemiColors.background,
                  ],
                ),
              ),
              child: SafeArea(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    HomeScreen(
                      controller: widget.controller,
                      onOpenServers: () => setState(() => _tabIndex = 1),
                      onOpenSettings: () => setState(() => _tabIndex = 2),
                    ),
                    ServersScreen(
                      controller: widget.controller,
                      onConnectedNavigateHome: () => setState(() => _tabIndex = 0),
                    ),
                    SettingsScreen(controller: widget.controller),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              backgroundColor: const Color(0xFF10131C),
              selectedIndex: _tabIndex,
              onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'Connect'),
                NavigationDestination(icon: Icon(Icons.dns_outlined), label: 'Servers'),
                NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
              ],
            ),
          );
        },
      ),
    );
  }
}
