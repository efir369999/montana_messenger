import Foundation
import MontanaBindings
import CryptoKit

/// The four quantities of delivery, exactly as Canon states them. One place computes them, so a
/// second implementation reading the same document lands on the same bytes.
///
///     tag(shared_secret, W)                  = SHA-256("mt-tag"        || 0x00 || shared_secret || W_8B_LE)[0..16]
///     step_label(handshake_secret, W)        = SHA-256("mt-step"       || 0x00 || handshake_secret || W_8B_LE)[0..16]
///     relay_seal(owner_secret, label)        = SHA-256("mt-relay-seal" || 0x00 || owner_secret || label)[0..16]
///     owner_ref(owner_secret, shared_secret) = SHA-256("mt-owner-ref"  || 0x00 || owner_secret || shared_secret)[0..16]
///
/// The NUL is part of the primitive, never an option: a hash without its domain is a different
/// hash, and two implementations that disagree here do not share a network.
enum MTPipe {
    /// The one composition of the set: `SHA-256(domain || 0x00 || parts…)`. Every label of this tree
    /// is built by it and by nothing else — a second place writing the same shape drifts the day one of
    /// them is corrected, and two labels that differ by a byte are two protocols. It stands in
    /// MTNodeWire, compiled into the extensions too, so the pipe's one owner (MTPipeKey) builds by it.
    static func domained(_ domain: String, _ parts: [Data]) -> Data { MTNodeWire.domained(domain, parts) }

    static func windowLE(_ w: UInt64) -> Data { MTNodeWire.windowLE(w) }

    /// The length of one window, and the only place it is stated. A label, a rendezvous and an
    /// announce all count time by this number: two of them holding their own copy is how one of
    /// them silently starts counting a different minute.
    static let windowSeconds: UInt64 = 60

    static func window(_ at: Date = Date()) -> UInt64 {
        UInt64(at.timeIntervalSince1970) / windowSeconds
    }

    /// Clocks drift, so a side accepts the neighbouring windows too. The tolerance is one value for
    /// the whole tree: written twice, it becomes two different tolerances the first time it changes.
    static func windows(around w: UInt64) -> [UInt64] { [w &- 1, w, w &+ 1] }

    static func windows(at: Date = Date()) -> [UInt64] { windows(around: window(at)) }

    /// The tag of a secret two hold: where a letter is deposited in this window, and nowhere else. A pipe's own tag is asked of
    /// its owner (MTPipeKey.tag); this one takes the channel secret two machines established (MontanaRendezvous).
    static func tag(sharedSecret: Data, window: UInt64) -> Data { MTNodeWire.tag(sharedSecret: sharedSecret, window: window) }

    /// The label of one step, from the secret two neighbouring machines share.
    static func stepLabel(handshakeSecret: Data, window: UInt64) -> Data {
        domained("mt-step", [handshakeSecret, windowLE(window)]).prefix(16)
    }

    /// The key that seals a letter body INSIDE the pipe. A value of the set, not our invention:
    ///
    /// «The inner seal — one pipe wide. Its key is `SHA-256("mt-pipe-key" || 0x00 || shared_secret
    /// || W_8B_LE)` … No hop holds that key, so the quantities a delivery needs of itself … live
    /// where only the two correspondents read them.»
    ///
    /// Exactly two hold it, so a Poly1305 seal under it IS proof of the sender, and a signature beside
    /// it is unnecessary: a signature would put a permanent public key onto the wire -- exactly the
    /// value the set abolishes. The key of a minute is the pipe owner's to derive (MTPipeKey.bodyKey).

    /// Seal a letter body with the pipe key. The core draws the nonce and lays it before the ciphertext.
    static func sealBody(_ body: Data, sharedSecret: MTPipeKey, window w: UInt64 = window()) -> Data? {
        MontanaDirect.seal(key: sharedSecret.bodyKey(window: w), body)
    }

    /// Open a letter body. The accepted windows are the same as for the label: clocks drift, and a
    /// letter sealed on a minute boundary must open for the one whose minute has already turned.
    static func openBody(_ sealed: Data, sharedSecret: MTPipeKey, at: Date = Date()) -> Data? {
        for w in windows(at: at) {
            if let p = MontanaDirect.open(key: sharedSecret.bodyKey(window: w), sealed) {
                return p
            }
        }
        return nil
    }

    /// A letter read from the node box: the node names the minute it took the letter, the seal
    /// wears the sender's minute — the walk goes back from the node's (MTNodeWire, the one owner).
    static func openBoxed(_ sealed: Data, sharedSecret: MTPipeKey, at: UInt64) -> (plain: Data, back: Int)? {
        MTNodeWire.openBoxed(sealed, secret: sharedSecret, at: at)
    }

    /// The seal a hop attaches to prove distinctness of owners inside one delivery. Two machines of
    /// one owner produce the same seal for the same step and collapse into one step of distinctness.
    static func relaySeal(ownerSecret: Data, label: Data) -> Data {
        domained("mt-relay-seal", [ownerSecret, label]).prefix(16)
    }

    /// The reference by which one sender tells two owners apart among its own entries. The same
    /// owner gives two senders references that do not join, so nothing persistent is created.
    static func ownerRef(ownerSecret: Data, sharedSecret: Data) -> Data {
        domained("mt-owner-ref", [ownerSecret, sharedSecret]).prefix(16)
    }

    /// The holder of a tag: the machine whose commitment is the least one standing above the tag,
    /// and the lowest of all when none stands above it — the ring closes rather than ending.
    /// Comparison runs over the first sixteen bytes of a commitment against the tag.
    static func holder(of tag: Data, among commitments: [Data]) -> Data? {
        guard !commitments.isEmpty else { return nil }
        let key = tag.prefix(16)
        let sorted = commitments.sorted { $0.prefix(16).lexicographicallyPrecedes($1.prefix(16)) }
        for c in sorted where key.lexicographicallyPrecedes(c.prefix(16)) { return c }
        return sorted.first
    }

    /// The number two people read to each other to be sure nobody stands between them.
    ///
    /// Canon fixes the derivation: `h = SHA-256("mt-safety" || 0x00 || h)` repeated
    /// `fingerprint_iterations` times, the first thirty bytes read as six groups of five, each
    /// group reduced modulo 100000. The count is fixed for everyone — a different count is a
    /// comparison that cannot succeed.
    ///
    /// The input is the secret of the correspondence, because this client holds nothing else that
    /// could serve: there is no identifier of a person here, and the peer's identity key is not a
    /// quantity a correspondence exposes. It is the right input for what the screen is for — a
    /// stranger in the middle would have had to replace exactly this value, and the number changes
    /// the moment they do. Named rather than smoothed: the set derives it from an identity key,
    /// and that difference is written down in the internal audit.
    static var fingerprintIterations: Int { MTNodeWire.fingerprintIterations }

