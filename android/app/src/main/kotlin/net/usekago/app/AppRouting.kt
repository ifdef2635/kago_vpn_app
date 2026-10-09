package net.usekago.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import org.json.JSONArray
import org.json.JSONObject

/**
 * Split tunneling. `exclude`: the chosen apps bypass the VPN (Russian services
 * that refuse to work behind a VPN or outside Russia); `include`: only the
 * chosen apps use the VPN; `off`: everything goes through the VPN.
 */
object AppRouting {
    private const val PREFS = "kago_app_routing"
    private const val KEY_MODE = "mode"
    private const val KEY_PACKAGES = "packages"

    fun load(context: Context): Pair<String, Set<String>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val mode = prefs.getString(KEY_MODE, "off") ?: "off"
        val packages = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()
        return mode to packages.toSet()
    }

    fun save(context: Context, mode: String, packages: Collection<String>) {
        val safeMode = if (mode == "exclude" || mode == "include") mode else "off"
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_MODE, safeMode)
            .putStringSet(KEY_PACKAGES, packages.toSet())
            .apply()
    }

    /** Apps with a launcher icon (visible through the manifest `<queries>`). */
    fun launchableApps(context: Context): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        return pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != context.packageName }
            .distinctBy { it.packageName }
            .map { mapOf("package" to it.packageName, "label" to pm.getApplicationLabel(it).toString()) }
            .sortedBy { it["label"]?.lowercase() }
    }

    /**
     * Applies the user's choice together with the subscription's lists
     * (`tun.include-package` / `tun.exclude-package` of the config, as
     * FlClashX does): a KAGO subscription sends ~500 Russian apps (banks,
     * Gosuslugi…) that must bypass the VPN. The lists are merged; Android
     * takes either an allow-list or a deny-list, so when anything must be
     * included only the allow-list applies (with this app in it, so its own
     * requests and IP check go through the VPN). Missing apps are skipped.
     */
    fun apply(context: Context, builder: VpnService.Builder, tun: JSONObject?) {
        val (mode, packages) = load(context)
        val include = linkedSetOf<String>()
        val exclude = linkedSetOf<String>()
        when (mode) {
            "include" -> include.addAll(packages)
            "exclude" -> exclude.addAll(packages)
        }
        include.addAll(strings(tun?.optJSONArray("include-package")))
        exclude.addAll(strings(tun?.optJSONArray("exclude-package")))
        // This app is never sent around its own VPN.
        exclude.remove(context.packageName)
        if (include.isNotEmpty()) {
            include.add(context.packageName)
            for (name in include) {
                try {
                    builder.addAllowedApplication(name)
                } catch (_: PackageManager.NameNotFoundException) {
                    // Not installed.
                }
            }
        } else {
            for (name in exclude) {
                try {
                    builder.addDisallowedApplication(name)
                } catch (_: PackageManager.NameNotFoundException) {
                    // Not installed.
                }
            }
        }
    }

    private fun strings(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return (0 until array.length())
            .map { array.optString(it).trim() }
            .filter { it.isNotEmpty() }
    }
}
