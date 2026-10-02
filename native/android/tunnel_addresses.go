package main

import (
	"errors"
	"fmt"
	"net/netip"
	"strings"
)

type tunnelAddresses struct {
	ipv4 []netip.Prefix
	ipv6 []netip.Prefix
}

func parseTunnelAddresses(csv string) (tunnelAddresses, error) {
	var result tunnelAddresses
	for _, part := range strings.Split(csv, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		prefix, err := netip.ParsePrefix(part)
		if err != nil {
			return result, fmt.Errorf("invalid Android TUN address %q: %w", part, err)
		}
		if prefix.Addr().Is4() {
			result.ipv4 = append(result.ipv4, prefix)
		} else {
			result.ipv6 = append(result.ipv6, prefix)
		}
	}
	if len(result.ipv4) == 0 {
		return result, errors.New("an IPv4 Android TUN address is required")
	}
	return result, nil
}
