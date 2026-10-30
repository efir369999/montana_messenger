// Package montanaxray — gomobile wrapper: the Xray-core engine for the iOS packet-tunnel extension.
// Source: github.com/xtls/xray-core (official XTLS). Run(config) starts Xray with a local SOCKS inbound;
// packets reach it from the tunnel through hev-socks5-tunnel on the Swift side, so device traffic
// egresses via the chosen VLESS/Reality outbound. Spec s.3 §4.2; author decision to build from source.
package montanaxray

import (
	"bufio"
	"bytes"
	ctx "context"
	"crypto/rand"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"runtime"
	"runtime/debug"
	"strings"
	"sync"
	"syscall"
	"time"
	_ "unsafe" // go:linkname, to reach the core's read strategy

	probedispatch "github.com/xtls/xray-core/app/dispatcher"
	probelog "github.com/xtls/xray-core/app/log"
	"github.com/xtls/xray-core/app/proxyman"
	corenet "github.com/xtls/xray-core/common/net"
	commserial "github.com/xtls/xray-core/common/serial"
	"github.com/xtls/xray-core/common/session"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	"github.com/xtls/xray-core/transport/internet"

	// The imports below name what this client runs; they are NOT the registry (29.09, the critic). The JSON config
	// loader (infra/conf) imports every proxy and every transport package of the core for their config types, and each
	// package registers itself in its init -- so Hysteria 2, WireGuard, SOCKS, mKCP, XHTTP and the VLESS encryption are in
	// this binary whatever stands here, and the framework weighs 75 MB either way. The list stays as documentation of
	// what the Swift side generates configs for.
	_ "github.com/xtls/xray-core/app/dispatcher"
	_ "github.com/xtls/xray-core/app/log"
	_ "github.com/xtls/xray-core/app/proxyman/inbound"
	_ "github.com/xtls/xray-core/app/proxyman/outbound"
	_ "github.com/xtls/xray-core/app/router"

	_ "github.com/xtls/xray-core/proxy/blackhole"
	_ "github.com/xtls/xray-core/proxy/freedom"
	_ "github.com/xtls/xray-core/proxy/hysteria"
	_ "github.com/xtls/xray-core/proxy/shadowsocks"
	_ "github.com/xtls/xray-core/proxy/shadowsocks_2022"
	_ "github.com/xtls/xray-core/proxy/socks"
	_ "github.com/xtls/xray-core/proxy/trojan"
	_ "github.com/xtls/xray-core/proxy/vless/outbound"
	_ "github.com/xtls/xray-core/proxy/vmess/outbound"
	_ "github.com/xtls/xray-core/proxy/wireguard"

	_ "github.com/xtls/xray-core/transport/internet/grpc"
	_ "github.com/xtls/xray-core/transport/internet/headers/http"
	_ "github.com/xtls/xray-core/transport/internet/httpupgrade"
	_ "github.com/xtls/xray-core/transport/internet/hysteria"
	_ "github.com/xtls/xray-core/transport/internet/kcp"
	_ "github.com/xtls/xray-core/transport/internet/reality"
	_ "github.com/xtls/xray-core/transport/internet/splithttp"
	_ "github.com/xtls/xray-core/transport/internet/tcp"
	_ "github.com/xtls/xray-core/transport/internet/tls"
	_ "github.com/xtls/xray-core/transport/internet/websocket"
)

// The one 204-endpoint every measurement asks ([C-1]); the Swift side passes "" and takes this.
const probeURL = "http://cp.cloudflare.com/generate_204"

// One server's time is bounded (the author's word 28.09: «the ping hangs too long»): a batch that has not answered in
// this many seconds is named timeout and the line goes on.
const probeDeadlineSeconds = 8

