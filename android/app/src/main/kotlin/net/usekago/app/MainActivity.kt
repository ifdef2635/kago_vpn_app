package net.usekago.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.provider.Settings
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "net.usekago.app/service"
    private val eventChannelName = "net.usekago.app/events"
    private val permissionRequestCode = 7402
    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfigPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // The user may have switched display mode or moved to another display.
        requestHighestRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Flutter's SurfaceView exists by now; vote on its surface too.
        if (hasFocus) voteSurfaceFrameRate()
    }

    /** Highest refresh rate of the current display mode set, 0 if unknown. */
    private var highestRefreshRate = 0f

    /**
     * Many phones keep apps at 60 Hz unless they ask for more. Pick the mode with
     * the highest refresh rate at the current resolution so Flutter animations
     * and scrolling run at the panel's full rate (90/120/144 Hz).
     */
    @Suppress("DEPRECATION")
    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        runCatching {
            val currentDisplay = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                windowManager.defaultDisplay
            }) ?: return@runCatching
            val current = currentDisplay.mode
            val best = currentDisplay.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return@runCatching
            highestRefreshRate = best.refreshRate
            val params = window.attributes
            params.preferredDisplayModeId = best.modeId
            // Some OEM schedulers (MIUI/HyperOS, ColorOS) read only this one.
            params.preferredRefreshRate = best.refreshRate
            window.attributes = params
        }
        voteSurfaceFrameRate()
    }

    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) = applyFrameRate(holder.surface)
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) =
            applyFrameRate(holder.surface)
        override fun surfaceDestroyed(holder: SurfaceHolder) {}
    }
    private val watchedSurfaces = mutableSetOf<SurfaceView>()

    /**
     * Flutter draws into a SurfaceView. On adaptive panels (LTPO/VRR: Samsung,
     * Pixel, Xiaomi…) the system picks the rate from each surface's own vote,
     * and a surface without one is held at 60 Hz even though the display mode
     * is 120 Hz. So the Flutter surface asks for the panel's top rate itself.
     */
    private fun voteSurfaceFrameRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || highestRefreshRate <= 0f) return
        runCatching {
            surfaceViews(window.decorView).forEach { view ->
                if (watchedSurfaces.add(view)) view.holder.addCallback(surfaceCallback)
                applyFrameRate(view.holder.surface)
            }
        }
    }

    private fun surfaceViews(root: View): List<SurfaceView> = when (root) {
        is SurfaceView -> listOf(root)
        is ViewGroup -> (0 until root.childCount).flatMap { surfaceViews(root.getChildAt(it)) }
        else -> emptyList()
    }

    private fun applyFrameRate(surface: Surface?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (surface == null || !surface.isValid || highestRefreshRate <= 0f) return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                surface.setFrameRate(
                    highestRefreshRate,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
                )
            } else {
                surface.setFrameRate(highestRefreshRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> requestVpnPermission(call.argument<String>("configPath"), result)
                "disconnect" -> {
                    startVpnService(Intent(this, KaGoVpnService::class.java).setAction(KaGoVpnService.ACTION_STOP))
                    result.success(mapOf("state" to "stopping"))
                }
                "status" -> result.success(mapOf("state" to if (KaGoVpnService.isConnected) "connected" else "disconnected"))
                "coreVersion" -> result.success(runCatching { MihomoNativeCore.version() }.getOrNull())
                "installedApps" -> Thread {
                    val apps = runCatching { AppRouting.launchableApps(this) }.getOrDefault(emptyList())
                    runOnUiThread { result.success(apps) }
                }.start()
                "getAppRouting" -> {
                    val (mode, packages) = AppRouting.load(this)
                    result.success(mapOf("mode" to mode, "packages" to packages.toList()))
                }
                "setAppRouting" -> {
                    AppRouting.save(
                        this,
                        call.argument<String>("mode") ?: "off",
                        call.argument<List<String>>("packages") ?: emptyList(),
                    )
                    result.success(true)
                }
                "deviceInfo" -> result.success(deviceInfo())
                "openVpnSettings" -> {
                    // "Always-on VPN" and "Block connections without VPN" (kill switch) are
                    // system settings; an app cannot turn them on itself.
                    val opened = runCatching {
                        startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }.isSuccess
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                KaGoVpnEvents.attach(events)
                KaGoVpnEvents.emit(if (KaGoVpnService.isConnected) "connected" else "disconnected")
            }
            override fun onCancel(arguments: Any?) { KaGoVpnEvents.attach(null) }
        })
    }

    /**
     * Subscription device headers (x-hwid etc.). ANDROID_ID is per app signing
     * key and survives reinstalls, so the panel keeps counting one device; the
     * Dart side only sends a hash of it.
     */
    @SuppressLint("HardwareIds")
    private fun deviceInfo(): Map<String, String> {
        val id = runCatching {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        }.getOrNull().orEmpty()
        val model = listOf(Build.MANUFACTURER, Build.MODEL)
            .filter { it.isNotBlank() }
            .distinctBy { it.lowercase() }
            .joinToString(" ")
        return mapOf("id" to id, "os" to Build.VERSION.RELEASE.orEmpty(), "model" to model)
    }

    @Suppress("DEPRECATION")
    private fun requestVpnPermission(configPath: String?, result: MethodChannel.Result) {
        if (configPath.isNullOrBlank()) {
            result.error("missing_config", getString(R.string.vpn_missing_config), null)
            return
        }
        if (pendingResult != null) {
            result.error("request_in_progress", getString(R.string.vpn_request_in_progress), null)
            return
        }
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent == null) {
            launchVpnService(configPath, result)
        } else {
            pendingConfigPath = configPath
            pendingResult = result
            startActivityForResult(prepareIntent, permissionRequestCode)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != permissionRequestCode) return
        val result = pendingResult
        val configPath = pendingConfigPath
        pendingResult = null
        pendingConfigPath = null
        if (result == null) return
        if (resultCode == Activity.RESULT_OK && !configPath.isNullOrBlank()) {
            launchVpnService(configPath, result)
        } else {
            result.error("vpn_permission_denied", getString(R.string.vpn_permission_denied), null)
        }
    }

    private fun launchVpnService(configPath: String, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, KaGoVpnService::class.java)
                .setAction(KaGoVpnService.ACTION_START)
                .putExtra(KaGoVpnService.EXTRA_CONFIG_PATH, configPath)
            startVpnService(intent)
            result.success(mapOf("state" to "starting"))
        } catch (error: Exception) {
            result.error("vpn_service_start_failed", error.message ?: getString(R.string.vpn_service_start_failed), null)
        }
    }

    private fun startVpnService(intent: Intent) {
        if (intent.action == KaGoVpnService.ACTION_STOP) {
            startService(intent)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}

/** Main-thread-safe bridge for service state and native core diagnostics. */
object KaGoVpnEvents {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink?) { sink = eventSink }

    fun emit(state: String, message: String? = null) {
        val event = mutableMapOf<String, Any>("state" to state)
        if (message != null) event["message"] = message
        mainHandler.post { sink?.success(event) }
    }
}
