package montanaxray

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// A real engine config: one freedom outbound (the default), a router that would send everything to a blackhole, and an
// inbound on a given port. The probe must leave by freedom (no router) and must not listen (no inbound).
func probeConfig(inboundPort int) string {
	return fmt.Sprintf(`{
  "log": {"loglevel": "none"},
  "inbounds": [{"listen": "127.0.0.1", "port": %d, "protocol": "socks", "settings": {"udp": false}}],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}],
  "routing": {"rules": [{"type": "field", "network": "tcp,udp", "outboundTag": "block"}]}
}`, inboundPort)
}

// A port the test holds: an engine that kept the config's inbound could not start on it.
func heldPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	return l.Addr().(*net.TCPAddr).Port
}

// answerServer answers every GET with status; delay(n) holds the n-th request (1-based) before it answers.
// open counts the server's connections that are not yet closed.
type answerServer struct {
	*httptest.Server
	hits atomic.Int64
	open atomic.Int64
}

func newAnswerServer(t *testing.T, status int, delay func(n int64) time.Duration) *answerServer {
	t.Helper()
	s := &answerServer{}
	s.Server = httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := s.hits.Add(1)
		if delay != nil {
			time.Sleep(delay(n))
		}
		w.WriteHeader(status)
	}))
	s.Config.ConnState = func(c net.Conn, st http.ConnState) {
		switch st {
		case http.StateNew:
			s.open.Add(1)
		case http.StateClosed, http.StateHijacked:
			s.open.Add(-1)
		}
	}
	s.Start()
	t.Cleanup(s.Close)
	return s
}

// silentServer accepts and reads, and never answers; open counts connections the client has not closed yet.
type silentServer struct {
	l        net.Listener
	accepted atomic.Int64
	open     atomic.Int64
	wg       sync.WaitGroup
}

func newSilentServer(t *testing.T) *silentServer {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	s := &silentServer{l: l}
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			s.accepted.Add(1)
			s.open.Add(1)
			s.wg.Add(1)
			go func() {
				defer s.wg.Done()
				_, _ = io.Copy(io.Discard, c) // ends when the client closes its side
				c.Close()
				s.open.Add(-1)
			}()
		}
	}()
	t.Cleanup(s.close)
	return s
}

func (s *silentServer) close()      { s.l.Close(); s.wg.Wait() }
func (s *silentServer) url() string { return "http://" + s.l.Addr().String() + "/generate_204" }

func shortLimits(t *testing.T, attempt, call time.Duration) {
	t.Helper()
	a, c := delayAttemptLimit, delayCallLimit
	delayAttemptLimit, delayCallLimit = attempt, call
	t.Cleanup(func() { delayAttemptLimit, delayCallLimit = a, c })
}

func waitFor(d time.Duration, ok func() bool) bool {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		if ok() {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return ok()
}

func TestDelayAnswers204ThroughFreedom(t *testing.T) {
	s := newAnswerServer(t, http.StatusNoContent, nil)
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.URL+"/generate_204", "")
	if err != nil {
		t.Fatalf("MeasureDelay: %v", err)
	}
	if ms < 0 || ms > 1000 {
		t.Fatalf("ms = %d, want a local delay", ms)
	}
	if got := s.hits.Load(); got != 2 {
		t.Fatalf("server saw %d requests, want 2 attempts", got)
	}
}

func TestDelayReturnsTheSmallerAttempt(t *testing.T) {
	const slow = 400 * time.Millisecond
	for _, slowOne := range []int64{1, 2} {
		t.Run(fmt.Sprintf("slow attempt %d", slowOne), func(t *testing.T) {
			s := newAnswerServer(t, http.StatusNoContent, func(n int64) time.Duration {
				if n == slowOne {
					return slow
				}
				return 0
			})
			start := time.Now()
			ms, err := MeasureDelay(probeConfig(heldPort(t)), s.URL, "")
			took := time.Since(start)
			if err != nil {
				t.Fatalf("MeasureDelay: %v", err)
			}
			if took < slow {
				t.Fatalf("call took %v: the slow attempt was not made", took)
			}
			if ms >= slow.Milliseconds() {
				t.Fatalf("ms = %d, want the fast attempt (< %d)", ms, slow.Milliseconds())
			}
			if got := s.hits.Load(); got != 2 {
				t.Fatalf("server saw %d requests, want 2", got)
			}
		})
	}
}

func TestDelayNon204IsAnError(t *testing.T) {
	s := newAnswerServer(t, http.StatusOK, nil)
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.URL, "")
	if err == nil || ms != -1 {
		t.Fatalf("got %d, %v; want -1 and an error", ms, err)
	}
	if !strings.Contains(err.Error(), "200") || !strings.Contains(err.Error(), "attempt 2") {
		t.Fatalf("error does not say why: %v", err)
	}
}

