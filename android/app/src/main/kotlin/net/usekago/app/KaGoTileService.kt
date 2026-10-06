package net.usekago.app

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile, as in FlClashX: turns the VPN on and off from the
 * notification shade. With the VPN permission granted and a profile prepared
 * by the app once, the start is headless (the service reuses the last
 * prepared config); otherwise the tile opens the app.
 */
class KaGoTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        syncTile()
    }

    override fun onClick() {
        val now = SystemClock.elapsedRealtime()
        if (now - lastClick < DEBOUNCE_MS) return
        lastClick = now

        if (KaGoVpnService.isConnected || KaGoVpnService.isStarting) {
            startService(Intent(this, KaGoVpnService::class.java).setAction(KaGoVpnService.ACTION_STOP))
            showState(active = false)
            return
        }
        if (VpnService.prepare(this) != null || !KaGoVpnService.hasPreparedConfig(this)) {
            // First start: the app asks for the VPN permission and prepares the profile.
            openApp()
            return
        }
        val start = Intent(this, KaGoVpnService::class.java).setAction(KaGoVpnService.ACTION_START)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(start) else startService(start)
        }.onSuccess {
            showState(active = true)
        }.onFailure {
            openApp()
        }
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }

    private fun syncTile() = showState(KaGoVpnService.isConnected || KaGoVpnService.isStarting)

    private fun showState(active: Boolean) {
        val tile = qsTile ?: return
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "KaGo VPN"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getString(if (active) R.string.tile_on else R.string.tile_off)
        }
        tile.updateTile()
    }

    companion object {
        private const val DEBOUNCE_MS = 600L
        @Volatile private var lastClick = 0L

        /** Asks the system to refresh the tile after the VPN state changed. */
        fun requestUpdate(context: Context) {
            runCatching {
                requestListeningState(context, ComponentName(context, KaGoTileService::class.java))
            }
        }
    }
}
