package net.usekago.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Android VPN lifecycle shell. The tunnel is established only after the native core library
 * is present; failed core startup closes the TUN descriptor immediately (fail closed).
 */
class KaGoVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var coreStarted = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                worker.execute { stopTunnel("disconnected", stopSelfAfter = true) }
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                startForegroundCompat(notification(getString(R.string.vpn_preparing)))
                val requestedPath = intent?.getStringExtra(EXTRA_CONFIG_PATH)
                val configPath = requestedPath ?: getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_CONFIG_PATH, null)
                if (configPath.isNullOrBlank()) {
                    KaGoVpnEvents.emit("error", getString(R.string.vpn_no_config_path))
                    removeForegroundNotification()
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(KEY_CONFIG_PATH, configPath).apply()
                KaGoVpnEvents.emit("starting")
                worker.execute { startTunnel(configPath) }
                return START_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    private fun startTunnel(configPath: String) {
        if (coreStarted) return
        var descriptor: ParcelFileDescriptor? = null
        try {
            val config = File(configPath)
            if (!config.isFile) throw IllegalStateException(getString(R.string.vpn_config_not_found, configPath))
            val root = JSONObject(config.readText())
            val tun = root.optJSONObject("tun") ?: JSONObject()
            val ipv6Enabled = root.optBoolean("ipv6", false)
            val stack = tun.optString("stack", "mixed").ifBlank { "mixed" }
            val tunnelAddress = if (ipv6Enabled) "$IPV4_CIDR,$IPV6_CIDR" else IPV4_CIDR
            val tunnelDns = if (ipv6Enabled) "$IPV4_DNS,$IPV6_DNS" else IPV4_DNS
            // Loads before establish(): without the native core, never capture or blackhole user traffic.
            Class.forName(MihomoNativeCore::class.java.name)
            val builder = Builder()
                .setSession("KaGo VPN")
                .setMtu(TUN_MTU)
                .addAddress(IPV4_ADDRESS, 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer(IPV4_DNS)
            if (ipv6Enabled) {
                builder.addAddress(IPV6_ADDRESS, 126)
                    .addRoute("::", 0)
                    .addDnsServer(IPV6_DNS)
            }
            AppRouting.apply(this, builder)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setBlocking(false)
            descriptor = builder.establish() ?: throw IllegalStateException(getString(R.string.vpn_no_tun))

            val result = MihomoNativeCore.start(
                this,
                config.absolutePath,
                config.parentFile?.absolutePath.orEmpty(),
                descriptor.fd,
                TUN_MTU,
                stack,
                tunnelAddress,
                tunnelDns,
            )
            if (result != 0) {
                val detail = runCatching { MihomoNativeCore.lastError() }.getOrNull().orEmpty()
                throw IllegalStateException(detail.ifBlank { getString(R.string.vpn_core_code, result) })
            }
            // The native ABI contract requires the core to dup(tunFd) before returning success.
            descriptor.close()
            descriptor = null
            coreStarted = true
            isConnected = true
            updateNotification(getString(R.string.vpn_connected))
            KaGoVpnEvents.emit("connected")
        } catch (error: Throwable) {
            runCatching { descriptor?.close() }
            runCatching { MihomoNativeCore.stop() }
            coreStarted = false
            isConnected = false
            stopTunnel("error", error.message ?: getString(R.string.vpn_core_failed), stopSelfAfter = true)
        }
    }

    @Suppress("DEPRECATION")
    private fun stopTunnel(state: String, message: String? = null, stopSelfAfter: Boolean = false) {
        if (coreStarted) runCatching { MihomoNativeCore.stop() }
        coreStarted = false
        isConnected = false
        KaGoVpnEvents.emit(state, message)
        removeForegroundNotification()
        if (stopSelfAfter) stopSelf()
    }

    @Suppress("DEPRECATION")
    private fun removeForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
    }

    override fun onRevoke() {
        worker.execute { stopTunnel("revoked", stopSelfAfter = true) }
    }

    override fun onDestroy() {
        if (coreStarted) runCatching { MihomoNativeCore.stop() }
        coreStarted = false
        isConnected = false
        worker.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "KaGo VPN", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun notification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        return builder.setContentTitle("KaGo VPN")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_kago)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(text: String) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification(text))
    }

    companion object {
        const val ACTION_START = "net.usekago.vpn.START"
        const val ACTION_STOP = "net.usekago.vpn.STOP"
        const val EXTRA_CONFIG_PATH = "configPath"
        private const val CHANNEL_ID = "kago_vpn_status"
        private const val NOTIFICATION_ID = 7401
        private const val PREFS = "kago_vpn_service"
        private const val KEY_CONFIG_PATH = "config_path"
        private const val IPV4_ADDRESS = "172.19.0.1"
        private const val IPV4_CIDR = "172.19.0.1/30"
        private const val IPV4_DNS = "172.19.0.2"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1"
        private const val IPV6_CIDR = "fdfe:dcba:9876::1/126"
        private const val IPV6_DNS = "fdfe:dcba:9876::2"
        private const val TUN_MTU = 1500
        @Volatile var isConnected: Boolean = false
            private set
    }
}
