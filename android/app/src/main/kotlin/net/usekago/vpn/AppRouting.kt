package net.usekago.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService

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

    /** Applies the saved choice to the VPN being built. Missing apps are skipped. */
    fun apply(context: Context, builder: VpnService.Builder) {
        val (mode, packages) = load(context)
        if (mode == "off") return
        for (name in packages) {
            try {
                if (mode == "exclude") {
                    builder.addDisallowedApplication(name)
                } else {
                    builder.addAllowedApplication(name)
                }
            } catch (_: PackageManager.NameNotFoundException) {
                // Uninstalled since it was chosen.
            }
        }
    }
}
