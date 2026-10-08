import NetworkExtension
import Foundation
import Darwin
#if canImport(MontanaXray)
import MontanaXray
#endif
import os.log

// Stage 10 (spec s.3 §4.2, §12.3): Montana packet-tunnel extension. iOS routes device traffic through
// this NEPacketTunnelProvider; it runs the Xray-core engine (MontanaXray gomobile xcframework, built
// from github.com/xtls/xray-core) with the chosen VLESS+Reality outbound and pumps packets between the
// tun and Xray's local SOCKS inbound. Reality/X25519 is the classical circumvention wrapper only.
// Crash-test grade tracing. Milliseconds on every line and a sample twice a second, about five hours
// kept. The window is held by rotating two files rather than reading one back and filtering it: at two
// lines a second the file runs to several megabytes, and pulling that into a process the system
// terminates near fifty is the very failure this log exists to catch. A rename costs nothing and cannot
// fail under pressure. Every line reaches disk the moment it happens — a session that gets killed is
// exactly the session whose record matters, and it never reaches the tidy ending where a buffer could
// have been flushed.
enum ExtLog {
    private static let q = DispatchQueue(label: "mt.ext.log")
    private static let osl = OSLog(subsystem: MTTunnelIds.extensionBundleId, category: "ext")
    private static let iso: ISO8601DateFormatter = {   // one formatter, not one per line
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    /// Half the budget: the trace occupies two files, so rotating at this size keeps the pair between
    /// half a megabyte and one on disk at every moment, and never more.
    ///
    /// The size is asked of the file, not counted in the process. A per-process counter starts at zero
    /// with every launch and therefore never reaches its threshold on a tunnel that restarts often —
    /// the file then grows without bound, which is exactly the case a diagnostic log must survive. The
    /// offset returned by seeking to the end is the file's own length and costs nothing extra.
    private static let rotateAtBytes: UInt64 = 512 * 1024

    private static var dir: URL? { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first }
    private static var url: URL? { dir?.appendingPathComponent("ext.log") }
    private static var prevURL: URL? { dir?.appendingPathComponent("ext.prev.log") }

    static func write(_ m: String) {
        os_log("%{public}@", log: osl, type: .info, m)
        let line = "\(iso.string(from: Date())) \(m)\n"
        q.async {
            guard let url = url, let data = line.data(using: .utf8) else { return }
            var size = UInt64(data.count)
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                size += (try? h.seekToEnd()) ?? 0
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
            if size >= rotateAtBytes, let prev = prevURL {
                let fm = FileManager.default
                try? fm.removeItem(at: prev)
                try? fm.moveItem(at: url, to: prev)
            }
        }
    }
}

extension PacketTunnelProvider {
    /// What this process has to say about itself: the dated tail of its running record. How the previous
    /// session ended and the fatal signal, when one was caught, are already in it -- both are written into the
    /// record at the next start, dated, once (24.09: the crash file had no dates and was sent again at every
    /// up, and a live line about the previous session read the running session's own heartbeat). The app
    /// carries only the lines newer than the last it carried, so the window is wide: hours, not forty lines.
    static func diaryTail(_ limit: Int = 48 * 1024) -> String {
        guard let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ext.log"),
              let h = try? FileHandle(forReadingFrom: u) else { return "no record" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let from = UInt64(limit) < size ? size - UInt64(limit) : 0
        try? h.seek(toOffset: from)
        guard let d = try? h.readToEnd(), !d.isEmpty else { return "no record" }
        var lines = String(decoding: d, as: UTF8.self).split(separator: "\n")
        if 0 < from, !lines.isEmpty { lines.removeFirst() }   // the cut fell inside a line
        return lines.isEmpty ? "no record" : lines.joined(separator: "\n")
    }
}

enum ExtCrash {
    private static var fd: Int32 = -1
    static func arm() {
        guard fd < 0 else { return }   // one descriptor and one set of handlers for the life of the process
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let path = dir.appendingPathComponent("ext.crash.log").path
        fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        NSSetUncaughtExceptionHandler { ex in
            ExtLog.write("CRASH uncaught exception \(ex.name.rawValue): \(ex.reason ?? "-") | \(ex.callStackSymbols.prefix(12).joined(separator: " | "))")
        }
        for sig in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                ExtCrash.emit(s)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
    /// The fatal signal's record, handed over ONCE at the next start (to be written into the dated record)
    /// and emptied in place -- the descriptor above keeps appending to the same file.
    static func take() -> [String] {
        guard let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ext.crash.log"),
              let d = try? Data(contentsOf: u), !d.isEmpty else { return [] }
        if let h = try? FileHandle(forWritingTo: u) { try? h.truncate(atOffset: 0); try? h.close() }
        let lines = String(decoding: d.prefix(16 * 1024), as: UTF8.self).split(separator: "\n").map(String.init)
        return Array(lines.filter { !$0.isEmpty }.prefix(48))
    }
    // Runs while the process is dying: only descriptor writes, no allocation, no formatter.
    fileprivate static func emit(_ sig: Int32) {
        guard fd >= 0 else { return }
        var head = "\nCRASH fatal signal \(sig) — extension died here\n"
        head.withUTF8 { _ = write(fd, $0.baseAddress, $0.count) }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 40)
        let n = backtrace(&frames, Int32(frames.count))
        backtrace_symbols_fd(&frames, n, fd)
    }
}

// Newest heartbeat of the running session. Present on next start == the previous session did not stop
// cleanly; its contents say when it was last alive and with how much memory.
// A minute-by-minute record of how the tunnel is actually living, kept for twelve hours. One line is
// a snapshot; a column of them is a trajectory, and the trajectory is what says whether memory creeps,
// whether the collector settles after a burst, and whether an hour of quiet looks like the hour before
// it. The same file serves a live watch — reading its tail is watching the tunnel breathe.
enum ExtSession {
    private static var url: URL? {
        guard let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return d.appendingPathComponent("session.alive")
    }
    /// The build that runs, kept in the marker: the next start tells an update of the app from a death by it.
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    static func beat(_ line: String) { if let u = url { try? Data("\(line) build=\(build)".utf8).write(to: u) } }
    /// A word added to the running marker -- the system's warning that it is about to reclaim -- so a death in
    /// the next seconds is named for what preceded it.
    static func note(_ word: String) {
        guard let u = url, let d = try? Data(contentsOf: u), let t = String(data: d, encoding: .utf8),
              !t.contains(word) else { return }
        try? Data("\(t) \(word)".utf8).write(to: u)
    }
    static func clear() { if let u = url { try? FileManager.default.removeItem(at: u) } }
    static func previous() -> (line: String, ago: TimeInterval, at: Date)? {
        guard let u = url, let d = try? Data(contentsOf: u), let t = String(data: d, encoding: .utf8),
              let m = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
        else { return nil }
        return (t, Date().timeIntervalSince(m), m)
    }
    /// WHY THE PREVIOUS SESSION ENDED WITHOUT A STOP (24.09), named from what is known for certain, in this
    /// order: the fatal signal it wrote; an update of the app -- the build changed (a marker without a build was
    /// written by an older one), and the system kills the extension for an install without calling its stop
    /// (T1, 23.09: three installs, three such ends, each in the minute of its install); a restart of the device
    /// (the kernel booted after the last heartbeat); the system's warning that it is about to reclaim, heard
    /// before the end; the kernel's headroom nearly gone at the last heartbeat. Anything else is said as
    /// unexplained, not guessed.
    static func cause(of marker: String, at: Date, crashed: [String]) -> String {
        if let head = crashed.first(where: { $0.contains("fatal signal") }) {
            return "crash-signal-\(PacketTunnelProvider.parseNumber(head, key: "fatal signal "))"
        }
        if !crashed.isEmpty { return "crash" }
        guard let r = marker.range(of: " build=") else { return "reinstalled" }
        if marker[r.upperBound...].prefix(while: { !$0.isWhitespace }) != Substring(build) { return "reinstalled" }
        if at.timeIntervalSince1970 < bootTime() { return "rebooted" }
        if marker.contains("dead=upstream") { return "dead-upstream" }   // the tunnel's own verdict, said before it went
        if marker.contains("dead=blocked") { return "dead-blocked" }     // the system carried nothing into it (MTTunnelDeath)
        if marker.contains("press=critical") { return "memory" }
        // The headroom is trusted only when the kernel reported one: a zero is «not said», not «nothing left».
        if let left = headroomMB(marker), 0 < left, left < 5 { return "memory-suspect" }
        return "unexplained"
    }
    /// The «left=» of a heartbeat, in megabytes with the decimals the line carries.
    static func headroomMB(_ marker: String) -> Double? {
        guard let r = marker.range(of: " left=") else { return nil }
        return Double(marker[r.upperBound...].prefix(while: { $0.isNumber || $0 == "." }))
    }
    /// When this device last booted, by the kernel's own clock; 0 when it will not say.
    static func bootTime() -> TimeInterval {
        var tv = timeval(); var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(tv.tv_sec)
    }
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = OSLog(subsystem: MTTunnelIds.extensionBundleId, category: "tunnel")
    private let socksPort = 10808
    private var memTimer: DispatchSourceTimer?
    // THE ROAD BEHIND THE TUNNEL IS JUDGED BY ITS BYTES (25.09). On the iPhone 15 at 22:26:56 the server behind the
    // tunnel went silent: for ten minutes the pump carried 70-240 kbps out and 0-2 kbps in, every knock at a node
    // timed out at five seconds, the call had no road for its restart, the engine piled up 891 goroutines on
    // connections nobody answered, and the system took the process at memory-critical. The platform showed the
    // tunnel connected the whole time: it judges the interface, not the road behind it. The road is judged here, by
    // the one witness that cannot lie about it -- bytes in against bytes out -- and a silent upstream is raised anew
    // on the same line the hot-swap walks (one owner of the engine's raise), with a backoff, so a network with no
    // way out at all is not hammered.
    private let measurementLine = DispatchQueue(label: "mt.ext.measure")
    private let engineLine = DispatchQueue(label: "mt.ext.engine")
    private var engineConfig: String?                 // the full engine config of the running server, for a raise
    private var lifeTimer: DispatchSourceTimer?
    private var lifeLast: (txb: Int, rxb: Int, at: Date)?
    private var lifeSilentSince: Date?                // the first sample with bytes out and none in
    private var lifeNextRaise = Date.distantPast      // the backoff: no raise before this
    private var lifeRaises = 0                        // raises this session; the app reads it as `raised`
    private var lifeRaiseStep: TimeInterval = 30      // doubles per raise up to five minutes; back to 30 when bytes come in
    private static let lifeSample: TimeInterval = 10
    private static let lifeSilentAfter: TimeInterval = 20
    private static let lifeOutFloor = 16 * 1024       // bytes out per sample that make silence a verdict, not idleness
    private static let lifeInFloor = 1024             // bytes in per sample that still count as silence (the ACKs of dead flows)
    private var lifeInAfterRaise = false
    private var lifetime = MTTunnelLifetime()
    // THE LIVING SECONDS (MTTunnelAlive): counted on the engine's line by the life watch, told to the app when it asks.
    private var living = MTTunnelAlive(total: UserDefaults.standard.double(forKey: MTTunnelAlive.totalKey))
    private var candidates: [MTTunnelCandidate] = []
    private var candidateIndex = 0
    private var profileRow = ""
    private var runningRow = ""
    private var recoveryAttempts = 0
    private var retry = MTTunnelRetry()
    private var recovering = false
    private var pathObservation: NSKeyValueObservation?
    // THE DEAD SESSION (29.09, MTTunnelDeath): its judge, the app's witness of the system's own word, and one release.
    private var death = MTTunnelDeath()
    private var appBlocked: (seconds: Int, at: Date)?
    private var releasing = false
    private static let witnessFresh: TimeInterval = 45          // a witness older than a beat and a half says nothing
    private static let blockedRestartKey = "ext.blocked.restartAt"   // this extension's store: the last restart for a block