// The core reads a socket in batches, and the batch doubles under load — up to eight buffers of eight
// kilobytes, so one busy connection can hold sixty-four. That growth happens precisely during a
// reconnect storm, which is where this process dies: the session recorded at half-second resolution
// went from 82 connections to 388 in three seconds and took the footprint from 21.8MB to 42.2MB.
//
// The flag governing it is read once, when the core's buffer package initialises, which happens while
// the framework loads — before any Swift code runs and therefore before an environment variable could
// be set. Package initialisation order answers it instead: imported packages initialise first, so the
// assignment below lands after the core has already made its choice, and the choice is consulted again
// on every reader that is created afterwards.
//
//go:linkname xrayUseReadv github.com/xtls/xray-core/common/buf.useReadv
var xrayUseReadv bool

func init() {
	xrayUseReadv = false
	debug.SetMemoryLimit(30 << 20)
	debug.SetGCPercent(30)
}

var instance *core.Instance

// MemStats reports Go runtime memory use for the extension's memory log. Read-only: it measures, it does
// not tune anything (no heap limit, no forced GC — those made things worse and are deliberately absent).
func MemStats() string {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	// stackSys separates what the goroutines themselves cost from what their work holds. The flow
	// count that used to be estimated here is gone: it was derived from goroutines back when this
	// process ran the packet stack, and the packet stack now lives in C. An estimate that no longer
	// measures what its name claims is worse than no estimate, and the pump reports bytes directly.
	g := runtime.NumGoroutine()
	return fmt.Sprintf("go{heapInuse=%dMB heapSys=%dMB stackSys=%dMB sys=%dMB numGC=%d goroutines=%d}",
		m.HeapInuse>>20, m.HeapSys>>20, m.StackSys>>20, m.Sys>>20, m.NumGC, g)
}

// Run starts Xray with a full JSON config (SOCKS inbound + chosen outbound). A running instance is
// closed first.
func Run(configJSON string) error {
	Stop()
	cfg, err := serial.LoadJSONConfig(bytes.NewReader([]byte(configJSON)))
	if err != nil {
		return err
	}
	inst, err := core.New(cfg)
	if err != nil {
		return err
	}
	if err := inst.Start(); err != nil {
		return err
	}
	instance = inst
	return nil
}

// Stop closes the running Xray instance.
func Stop() {
	if instance != nil {
		_ = instance.Close()
		instance = nil
	}
}

// Packets are moved by hev-socks5-tunnel on the Swift side — a userspace TCP/IP stack in C, outside
// this heap entirely. What remains here is the proxy and nothing else, which is why the soft limit
// above can finally sit over the live memory rather than under it.

// FreeMemory hands back to the system every page the runtime no longer needs. The system counts the
// footprint, not the live heap, and the runtime returns freed pages lazily -- so a session that had
// already collected its burst still stood at the ceiling and was taken. Measured on T1 (22.09, 1872):
// heapInuse 9-17 MB while heapSys stayed 37-45 MB and the footprint reached 40.8 MB -- five CRITICAL
// pressure warnings, then the process was killed twice in twenty minutes.
//
// Called from the pressure source of the extension, which is the last word a process about to be taken
// ever hears. It is slow by design (a full collection and a scavenge) and therefore is not on any timer.
func FreeMemory() string {
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	debug.FreeOSMemory()
	runtime.ReadMemStats(&after)
	return fmt.Sprintf("freed heapSys=%dMB->%dMB sys=%dMB->%dMB goroutines=%d",
		before.HeapSys>>20, after.HeapSys>>20, before.Sys>>20, after.Sys>>20, runtime.NumGoroutine())
}

// Version returns the Xray-core version string.
func Version() string { return core.Version() }

