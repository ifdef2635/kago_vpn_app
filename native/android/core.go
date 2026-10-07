//go:build android

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime/debug"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	mihomo "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// Upstream resolvers for "system" DNS entries. Built with the `cmfa` tag, Mihomo does not
// read Android's DNS itself; the TUN DNS (172.19.0.2) would loop back into the tunnel.
var fallbackSystemDNS = []string{"1.1.1.1:53", "8.8.8.8:53"}

// Soft heap limit for the core inside the app process: the GC works harder
// near it instead of letting the heap double (phones with little RAM, and
// Android kills big background processes first). Not a hard cap.
const coreMemoryLimit = 160 << 20

func init() {
	debug.SetMemoryLimit(coreMemoryLimit)
}

var (
	lifecycleMu sync.Mutex
	coreRunning atomic.Bool
	// coreApplied: hub.ApplyConfig ran, so listeners/controller may be up and
	// must be torn down even if the start then failed.
	coreApplied bool
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
	return jniSafeText(lastErr)
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
	var tunStat syscall.Stat_t
	_ = syscall.Fstat(ownedFD, &tunStat)
	// Until Mihomo is configured the duplicate is ours to close. Once sing-tun
	// opens the TUN it wraps the descriptor in an os.File and closes it itself
	// (listener.Cleanup, or its own error path); closing it again here would
	// close whatever file reused that number — a socket or the Go runtime's
	// epoll fd — and crash the process at random later.
	handedOver := false
	defer func() {
		if err != nil && (!handedOver || stillOurTun(ownedFD, &tunStat)) {
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
	// Traffic enters only through the TUN. No local proxy ports (any app on the phone
	// could use them to detect the VPN and its exit address) and no inbound servers.
	cfg.General.Port = 0
	cfg.General.SocksPort = 0
	cfg.General.RedirPort = 0
	cfg.General.TProxyPort = 0
	cfg.General.MixedPort = 0
	cfg.General.TuicServer.Enable = false
	cfg.General.ShadowSocksConfig = ""
	cfg.General.VmessConfig = ""

	// The app controls the API endpoint; reject any subscription-supplied remote controller.
	controllerHost, _, splitErr := net.SplitHostPort(cfg.Controller.ExternalController)
	controllerIP := net.ParseIP(controllerHost)
	if splitErr != nil || controllerIP == nil || !controllerIP.IsLoopback() {
		cfg.Controller.ExternalController = "127.0.0.1:9090"
	}
	cfg.Controller.ExternalControllerTLS = ""
	cfg.Controller.ExternalControllerUnix = ""
	cfg.Controller.ExternalControllerPipe = ""
	// Enforced here as well as in the Dart config builder, so a config written
	// by any code path cannot open listeners or unauthenticated endpoints.
	cfg.Controller.ExternalUI = ""
	cfg.Controller.ExternalUIURL = ""
	cfg.Controller.ExternalUIName = ""
	cfg.Controller.ExternalDohServer = ""
	cfg.Controller.Cors.AllowOrigins = []string{"https://controller.invalid"}
	cfg.Controller.Cors.AllowPrivateNetwork = false
	if cfg.Controller.Secret == "" {
		return errors.New("controller secret is missing")
	}
	cfg.Listeners = nil
	cfg.Tunnels = nil
	if cfg.NTP != nil {
		cfg.NTP.WriteToSystem = false
	}
	// debug mounts /debug/pprof on the controller without the secret.
	if cfg.General.LogLevel == log.DEBUG {
		cfg.General.LogLevel = log.WARNING
	}

	protectMu.RLock()
	protectorReady := protectFD != nil
	protectMu.RUnlock()
	if !protectorReady {
		return errors.New("Android VpnService.protect callback is not installed")
	}
	dialer.DefaultSocketHook = protectOutboundSockets

	dns.UpdateSystemDNS(fallbackSystemDNS)

	// ReCreateTun only logs why the TUN listener failed; keep that reason for the UI.
	coreErrors := collectCoreErrors()
	defer coreErrors.stop()

	defer func() {
		if err != nil && coreApplied {
			stopCoreLocked()
		}
	}()
	handedOver = true
	coreApplied = true
	hub.ApplyConfig(cfg)
	listener.SetAllowLan(false)
	listener.SetBindAddress("127.0.0.1")
	listener.ReCreateMixed(cfg.General.MixedPort, tunnel.Tunnel)
	listener.ReCreateTun(cfg.General.Tun, tunnel.Tunnel)
	if !listener.GetTunConf().Enable {
		if reason := coreErrors.last(); reason != "" {
			return fmt.Errorf("Mihomo could not attach to the Android TUN descriptor: %s", reason)
		}
		return errors.New("Mihomo could not attach to the Android TUN descriptor; see core logs")
	}
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
	if !coreRunning.Load() && !coreApplied {
		dialer.DefaultSocketHook = nil
		return 0
	}
	// Cleanup closes the TUN listener and with it the descriptor it owns; the
	// descriptor must not be closed a second time here.
	listener.Cleanup()
	listener.ReCreateMixed(0, tunnel.Tunnel)
	route.ReCreateServer(&route.Config{})
	executor.Shutdown()
	dialer.DefaultSocketHook = nil
	coreApplied = false
	coreRunning.Store(false)
	setNativeProtector(nil)
	setLastError(nil)
	// Give the core's memory back to Android while the VPN is off.
	go debug.FreeOSMemory()
	return 0
}

type coreErrorCollector struct {
	sub  <-chan log.Event
	done chan struct{}
	mu   sync.Mutex
	msg  string
}

func collectCoreErrors() *coreErrorCollector {
	c := &coreErrorCollector{sub: log.Subscribe(), done: make(chan struct{})}
	go func() {
		defer close(c.done)
		for event := range c.sub {
			if event.LogLevel == log.ERROR {
				c.mu.Lock()
				c.msg = event.Payload
				c.mu.Unlock()
			}
		}
	}()
	return c
}

// last waits briefly for log delivery (it is asynchronous) and returns the latest error.
func (c *coreErrorCollector) last() string {
	time.Sleep(200 * time.Millisecond)
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.msg
}

func (c *coreErrorCollector) stop() {
	log.UnSubscribe(c.sub)
	<-c.done
}

// stillOurTun reports whether fd is still open on the TUN device we duplicated
// (same device and inode), i.e. sing-tun failed before taking it over.
func stillOurTun(fd int, want *syscall.Stat_t) bool {
	var st syscall.Stat_t
	if err := syscall.Fstat(fd, &st); err != nil {
		return false
	}
	return st.Dev == want.Dev && st.Ino == want.Ino && st.Rdev == want.Rdev
}

func isCoreRunning() bool { return coreRunning.Load() }

// main is required when this package is built with Go's c-shared build mode.
func main() {}
