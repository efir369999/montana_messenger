import Foundation

/// Line format:  ISO8601|proc_ms|event|mid|k=v ... proc_ms — milliseconds since
/// process exec (monotonic; honest cold-start speed) mid     — message id when the
/// event belongs to a concrete message ("-" otherwise)
enum MontanaTrace {
    // Real process exec time (kinfo_proc) — captures dyld+runtime before our first Swift line.
    private static let procStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0 {
            let tv = info.kp_proc.p_starttime
            return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
        }
        return Date()
    }()
    private static let q = DispatchQueue(label: "montana.trace", qos: .utility)
    /// THE BOOKKEEPING OF THE DIARY IS A LOCK, NOT A QUEUE. Marking is called from every thread,
    /// the main one included; a hop onto a serial queue makes the caller wait for whatever that
    /// queue is doing. A dictionary update takes nanoseconds and needs a lock, not a queue.
    private static let bookLock = NSLock()
    private static var onceKeys = Set<String>()

    static var url: URL { MontanaLog.url(.trace) }

    private static let enabled = true

    /// The letter's name in the diary. A minted name is «t<ms>-<uuid>»: its first eight
    /// characters are a thousand-second bucket shared by every letter of a quarter-hour, so the
    /// diary printed one name for many letters (08.09: two letters to two people read as one).
    /// The last eight digits of the millisecond are unique within a day's file — the device
    /// mints milliseconds strictly monotonic. Any other name keeps its first eight characters.
    static func short(_ mid: String) -> String {
        // A receipt rides under its letter's name (ChatStore.receiptMid, 23.09): «r» and the letter's
        // own short name, or every receipt of a quarter-hour would print as one «rcpt-t17».
        if mid.hasPrefix("rcpt-") { return "r" + short(String(mid.dropFirst(5))) }
        if mid.hasPrefix("t"), let dash = mid.firstIndex(of: "-") {
            let digits = mid[mid.index(after: mid.startIndex)..<dash]
            if digits.count >= 8, digits.allSatisfy({ $0.isNumber }) { return String(digits.suffix(8)) }
        }
        return String(mid.prefix(8))
    }
    /// A birth millisecond in the diary, written as the letter born then is named there (short): its
    /// last eight digits. The whole thirteen are hidden by the diary as an address, and «upto=a:ec589d»
    /// (23.09) could not be matched with any letter.
    static func shortMs(_ ms: Int64) -> String { String(String(ms).suffix(8)) }

    static func mark(_ event: String, mid: String? = nil, _ kv: String = "") {
        guard enabled else { return }
        let now = Date()
        let ms = Int(now.timeIntervalSince(procStart) * 1000)
        let m = mid.map(Self.short) ?? "-"
        MontanaLog.write(.trace, "|\(ms)|\(event)|\(m)|\(kv)")
        // AN ERROR CALLS FOR THE JOURNAL ITSELF. A breakdown must be reported in the hour it
        // happens, not a quarter of an hour later. The line describing the error is already here —
        // at the one point every mark passes through — so the decision "time to report" belongs
        // here too, not to ten call sites across the tree ([C-1]).
        if Self.isFailure(event, kv) { onFailure?() }
    }

    /// The hand an error uses to reach the shipper. The app wires it at launch; the extensions
    /// leave it nil — their journal is carried over by the app, they have nothing to ship with.
    static var onFailure: (() -> Void)?

    /// WHAT COUNTS AS AN ERROR — a closed list, like TRACE_KEYS on the node: a form cannot
    /// tell meaning apart, only a list can.
    ///   • a letter refused, dead of age, or turned red: enqueue_drop, send_refused,
    ///     send_failed, send_red
    ///   • a call that did not assemble: dial_failed, call_ice with failed/disconnected
    ///   • the node answered with its own breakdown: any code=5xx (precedent 26.08: httpx
    ///     vanished from the node — 502 on every push, and for half an hour only the node knew)
    ///   • wake registration failed: wakepush_register_fail
    /// NOT an error: 404 (an empty box is routine), and diag_ship itself — a failed shipment
    /// must never call for a shipment, that loop would drain the battery.
    ///   • THE AUTHOR'S CLASSES (16.09: «a send failure, a demanded retry, a call error, a
    ///     network or connection error must fly to the diary at once»): a door that refused or
    ///     went dead (sig_tx FAIL, sig_door, box_fetch refused, blob_get unreachable, wakepush_tx
    ///     code=-1, handshake_timeout, node_shut, path_down), a call that did not ring or
    ///     died (call_refused, ring_dead, ring_unreached, ring_expired, notify_failed), a
    ///     store that failed (media_store_fail, rx_media_dead), a retry demanded anywhere
    ///     (the word «retry» in the line), and any code=-1 — a door that did not answer.
    static func isFailure(_ event: String, _ kv: String) -> Bool {
        if event == "diag_ship" { return false }
        switch event {
        case "enqueue_drop", "send_refused", "send_failed", "send_red",
             "dial_failed", "wakepush_register_fail",
             "sig_door", "handshake_timeout", "node_shut", "path_down",
             "call_refused", "ring_dead", "ring_unreached", "ring_expired", "notify_failed",
             "media_store_fail", "rx_media_dead", "of_relay_drop",
             "cam_denied", "cam_fail":
            return true
        // THE CALL'S MIRRORED WORDS (20.09): a camera that did not start, a format that failed, a
        // silent session, a refused description — each is a breakdown the author asked to see in
        // the hour it happens, not with the next quarter-hour shipment.
        case "wake_verdict":
            return !kv.hasSuffix("verdict=ok")
        case "call_dbg":
            return kv.contains("did not start") || kv.contains("failed to start") || kv.contains("SILENT")
                || kv.contains("ERROR") || kv.contains("refused") || kv.contains("FAILED") || kv.contains("denied")
        case "call_ice":
            return kv.contains("failed") || kv.contains("disconnected")
        case "sig_tx":
            return kv.contains("FAIL")
        case "box_fetch":
            return kv.contains("refused")
        case "blob_get":
            return kv.contains("unreachable")
        default:
            return kv.contains("code=5") || kv.contains("code=-1") || event.contains("retry") || kv.contains("retry")
        }
    }

    /// THE ONE PLACE THAT DECIDES «is this worth a line» ([C-1]). A state that has not changed is not
    /// news: the line is written when the CONTENT changes, and once per `every` seconds after that so
    /// a long-standing truth still proves itself alive.
    private static var lastKV: [String: (kv: String, at: Date)] = [:]
    static func markChanged(_ event: String, _ kv: String, every: TimeInterval = 0,
                            key: String? = nil, mid: String? = nil, tele: Bool = false) {
        var write = false
        let slot = event + "|" + (key ?? "")
        bookLock.lock()
        let prev = lastKV[slot]
        if prev?.kv != kv || (every > 0 && Date().timeIntervalSince(prev?.at ?? .distantPast) >= every) {
            lastKV[slot] = (kv, Date()); write = true
        }
        bookLock.unlock()
        guard write else { return }
        mark(event, mid: mid, kv)
        // A changed state the telemetry must keep too (the shipper's ledger, 25.09): the file that outlives a storm of
        // the trace carries the same line, judged by the same gate -- one owner of «changed» ([C-1], P-112).
        if tele { MontanaLog.event(event.uppercased() + " " + kv) }
    }

    /// A REPEAT IS A NUMBER, NOT A PAGE. Events that legitimately fire in volleys (a punch fan, a
    /// batch of receipts, duplicate frames arriving through both doors) are counted inside a window
    /// and reported as one line with n=. The first of a volley is written at once — a fault must not
    /// wait out a window — and the tail arrives folded.
    private static var folds: [String: (n: Int, at: Date, kv: String)] = [:]
    /// `key` keeps volleys of DIFFERENT things apart: two doors folded into one counter would
    /// hide the fact that one of them is silent while the other answers.
    static func markFolded(_ event: String, _ kv: String = "", window: TimeInterval = 10, key: String? = nil) {
        var first = false
        let slot = event + "|" + (key ?? "")
        bookLock.lock()
        if let f = folds[slot], Date().timeIntervalSince(f.at) < window {
            folds[slot] = (f.n + 1, f.at, kv)
        } else {
            folds[slot] = (1, Date(), kv); first = true
        }
        bookLock.unlock()
        guard first else { return }
        mark(event, mid: nil, kv)
        // The tail of a volley closes ITSELF: a count that waits for the next event would be
        // silent exactly when the volley was the last thing that happened — and that is the
        // case worth reading. One-shot, never a repeating timer.
        q.asyncAfter(deadline: .now() + window) {
            bookLock.lock(); let f = folds[slot]; folds[slot] = nil; bookLock.unlock()
            guard let f else { return }
            if f.n > 1 { mark(event, mid: nil, "n=\(f.n - 1) more \(f.kv)") }
        }
    }

    /// One-shot events (first frame, app init) — repeated calls are ignored.
    static func markOnce(_ event: String, _ kv: String = "") {
        var first = false
        bookLock.lock(); if !onceKeys.contains(event) { onceKeys.insert(event); first = true }; bookLock.unlock()
        guard first else { return }
        mark(event, mid: nil, kv)
    }

}