    override init() {
        super.init()
        ExtLog.write("provider initialized build=\(ExtSession.build)")
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        lifetime.stop()
        let run = MTTunnelLifetime(completion: completionHandler)
        lifetime = run
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 45) { [weak self] in
            let error = NSError(domain: "montana.tunnel", code: 8,
                                userInfo: [NSLocalizedDescriptionKey: "Tunnel startup timed out"])
            if run.finish(error) {
                run.stop()
                ExtLog.write("startup deadline reached; On Demand keeps the requested connection")
                self?.cancelTunnelWithError(error)
            }
        }
        let completionHandler: (Error?) -> Void = { error in _ = run.finish(error) }
        let crashed = ExtCrash.take()   // before arming: the record of the last death, not of this life
        ExtCrash.arm()
        if let prev = ExtSession.previous() {
            ExtLog.write(String(format: "PREVIOUS SESSION DID NOT STOP CLEANLY — killed or crashed %.0fs ago; last heartbeat: %@ cause=%@",
                                prev.ago, prev.line, ExtSession.cause(of: prev.line, at: prev.at, crashed: crashed)))
            ExtSession.clear()
        }
        for line in crashed { ExtLog.write("crash record: " + line) }
        os_log("Montana tunnel start", log: log, type: .info); NSLog("[montana-vpn-ext] startTunnel enter"); ExtLog.write("startTunnel enter")
        // Written out now, not only at a clean stop. A session that is killed never reaches stopTunnel,
        // and the ring died with it — which is how three hours of a soak test left no record at all.
        // Who raised it: the app names itself in the options; the system -- the reconnect, or the switch in
        // its own panel -- passes none.
        let by = (options?["mt.by"] as? String) ?? "system"
        ExtLog.write("── session start by=\(by) build=\(ExtSession.build) ──")
        ExtReconnect.arm(run) // ON is kept even when this attempt fails before the tunnel stands.
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let pconf = proto.providerConfiguration,
              let b64 = pconf["xray"] as? String, let outboundData = Data(base64Encoded: b64),
              let outbound = try? JSONSerialization.jsonObject(with: outboundData) as? [String: Any] else {
            ExtLog.write("bad providerConfiguration (no xray)"); NSLog("[montana-vpn-ext] bad providerConfiguration (no xray)"); completionHandler(NSError(domain: "montana.tunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad tunnel config"])); return
        }

