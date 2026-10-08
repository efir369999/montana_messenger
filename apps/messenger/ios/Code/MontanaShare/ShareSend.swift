import Foundation
import CryptoKit
import MontanaBindings
import Network

// The share extension prepares and UPLOADS; the app SENDS. The pieces of a shared item are
// sealed by the shared MontanaMedia.buildManifest (one implementation for the chat and the
// extension) and land in the extension's own blob store — the app cannot read that container,
// so the upload to the node happens HERE, where the bytes are. The manifest letter itself is
// sent by the app on next open through the one delivery engine (ingestPendingShares): the
// engine owns retries, receipts and the wake — a second sender would drift by construction.

// mediaMark lives in MontanaMediaKit — one owner ([C-1]), compiled into this target too.

enum ShareSend {

    // SSOT-DEBT-ACK: node base + blob-put are copies of MontanaWakePush.putBlob — the app's
    // network layer does not compile into the extension. The wire shape is frozen by the node
    // (/blob-put {bid, data}); node tests hold the contract.
    // The doors, the deadline move and the wire formulas live in MTNodeWire — the ONE
    // owner compiled into this target too (SSOT-CONSOLIDATE: the frozen copies are gone).
    /// THE DOORS OF THIS SEND (the author's word 16.09: one behaviour on any network): judged
    /// at the tap — every mirrored door asked at once, those that answer kept, fastest first;
    /// only when none answers does the roster stand as it is, and the journal says so.
    private static var judged: [String] = []
    private static let judgedLock = NSLock()
    static func judgeDoors() async {
        let roster = MTNodeWire.mirroredDoors()
        let t0 = Date()
        let up = await MTNodeWire.judgedDoors(roster, cap: "blob")
        judgedLock.lock(); judged = up; judgedLock.unlock()
        let names = up.map { URL(string: $0)?.host ?? $0 }.joined(separator: ",")
        diag("doors up=\(up.count) of=\(roster.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000)) order=\(names)")
    }
    static func doors() -> [String] {
        judgedLock.lock(); let j = judged; judgedLock.unlock()
        let list = j.isEmpty ? MTNodeWire.mirroredDoors() : j
        // THE APP'S ELECTED DOOR FIRST (1638, the author's word: one live node per phone): the sheet
        // writes where the app writes; the judged list only says which doors are alive on this
        // network and in what order to walk on when the elected one has died (the rule lives in MTNodeWire).
        return MTNodeWire.electedFirst(list)
    }

    static func putBlob(_ bid: String, data: Data) async -> Bool {
        let code = await MTNodeWire.post("/blob-put", body: ["bid": bid, "data": data.base64EncodedString()],
                                         doors: doors(), attempts: 3, timeout: MTNodeWire.cargoTimeoutS(bytes: data.count)).code   // the cargo's own deadline (17.09)
        if code != 200 { diag("blob code=\(code) bid=\(String(bid.prefix(8)))") }
        return code == 200
    }

    /// Upload every piece of the manifest to the node, three in flight (the same window the
    /// app uses). True only when ALL pieces made it — the recipient must never chase a hole.
    static func uploadManifestChunks(_ ref: [String: Any],
                                     progress: @escaping @Sendable (Int, Int) -> Void) async -> Bool {
        let bids = (ref["chunks"] as? [[String: Any]] ?? []).compactMap { $0["bid"] as? String }
        guard !bids.isEmpty else { return false }
        let total = bids.count
        // THE UPLOAD'S MEASURE (the author's word 16.09: the sheet on cellular and on Wi-Fi must
        // be one and the same road): pieces, bytes, the seconds and the rate — one line per cargo.
        let t0 = Date()
        var bytes = 0
        for b in bids { bytes += MontanaBlobStore.get(b)?.count ?? 0 }
        defer {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            diag("upload chunks=\(total) bytes=\(bytes) ms=\(ms) kbps=\(ms > 0 ? bytes * 8 / ms : 0) doors=\(doors().count)")
        }
        return await withTaskGroup(of: Bool.self) { group -> Bool in
            var next = 0
            func launch(_ i: Int) {
                let bid = bids[i]
                group.addTask {
                    guard let sealed = MontanaBlobStore.get(bid) else { return false }
                    return await putBlob(bid, data: sealed)
                }
            }
            for _ in 0..<min(3, bids.count) { launch(next); next += 1 }
            var good = true
            var done = 0
            for await ok in group {
                if !ok { good = false; group.cancelAll(); break }
                done += 1
                progress(done, total)   // honest network progress: the piece is ON the node
                if next < bids.count { launch(next); next += 1 }
            }
            return good
        }
    }