enum MontanaBlobStore {
    /// THE PIECES LIE ON THE CONTOUR'S SHELF (29.09, MontanaHandoff.blobs): one folder for the app and the landing door, so a
    /// piece the extension brought in the background is the very piece the app assembles from. The folder of the older builds
    /// (Documents/Montana/Blobs) is emptied onto the shelf once, at the first ask; without a group it stays the store. Resolved
    /// once per process by the language's own once-initialisation — no lock of ours stands over a file move.
    private static let legacy: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Montana").appendingPathComponent("Blobs")
    private static let resolved: URL = {
        guard let shelf = MontanaHandoff.blobs else {
            try? FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            return legacy
        }
        if let names = try? FileManager.default.contentsOfDirectory(atPath: legacy.path) {
            var moved = 0
            for n in names where !n.hasPrefix(".") {
                let from = legacy.appendingPathComponent(n), to = shelf.appendingPathComponent(n)
                if FileManager.default.fileExists(atPath: to.path) { try? FileManager.default.removeItem(at: from) }
                else if (try? FileManager.default.moveItem(at: from, to: to)) != nil { moved += 1 }
            }
            if moved > 0 { MontanaTrace.mark("blob_shelf", "moved=\(moved) pieces from the app's folder onto the contour's shelf") }
        }
        return shelf
    }()
    static var dir: URL { resolved }
    private static func url(_ blobId: String) -> URL { dir.appendingPathComponent(blobId) }

