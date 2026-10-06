//go:build android && cgo

package main

/*
#cgo CFLAGS: -I../include
#cgo android CXXFLAGS: -std=c++17 -I../include
#cgo android LDFLAGS: -llog -landroid -lc++_shared
#include <stdlib.h>
#include "kago_mihomo_bridge.h"
#include "kago_socket_protector.h"
*/
import "C"

import (
	"errors"
	"net/netip"
	"strings"
	"unsafe"

	mihomo "github.com/metacubex/mihomo/constant"
)

//export kago_mihomo_set_socket_protector
func kago_mihomo_set_socket_protector(protector C.kago_socket_protector) C.int {
	C.kago_store_socket_protector(protector)
	if protector == nil {
		setNativeProtector(nil)
		return 0
	}
	setNativeProtector(func(fd int) bool {
		return C.kago_call_socket_protector(C.int(fd)) == 1
	})
	return 0
}

//export kago_mihomo_set_package_resolver
func kago_mihomo_set_package_resolver(resolver C.kago_package_resolver) C.int {
	C.kago_store_package_resolver(resolver)
	if resolver == nil {
		setPackageResolver(nil)
		return 0
	}
	setPackageResolver(func(protocol int, src, dst netip.AddrPort) string {
		const size = 256
		cSrc := C.CString(src.Addr().String())
		defer C.free(unsafe.Pointer(cSrc))
		cDst := C.CString(dst.Addr().String())
		defer C.free(unsafe.Pointer(cDst))
		buffer := (*C.char)(C.malloc(size))
		defer C.free(unsafe.Pointer(buffer))
		length := C.kago_call_package_resolver(C.int(protocol), cSrc, C.int(src.Port()),
			cDst, C.int(dst.Port()), buffer, size)
		if length <= 0 || length >= size {
			return ""
		}
		return C.GoStringN(buffer, length)
	})
	return 0
}

//export kago_mihomo_protect_socket
func kago_mihomo_protect_socket(fd C.int) C.int {
	if C.kago_call_socket_protector(fd) == 1 {
		return 1
	}
	return 0
}

//export kago_mihomo_start
func kago_mihomo_start(configPath, workDir *C.char) C.int {
	_ = configPath
	_ = workDir
	setLastError(errors.New("Android startup requires a VpnService TUN descriptor"))
	return -1
}

//export kago_mihomo_start_with_tun_fd
func kago_mihomo_start_with_tun_fd(configPath, workDir *C.char, tunFD, mtu C.int, stack, address, dns *C.char) C.int {
	_ = dns // VpnService.Builder installs system DNS on the same TUN.
	if err := startCore(C.GoString(configPath), C.GoString(workDir), int(tunFD), int(mtu), C.GoString(stack), C.GoString(address)); err != nil {
		setLastError(err)
		return -1
	}
	return 0
}

//export kago_mihomo_stop
func kago_mihomo_stop() C.int { return C.int(stopCore()) }

//export kago_mihomo_is_running
func kago_mihomo_is_running() C.int {
	if isCoreRunning() {
		return 1
	}
	return 0
}

//export kago_mihomo_version
func kago_mihomo_version() *C.char {
	version := mihomo.Version
	if version != "" && !strings.HasPrefix(version, "v") {
		version = "v" + version
	}
	return C.CString(version)
}

//export kago_mihomo_last_error
func kago_mihomo_last_error() *C.char { return C.CString(currentError()) }

//export kago_mihomo_free_string
func kago_mihomo_free_string(value *C.char) { C.free(unsafe.Pointer(value)) }