func TestDelayBadConfig(t *testing.T) {
	s := newAnswerServer(t, http.StatusNoContent, nil)
	for _, cfg := range []string{"", "not json", `{"outbounds": [{"protocol": "no-such-protocol"}]}`, `{}`} {
		ms, err := MeasureDelay(cfg, s.URL, "")
		if err == nil || ms != -1 {
			t.Fatalf("config %q: got %d, %v; want -1 and an error", cfg, ms, err)
		}
		t.Logf("config %q: %v", cfg, err)
	}
	if _, err := MeasureDelay(`{}`, s.URL, ""); err == nil || !strings.Contains(err.Error(), "no outbound") {
		t.Fatalf("a config without outbounds should say so: %v", err)
	}
	if got := s.hits.Load(); got != 0 {
		t.Fatalf("a bad config reached the server %d times", got)
	}
}

func TestDelayBadURL(t *testing.T) {
	for _, u := range []string{"ftp://127.0.0.1/x", "http://", "::bad"} {
		if ms, err := MeasureDelay(probeConfig(heldPort(t)), u, ""); err == nil || ms != -1 {
			t.Fatalf("url %q: got %d, %v", u, ms, err)
		}
	}
}

func TestDelayUnreachableURL(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := l.Addr().String()
	l.Close() // nothing listens there now
	start := time.Now()
	ms, err := MeasureDelay(probeConfig(heldPort(t)), "http://"+addr+"/generate_204", "")
	if err == nil || ms != -1 {
		t.Fatalf("got %d, %v; want -1 and an error", ms, err)
	}
	if took := time.Since(start); took > 3*time.Second {
		t.Fatalf("a refused connection took %v", took)
	}
	t.Logf("unreachable: %v", err)
}

func TestDelayAttemptTimeout(t *testing.T) {
	shortLimits(t, 400*time.Millisecond, 10*time.Second)
	s := newSilentServer(t)
	start := time.Now()
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.url(), "")
	took := time.Since(start)
	if err == nil || ms != -1 {
		t.Fatalf("got %d, %v; want -1 and an error", ms, err)
	}
	if strings.Count(err.Error(), "no answer within 400ms") != 2 {
		t.Fatalf("both attempts should time out on their own limit: %v", err)
	}
	if took < 800*time.Millisecond || took > 2*time.Second {
		t.Fatalf("two 400ms attempts took %v", took)
	}
	if s.accepted.Load() != 2 {
		t.Fatalf("server accepted %d connections, want 2", s.accepted.Load())
	}
	if !waitFor(2*time.Second, func() bool { return s.open.Load() == 0 }) {
		t.Fatalf("%d probe connections still open at the server", s.open.Load())
	}
}

func TestDelayWholeCallBound(t *testing.T) {
	shortLimits(t, 700*time.Millisecond, time.Second)
	s := newSilentServer(t)
	start := time.Now()
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.url(), "")
	took := time.Since(start)
	if err == nil || ms != -1 {
		t.Fatalf("got %d, %v; want -1 and an error", ms, err)
	}
	if took < 950*time.Millisecond || took > 1400*time.Millisecond {
		t.Fatalf("a call bounded at 1s took %v", took)
	}
	// The second attempt gets only what is left of the call (about 300ms), not its own 700ms.
	if !strings.Contains(err.Error(), "attempt 1: no answer within 700ms") ||
		!strings.Contains(err.Error(), "attempt 2: no answer within") || strings.Count(err.Error(), "700ms") != 1 {
		t.Fatalf("error: %v", err)
	}
	t.Logf("bounded call: %v in %v", err, took)
}

func TestDelayDefaultURL(t *testing.T) {
	// With url "" the probe asks probeURL; the engine's only outbound here is a blackhole, so nothing leaves the
	// machine and the test checks that the error names the default endpoint.
	shortLimits(t, 300*time.Millisecond, 600*time.Millisecond)
	cfg := `{"log":{"loglevel":"none"},"outbounds":[{"protocol":"blackhole"}]}`
	_, err := MeasureDelay(cfg, "", "")
	if err == nil || !strings.Contains(err.Error(), probeURL) {
		t.Fatalf("error should name %s: %v", probeURL, err)
	}
}

func TestDelayIfaceMissingFailsCleanly(t *testing.T) {
	s := newAnswerServer(t, http.StatusNoContent, nil)
	start := time.Now()
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.URL, "montana-nope0")
	if err == nil || ms != -1 || !strings.Contains(err.Error(), `interface "montana-nope0"`) {
		t.Fatalf("got %d, %v", ms, err)
	}
	if time.Since(start) > 200*time.Millisecond || s.hits.Load() != 0 {
		t.Fatalf("a missing interface must fail before any dial")
	}
}