// MeasureDelay reports the delay of a server the way every reference client reports it: bring the outbound up,
// ask a 204-endpoint through it and time the answer. A TCP handshake with the address in the link measures
// something else entirely -- the plans put an entry node near the user in front of every country, so "Netherlands"
// answered in six milliseconds while the Netherlands were still a hundred away (measured 22.09: the entry of that
// plan sits in Moscow -- 2 ms from our Moscow node, 46 ms from Amsterdam).
//
// `iface`, when given, binds every socket the probe opens to that network interface. That is the one piece the
// reference solves with the platform's protect(): with our own tunnel up, an unbound socket of the app would ride
// into the tunnel and the number would be the tunnel's road plus the server's, not the server's.
//
// Two attempts are made one after the other and the smaller time is the answer; a call that gets no 204 from either
// returns -1 and an error naming what each attempt met. The engine built for the call listens on nothing and is closed
// before the call returns, whatever happened.
func MeasureDelay(configJSON string, url string, iface string) (int64, error) {
	callEnd := time.Now().Add(delayCallLimit)
	if url == "" {
		url = probeURL
	}
	req, dest, err := delayRequest(url)
	if err != nil {
		return -1, err
	}
	// The core treats a socket option it cannot apply as a log line and dials unbound, so a missing interface is
	// refused here, before anything is dialled past it.
	if iface != "" {
		if _, err := net.InterfaceByName(iface); err != nil {
			return -1, fmt.Errorf("measure delay: interface %q: %w", iface, err)
		}
	}
	engine, err := delayEngine(configJSON, iface)
	if err != nil {
		return -1, err
	}
	defer engine.Close()

	ms, err := delayBestOfTwo(engine, "", req, dest, callEnd, delayCallLimit)
	if err != nil {
		return -1, fmt.Errorf("measure delay of %s: %w", url, err)
	}
	return ms, nil
}

// delayBestOfTwo makes the two attempts one after the other on the outbound named by tag ("" -- the default one) and
// answers the smaller time; with no 204 from either, an error naming what each attempt met. No attempt runs past callEnd.
func delayBestOfTwo(engine *core.Instance, tag string, req *http.Request, dest corenet.Destination, callEnd time.Time,
	callLimit time.Duration) (int64, error) {
	best := int64(-1)
	var failures []string
	for n := 1; n <= 2; n++ {
		limit := min(delayAttemptLimit, time.Until(callEnd))
		if limit <= 0 {
			failures = append(failures, fmt.Sprintf("attempt %d: not made, the call's %v ran out", n, callLimit))
			continue
		}
		ms, err := delayAttempt(engine, tag, req, dest, limit)
		if err != nil {
			failures = append(failures, fmt.Sprintf("attempt %d: %v", n, err))
			continue
		}
		if best < 0 || ms < best {
			best = ms
		}
	}
	if best < 0 {
		return -1, errors.New(strings.Join(failures, "; "))
	}
	return best, nil
}

// One attempt is a fresh connection through the outbound: TCP to the server, the outbound's own handshake (TLS or
// Reality), then the request and its answer -- three to four round trips. Five seconds hold that at a 1 s round trip
// with room for a lost SYN (first retransmit at 1 s); a server slower than that is no server to ride. The whole call
// keeps the module's bound for one server (probeDeadlineSeconds), so a silent server costs 5 + 3 s, never more.
// Variables, not constants, only so the tests can shorten them.
var (
	delayAttemptLimit = 5 * time.Second
	delayCallLimit    = probeDeadlineSeconds * time.Second
)

// delayRequest checks the address once for both attempts and names the place the outbound is asked to reach.
func delayRequest(target string) (*http.Request, corenet.Destination, error) {
	req, err := http.NewRequest(http.MethodGet, target, nil)
	if err != nil {
		return nil, corenet.Destination{}, fmt.Errorf("measure delay: url %q: %w", target, err)
	}
	port := req.URL.Port()
	switch req.URL.Scheme {
	case "http":
		if port == "" {
			port = "80"
		}
	case "https":
		if port == "" {
			port = "443"
		}
	default:
		return nil, corenet.Destination{}, fmt.Errorf("measure delay: url %q: scheme must be http or https", target)
	}
	host := req.URL.Hostname()
	if host == "" {
		return nil, corenet.Destination{}, fmt.Errorf("measure delay: url %q has no host", target)
	}
	p, err := corenet.PortFromString(port)
	if err != nil {
		return nil, corenet.Destination{}, fmt.Errorf("measure delay: url %q: %w", target, err)
	}
	req.Close = true // one request per connection; nothing is kept for later
	return req, corenet.TCPDestination(corenet.ParseAddress(host), p), nil
}