    // The letter-path formulas live in MTNodeWire (the one owner, canon-held) — this file
    // references them; no frozen copy remains here (SSOT-CONSOLIDATE, the author's word 29.08).
    static func sealBlob(key: [UInt8], _ plain: Data) -> Data? { MTNodeWire.sealBlob(key: key, plain) }
    private static func keychainString(_ key: String) -> String {
        MontanaKeychain.get(key).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    /// The name my letters carry: the byline of a post written in the sheet.
    static var myName: String { keychainString("wakeMyName") }
    private static func pipeSecret(for conv: String) -> Data? {
        guard let d = MontanaKeychain.get("nsePipeSecrets"),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return nil }
        if let s = m[conv] { return s }
        // The pipe may live under a local name (ref) while the share grid keys by the chat
        // key — the NSE walks the alias dictionary for exactly this; the sender must too.
        if let ad = MontanaKeychain.get("nsePipeAlias"),
           let alias = try? JSONDecoder().decode([String: String].self, from: ad) {
            if let ref = alias.first(where: { $0.value == conv })?.key, let s = m[ref] { return s }
            if let chat = alias[conv], let s = m[chat] { return s }
        }
        return nil
    }

    /// Ring the host across processes: a Darwin note a RUNNING app hears at once and picks
    /// up the pending share — the sender's bubble must not wait for the next activation.
    /// A suspended app misses the note by design; activation ingest is its road.
    static func ringHost() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("quest.montana.share.pending" as CFString), nil, nil, true)
    }

    /// The extension's journal: it cannot reach the trace file, so lines ride the keychain
    /// and the app prints them on activation — the same road the NSE diagnostics take.
    static func diag(_ line: String) {
        var arr: [String] = []
        if let d = MontanaKeychain.get("shareDiag"),
           let a = try? JSONDecoder().decode([String].self, from: d) { arr = a }
        arr.append("t=" + MTNodeWire.clock() + " " + line)   // the moment rides with the line: where a share spent its seconds is measurable
        if arr.count > 24 { arr.removeFirst(arr.count - 24) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("shareDiag", d) }
        if let last = arr.last { ship(last) }
    }

    /// EVERY EVENT REACHES THE DIARY AT ONCE (the author's word 16.09: the sheet died after
    /// «SAVED» and the diary learned it two minutes later, at the app's next opening — where it
    /// died nobody could say). The line goes to the node's diary door the moment it is written,
    /// under the app's own diary id (mirrored into the shared keychain), in the trace's own
    /// shape; the keychain copy stays for the app's print. A line that does not make it is a
    /// line lost, never a sheet held: the shipment is detached and short.
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static func ship(_ stamped: String) {
        guard let dg = MontanaKeychain.get("diagId").flatMap({ String(data: $0, encoding: .utf8) }), !dg.isEmpty else { return }
        let line = iso.string(from: Date()) + "|0|share_live|-|" + stamped
        let body: [String: Any] = ["dg": dg, "file": "trace",
                                   // The device names itself as the app does (MTNodeWire, 25.09): «sheet» as the model let the
                                   // diaries machine read a phone's folder as an extension.
                                   "dev": ["model": MTNodeWire.deviceModel(), "ios": MTNodeWire.osVersion(), "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
                                           "tz": TimeZone.current.secondsFromGMT(), "lang": MTNodeWire.screenLang(), "skew_ms": 0],
                                   "lines": [line]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let doors = MTNodeWire.mirroredDoors()
        Task.detached(priority: .utility) {
            for b in doors {
                guard let u = URL(string: b + "/diag-put") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
                var req = URLRequest(url: u); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.timeoutInterval = 5
                req.httpBody = data
                guard let (_, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                      (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                return
            }
        }
    }

    /// Send one letter from the extension over the node wake — the same envelope shape the
    /// app seals (mid‖0‖text‖0‖name‖0‖glyph‖0, padded to 2048, keyed by the pipe). True on
    /// node 200: the banner rings NOW; the app re-enqueues the SAME mid on next open as the
    /// guarantee leg — the node and the receiver dedup it.
    static func sendLetter(peer: String, mid: String, text: String) async -> Bool {
        // An older build's retired letter is never sent again (MTRetired.letter).
        guard !MTRetired.letter(text) else { diag("send SKIP a retired letter"); return false }
        let doors = doors()
        guard let secret = pipeSecret(for: peer) else {
            diag("send SKIP no-secret peer=\(String(peer.prefix(10))) doors=\(doors.count)")
            return false
        }
        let twinRef = keychainString("wakeMyAddr")
        guard !twinRef.isEmpty else { diag("send SKIP no-addr"); return false }
        // The envelope's shape and the walk over the doors live in MTNodeWire — the one owner
        // for the app, this sheet and the landing door (SSOT-CONSOLIDATE, 18.09).
        guard let plain = MTNodeWire.padEnvelope(MTNodeWire.letterHead(mid: mid, text: text,
                                                                        name: keychainString("wakeMyName"),
                                                                        glyph: keychainString("wakeMyGlyph"))) else { return false }
        // A quiet failure here is NOT a loss: the app re-enqueues the SAME mid on next open
        // (the guarantee leg) — so the sheet must never buy delivery with minutes of hanging.
        // THE SHEET WALKS ON A DEAD BELL AS THE APP DOES (1637, the author's word 16.09): boxed at
        // one door is the guarantee; the walk goes on until a door rings or the doors run out.
        let t0 = Date()
        let k = await MTNodeWire.knockLetter(secret: secret, twinRef: twinRef, mid: mid, plain: plain, doors: doors)
        diag("send code=\(k.code) woken=\(k.woken) walked=\(k.walked)/\(doors.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000)) peer=\(String(peer.prefix(10))) mid=\(String(mid.prefix(8)))")
        return k.boxed
    }

    /// The sheet's own network, as the app's net_env line says it (the author's word 16.09:
    /// cellular and Wi-Fi are suspected to walk different roads): the path the system reports
    /// to THIS process at the tap — interfaces, cost, constraint, address families.
    static func netEnv() async -> String {
        await withCheckedContinuation { c in
            let m = NWPathMonitor()
            let once = NSLock(); var done = false
            let finish: (String) -> Void = { s in once.lock(); let d = done; done = true; once.unlock(); if !d { m.cancel(); c.resume(returning: s) } }
            m.pathUpdateHandler = { p in
                let ifs = p.availableInterfaces.map { i -> String in
                    switch i.type { case .cellular: return "cellular"; case .wifi: return "wifi"; case .wiredEthernet: return "wired"; case .loopback: return "loop"; default: return "other" }
                }.joined(separator: ",")
                finish("status=\(p.status == .satisfied ? "satisfied" : "unsatisfied") ifs=\(ifs) v4=\(p.supportsIPv4 ? 1 : 0) v6=\(p.supportsIPv6 ? 1 : 0) dns=\(p.supportsDNS ? 1 : 0) metered=\(p.isExpensive ? 1 : 0) constrained=\(p.isConstrained ? 1 : 0)")
            }
            m.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { finish("status=unknown (no path report in 1.5 s)") }
        }
    }
}
