package com.sutemi.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.Libbox

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_VPN_PREPARE = 1001
        private const val CONTROL_CHANNEL = "sutemi.vpn/control"
        private const val STATE_CHANNEL = "sutemi.vpn/state"
        private const val TRAFFIC_CHANNEL = "sutemi.vpn/traffic"
        private const val LOGS_CHANNEL = "sutemi.vpn/logs"
    }

    private var pendingConnectArgs: Map<String, Any?>? = null
    private var pendingConnectResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATE_CHANNEL)
            .setStreamHandler(VpnEventBus.stateHandler)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TRAFFIC_CHANNEL)
            .setStreamHandler(VpnEventBus.trafficHandler)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOGS_CHANNEL)
            .setStreamHandler(VpnEventBus.logHandler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCoreVersion" -> {
                        val version = try {
                            "sing-box ${Libbox.version()}"
                        } catch (_: Throwable) {
                            "sing-box/libbox"
                        }
                        result.success(version)
                    }
                    "connect" -> {
                        val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            pendingConnectArgs = args
                            pendingConnectResult = result
                            startActivityForResult(prepareIntent, REQUEST_VPN_PREPARE)
                        } else {
                            startVpnService(args)
                            result.success(null)
                        }
                    }
                    "disconnect" -> {
                        val intent = Intent(this, SutemiVpnService::class.java).apply {
                            action = SutemiVpnService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "reconnect" -> {
                        val intent = Intent(this, SutemiVpnService::class.java).apply {
                            action = SutemiVpnService.ACTION_RECONNECT
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "getState" -> {
                        result.success(VpnEventBus.currentState)
                    }
                    "getLastError" -> {
                        result.success(VpnEventBus.lastError)
                    }
                    "isAlwaysOnSupported" -> {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    }
                    "isLockdownEnabled" -> {
                        val lockdown = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            SutemiVpnService.activeInstance?.isLockdownEnabled ?: false
                        } else {
                            false
                        }
                        result.success(lockdown)
                    }
                    "openSystemVpnSettings" -> {
                        startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                        result.success(null)
                    }
                    "getLocalProxyPort" -> {
                        result.success(2080)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PREPARE) {
            val res = pendingConnectResult
            val args = pendingConnectArgs
            pendingConnectResult = null
            pendingConnectArgs = null
            if (resultCode == Activity.RESULT_OK && args != null) {
                startVpnService(args)
                res?.success(null)
            } else {
                res?.error("VPN_DENIED", "User declined Android VPN permission", null)
            }
        }
    }

    private fun startVpnService(args: Map<String, Any?>) {
        val prefs = getSharedPreferences("sutemi_vpn_runtime", MODE_PRIVATE)
        prefs.edit()
            .putString("configJson", args["configJson"] as? String ?: "")
            .putString("profileName", args["profileName"] as? String ?: "SUTEMI")
            .putBoolean("autoReconnect", args["autoReconnect"] as? Boolean ?: true)
            .putBoolean("notificationsEnabled", args["notificationsEnabled"] as? Boolean ?: true)
            .apply()

        val intent = Intent(this, SutemiVpnService::class.java).apply {
            action = SutemiVpnService.ACTION_START
            putExtra("configJson", args["configJson"] as? String ?: "")
            putExtra("profileName", args["profileName"] as? String ?: "SUTEMI")
            putExtra("autoReconnect", args["autoReconnect"] as? Boolean ?: true)
            putExtra("notificationsEnabled", args["notificationsEnabled"] as? Boolean ?: true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
