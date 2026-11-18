# SUTEMI VPN Mobile — Build, Signing & Deployment Guide

## 1. VPN Core Architecture (`sing-box / libbox`)
- **Core**: `sing-box` (`experimental/libbox`), compiled via `gomobile` (`GPL-3.0-or-later`).
- **Supported Protocols**: VLESS (Reality, XTLS-RPRX-Vision, TLS, WS, gRPC, HTTPUpgrade), VMess (WS/TLS/TCP), Trojan, Shadowsocks (SIP002 & legacy), Hysteria2 (`hy2://` / `hysteria2://`, obfs, port hopping), TUIC v5.
- **Note on Desktop Legacy**: Windows `Throne.exe` / `thronectl.exe` and Windows Registry System Proxy are **not** used on mobile. Both Android (`VpnService`) and iOS (`NEPacketTunnelProvider`) run full system-wide TUN tunneling.

## 2. Prerequisites & Honest Environment Limitations
The web/Node.js sandbox cannot compile native `.apk`, `.aab`, or `.ipa` binaries because it lacks Android SDK/NDK, Flutter SDK, Go, macOS, and Xcode. Follow the steps below on your build machine to produce installable binaries.

### Step A — Compile Pinned `libbox` (`v1.10.7`) Core
Requires **Go 1.22+**, **Android NDK r26+**, and (for iOS) **macOS + Xcode 15+**:
```bash
cd mobile
chmod +x scripts/build_libbox.sh
./scripts/build_libbox.sh
```
This outputs:
- `mobile/android/app/libs/libbox.aar` (`io.nekohasekai.libbox`)
- `mobile/ios/Frameworks/Libbox.xcframework` (macOS only)

See `mobile/README_BUILD.md` for full keystore signing, Flutter tests (`flutter test`), Android APK/AAB builds, Apple Developer NetworkExtension provisioning, and device verification steps.
