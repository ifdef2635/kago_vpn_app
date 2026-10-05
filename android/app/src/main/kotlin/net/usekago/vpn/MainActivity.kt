package net.usekago.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "net.usekago.vpn/service"
    private val eventChannelName = "net.usekago.vpn/events"
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
            if (best.modeId == current.modeId) return@runCatching
            val params = window.attributes
            params.preferredDisplayModeId = best.modeId
            window.attributes = params
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