    /// The hash the thirty digits are read from, all thirty-two bytes of it (Canon, «The fingerprint compared out of band»: h after
    /// fingerprint_iterations). It is also what a testimony of a call names its addressee by (Canon, «The testimony of a call»;
    /// MTFabric), so the number and the testimony stand on one derivation, never two -- MTNodeWire's, which the pipe's owner
    /// keeps a correspondence's material by (MTPipeKey.kept).
    static func fingerprintMaterial(_ key: Data) -> Data { MTNodeWire.fingerprintMaterial(key) }

    static func fingerprint(secret: Data) -> String? {
        guard secret.count == 32 else { return nil }
        return fingerprint(material: fingerprintMaterial(secret))
    }

    /// The thirty digits read off a material already derived -- the one a correspondence keeps from its birth (MTPipeKept).
    static func fingerprint(material h: Data) -> String? {
        guard h.count == 32 else { return nil }
        let groups = (0 ..< 6).map { i -> String in
            let g = h.subdata(in: h.startIndex + i * 5 ..< h.startIndex + i * 5 + 5)
            let v = g.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } % 100_000
            return String(format: "%05llu", v)
        }
        return groups.joined()
    }

    /// The owner branch of a seed: `HKDF-Expand(master_seed, "mt-owner-key", 32)`. A person copies
    /// this one branch onto every machine they run, and it exists for a single reason — the seal of
    /// a step must collapse to ONE value for one owner, or a path crossing two machines of one owner
    /// would count as two owners and the bound on distinct owners would protect nothing.
    static func ownerSecret(masterSeed: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let role = Array("mt-owner-key".utf8)
        let rc = masterSeed.withUnsafeBytes { m -> Int32 in
            role.withUnsafeBufferPointer { r -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_mldsa_seed_for_role(mb, r.baseAddress, role.count, &out)
            }
        }
        return rc == 0 ? Data(out) : nil
    }

    /// The frozen vectors of the Canon, stated in the document and reproduced here. A core or a
    /// derivation that drifts by one byte fails this before a single letter is written — which is
    /// what makes the values above quantities and not code.
    static func agreesWithCanon() -> Bool {
        let shared = Data(repeating: 0x44, count: 32)
        guard tag(sharedSecret: shared, window: 1000).montanaHexString == "1d99467017fe1d0cc7c7ba29df6fd1b6",
              tag(sharedSecret: shared, window: 1001).montanaHexString == "c146445f67c990e25256dd88dfb39a49",
              tag(sharedSecret: Data(repeating: 0x55, count: 32), window: 1000).montanaHexString == "783b2b17dffaab016d1aca852f60ea3e" else { return false }

        guard stepLabel(handshakeSecret: Data(repeating: 0x51, count: 32), window: 1000).montanaHexString == "4b8cb5c6442a52d0750bfb4fac0ba39d",
              stepLabel(handshakeSecret: Data(repeating: 0x52, count: 32), window: 1000).montanaHexString == "401d8ab71a2e2554ab30c11aab1ae97d",
              stepLabel(handshakeSecret: Data(repeating: 0x51, count: 32), window: 1001).montanaHexString == "1cc3ac539a8b1d2701e489455a8b04d5" else { return false }

        let owner = Data(repeating: 0x99, count: 32)
        guard relaySeal(ownerSecret: owner, label: Data(repeating: 0xAA, count: 16)).montanaHexString == "2c2231f087682d4daef313938a2da5e0",
              relaySeal(ownerSecret: owner, label: Data(repeating: 0xBB, count: 16)).montanaHexString == "3e83b1e1610e48bfc13929a602617d79" else { return false }

        // The key that seals a letter body. The vector stands on a secret of THIRTY-TWO DISTINCT bytes
        // and on a window with bits at both ends (0x0102030405060708) -- otherwise a wrong
        // implementation passes it. What it rejects is named: an implementation without the domain
        // separator (1d1f4bf4...), one laying the window most-significant byte first (11178eee...), one
        // reversing the secret (c04889ba...) and one taking the label domain instead of the key domain
        // (de05839d...). The values are derived from the set formula apart from this code, not read off it.
        let bodySecret = Data((0..<32).map { UInt8($0) })
        guard Data(MTNodeWire.sealKey(stepSecret: bodySecret, window: 0x0102030405060708)).montanaHexString
                  == "e55fbc1e0f95c4fe012b476c4dd1a51c9455e24641248f4f1557ed57f8c14f35" else { return false }

        // The body key of a minute, the walk of the pipe secret by the day, the root and the author field stand with the secret
        // in its one owner, and so do their vectors (MTPipeKey.agreesWithCanon).
        guard MTPipeKey.agreesWithCanon() else { return false }

        guard ownerRef(ownerSecret: owner, sharedSecret: shared).montanaHexString == "f4f72dafb742470e49defbd3c2326c27",
              ownerRef(ownerSecret: owner, sharedSecret: Data(repeating: 0x45, count: 32)).montanaHexString == "d24f63a8c1220ea9c176ec706b8a256f" else { return false }

        let ring = [Data(repeating: 0x10, count: 32), Data(repeating: 0x90, count: 32)]
        guard holder(of: Data(montanaHex: "45468cdd9bcdebe6f622c46257c27fe3") ?? Data(), among: ring)
                  == ring[1],
              holder(of: Data(repeating: 0xFF, count: 16), among: ring) == ring[0] else { return false }
        return true
    }
}


// What a correspondence derives from its secret once and for good (MTPipeKept) is made by the secret's one owner, MTPipeKey.