// delayEngine builds the engine of one measurement: the outbounds of the config and only the apps they need to carry a
// request -- no inbound, so it listens on nothing, and no router, so the request leaves by the default outbound.
func delayEngine(configJSON string, iface string) (*core.Instance, error) {
	cfg, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return nil, fmt.Errorf("measure delay: config: %w", err)
	}
	if len(cfg.Outbound) == 0 {
		return nil, fmt.Errorf("measure delay: config has no outbound")
	}
	probeOutboundsOnly(cfg)
	if iface != "" {
		for _, out := range cfg.Outbound {
			if err := bindOutboundTo(out, iface); err != nil {
				return nil, fmt.Errorf("measure delay: %w", err)
			}
		}
	}
	engine, err := core.New(cfg)
	if err != nil {
		return nil, fmt.Errorf("measure delay: engine: %w", err)
	}
	if err := engine.Start(); err != nil {
		_ = engine.Close()
		return nil, fmt.Errorf("measure delay: engine start: %w", err)
	}
	return engine, nil
}

// probeOutboundsOnly strips a loaded config to what its outbounds need to carry a measurement: no inbound, so the engine
// listens on nothing, and of the apps only the outbound manager, the dispatcher and the log -- no router, so a request
// leaves by the default outbound or the one its context names.
func probeOutboundsOnly(cfg *core.Config) {
	cfg.Inbound = nil
	needed := map[string]bool{
		commserial.GetMessageType(&proxyman.OutboundConfig{}): true,
		commserial.GetMessageType(&probedispatch.Config{}):    true,
		commserial.GetMessageType(&probelog.Config{}):         true,
	}
	var apps []*commserial.TypedMessage
	for _, app := range cfg.App {
		if needed[app.Type] {
			apps = append(apps, app)
		}
	}
	cfg.App = apps
}

// bindOutboundTo writes the interface into one outbound's own socket options. The binding lives in this engine's
// config and dies with it; the core applies it per platform (SO_BINDTODEVICE on Linux, IP_BOUND_IF on Darwin).
func bindOutboundTo(out *core.OutboundHandlerConfig, iface string) error {
	sender := new(proxyman.SenderConfig)
	if out.SenderSettings != nil {
		msg, err := out.SenderSettings.GetInstance()
		if err != nil {
			return fmt.Errorf("outbound %q: %w", out.Tag, err)
		}
		s, ok := msg.(*proxyman.SenderConfig)
		if !ok {
			return fmt.Errorf("outbound %q: sender settings of type %s", out.Tag, out.SenderSettings.Type)
		}
		sender = s
	}
	if sender.StreamSettings == nil {
		sender.StreamSettings = new(internet.StreamConfig)
	}
	if sender.StreamSettings.SocketSettings == nil {
		sender.StreamSettings.SocketSettings = new(internet.SocketConfig)
	}
	sender.StreamSettings.SocketSettings.Interface = iface
	out.SenderSettings = commserial.ToTypedMessage(sender)
	return nil
}

// delayAttempt times one GET through the engine -- on the outbound named by tag, or the default one for "" -- from the
// dial to the answer's status line.
func delayAttempt(engine *core.Instance, tag string, req *http.Request, dest corenet.Destination, limit time.Duration) (int64, error) {
	attempt, cancel := ctx.WithTimeout(ctx.Background(), limit)
	defer cancel() // ends the outbound's work for this connection inside the core
	route := attempt
	if tag != "" {
		route = session.SetForcedOutboundTagToContext(attempt, tag)
	}
	start := time.Now()
	conn, err := core.Dial(route, engine, dest)
	if err != nil {
		return -1, err
	}
	defer conn.Close()
	// The core's in-process connection ignores deadlines; the limit is kept by closing it, which ends any read.
	unwatch := ctx.AfterFunc(attempt, func() { _ = conn.Close() })
	defer unwatch()

	var stream net.Conn = conn
	if req.URL.Scheme == "https" {
		secure := tls.Client(conn, &tls.Config{ServerName: req.URL.Hostname()})
		if err := secure.HandshakeContext(attempt); err != nil {
			return -1, attemptError(attempt, limit, "tls", err)
		}
		stream = secure
	}
	if err := req.Write(stream); err != nil {
		return -1, attemptError(attempt, limit, "request", err)
	}
	resp, err := http.ReadResponse(bufio.NewReader(stream), req)
	if err != nil {
		return -1, attemptError(attempt, limit, "answer", err)
	}
	took := time.Since(start)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		return -1, fmt.Errorf("answered %q, not 204", resp.Status)
	}
	return took.Milliseconds(), nil
}

