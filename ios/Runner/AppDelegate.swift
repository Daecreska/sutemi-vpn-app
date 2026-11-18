import Flutter
import NetworkExtension
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let appGroupId = "group.com.sutemi.vpn"
    private let tunnelBundleId = "com.sutemi.vpn.PacketTunnelExtension"

    private var stateSink: FlutterEventSink?
    private var trafficSink: FlutterEventSink?
    private var logSink: FlutterEventSink?
    private var statusObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var lastErrorMessage: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let messenger = controller.binaryMessenger

            FlutterEventChannel(name: "sutemi.vpn/state", binaryMessenger: messenger)
                .setStreamHandler(StreamHandlerProxy(
                    onListen: { [weak self] sink in
                        self?.stateSink = sink
                        self?.observeTunnelStatus()
                    },
                    onCancel: { [weak self] in
                        self?.stateSink = nil
                    }
                ))

            FlutterEventChannel(name: "sutemi.vpn/traffic", binaryMessenger: messenger)
                .setStreamHandler(StreamHandlerProxy(
                    onListen: { [weak self] sink in
                        self?.trafficSink = sink
                        self?.startExtensionPolling()
                    },
                    onCancel: { [weak self] in
                        self?.trafficSink = nil
                        self?.pollTimer?.invalidate()
                        self?.pollTimer = nil
                    }
                ))

            FlutterEventChannel(name: "sutemi.vpn/logs", binaryMessenger: messenger)
                .setStreamHandler(StreamHandlerProxy(
                    onListen: { [weak self] sink in self?.logSink = sink },
                    onCancel: { [weak self] in self?.logSink = nil }
                ))

            FlutterMethodChannel(name: "sutemi.vpn/control", binaryMessenger: messenger)
                .setMethodCallHandler { [weak self] call, result in
                    self?.handleMethodCall(call, result: result)
                }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCoreVersion":
            result("sing-box/libbox (NEPacketTunnelProvider)")
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let configJson = args["configJson"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing configJson", details: nil))
                return
            }
            let profileName = (args["profileName"] as? String) ?? "SUTEMI VPN"
            let autoReconnect = (args["autoReconnect"] as? Bool) ?? true
            connectTunnel(configJson: configJson, profileName: profileName, autoReconnect: autoReconnect, result: result)
        case "disconnect":
            disconnectTunnel(result: result)
        case "reconnect":
            loadOrSelectManager { manager in
                guard let manager else {
                    result(nil)
                    return
                }
                manager.connection.stopVPNTunnel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    try? manager.connection.startVPNTunnel()
                    result(nil)
                }
            }
        case "getState":
            loadOrSelectManager { [weak self] manager in
                result(self?.mapStatus(manager?.connection.status ?? .disconnected) ?? "disconnected")
            }
        case "getLastError":
            result(lastErrorMessage)
        case "isAlwaysOnSupported":
            result(false)
        case "isLockdownEnabled":
            result(false)
        case "openSystemVpnSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            result(nil)
        case "getLocalProxyPort":
            result(2080)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func connectTunnel(
        configJson: String,
        profileName: String,
        autoReconnect: Bool,
        result: @escaping FlutterResult
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            result(FlutterError(
                code: "APP_GROUP",
                message: "App Group \(appGroupId) is not provisioned in Signing & Capabilities",
                details: nil
            ))
            return
        }

        lastErrorMessage = nil
        defaults.set(configJson, forKey: "active_singbox_config")
        defaults.set(profileName, forKey: "active_profile_name")
        defaults.synchronize()

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else { return }
            if let error {
                self.lastErrorMessage = error.localizedDescription
                result(FlutterError(code: "NE_LOAD", message: error.localizedDescription, details: nil))
                return
            }

            let matching = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
            }
            let manager = matching ?? managers?.first ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.tunnelBundleId
            proto.serverAddress = "SUTEMI Tunnel"
            proto.providerConfiguration = ["profileName": profileName]

            manager.protocolConfiguration = proto
            manager.localizedDescription = "SUTEMI VPN"
            manager.isEnabled = true

            if autoReconnect {
                let connectRule = NEOnDemandRuleConnect()
                connectRule.interfaceTypeMatch = .any
                manager.onDemandRules = [connectRule]
                manager.isOnDemandEnabled = true
            } else {
                manager.onDemandRules = []
                manager.isOnDemandEnabled = false
            }

            manager.saveToPreferences { saveErr in
                if let saveErr {
                    self.lastErrorMessage = saveErr.localizedDescription
                    result(FlutterError(code: "NE_SAVE", message: saveErr.localizedDescription, details: nil))
                    return
                }
                manager.loadFromPreferences { reloadErr in
                    if let reloadErr {
                        self.lastErrorMessage = reloadErr.localizedDescription
                        result(FlutterError(code: "NE_RELOAD", message: reloadErr.localizedDescription, details: nil))
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        result(nil)
                    } catch {
                        self.lastErrorMessage = error.localizedDescription
                        result(FlutterError(code: "NE_START", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func disconnectTunnel(result: @escaping FlutterResult) {
        loadOrSelectManager { manager in
            guard let manager else {
                result(nil)
                return
            }
            if manager.isOnDemandEnabled {
                manager.isOnDemandEnabled = false
                manager.saveToPreferences { _ in
                    manager.connection.stopVPNTunnel()
                    result(nil)
                }
            } else {
                manager.connection.stopVPNTunnel()
                result(nil)
            }
        }
    }

    private func loadOrSelectManager(_ completion: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self else {
                completion(nil)
                return
            }
            let match = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
            }
            completion(match ?? managers?.first)
        }
    }

    private func observeTunnelStatus() {
        if let existing = statusObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let conn = note.object as? NEVPNConnection else { return }
            let mapped = self.mapStatus(conn.status)
            if mapped == "disconnected" {
                self.trafficSink?(["downBps": 0, "upBps": 0, "totalDown": 0, "totalUp": 0])
                if #available(iOS 16.0, *) {
                    conn.fetchLastDisconnectError { err in
                        if let err {
                            self.lastErrorMessage = err.localizedDescription
                            self.logSink?("Disconnect reason: \(err.localizedDescription)")
                        }
                    }
                }
            }
            self.stateSink?(mapped)
        }
        loadOrSelectManager { [weak self] manager in
            DispatchQueue.main.async {
                self?.stateSink?(self?.mapStatus(manager?.connection.status ?? .disconnected) ?? "disconnected")
            }
        }
    }

    private func startExtensionPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.loadOrSelectManager { manager in
                guard let session = manager?.connection as? NETunnelProviderSession,
                      session.status == .connected else { return }

                if let statsMsg = "stats".data(using: .utf8) {
                    try? session.sendProviderMessage(statsMsg) { response in
                        guard let data = response,
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        DispatchQueue.main.async {
                            self?.trafficSink?(obj)
                        }
                    }
                }

                if let logsMsg = "logs".data(using: .utf8) {
                    try? session.sendProviderMessage(logsMsg) { response in
                        guard let data = response,
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let lines = obj["lines"] as? [String],
                              !lines.isEmpty else { return }
                        DispatchQueue.main.async {
                            for line in lines {
                                self?.logSink?(line)
                            }
                        }
                    }
                }
            }
        }
    }

    private func mapStatus(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .reasserting: return "reconnecting"
        case .disconnecting, .disconnected, .invalid: return "disconnected"
        @unknown default: return "disconnected"
        }
    }
}

private class StreamHandlerProxy: NSObject, FlutterStreamHandler {
    private let onListenBlock: (FlutterEventSink?) -> Void
    private let onCancelBlock: () -> Void

    init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
        self.onListenBlock = onListen
        self.onCancelBlock = onCancel
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenBlock(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelBlock()
        return nil
    }
}
