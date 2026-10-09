package net.usekago.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android VPN lifecycle shell. The tunnel is established only after the native core library
 * is present; failed core startup closes the TUN descriptor immediately (fail closed).
 */
class KaGoVpnService : VpnService() {
    // Set in onDestroy: a start still running on the core thread must not
    // leave the core up without the service (nothing could stop it then).
    @Volatile private var destroyed = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                // A later START (fast taps on the tile) supersedes this stop.
                val request = requests.incrementAndGet()
                isStarting = false
                onCoreThread { if (request == requests.get()) stopTunnel("disconnected", stopStartId = startId) }
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
                val request = requests.incrementAndGet()
                isStarting = true
                KaGoVpnEvents.emit("starting")
                KaGoTileService.requestUpdate(this)
                onCoreThread { if (request == requests.get()) startTunnel(configPath, request) }
                return START_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    private fun onCoreThread(task: () -> Unit) {
        runCatching { coreThread.execute { runCatching(task) } }
    }

    private fun startTunnel(configPath: String, request: Int) {
        if (destroyed) return
        if (coreRunning) {
            // Already up (a stop was superseded by this start).
            isConnected = true
            isStarting = false
            KaGoTileService.requestUpdate(this)
            updateNotification(getString(R.string.vpn_connected))
            KaGoVpnEvents.emit("connected")
            return
        }
        var descriptor: ParcelFileDescriptor? = null
        try {
            val config = File(configPath)
            if (!config.isFile) throw IllegalStateException(getString(R.string.vpn_config_not_found, configPath))
            val root = JSONObject(config.readText())
            val ipv6Enabled = root.optBoolean("ipv6", false)
            // The embedded core is built without gVisor (no with_gvisor tag), so
            // "gvisor" and "mixed" from a panel template cannot start; use the
            // system stack whatever the subscription asks for.
            val stack = "system"
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
            AppRouting.apply(this, builder, root.optJSONObject("tun"))
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
            coreRunning = true
            // Stopped or destroyed while the core was starting: the later
            // request runs next on this thread; never leave the core orphaned.
            if (destroyed) {
                stopCore()
                return
            }
            if (request != requests.get()) return
            runningConfig = configPath
            isConnected = true
            isStarting = false
            KaGoTileService.requestUpdate(this)
            updateNotification(getString(R.string.vpn_connected))
            KaGoVpnEvents.emit("connected")
        } catch (error: Throwable) {
            runCatching { descriptor?.close() }
            stopCore()
            if (request == requests.get()) {
                stopTunnel("error", error.message ?: getString(R.string.vpn_core_failed), stopStartId = -1)
            }
        }
    }

    private fun stopCore() {
        // Idempotent in the core; called even if this instance did not start
        // it (a previous instance may have).
        runCatching { MihomoNativeCore.stop() }
        coreRunning = false
    }

    /**
     * Stops the core and the service. [stopStartId] is the id of the STOP
     * command: stopSelf(id) is ignored when a newer START was delivered
     * meanwhile, so a fast off/on never loses the "on". -1 stops in any case.
     */
    private fun stopTunnel(state: String, message: String? = null, stopStartId: Int) {
        stopCore()
        isConnected = false
        isStarting = false
        runningConfig = null
        KaGoVpnEvents.emit(state, message)
        KaGoTileService.requestUpdate(this)
        removeForegroundNotification()
        if (stopStartId >= 0) stopSelf(stopStartId) else stopSelf()
    }

    @Suppress("DEPRECATION")
    private fun removeForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
    }

    override fun onRevoke() {
        val request = requests.incrementAndGet()
        onCoreThread { if (request == requests.get()) stopTunnel("revoked", stopStartId = -1) }
    }

    override fun onDestroy() {
        destroyed = true
        isConnected = false
        runningConfig = null
        isStarting = false
        // On the core thread, after anything this instance queued, and before
        // the start of a new instance: start and stop never overlap.
        onCoreThread { stopCore() }
        KaGoTileService.requestUpdate(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    // uid -> (package, time). Short-lived: Android reuses the uid of an
    // uninstalled app, and a stale name would route a new app by old rules.
    private val packageByUid = ConcurrentHashMap<Int, Pair<String, Long>>()

    /**
     * Called by the native core (JNI) for PROCESS-NAME rules: the package that
     * owns a connection seen on the TUN. This makes the subscription's own app
     * routing (e.g. Russian apps -> DIRECT) work without per-app settings.
     * Android 10+ only; older systems simply do not match such rules.
     */
    fun resolvePackage(protocol: Int, srcIp: String, srcPort: Int, dstIp: String, dstPort: Int): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val uid = runCatching {
            getSystemService(ConnectivityManager::class.java).getConnectionOwnerUid(
                protocol,
                InetSocketAddress(InetAddress.getByName(srcIp), srcPort),
                InetSocketAddress(InetAddress.getByName(dstIp), dstPort),
            )
        }.getOrDefault(-1)
        if (uid < 0) return null
        val now = android.os.SystemClock.elapsedRealtime()
        packageByUid[uid]?.let { (name, at) -> if (now - at < PACKAGE_CACHE_MS) return name }
        // A shared uid has several packages: no single name to match rules on.
        val packages = runCatching { packageManager.getPackagesForUid(uid) }.getOrNull()
        val name = packages?.singleOrNull() ?: return null
        packageByUid[uid] = name to now
        return name
    }

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
        private const val PACKAGE_CACHE_MS = 30_000L
        const val ACTION_START = "net.usekago.app.START"
        const val ACTION_STOP = "net.usekago.app.STOP"
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

        /** The profile the running core was started with (for the app's labels). */
        @Volatile var runningConfig: String? = null
            private set

        /**
         * Every core start/stop of every service instance runs on this one
         * thread. With a thread per instance, fast taps on the tile let a new
         * instance start the (process-wide) core while the old one was still
         * starting or stopping it, and the connection hung at "starting".
         */
        private val coreThread = Executors.newSingleThreadExecutor()
        /** The latest start/stop request; older queued work is skipped. */
        private val requests = AtomicInteger()
        @Volatile private var coreRunning = false
        @Volatile var isStarting: Boolean = false
            private set

        /**
         * The profile the tile starts. Called after a subscription import, so
         * the tile does not keep starting the guest (Telegram-only) profile.
         * Only files of the app itself are accepted.
         */
        fun rememberConfigPath(context: Context, path: String): Boolean {
            val file = File(path).canonicalFile
            val home = File(context.applicationInfo.dataDir).canonicalFile
            if (!file.isFile || !file.path.startsWith(home.path + File.separator)) return false
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_CONFIG_PATH, file.path).apply()
            return true
        }

        /** Sign-out: the tile opens the app instead of starting a profile. */
        fun forgetConfigPath(context: Context): Boolean {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_CONFIG_PATH).apply()
            return true
        }

        /** The app prepared a profile once, so the tile can start headless. */
        fun hasPreparedConfig(context: Context): Boolean {
            val path = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CONFIG_PATH, null)
            return !path.isNullOrBlank() && File(path).isFile
        }
    }
}