func TestDelayIfaceLoopbackReachesLocal(t *testing.T) {
	lo := loopbackName(t)
	s := newAnswerServer(t, http.StatusNoContent, nil)
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.URL, lo)
	if err != nil || ms < 0 {
		t.Fatalf("bound to %s: %d, %v", lo, ms, err)
	}
}

// Bound to an interface that is not the loopback, a socket cannot reach 127.0.0.1: the failure shows the binding is
// applied to the probe's sockets.
func TestDelayIfaceBindingIsApplied(t *testing.T) {
	other := ""
	ifs, _ := net.Interfaces()
	for _, i := range ifs {
		if i.Flags&net.FlagUp != 0 && i.Flags&net.FlagLoopback == 0 {
			if addrs, _ := i.Addrs(); len(addrs) > 0 {
				other = i.Name
				break
			}
		}
	}
	if other == "" {
		t.Skip("no non-loopback interface is up")
	}
	shortLimits(t, 500*time.Millisecond, 1500*time.Millisecond)
	s := newAnswerServer(t, http.StatusNoContent, nil)
	ms, err := MeasureDelay(probeConfig(heldPort(t)), s.URL, other)
	if err == nil || ms != -1 {
		t.Fatalf("bound to %s, the probe still reached 127.0.0.1: %d, %v", other, ms, err)
	}
	if s.hits.Load() != 0 {
		t.Fatalf("the server was reached %d times through %s", s.hits.Load(), other)
	}
	t.Logf("bound to %s: %v", other, err)
}

// Two outbounds of a batch: a plain freedom that reaches the asked URL, and a freedom redirected to a silent server.
func batchOutbounds(silent *silentServer, silentFirst bool) string {
	answering := `{"protocol":"freedom"}`
	mute := fmt.Sprintf(`{"protocol":"freedom","settings":{"redirect":%q}}`, silent.l.Addr().String())
	if silentFirst {
		return "[" + mute + "," + answering + "]"
	}
	return "[" + answering + "," + mute + "]"
}

func measureMany(t *testing.T, outbounds, url string) []probeAnswer {
	t.Helper()
	js, err := MeasureMany(outbounds, url, 2, "", 1)
	if err != nil {
		t.Fatalf("MeasureMany: %v", err)
	}
	var answers []probeAnswer
	if err := json.Unmarshal([]byte(js), &answers); err != nil {
		t.Fatalf("answer %q: %v", js, err)
	}
	return answers
}

// Each outbound is asked on its own tag: were the dial not forced, both rows would ride the first (default) outbound
// and give the same answer.
func TestMeasureManyForcesEachOutbound(t *testing.T) {
	shortLimits(t, 400*time.Millisecond, 10*time.Second)
	for _, silentFirst := range []bool{true, false} {
		t.Run(fmt.Sprintf("silent first %v", silentFirst), func(t *testing.T) {
			ok := newAnswerServer(t, http.StatusNoContent, nil)
			silent := newSilentServer(t)
			start := time.Now()
			answers := measureMany(t, batchOutbounds(silent, silentFirst), ok.URL)
			took := time.Since(start)
			if len(answers) != 2 {
				t.Fatalf("answers %+v", answers)
			}
			okRow, muteRow := answers[0], answers[1]
			if silentFirst {
				okRow, muteRow = answers[1], answers[0]
			}
			if okRow.Ms < 0 || okRow.Err != "" {
				t.Fatalf("the answering outbound: %+v", okRow)
			}
			if muteRow.Ms != -1 || strings.Count(muteRow.Err, "no answer within 400ms") != 2 {
				t.Fatalf("the silent outbound: %+v", muteRow)
			}
			if ok.hits.Load() != 2 || silent.accepted.Load() != 2 {
				t.Fatalf("hits: 204 server %d, silent server %d; want 2 and 2", ok.hits.Load(), silent.accepted.Load())
			}
			if took > 1500*time.Millisecond {
				t.Fatalf("a batch bounded at 1s took %v", took)
			}
			t.Logf("%+v in %v", answers, took)
		})
	}
}

func TestMeasureManyKeepsARefusedOutboundInItsRow(t *testing.T) {
	ok := newAnswerServer(t, http.StatusNoContent, nil)
	answers := measureMany(t, `[{"protocol":"no-such-protocol"},{"protocol":"freedom"}]`, ok.URL)
	if len(answers) != 2 || answers[0].Ms != -1 || answers[0].Err == "" || answers[1].Ms < 0 || answers[1].Err != "" {
		t.Fatalf("answers %+v", answers)
	}
}

