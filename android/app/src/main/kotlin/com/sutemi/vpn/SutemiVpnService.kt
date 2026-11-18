package com.sutemi.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Connections
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.Notification as LibboxNotification
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.net.InetAddress
import java.net.NetworkInterface

object VpnEventBus {
    @Volatile
    var currentState: String = "disconnected"

    @Volatile
    var lastError: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var stateSink: EventChannel.EventSink? = null
    private var trafficSink: EventChannel.EventSink? = null
    private var logSink: EventChannel.EventSink? = null

    val stateHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            stateSink = events
            events?.success(currentState)
        }
        override fun onCancel(arguments: Any?) { stateSink = null }
    }

    val trafficHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { trafficSink = events }
        override fun onCancel(arguments: Any?) { trafficSink = null }
    }

    val logHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { logSink = events }
        override fun onCancel(arguments: Any?) { logSink = null }
    }

    fun emitState(state: String) {
        currentState = state
        mainHandler.post { stateSink?.success(state) }
    }

    fun emitTraffic(downBps: Long, upBps: Long, totalDown: Long, totalUp: Long) {
        mainHandler.post {
            trafficSink?.success(
                mapOf(
                    "downBps" to downBps,
                    "upBps" to upBps,
                    "totalDown" to totalDown,
                    "totalUp" to totalUp
                )
            )
        }
    }

    fun emitLog(line: String) {
        if (line.isBlank()) return
        mainHandler.post { logSink?.success(line) }
    }
}

class SutemiVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    companion object {
        const val ACTION_START = "com.sutemi.vpn.START"
        const val ACTION_STOP = "com.sutemi.vpn.STOP"
        const val ACTION_RECONNECT = "com.sutemi.vpn.RECONNECT"
        private const val CHANNEL_ID = "sutemi_vpn_channel"
        private const val NOTIFICATION_ID = 7001