// attemptError names a timeout as one; anything else keeps its own words.
func attemptError(attempt ctx.Context, limit time.Duration, stage string, err error) error {
	if attempt.Err() != nil {
		return fmt.Errorf("no answer within %v", limit.Round(time.Millisecond))
	}
	return fmt.Errorf("%s: %w", stage, err)
}

// MeasureUDP answers the question a call asks of a server: does it carry our packets, and how fast. The
// engine brings the outbound up exactly as MeasureDelay does -- inbounds dropped, every socket bound to the
// physical interface, our own tunnel outside the measurement -- and asks our node's STUN through it: a
// Binding Request of RFC 5389, twenty bytes, sent at 0, 0.5 and 1.5 s under a fresh transaction id each,
// the answer awaited until 3 s. The milliseconds are those of the send the answer names, never of an
// earlier or a later one. The datagram rides the outbound the way a call's does through the tunnel (VLESS
// turns it into XUDP on its stream), so the number is the call's own road through this server. No answer is
// the answer: the server passes TCP only -- a seller's entry that forwards TCP alone, measured on the fleet
// 20-24.09 as UDP_NONE on every session through it -- and a call there rides our relay over TCP.
func MeasureUDP(configJSON string, stun string, iface string) (int64, error) {
	cfg, err := serial.LoadJSONConfig(bytes.NewReader([]byte(configJSON)))
	if err != nil {
		return -1, err
	}
	probeOutboundsOnly(cfg)

	if iface != "" {
		bindSocketsTo(iface)
		defer bindSocketsTo("")
	}

	inst, err := core.New(cfg)
	if err != nil {
		return -1, err
	}
	if err := inst.Start(); err != nil {
		return -1, err
	}
	defer inst.Close()

	dest, err := corenet.ParseDestination("udp:" + stun)
	if err != nil {
		return -1, err
	}
	c, cancel := ctx.WithTimeout(ctx.Background(), 4*time.Second)
	defer cancel()
	conn, err := core.Dial(c, inst, dest)
	if err != nil {
		return -1, err
	}
	defer conn.Close()
	return stunRoundTrip(conn)
}

// stunRoundTrip asks a STUN Binding Request through an open datagram road and times the answer (see MeasureUDP).
func stunRoundTrip(conn net.Conn) (int64, error) {
	type answer struct {
		id  [12]byte
		at  time.Time
		err error
	}
	got := make(chan answer, 4)
	go func() {
		b := make([]byte, 1500)
		for {
			n, err := conn.Read(b)
			if err != nil {
				got <- answer{err: err}
				return
			}
			// A Binding Success Response (0x0101) under the magic cookie; its id names the send it answers.
			if n >= 20 && b[0] == 0x01 && b[1] == 0x01 && b[4] == 0x21 && b[5] == 0x12 && b[6] == 0xA4 && b[7] == 0x42 {
				var a answer
				copy(a.id[:], b[8:20])
				a.at = time.Now()
				got <- a
				return
			}
		}
	}()

	schedule := []time.Duration{0, 500 * time.Millisecond, 1500 * time.Millisecond}
	const wait = 3 * time.Second
	start := time.Now()
	sent := map[[12]byte]time.Time{}
	next := 0
	timer := time.NewTimer(0)
	defer timer.Stop()
	for {
		select {
		case a := <-got:
			if a.err != nil {
				return -1, a.err
			}
			t0, ok := sent[a.id]
			if !ok {
				return -1, fmt.Errorf("an answer to no request of ours")
			}
			return a.at.Sub(t0).Milliseconds(), nil
		case <-timer.C:
			if next >= len(schedule) {
				return -1, fmt.Errorf("no answer: the server carries no UDP")
			}
			var req [20]byte
			req[1] = 0x01 // Binding Request, no attributes
			req[4], req[5], req[6], req[7] = 0x21, 0x12, 0xA4, 0x42
			if _, err := rand.Read(req[8:20]); err != nil {
				return -1, err
			}
			var id [12]byte
			copy(id[:], req[8:20])
			sent[id] = time.Now()
			if _, err := conn.Write(req[:]); err != nil {
				return -1, err
			}
			next++
			if next < len(schedule) {
				timer.Reset(schedule[next] - time.Since(start))
			} else {
				timer.Reset(wait - time.Since(start))
			}
		}
	}
}

