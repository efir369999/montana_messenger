import Foundation
import os.log

// Moves IP packets between the tunnel and Xray's local SOCKS inbound. The pump is hev-socks5-tunnel
// (github.com/heiher/hev-socks5-tunnel, MIT): a userspace TCP/IP stack written in C, the same one Orbot
// carries. It replaces a second Go stack whose per-connection cost lived in the same heap Xray does,
// under a ceiling the system enforces near fifty megabytes.
//
// Three of its settings are the reason it is here. A session costs a task stack plus a buffer, both
// fixed and both allocated in C rather than on the Go heap, so no collector can be made to thrash by
// them. And `max-session-count` bounds how many exist at once — the one thing that actually stops a
// reconnect storm, which is what every recorded death here has been: a phone that lost its routes and
// brought every application back at the same instant, 77 connections to 363 in a second and a half.
//
// The limit propagates on its own: the pump opens exactly one SOCKS connection per session, so bounding
// sessions bounds Xray too. One number governs both stacks.
final class MontanaPacketPump {
    static let shared = MontanaPacketPump()
    private let log = OSLog(subsystem: MTTunnelIds.extensionBundleId, category: "pump")
    private let queue = DispatchQueue(label: "mt.ext.pump", qos: .userInitiated)
    private let stateLock = NSLock()
    private var running = false
    private let exited = DispatchGroup()
    var onUnexpectedExit: (() -> Void)?

    @discardableResult
    func start(socksHost: String, socksPort: Int) -> Bool {
        stateLock.lock()
        let alreadyRunning = running
        stateLock.unlock()
        if alreadyRunning { return true }
        guard exited.wait(timeout: .now() + 3) == .success else {
            ExtLog.write("pump: previous loop has not exited"); return false
        }
        guard let fd = Self.tunFileDescriptor() else {
            ExtLog.write("pump: utun fd NOT FOUND")
            os_log("pump: utun fd not found", log: log, type: .error)
            return false
        }
        stateLock.lock(); running = true; stateLock.unlock()
        exited.enter()
        // The pump's own diagnostics go to a file beside the extension's trace. Sent to stderr they
        // reach nowhere an extension can be read from, and a configuration it rejects would be silent.
        let pumpLog = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("pump.log").path) ?? "stderr"
        // Timeouts match the connection policy the core already carries, so a finished flow stops
        // holding a session at the same moment it stops holding a proxy buffer.
        //
        // THE CEILING IS OURS, NOT THE SYSTEM'S (22.09). The number below used to be 128 -- inherited from
        // the library's example and derived from no budget at all -- while the budget it must fit is about
        // fifty megabytes, of which the system starts taking the process at forty. Measured on T1 in one
        // day: five warnings at footprint 39.8 to 40.8 MB with the engine holding 47 MB of live heap and
        // 954 goroutines, then death; eight deaths in ten sessions; and, at rest, a whole session living at
        // 17 to 19 MB with 30 to 60 goroutines. The ceiling that actually bounded us was the system's
        // killer, and a refusal we never made.
        //
        // The derivation, conservative in the only direction that matters:
        //   base, measured at rest .............. 15 MB (engine + pump + provider)
        //   target ceiling ...................... 30 MB (the system takes the process at 40; a quarter of
        //                                        the way back is the margin)
        //   left for flows ...................... 15 MB
        //   cost per flow, LOWER bound .......... 0.37 MB (47 MB of live heap at the moment of death over
        //                                        the ceiling that stood then: whatever the true number of
        //                                        flows was, it was not above 128, so the true cost per
        //                                        flow is not below this)
        //   ceiling = 15 / 0.37 ................. 40 flows, and 32 is that with a margin
        // Sensitivity: at 0.25 MB a flow, 32 flows cost 8 MB (footprint 23, comfortable); at 0.50 they cost
        // 16 MB (footprint 31, still under the warning line). At 128 the same spread spans 32 to 64 MB --
        // above the killer in both halves, which is exactly what the diary shows.
        //
        // AND THIS NUMBER IS THE REFUSAL. The library offers no way to close the door under pressure, so
        // the refusal has to be the ceiling itself: the thirty-third flow waits instead of the whole tunnel
        // dying. A page that stalls for a moment is a smaller harm than a session the system takes, and the
        // person can tell the two apart.
        let sessionCeiling = 32
        let config = """
        tunnel:
          mtu: 1400
        socks5:
          port: \(socksPort)
          address: \(socksHost)
          udp: 'udp'
        misc:
          task-stack-size: 16384
          tcp-buffer-size: 8192
          max-session-count: \(sessionCeiling)
          connect-timeout: 5000
          tcp-read-write-timeout: 30000
          udp-read-write-timeout: 30000
          log-file: \(pumpLog)
          log-level: warn
          limit-nofile: 4096
        """
        ExtLog.write("pump start fd=\(fd) -> \(socksHost):\(socksPort) sessions<=\(sessionCeiling) stack=16k buf=8k")
        os_log("pump start fd=%d -> %{public}@:%d", log: log, type: .info, fd, socksHost, socksPort)
        // The call is the event loop itself and returns only on quit, so it owns this thread.
        queue.async {
            var cfg = config
            let code = cfg.withUTF8 { buf in
                hev_socks5_tunnel_main_from_str(buf.baseAddress, UInt32(buf.count), fd)
            }
            self.stateLock.lock()
            let unexpected = self.running
            self.running = false
            self.stateLock.unlock()
            if unexpected { self.onUnexpectedExit?() }
            self.exited.leave()
            ExtLog.write("pump exited code=\(code)")
            os_log("pump exited code=%d", log: self.log, type: .info, code)
        }
        return true
    }

    func stop() {
        stateLock.lock()
        guard running else { stateLock.unlock(); return }
        running = false
        stateLock.unlock()
        hev_socks5_tunnel_quit()
        ExtLog.write("pump stop")
        os_log("pump stop", log: log, type: .info)
    }

    // Byte counters straight from the pump, so the log can show whether traffic actually moves rather
    // than only how much memory is held while it may not.
    func traffic() -> String {
        let s = rawStats()
        return "io{tx=\(s.txb / 1024)KB rx=\(s.rxb / 1024)KB pkts=\(s.txp + s.rxp)}"
    }

    /// The same counters as numbers, for the app asking over a provider message.
    func rawStats() -> (txp: Int, txb: Int, rxp: Int, rxb: Int) {
        var txp = 0, txb = 0, rxp = 0, rxb = 0
        hev_socks5_tunnel_stats(&txp, &txb, &rxp, &rxb)
        return (txp, txb, rxp, rxb)
    }

    // The packet-tunnel's utun interface fd (standard NEPacketTunnelProvider technique: scan fds, read
    // UTUN_OPT_IFNAME via getsockopt, match "utun").
    private static func tunFileDescriptor() -> Int32? {
        let SYSPROTO_CONTROL: Int32 = 2
        let UTUN_OPT_IFNAME: Int32 = 2
        for fd in Int32(0)..<Int32(1024) {
            var buf = [CChar](repeating: 0, count: 256)
            var len = socklen_t(buf.count)
            if getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &buf, &len) == 0 {
                if String(cString: buf).hasPrefix("utun") { return fd }
            }
        }
        return nil
    }
}