// MeasureUDP goes through the same filter: an engine that kept the config's inbound could not start on the held port.
// Nothing answers the STUN here, so the call ends in its own error -- never in one about listening.
func TestMeasureUDPBuildsWithoutInbounds(t *testing.T) {
	if _, err := MeasureUDP("not json", "127.0.0.1:3478", ""); err == nil {
		t.Fatal("a bad config passed")
	}
	quiet, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer quiet.Close()
	ms, err := MeasureUDP(probeConfig(heldPort(t)), quiet.LocalAddr().String(), "")
	if err == nil || ms != -1 {
		t.Fatalf("got %d, %v; want -1 and an error", ms, err)
	}
	if strings.Contains(err.Error(), "listen") || strings.Contains(err.Error(), "address already in use") {
		t.Fatalf("the inbound was kept: %v", err)
	}
	t.Logf("udp: %v", err)
}

func loopbackName(t *testing.T) string {
	ifs, _ := net.Interfaces()
	for _, i := range ifs {
		if i.Flags&net.FlagLoopback != 0 && i.Flags&net.FlagUp != 0 {
			return i.Name
		}
	}
	t.Skip("no loopback interface")
	return ""
}

func openFiles() int {
	entries, err := os.ReadDir("/proc/self/fd")
	if err != nil {
		return -1
	}
	return len(entries)
}

func settledGoroutines() int {
	runtime.GC()
	time.Sleep(50 * time.Millisecond)
	return runtime.NumGoroutine()
}

func TestDelayLeavesNothingBehind(t *testing.T) {
	shortLimits(t, 300*time.Millisecond, 2*time.Second)
	cfg := probeConfig(heldPort(t))

	// A first call outside the count: whatever the core starts once per process is not left behind by this function.
	warm := newAnswerServer(t, http.StatusNoContent, nil)
	if _, err := MeasureDelay(cfg, warm.URL, ""); err != nil {
		t.Fatal(err)
	}
	warm.Close()

	goroutinesBefore, filesBefore := settledGoroutines(), openFiles()

	ok := newAnswerServer(t, http.StatusNoContent, nil)
	bad := newAnswerServer(t, http.StatusOK, nil)
	silent := newSilentServer(t)
	lo := loopbackName(t)
	for k := 0; k < 10; k++ {
		if _, err := MeasureDelay(cfg, ok.URL, ""); err != nil {
			t.Fatalf("call %d: %v", k, err)
		}
		if _, err := MeasureDelay(cfg, ok.URL, lo); err != nil {
			t.Fatalf("call %d bound: %v", k, err)
		}
		if _, err := MeasureDelay(cfg, bad.URL, ""); err == nil {
			t.Fatal("non-204 passed")
		}
		if _, err := MeasureDelay(cfg, silent.url(), ""); err == nil {
			t.Fatal("silent server passed")
		}
		if _, err := MeasureDelay("not json", ok.URL, ""); err == nil {
			t.Fatal("bad config passed")
		}
		// The batch path: one engine, two outbounds forced by tag, one answering and one silent.
		js, err := MeasureMany(batchOutbounds(silent, k%2 == 0), ok.URL, 2, "", 1)
		if err != nil || strings.Count(js, `"err"`) != 1 {
			t.Fatalf("batch %d: %s, %v", k, js, err)
		}
	}

	// Every connection the probes opened is closed, as the servers see it.
	if !waitFor(3*time.Second, func() bool {
		return ok.open.Load() == 0 && bad.open.Load() == 0 && silent.open.Load() == 0
	}) {
		t.Fatalf("open at the servers: 204 %d, 200 %d, silent %d", ok.open.Load(), bad.open.Load(), silent.open.Load())
	}
	ok.Close()
	bad.Close()
	silent.close()

	var goroutinesAfter, filesAfter int
	settled := waitFor(5*time.Second, func() bool {
		goroutinesAfter, filesAfter = settledGoroutines(), openFiles()
		return goroutinesAfter <= goroutinesBefore && filesAfter <= filesBefore
	})
	t.Logf("60 calls (10 of them batches): goroutines %d -> %d, open files %d -> %d", goroutinesBefore, goroutinesAfter, filesBefore, filesAfter)
	if !settled {
		buf := make([]byte, 1<<20)
		t.Fatalf("left behind: goroutines %d -> %d, open files %d -> %d\n%s", goroutinesBefore, goroutinesAfter,
			filesBefore, filesAfter, buf[:runtime.Stack(buf, true)])
	}
}
