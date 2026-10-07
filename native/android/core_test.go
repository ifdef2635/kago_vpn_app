package main

import "testing"

func TestParseTunnelAddresses(t *testing.T) {
	got, err := parseTunnelAddresses("172.19.0.1/30,fdfe:dcba:9876::1/126")
	if err != nil {
		t.Fatalf("parseTunnelAddresses returned error: %v", err)
	}
	if len(got.ipv4) != 1 || len(got.ipv6) != 1 {
		t.Fatalf("expected one IPv4 and one IPv6 prefix, got %d and %d", len(got.ipv4), len(got.ipv6))
	}
}

func TestParseTunnelAddressesRequiresIPv4(t *testing.T) {
	if _, err := parseTunnelAddresses("fdfe:dcba:9876::1/126"); err == nil {
		t.Fatal("expected an IPv4 address requirement")
	}
}

func TestJniSafeText(t *testing.T) {
	got := jniSafeText("bad \xff node 🇩🇪\x00end")
	want := "bad � node �� end"
	if got != want {
		t.Fatalf("jniSafeText = %q, want %q", got, want)
	}
	if jniSafeText("plain ошибка") != "plain ошибка" {
		t.Fatal("BMP text must stay as is")
	}
}