/// The secret a correspondence stands on, kept where the tag that stands on it is computed.
///
/// The set states it outright: the secret a first letter establishes is the one **on which every
/// later tag of that correspondence stands**. It is not the secret of a channel between two
/// machines — that one does not exist where it is needed most, because a letter that has to be
/// passed through a third machine is precisely the letter whose two ends hold no channel. It is
/// not derived from an address either: an address is what leaves.
///
/// One place, sealed at rest under the key of the device, and it never travels. The book holds each pipe as its one owner
/// does (MTPipeKey) and hands out that value, never the bytes: what a pipe derives is asked of it (24.10.2026).
enum MTPipeBook {
    private static let storeKey = "pipeSecrets"
    private static var cache: [String: MTPipeKey]?
    /// The UTC day the book in memory stands floored for (0 before the first read).
    private static var cacheDay: UInt64 = 0
    /// Whether the clock guard withheld the first floor at the last read: the next read asks it again (decision 188, #38).
    private static var cacheHeld = false
    /// When the vault last refused to seal the book (nil while the disk holds what memory holds). Memory keeps the floored copy
    /// and hands it out floored; a later read seals it again, at most once a minute (a locked device must not flood the trace).
    private static var cacheRefusedAt: Date?

    /// THE LOCK GUARDS MEMORY ONLY. The store — cipher, keychain, preferences, the diary — is
    /// read and written OUTSIDE it (14.09: the main thread stood 200 s on this lock in the chat's
    /// body while another thread held it inside the store; the screen froze whole). A slow store
    /// now slows one reader; nobody waits on a lock for I/O.
    private static let cacheLock = NSLock()
    private static func load() -> [String: MTPipeKey] {
        let day = MTNodeWire.dayWindow()
        cacheLock.lock()
        let hit = cache, hitDay = cacheDay, hitHeld = cacheHeld
        let retry = cacheRefusedAt.map { Date().timeIntervalSince($0) >= 60 } ?? false
        cacheLock.unlock()
        if let hit {
            if hitDay == day, !hitHeld, !retry { return hit }
            // THE BOOK IN MEMORY WALKS WITH THE DAY (25.10.2026, decision 191): memory holds the book as floored for the day
            // it is read on, as the disk does. A new day floors what memory holds before anyone reads it -- by the day the
            // clock guard gives (decision 188, #38), asked again at every read while it withholds the first floor.
            let fd = floorDay(for: hit)
            let walked = hit.mapValues { $0.floored(day: fd) }
            cacheLock.lock()
            if cacheDay == hitDay { cache = walked; cacheDay = day; cacheHeld = fd < day }
            cacheLock.unlock()
            if walked != hit { floorStore(walked) } else if retry { store(walked) }   // a refused write is sealed again (#38, case 13)
            if fd >= MTPipeKey.eraseDay { MontanaArchive.dropSecretHeads(day: fd) }   // after the floor heads, on the same queue
            return walked
        }
        // A decryption failure is NOT cached: a thread race at process start cached emptiness forever --
        // the whole pipe book "vanished", live letters fell with send_refused no_secret /
        // enqueue_drop no-pipe (22:10:30). Truly empty -- we re-read cheaply; empty from a fault --
        // the next attempt sees the truth.
        let t0 = Date()
        guard let d = MontanaLocalVault.getDecrypted(storeKey) else { return [:] }
        let raw = MTPipeKey.book(d, day: 0)   // as sealed, before the day's floor: the guard sees whether a key is floored
        let fd = floorDay(for: raw)
        let m = raw.mapValues { $0.floored(day: fd) }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if ms > 500 { MontanaTrace.mark("pipes_read_slow", "ms=\(ms) main=\(Thread.isMainThread ? 1 : 0)") }
        cacheLock.lock()
        let first = cache == nil
        if first { cache = m; cacheDay = day; cacheHeld = fd < day }   // the first reader publishes; a parallel reader's copy is the same book
        let now = cache ?? m
        cacheLock.unlock()
        // THE BOOK ERASES ITSELF BY THE DAY (OZ1, decision 126): the pipes were read floored (MTPipeKey.book); a vault that still
        // holds more -- the established secret from 03.11.2026 UTC, a floor of an earlier day -- is sealed again as read, once,
        // and the archive's head of each correspondence is written in the floor's form, so a restore by the words never meets
        // the secret again. The index stays: a floor derives every tag of the days it keeps byte for byte.
        if first, MTPipeKey.lags(d, day: fd) { floorStore(now) }
        // the archive's old heads with the secret leave the folders' logs, once, after the floor heads above (the same queue)
        if first, fd >= MTPipeKey.eraseDay { MontanaArchive.dropSecretHeads(day: fd) }
        return now
    }

    private static func floorStore(_ m: [String: MTPipeKey]) {
        store(m)
        let refs = m.filter { conv, pipe in pipe.reference == conv }.keys
        for conv in refs { MontanaArchive.writeHead(convRef: conv, legacy: []) }
        MontanaTrace.mark("pipes_floored", "n=\(m.count) heads=\(refs.count)")
    }

    @discardableResult
    private static func store(_ m: [String: MTPipeKey]) -> Bool {
        // The seal refused (the key is absent at this instant) -- the cache is NOT replaced: otherwise
        // the process would live with a book that is not on disk, and the next writer would immortalise emptiness.
        let fd = floorDay(for: m)
        guard let d = MTPipeKey.form(m, day: fd), MontanaLocalVault.setEncrypted(storeKey, d) else {
            MontanaTrace.mark("pipes_write_refused", "n=\(m.count)")
            cacheLock.lock(); cacheRefusedAt = Date(); cacheLock.unlock()
            return false
        }
        // Memory holds what the disk holds: the book as floored on the day (a pipe born from eraseDay is floored at its birth,
        // and the confirmation its first letter carries was kept beside the ciphertext before it -- rememberConfirm).
        let day = MTNodeWire.dayWindow()
        let held = m.mapValues { $0.floored(day: fd) }
        cacheLock.lock(); cache = held; cacheDay = day; cacheHeld = fd < day; cacheRefusedAt = nil; cacheLock.unlock()
        return true
    }

