//go:build android

// The one piece the Android engine needs beside the iOS wrapper (montanaxray.go, carried byte for byte from
// apps/messenger/ios/scripts/xray-ios of iOS 2235): on iOS the system keeps the packet-tunnel extension's own sockets
// out of its tunnel; on Android the tunnel belongs to the app's own VpnService, and every socket the engine dials must
// be handed to VpnService.protect, or the engine's road to the server would ride back into the tunnel it serves.
package montanaxray

import (
	"context"
	"errors"
	"net"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/xtls/xray-core/transport/internet"
)

// Protector is the platform's VpnService.protect: a socket given to it leaves through the physical network.
type Protector interface {
	Protect(fd int) bool
}

var (
	protectMu sync.RWMutex
	protector Protector
	protectOn sync.Once
)

// protectControl hands one socket to the protector of the moment before it connects; with none it leaves the socket as it
// is. A socket the platform refuses to protect is not dialled: left alone it would loop into our own tunnel.
func protectControl(network, address string, c syscall.RawConn) error {
	protectMu.RLock()
	now := protector
	protectMu.RUnlock()
	if now == nil {
		return nil
	}
	var refused error
	if err := c.Control(func(fd uintptr) {
		if !now.Protect(int(fd)) {
			refused = errors.New("the VPN refused to protect the engine's socket")
		}
	}); err != nil {
		return err
	}
	return refused
}

// SetProtector hands every socket the engine dials from now on to p before it connects; nil leaves sockets as they are.
// The core's dialer only ever adds controllers and refuses a nil one (RegisterDialerController), so one controller is
// registered once and reads the protector of the moment. The measurements are asked with an empty interface here, so the
// core's bindSocketsTo (Darwin's IP_BOUND_IF) never adds a controller of its own.
func SetProtector(p Protector) {
	protectMu.Lock()
	protector = p
	protectMu.Unlock()
	protectOn.Do(func() { _ = internet.RegisterDialerController(protectControl) })
}

var (
	resolveMu      sync.Mutex
	systemResolver *net.Resolver
)

// SetResolvers sends the engine's own name lookups -- its server's name above all -- to the named DNS servers ("ip" or
// "ip:port", comma-separated) over sockets the protector takes, as its dials go; "" gives the lookups back to the system.
// On Android the system resolver asks through the app's own network, which is our tunnel once it stands: the engine looking
// up its server inside the tunnel that waits for that very server would wait for itself. On iOS the extension's own
// lookups never enter its tunnel, so the wrapper there needs no such word.
func SetResolvers(servers string) {
	var list []string
	for _, s := range strings.Split(servers, ",") {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		if _, _, err := net.SplitHostPort(s); err != nil {
			s = net.JoinHostPort(s, "53")
		}
		list = append(list, s)
	}
	resolveMu.Lock()
	defer resolveMu.Unlock()
	if len(list) == 0 {
		if systemResolver != nil {
			net.DefaultResolver = systemResolver
			systemResolver = nil
		}
		return
	}
	if systemResolver == nil {
		systemResolver = net.DefaultResolver
	}
	net.DefaultResolver = &net.Resolver{
		PreferGo: true,
		// The resolver asks its own two servers in turn -- with no resolv.conf on Android, the loopback's 127.0.0.1:53 and
		// [::1]:53 -- and the question goes to ours instead: its first server to our first (the phone's own network names it),
		// its second to our second; a server that cannot be reached at all hands the question to the next.
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			first := 0
			if strings.HasPrefix(address, "[") {
				first = 1
			}
			var last error
			for k := 0; k < len(list); k++ {
				d := net.Dialer{Timeout: 5 * time.Second, Control: protectControl}
				c, err := d.DialContext(ctx, network, list[(first+k)%len(list)])
				if err == nil {
					return c, nil
				}
				last = err
			}
			return nil, last
		},
	}
}
