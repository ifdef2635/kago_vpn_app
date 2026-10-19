//go:build android

package main

import (
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// resetNetwork runs when the phone moved to another network (Wi-Fi to mobile
// data and back). Connections opened over the old network often do not fail
// but hang (Samsung keeps a weak Wi-Fi up while it routes over mobile data),
// so apps waited until the user turned the VPN off and on. As FlClashX does:
// the "system" DNS follows the new network, the DNS cache and the resolvers'
// connections are reset, and with closeConnections every proxied connection
// is closed so apps reconnect over the new network at once.
func resetNetwork(dnsServers []string, closeConnections bool) {
	lifecycleMu.Lock()
	defer lifecycleMu.Unlock()
	if !coreRunning.Load() {
		return
	}
	dns.UpdateSystemDNS(systemDNSServers(dnsServers))
	dns.FlushCacheWithDefaultResolver()
	if closeConnections {
		statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
			_ = c.Close()
			return true
		})
	}
}
