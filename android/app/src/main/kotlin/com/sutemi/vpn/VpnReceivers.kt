package com.sutemi.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VpnTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = if (VpnEventBus.currentState == "connected") Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            label = "SUTEMI VPN"
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val isConnected = VpnEventBus.currentState == "connected"
        val intent = Intent(this, SutemiVpnService::class.java).apply {
            action = if (isConnected) SutemiVpnService.ACTION_STOP else SutemiVpnService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isConnected) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences("sutemi_vpn_runtime", Context.MODE_PRIVATE)
        val config = prefs.getString("configJson", null) ?: return
        val autoStart = prefs.getBoolean("autoConnectOnBoot", false)
        if (!autoStart || config.isBlank()) return
        if (VpnService.prepare(context) != null) return

        val svc = Intent(context, SutemiVpnService::class.java).apply {
            action = SutemiVpnService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc)
        } else {
            context.startService(svc)
        }
    }
}