        // A profile has exactly the outbound the person selected.  Ignore a rotation left by an
        // earlier build as well, so installing this build cannot silently continue a server switch.
        candidates = []
        let current: [String: Any] = ["row": pconf["row"] as? String ?? "", "host": proto.serverAddress ?? "",
                                      "xray": b64]
        if let first = MTTunnelCandidate(current) {
            candidates = [first] + candidates.filter { $0.row != first.row }
        }
        candidateIndex = 0
        death.reset(); appBlocked = nil; releasing = false
        profileRow = pconf["row"] as? String ?? ""
        runningRow = profileRow
        // tun settings: full-tunnel routing, our DNS. tunnelRemoteAddress MUST be an IP literal —
        // iOS rejects a hostname ("Invalid NETunnelNetworkSettings tunnelRemoteAddress"). It is purely
        // informational: the engine alone resolves and dials the server.
        let remoteIP = "192.0.2.1" // informational only; DNS cannot hold provider startup
        NSLog("[montana-vpn-ext] tunnelRemoteAddress %@ -> %@", proto.serverAddress ?? "-", remoteIP); ExtLog.write("tunnelRemoteAddress \(proto.serverAddress ?? "-") -> \(remoteIP)")
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteIP)
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Local networks are excluded by the platform property on the protocol (set by the app), not by
        // hand-rolled routes. Multicast is listed here because it is not part of that definition and
        // Bonjour discovery rides on it.
        ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: "224.0.0.0", subnetMask: "240.0.0.0")]
        settings.ipv4Settings = ipv4
        // Capture IPv6 too: many carriers are IPv6-only on LTE, so without this the cellular traffic
        // bypasses the tunnel and the VPN "does not work on LTE".
        let ipv6 = NEIPv6Settings(addresses: ["fd6d:6f6e:7461::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        ipv6.excludedRoutes = [NEIPv6Route(destinationAddress: "ff00::", networkPrefixLength: 8)]   // multicast
        settings.ipv6Settings = ipv6
        settings.mtu = 1400   // safe on cellular (avoids fragmentation)
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8", "2606:4700:4700::1111", "2001:4860:4860::8888"])

        setTunnelNetworkSettings(settings) { [weak self] err in
            guard let self, run.isAlive else { return }
            if let err { ExtLog.write("tun settings error: \(String(describing: err))"); NSLog("[montana-vpn-ext] tun settings error: %@", String(describing: err)); os_log("tun settings error: %{public}@", log: self.log, type: .error, String(describing: err)); completionHandler(err); return }

            guard let cfgStr = Self.fullConfigString(outbound, socksPort: self.socksPort) else {
                completionHandler(NSError(domain: "montana.tunnel", code: 2)); return
            }
            self.engineLine.async {
                guard run.isAlive else { return }
                self.engineConfig = cfgStr
                // Start the Xray engine. MontanaXray is the gomobile xcframework (linked once built).
                let initialError = MontanaXrayBridge.run(cfgStr)
                if initialError != nil { ExtLog.write("initial engine failed; waiting for a working fallback") }
                self.recovering = initialError != nil
                guard run.isAlive else { MontanaXrayBridge.stop(); return }
                ExtLog.write("engine start attempted: ready=\(initialError == nil)")
                // Bridge tun <-> local SOCKS (tun2socks). Started here; the pump reads NEPacketTunnelFlow.
                MontanaPacketPump.shared.onUnexpectedExit = { [weak self] in
                    guard let self else { return }
                    self.engineLine.async {
                        guard self.lifetime.isAlive else { return }
                        self.recovering = true; self.reasserting = true; self.retry.reset()
                    }
                }
                ExtLog.write("starting packet pump")
                if initialError == nil, !MontanaPacketPump.shared.start(socksHost: "127.0.0.1", socksPort: self.socksPort) {
                    self.recovering = true
                }
                self.reasserting = self.recovering
                ExtLog.write("tunnel UP (completionHandler nil)"); NSLog("[montana-vpn-ext] tunnel UP")
                self.sessionStart = Date()
                ExtSession.beat("up=0h00m00s")   // a death before the first heartbeat is a death too
                self.startMemoryWatch()
                self.startMemoryPressureWatch()
                self.startLifeWatch()
                self.pathObservation = self.observe(\.defaultPath, options: [.new]) { [weak self] _, _ in
                    guard let self else { return }
                    self.engineLine.async {
                        guard self.lifetime.isAlive else { return }
                        self.retry.reset()
                        self.lifeLast = nil
                        if self.phonePathUp, self.recovering { self.recoverUpstream() }
                    }
                }
                completionHandler(nil)
            }
        }
    }

    // Full Xray config (SOCKS inbound + chosen outbound + routing) — shared by start and hot-swap.
    static func fullConfigString(_ outbound: [String: Any], socksPort: Int) -> String? {
        // Connection policy is what keeps this process alive. Without it every connection holds the
        // default buffer and no idle timeout: a burst of flows took the extension from 14 MB to 42 MB
        // and 575 goroutines in fifty seconds, and the system terminated it. Small buffers plus short
        // idle and handshake limits make a burst survivable instead of fatal.
        let policy: [String: Any] = ["levels": ["0": ["handshake": 4, "connIdle": 30,
                                                      "uplinkOnly": 1, "downlinkOnly": 1,
                                                      "bufferSize": 4]]]   // KB per connection
        // Sniffing is dropped: it costs a read buffer on every connection and nothing here consumes
        // the result — routing decides by address, not by sniffed protocol.
        // That is also the MIP's own requirement for the carrier's inbound (s 4.4: no sniffing there,
        // else the engine may replace the destination address with a name and break the addressing).
        //
        // NAMED DEVIATION FROM THE MIP (s 4.4). The MIP asks for a SECOND, tagged inbound named
        // "mt-overlay-in" with a rule of its own standing first. The carrier uses THIS inbound instead,
        // and the reason is not convenience: a second listening port is a second way for the engine to
        // refuse to start -- a port still held by the previous instance during a restart, and this process
        // is killed and restarted by the system several times an hour (measured on T1, 22.09) -- which
        // would cost the whole tunnel to gain a tag. What the tag buys is three properties, and all three
        // hold here by construction: UDP is carried, no sniffing key exists, and the only rule before the
        // proxy rule catches private and loopback addresses, which a reflector and a neighbour never are.
        // The ring holds the three (P-99), so the properties cannot drift away unnoticed.
        let full: [String: Any] = [
            "log": ["loglevel": "warning"],
            "policy": policy,
            "inbounds": [["tag": "socks-in", "listen": "127.0.0.1", "port": socksPort, "protocol": "socks",
                          "settings": ["udp": true, "auth": "noauth"]]],
            "outbounds": [outbound, ["protocol": "freedom", "tag": "direct"]],
            // Private and loopback destinations leave through `direct` even if a packet ever reaches
            // the engine. Sending a LAN address to a remote proxy cannot work and would break every
            // local service on the network; a reference client routes them out untouched.
            "routing": ["rules": [
                ["type": "field", "outboundTag": "direct",
                 "ip": ["127.0.0.0/8", "::1/128", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                        "169.254.0.0/16", "224.0.0.0/4", "fe80::/10", "fc00::/7", "ff00::/8"]],
                ["type": "field", "outboundTag": "proxy", "network": "tcp,udp"],
            ]]
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: full) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // Seamless server switch: the app sends the new outbound; restart Xray in place, tun stays up.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // The living seconds (MTTunnelAlive), read on the engine's line where the life watch counts them.
        if messageData == Data("alive".utf8) {
            engineLine.async {
                let d = try? JSONSerialization.data(withJSONObject: ["alive_s": self.living.told(now: MTTunnelAlive.clock()),
                                                                     "held": self.living.last != nil, "epoch": MTTunnelAlive.epoch()])
                completionHandler?(d)
            }
            return
        }
        // A BATCH OF SERVERS THROUGH ONE ENGINE INSTANCE (29.09, the critic's P-1): the app asks for up to six at once, the
        // engine stands one instance up for the batch and answers every row in order within its own 8 s deadline, so
        // nothing of a batch outlives the asker (P-2). One batch waits on the engine line as one measurement did:
        // life-watch events get their turn between batches.
        if messageData.starts(with: Data("probes:".utf8)),
           let value = try? JSONSerialization.jsonObject(with: messageData.dropFirst(7)) as? [String: Any],
           let outbounds = value["outbounds"] as? [[String: Any]] {
            let run = lifetime
            let stun = value["stun"] as? String ?? ""
            let width = value["width"] as? Int ?? 6
            measurementLine.async {
                self.engineLine.sync {
                    guard run.isAlive, !self.recovering else {
                        completionHandler?(try? JSONSerialization.data(withJSONObject: ["error": "busy"])); return
                    }
                    let memory = Self.memoryLedgerMB()
                    guard memory.left >= 20 || (memory.left <= 0 && memory.now < 24) else {
                        completionHandler?(try? JSONSerialization.data(withJSONObject: ["error": "busy"])); return
                    }
                    let deadline = self.engineDeadline()
                    defer { deadline.finish(nil) }
                    let answers = MontanaXrayBridge.measureMany(outbounds, stun: stun, width: width)
                    guard run.isAlive else { completionHandler?(nil); return }
                    completionHandler?(try? JSONSerialization.data(withJSONObject: ["answers": answers]))
                }
            }
            return
        }
        if messageData == Data("restart".utf8) {
            completionHandler?(Data([1]))
            cancelTunnelWithError(NSError(domain: "montana.tunnel", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Unresponsive engine restart"]))
            return
        }
        if messageData == Data("health".utf8) {
            completionHandler?(lifetime.isAlive ? Data([1]) : nil); return
        }
        if messageData.starts(with: Data("plan:".utf8)),
           let plan = try? JSONSerialization.jsonObject(with: messageData.dropFirst(5)) as? [String: Any] {
            engineLine.async {
                guard self.lifetime.isAlive,
                      let encoded = plan["xray"] as? String,
                      let bytes = Data(base64Encoded: encoded),
                      let outbound = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let config = Self.fullConfigString(outbound, socksPort: self.socksPort) else {
                    completionHandler?(nil); return
                }
                let row = plan["row"] as? String ?? ""
                let current: [String: Any] = ["row": row, "host": plan["host"] as? String ?? "", "xray": encoded]
                self.candidates = [MTTunnelCandidate(current)].compactMap { $0 }
                self.candidateIndex = 0
                self.profileRow = row
                self.runningRow = row
                self.recoveryAttempts = 0
                self.retry.reset()
                self.lifeLast = nil; self.lifeSilentSince = nil; self.lifeInAfterRaise = false; self.death.reset()
                self.recovering = self.raiseEngine(config, why: "chosen server") != nil
                self.reasserting = self.recovering
                completionHandler?(Data([self.recovering ? 0 : 1]))
            }
            return
        }
        // The tunnel's own words, asked for by the app and written by it into the diary. Until this
        // existed a death here reached the person as "an internal error occurred" and reached the diary
        // as nothing at all: this process keeps its record inside its own container, which the app
        // cannot read, so every failure of the tunnel was unnamed by construction (22.09).
        if messageData == Data("diary".utf8) {
            completionHandler?(Data(Self.diaryTail().utf8)); return
        }
        // The app's question about the reconnect: what this session's arm said. The answer waits for the arm on its
        // line, so the question never overtakes it (ExtReconnect).
        if messageData == Data("reconnect?".utf8) {
            ExtReconnect.answer { completionHandler?(Data($0.utf8)) }; return
        }
        // The app polls tunnel throughput while connected; the door's atoms ride the SAME beat. A
        // measurement costs a minute of silence and cannot be the answer to a message; a second timer
        // to collect it would be a patrol where a beat already passes (one road, not two).
        if messageData == Data("stats".utf8) || messageData.starts(with: Data("stats:".utf8)) {
            let s = MontanaPacketPump.shared.rawStats()
            // The app's witness rides the beat (29.09): how long its own path -- the system's word for every app -- has stood
            // unsatisfied under this tunnel. The tunnel sees its bytes and the phone's own network, never that word.
            let witness = messageData.count > 6 ? (try? JSONSerialization.jsonObject(with: messageData.dropFirst(6))) as? [String: Any] : nil
            // The road's verdict rides the same beat: how long the upstream has returned nothing, and how many
            // times this session raised the engine for it. Read on the engine's line, where it is written.
            engineLine.async {
            if let seconds = witness?["blocked_s"] as? Int { self.appBlocked = (max(0, seconds), Date()) }
            let life = (silent: self.lifeSilentSince.map { Int(Date().timeIntervalSince($0)) } ?? 0, raised: self.lifeRaises)
            let d = try? JSONSerialization.data(withJSONObject:
                ["txp": s.txp, "txb": s.txb, "rxp": s.rxp, "rxb": s.rxb,
                 "dead_s": life.silent, "raised": life.raised,
                 "row": self.runningRow])
            completionHandler?(d)
            }
            return
        }
        guard let outbound = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let cfgStr = Self.fullConfigString(outbound, socksPort: socksPort) else {
            NSLog("[montana-vpn-ext] handleAppMessage: bad outbound"); completionHandler?(nil); return
        }
        NSLog("[montana-vpn-ext] handleAppMessage: hot-swap server")
        engineLine.async { [weak self] in
            guard let self else { completionHandler?(nil); return }
            if let err = self.raiseEngine(cfgStr, why: "hot-swap") {
                NSLog("[montana-vpn-ext] swap xray err %@", err); completionHandler?(nil); return
            }
            NSLog("[montana-vpn-ext] hot-swap done")
            completionHandler?(Data([1]))
        }
    }

    /// THE ENGINE RAISED ANEW IN PLACE -- the tun stays up, the pump re-dials its flows. One road for the hot-swap of
    /// a server and for the watchdog below; both walk it on the engine's line, never at once.
    private func raiseEngine(_ cfgStr: String, why: String) -> String? {
        let deadline = engineDeadline()
        defer { deadline.finish(nil) }
        guard lifetime.isAlive else { return "session stopped" }
        MontanaPacketPump.shared.stop()
        MontanaXrayBridge.stop()
        if let err = MontanaXrayBridge.run(cfgStr) {
            ExtLog.write("engine raise (\(why)) failed: \(err)")
            return err
        }
        guard lifetime.isAlive else { MontanaXrayBridge.stop(); return "session stopped" }
        engineConfig = cfgStr
        guard MontanaPacketPump.shared.start(socksHost: "127.0.0.1", socksPort: socksPort) else {
            MontanaXrayBridge.stop(); return "packet pump did not start"
        }
        ExtLog.write("engine raised (\(why))")
        return nil
    }

    /// Every ten seconds, on the engine's line: the pump's counters against the last sample.
    private func startLifeWatch() {
        let t = DispatchSource.makeTimerSource(queue: engineLine)
        t.schedule(deadline: .now() + Self.lifeSample, repeating: Self.lifeSample)
        t.setEventHandler { [weak self] in self?.judgeLife() }
        t.resume(); lifeTimer = t
    }

    /// Silence is bytes out and none in, for twenty seconds; idleness (nothing asked out) is not silence, and a
    /// single byte in ends it. A silent upstream is raised anew, no sooner than the backoff allows.
    private func judgeLife() {
        guard lifetime.isAlive else { return }
        defer { countLife() }
        // One reading of the pump serves both judges: the dead session's first, then the silence watch below.
        let s = MontanaPacketPump.shared.rawStats()
        let now = Date()
        let sample = recovering ? nil : lifeLast.map { (dtx: s.txb - $0.txb, drx: s.rxb - $0.rxb) }
        if judgeDeath(now: now, sample: sample) { return }
        if recovering { recoverUpstream(); return }
        guard phonePathUp else {
            lifeLast = nil; lifeSilentSince = nil
            recovering = true; reasserting = true
            return
        }
        guard let prev = lifeLast else { lifeLast = (s.txb, s.rxb, now); return }
        lifeLast = (s.txb, s.rxb, now)
        let dtx = s.txb - prev.txb, drx = s.rxb - prev.rxb
        if drx > Self.lifeInFloor {
            lifeInAfterRaise = true
            if lifeSilentSince != nil || lifeRaiseStep != 30 {
                ExtLog.write("upstream alive: in=\(drx / 1024)KB out=\(dtx / 1024)KB in the last \(Int(Self.lifeSample))s raised=\(lifeRaises)")
            }
            lifeSilentSince = nil; lifeRaiseStep = 30
            return
        }
        guard dtx >= Self.lifeOutFloor else { return }   // nothing asked to go out: idleness, not silence
        if lifeSilentSince == nil { lifeSilentSince = prev.at }
        guard let since = lifeSilentSince else { return }
        let silent = now.timeIntervalSince(since)
        guard silent >= Self.lifeSilentAfter, now >= lifeNextRaise, let cfg = engineConfig else { return }
        // A failed restart enters recovery without releasing the tunnel routes.
        if lifeRaises >= 1, !lifeInAfterRaise, phonePathUp {
            yieldDeadUpstream(out: dtx, inb: drx, silent: Int(silent), why: "silent after a raise")
            return
        }
        lifeInAfterRaise = false
        lifeRaises += 1
        lifeNextRaise = now.addingTimeInterval(lifeRaiseStep)
        ExtLog.write("upstream silent: out=\(dtx / 1024)KB in=\(drx / 1024)KB, \(Int(silent))s without a byte in -- the engine is raised anew (\(lifeRaises)), the next no sooner than \(Int(lifeRaiseStep))s")
        lifeRaiseStep = min(300, lifeRaiseStep * 2)
        if raiseEngine(cfg, why: "silent upstream") != nil {
            recovering = true; reasserting = true
        }
        lifeLast = nil          // the pump's counters start over with it; the next sample only records
        lifeSilentSince = nil   // judged afresh after the raise
    }

    /// The life watch's word on this beat, counted (MTTunnelAlive): alive is the session standing on the phone's own network, out of
    /// recovery and not released, whose upstream brought bytes back since the beat before -- the proof of life. An idle tunnel and a
    /// tunnel to a dead server look the same from inside (MTTunnelDeath), so a stretch without bytes back proves nothing and counts
    /// nothing beyond the beat it began; after a stop the open stretch closes.
    private var livingRx = 0
    private func countLife() {
        let rx = MontanaPacketPump.shared.rawStats().rxb
        let proof = Self.lifeInFloor < rx - livingRx
        livingRx = rx
        let alive = [lifetime.isAlive, phonePathUp, !recovering, !releasing, proof].allSatisfy { held in held }
        living.judge(alive: alive, now: MTTunnelAlive.clock())
        UserDefaults.standard.set(living.total, forKey: MTTunnelAlive.totalKey)
    }

    /// The dead session's judge (MTTunnelDeath), on the engine's line: true when the session was restarted or released.
    /// The app's witness counts no further back than this session: a block carried over a restart is judged afresh.
    private func judgeDeath(now: Date, sample: (dtx: Int, drx: Int)?) -> Bool {
        guard !releasing else { return true }
        let reported = appBlocked.flatMap { now.timeIntervalSince($0.at) <= Self.witnessFresh ? $0.seconds : nil } ?? 0
        let witness = min(reported, max(0, Int(now.timeIntervalSince(sessionStart))))
        let store = UserDefaults.standard
        let verdict = death.judge(now: now.timeIntervalSince1970, phonePath: phonePathUp,
                                  bytesIn: Self.lifeInFloor < (sample?.drx ?? 0),
                                  bytesOut: Self.lifeOutFloor <= (sample?.dtx ?? 0),
                                  blocked: TimeInterval(witness),
                                  lastBlockedRestart: store.object(forKey: Self.blockedRestartKey) as? Double)
        switch verdict {
        case .alive:
            return false
        case .restart:
            store.set(now.timeIntervalSince1970, forKey: Self.blockedRestartKey)
            appBlocked = nil
            ExtLog.write("the system carries nothing into the tunnel: the app's path unsatisfied for \(witness)s with the phone's own network up -- the session restarts once")
            cancelTunnelWithError(NSError(domain: "montana.tunnel", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Restart: the system carried nothing into the tunnel"]))
            return true
        case .release(let why):
            releaseDeadSession(why: why, witness: witness)
            return true
        }
    }

    /// THE DEAD SESSION LETS THE PHONE GO (the author's word 29.09: «let a dead session release itself»). The reconnect is
    /// lifted first -- or the system would raise the same dead session at once -- and then the session ends with its reason,
    /// which the app says to the person under the switch. The phone is back on its own network; the VPN stays off until the
    /// person turns it on again.
    private func releaseDeadSession(why: String, witness: Int) {
        guard lifetime.isAlive, !releasing else { return }
        releasing = true
        let run = lifetime
        let silent = death.silentSince.map { Int(Date().timeIntervalSince1970 - $0) } ?? 0
        ExtLog.write("session dead (\(why)): silent=\(silent)s blocked=\(witness)s -- the reconnect is lifted and the phone released")
        ExtSession.note("dead=\(why)")
        // The moment rides the lift's own save (ExtReconnect.deadKey): the app reads it as this tunnel's verdict, at the fall or
        // at its next return, and the VPN wall's road decides what rises under the permitted list (MTVPNWhitelistRoad).
        ExtReconnect.lift(dead: Date().timeIntervalSince1970) { [weak self] in
            guard let self, run.isAlive else { return }
            self.cancelTunnelWithError(NSError(domain: "montana.tunnel", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "The VPN carried nothing: VPN off"]))
        }
    }

    private func engineDeadline() -> MTTunnelLifetime {
        let run = lifetime
        let deadline = MTTunnelLifetime { [weak self] error in
            guard let error, run.isAlive else { return }
            run.stop()
            ExtLog.write("engine operation timed out; requesting a system restart")
            self?.cancelTunnelWithError(error)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 45) {
            deadline.finish(NSError(domain: "montana.tunnel", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Engine recovery timed out"]))
        }
        return deadline
    }

    private var phonePathUp: Bool { defaultPath?.status == .satisfied }

    private func yieldDeadUpstream(out: Int, inb: Int, silent: Int, why: String) {
        guard lifetime.isAlive else { return }
        ExtLog.write("upstream unavailable: out=\(out / 1024)KB in=\(inb / 1024)KB silent=\(silent)s why=\(why); keeping tunnel routes")
        recovering = true
        reasserting = true
        recoverUpstream()
    }

    // One probe at a time, after closing the failed engine: two Go instances must not share the
    // extension's memory budget. A successful HTTP exchange THROUGH the outbound admits a candidate.
    // The tunnel interface and its routes stay installed throughout this operation.
    private func recoverUpstream() {
        guard lifetime.isAlive, phonePathUp, retry.ready(at: ProcessInfo.processInfo.systemUptime) else { return }
        let deadline = engineDeadline()
        defer { deadline.finish(nil) }
        MontanaPacketPump.shared.stop()
        MontanaXrayBridge.stop()
        guard !candidates.isEmpty else { retry.failed(at: ProcessInfo.processInfo.systemUptime); return }
        let next = (candidateIndex + 1) % candidates.count
        candidateIndex = next
        let candidate = candidates[next]
        guard let config = Self.fullConfigString(candidate.outbound, socksPort: socksPort) else {
            retry.failed(at: ProcessInfo.processInfo.systemUptime); return
        }
        recoveryAttempts += 1
        let delay = MontanaXrayBridge.measure(config)
        guard lifetime.isAlive else { return } // a manual OFF outranks a probe that finished late
        guard let delay, raiseEngine(config, why: "verified fallback") == nil else {
            if recoveryAttempts >= candidates.count {
                recoveryAttempts = 0
                retry.failed(at: ProcessInfo.processInfo.systemUptime)
            } else {
                engineLine.async { [weak self] in self?.recoverUpstream() }
            }
            ExtLog.write("recovery waiting: candidate=\(next) failures=\(retry.failures)")
            return
        }
        retry.reset()
        recoveryAttempts = 0
        runningRow = candidate.row
        recovering = false
        reasserting = false
        lifeLast = nil; lifeSilentSince = nil; lifeInAfterRaise = false; death.reset()
        lifeNextRaise = Date().addingTimeInterval(30)
        let run = lifetime
        let replacing = profileRow
        ExtReconnect.remember(candidate, replacing: replacing, run: run) { [weak self] saved in
            guard let self, saved else { return }
            self.engineLine.async {
                if run.isAlive, self.profileRow == replacing { self.profileRow = candidate.row }
            }
        }
        ExtLog.write("recovery connected: candidate=\(next) delay_ms=\(delay)")
    }

    // Memory measurement for the long-run soak test: the process footprint iOS actually terminates on
    // (Mach phys_footprint) plus the Go runtime's heap and goroutine count, once every 30 s. Measurement
    // only — nothing here tunes memory, and there is no memory-pressure source (that one flooded the log).
    static func parseNumber(_ s: String, key: String) -> Int {
        guard let r = s.range(of: key) else { return 0 }
        let tail = s[r.upperBound...].prefix { $0.isNumber }
        return Int(tail) ?? 0
    }
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / (1024 * 1024) : -1
    }
    // The heartbeat is a minute apart, and a load spike lives seconds — so a sample can read healthy
    // while the peak that killed the session went unrecorded. The kernel keeps the high-water mark itself
    // (its own ledger, not a sample of ours: the variable that stood here was overwritten with the very
    // sample it was meant to exceed and never written, 24.09), and beside it how much is left before the
    // limit the system kills at. Both ride every heartbeat.
    static func memoryLedgerMB() -> (now: Double, peak: Double, left: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (-1, -1, -1) }
        let mb = 1024.0 * 1024.0
        return (Double(info.phys_footprint) / mb, Double(info.ledger_phys_footprint_peak) / mb,
                Double(info.limit_bytes_remaining) / mb)
    }
    private var lastNumGC: Int = 0
    private var sessionStart = Date()
    private var memPressure: DispatchSourceMemoryPressure?

    // The system announces that it is about to reclaim. That announcement is the last thing a process
    // about to be terminated ever receives, and it arrives before the end rather than after — which is
    // more than any sampler, however fast, can promise.
    private func startMemoryPressureWatch() {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical],
                                                          queue: DispatchQueue(label: "mt.ext.press"))
        src.setEventHandler { [weak self] in
            let lvl = src.data.contains(.critical) ? "CRITICAL" : "warning"
            if lvl == "CRITICAL" { ExtSession.note("press=critical") }   // a death in the next seconds is named for it
            ExtLog.write(String(format: "MEMORY PRESSURE %@ footprint=%.1fMB %@",
                                lvl, Self.memoryFootprintMB(), MontanaXrayBridge.memStats()))
            // A MEMORY-CRITICAL WARNING UNDER A SILENT UPSTREAM IS THE DEAD ROAD'S VERDICT, said before the system says it
            // with a kill (25.09, the iPhone 17: forty such warnings and fourteen kills, every session under forty seconds --
            // the silence watchdog never got its twenty). Bytes of this engine's life: nothing in, plenty out.
            if lvl == "CRITICAL", let self, self.phonePathUp, Date().timeIntervalSince(self.sessionStart) >= 5 {
                let s = MontanaPacketPump.shared.rawStats()
                if s.rxb <= Self.lifeInFloor, s.txb >= Self.lifeOutFloor {
                    let age = Int(Date().timeIntervalSince(self.sessionStart))
                    self.engineLine.async { self.yieldDeadUpstream(out: s.txb, inb: s.rxb, silent: age, why: "memory critical, nothing in") }
                }
            }
            // The announcement is the last thing a process about to be taken ever hears, so it is
            // answered rather than only written down. The runtime hands freed pages back lazily and the
            // system counts the footprint, not the live heap: on T1 (22.09, 1872) the heap in use fell
            // to 9 MB while the runtime still held 45 MB and the process was killed twice in twenty
            // minutes. Here the pages go back at once, which is the one thing that moves the number the
            // system is looking at.
            let freed = MontanaXrayBridge.freeMemory()
            ExtLog.write(String(format: "MEMORY RELEASED after %@ footprint=%.1fMB %@", lvl, Self.memoryFootprintMB(), freed))
        }
        src.resume(); memPressure = src
    }

    private func startMemoryWatch() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mt.ext.mem"))
        // Once a minute. Half-second sampling was there to catch a death that lives seconds — the storm
        // that took a session from 82 connections to 388 in three, invisible between two minute-apart
        // readings. That question is answered and the build now runs for days, so the trace is paced for
        // the long view instead: two files of eighteen thousand lines cover weeks at this rate rather
        // than the seven to thirteen hours they held before, which was shorter than the sessions being
        // measured. Nothing about a sudden death goes unrecorded even so — the memory-pressure source
        // writes the moment it fires, and it is not sampled.
        t.schedule(deadline: .now() + 60, repeating: 60)
        t.setEventHandler {
            let mem = Self.memoryLedgerMB()
            // Bytes through the pump, on every line. A tunnel can hold steady memory and carry nothing
            // at all — that failure looked healthier than a working one in the log until this was here.
            let stats = "\(MontanaPacketPump.shared.traffic()) \(MontanaXrayBridge.memStats())"
            // Collections per interval, not the running total: the rate is what says whether the runtime
            // is working or straining, and a total says nothing without arithmetic.
            let gc = Self.parseNumber(stats, key: "numGC=")
            let gcRate = self.lastNumGC == 0 ? 0 : max(0, gc - self.lastNumGC)   // per minute
            self.lastNumGC = gc
            let up = Int(Date().timeIntervalSince(self.sessionStart))
            let line = String(format: "up=%dh%02dm%02ds footprint=%.1fMB peak=%.1fMB left=%.1fMB gc=%d %@",
                              up / 3600, (up % 3600) / 60, up % 60, mem.now, mem.peak, mem.left, gcRate, stats)
            ExtLog.write(line)
            // The only file this process touches while running: 80 bytes overwritten once a minute.
            // A termination gives no chance to flush anything, so this marker is the sole way the next
            // start can say how the previous session died — it earns its keep.
            ExtSession.beat(line)
        }
        t.resume(); memTimer = t
    }

    static func stopReasonName(_ r: NEProviderStopReason) -> String {
        switch r {
        case .none: return "none"
        case .userInitiated: return "userInitiated (MANUAL)"
        case .providerFailed: return "providerFailed"
        case .noNetworkAvailable: return "noNetworkAvailable"
        case .unrecoverableNetworkChange: return "unrecoverableNetworkChange"
        case .providerDisabled: return "providerDisabled"
        case .authenticationCanceled: return "authenticationCanceled"
        case .configurationFailed: return "configurationFailed"
        case .idleTimeout: return "idleTimeout"
        case .configurationDisabled: return "configurationDisabled"
        case .configurationRemoved: return "configurationRemoved"
        case .superceded: return "superceded"
        case .userLogout: return "userLogout"
        case .userSwitch: return "userSwitch"
        case .connectionFailed: return "connectionFailed"
        case .sleep: return "sleep"
        case .appUpdate: return "appUpdate"
        case .internalError: return "internalError"
        @unknown default: return "unknown(\(r.rawValue))"
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        lifetime.stop()
        pathObservation = nil
        os_log("Montana tunnel stop", log: log, type: .info)
        memTimer?.cancel(); memTimer = nil
        lifeTimer?.cancel(); lifeTimer = nil
        engineLine.async { self.countLife() }   // the living stretch still open is counted at the stop
        ExtSession.clear()
        ExtLog.write("stopTunnel reason=\(reason.rawValue) \(Self.stopReasonName(reason)) footprint=\(String(format: "%.1f", Self.memoryFootprintMB()))MB"); ExtLog.write("stopTunnel"); NSLog("[montana-vpn-ext] stopTunnel -> instant")
        // Return to iOS at once so the toggle flips off at once. Tearing Xray/tun2socks down here
        // blocked for ~25s (iOS grace window) which hung disconnect and made the system toggle need a
        // second tap. The process is killed right after the handler, so the teardown is best-effort async.
        // A stop by the person's hand waits for one thing first -- the reconnect lifted -- or the system would
        // raise at once what the person has just switched off (ExtReconnect).
        let finish = {
            ExtLog.write("── session end: \(Self.stopReasonName(reason)) ──")
            completionHandler()
            self.engineLine.async {
                MontanaPacketPump.shared.stop()
                MontanaXrayBridge.stop()
            }
        }
        // AN UPDATE OF THE APP LIFTS IT TOO (the author's word 28.09, T1 at 17:25: «after a reinstall you give an error -- the VPN
        // fails after it; do not try to raise it»). The system stops this tunnel to replace it; with the reconnect standing it
        // raises the new one at once, and the new one may not start before the system has verified the new app -- a
        // verification that needs the network which this very tunnel holds (includeAllNetworks): «Unable to verify app ...
        // requires a network connection». Lifted here, the phone comes back on its own road; the person turns the VPN on.
        guard reason == .userInitiated || reason == .configurationDisabled || reason == .configurationRemoved
                || reason == .providerDisabled || reason == .appUpdate else { finish(); return }
        // A STOP BY THE APP'S RECOVERY IS NOT THE PERSON'S OFF (29.09): the recovery marks its stop in the tunnel's own
        // configuration a moment before it stops; the lift below reads the mark and keeps the reconnect standing.
        ExtReconnect.lift(then: finish)
    }
}

// Preference operations run in one async line. A stop invalidates its lifetime synchronously,
// before joining that line, and waits for the saved OFF before completing the system's stop.
@MainActor
enum ExtReconnect {
    private static var tail: Task<Void, Never>?
    private static var said = "none"

    private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { await previous?.value; await work() }
    }

    nonisolated static func arm(_ run: MTTunnelLifetime) {
        Task { @MainActor in
            enqueue {
                guard run.isAlive else { return }
                said = await write(true, run: run)
                ExtLog.write("reconnect: " + said)
            }
        }
    }

    /// THE DEAD MARK (30.09, the author's word: the VPN wall must tell when it stands under the white lists and raise a live node
    /// of the wall by itself). A session this tunnel released as dead leaves its moment in its own configuration, in the very save
    /// that lifts the reconnect; the app reads it, at the fall or at its next return, as the tunnel's own verdict and never a
    /// guess. The next session's arm takes it away, so a later off by the person never reads as a death.
    static let deadKey = "deadAt"

    nonisolated static func lift(dead: Double? = nil, then done: @escaping () -> Void) {
        Task { @MainActor in
            enqueue {
                said = await write(false, run: nil, dead: dead)
                ExtLog.write("reconnect: " + said)
                done()
            }
        }
    }

    nonisolated static func answer(_ reply: @escaping (String) -> Void) {
        Task { @MainActor in enqueue { reply(said) } }
    }

    nonisolated static func remember(_ candidate: MTTunnelCandidate, replacing row: String,
                                     run: MTTunnelLifetime, done: @escaping (Bool) -> Void) {
        ExtLog.write("automatic server switch suppressed")
        done(false)
    }

    private static func manager() async throws -> NETunnelProviderManager? {
        try await NETunnelProviderManager.loadAllFromPreferences().first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == MTTunnelIds.extensionBundleId
        }
    }

    private static func write(_ on: Bool, run: MTTunnelLifetime?, dead: Double? = nil) async -> String {
        for attempt in 0..<3 {
            do {
                guard let manager = try await manager() else { return "refused missing configuration" }
                if on {
                    guard run?.isAlive == true, manager.isEnabled,
                          manager.connection.status != .disconnecting else { return "skipped stopped session" }
                    guard !(manager.onDemandRules ?? []).isEmpty else { return "refused missing rule" }
                }
                let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
                // The arm takes a standing dead mark away and a dead release writes one: either moves the profile even when the
                // reconnect already reads as asked.
                let marks = on ? proto?.providerConfiguration?[deadKey] != nil : dead != nil
                if manager.isOnDemandEnabled == on, !marks { return on ? "armed" : "lifted" }
                // THE RECOVERY'S OWN STOP KEEPS THE RECONNECT (29.09, T1 28.09: nine stops by the app's recovery in a day,
                // each read as the person's off, each lifting the reconnect -- and the recovery could not raise what it had
                // stopped, since it asks for a standing reconnect; the tunnel lay until a finger). The app writes the moment
                // of its stop into this configuration (MTVPNSystemControl.markStop); a mark under ninety seconds old is the
                // recovery's hand, and the reconnect stands for the system to raise the tunnel anew. No entitlement is
                // needed: both sides read and write this configuration already.
                if !on, let at = proto?.providerConfiguration?["recoveryStop"] as? Double,
                   Date().timeIntervalSince1970 - at < 90 {
                    return "kept for the recovery"
                }
                if marks, let proto {
                    var config = proto.providerConfiguration ?? [:]
                    if on { config[deadKey] = nil } else if let dead { config[deadKey] = dead }
                    proto.providerConfiguration = config
                    manager.protocolConfiguration = proto
                }
                manager.isOnDemandEnabled = on
                try await manager.saveToPreferences()
                if marks { ExtLog.write(on ? "dead mark: taken away by this session" : "dead mark: written for the app") }
                return on ? "armed" : "lifted"
            } catch {
                let e = error as NSError
                if attempt == 2 { return "refused preferences \(e.domain)#\(e.code)" }
            }
        }
        return "refused preferences"
    }
}