    // ── THE CLOCK GUARD OF THE FIRST FLOOR, SEALED BESIDE THE BOOK (decision 188, #38, 25.10.2026) ─────────────────────────────
    // The rule is MTFloorGuard's (MTPipeKey.swift); here its state lives: M, H and Hc sealed under the device key beside the book,
    // one of the seat's keys (SeedScope.seatKeys), never in the archive -- a restore by the words starts with none and takes c
    // from the nodes. A record that does not open now is not replaced: the guard decides on a fresh state and writes nothing.
    private static let guardKey = "pipeFloorGuard"
    private static let guardLock = NSLock()   // LOCK-OK: the guard's state and this run's node day, in memory
    private static var guardState: MTFloorGuard?
    private static var heardDay: UInt64?        // the day of a node Date heard in this run (c of the run)
    private static var heldTold: [UInt64]?      // d, c, left of this run's last floor_held
    private static var floorDayNow: UInt64 = 0  // the day the book last floored by
    /// The sealed record, read outside the lock; nil while it lies on the disk and does not open.
    private static func guardRead() -> MTFloorGuard? {
        guardLock.lock(); let hit = guardState; guardLock.unlock()
        if let hit { return hit }
        let g: MTFloorGuard
        if UserDefaults.standard.data(forKey: guardKey) == nil {
            g = MTFloorGuard()
        } else {
            guard let d = MontanaLocalVault.getDecrypted(guardKey),
                  let read = try? JSONDecoder().decode(MTFloorGuard.self, from: d) else { return nil }
            g = read
        }
        guardLock.lock()
        if guardState == nil { guardState = g }
        let now = guardState ?? g
        guardLock.unlock()
        return now
    }
    private static func guardWrite(_ g: MTFloorGuard) {
        if let d = try? JSONEncoder().encode(g) { _ = MontanaLocalVault.setEncrypted(guardKey, d) }
    }
    /// A node's Date was heard (MontanaWakePush.learnSkew): it is the confirmed day of this run, and M rises to it.
    static func heard(nodeDate: Date) {
        let day = UInt64(max(0, nodeDate.timeIntervalSince1970)) / 86400
        let read = guardRead()
        guardLock.lock()
        heardDay = max(heardDay ?? 0, day)
        var g = guardState ?? read ?? MTFloorGuard()
        let rose = g.heard(day)
        if read != nil { guardState = g }
        guardLock.unlock()
        if rose, read != nil { guardWrite(g) }
    }
    /// The day a restore by the words floors the heads it reads by: the later of the device day and M (decision 188, E).
    static func recoveryDay() -> UInt64 {
        MTPipeKey.recoveryDay(device: MTNodeWire.dayWindow(), mark: guardRead()?.mark)
    }
    /// The day the book floors by now: the device day, or the day before eraseDay while the guard withholds the first floor.
    /// The archive's heads and the extensions' mirror are written by it, as the book is.
    static func floorDay() -> UInt64 {
        _ = load()
        guardLock.lock(); let fd = floorDayNow; guardLock.unlock()
        return fd == 0 ? MTNodeWire.dayWindow() : fd
    }
    /// The guard asked for a book about to be floored: the day it floors by. A book with no pipe is not asked (the rule is
    /// asked when the first pipe arrives, and H does not start on an empty book).
    private static func floorDay(for book: [String: MTPipeKey]) -> UInt64 {
        let d = MTNodeWire.dayWindow()
        guard !book.isEmpty else {
            guardLock.lock(); floorDayNow = d; guardLock.unlock()
            return d
        }
        let floored = book.values.contains { $0.isFloored }
        let read = guardRead()
        guardLock.lock()
        var g = guardState ?? read ?? MTFloorGuard()
        let before = g, heard = heardDay
        let v = g.decide(day: d, heard: heard, floored: floored)
        let line = MTFloorGuard.line(v, day: d, confirmed: g.confirmed(heard: heard), told: &heldTold)
        if read != nil { guardState = g }
        let fd = MTFloorGuard.floorDay(v, day: d)
        floorDayNow = fd
        guardLock.unlock()
        if g != before, read != nil { guardWrite(g) }
        if let line { MontanaTrace.mark(line.0, line.1) }
        return fd
    }

    /// Remember the secret a first letter established. Written once per correspondence: a second
    /// writing would mean two secrets for one pipe, and the two ends would compute two tags.
    /// The answer is explicit: a caller that cannot store the secret cannot send, and learning that
    /// at the moment of sending is how a letter goes missing without anyone being told.
    private static func remember(_ secret: MTPipeKey, for conv: String) -> Bool {
        if !secret.isWhole || conv.isEmpty { return false }
        guard MontanaDeviceKey.key != nil else { MontanaTrace.mark("pipes_read_locked", "remember"); return false }
        var m = load()
        // ONE PIPE MET AGAIN (decision 188, #37): from eraseDay the book holds the floor, and a card letter brings the whole secret
        // again, an archive head a floor of another day. Two keys are one pipe only when both, walked to the later floor day,
        // give the same whole floor (MTPipeKey.samePipe) -- never the reference alone. The store keeps the further floor; a whole
        // secret met again is floored before the comparison and never written back.
        if let existing = m[conv] {
            guard existing.samePipe(secret) else { return false }
            let keep = existing.further(secret)
            if keep != existing { m[conv] = keep; store(m) }
            return true
        }
        m[conv] = secret
        store(m)
        dropIndex()
        return true
    }

    /// The pipe of a correspondence as its one owner holds it: a reference that answers what the pipe derives -- the key of a
    /// minute, the label of a day, the tag of a window, an item's blind and author field -- and hands out no byte of the secret.
    static func key(for conv: String) -> MTPipeKey? { load()[conv] }

    // -- what a correspondence keeps of its secret for good -------------------
    // THE PERMANENT DERIVATIVES ARE BORN WITH THE PIPE (22.10.2026, OZ 3 phase 2 step 1). The walk erases the established
    // secret only if nothing reads it after birth; what does not walk with the day -- the root, the fingerprint's
    // material, the face's name and key, the pair's tag -- is derived here once and kept beside the secret, sealed alike.
    // A pipe born before this build gets its record from the secret it still holds, on the first question.
    private static let keptKey = "pipeKept"
    private static var keptCache: [String: MTPipeKept]?

    /// nil: the map lies on the disk and does not open now -- a writer must not replace it with what it holds in hand.
    private static func keptLoad() -> [String: MTPipeKept]? {
        cacheLock.lock()
        let hit = keptCache
        cacheLock.unlock()
        if let hit { return hit }
        let m: [String: MTPipeKept]
        if UserDefaults.standard.data(forKey: keptKey) == nil {
            m = [:]
        } else {
            guard let d = MontanaLocalVault.getDecrypted(keptKey),
                  let read = try? JSONDecoder().decode([String: MTPipeKept].self, from: d) else {
                MontanaTrace.mark("pipes_kept_unreadable", "")
                return nil
            }
            m = read
        }
        cacheLock.lock()
        if keptCache == nil { keptCache = m }
        let now = keptCache ?? m
        cacheLock.unlock()
        return now
    }

    private static func keptStore(_ m: [String: MTPipeKept]) {
        guard let d = try? JSONEncoder().encode(m), MontanaLocalVault.setEncrypted(keptKey, d) else {
            MontanaTrace.mark("pipes_kept_write_refused", "n=\(m.count)")
            return
        }
        cacheLock.lock(); keptCache = m; cacheLock.unlock()
    }