// MeasureMany measures several servers at once through ONE engine instance (29.09, the critic's P-1): every outbound of
// `outboundsJSON` (a JSON array of outbound objects, as MontanaXrayConfig.outbound writes them) joins one config under
// a tag of its own, and `width` goroutines ask the 204-endpoint through them, each dial forced onto its own outbound by
// the dispatcher's detour word (session forcedOutboundTag, app/dispatcher/default.go). One instance instead of one per
// server: under the tunnel's 50 MB ceiling that is the whole difference between six at once and one at a time. An
// outbound the loader refuses answers its error alone and keeps the others in the batch. The answer is a JSON array in
// the outbounds' order -- {"ms":71} or {"err":"..."} -- and the whole batch is bounded by `deadlineSeconds` (0: the
// default of 8 s), so nothing of a batch outlives the asker.
func MeasureMany(outboundsJSON string, url string, width int, iface string, deadlineSeconds int) (string, error) {
	answers, inst, tags, err := batchInstance(outboundsJSON, iface)
	if err != nil {
		return "", err
	}
	if inst != nil {
		defer inst.Close()
		if url == "" {
			url = probeURL
		}
		deadline := time.Duration(deadlineSeconds) * time.Second
		if deadlineSeconds <= 0 {
			deadline = probeDeadlineSeconds * time.Second
		}
		runBatch(len(tags), width, func(i int) {
			ms, err := delayVia(inst, tags[i].tag, url, deadline)
			answers[tags[i].index] = probeAnswer{Ms: ms, Err: errWord(err)}
		})
	}
	out, err := json.Marshal(answers)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// MeasureUDPMany asks our node's STUN through several servers at once (the call's road, see MeasureUDP), the way
// MeasureMany asks the 204-endpoint: one instance, `width` at a time, every answer in the outbounds' order.
func MeasureUDPMany(outboundsJSON string, stun string, width int, iface string, deadlineSeconds int) (string, error) {
	answers, inst, tags, err := batchInstance(outboundsJSON, iface)
	if err != nil {
		return "", err
	}
	if inst != nil {
		defer inst.Close()
		dest, err := corenet.ParseDestination("udp:" + stun)
		if err != nil {
			return "", err
		}
		deadline := time.Duration(deadlineSeconds) * time.Second
		if deadlineSeconds <= 0 {
			deadline = probeDeadlineSeconds * time.Second
		}
		runBatch(len(tags), width, func(i int) {
			c, cancel := ctx.WithTimeout(ctx.Background(), deadline)
			defer cancel()
			conn, err := core.Dial(session.SetForcedOutboundTagToContext(c, tags[i].tag), inst, dest)
			if err != nil {
				answers[tags[i].index] = probeAnswer{Ms: -1, Err: errWord(err)}
				return
			}
			defer conn.Close()
			ms, err := stunRoundTrip(conn)
			answers[tags[i].index] = probeAnswer{Ms: ms, Err: errWord(err)}
		})
	}
	out, err := json.Marshal(answers)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

type probeAnswer struct {
	Ms  int64  `json:"ms"`
	Err string `json:"err,omitempty"`
}

type batchTag struct {
	index int
	tag   string
}

func errWord(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// batchInstance stands one engine up with every outbound the loader accepts, each under its own tag. An outbound the
// loader refuses is answered at once with its error; a batch with nothing left to ask returns no instance.
func batchInstance(outboundsJSON string, iface string) ([]probeAnswer, *core.Instance, []batchTag, error) {
	var outs []json.RawMessage
	if err := json.Unmarshal([]byte(outboundsJSON), &outs); err != nil {
		return nil, nil, nil, err
	}
	answers := make([]probeAnswer, len(outs))
	var tags []batchTag
	var parts []string
	for i, raw := range outs {
		var m map[string]any
		if err := json.Unmarshal(raw, &m); err != nil {
			answers[i] = probeAnswer{Ms: -1, Err: err.Error()}
			continue
		}
		tag := fmt.Sprintf("m%d", i)
		m["tag"] = tag
		one, err := json.Marshal(m)
		if err != nil {
			answers[i] = probeAnswer{Ms: -1, Err: err.Error()}
			continue
		}
		// The loader's verdict on this one outbound alone, so a refused cipher or wrapper names its own row.
		if _, err := serial.LoadJSONConfig(strings.NewReader(`{"outbounds":[` + string(one) + `]}`)); err != nil {
			answers[i] = probeAnswer{Ms: -1, Err: err.Error()}
			continue
		}
		answers[i] = probeAnswer{Ms: -1, Err: "timeout"}
		tags = append(tags, batchTag{index: i, tag: tag})
		parts = append(parts, string(one))
	}
	if len(parts) == 0 {
		return answers, nil, nil, nil
	}
	js := `{"log":{"loglevel":"warning"},"outbounds":[` + strings.Join(parts, ",") + `,{"protocol":"freedom","tag":"direct"}]}`
	cfg, err := serial.LoadJSONConfig(strings.NewReader(js))
	if err != nil {
		return nil, nil, nil, err
	}
	probeOutboundsOnly(cfg)
	if iface != "" {
		bindSocketsTo(iface)
		defer bindSocketsTo("")
	}
	inst, err := core.New(cfg)
	if err != nil {
		return nil, nil, nil, err
	}
	if err := inst.Start(); err != nil {
		return nil, nil, nil, err
	}
	return answers, inst, tags, nil
}

// runBatch runs `n` jobs, at most `width` at a time, and returns when every one has finished.
func runBatch(n int, width int, job func(int)) {
	if width <= 0 {
		width = 1
	}
	var wg sync.WaitGroup
	slots := make(chan struct{}, width)
	for i := 0; i < n; i++ {
		wg.Add(1)
		slots <- struct{}{}
		go func(i int) {
			defer wg.Done()
			defer func() { <-slots }()
			job(i)
		}(i)
	}
	wg.Wait()
}

// delayVia is one server's delay through a running instance: two GETs of the 204-endpoint on the outbound named by
// `tag`, the smaller one wins (the reference's own rule), all within `deadline`.
func delayVia(inst *core.Instance, tag string, url string, deadline time.Duration) (int64, error) {
	callEnd := time.Now().Add(deadline)
	if url == "" {
		url = probeURL
	}
	req, dest, err := delayRequest(url)
	if err != nil {
		return -1, err
	}
	return delayBestOfTwo(inst, tag, req, dest, callEnd, deadline)
}

// Every socket the engine opens from here on is bound to the named interface (empty -- the system chooses).
// The engine hands out this hook for exactly this purpose; on this platform the binding is IP_BOUND_IF.
func bindSocketsTo(iface string) {
	if iface == "" {
		internet.RegisterDialerController(nil)
		return
	}
	idx, err := net.InterfaceByName(iface)
	if err != nil {
		return
	}
	internet.RegisterDialerController(func(network, address string, c syscall.RawConn) error {
		var inner error
		if err := c.Control(func(fd uintptr) {
			if strings.Contains(address, ".") {
				inner = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, ipBoundIf, idx.Index)
				return
			}
			inner = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IPV6, ipv6BoundIf, idx.Index)
		}); err != nil {
			return err
		}
		return inner
	})
}

const (
	ipBoundIf   = 25 // IP_BOUND_IF (Darwin)
	ipv6BoundIf = 125 // IPV6_BOUND_IF (Darwin)
)
