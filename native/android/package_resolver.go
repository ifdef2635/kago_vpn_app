//go:build android

package main

import (
	"net"
	"net/netip"
	"sync"

	"github.com/metacubex/mihomo/component/process"
	mihomo "github.com/metacubex/mihomo/constant"
)

// Built with the `cmfa` tag, Mihomo asks the host app which package owns a
// connection (as Clash Meta for Android does). The Android side answers with
// ConnectivityManager.getConnectionOwnerUid, so PROCESS-NAME rules with
// package names (e.g. Russian apps -> DIRECT) from the subscription work.
var (
	packageMu     sync.RWMutex
	packageLookup func(protocol int, src, dst netip.AddrPort) string
)

func setPackageResolver(lookup func(protocol int, src, dst netip.AddrPort) string) {
	packageMu.Lock()
	packageLookup = lookup
	packageMu.Unlock()
}

func init() {
	process.DefaultPackageNameResolver = resolvePackageName
}

func resolvePackageName(metadata *mihomo.Metadata) (string, error) {
	packageMu.RLock()
	lookup := packageLookup
	packageMu.RUnlock()
	if lookup == nil {
		return "", process.ErrPlatformNotSupport
	}
	src, dst, protocol, ok := connectionTuple(metadata)
	if !ok {
		return "", process.ErrInvalidNetwork
	}
	if name := lookup(protocol, src, dst); name != "" {
		return name, nil
	}
	return "", process.ErrNotFound
}

// connectionTuple is the socket as the app opened it: the TUN listener keeps
// the raw addresses, so a fake-ip destination still matches the kernel's view.
func connectionTuple(metadata *mihomo.Metadata) (src, dst netip.AddrPort, protocol int, ok bool) {
	protocol = 6
	if metadata.NetWork == mihomo.UDP {
		protocol = 17
	}
	src, okSrc := addrPortOf(metadata.RawSrcAddr)
	if !okSrc {
		src = netip.AddrPortFrom(metadata.SrcIP, metadata.SrcPort)
	}
	dst, okDst := addrPortOf(metadata.RawDstAddr)
	if !okDst {
		dst = netip.AddrPortFrom(metadata.DstIP, metadata.DstPort)
	}
	src = netip.AddrPortFrom(src.Addr().Unmap(), src.Port())
	dst = netip.AddrPortFrom(dst.Addr().Unmap(), dst.Port())
	return src, dst, protocol, src.IsValid() && dst.IsValid()
}

func addrPortOf(addr net.Addr) (netip.AddrPort, bool) {
	var value netip.AddrPort
	switch typed := addr.(type) {
	case *net.TCPAddr:
		if typed == nil {
			return value, false
		}
		value = typed.AddrPort()
	case *net.UDPAddr:
		if typed == nil {
			return value, false
		}
		value = typed.AddrPort()
	default:
		return value, false
	}
	return value, value.IsValid()
}