        @Volatile
        var activeInstance: SutemiVpnService? = null
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var boxService: BoxService? = null
    private var commandServer: CommandServer? = null
    private var statusClient: CommandClient? = null
    private var tunFd: ParcelFileDescriptor? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var interfaceListener: InterfaceUpdateListener? = null
    private var lastConfigJson: String = ""
    private var lastProfileName: String = "SUTEMI"
    private var autoReconnect: Boolean = true
    private var notificationsEnabled: Boolean = true

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        ensureNotificationChannel()
        val workDir = File(filesDir, "libbox").apply { mkdirs() }
        val setup = SetupOptions().apply {
            basePath = filesDir.absolutePath
            workingPath = workDir.absolutePath
            tempPath = cacheDir.absolutePath
            fixAndroidStack = true
        }
        Libbox.setup(setup)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopVpn(preserveErrorState = false)
            return START_NOT_STICKY
        }

        val prefs = getSharedPreferences("sutemi_vpn_runtime", MODE_PRIVATE)
        lastConfigJson = intent?.getStringExtra("configJson") ?: prefs.getString("configJson", "") ?: ""
        lastProfileName = intent?.getStringExtra("profileName") ?: prefs.getString("profileName", "SUTEMI") ?: "SUTEMI"
        autoReconnect = intent?.getBooleanExtra("autoReconnect", true) ?: prefs.getBoolean("autoReconnect", true)
        notificationsEnabled = intent?.getBooleanExtra("notificationsEnabled", true) ?: prefs.getBoolean("notificationsEnabled", true)

        if (lastConfigJson.isBlank()) {
            VpnEventBus.lastError = "Empty sing-box configuration"
            VpnEventBus.emitState("error")
            stopSelf()
            return START_NOT_STICKY
        }

        VpnEventBus.lastError = null
        startForegroundWithNotification("Connecting to $lastProfileName...")
        VpnEventBus.emitState(if (action == ACTION_RECONNECT) "reconnecting" else "connecting")

        serviceScope.launch {
            startTunnelInternal()
        }
        return START_STICKY
    }

    private suspend fun startTunnelInternal() {
        try {
            stopCoreOnly()
            registerNetworkMonitor()

            val cmdServer = Libbox.newCommandServer(this, 250)
            cmdServer.start()
            commandServer = cmdServer

            val service = Libbox.newService(lastConfigJson, this)
            service.start()

            val currentTun = tunFd
            if (currentTun == null || currentTun.fd < 0) {
                runCatching { service.close() }
                throw IllegalStateException("Android TUN interface was not created")
            }

            boxService = service
            cmdServer.setService(service)
            startStatusCommandClient()

            VpnEventBus.lastError = null
            VpnEventBus.emitState("connected")
            if (notificationsEnabled) {
                updateNotification("Protected · $lastProfileName")
            }
            VpnEventBus.emitLog("Tunnel started for $lastProfileName (fd=${currentTun.fd})")
        } catch (t: Throwable) {
            val msg = t.message ?: t.javaClass.simpleName
            VpnEventBus.lastError = msg
            VpnEventBus.emitLog("Tunnel startup failed: $msg")
            stopVpn(preserveErrorState = true)
        }
    }

    private fun startStatusCommandClient() {
        runCatching { statusClient?.disconnect() }
        statusClient = null

        val options = CommandClientOptions().apply {
            command = Libbox.CommandStatus
            statusInterval = 1_000_000_000L // 1 second in nanoseconds
        }

        val client = Libbox.newCommandClient(
            object : CommandClientHandler {
                override fun connected() {}
                override fun disconnected(message: String?) {}
                override fun clearLogs() {}
                override fun writeLogs(messageList: StringIterator?) {
                    if (messageList == null) return
                    while (messageList.hasNext()) {
                        VpnEventBus.emitLog(messageList.next())
                    }
                }

                override fun writeStatus(message: StatusMessage?) {
                    if (message == null || !message.trafficAvailable) return
                    VpnEventBus.emitTraffic(
                        downBps = message.downlink.coerceAtLeast(0L),
                        upBps = message.uplink.coerceAtLeast(0L),
                        totalDown = message.downlinkTotal.coerceAtLeast(0L),
                        totalUp = message.uplinkTotal.coerceAtLeast(0L)
                    )
                }

                override fun writeGroups(message: OutboundGroupIterator?) {}
                override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {}
                override fun updateClashMode(newMode: String?) {}
                override fun writeConnections(message: Connections?) {}
            },
            options
        )
        statusClient = client
        runCatching { client.connect() }.onFailure {
            VpnEventBus.emitLog("CommandClient status connect warning: ${it.message}")
        }
    }

    private fun registerNetworkMonitor() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (networkCallback != null) return
        val req = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val lp = cm.getLinkProperties(network)
                notifyInterfaceChanged(lp)
                if (VpnEventBus.currentState == "reconnecting" && boxService != null) {
                    VpnEventBus.emitState("connected")
                    if (notificationsEnabled) updateNotification("Protected · $lastProfileName")
                }
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                notifyInterfaceChanged(linkProperties)
            }

            override fun onLost(network: Network) {
                interfaceListener?.updateDefaultInterface("", -1)
                if (autoReconnect && boxService != null) {
                    VpnEventBus.emitState("reconnecting")
                    if (notificationsEnabled) updateNotification("Reconnecting...")
                    VpnEventBus.emitLog("Physical network lost; awaiting interface recovery...")
                }
            }
        }
        networkCallback = cb
        cm.registerNetworkCallback(req, cb)
    }

    private fun notifyInterfaceChanged(lp: LinkProperties?) {
        val ifaceName = lp?.interfaceName ?: ""
        if (ifaceName.isEmpty()) return
        val ifaceIndex = runCatching { NetworkInterface.getByName(ifaceName)?.index ?: 0 }.getOrDefault(0)
        interfaceListener?.updateDefaultInterface(ifaceName, ifaceIndex)
    }

    private fun stopCoreOnly() {
        runCatching { statusClient?.disconnect() }
        statusClient = null
        runCatching { commandServer?.setService(null) }
        runCatching { boxService?.close() }
        boxService = null
        runCatching { commandServer?.close() }
        commandServer = null
        runCatching { tunFd?.close() }
        tunFd = null
    }

    private fun stopVpn(preserveErrorState: Boolean) {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        networkCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        networkCallback = null
        stopCoreOnly()
        VpnEventBus.emitTraffic(0L, 0L, 0L, 0L)
        VpnEventBus.emitState(if (preserveErrorState) "error" else "disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        VpnEventBus.emitLog("VPN permission revoked by Android system")
        stopVpn(preserveErrorState = false)
        super.onRevoke()
    }

    override fun onDestroy() {
        activeInstance = null
        stopCoreOnly()
        serviceScope.cancel()
        super.onDestroy()
    }

    // --- libbox CommandServerHandler ---
    override fun serviceReload() {
        if (lastConfigJson.isBlank()) throw IllegalStateException("Missing config")
        serviceScope.launch { startTunnelInternal() }
    }

    override fun postServiceClose() {
        stopVpn(preserveErrorState = false)
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        return SystemProxyStatus().apply {
            available = false
            enabled = false
        }
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {}

    // --- libbox v1.10.7 PlatformInterface ---
    override fun openTun(options: TunOptions): Int {
        val builder = Builder()
            .setSession("SUTEMI VPN")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // Exclude our own app package from TUN to avoid infinite proxy loops;
        // in-app checks explicitly route via libbox localhost mixed-in proxy.
        runCatching { builder.addDisallowedApplication(packageName) }

        val inet4 = options.inet4Address
        while (inet4.hasNext()) {
            val prefix = inet4.next()
            builder.addAddress(prefix.address(), prefix.prefix())
        }
        val inet6 = options.inet6Address
        while (inet6.hasNext()) {
            val prefix = inet6.next()
            builder.addAddress(prefix.address(), prefix.prefix())
        }

        if (options.autoRoute) {
            var hasRoute4 = false
            val route4 = options.inet4RouteAddress
            while (route4.hasNext()) {
                val prefix = route4.next()
                builder.addRoute(prefix.address(), prefix.prefix())
                hasRoute4 = true
            }
            if (!hasRoute4) {
                builder.addRoute("0.0.0.0", 0)
            }

            var hasRoute6 = false
            val route6 = options.inet6RouteAddress
            while (route6.hasNext()) {
                val prefix = route6.next()
                builder.addRoute(prefix.address(), prefix.prefix())
                hasRoute6 = true
            }
            if (!hasRoute6) {
                builder.addRoute("::", 0)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val ex4 = options.inet4RouteExcludeAddress
                while (ex4.hasNext()) {
                    val p = ex4.next()
                    runCatching { builder.excludeRoute(IpPrefix(InetAddress.getByName(p.address()), p.prefix())) }
                }
                val ex6 = options.inet6RouteExcludeAddress
                while (ex6.hasNext()) {
                    val p = ex6.next()
                    runCatching { builder.excludeRoute(IpPrefix(InetAddress.getByName(p.address()), p.prefix())) }
                }
            }
        }

        val dnsAddr = runCatching { options.dnsServerAddress?.value }.getOrNull()
        builder.addDnsServer(if (!dnsAddr.isNullOrBlank()) dnsAddr else "1.1.1.1")

        val pfd = builder.establish()
            ?: throw IllegalStateException("Android VpnService.Builder.establish() returned null")
        if (pfd.fd < 0) {
            pfd.close()
            throw IllegalStateException("Android VpnService returned invalid TUN fd=${pfd.fd}")
        }
        tunFd = pfd
        return pfd.fd
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun useProcFS(): Boolean = false
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int
    ): Int = -1

    override fun packageNameByUid(uid: Int): String = packageManager.getNameForUid(uid) ?: ""
    override fun uidByPackageName(packageName: String): Int =
        runCatching { packageManager.getApplicationInfo(packageName, 0).uid }.getOrDefault(-1)

    override fun usePlatformDefaultInterfaceMonitor(): Boolean = true
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = listener
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = null
    }

    override fun usePlatformInterfaceGetter(): Boolean = false
    override fun getInterfaces(): io.nekohasekai.libbox.NetworkInterfaceIterator? = null
    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState? = null
    override fun writeLog(message: String) { VpnEventBus.emitLog(message) }
    override fun sendNotification(notification: LibboxNotification) {}

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(CHANNEL_ID, "SUTEMI VPN Status", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, SutemiVpnService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("SUTEMI VPN")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(0, "Disconnect", stopIntent)
            .build()
    }

    private fun startForegroundWithNotification(text: String) {
        val notif = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notif)
        }
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }
}
