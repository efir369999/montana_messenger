import Foundation
import CryptoKit

/// The one place in this app that opens a diagnostic file and writes a line to it.
///
/// There were four. Three of them appended to the same telemetry.log — one through a private queue,
/// two through none at all — and each built its own ISO formatter on every call. Two writers that both
/// seek to the end and then write can land on the same offset, and one line silently replaces the
/// other: not interleaved output, a lost record, and lost precisely under the load worth recording.
/// Only one of the three participated in trimming, which is how a file governed by a "48 hours" policy
/// reached 2.4 MB.
///
/// So: one serial queue, one formatter, one rotation. Channels differ in their file and their budget,
/// not in their mechanism — a channel that carries its own line shape supplies everything after the
/// timestamp and nothing else.

// Journals do not travel into the backup. They hold the most telling thing this client has:
// window labels, neighbour and node endpoints, routes and the moment of every sending. A phone backup
// is kept by the operating system vendor, and landing there cancels exactly what the protocol closes.
private func mtExcludeFromBackup(_ url: URL) {
    var u = url
    var rv = URLResourceValues()
    rv.isExcludedFromBackup = true
    try? u.setResourceValues(rv)
}

/// The journal must be readable by the SHIPPING loop while the phone lies LOCKED: with the
/// default file protection a locked phone cannot open its own diagnostics, the loop reported
/// «passes=0» without one refusal line, and the node saw silence for hours (measured 27.08,
/// T2 on the desk). The journals are addressless by construction — no protection is lost.
private func mtUnprotect(_ url: URL) {
    try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
}
enum MontanaLog {
    enum Channel: CaseIterable {
        case telemetry, trace
        /// THE MEASURES KEEP A FILE OF THEIR OWN (the author's word 21659: «do not allow the loss of the measures»; OZ 1 p.1.1.6): the
        /// trace filled its 512 KB in four to eight minutes of a person's work on T1 (2392, 13.11.2026) and the shipper takes each
        /// finished file off the phone -- a motion measured ten minutes ago was no longer there to read. The screen's measures
        /// (MontanaTrace.measures) are a few kilobytes an hour: in their own file they stand for days, and ship as the trace does.
        case measure
        #if !MONTANA_MESSENGER
        case vpn   // the VPN's diary, the Protocol's alone (decision 651 = a)
        #endif

        var file: String {
            switch self {
            case .telemetry: return "telemetry.log"
            case .trace:     return "trace.log"
            case .measure:   return "measure.log"
            #if !MONTANA_MESSENGER
            case .vpn:       return "vpn.log"
            #endif
            }
        }
        /// Half the budget: each channel keeps a current file and a previous one, so rotating here caps
        /// the pair at twice this and never more.
        var rotateAtBytes: UInt64 {
            switch self {
            case .telemetry: return 512 * 1024
            case .trace:     return 512 * 1024
            case .measure:   return 512 * 1024
            #if !MONTANA_MESSENGER
            case .vpn:       return 256 * 1024
            #endif
            }
        }
        /// The shipper's two marks of the channel -- how far it has sent, and the birth of the file that offset measures -- named
        /// here, by the channels' one owner (the author's word 21679): the shipper kept a list of its own of the files and the marks.
        var ship: (mark: String, birth: String) {
            switch self {
            case .telemetry: return ("diagWmTele", "diagGenTele")
            case .trace:     return ("diagWmTrace", "diagGenTrace")
            case .measure:   return ("diagWmMeasure", "diagGenMeasure")
            #if !MONTANA_MESSENGER
            case .vpn:       return ("diagWmVpn", "diagGenVpn")
            #endif
            }
        }
    }

