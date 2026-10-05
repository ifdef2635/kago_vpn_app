//go:build android

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	mihomo "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	lifecycleMu sync.Mutex
	coreRunning atomic.Bool
	ownedTunFD  = -1
	lastErrMu   sync.RWMutex
	lastErr     string
	protectMu   sync.RWMutex
	protectFD   func(int) bool
)

func setNativeProtector(callback func(int) bool) {
	protectMu.Lock()
	protectFD = callback
	protectMu.Unlock()
}

func setLastError(err error) {
	lastErrMu.Lock()
	defer lastErrMu.Unlock()
	if err == nil {
		lastErr = ""
	} else {
		lastErr = err.Error()
	}
}

func currentError() string {
	lastErrMu.RLock()
	defer lastErrMu.RUnlock()
	return lastErr
}

func protectOutboundSockets(network, address string, raw syscall.RawConn) error {
	var protectErr error
	err := raw.Control(func(fd uintptr) {
		protectMu.RLock()
		callback := protectFD
		protectMu.RUnlock()
		if callback == nil || !callback(int(fd)) {
			protectErr = errors.New("VpnService.protect refused the Mihomo socket")
		}
	})
	if err != nil {
		return err
	}
	return protectErr
}

func startCore(configPath, workDir string, tunFD, mtu int, stack, addressCSV string) (err error) {
	lifecycleMu.Lock()
	defer lifecycleMu.Unlock()
	if coreRunning.Load() {
		return nil
	}
	if tunFD <= 0 {
		return errors.New("Android TUN file descriptor is invalid")
	}
	if mtu < 576 || mtu > 9000 {
		return fmt.Errorf("Android TUN MTU is outside the supported range: %d", mtu)
	}
	if workDir == "" || configPath == "" {
		return errors.New("Mihomo config path and work directory are required")
	}
	if !filepath.IsAbs(configPath) || !filepath.IsAbs(workDir) {
		return errors.New("Mihomo config path and work directory must be absolute")
	}
	if err := os.MkdirAll(workDir, 0o700); err != nil {
		return fmt.Errorf("create Mihomo work directory: %w", err)
	}
	configBytes, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("read Mihomo config: %w", err)
	}
	if len(configBytes) == 0 {
		return errors.New("Mihomo config is empty")
	}

	addresses, err := parseTunnelAddresses(addressCSV)
	if err != nil {
		return err
	}
	stackValue, ok := mihomo.StackTypeMapping[strings.ToLower(strings.TrimSpace(stack))]
	if !ok {
		return fmt.Errorf("unsupported Mihomo TUN stack: %q", stack)
	}

	ownedFD, err := syscall.Dup(tunFD)
	if err != nil {
		return fmt.Errorf("duplicate Android TUN descriptor: %w", err)
	}
	keepFD := false
	defer func() {
		if !keepFD {
			_ = syscall.Close(ownedFD)
		}
	}()

	// Both paths must be absolute: by default Mihomo resolves "config.yaml" against the
	// process cwd, which is the read-only "/" on Android.
	mihomo.SetHomeDir(workDir)
	mihomo.SetConfig(configPath)
	if err := config.Init(workDir); err != nil {
		return fmt.Errorf("initialize Mihomo home: %w", err)
	}
	cfg, err := executor.ParseWithBytes(configBytes)
	if err != nil {
		return fmt.Errorf("parse Mihomo config: %w", err)
	}
	if cfg == nil || cfg.General == nil || cfg.Controller == nil {
		return errors.New("Mihomo parsed an incomplete configuration")
	}

	// The Android VpnService owns routing; Mihomo attaches to a duplicate of its TUN fd.
	cfg.General.Tun.Enable = true
	cfg.General.Tun.FileDescriptor = ownedFD
	cfg.General.Tun.MTU = uint32(mtu)
	cfg.General.Tun.Stack = stackValue
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.AutoRedirect = false
	cfg.General.Tun.Inet4Address = addresses.ipv4
	cfg.General.Tun.Inet6Address = addresses.ipv6
	cfg.General.AllowLan = false

	// The app controls the API endpoint; reject any subscription-supplied remote controller.
	controllerHost, _, splitErr := net.SplitHostPort(cfg.Controller.ExternalController)
	controllerIP := net.ParseIP(controllerHost)
	if splitErr != nil || controllerIP == nil || !controllerIP.IsLoopback() {
		cfg.Controller.ExternalController = "127.0.0.1:9090"
	}
	cfg.Controller.ExternalControllerTLS = ""
	cfg.Controller.ExternalControllerUnix = ""
	cfg.Controller.ExternalControllerPipe = ""

	protectMu.RLock()
	protectorReady := protectFD != nil
	protectMu.RUnlock()
	if !protectorReady {
		return errors.New("Android VpnService.protect callback is not installed")
	}
	dialer.DefaultSocketHook = protectOutboundSockets

	coreInitialized := false
	defer func() {
		if err != nil && coreInitialized {
			stopCoreLocked()
		}
	}()
	hub.ApplyConfig(cfg)
	coreInitialized = true
	listener.SetAllowLan(false)
	listener.SetBindAddress("127.0.0.1")
	listener.ReCreateMixed(cfg.General.MixedPort, tunnel.Tunnel)
	listener.ReCreateTun(cfg.General.Tun, tunnel.Tunnel)
	if !listener.GetTunConf().Enable {
		return errors.New("Mihomo could not attach to the Android TUN descriptor; see core logs")
	}
	ownedTunFD = ownedFD
	keepFD = true
	coreRunning.Store(true)
	setLastError(nil)
	return nil
}

func stopCore() int {
	lifecycleMu.Lock()
	defer lifecycleMu.Unlock()
	return stopCoreLocked()
}

func stopCoreLocked() int {
	if !coreRunning.Load() && ownedTunFD < 0 {
		dialer.DefaultSocketHook = nil
		return 0
	}
	listener.Cleanup()
	listener.ReCreateMixed(0, tunnel.Tunnel)
	route.ReCreateServer(&route.Config{})
	executor.Shutdown()
	dialer.DefaultSocketHook = nil
	if ownedTunFD >= 0 {
		// ReCreateTun/Cleanup closes the duplicate when the Android tunnel listener owns it.
		// The descriptor was duplicated before passing it to Mihomo, never borrowed from Java.
		_ = syscall.Close(ownedTunFD)
		ownedTunFD = -1
	}
	coreRunning.Store(false)
	setNativeProtector(nil)
	setLastError(nil)
	return 0
}

func isCoreRunning() bool { return coreRunning.Load() }

// main is required when this package is built with Go's c-shared build mode.
func main() {}