    static func kept(for conv: String) -> MTPipeKept? {
        let m = keptLoad()
        if let k = m?[conv], k.ref != nil { return k }
        guard let s = key(for: conv), s.isWhole else { return m?[conv] }
        let k = s.kept()
        if var m, MontanaDeviceKey.key != nil { m[conv] = k; keptStore(m) }
        return k
    }

    /// Every held pipe's record in one writing: the first launch after the record grew its name fills them all at once,
    /// not one sealed write per pipe on the thread that asks.
    static func keepAll() {
        guard var m = keptLoad(), MontanaDeviceKey.key != nil else { return }
        let lacking = load().filter { conv, s in s.isWhole && m[conv]?.ref == nil }
        guard !lacking.isEmpty else { return }
        for (conv, s) in lacking { m[conv] = s.kept() }
        keptStore(m)
    }

    private static func forgetKept(_ conv: String) {
        guard var m = keptLoad(), m.removeValue(forKey: conv) != nil else { return }
        keptStore(m)
    }

    /// The identity left: the book in memory leaves with it. The disk copy is sealed under the
    /// device key that SeedScope resets, so only the cache could have carried the previous
    /// person's pipes into the next person's book — and re-sealed them there on the first write.
    static func forgetAll() {
        cacheLock.lock(); cache = nil; keptCache = nil; cacheHeld = false; cacheLock.unlock()
        guardLock.lock(); guardState = nil; heldTold = nil; floorDayNow = 0; guardLock.unlock()   // the guard is the seat's, as the book
        dropIndex()
    }

    /// A correspondence this device can answer for. It replaces the question the tree used to ask —
    /// «is this string a Montana address» — which asked about the shape of a public name instead of
    /// about possession, and which no string could ever satisfy. Reachability is proven, not named.
    static func holds(_ conv: String) -> Bool { key(for: conv) != nil }

    /// Every correspondence this device answers for. The list never leaves the device.
    static func all() -> [String] { Array(load().keys) }

    /// The death of a pipe. The book could not forget at all: every trial introduction stayed in it
    /// forever, hundreds of dead pipes swelled the wake registration to a node refusal (413) -- and the
    /// refusal buried the LIVE subscriptions. A deleted chat takes its pipe with it.
    static func forget(_ conv: String) {
        // One does not build on a read failure: an empty book with a live disk means "the store is
        // closed for an instant" -- the burial waits for the next pass instead of rewriting the book with emptiness.
        guard MontanaDeviceKey.key != nil else { MontanaTrace.mark("pipes_read_locked", "forget"); return }
        var m = load()
        if m.removeValue(forKey: conv) != nil { store(m) }
        forgetKept(conv)
        unmarkDying(conv)
        forgetFirst(conv)
        forgetRoot(conv)                       // the meeting point does not outlive the pipe
        MontanaMeeting.forgetConv(conv)        // and neither does the meeting memory (23:06: a tap resurrected a dead one)
        touchLock.lock(); touchMem.removeValue(forKey: conv); touchLock.unlock()
        var t = touchedLoad()
        if t.removeValue(forKey: conv) != nil { touchedStore(t) }
        dropIndex()
    }

    // -- freshness: when the pipe last lived --------------------------------
    // Wake registration stands up in parts when the node cuts the body by size -- and which
    // subscriptions survive used to be decided by the alphabet. Now life decides: fresh pipes first.
    private static let touchedKey = "pipeTouched"
    private static let touchLock = NSLock()
    private static var touchMem: [String: Double] = [:]   // no more than once an hour per pipe

