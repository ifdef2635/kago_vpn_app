package net.usekago.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android VPN lifecycle shell. The tunnel is established only after the native core library
 * is present; failed core startup closes the TUN descriptor immediately (fail closed).
 */
class KaGoVpnService : VpnService() {
    // Set in onDestroy: a start still running on the core thread must not
    // leave the core up without the service (nothing could stop it then).
    @Volatile private var destroyed = false
    @Volatile private var desired = false
    private var recoveryAttempts = 0
    private var recoveryTask: ScheduledFuture<*>? = null
    private var healthTask: ScheduledFuture<*>? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var currentConfig: String? = null
    private var expiresAt = 0L
    private var guest = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        watchNetworks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                // A later START (fast taps on the tile) supersedes this stop.
                val request = requests.incrementAndGet()
                desired = false
                recoveryTask?.cancel(false)
                healthTask?.cancel(false)
                isStarting = false
                onCoreThread { if (request == requests.get()) stopTunnel("disconnected", stopStartId = startId) }
                return START_NOT_STICKY
            }
            ACTION_START -> {
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
                val preferences = getSharedPreferences(PREFS, MODE_PRIVATE)
                expiresAt = if (intent.hasExtra(EXTRA_EXPIRES_AT)) intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
                    else preferences.getLong(KEY_EXPIRES_AT, 0L)
                guest = if (intent.hasExtra(EXTRA_GUEST)) intent.getBooleanExtra(EXTRA_GUEST, false)
                    else preferences.getBoolean(KEY_GUEST, false)
                if (!guest && expiresAt > 0 && System.currentTimeMillis() >= expiresAt) {
                    KaGoVpnEvents.emit("error", getString(R.string.vpn_subscription_expired))
                    removeForegroundNotification()
                    stopSelf(startId)
                    return START_NOT_STICKY
                }
                preferences.edit().putLong(KEY_EXPIRES_AT, expiresAt).putBoolean(KEY_GUEST, guest).apply()
                currentConfig = configPath
                desired = true
                recoveryAttempts = 0
                recoveryTask?.cancel(false)
                val request = requests.incrementAndGet()
                isStarting = true
                KaGoVpnEvents.emit("starting")
                KaGoTileService.requestUpdate(this)
                onCoreThread { if (request == requests.get()) startTunnel(configPath, request) }
                return START_NOT_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    private fun onCoreThread(task: () -> Unit) {
        runCatching { coreThread.execute { runCatching(task) } }
    }

    private fun watchNetworks() {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = queueNetworkCheck()
            override fun onLost(network: Network) = queueNetworkCheck()
        }
        runCatching { connectivity.registerNetworkCallback(request, callback) }
            .onSuccess { networkCallback = callback }
    }

    private var networkTask: ScheduledFuture<*>? = null

    private fun queueNetworkCheck() {
        onCoreThread {
            networkTask?.cancel(false)
            networkTask = coreThread.schedule({
                if (!desired || destroyed) return@schedule
                if (!physicalNetworkAvailable()) return@schedule
                if (isRecovering) {
                    scheduleRecovery(immediate = true)
                } else if (coreRunning && !probeExternalTwice()) {
                    beginRecovery(immediate = true)
                }
            }, 2, TimeUnit.SECONDS)
        }
    }

    private fun physicalNetworkAvailable(): Boolean = runCatching {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        connectivity.allNetworks.any { network ->
            val capabilities = connectivity.getNetworkCapabilities(network)
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
    }.getOrDefault(false)

    private fun startHealthChecks() {
        healthTask?.cancel(false)
        healthTask = coreThread.scheduleWithFixedDelay({
            if (desired && coreRunning && !probeLocal()) beginRecovery()
        }, 30, 30, TimeUnit.SECONDS)
    }

    private fun controllerRoot(): JSONObject? = currentConfig?.let { path ->
        runCatching { JSONObject(File(path).readText()) }.getOrNull()
    }

    private fun controllerRequest(path: String, timeoutMs: Int): JSONObject? {
        val root = controllerRoot() ?: return null
        val endpoint = root.optString("external-controller", "127.0.0.1:9090")
        val base = runCatching { URI("http://$endpoint") }.getOrNull() ?: return null
        if (base.host !in listOf("127.0.0.1", "localhost") ||
            base.port !in 1..65535 ||
            base.userInfo != null ||
            base.rawPath !in listOf("", "/") ||
            base.rawQuery != null ||
            base.rawFragment != null
        ) return null
        val connection = runCatching {
            base.resolve(path).toURL().openConnection() as HttpURLConnection
        }.getOrNull() ?: return null
        return try {
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            root.optString("secret").takeIf { it.isNotEmpty() }?.let {
                connection.setRequestProperty("Authorization", "Bearer $it")
            }
            if (connection.responseCode !in 200..299) return null
            JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun probeLocal(): Boolean = controllerRequest("/version", 3_000) != null

    private fun probeExternalTwice(): Boolean {
        if (probeExternal()) return true
        Thread.sleep(2_000)
        return !desired || probeExternal()
    }

    private fun probeExternal(): Boolean {
        if (!probeLocal()) return false
        val groups = controllerRoot()?.optJSONArray("proxy-groups") ?: return false
        val selected = (0 until groups.length()).asSequence()
            .mapNotNull { groups.optJSONObject(it) }
            .firstOrNull { it.optString("name").isNotBlank() && it.optString("name") != "GLOBAL" }
            ?: return false
        val groupName = selected.optString("name")
        val proxies = controllerRequest("/proxies", 3_000)?.optJSONObject("proxies")
        val activeNode = proxies?.optJSONObject(groupName)?.optString("now")
            ?.takeIf { it.isNotBlank() } ?: groupName
        val name = URLEncoder.encode(activeNode, "UTF-8").replace("+", "%20")
        val target = if (guest) "https://telegram.org/" else
            selected.optString("url").ifBlank { "https://www.gstatic.com/generate_204" }
        val url = URLEncoder.encode(target, "UTF-8")
        return controllerRequest("/proxies/$name/delay?url=$url&timeout=5000", 7_000)
            ?.optInt("delay", -1)?.let { it >= 0 } == true
    }

    private fun beginRecovery(immediate: Boolean = false) {
        if (!desired || destroyed) return
        healthTask?.cancel(false)
        stopCore()
        isConnected = false
        isStarting = false
        isRecovering = true
        runningConfig = null
        KaGoVpnEvents.emit("recovering")
        KaGoTileService.requestUpdate(this)
        updateNotification(getString(R.string.vpn_recovering))
        scheduleRecovery(immediate)
    }

    private fun scheduleRecovery(immediate: Boolean = false) {
        recoveryTask?.cancel(false)
        if (!desired || destroyed) return
        val delay = if (immediate) 0L else RETRY_DELAYS[recoveryAttempts.coerceAtMost(RETRY_DELAYS.lastIndex)]
        if (!immediate) recoveryAttempts++
        recoveryTask = coreThread.schedule({
            val path = currentConfig
            if (!desired || destroyed || path == null) return@schedule
            if (!File(path).isFile) {
                stopTunnel("error", getString(R.string.vpn_config_missing_recovery), -1)
                return@schedule
            }
            if (!guest && expiresAt > 0 && System.currentTimeMillis() >= expiresAt) {
                stopTunnel("error", getString(R.string.vpn_subscription_expired), -1)
                return@schedule
            }
            if (VpnService.prepare(this) != null) {
                stopTunnel("revoked", getString(R.string.vpn_permission_required), -1)
                return@schedule
            }
            if (!physicalNetworkAvailable()) {
                scheduleRecovery()
                return@schedule
            }
            val request = requests.get()
            startTunnel(path, request)
        }, delay, TimeUnit.SECONDS)
    }

    private fun startTunnel(configPath: String, request: Int) {
        if (destroyed || request != requests.get()) return
        if (coreRunning) {
            // Already up (a stop was superseded by this start).
            isConnected = true
            isStarting = false
            isRecovering = false
            recoveryAttempts = 0
            recoveryTask?.cancel(false)
            startHealthChecks()
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
                .addDnsServer(IPV4_DNS)
            if (ipv6Enabled) {
                builder.addAddress(IPV6_ADDRESS, 126)
                    .addDnsServer(IPV6_DNS)
            }
            val tun = root.optJSONObject("tun")
            addRoutes(builder, tun, ipv6Enabled)
            AppRouting.apply(this, builder, tun)
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
            isRecovering = false
            recoveryAttempts = 0
            recoveryTask?.cancel(false)
            startHealthChecks()
            KaGoTileService.requestUpdate(this)
            updateNotification(getString(R.string.vpn_connected))
            KaGoVpnEvents.emit("connected")
        } catch (error: Throwable) {
            runCatching { descriptor?.close() }
            stopCore()
            if (request == requests.get()) {
                if (desired &&
                    File(configPath).isFile &&
                    error !is org.json.JSONException &&
                    error !is LinkageError &&
                    error !is ClassNotFoundException &&
                    VpnService.prepare(this) == null
                ) {
                    beginRecovery()
                } else {
                    stopTunnel("error", error.message ?: getString(R.string.vpn_core_failed), stopStartId = -1)
                }
            }
        }
    }

    /**
     * The subscription's routes (`route-address` without
     * `route-exclude-address`, computed by the app: `AndroidRoutes` in
     * lib/core/network/android_routes.dart), so local networks bypass the
     * VPN; everything when the subscription sets none or a route is invalid.
     */
    private fun addRoutes(builder: Builder, tun: JSONObject?, ipv6Enabled: Boolean) {
        val list = tun?.optJSONArray(ROUTES_KEY)
        val routes = mutableListOf<Pair<String, Int>>()
        if (list != null) {
            for (i in 0 until list.length()) {
                val parts = list.optString(i).split('/')
                val prefix = parts.getOrNull(1)?.toIntOrNull()
                if (parts.size != 2 || prefix == null) {
                    routes.clear()
                    break
                }
                if (!parts[0].contains(':') || ipv6Enabled) routes.add(parts[0] to prefix)
            }
        }
        if (routes.none { !it.first.contains(':') }) {
            builder.addRoute("0.0.0.0", 0)
            if (ipv6Enabled) builder.addRoute("::", 0)
            return
        }
        for ((address, prefix) in routes) builder.addRoute(address, prefix)
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
        desired = false
        recoveryTask?.cancel(false)
        healthTask?.cancel(false)
        networkTask?.cancel(false)
        stopCore()
        isConnected = false
        isStarting = false
        isRecovering = false
        runningConfig = null
        KaGoVpnEvents.emit(state, message)
        KaGoTileService.requestUpdate(this)
        removeForegroundNotification()
        if (stopStartId >= 0) stopSelf(stopStartId) else stopSelf()
    }

    /**
     * Also cancels the notification by id: it was last updated with notify(),
     * and some OEM systems left "KaGo VPN connected" behind after
     * stopForeground alone, with the VPN already off.
     */
    @Suppress("DEPRECATION")
    private fun removeForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        runCatching { getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID) }
    }

    override fun onRevoke() {
        val request = requests.incrementAndGet()
        desired = false
        recoveryTask?.cancel(false)
        onCoreThread { if (request == requests.get()) stopTunnel("revoked", stopStartId = -1) }
    }

    override fun onDestroy() {
        destroyed = true
        desired = false
        recoveryTask?.cancel(false)
        healthTask?.cancel(false)
        networkTask?.cancel(false)
        networkCallback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
        isConnected = false
        runningConfig = null
        isStarting = false
        isRecovering = false
        // On the core thread, after anything this instance queued, and before
        // the start of a new instance: start and stop never overlap.
        onCoreThread { stopCore() }
        removeForegroundNotification()
        // Destroyed by the system without a stop: tell the UI it is off
        // (after a stop or an error this sends nothing, the message stays).
        KaGoVpnEvents.resync()
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
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            immutable or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, KaGoVpnService::class.java).setAction(ACTION_STOP),
            immutable or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val disconnect = Notification.Action.Builder(0, getString(R.string.vpn_disconnect), stop).build()
        return builder.setContentTitle("KaGo VPN")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_kago)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .addAction(disconnect)
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
        private val RETRY_DELAYS = longArrayOf(2, 5, 15, 30, 60, 300)
        const val ACTION_START = "net.usekago.app.START"
        const val ACTION_STOP = "net.usekago.app.STOP"
        const val EXTRA_CONFIG_PATH = "configPath"
        const val EXTRA_EXPIRES_AT = "expiresAt"
        const val EXTRA_GUEST = "guest"
        private const val CHANNEL_ID = "kago_vpn_status"
        private const val NOTIFICATION_ID = 7401
        private const val PREFS = "kago_vpn_service"
        private const val KEY_CONFIG_PATH = "config_path"
        private const val KEY_EXPIRES_AT = "expires_at"
        private const val KEY_GUEST = "guest"
        // The tunnel networks are also in AndroidRoutes (Dart): keep them equal.
        private const val IPV4_ADDRESS = "172.19.0.1"
        private const val IPV4_CIDR = "172.19.0.1/30"
        private const val IPV4_DNS = "172.19.0.2"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1"
        private const val IPV6_CIDR = "fdfe:dcba:9876::1/126"
        private const val IPV6_DNS = "fdfe:dcba:9876::2"
        private const val TUN_MTU = 1500
        private const val ROUTES_KEY = "kago-android-routes"
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
        private val coreThread = Executors.newSingleThreadScheduledExecutor()
        /** The latest start/stop request; older queued work is skipped. */
        private val requests = AtomicInteger()
        @Volatile private var coreRunning = false
        @Volatile var isStarting: Boolean = false
            private set
        @Volatile var isRecovering: Boolean = false
            private set

        /**
         * The profile the tile starts. Called after a subscription import, so
         * the tile does not keep starting the guest (Telegram-only) profile.
         * Only files of the app itself are accepted.
         */
        fun rememberConfigPath(context: Context, path: String, expiresAt: Long): Boolean {
            val file = File(path).canonicalFile
            val home = File(context.applicationInfo.dataDir).canonicalFile
            if (!file.isFile || !file.path.startsWith(home.path + File.separator)) return false
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_CONFIG_PATH, file.path)
                .putLong(KEY_EXPIRES_AT, expiresAt)
                .putBoolean(KEY_GUEST, false)
                .apply()
            return true
        }

        /** Sign-out: the tile opens the app instead of starting a profile. */
        fun forgetConfigPath(context: Context): Boolean {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .remove(KEY_CONFIG_PATH)
                .remove(KEY_EXPIRES_AT)
                .remove(KEY_GUEST)
                .apply()
            return true
        }

        /** The app prepared a profile once, so the tile can start headless. */
        fun hasPreparedConfig(context: Context): Boolean {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val path = preferences.getString(KEY_CONFIG_PATH, null)
            val expiresAt = preferences.getLong(KEY_EXPIRES_AT, 0L)
            return !path.isNullOrBlank() && File(path).isFile &&
                (preferences.getBoolean(KEY_GUEST, false) || expiresAt <= 0 || System.currentTimeMillis() < expiresAt)
        }
    }
}