// Thin indirection over the MontanaXray gomobile module so the extension compiles before the
// xcframework is linked. Once MontanaXray.xcframework is embedded, these forward to MontanaxrayRun/Stop.
enum MontanaXrayBridge {
    /// Several outbounds at once through one engine instance (MeasureMany / MeasureUDPMany in the wrapper): the engine's
    /// own rows, [{"ms":71},{"ms":-1,"err":"..."}], in the outbounds' order; a batch that failed as a whole fails every row.
    static func measureMany(_ outbounds: [[String: Any]], stun: String, width: Int) -> [[String: Any]] {
        let failed: (String) -> [[String: Any]] = { word in outbounds.map { _ in ["ms": -1, "err": word] } }
        guard let d = try? JSONSerialization.data(withJSONObject: outbounds), let json = String(data: d, encoding: .utf8) else { return failed("bad outbound") }
        #if canImport(MontanaXray)
        var error: NSError?
        let text = stun.isEmpty ? MontanaxrayMeasureMany(json, "", width, "", 0, &error)
                                : MontanaxrayMeasureUDPMany(json, stun, width, "", 0, &error)
        if let error { return failed(error.localizedDescription) }
        guard let td = text.data(using: .utf8), let rows = try? JSONSerialization.jsonObject(with: td) as? [[String: Any]],
              rows.count == outbounds.count else { return failed("no answer") }
        return rows
        #else
        return failed("engine not linked")
        #endif
    }

