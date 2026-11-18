import Foundation
import Libbox
import Network
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider,
    LibboxPlatformInterfaceProtocol,
    LibboxCommandServerHandlerProtocol,
    LibboxCommandClientHandlerProtocol {

    private let appGroupId = "group.com.sutemi.vpn"
    private var boxService: LibboxBoxService?
    private var commandServer: LibboxCommandServer?
    private var statusClient: LibboxCommandClient?
    private var pathMonitor: NWPathMonitor?
    private var interfaceListener: LibboxInterfaceUpdateListenerProtocol?

    private let statsLock = NSLock()
    private var currentDownBps: Int64 = 0
    private var currentUpBps: Int64 = 0
    private var totalDown: Int64 = 0
    private var totalUp: Int64 = 0
    private var connectionsOut: Int32 = 0
    private var recentLogs: [String] = []

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let configJson = defaults.string(forKey: "active_singbox_config"),
              !configJson.isEmpty else {
            completionHandler(NSError(
                domain: "com.sutemi.vpn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing sing-box config in App Group \(appGroupId)"]
            ))
            return
        }

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            completionHandler(NSError(
                domain: "com.sutemi.vpn",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable for \(appGroupId)"]
            ))
            return
        }

        let workDir = containerURL.appendingPathComponent("libbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let setup = LibboxSetupOptions()
        setup.basePath = containerURL.path
        setup.workingPath = workDir.path
        setup.tempPath = NSTemporaryDirectory()
        var setupErr: NSError?
        LibboxSetup(setup, &setupErr)
        if let setupErr = setupErr {
            completionHandler(setupErr)
            return
        }

        var cmdErr: NSError?
        guard let cmdServer = LibboxNewCommandServer(self, 200, &cmdErr), cmdErr == nil else {
            completionHandler(cmdErr ?? NSError(domain: "com.sutemi.vpn", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize LibboxCommandServer",
            ]))
            return
        }
        do {
            try cmdServer.start()
            self.commandServer = cmdServer
        } catch {
            completionHandler(error)
            return
        }

        startPathMonitor()

        var serviceErr: NSError?
        guard let service = LibboxNewService(configJson, self, &serviceErr), serviceErr == nil else {
            cleanupCore()
            completionHandler(serviceErr)
            return
        }

        do {
            try service.start()
            self.boxService = service
            cmdServer.setService(service)
            startStatusClient()
            appendLog("PacketTunnelProvider started (libbox \(LibboxVersion()))")
            completionHandler(nil)
        } catch {
            try? service.close()
            cleanupCore()
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        appendLog("PacketTunnelProvider stopping (reason=\(reason.rawValue))")
        cleanupCore()
        completionHandler()
    }

    private func cleanupCore() {
        pathMonitor?.cancel()
        pathMonitor = nil
        try? statusClient?.disconnect()
        statusClient = nil
        commandServer?.setService(nil)
        try? boxService?.close()
        boxService = nil
        try? commandServer?.close()
        commandServer = nil

        statsLock.lock()
        currentDownBps = 0
        currentUpBps = 0
        totalDown = 0
        totalUp = 0
        connectionsOut = 0
        statsLock.unlock()
    }

    private func startStatusClient() {
        let clientOptions = LibboxCommandClientOptions()
        clientOptions.command = LibboxCommandStatus
        clientOptions.statusInterval = 1_000_000_000 // 1s in nanoseconds
        let client = LibboxNewCommandClient(self, clientOptions)
        self.statusClient = client
        try? client?.connect()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let cmd = String(data: messageData, encoding: .utf8) ?? ""
        if cmd == "stats" {
            statsLock.lock()
            let payload: [String: Any] = [
                "downBps": currentDownBps,
                "upBps": currentUpBps,
                "totalDown": totalDown,
                "totalUp": totalUp,
                "connectionsOut": connectionsOut,
                "running": boxService != nil,
            ]
            statsLock.unlock()
            completionHandler?(try? JSONSerialization.data(withJSONObject: payload))
            return
        }
        if cmd == "logs" {
            statsLock.lock()
            let drained = recentLogs
            recentLogs.removeAll()
            statsLock.unlock()
            completionHandler?(try? JSONSerialization.data(withJSONObject: ["lines": drained]))
            return
        }
        completionHandler?(nil)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        boxService?.pause()
        completionHandler()
    }

    override func wake() {
        boxService?.wake()
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status != .satisfied {
                self?.interfaceListener?.updateDefaultInterface("", interfaceIndex: -1)
                return
            }
            let iface = path.availableInterfaces.first(where: { $0.type != .other }) ?? path.availableInterfaces.first
            let ifaceName = iface?.name ?? ""
            let ifaceIndex = Int32(iface?.index ?? -1)
            self?.interfaceListener?.updateDefaultInterface(ifaceName, interfaceIndex: ifaceIndex)
        }
        monitor.start(queue: DispatchQueue(label: "com.sutemi.vpn.pathmonitor"))
        self.pathMonitor = monitor
    }

    private func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        statsLock.lock()
        recentLogs.append(trimmed)
        if recentLogs.count > 120 {
            recentLogs.removeFirst(recentLogs.count - 120)
        }
        statsLock.unlock()
    }

    // MARK: - LibboxCommandServerHandlerProtocol
    func serviceReload() throws {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let configJson = defaults.string(forKey: "active_singbox_config"),
              !configJson.isEmpty else {
            throw NSError(domain: "com.sutemi.vpn", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Missing config for reload",
            ])
        }
        try? statusClient?.disconnect()
        commandServer?.setService(nil)
        try? boxService?.close()
        boxService = nil

        var err: NSError?
        guard let service = LibboxNewService(configJson, self, &err), err == nil else {
            throw err ?? NSError(domain: "com.sutemi.vpn", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "Reload failed",
            ])
        }
        try service.start()
        boxService = service
        commandServer?.setService(service)
        startStatusClient()
    }

    func postServiceClose() {
        cleanupCore()
        cancelTunnelWithError(nil)
    }

    func getSystemProxyStatus() -> LibboxSystemProxyStatus? {
        let status = LibboxSystemProxyStatus()
        status.available = false
        status.enabled = false
        return status
    }

    func setSystemProxyEnabled(_ isEnabled: Bool) throws {}

    // MARK: - LibboxCommandClientHandlerProtocol
    func connected() {}
    func disconnected(_ message: String?) {}
    func clearLogs() {}

    func writeLogs(_ messageList: LibboxStringIteratorProtocol?) {
        guard let list = messageList else { return }
        while list.hasNext() {
            appendLog(list.next())
        }
    }

    func writeStatus(_ message: LibboxStatusMessage?) {
        guard let msg = message, msg.trafficAvailable else { return }
        statsLock.lock()
        currentDownBps = max(0, msg.downlink)
        currentUpBps = max(0, msg.uplink)
        totalDown = max(0, msg.downlinkTotal)
        totalUp = max(0, msg.uplinkTotal)
        connectionsOut = msg.connectionsOut
        statsLock.unlock()
    }

    func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {}
    func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
    func updateClashMode(_ newMode: String?) {}
    func writeConnections(_ message: LibboxConnections?) {}

    // MARK: - LibboxPlatformInterfaceProtocol (sing-box v1.10.7)
    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else {
            throw NSError(domain: "com.sutemi.vpn", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "Nil LibboxTunOptions",
            ])
        }
        guard let ret0_ else {
            throw NSError(domain: "com.sutemi.vpn", code: -11, userInfo: [
                NSLocalizedDescriptionKey: "Nil TUN fd return pointer",
            ])
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())

        var ipv4Addrs: [String] = []
        var ipv4Masks: [String] = []
        if let inet4 = options.getInet4Address() {
            while inet4.hasNext() {
                if let prefix = inet4.next() {
                    ipv4Addrs.append(prefix.address())
                    ipv4Masks.append(prefix.mask())
                }
            }
        }
        if ipv4Addrs.isEmpty {
            ipv4Addrs = ["172.19.0.1"]
            ipv4Masks = ["255.255.255.252"]
        }
        let ipv4 = NEIPv4Settings(addresses: ipv4Addrs, subnetMasks: ipv4Masks)
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        var ipv6Addrs: [String] = []
        var ipv6Lens: [NSNumber] = []
        if let inet6 = options.getInet6Address() {
            while inet6.hasNext() {
                if let prefix = inet6.next() {
                    ipv6Addrs.append(prefix.address())
                    ipv6Lens.append(NSNumber(value: prefix.prefix()))
                }
            }
        }
        if !ipv6Addrs.isEmpty {
            let ipv6 = NEIPv6Settings(addresses: ipv6Addrs, networkPrefixLengths: ipv6Lens)
            ipv6.includedRoutes = [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6
        }

        var dnsServers = ["1.1.1.1"]
        var dnsErr: NSError?
        if let dnsBox = options.getDNSServerAddress(&dnsErr), dnsErr == nil, !dnsBox.value.isEmpty {
            dnsServers = [dnsBox.value]
        }
        settings.dnsSettings = NEDNSSettings(servers: dnsServers)

        let semaphore = DispatchSemaphore(value: 0)
        var setErr: Error?
        setTunnelNetworkSettings(settings) { error in
            setErr = error
            semaphore.signal()
        }
        semaphore.wait()
        if let setErr {
            throw setErr
        }

        // Primary mechanism used by SagerNet/sing-box-for-apple; falls back to
        // utun kernel control socket scan (LibboxGetTunnelFileDescriptor) if KVC is unavailable.
        if let tunFd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, tunFd >= 0 {
            ret0_.pointee = tunFd
            return
        }

        let fallbackFd = LibboxGetTunnelFileDescriptor()
        if fallbackFd >= 0 {
            ret0_.pointee = fallbackFd
            return
        }

        throw NSError(domain: "com.sutemi.vpn", code: -12, userInfo: [
            NSLocalizedDescriptionKey: "Failed to acquire utun file descriptor from NEPacketTunnelFlow",
        ])
    }

    func autoDetectInterfaceControl(_ fd: Int32) throws {}
    func usePlatformAutoDetectInterfaceControl() -> Bool { false }
    func useProcFS() -> Bool { false }

    func findConnectionOwner(
        _ ipProtocol: Int32,
        sourceAddress: String?,
        sourcePort: Int32,
        destinationAddress: String?,
        destinationPort: Int32,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {
        ret0_?.pointee = -1
    }

    func packageName(byUid uid: Int32, error: NSErrorPointer) -> String { "" }
    func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        ret0_?.pointee = -1
    }

    func usePlatformDefaultInterfaceMonitor() -> Bool { true }
    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        interfaceListener = listener
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        interfaceListener = nil
    }

    func usePlatformInterfaceGetter() -> Bool { false }
    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "com.sutemi.vpn", code: -13, userInfo: [
            NSLocalizedDescriptionKey: "Platform interface getter disabled",
        ])
    }

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func clearDNSCache() {}
    func readWIFIState() -> LibboxWIFIState? { nil }
    func writeLog(_ message: String?) {
        if let message { appendLog(message) }
    }

    func send(_ notification: LibboxNotification?) throws {}
}
