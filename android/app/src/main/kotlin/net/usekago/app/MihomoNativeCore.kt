package net.usekago.app

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
    /**
     * After a network change: the core's "system" DNS from [dnsServers] (the
     * new network's DNS, comma-separated; empty — public fallback), DNS cache
     * and resolver connections reset; [closeConnections] closes every proxied
     * connection so apps reconnect over the new network.
     */
    external fun resetNetwork(dnsServers: String, closeConnections: Boolean): Int
    /** Returns the Mihomo release tag embedded into this signed Android app build. */
    external fun version(): String
    /** Detailed startup error from the Go bridge for fail-closed diagnostics. */
    external fun lastError(): String
}
