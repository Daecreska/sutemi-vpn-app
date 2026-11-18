# SUTEMI VPN Mobile — Full Build, Signing & Verification Guide

> **Platform Scope**: This repository contains the complete Flutter/Dart UI, Kotlin Android `VpnService`, Swift iOS `NEPacketTunnelProvider` + `Runner.xcodeproj`, pinned `build_libbox.sh` (`sing-box v1.10.7`), and unit tests.
> **Environment Disclosure**: Cloud/Linux Node.js sandboxes cannot run `gomobile`, Gradle Android builds, Flutter tests, or macOS Xcode builds. Follow the steps below on your workstation / CI runner to produce signed binaries and verify real TUN traffic.

---

## 1. Prerequisites

### Common
- **Git** & **Go 1.22+** (`go version`)
- **Flutter SDK 3.24+** (`flutter doctor`)

### Android
- **JDK 17** (`JAVA_HOME` pointing to Temurin/Zulu 17)
- **Android SDK 35** (`ANDROID_HOME` / `ANDROID_SDK_ROOT`)
- **Android NDK r26** (`26.3.11579264`, with `ANDROID_NDK_HOME` set)

### iOS
- **macOS** + **Xcode 15+** & **CocoaPods** (`pod install`)
- **Paid Apple Developer Program ($99/year)** membership (required for `com.apple.developer.networking.networkextension` `packet-tunnel-provider` and App Groups entitlements; personal free Apple IDs cannot sign Packet Tunnel extensions).

---

## 2. Build Pinned `sing-box` (`v1.10.7`) `libbox` Core

```bash
cd mobile
chmod +x scripts/build_libbox.sh
./scripts/build_libbox.sh
```

What this produces:
- `mobile/android/app/libs/libbox.aar` (Java package `io.nekohasekai.libbox`, tags `with_gvisor,with_quic,with_wireguard,with_utls,with_reality_server,with_clash_api`)
- `mobile/ios/Frameworks/Libbox.xcframework` (on macOS only, targeting `ios` and `iossimulator`)

---

## 3. Run Flutter Unit Tests

```bash
cd mobile
flutter pub get
flutter test
```

Tests verify:
- `test/share_link_parser_test.dart`: VLESS Reality/TLS/WS/gRPC, VMess JSON/URI, Trojan, Shadowsocks SIP002/legacy, Hysteria2, TUIC v5, Strict TLS filtering, private IP rejection, and RU-audience vs physical-RU country detection.
- `test/singbox_config_builder_test.dart`: `tun-in` + `mixed-in`, `experimental.clash_api`, remote `rule_set` declarations, Android/iOS TUN parameters.
- `test/diagnostics_and_smart_filter_test.dart`: Secret redaction in `DiagnosticsLogger` and strict refusal of direct fallback in `TunneledHttp`.

---

## 4. Build Android APK & Play Store AAB

### Debug APK (sideload testing)
```bash
cd mobile
flutter build apk --debug
```

### Release Signing (`sutemi-release.jks`)
1. Generate keystore (once):
   ```bash
   keytool -genkey -v -keystore sutemi-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias sutemi
   ```
2. Create `mobile/android/key.properties` (never commit):
   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=sutemi
   storeFile=../sutemi-release.jks
   ```
3. Build release binaries:
   ```bash
   flutter build apk --release --split-per-abi
   flutter build appbundle --release
   ```
   Outputs:
   - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
   - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
   - `build/app/outputs/bundle/release/app-release.aab`

---

## 5. Build iOS IPA (`Runner` + `PacketTunnelExtension`)

1. Ensure `mobile/ios/Frameworks/Libbox.xcframework` exists (Step 2 on macOS).
2. Install CocoaPods:
   ```bash
   cd mobile/ios
   pod install
   ```
3. In Apple Developer Portal, enable **Network Extensions (Packet Tunnel)** & **App Groups (`group.com.sutemi.vpn`)** for BOTH App IDs:
   - `com.sutemi.vpn` (`Runner`)
   - `com.sutemi.vpn.PacketTunnelExtension` (`PacketTunnelExtension`)
4. Open `mobile/ios/Runner.xcworkspace` in Xcode:
   - Select your Development Team (`DEVELOPMENT_TEAM`) for both `Runner` and `PacketTunnelExtension` targets under **Signing & Capabilities**.
   - Verify `Libbox.xcframework` is **Embed & Sign** on `Runner` and **Do Not Embed** (linked) on `PacketTunnelExtension`.
5. Build signed `.ipa`:
   ```bash
   cd mobile
   flutter build ipa --release
   ```

---

## 6. Real Device Acceptance Checklist

1. **System Tunnel**: Connect to a VLESS Reality or Hysteria2 server, confirm Android VPN key icon / iOS VPN badge appears, and verify `curl https://www.cloudflare.com/cdn-cgi/trace` or browser IP matches the remote server.
2. **In-App Proxy Enforcement**: Tap **Check AI & Speed** on Home screen; confirm Exit IP equals the VPN server IP (never ISP IP) and speed counters update live via `libbox` `CommandServer`.
3. **Kill Switch / Network Handoff**: Switch Wi-Fi -> LTE/5G while connected and verify `reconnecting` -> `connected` recovery.
4. **Secret Hygiene**: Open **Settings → Diagnostic Logs** and verify UUIDs, Reality `pbk`, passwords, and `ss://` payloads appear as `[REDACTED]`.
