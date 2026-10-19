package main

import (
	"net/netip"
	"strings"
)

// Upstream resolvers for "system" DNS entries until the phone's network is
// known (and when it reports none). Built with the `cmfa` tag, Mihomo does
// not read Android's DNS itself; the TUN DNS (172.19.0.2) would loop back
// into the tunnel.
var fallbackSystemDNS = []string{"1.1.1.1:53", "8.8.8.8:53"}

// systemDNSServers turns the DNS servers of the phone's current network
// ("192.168.1.1", "2001:db8::53") into the "system" resolvers of the core.
// Loopback, link-local and unspecified addresses are skipped; without any
// usable server the public fallback is used.
func systemDNSServers(list []string) []string {
	servers := make([]string, 0, len(list))
	for _, item := range list {
		addr, err := netip.ParseAddr(strings.TrimSpace(item))
		if err != nil {
			continue
		}
		addr = addr.Unmap().WithZone("")
		if addr.IsLoopback() || addr.IsUnspecified() || addr.IsLinkLocalUnicast() || addr.IsMulticast() {
			continue
		}
		servers = append(servers, netip.AddrPortFrom(addr, 53).String())
	}
	if len(servers) == 0 {
		return append([]string(nil), fallbackSystemDNS...)
	}
	return servers
}
