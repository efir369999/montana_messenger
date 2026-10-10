//  MTNodeWire.swift — the ONE owner of the node-wire formulas and of the one network move
//  to the accelerator doors ([C-1]). Compiled into the app, the share extension and the
//  notification extension alike: the frozen copies these targets used to carry under
//  SSOT-DEBT-ACK lived in four places and could only drift. The canon vectors
//  (MontanaWakePush.agreesWithCanon + the node-wake checklist) keep holding these very
//  bytes through the app target — every caller now holds them by reference.
//  LOCAL-HASH-OK: this file IS the single canon owner of the wire hash compositions the
//  vectors freeze; sealing/opening itself is the core (mt_e2e_*), no own cipher exists.

import Foundation
import CryptoKit
import Security
import MontanaBindings

enum MTNodeWire {

    // ── THE DEVICE NAMES ITSELF THE SAME FROM EVERY TARGET (25.09) ────────────────────────────
    // The extensions shipped «nse» and «sheet» as the model, and the diaries machine kept the last word it
    // heard: a phone's folder read as an extension, and the fleet's map counted a person as a door.
    /// The hardware name the kernel gives (iPhone14,3); an iOS app on Apple silicon says so in brackets
    /// (23.09, the critic: the Mac's diary read «iPad8,6» and a reader took it for a tablet).
    static func deviceModel() -> String {
        var u = utsname(); uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix(while: { b in b != 0 }), as: UTF8.self)
        }
        return ProcessInfo.processInfo.isiOSAppOnMac ? "Mac(" + machine + ")" : machine
    }
    /// The system's version as the app has always written it (26.6, 26.6.2): the patch only when it is not zero.
    static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    /// The two letters of the person's screen language.
    static func screenLang() -> String { String(Locale.preferredLanguages.first?.prefix(2) ?? "?") }

    // ── the frozen wire formulas (canon-held) ──────────────────────────────
    static func hexHash(_ m: Data) -> String {
        SHA256.hash(data: m).map { String(format: "%02x", $0) }.joined()   // LOCAL-HASH-OK: canon owner
    }
    /// The letter body key: SHA-256("mt-pipe-key" ‖ 0x00 ‖ secret ‖ W_8B_LE) — the set's value.
    static func bodyKey(secret: Data, window: UInt64) -> [UInt8] {
        var m = Data("mt-pipe-key".utf8); m.append(0); m.append(secret)   // LOCAL-HASH-OK: canon owner
        var w = window.littleEndian; withUnsafeBytes(of: &w) { m.append(contentsOf: $0) }
        return Array(SHA256.hash(data: m))   // LOCAL-HASH-OK: canon owner, held by the vectors
    }
    /// THE WALLET'S OWN DOORS ON THE NODE (the author's word 09.10.2026 16:03 MSK: «the calls conflict in the phone if I am in
    /// our different apps with one seed -- fix it at the root by construction»). The node keeps ONE row per label and seed tag,
    /// PRIMARY KEY(conv, sub_id), and the last app of a seed to register takes it; the box gives a letter to whichever app of the
    /// seed asks first and lets it go at that app's receipt (montana-notify and the store, read on both nodes 09.10.2026, sha256
    /// 8a36288e). A coin letter rang, and was taken by, the Messenger of the same seed. The wallet's labels carry the wallet's own
    /// domain: a wallet's letter goes to a wallet, and no other app of the seed hears it, rings for it or takes it from the box.
    static let ownDoor = "-wallet"
    /// THE DOOR THE PERSON'S OTHER APPS WRITE AT (the author's word 10.10.2026 12:4x MSK: «when the words entered several apps,
    /// Montana is asked first, then Business»). Montana and Montana Business label every pipe with no door of their own -- their
    /// canon freezes the tag of 0..31 at 29737 as 43eaf281… -- so the pipe of light they name their light copy in is heard at that
    /// door alone. Read at the wallet's own door it was silent by construction (T1 10.10.2026 12:09:53Z: both nodes answered the
    /// wallet's ten labels of light with letters=0, and the card of the person stood empty).
    static let sharedDoor = ""
    /// The conversation's daily tag: both sides derive it from the shared pipe secret, at the door both of them use.
    static func convW(_ secret: Data, window: UInt64, door: String = ownDoor) -> String {
        var m = Data(("mt-wake-conv" + door).utf8); m.append(0); m.append(secret)   // LOCAL-HASH-OK: canon owner
        var w = window.littleEndian; withUnsafeBytes(of: &w) { m.append(contentsOf: $0) }
        return hexHash(m)
    }
    /// The daily tag of a handed-out invite (F-2: the first-letter wake).
    static func rdvConvW(_ invite: Data, window: UInt64) -> String {
        var m = Data(("mt-rdv-wake" + ownDoor).utf8); m.append(0); m.append(invite)   // LOCAL-HASH-OK: canon owner
        var w = window.littleEndian; withUnsafeBytes(of: &w) { m.append(contentsOf: $0) }
        return hexHash(m)
    }
    /// The subscription tag standing in for the Montana address at the node.
    static func subId(_ conv: String, ref: String) -> String {
        var m = Data("mt-wake-sub".utf8); m.append(0)   // LOCAL-HASH-OK: canon owner
        m.append(contentsOf: conv.utf8); m.append(0)
        m.append(contentsOf: ref.utf8)
        return hexHash(m)
    }
    // ── the letter envelope's plain body — ONE recipe for the app, the sheet and the landing door ──
    /// mid‖0‖text‖0‖name‖0‖glyph‖0 [‖quote(≤200)‖0‖quoted mid‖0]: the head every letter envelope
    /// wears. The app built it in sealLetterEnvelope and the sheet in sendLetter — two copies of one
    /// shape; the landing door became the third writer, so the shape moved here (SSOT-CONSOLIDATE, 18.09).
    static let envelopeSize = 2048
    static func letterHead(mid: String, text: String, name: String, glyph: String,
                           quoteText: String? = nil, quoteMid: String? = nil) -> Data {
        var body = Data(mid.utf8); body.append(0); body.append(contentsOf: text.utf8); body.append(0)
        body.append(contentsOf: name.utf8); body.append(0)
        body.append(contentsOf: glyph.utf8); body.append(0)
        // The quote tail is decoration: when it does not fit, the letter rides without it.
        if let qt = quoteText, !qt.isEmpty {
            var tail = Data(qt.prefix(200).utf8); tail.append(0)
            tail.append(contentsOf: (quoteMid ?? "").utf8); tail.append(0)
            if body.count + tail.count <= envelopeSize { body.append(tail) }
        }
        return body
    }
    /// One size for every envelope — the node cannot tell letter lengths apart. Larger — nil.
    static func padEnvelope(_ body: Data) -> Data? {
        guard body.count <= envelopeSize else { return nil }
        var b = body; b.append(Data(count: envelopeSize - body.count)); return b
    }
    /// The phone's ONE elected door first (1638, the author's word: one live node per phone):
    /// written by the app, read by every process that knocks without the live list.
    static func electedFirst(_ list: [String]) -> [String] {
        if let d = MontanaKeychain.get(electedKey), let e = String(data: d, encoding: .utf8), list.contains(e) {
            return [e] + list.filter { $0 != e }
        }
        return list
    }
    // ── THE SHELF'S EARS FOR THE EXTENSION (07.10, MTShelfPost) ─────────────
    /// The persons waiting on this phone's shelf -- their seat, their name and the keys their letters open with (a pipe's
    /// reference, or «rdv:» and an invitation) -- so a letter to a person not seated shows whose it is. Written by the app,
    /// read by the notification extension; this device's own, never in a copy (SeedScope.keychainStays).
    struct ShelfEar: Codable { let seat: String; let name: String; let keys: [String: Data] }
    static func shelfEars() -> [ShelfEar] {
        MontanaKeychain.get("nseShelf").flatMap { try? JSONDecoder().decode([ShelfEar].self, from: $0) } ?? []
    }
    static func writeShelfEars(_ ears: [ShelfEar]) {
        if let d = try? JSONEncoder().encode(ears) { MontanaKeychain.set("nseShelf", d) }
    }
    /// ONE KNOCK OF A LETTER FROM A PROCESS WITHOUT THE LIVE LIST (the sheet, the landing door) —
    /// the walk the sheet proved (1637): the node answers 200 the moment the letter is boxed and
    /// names the ring itself; boxed at one door is the guarantee, the walk goes on until a door
    /// rings or the doors run out. The seal is made AT the knock, afresh for every door (16.09).
    struct Knock { let boxed: Bool; let woken: Int; let code: Int; let walked: Int }
    static func knockLetter(secret: Data, twinRef: String, mid: String, plain: Data, doors: [String],
                            deadline: Date? = nil, silent: Bool = false) async -> Knock {
        let cw = convW(secret, window: dayWindow())
        let sub = subId(cw, ref: twinRef)
        var boxed = false, woken = -1, code = -1, walked = 0
        for d in doors {
            if let deadline, Date() >= deadline { break }
            walked += 1
            let r = await post("/wake", make: {
                guard let env = sealBlob(key: bodyKey(secret: secret, window: minuteWindow()), plain) else { return [:] }
                var body: [String: Any] = ["conv": cw, "from_id": sub, "mid": mid, "env": env.base64EncodedString()]
                if silent { body["silent"] = true }   // a service word (a receipt from the shelf, MTShelfPost) rings nobody
                return body
            }, doors: [d], attempts: 1)
            code = r.code
            guard code == 200 else { continue }
            boxed = true
            woken = ((r.data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any])?["woken"] as? Int ?? -1
            if woken > 0 { break }
        }
        return Knock(boxed: boxed, woken: woken, code: code, walked: walked)
    }
    /// A CLOCK FOR THE EXTENSIONS' JOURNALS: hh:mm:ss UTC, which the diary scrubber leaves alone
    /// (an epoch of ten digits is hidden as an address). One owner for both extensions.
    static func clock() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
    static func minuteWindow() -> UInt64 { UInt64(Date().timeIntervalSince1970) / 60 }
    static func dayWindow() -> UInt64 { UInt64(Date().timeIntervalSince1970) / 86400 }

    // ── seal / open by the core — no own cipher exists ─────────────────────
    static func sealBlob(key: [UInt8], _ plain: Data) -> Data? {
        var nonce = [UInt8](repeating: 0, count: 12)
        guard mt_random_fast(&nonce, 12) == 0 else { return nil }
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let rc = key.withUnsafeBufferPointer { k in nonce.withUnsafeBufferPointer { n in plain.withUnsafeBytes { pp -> Int32 in
            mt_e2e_seal_blob(k.baseAddress, n.baseAddress, pp.bindMemory(to: UInt8.self).baseAddress, plain.count, &outPtr, &outLen)
        }}}
        guard rc == 0, let ptr = outPtr else { return nil }
        let sealed = Data(bytes: ptr, count: outLen); mt_e2e_free(ptr, outLen)
        return sealed
    }
    static func openBlob(key: [UInt8], sealed: Data) -> Data? {
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let rc = key.withUnsafeBufferPointer { k in sealed.withUnsafeBytes { s -> Int32 in
            mt_e2e_open_blob(k.baseAddress, s.bindMemory(to: UInt8.self).baseAddress, sealed.count, &outPtr, &outLen)
        }}
        guard rc == 0, let ptr = outPtr else { return nil }
        let plain = Data(bytes: ptr, count: outLen); mt_e2e_free(ptr, outLen)
        return plain
    }

    /// THE MINUTE OF THE SEAL IS THE SENDER'S; THE MINUTE THE NODE NAMES IS THE RECEIVER'S (16.09).
    /// A boxed letter is sealed under the key of the minute it was sealed in, and the node keeps
    /// only the minute it RECEIVED it. Between the two stand a door walk, a suspended app, a dead
    /// carrier route — minutes, not seconds. Measured 16.09 on T1 (cellular): six letters lay in
    /// the boxes of three nodes, fetched 26 times each, never opened — the labels matched (the
    /// secret is the same), only the minute did not; they landed in the chat hours later, when the
    /// sender's resend rode a fresh seal. So the receiver walks BACK from the node's minute, a day
    /// deep (one hash and one open per minute — twelve milliseconds for the whole day), because a
    /// seal is never made after the node took it. One owner for the app and the landing door.
    static let openBackMinutes: UInt64 = 1440
    static func openBoxed(_ sealed: Data, secret: Data, at: UInt64) -> (plain: Data, back: Int)? {
        let w0 = at / 60
        for w in [w0, w0 &- 1, w0 &+ 1] {   // the common case first: sealed and taken in one breath
            if let p = openBlob(key: bodyKey(secret: secret, window: w), sealed: sealed) { return (p, Int(w0) - Int(w)) }
        }
        var w = w0 &- 2
        for _ in 2...openBackMinutes {
            if let p = openBlob(key: bodyKey(secret: secret, window: w), sealed: sealed) { return (p, Int(w0) - Int(w)) }
            w = w &- 1
        }
        return nil
    }

    // ── the doors, as a process without the live list sees them ────────────
    /// The app mirrors its verified door list at bootstrap; an extension has no live list of
    /// its own. One dead remembered door used to hold the whole share sheet hostage.
    static func mirroredDoors() -> [String] {
        if let d = MontanaKeychain.get("wakeBases"),
           let arr = try? JSONDecoder().decode([String].self, from: d), !arr.isEmpty { return arr }
        if let d = MontanaKeychain.get("wakeBase"), let s = String(data: d, encoding: .utf8),
           !s.isEmpty { return [s] }
        return []
    }

    // ── the doors are judged on the network of the moment ─────────────────
    /// ONE PROBE OF A DOOR ([C-1], the author's word 16.09: one behaviour on Wi-Fi and on
    /// cellular): the door's /health, its capability map and its answer time. The app's
    /// verification and the sheet's judgement both ask through here; a door that answers
    /// without a map is believed to hold everything ([P2P-COMPAT]).
    static func health(_ base: String, timeout: TimeInterval) async -> (caps: Set<String>?, ms: Int)? {
        guard let u = URL(string: base + "/health") else { return nil }   // SERVER-DEBT-ACK: the accelerator node (rung 4), health probe
        var req = URLRequest(url: u); req.timeoutInterval = timeout   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        let t0 = Date()
        guard let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let caps = j["caps"] as? [String: Any] else { return (nil, ms) }
        return (Set(caps.filter { ($0.value as? Bool) == true }.map(\.key)), ms)
    }
    /// THE DOORS OF THIS SEND: every candidate asked at once, and those that answered on THIS
    /// network — the fastest first. The sheet used to walk a stored list in a fixed order, five
    /// seconds per dead door; the app knocks every door on a network change and keeps the ones
    /// that answer. One judgement now, for both.
    static func judgedDoors(_ candidates: [String], cap: String? = nil, timeout: TimeInterval = 4) async -> [String] {
        await withTaskGroup(of: (String, Int)?.self) { group -> [String] in
            for b in candidates {
                group.addTask {
                    guard let h = await health(b, timeout: timeout) else { return nil }
                    if let cap, let caps = h.caps, !caps.contains(cap) { return nil }
                    return (b, h.ms)
                }
            }
            var good: [(String, Int)] = []
            for await r in group { if let r { good.append(r) } }
            return good.sorted { $0.1 < $1.1 }.map(\.0)
        }
    }

    // ── the one network move to a node door ────────────────────────────────
    /// A deadline instead of the 60s system one, a FRESH ephemeral lane after any failure (a
    /// zombie HTTP/2 pipe under a VPN eats a request whole — measured twice: the voip wake
    /// 22:20→22:21, the share sheet 05:32→05:35), and door rotation so one dead door never
    /// gets every try. 404 returns as knowledge (nobody listens), not as a retryable failure.
    /// THE DOOR THAT ANSWERED LAST IS ASKED FIRST (13.09, the share sheet): an extension has no
    /// dead-door memory of its own, and every request started at the list's first door — a dead
    /// first door cost every chunk and every letter its whole deadline. The cursor moves onto the
    /// door that answered and past a door that did not; the process remembers for its life.
    /// The phone's ONE elected door (1638, the author's word): written by the app, read by the sheet.
    static let electedKey = "wakeElected"
    static func post(_ path: String, body: [String: Any], doors: [String],
                     attempts: Int, timeout: TimeInterval = postTimeoutS) async -> (code: Int, data: Data?) {
        await post(path, make: { body }, doors: doors, attempts: attempts, timeout: timeout)
    }
    /// THE BODY IS MADE AT THE KNOCK, not when the walk was planned (16.09): a sealed envelope
    /// carries the minute of its sealing, and a walk over dead doors carries it into the next
    /// minutes — the maker seals afresh for every door it knocks on.
    static func post(_ path: String, make: @escaping () -> [String: Any], doors: [String],
                     attempts: Int, timeout: TimeInterval = postTimeoutS) async -> (code: Int, data: Data?) {
        guard !doors.isEmpty else { return (-1, nil) }
        var fresh = false
        var saw404 = false
        let start = 0   // the caller's order is the law (1638): the elected door first, the rest only past its death
        for attempt in 0..<attempts {
            let idx = (start + attempt) % doors.count
            let base = doors[idx]
            guard let url = URL(string: base + path) else { continue }
            var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = timeout
            guard let data = try? JSONSerialization.data(withJSONObject: make()) else { return (-1, nil) }
            req.httpBody = data
            let session: URLSession
            if fresh {
                let cfg = URLSessionConfiguration.ephemeral
                cfg.timeoutIntervalForRequest = timeout
                session = URLSession(configuration: cfg)
            } else {
                session = URLSession.shared
            }
            var code = -1; var out: Data? = nil
            if let (d, resp) = try? await session.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
               let c = (resp as? HTTPURLResponse)?.statusCode { code = c; out = d }
            if fresh { session.finishTasksAndInvalidate() }
            if code == 200 { return (code, out) }
            // A 404 is knowledge ONLY when every door says it: a mesh door serves 404 for
            // the accelerator by construction, and one such door in the rotation used to
            // mask the living ones — the share letter died on the first ask (measured 06:28).
            if code == 404 { saw404 = true }
            fresh = true
            if code == 429 { try? await Task.sleep(nanoseconds: 1_200_000_000) }
        }
        return (saw404 ? 404 : -1, nil)
    }

    /// The same move for a caller holding a ready URLRequest (the app's callPost wraps this):
    /// deadline, fresh lane after a failure — one rule, one place.
    /// `lane` — a session the caller owns for the first attempt: a lane the caller can CUT the
    /// instant the network path changes, so a request on a dead socket fails now and not at
    /// its deadline. The retry after a failure opens fresh, as always.
    /// THE ONE DEADLINE OF A POST TO A NODE (13.09): every knock, every call word, every wake
    /// stands this long on a door and not a second more. The caller's wait for a walk is
    /// derived from it (doors × this), never written beside it as a number of its own.
    static let postTimeoutS: TimeInterval = 5
    /// THE DEADLINE OF A CARGO POST GROWS WITH THE CARGO (17.09): a 512 KB chunk is not a knock. The
    /// sheet stood every chunk on the knock's five seconds while the app used the session's sixty,
    /// and on a 2.5 Mbit/s cellular link with three chunks in flight each needed the whole five —
    /// the last three chunks of four files out of five died at their deadline (T1 05:41–05:42Z,
    /// «lettered=1 failed=4»). One rule for both roads: the knock's five seconds plus a second per
    /// sixteen kilobytes — 64 KB waits 9 s, 512 KB waits 37 s.
    static func cargoTimeoutS(bytes: Int) -> TimeInterval { postTimeoutS + Double(max(0, bytes)) / 16_384 }
    static func postRaw(_ req: URLRequest, attempts: Int, timeout: TimeInterval = postTimeoutS, lane: URLSession? = nil) async -> (code: Int, data: Data?) {
        var r = req
        r.timeoutInterval = timeout
        var fresh = false
        for _ in 0..<attempts {
            let session: URLSession
            if fresh {
                let cfg = URLSessionConfiguration.ephemeral
                cfg.timeoutIntervalForRequest = timeout
                session = URLSession(configuration: cfg)
            } else {
                session = lane ?? URLSession.shared
            }
            var code = -1; var out: Data? = nil
            if let (d, resp) = try? await session.data(for: r),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
               let c = (resp as? HTTPURLResponse)?.statusCode { code = c; out = d }
            if fresh { session.finishTasksAndInvalidate() }
            if code == 200 { return (code, out) }
            fresh = true
        }
        return (-1, nil)
    }
}