    private static func touchedLoad() -> [String: Double] {
        MontanaLocalVault.getDecrypted(touchedKey)
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }
    private static func touchedStore(_ m: [String: Double]) {
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(touchedKey, d) }
    }

    /// Returns true when the hour mark advanced — the first sign of life in an hour.
    @discardableResult
    static func touch(_ conv: String) -> Bool {
        guard !conv.isEmpty else { return false }
        let now = Date().timeIntervalSince1970
        touchLock.lock()
        let last = touchMem[conv] ?? 0
        if now - last < 3600 { touchLock.unlock(); return false }
        touchMem[conv] = now
        touchLock.unlock()
        var t = touchedLoad(); t[conv] = now; touchedStore(t)
        return true
    }

    /// When a conversation last gave a sign of life. A sign is proof that the other side EXISTS: the
    /// birth of a pipe (the introduction happened), an opened incoming letter, a channel that stood up
    /// to it, an arrived receipt. Our own sending is not a sign -- one can write into emptiness too.
    static func aliveAt(_ conv: String) -> Double? { touchedLoad()[conv] }

    /// Pipes by freshness: the living first, the mute to the tail. The order of registering subscriptions.
    static func allByFreshness() -> [String] {
        let t = touchedLoad()
        return load().keys.sorted { (t[$0] ?? 0, $0) > (t[$1] ?? 0, $1) }
    }

    // -- a dying pipe: the secret lives for exactly the last letter ----------
    // "Delete for both" sends the burial notice OVER THIS PIPE -- by killing it at the moment the chat
    // is deleted, the sender leaves the notice no road (precedent: the letter was not even born, holds=false).
    // A dying pipe is not registered for the wake and is buried by the notice receipt or by term.
    private static let dyingKey = "pipeDying"
    private static func dyingLoad() -> Set<String> {
        Set(MontanaLocalVault.getStringArray(dyingKey) ?? [])
    }
    static func markDying(_ conv: String) {
        guard !conv.isEmpty, holds(conv) else { return }
        var d = dyingLoad(); guard !d.contains(conv) else { return }
        d.insert(conv); MontanaLocalVault.setStringArray(dyingKey, Array(d))
    }
    static func isDying(_ conv: String) -> Bool { dyingLoad().contains(conv) }
    static func dyingAll() -> [String] { Array(dyingLoad()) }
    static func unmarkDying(_ conv: String) {
        var d = dyingLoad()
        if d.remove(conv) != nil { MontanaLocalVault.setStringArray(dyingKey, Array(d)) }
    }

    /// Pipes entitled to wake subscriptions: living, not dying.
    static func registrable() -> [String] { registrable(refusing: ChatStore.refusedNow()) }
    /// The same, with the refused names already in hand: the wake registration walks this book off the main thread
    /// now (28.09), and the question «does this device refuse the person» is asked once, where the store lives.
    static func registrable(refusing refused: Set<String>) -> [String] {
        let d = dyingLoad()
        return allByFreshness().filter { !d.contains($0) && !refused.contains($0) }   // a blocked person wakes nobody
    }

    /// The contact key of a name this device has already met: knowing it costs no reach into the
    /// space of slots, and it makes a second letter to that name as cheap as a first. It is kept
    /// sealed under the key of the device and leaves it under no circumstance.
    private static let namesKey = "pipeNameRoots"
    private static var namesCache: [String: Data]?

    private static func namesLoad() -> [String: Data]? {
        // The same illness, the same rule: a decryption failure is not cached (class 22.08), and
        // the store is read outside the lock (class 14.09).
        cacheLock.lock()
        let hit = namesCache
        cacheLock.unlock()
        if let hit { return hit }
        guard let d = MontanaLocalVault.getDecrypted(namesKey) else { return nil }
        let m = (try? JSONDecoder().decode([String: Data].self, from: d)) ?? [:]
        cacheLock.lock()
        if namesCache == nil { namesCache = m }
        let now = namesCache ?? m
        cacheLock.unlock()
        return now
    }

    static func contactRoot(forName n: String) -> Data? { namesLoad()?[n] }

    @discardableResult
    static func rememberName(_ n: String, contactRoot root: Data) -> Bool {
        if n.isEmpty || root.count != 1184 { return false }
        var m = namesLoad() ?? [:]
        m[n] = root
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(namesKey, d) }
        cacheLock.lock(); namesCache = m; cacheLock.unlock()
        return true
    }

    // The local name of a correspondence -- what this device files a conversation under once an address is no longer allowed
    // to be that name -- is derived from the secret the two of them hold, so both devices of one person arrive at the same one,
    // and it NEVER leaves the device (MTPipeKey.reference). It is not an address, it cannot be handed out, and a stranger
    // holding it learns nothing they could reach anyone with.

    /// Establish a correspondence from the secret its first letter produced: the device files it
    /// under a name of its own making and answers for its tags from that moment.
    /// THE BIRTH OF A CORRESPONDENCE SEALS ITS SECRET UNDER THE SEED (15.10.4). The secret is
    /// born here and derives from nothing; the archive folder sealed under the seed is the one
    /// place it may outlive the device key, and «Forget this device» wipes the book. Sealing at
    /// load, under conditions and a once-per-folder marker, left T2 without a single sealed
    /// secret in its whole life (07.09: archive_restore headed=0) — and a correspondence whose
    /// secret is gone is dead on both sides until a new first contact. The point of birth is the
    /// one place every secret passes; `seal: false` is for the two callers that are not a
    /// birth: the twin reference (no correspondence, no folder) and the restore itself.
    static func establish(secret: Data, seal: Bool = true) -> String? { establish(pipe: MTPipeKey(secret), seal: seal) }
    /// The same birth for a pipe already held as its owner holds it: one met on the shelf, one restored from the archive.
    static func establish(pipe: MTPipeKey, seal: Bool = true) -> String? {
        guard let ref = pipe.reference else { return nil }
        let born = key(for: ref) == nil
        guard remember(pipe, for: ref) else { return nil }
        _ = kept(for: ref)
        touch(ref)
        if seal, born { MontanaArchive.writeHead(convRef: ref, legacy: []) }   // the folder is the archive's to resolve, on its queue
        return ref
    }

    /// The ciphertext a first letter must carry, kept until that letter is answered.
    ///
    /// A correspondence begins when one side encapsulates to the other's contact key. The side that
    /// did it holds the secret at once; the other cannot derive it until the ciphertext reaches
    /// them, and it reaches them inside the first letter. Kept sealed like the secrets beside it,
    /// and dropped the moment the other side answers — after that both hold the secret and the
    /// ciphertext is a copy of something already spent.
    private static let firstKey = "pipeFirstCiphertexts"

    private static func firsts() -> [String: Data] {
        guard let d = MontanaLocalVault.getDecrypted(firstKey),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }
    /// THE CORRESPONDENCES AWAITING A FIRST ANSWER, AS A SET (18.10.2026, Agent 89): the queue's one-second look asks it for every
    /// letter (MontanaDeliveryEngine.backoff), and a sealed record opened that often is the heat it exists to save. A mirror of the
    /// record, dropped at its every write and at a reread; the record stays the one owner.
    private static var awaitingCache: Set<String>?   // BOUND-OK: the keys of the sealed record, no more
    private static let awaitingLock = NSLock()
    static func awaitingFirst() -> Set<String> {
        awaitingLock.lock(); let held = awaitingCache; awaitingLock.unlock()
        if let held { return held }
        let fresh = Set(firsts().keys)
        awaitingLock.lock(); awaitingCache = fresh; awaitingLock.unlock()
        return fresh
    }
    private static func dropAwaiting() { awaitingLock.lock(); awaitingCache = nil; awaitingLock.unlock() }
    @discardableResult
    static func rememberFirst(_ ct: Data, for conv: String) -> Bool {
        guard ct.count == 1088, !conv.isEmpty else { return false }
        var m = firsts(); m[conv] = ct
        guard let d = try? JSONEncoder().encode(m) else { return false }
        defer { dropAwaiting() }
        return MontanaLocalVault.setEncrypted(firstKey, d)
    }
    static func first(for conv: String) -> Data? { firsts()[conv] }
    static func forgetFirst(_ conv: String) {
        forgetRoot(conv)   // the point of first contact dies with the ciphertext it belonged to
        forgetConfirm(conv)   // and the confirmation bound to that ciphertext
        var m = firsts()
        guard m.removeValue(forKey: conv) != nil, let d = try? JSONEncoder().encode(m) else { return }
        _ = MontanaLocalVault.setEncrypted(firstKey, d)
        dropAwaiting()
    }

    /// THE CONFIRMATION OF A FIRST LETTER OUTLIVES THE FLOOR (decision 188, #36, 25.10.2026). The key confirmation a first
    /// letter carries is made of the established secret (MTNodeWire.firstConfirm), and from eraseDay the book holds the floor, never the secret: an
    /// introduction still unanswered then could not be sent again (sameConfirm refuses an empty value). So the confirmation is
    /// made once, at the pipe's birth, and kept here -- sealed like the ciphertext beside it, bound to that ciphertext by its
    /// hash, and dropped with it on the answer or the drop (forgetFirst). It is bytes the wire carries anyway: it opens nothing,
    /// and the floor still erases the secret.
    private static let confirmKey = "pipeFirstConfirms"
    private static func confirms() -> [String: Data] {
        guard let d = MontanaLocalVault.getDecrypted(confirmKey),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }
    /// The bound form: SHA-256 of the ciphertext (32) followed by the confirmation's bytes.
    // LOCAL-HASH-OK: a binding inside one device's sealed record, not a quantity of the protocol.
    private static func bound(_ ct: Data) -> Data { Data(SHA256.hash(data: ct)) }
    @discardableResult
    static func rememberConfirm(_ confirm: String, ct: Data, for conv: String) -> Bool {
        guard ct.count == 1088, !conv.isEmpty, !confirm.isEmpty else { return false }
        var m = confirms(); m[conv] = bound(ct) + Data(confirm.utf8)
        guard let d = try? JSONEncoder().encode(m) else { return false }
        return MontanaLocalVault.setEncrypted(confirmKey, d)
    }
    private static func forgetConfirm(_ conv: String) {
        var m = confirms()
        guard m.removeValue(forKey: conv) != nil, let d = try? JSONEncoder().encode(m) else { return }
        _ = MontanaLocalVault.setEncrypted(confirmKey, d)
    }
    /// The confirmation a first letter of this correspondence carries with this ciphertext: the pipe's own while it holds the
    /// secret, else the one kept at its birth -- and only for the very ciphertext it was made for; any other gets none.
    static func firstConfirm(for conv: String, pipe: MTPipeKey, ct: Data) -> String {
        if pipe.holdsOrigin { return pipe.firstConfirm(ct: ct) }
        guard let kept = confirms()[conv], kept.count > 32, kept.prefix(32) == bound(ct) else { return "" }
        return String(decoding: kept.dropFirst(32), as: UTF8.self)
    }

    /// The contact key a correspondence was BEGUN at, kept until the other side answers.
    ///
    /// A first letter cannot be addressed by the tag of its pipe: the side receiving it does not
    /// hold the secret yet — the ciphertext inside the letter is what gives it that secret. So the
    /// set addresses a first letter at the point of first contact, derived from the contact root,
    /// and the holder of that root listens there. This is the root to derive it from, and it is
    /// dropped together with the ciphertext the moment the other side answers.
    private static let rootsKey = "pipeFirstRoots"

    private static func roots() -> [String: Data] {
        guard let d = MontanaLocalVault.getDecrypted(rootsKey),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }
    @discardableResult
    static func rememberRoot(_ root: Data, for conv: String) -> Bool {
        guard root.count == 1184, !conv.isEmpty else { return false }
        var m = roots(); m[conv] = root
        guard let d = try? JSONEncoder().encode(m) else { return false }
        return MontanaLocalVault.setEncrypted(rootsKey, d)
    }
    static func root(for conv: String) -> Data? { roots()[conv] }
    /// A conversation ALREADY knocking with a first letter at this meeting point. Meeting dedup by
    /// root: scan memory was a second store and silently lost a record, while this is the delivery
    /// state itself, and while the knocking lives the record lives by construction (regression 21:10:
    /// every scan of the same code gave birth to a twin, all knocked at one card, one spent it).
    static func convKnocking(at root: Data) -> String? {
        roots().first(where: { $0.value == root })?.key
    }
    static func forgetRoot(_ conv: String) {
        var m = roots()
        guard m.removeValue(forKey: conv) != nil, let d = try? JSONEncoder().encode(m) else { return }
        _ = MontanaLocalVault.setEncrypted(rootsKey, d)
    }

    /// Where THIS device addresses its next letter to that correspondence: the point of first
    /// contact while the first letter is still unanswered, the tag of the pipe ever after.
    static func outgoingTag(for conv: String, at: Date = Date()) -> Data? {
        if first(for: conv) != nil, let r = root(for: conv) {
            let w = MTPipe.window(at)
            let t = MontanaFirstContact.knock(at: r, window: w)
            MontanaTrace.mark("first_tx", "dst=\(t.map { $0.prefix(4).map { String(format: "%02x", $0) }.joined() } ?? "-") w=\(w) conv=\(String(conv.prefix(10)))")
            return t
        }
        return myTag(for: conv, at: at)
    }

    /// Which correspondence of MINE is still waiting at this point of first contact. Asked when an
    /// answer to a knock comes back before the other side has ever written: the pipe exists here,
    /// but its tag is not what was knocked — the point of first contact was.
    static func convAwaiting(firstContactTag tag: Data, at: Date = Date()) -> String? {
        let w = MTPipe.window(at)
        for (conv, root) in roots() {
            for k in MTPipe.windows(around: w) where MontanaFirstContact.knock(at: root, window: k) == tag {
                return conv
            }
        }
        return nil
    }

    /// The points this device listens at for somebody writing FIRST: one per card it handed out,
    /// and one for the name it holds. Computed per window like every other tag, and cached with the
    /// window exactly as the tags of pipes are.
    private static var firstIndex: (window: UInt64, points: [Data: Data])?
    private static let firstLock = NSLock()

    /// The other side has written under the pipe, so the introduction is over: the ciphertext my letters
    /// carried for it is spent, and the point they knocked at dies with it. Called at the one door every
    /// word of theirs lands at (MontanaDeliveryEngine.receive): a word sealed under the pipe's secret by the
    /// other side IS the proof that they hold it, whatever road brought it -- the live wire, the radio, the
    /// direct road, the node's box, a wake, the live-chat lane. The proof used to be read on the first three
    /// alone, and it dropped only the point, never the ciphertext, which only a receipt dropped (26.09, T3:
    /// a peer's name and face kept arriving from the box, and T3 still sent them two pictures for seven
    /// minutes by the live channel alone -- no node took them, nothing woke the sleeping phone -- and held
    /// every receipt to them «until the pipe»). True when an introduction was open and is closed now.
    @discardableResult
    static func firstContactDone(_ conv: String) -> Bool {
        if first(for: conv) == nil, root(for: conv) == nil { return false }
        forgetFirst(conv)   // the point dies with the ciphertext it belonged to
        dropFirstIndex()
        MontanaMeeting.forgetFirstMeta(conv: conv)   // the meeting happened -- the horizon clock is off
        MontanaTrace.mark("first_done", "conv=\(String(conv.prefix(10)))")
        return true
    }

    static func isFirstContactTag(_ tag: Data, at: Date = Date()) -> Bool {
        listeningFirstContactPoints(at: at)[tag] != nil
    }

    /// The root THIS point is derived from. The knowledge existed at the moment the points were built
    /// and was thrown away -- and it was restored by walking all the cards, and the walk gave birth to a
    /// phantom on every letter: ML-KEM on a foreign key does not refuse (implicit rejection, FIPS 203),
    /// it returns deterministic garbage from which a conversation link is honestly computed. A letter is
    /// addressed not to a person but to a POINT; a point is opened under one card -- so the card is known
    /// BEFORE any cryptography, and there is nothing left to try.
    static func firstContactRoot(forTag tag: Data, at: Date = Date()) -> Data? {
        listeningFirstContactPoints(at: at)[tag]
    }

    static func listeningFirstContactTags(at: Date = Date()) -> Set<Data> {
        Set(listeningFirstContactPoints(at: at).keys)
    }

    /// The points this device listens at, as a set. One computation, two readers: the question
    /// «is this tag mine» and the question «what do I put on the air so somebody can find me».
    /// They were one question all along — a device that listens at a point nobody is told about
    /// is a device nobody reaches, which is exactly what happened over Wi-Fi.
    static func listeningFirstContactPoints(at: Date = Date()) -> [Data: Data] {
        let w = MTPipe.window(at)
        firstLock.lock()
        if let i = firstIndex, i.window == w { firstLock.unlock(); return i.points }
        firstLock.unlock()
        var tags: [Data: Data] = [:]
        let nRoots = roots().count, nCards = MontanaCard.outstanding
        for r in roots().values where r.count == 1184 {
            for k in MTPipe.windows(around: w) { if let t = MontanaFirstContact.knock(at: r, window: k) { tags[t] = r } }
        }
        for r in MontanaCard.outstandingRoots() {
            for k in MTPipe.windows(around: w) { if let t = MontanaFirstContact.knock(at: r, window: k) { tags[t] = r } }
        }
        if let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn),
           let mine = MontanaNames.contactRoot(masterSeed: master) {
            for k in MTPipe.windows(around: w) { if let t = MontanaFirstContact.knock(at: mine, window: k) { tags[t] = mine } }
        }
        firstLock.lock(); firstIndex = (w, tags); firstLock.unlock()
        // Where the points came from: correspondences awaiting a first answer, and cards handed
        // out and not yet spent. A device listening at nothing is a device nobody can reach, and
        // the two sources fail for different reasons.
        MontanaTrace.mark("first_points", "n=\(tags.count) awaiting=\(nRoots) cards=\(nCards)")
        return tags
    }

    /// A card was spent or a name changed: the points this device listens at changed with them.
    static func dropFirstIndex() { firstLock.lock(); firstIndex = nil; firstLock.unlock() }
    /// A copy laid, or a seed changed (23.09): the name roots, the tags and the first-contact points are read
    /// again from the store — a first letter the copy carried knocks at its point from this moment.
    static func reread() {
        cacheLock.lock(); namesCache = nil; cacheLock.unlock()
        dropIndex()
        dropFirstIndex()
        dropAwaiting()
    }

    /// Where a letter of this correspondence is deposited in this window.
    static func tag(for conv: String, window w: UInt64) -> Data? { key(for: conv)?.tag(window: w) }

    /// The tags this device answers for right now — its own pipes across the accepted windows.
    ///
    /// Computed ONCE per window and kept, rather than derived again for every frame that arrives.
    /// The difference is not tidiness: the previous form hashed every correspondence against every
    /// accepted window on each incoming frame, so a device with fifty conversations paid a hundred
    /// and fifty hashes to answer the question «is this one mine», and paid it again a moment later
    /// for the next frame. A radio that is busy hashing is a radio that drops packets.
    ///
    /// A tag is a quantity of ONE window by construction, so the index is valid exactly as long as
    /// the window is, and it is rebuilt when the window turns or when the book itself changes —
    /// never on a timer, and never twice for one window.
    private static var index: (window: UInt64, map: [Data: String])?
    private static let indexLock = NSLock()

    private static func tagIndex(at: Date = Date()) -> [Data: String] {
        let w = MTPipe.window(at)
        indexLock.lock(); defer { indexLock.unlock() }
        if let i = index, i.window == w { return i.map }
        var map: [Data: String] = [:]
        for (conv, pipe) in load() {
            for k in MTPipe.windows(around: w) { for t in pipe.tags(window: k) { map[t] = conv } }   // Y, Y + 1: the earlier tag too
        }
        index = (w, map)
        return map
    }

    /// The book changed, so the tags standing on it did too. Called wherever a secret is written:
    /// an index outliving its book answers for a correspondence this device no longer holds.
    private static func dropIndex() {
        indexLock.lock(); index = nil; indexLock.unlock()
    }

    /// A frame is for this device when its tag stands in the index, and the correspondence it
    /// belongs to is read off the match: nothing on the wire has to name the sender.
    static func match(_ tag: Data, at: Date = Date()) -> String? { tagIndex(at: at)[tag] }

    /// Whom a frame under this label is addressed to -- ONE question for both transports.
    ///
    /// There are two marks: the pipe label held by two, and the first-contact point where the one whose
    /// card or name was taken stands. The question was written twice -- radio asked both marks, the wire
    /// only the first -- and nobody recognised a first letter on the wire: the addressee has no secret
    /// yet, it arrives as ciphertext INSIDE that very letter. Two implementations of one question drift
    /// apart silently, so here it is one.
    enum Addressed {
        case pipe(String)            // a pipe this device holds
        case firstContact(Data)      // the point of a first letter -- and the ROOT it is opened under
    }
    static func addressed(byTag tag: Data, at: Date = Date()) -> Addressed? {
        if let conv = match(tag, at: at) { return .pipe(conv) }
        if let root = firstContactRoot(forTag: tag, at: at) { return .firstContact(root) }
        return nil
    }

    /// The label of this conversation in this window. It does not go on the air and cannot: the
    /// announcement carries only a port. Conversation marks in a local network record were an error of
    /// class -- any value bound to a conversation is disclosure in an open announcement -- and the
    /// mechanism computing them is removed from here whole, so that one line cannot bring it back.
    static func myTag(for conv: String, at: Date = Date()) -> Data? { key(for: conv)?.tag(window: MTPipe.window(at)) }

    /// How many correspondences this device can answer for — the measure of the stage, countable
    /// without opening anything.
    static var count: Int { load().count }
}