    private static let q = DispatchQueue(label: "montana.log", qos: .utility)
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana").appendingPathComponent("Diagnostics")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        mtExcludeFromBackup(d)
        mtUnprotect(d)
        for ch in Channel.allCases {
            mtUnprotect(d.appendingPathComponent(ch.file))
            mtUnprotect(d.appendingPathComponent(ch.file + ".prev"))
        }
        return d
    }
    static func url(_ ch: Channel) -> URL { dir.appendingPathComponent(ch.file) }
    /// GENERATIONS ARE KEPT UNTIL SHIPPED (25.09). One finished file stood behind the live one, and a day on the
    /// road rotated it many times between two shipments: T1's transport diary reached the store from 20:08Z on the
    /// 24th and from 16:08Z on the 25th, the 15 Pro Max's from 14:09Z -- the hours that held the calls and the
    /// deaths were gone before the shipper's turn, and the diary said nothing of the loss. A rotation now shifts the
    /// finished files up one place: `.prev` is the newest, `.prev.1` the one before it, up to `.prev.keep`; the
    /// shipper (MontanaDiagShip) deletes each one it has sent whole. Only when every place is taken is the oldest
    /// dropped -- and the drop is written into the telemetry as a fact, so a hole in the diary is never silent.
    /// TWENTY-FOUR PLACES (the author's word 17968, 09.11.2026: the diary is critical, no scenario loses it). Six held three
    /// megabytes a channel -- less than one day of T1's trace (4.2 MB on 09.11) when the node refuses; twenty-four hold about
    /// three such days, twelve megabytes a channel at most, and the loss below stays the last fuse, written as a fact.
    static let keep = 24
    private static func prevURL(_ ch: Channel, generation g: Int = 0) -> URL {
        dir.appendingPathComponent(ch.file + (g == 0 ? ".prev" : ".prev." + String(g)))
    }

    /// Called after the telemetry channel rotates. The crash handler holds an open descriptor on that
    /// file so it can write from inside a dying process, and a rename carries the descriptor along with
    /// the inode — the next rotation would then delete the file it points at and crash records would go
    /// nowhere. Rotation stays one mechanism for every channel; the descriptor follows it.
    static var onTelemetryRotate: (() -> Void)?
    /// THE TRACE OF A CALL IS NOT ROTATED UNDER THE CALL (29.09): a ring of 512 KB held sixteen minutes on T1, and a call's
    /// own lines were gone before the call was over. The hold is the app's word (an extension keeps none) and ends at four
    /// rings: a call that talks for an hour still keeps the journal bounded.
    static var holdRotation: ((Channel) -> Bool)?

    /// The telemetry channel's entry point, and the only name the app and its extensions use for it.
    /// It lives here rather than on MontanaTelemetry because that facility is compiled into the app
    /// target alone — which is exactly how a second logger came to exist for the extensions to call.
    static func event(_ msg: String, numbers: [String: Int64] = [:]) { write(.telemetry, " " + msg, numbers: numbers) }

    /// Typed counters cannot contain private strings. Keep them numeric on disk: the generic
    /// hex-name filter also matches a thirteen-digit UTC timestamp. All text still passes hide.
    static func body(_ body: String, numbers: [String: Int64]) -> String {
        let metrics = numbers.sorted { $0.key < $1.key }.filter {
            !$0.key.isEmpty && $0.key.utf8.allSatisfy { $0 == 95 || (97...122).contains($0) }
        }.map { " \($0.key)=\($0.value)" }.joined()
        return hide(body) + metrics
    }

    /// The journal's own time for a record written past the queue (the crash handler): the same
    /// formatter, so a filter by the hour finds it like any other line.
    static func stamp(_ d: Date = Date()) -> String { iso.string(from: d) }

    // -- WHAT IS NOT IN THE JOURNAL AT ALL -------------------------------------
    //
    // A conversation name and a network address are not cleaned before sending -- they DO NOT GET HERE.
    // The difference is not in tidiness but in construction: while a trace lay on disk as is, it lay on
    // the phone whole, and any cleaning error at export became a leak. There is nothing to clean where
    // there was nothing to write.
    //
    // Instead of an address a salted label is written: the same address gives the same label, so a line
    // can still be read ("the same peer as three lines above") while it cannot be tied to a person
    // either on the node or on the phone itself. The salt lives in the device keychain, shared by the
    // app and both extensions, and goes nowhere: without it the label is irreversible even to someone who knows the address.
    //
    // Numbers stay numbers: codes, durations, counters and port numbers say nothing about a person and
    // are needed for analysis -- the rule does not touch them.
    private static let saltKey = "diagSalt"
    private static var saltCache: String?
    private static var salt: String {
        if let s = saltCache { return s }
        if let d = MontanaKeychain.get(saltKey), let s = String(data: d, encoding: .utf8), !s.isEmpty {
            saltCache = s; return s
        }
        let s = UUID().uuidString + UUID().uuidString   // LOCAL-RANDOM-OK: the anonymising salt, not a key
        MontanaKeychain.set(saltKey, Data(s.utf8)); saltCache = s
        return s
    }

    // The author's rule 26.08: an address leaves NO trace at all — not even a salted tag.
    // What debugging needs is the FACT of the family (did the path use v4 or v6), never the
    // number. Correspondent names keep their per-device tag: without one, two peers on one
    // device are indistinguishable; cross-device stitching rides the letter id instead.
    private static let hexRe = try? NSRegularExpression(pattern: "[0-9a-f]{10,}")
    private static let ip4Re = try? NSRegularExpression(pattern: "\\b\\d{1,3}(?:\\.\\d{1,3}){3}\\b")
    // A candidate, not a verdict: the compressed form (2a00:…:c07::8b, fe80::1, ::1) defeats any
    // fixed group-count pattern — the draft test caught exactly that, a leaked "::8b" tail. So the
    // pattern grabs every run of hex-and-colons and the code keeps only runs with two colons or
    // more; a correspondent tag (a:xxxxxx, one colon) never qualifies.
    private static let ip6Re = try? NSRegularExpression(pattern: "[0-9a-fA-F:]{3,}")

    /// The line as it will lie on disk. The door is open to checking: a promise to a person must be
    /// measurable, or it is not a promise.
    /// THE PATTERNS ARE ASKED ONLY WHERE THEY COULD MATCH (the critic 22.09). Three regular
    /// expressions walked EVERY line of the diary, and a fourth cost -- a digest and thirty-two
    /// formatted bytes for each hex run -- rode on top. Measured on this machine: 14 us for a line
    /// without a name, 98 us for one carrying a key and a letter name; a phone pays two to three
    /// times that, on the thread that called, which is the main thread for everything the screen
    /// writes. Six hundred thousand lines crossed the fleet in thirty hours. An address pattern
    /// cannot match a line that holds no colon, and an IPv4 pattern cannot match one with no dot:
    /// the cheap question is asked first, and the names already seen are remembered instead of being
    /// hashed again -- the same references, keys and letter names repeat all day long.
    private static var tagCache: [String: String] = [:]
    private static let tagLock = NSLock()
    static func hide(_ line: String) -> String {
        var out = line
        // Addresses first: an IPv6 literal is hex-with-colons, and the name pattern must never
        // see its fragments. Both families collapse to the family fact alone.
        if line.contains(":"), let re = ip6Re {
            let matches = re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
            for m in matches {
                guard let r = Range(m.range, in: out) else { continue }
                let run = out[r]
                guard run.filter({ $0 == ":" }).count >= 2, run.contains(where: { $0 != ":" })
                else { continue }
                // A time of day (17:31:57) is hex-with-colons too; an address is told apart by a
                // hex LETTER or by the :: compression. All-digit runs without :: are clocks.
                guard run.contains("::") || run.lowercased().contains(where: { "abcdef".contains($0) })
                else { continue }
                out.replaceSubrange(r, with: "[ip6]")
            }
        }
        if out.contains("."), let re = ip4Re {
            let matches = re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
            for m in matches {
                guard let r = Range(m.range, in: out) else { continue }
                out.replaceSubrange(r, with: "[ip4]")
            }
        }
        if let re = hexRe {
            let matches = re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
            for m in matches {
                guard let r = Range(m.range, in: out) else { continue }
                let token = String(out[r])
                tagLock.lock()
                var tag = tagCache[token]
                tagLock.unlock()
                if tag == nil {
                    // Three bytes ARE the six characters the tag is: the whole digest used to be
                    // formatted byte by byte and then cut down to six.
                    let digest = SHA256.hash(data: Data((salt + token).utf8))
                    tag = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
                    tagLock.lock()
                    if tagCache.count == 4096 { tagCache.removeAll(keepingCapacity: true) }   // a day's worth of names, then a fresh page
                    tagCache[token] = tag
                    tagLock.unlock()
                }
                out.replaceSubrange(r, with: "a:" + (tag ?? ""))
            }
        }
        return out
    }

    /// A SECRET IS NAMED IN THE DIARY BY ITS SALTED LABEL (24.09): a plan's link, whose host carries the panel's
    /// token for the person -- «update plan=TOKEN.PANEL» rode every diary to the node, because the name pattern
    /// above takes only lowercase hex and the token is mixed case. The same secret gives the same label on this
    /// phone, so one plan can still be followed from line to line; anywhere else the label says nothing.
    static func label(_ secret: String) -> String {
        let digest = SHA256.hash(data: Data((salt + secret).utf8))
        return "p:" + digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    /// `body` is everything after the timestamp, separator included: channels keep their own line shape
    /// (` [app] …` for the tunnel, `|elapsed|event|mid|kv` for the trace) while the timestamp, the
    /// queue and the file handling stay here.
    // An extension's journal lives in a container the app cannot read; every line it writes is
    // therefore ALSO appended to the shared keychain, and the app carries it into the common
    // journal on its next breath (launch, silent wake, foreground). Capped: the newest 64 KB win.
    private static let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")
    private static func bridgeToApp(_ line: String) {
        var d = MontanaKeychain.get("nseLog") ?? Data()
        d.append(Data(line.utf8))
        if d.count > 65_536 { d = d.suffix(65_536) }
        MontanaKeychain.set("nseLog", d)
    }

    /// Every line handed in so far is on disk when this returns: a process that leaves by its own word would
    /// otherwise take the queue's tail with it. MAIN-SAFE-SYNC: called once, by the install road's prepare, a moment
    /// before exit; the queue holds only file appends and never waits on the main thread -- the wait is the diary's tail.
    static func drain() { q.sync {} }
    static func write(_ ch: Channel, _ body: String, numbers: [String: Int64] = [:]) {
        let line = iso.string(from: Date()) + Self.body(body, numbers: numbers) + "\n"
        if isExtension { bridgeToApp(line) }
        q.async {
            let u = url(ch)
            guard let data = line.data(using: .utf8) else { return }
            var size = UInt64(data.count)
            if let h = try? FileHandle(forWritingTo: u) {
                defer { try? h.close() }
                // The offset returned by seeking to the end is the file's own length: rotation is
                // decided by the file rather than by a counter in this process, which starts at zero on
                // every launch and would never reach its threshold on a process that restarts often.
                size += (try? h.seekToEnd()) ?? 0
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: u)
            }
            MTDiskDoor.count("log:\(ch)", data.count)   // the diary's own bytes are named too (the disk door, 01.11)
            guard size >= ch.rotateAtBytes else { return }
            if size < 4 * ch.rotateAtBytes, holdRotation?(ch) == true { return }
            let fm = FileManager.default
            let prev = prevURL(ch)
            // The oldest place is freed first: a generation still standing there was never shipped, and its loss is a fact.
            let oldest = prevURL(ch, generation: keep)
            if let a = try? fm.attributesOfItem(atPath: oldest.path) {
                let lost = (a[.size] as? NSNumber)?.intValue ?? 0
                try? fm.removeItem(at: oldest)
                write(.telemetry, " DIARY dropped \(ch.file) generation=\(keep) bytes=\(lost) -- rotated out before it was shipped")
            }
            for g in stride(from: keep - 1, through: 1, by: -1) {
                try? fm.moveItem(at: prevURL(ch, generation: g), to: prevURL(ch, generation: g + 1))
            }
            try? fm.moveItem(at: prev, to: prevURL(ch, generation: 1))
            try? fm.moveItem(at: u, to: prev)
            if ch == .telemetry { onTelemetryRotate?() }
        }
    }
}