    static func measure(_ config: String, stun: String = "") -> Int? {
        #if canImport(MontanaXray)
        var delay: Int64 = -1
        var error: NSError?
        // Provider sockets already use the physical path; no global interface-binding override.
        let ok = stun.isEmpty ? MontanaxrayMeasureDelay(config, "", "", &delay, &error)
                             : MontanaxrayMeasureUDP(config, stun, "", &delay, &error)
        guard ok, delay >= 0 else { return nil }
        return Int(delay)
        #else
        return nil
        #endif
    }

    static func run(_ config: String) -> String? {
        #if canImport(MontanaXray)
        var err: NSError?
        MontanaxrayRun(config, &err)   // gomobile-exported: func Run(config string) error
        return err?.localizedDescription
        #else
        return "MontanaXray engine not linked (build the xcframework)"
        #endif
    }
    static func stop() {
        #if canImport(MontanaXray)
        MontanaxrayStop()
        #endif
    }
    static func memStats() -> String {
        #if canImport(MontanaXray)
        return MontanaxrayMemStats()
        #else
        return "go{n/a}"
        #endif
    }
    /// Hand every page the runtime no longer needs back to the system. Slow by design (a full
    /// collection and a scavenge) and therefore called only when the system says it is about to reclaim.
    static func freeMemory() -> String {
        #if canImport(MontanaXray)
        return MontanaxrayFreeMemory()
        #else
        return "go{n/a}"
        #endif
    }
}
