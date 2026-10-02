package net.usekago.vpn

/** JNI symbols are implemented by the bundled libkago_mihomo_bridge.so. */
object MihomoNativeCore {
    init { System.loadLibrary("kago_mihomo_bridge") }

    /** Returns 0 only after the core owns a duplicate of tunFd and protects outbound sockets. */
    external fun start(
        vpnService: KaGoVpnService,
        configPath: String,
        workDirectory: String,
        tunFd: Int,
        mtu: Int,
        stack: String,
        tunnelAddress: String,
        tunnelDns: String,
    ): Int
    external fun stop(): Int
    /** Returns the Mihomo release tag embedded into this signed Android app build. */
    external fun version(): String
    /** Detailed startup error from the Go bridge for fail-closed diagnostics. */
    external fun lastError(): String
}