/// THE ONE DOOR OF THE DISK (the law of 01.11.2026, the author's word, link 13994: «every overrun is named»). T1 wrote 4.3 GB in
/// 1.7 hours on 2315 and no line named the writer -- it was laid on the history, which it was not. A file is written whole
/// through `write`, an append made by a handle of its own is told through `count`; the bytes are summed by the writer's name
/// for the hour. Past the hour's budget one line names the writers, the largest first, and the stack of the write that
/// crossed it; at the turn of the hour one line gives the hour's names beside the process's own count of written blocks
/// (getrusage, ru_oublock): what the names do not hold is the unnamed rest. tools/mt-main-door-check.py refuses a new write
/// past this door.
enum MTDiskDoor {
    static let hourBudget = 256 << 20
    private static let lock = NSLock()
    private static var hourAt = ProcessInfo.processInfo.systemUptime
    private static var named: [String: Int] = [:]
    private static var blocksAt = outBlocks()
    private static var spoke = false
    /// A file written whole, under its writer's name.
    @discardableResult
    static func write(_ data: Data, to url: URL, _ name: String, options: Data.WritingOptions = []) -> Bool {
        do { try data.write(to: url, options: options) } catch { return false }
        count(name, data.count)
        return true
    }
    /// Bytes appended to the end of a file that stands, under the writer's name (the person's time chain, S2a of APPS-API: its
    /// handle used to open past the door). False when the file would not open or take the bytes -- the caller decides whether a
    /// file is born; a file that stands is never written over here.
    @discardableResult
    static func append(_ data: Data, to url: URL, _ name: String) -> Bool {
        guard let f = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? f.close() }
        do { _ = try f.seekToEnd(); try f.write(contentsOf: data) } catch { return false }
        count(name, data.count)
        return true
    }
    /// Bytes written by a handle of the writer's own, under its name.
    static func count(_ name: String, _ bytes: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        var hour: String?, over: String?
        lock.lock()
        if 3600 <= now - hourAt {
            let blocks = outBlocks()
            hour = "DISK HOUR named=\(named.values.reduce(0, +)) out_blocks=\(blocks - blocksAt) top=\(top())"
            named = [:]; hourAt = now; spoke = false; blocksAt = blocks
        }
        named[name, default: 0] += bytes
        let total = named.values.reduce(0, +)
        if hourBudget < total, !spoke { spoke = true; over = "DISK OVER what=\(name) total=\(total) budget=\(hourBudget) top=\(top())" }
        lock.unlock()
        if let hour { MontanaLog.event(hour) }
        if let over { MontanaLog.event(over + " frames: " + Thread.callStackSymbols.prefix(12).map { String($0.prefix(90)) }.joined(separator: " < ")) }
    }
    /// The hour's writers, the largest first (under the lock).
    private static func top() -> String {
        named.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }
    private static func outBlocks() -> Int {
        var u = rusage()
        return getrusage(RUSAGE_SELF, &u) == 0 ? Int(u.ru_oublock) : 0
    }
}