    static func put(_ blobId: String, _ sealed: Data) {
        guard blobId.count == 64 else { return }
        let u = url(blobId)
        if !FileManager.default.fileExists(atPath: u.path) { try? sealed.write(to: u, options: .atomic) }
    }
    static func get(_ blobId: String) -> Data? {
        try? Data(contentsOf: url(blobId), options: .mappedIfSafe)
    }
    /// How much a chunk weighs, WITHOUT reading it. Summing the bytes held for others used to open
    /// every file in the store; on the network page that ran on the main thread and froze the app
    /// (measured 03.09 23:24: main_hang step=net.pending). The file system already knows the size.
    static func size(_ blobId: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url(blobId).path)[.size] as? Int64) as? Int64 ?? 0
    }

    /// A chunk is TRANSPORT PACKAGING, not storage. An assembled file lies sealed in the archive, and
    /// after that the chunks are needed by nobody; the sent ones are needed exactly while the peer can
    /// fetch them. While nobody removed them, they piled up forever: measured on a phone -- almost four
    /// thousand files of half a megabyte, about two gigabytes of an "empty" app.
    static func drop(_ blobIds: [String]) {
        for id in blobIds where id.count == 64 { try? FileManager.default.removeItem(at: url(id)) }
    }

    /// Packaging nobody named is rubbish. Chunks are needed for exactly two jobs: handing a file to the
    /// node and assembling it at the recipient; both end in minutes. Keeping them "just in case" is
    /// pointless -- the peer has the file assembled already, and on the node the blob lives its own week.
    /// Measured: 1332 chunks lay on a phone with an EMPTY chat list -- a pure second copy.
    ///
    /// BOUND-OK: what remains is only what a live letter refers to, plus a window for the current
    /// carriage -- a chunk born a minute ago may still be waiting to be sent.
    static let graceSeconds = 900.0
    static func sweepUnreferenced(keep: Set<String>) {
        let fm = FileManager.default
        let edge = Date().addingTimeInterval(-graceSeconds)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        var freed = 0, gone = 0
        for n in names where !n.hasPrefix(".") && !keep.contains(n) {
            let u = dir.appendingPathComponent(n)
            let attrs = try? fm.attributesOfItem(atPath: u.path)
            let made = (attrs?[.modificationDate] as? Date) ?? Date()
            guard made < edge else { continue }
            freed += (attrs?[.size] as? Int) ?? 0; gone += 1
            try? fm.removeItem(at: u)
        }
        // A pass always says what it did: the silence of "deleted nothing" and the silence of "never
        // ran" look the same, and on exactly that the cleanup twice seemed to be working.
        MontanaTrace.mark("blob_sweep", "dropped=\(gone) kept=\(keep.count) freed_kb=\(freed / 1024)")
    }

    /// Bounded so a lost chunk fails the download instead of hanging. Waiting for a chunk makes sense
    /// for SECONDS, not minutes: real delivery is done by fetchChunks with three passes and a fallback,
    /// and if there is no chunk after it, there is none on the node at all. The former three minutes PER
    /// CHUNK turned a loss into a multi-minute freeze with a full bar, while the person looked at
    /// "downloaded" on a file that would never come (20.08).
    static func awaitChunk(_ blobId: String, timeoutMs: Int = 5000) async -> Data? {
        var waited = 0
        while waited < timeoutMs {
            if let d = get(blobId) { return d }
            try? await Task.sleep(nanoseconds: 100_000_000); waited += 100
        }
        return get(blobId)
    }
}