/// THE OUTGOING QUEUE'S ONE STORE, SHARED BY THE APP AND THE LANDING DOOR (18.09, the author's
/// word: «any letter to you is a window to send yours»). The queue used to be sealed in the app's
/// own defaults under the device key, where no other process could read it. A loud push raises
/// the notification extension with the network for thirty seconds even when the app is gone —
/// and the extension can knock with the waiting letters only if it can read them. So the records
/// live in the app group, sealed under a key of their own in the shared keychain (device-only,
/// after first unlock; [I-1]: ChaCha20-Poly1305, the vault's own cipher). The app is the ONLY
/// writer — atomically, whole; the extension reads, knocks, and leaves its word in a ledger the
/// app absorbs on its next drain. Two writers of one file would be a race by construction.
enum MTOutbox {
    enum Kind: String, Codable {
        case letter, picture, piece, profile, about, ground
        /// State is not a person's word but what the device declares about its owner: name,
        /// face, the owner's own words about themselves (the bio and the link, «about») and the
        /// ground of their page («ground», 25.09).
        /// State has no history: the next value cancels the previous one wholly. A person's word
        /// behaves the other way — each stands on its own and may not be lost.
        var isState: Bool { self == .profile || self == .picture || self == .about || self == .ground }
    }
    struct Item: Codable {
        var to: String; var chat: String; var mid: String; var text: String
        var silent: Bool; var since: Double; var tries: Int; var lastTry: Double
        // Born row-less BY CONSTRUCTION (a reply typed on the banner before the UI woke):
        // exempt from the mirror law M-1 — its row appears later or never, the letter rides.
        var headless: Bool? = nil
        var kind: Kind = .letter
        // The node accepted the envelope (200): the letter is at APNs; the receiver's extension
        // will store it. That is «sent», NOT «delivered»: a push is not guaranteed, the letter
        // stays queued — the only exit is a receipt. Optional: old queue records read as nil.
        var nodeAck: Bool? = nil
        var qt: String? = nil   // quoted preview (rides the envelope tail)
        var qm: String? = nil   // quoted letter's bare mid
        var lp: String? = nil   // link preview card (rides the letter's 7th field)
        /// The text that rides the envelope when it is not the letter itself: a long letter's blob
        /// reference, born once by the app. A process without the blob road seals what stands here.
        var wire: String? = nil
    }
    private static let keyName = "mt.outbox.key"
    private static let aad = "mt.outbox"
    static var fileURL: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) else { return nil }
        let d = base.appendingPathComponent("delivery", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return d.appendingPathComponent("pending.sealed")
    }
    /// No group container (an old profile without the group): the app keeps its old store.
    static var available: Bool { fileURL != nil }
    /// THE QUEUE IN MEMORY WHILE ITS FILE STANDS AS IT WAS (28.09): the delivery engine asks for the whole queue at about thirty
    /// places -- each drain, each retry, each «is this letter still queued» -- and every ask read the file, asked the keychain
    /// for its key, opened the seal and decoded every item: T3's queue weighed 166 KB, all day, in the background too (the iPhone
    /// 17 Pro Max: MetricKit cpu_s=5682 in 4263 s of life). The app keeps the last items it read or wrote under the file's own
    /// stamp -- its number, size and moment -- and asks the disk again only when the stamp moved; a write is atomic and stands a
    /// new file, so any write of any process moves it. The key is kept once read. The extensions keep nothing and read as before.
    private struct Stamp: Equatable { let number: Int; let size: Int; let at: Date }
    private struct Kept { let stamp: Stamp; let items: [Item] }
    private static let keeps = Bundle.main.bundleURL.pathExtension != "appex"
    private static let memo = NSLock()
    private static var kept: Kept?
    private static var keptKey: SymmetricKey?
    /// THE QUEUE'S ERA (03.10): a forgotten person ends it. The app's delivery line keeps its own copy of the queue and writes
    /// it after its turn; a copy of an older era is never written over the wipe.
    private static var eraCount = 0
    static var era: Int { memo.lock(); defer { memo.unlock() }; return eraCount }
    private static func stamp(_ u: URL) -> Stamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: u.path) else { return nil }
        return Stamp(number: (a[.systemFileNumber] as? NSNumber)?.intValue ?? -1,
                     size: (a[.size] as? NSNumber)?.intValue ?? -1,
                     at: (a[.modificationDate] as? Date) ?? .distantPast)
    }
    private static func keep(_ k: SymmetricKey) -> SymmetricKey {
        if keeps { memo.lock(); keptKey = k; memo.unlock() }
        return k
    }
    private static func key(create: Bool) -> SymmetricKey? {
        if keeps { memo.lock(); let held = keptKey; memo.unlock(); if let held { return held } }
        if let d = MontanaKeychain.get(keyName), d.count == 32 { return keep(SymmetricKey(data: d)) }
        guard create else { return nil }
        var b = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &b) == errSecSuccess else { return nil }
        let d = Data(b)
        guard MontanaKeychain.set(keyName, d) else { return nil }
        return keep(SymmetricKey(data: d))
    }
    enum Read { case items([Item]); case empty; case unreadable(bytes: Int) }
    /// «CANNOT READ» IS NOT «EMPTY»: bytes that exist and do not open are named, never overwritten.
    static func read() -> Read {
        guard let u = fileURL, let now = stamp(u) else { return .empty }
        if keeps {
            memo.lock(); let held = kept; memo.unlock()
            if let held, held.stamp == now { return .items(held.items) }
        }
        guard let raw = try? Data(contentsOf: u) else { return .empty }
        guard let k = key(create: false),
              let box = try? ChaChaPoly.SealedBox(combined: raw),
              let plain = try? ChaChaPoly.open(box, using: k, authenticating: Data(aad.utf8)),
              let items = try? JSONDecoder().decode([Item].self, from: plain) else { return .unreadable(bytes: raw.count) }
        if keeps { memo.lock(); kept = Kept(stamp: now, items: items); memo.unlock() }
        return .items(items)
    }
    /// A queue sealed under a given key -- the queue of a person on the shelf (MTShelfPost), whose key rides their seat's record.
    static func open(_ raw: Data, key: Data) -> [Item]? {
        guard key.count == 32, let box = try? ChaChaPoly.SealedBox(combined: raw),
              let plain = try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: Data(aad.utf8)) else { return nil }
        return try? JSONDecoder().decode([Item].self, from: plain)
    }
    @discardableResult
    static func write(_ items: [Item]) -> Bool {
        guard let u = fileURL, let k = key(create: true),
              let plain = try? JSONEncoder().encode(items),
              let sealed = try? ChaChaPoly.seal(plain, using: k, authenticating: Data(aad.utf8)).combined else { return false }
        let wrote = (try? sealed.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
        if keeps {
            // The file standing now is ours when its size is our seal's; anything else is read from the disk next time.
            let now = wrote ? stamp(u) : nil
            let ours = now.map { $0.size == sealed.count } ?? false
            memo.lock(); kept = ours ? now.map { Kept(stamp: $0, items: items) } : nil; memo.unlock()
        }
        return wrote
    }
    /// The person is forgotten: the queue, its key and the door's ledger go with them.
    static func wipe() {
        if let u = fileURL { try? FileManager.default.removeItem(at: u) }
        MontanaKeychain.delete(keyName)
        MontanaKeychain.delete(ledgerKey)
        memo.lock(); kept = nil; keptKey = nil; eraCount += 1; memo.unlock()
    }

    // ── the landing door's word to the app ──
    private static let ledgerKey = "nseKnocked"
    /// The extension boxed this letter at a node: the app marks it «sent» on its next drain.
    static func noteExtensionKnock(_ mid: String) {
        var m: [String: Double] = [:]
        if let d = MontanaKeychain.get(ledgerKey), let x = try? JSONDecoder().decode([String: Double].self, from: d) { m = x }
        m[mid] = Date().timeIntervalSince1970
        if m.count > 100 {
            for (k, _) in m.sorted(by: { $0.value < $1.value }).prefix(m.count - 100) { m.removeValue(forKey: k) }
        }
        if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set(ledgerKey, d) }
    }
    static func takeExtensionKnocks() -> [String: Double] {
        guard let d = MontanaKeychain.get(ledgerKey),
              let m = try? JSONDecoder().decode([String: Double].self, from: d), !m.isEmpty else { return [:] }
        MontanaKeychain.delete(ledgerKey)
        return m
    }
}
