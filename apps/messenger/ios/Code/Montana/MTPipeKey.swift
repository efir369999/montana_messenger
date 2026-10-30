//  MTPipeKey.swift — THE ONE OWNER OF A PIPE'S SECRET (24.10.2026, the author's words at 22:1x-22:2x UTC: «then do it now so
//  that for us this question is closed and it works by itself»; «should not the reading of the secret be in one place with
//  one owner and only references to it?»). Compiled into the app, the share extension and the notification extension alike.
//  The bytes a correspondence stands on live in one stored property, private to this file: every other file holds a pipe by
//  its name or by this value and asks it for what the pipe derives -- the key of a minute, the label of a day, the tag of a
//  window, the blind and the author field of an item, the record kept for good, the proofs of one person and of a first
//  letter. Thirty-eight readings of MTPipeBook.secret(for:) in eleven files, the extension's own reading of the mirror and the
//  sheet's own reading stood before it, each free to walk, to keep and to copy the bytes. No function of this file hands them
//  out but the forms a store of this device seals (form, stored, archiveHead), and tools/mt-pipe-owner-check.py names every caller of
//  those forms and refuses a reading past this file.
//  LOCAL-HASH-OK: this file IS the single owner of the walk and of the derivations a pipe's secret feeds; the compositions
//  themselves are MTNodeWire's (domained, sealKey, convTag, authorTag, tag, fingerprintMaterial, firstConfirm).

import Foundation
import CryptoKit

struct MTPipeKey: Hashable, Sendable {
    /// The secret a first letter established (or the key a store of this device derives for a pipe of its own: a slot it keeps,
    /// the pipe of the seed's devices, an invitation's letter key, a room's lane). Nothing outside this file reads it. Empty once
    /// the walk erased it (floor below).
    private let secret: Data
    /// What a pipe holds once the walk erased the established secret (from eraseDay on, OZ1, decision 126): the value of the walk
    /// at the floor day F = D - 2 -- the earliest day a box read still listens at (MTNodeWire.boxDays) -- and the quantities the
    /// pipe keeps for good (Canon, «Invariants of the walk»: a quantity a pipe keeps for good is derived once at birth and kept
    /// beside the walk). nil while the established secret is held.
    private let floor: Floor?
    private struct Floor: Hashable, Sendable {
        let day: UInt64
        let value: Data
        let root: Data, rank: Data, fingerprint: Data, faceBid: Data, faceKey: Data, pair: Data, ref: Data
    }

    init(_ secret: Data) { self.secret = secret; floor = nil }
    private init(floor: Floor) { secret = Data(); self.floor = floor }

    /// A pipe: thirty-two bytes, the size every pipe is born with, or the floor the walk left of them; a record of another size is
    /// no pipe.
    var isWhole: Bool { floor != nil || secret.count == 32 }
    /// Whether this device still holds the established secret: up to eraseDay, and never again once the walk erased it.
    var holdsOrigin: Bool { floor == nil && secret.count == 32 }

    // ── THE WALK BY THE CLIENT'S DAY (21.10.2026, the author's word at 09:00 UTC: the day; Canon, «The secret a tag stands on walks
    // with the window») ────────────────────────────────────────────────────────────────────────────────────────────────────────
    /// pipe_secret(D + 1) = SHA-256("mt-pipe-ratchet" ‖ 0x00 ‖ pipe_secret(D)), one step a day, standing still through
    /// walkAnchorDay: up to that day every key is byte for byte the one the earlier builds and Android derive, so they still meet,
    /// and from the day after each day stands one hash further down a one-way walk. The client counts its own day, not the
    /// Canon's window: its box keeps days (MTNodeWire.boxDays) and its seal minutes, and one anchor for every pipe brings both
    /// sides to one value without a letter about it. A day read off a node's time is clamped to maxWalk steps, so a forged time
    /// costs a bounded walk and opens nothing.
    static let walkAnchorDay: UInt64 = 20754   // 28.10.2026 UTC
    static let maxWalk: UInt64 = 36_600
    // ── THE TAG AND THE ERASURE BY THE DAY (OZ1, decision 126; the author's word 24.10.2026 23:2x UTC: «yes, and so that in the
    // very next build it starts to work seamlessly») ─────────────────────────────────────────────────────────────────────────────
    /// From tagWalkDay (Y) the tag of a window, the proof of one person and the author field of a group word stand on the walk and
    /// the root, never on the established secret; on Y and Y + 1 a receiver still accepts the tag and the proof an earlier build
    /// laid over the secret; from eraseDay (Y + 2) the secret is erased and the pipe holds the floor. One build carries the whole
    /// passage by the UTC day, with no build after it and no step of the person. No new number: Y is the anchor plus the four
    /// days a box read listens at (boxDays: D - 2 ... D + 1), so no box still holds a letter under a day before the walk began;
    /// Y + 2 is Y plus the box's two days back, the same two the floor keeps.
    static let tagWalkDay: UInt64 = walkAnchorDay + 4   // 20758, 01.11.2026 UTC
    static let eraseDay: UInt64 = tagWalkDay + 2        // 20760, 03.11.2026 UTC
    static let floorLag: UInt64 = 2                     // F = D - 2: the lower bound of MTNodeWire.boxDays
    private static let walkLock = NSLock()
    private static var walkCache: [Data: (steps: UInt64, value: Data)] = [:]   // BOUND-OK: emptied at 256 pipes
    private static func steps(_ day: UInt64) -> UInt64 { min(day > walkAnchorDay ? day - walkAnchorDay : 0, maxWalk) }
    /// The value of the walk on a day: from the established secret, or from the floor forward. A day before the floor gets the
    /// floor's own value -- the walk never goes back, and that value opens nothing laid before it.
    private func walked(_ day: UInt64) -> Data {
        let base = floor.map { f in (steps: Self.steps(f.day), value: f.value) } ?? (steps: 0, value: secret)
        let target = Self.steps(day)
        if target <= base.steps { return base.value }
        Self.walkLock.lock(); defer { Self.walkLock.unlock() }
        var at = base.steps, value = base.value
        if let c = Self.walkCache[base.value], c.steps <= target, c.steps >= at { at = c.steps; value = c.value }
        while at < target {
            value = MTNodeWire.domained("mt-pipe-ratchet", [value]); at += 1
        }
        if Self.walkCache.count >= 256 { Self.walkCache.removeAll() }
        Self.walkCache[base.value] = (target, value)
        return value
    }

    /// The pipe as this device may hold it on a day: up to eraseDay as it is; from it the floor at F = D - 2, walked forward from
    /// the floor already held, never back. The established secret leaves the value here and every store sealed from it.
    func floored(day: UInt64) -> MTPipeKey {
        guard day >= Self.eraseDay, isWhole else { return self }
        let f = day - Self.floorLag
        if let floor, floor.day >= f { return self }
        let k = kept()
        guard let ref = refBytes, let bid = Self.unhex(k.faceBid), bid.count == 32 else { return self }
        return MTPipeKey(floor: Floor(day: f, value: walked(f), root: rootKey, rank: sameRank, fingerprint: k.fingerprint,
                                      faceBid: bid, faceKey: k.faceKey, pair: k.pair, ref: ref))
    }

    /// Whether the walk already erased the established secret here: the pipe holds its floor.
    var isFloored: Bool { floor != nil }

    // ── ONE PIPE MET AGAIN (decision 188, #37, 25.10.2026) ───────────────────────────────────────────────────────────────────
    /// Whether two keys are one pipe: equal, or both walked to the later floor day of the two give the same whole floor -- the
    /// walk's value, root, rank, fingerprint, face name and key, pair and reference. Never the reference alone, never a name: a
    /// key that differs in any one kept quantity is another pipe. Two whole secrets are one pipe only when they are equal.
    func samePipe(_ other: MTPipeKey) -> Bool {
        if self == other { return true }
        guard let f = [floor?.day, other.floor?.day].compactMap({ $0 }).max() else { return false }
        let day = f + Self.floorLag
        guard let a = floored(day: day).floor, let b = other.floored(day: day).floor else { return false }
        return a == b
    }
    /// Of two keys of one pipe, the one a store keeps: the further floor. A whole secret met again is never written back over a
    /// floor.
    func further(_ other: MTPipeKey) -> MTPipeKey {
        guard let o = other.floor?.day else { return self }
        guard let s = floor?.day else { return other }
        return o > s ? other : self
    }

    /// The letter body key of a minute: the seal key under the pipe secret of that minute's day.
    func bodyKey(window: UInt64) -> [UInt8] {
        MTNodeWire.sealKey(stepSecret: walked(window / MTNodeWire.minutesPerDay), window: window)
    }
    /// The conversation's daily label at the node: both sides derive it from the pipe secret of that day.
    func convW(day: UInt64) -> String {
        MTNodeWire.convTag(daySecret: walked(day), window: day)
    }
    /// The tag of a pipe in a window: where a letter is deposited on the live wire, the radio and the direct road. Over the
    /// established secret before tagWalkDay, as every build has laid it; from it over the walked value of the window's day.
    func tag(window: UInt64) -> Data {
        let day = window / MTNodeWire.minutesPerDay
        return MTNodeWire.tag(sharedSecret: day >= Self.tagWalkDay || !holdsOrigin ? walked(day) : secret, window: window)
    }
    /// The tags a receiver accepts in a window: the tag of the window and, on Y and Y + 1, the one an earlier build laid over the
    /// established secret.
    func tags(window: UInt64) -> [Data] {
        let day = window / MTNodeWire.minutesPerDay, now = tag(window: window)
        guard holdsOrigin, day >= Self.tagWalkDay, day < Self.eraseDay else { return [now] }
        return [now, MTNodeWire.tag(sharedSecret: secret, window: window)]
    }

    // ── THE ROOT OF A CONVERSATION (21.10.2026, the author's word at 12:2x UTC: «yes») ──────────────────────────────────────────
    /// SHA-256("mt-conv-root" ‖ 0x00 ‖ the established secret). What a pair derives afresh for every item -- the blind of a coin
    /// SEND and the author field of a letter -- stands on the root from the day after walkAnchorDay, never on the established
    /// secret, so the walk can erase that secret. The root opens no letter: it is one hash in a domain of its own, and nothing of
    /// the walk is derived from it.
    private static func root(_ secret: Data) -> Data { MTNodeWire.domained("mt-conv-root", [secret]) }
    private var rootKey: Data { floor?.root ?? Self.root(secret) }
    /// The key an item laid today stands on: the root past the anchor, the established secret up to it, so a phone and an
    /// earlier build blind and sign alike until the walk begins.
    private func itemKey(day: UInt64) -> Data { day > Self.walkAnchorDay || !holdsOrigin ? rootKey : secret }
    /// The keys a received item may stand on, the root first: the sender's day is its own clock, so the receiver tries both
    /// while it still holds the established secret; no third party computes either.
    private var itemKeys: [Data] { holdsOrigin ? [rootKey, secret] : [rootKey] }

    /// The blind of a coin SEND laid today, by the coin's own rule (MTCoinChainRules.blind: the COIN-RULES region is compiled on
    /// its own, so the rule is handed in): the rule is applied to the item key here, and only the blind comes out.
    func blind(nonce: Data, day: UInt64 = MTNodeWire.dayWindow(), by rule: (Data, Data) -> Data) -> Data {
        rule(itemKey(day: day), nonce)
    }
    /// The blinds a received SEND may stand on, the root's first.
    func blinds(nonce: Data, by rule: (Data, Data) -> Data) -> [Data] { itemKeys.map { k in rule(k, nonce) } }

    // ── THE LETTER'S AUTHOR IS THE PERSON (MTNodeWire, the author's words 11.10.2026 13:4x UTC and 14:13 UTC, No.61-62) ───────────
    /// The body with the author's field, signed by the person's key over the item key of the day.
    func withAuthor(_ body: Data, person key: Data?, mid: String, text: String, day: UInt64 = MTNodeWire.dayWindow()) -> Data {
        guard let key, key.count == 32 else { return body }
        return MTNodeWire.withAuthor(body, tag: MTNodeWire.authorTag(key: key, secret: itemKey(day: day), mid: mid, text: text))
    }
    /// Whether a letter's author field is this person's: the tag made again under this person's key over each item key, compared
    /// in constant time.
    func authorHolds(_ tag: String, person key: Data?, mid: String, text: String) -> Bool {
        guard let key, key.count == 32, !tag.isEmpty, let got = Data(base64Encoded: tag), got.count == 16 else { return false }
        return itemKeys.contains { k in
            guard let want = Data(base64Encoded: MTNodeWire.authorTag(key: key, secret: k, mid: mid, text: text)) else { return false }
            var diff: UInt8 = 0
            for (a, b) in zip(got, want) { diff |= a ^ b }
            return diff == 0
        }
    }
    /// The person's tag on a group word carried on this pipe (MontanaGroup.ownTag): over the item key of the day, as a letter's
    /// author field (decision 126). Its reader (MontanaGroup.ownTag through authorHolds) has tried the root first since build
    /// 2309, so a word laid either way stays the person's own.
    func authorTag(person key: Data, mid: String, text: String, day: UInt64 = MTNodeWire.dayWindow()) -> String {
        MTNodeWire.authorTag(key: key, secret: itemKey(day: day), mid: mid, text: text)
    }

    // ── the proofs that stand on the secret itself ──────────────────────────────────────────────────────────────────────────────
    /// The key confirmation a first letter carries (MontanaFirstContact.firstConfirm, P-56). A pipe whose secret the walk erased
    /// confirms nothing by itself: an introduction still unanswered on eraseDay sends the confirmation kept at its birth
    /// (MTPipeBook.firstConfirm(for:pipe:ct:), decision 188), and an empty confirmation matches none (sameConfirm).
    func firstConfirm(ct: Data) -> String { holdsOrigin ? MTNodeWire.firstConfirm(secret: secret, ct: ct) : "" }
    /// ONE PERSON, ONE CONVERSATION (MTSamePair, 20.10.2026): the tag of this pipe (the older) beside a pipe just born (the newer),
    /// sixteen bytes in hex -- over the two roots from tagWalkDay (decision 126), over the two established secrets before it.
    func sameTag(_ domain: String, newer: MTPipeKey, day: UInt64 = MTNodeWire.dayWindow()) -> String {
        if day < Self.tagWalkDay, holdsOrigin, newer.holdsOrigin { return Self.sameOrigin(domain, self, newer) }
        return Self.hex16(MTNodeWire.domained(domain, [rootKey, newer.rootKey]))
    }
    /// The proofs a receiver accepts: the one of the day and, on Y and Y + 1, the one an earlier build laid over the secrets.
    func sameTags(_ domain: String, newer: MTPipeKey, day: UInt64 = MTNodeWire.dayWindow()) -> [String] {
        let now = sameTag(domain, newer: newer, day: day)
        guard day >= Self.tagWalkDay, day < Self.eraseDay, holdsOrigin, newer.holdsOrigin else { return [now] }
        return [now, Self.sameOrigin(domain, self, newer)]
    }
    private static func sameOrigin(_ domain: String, _ older: MTPipeKey, _ newer: MTPipeKey) -> String {
        hex16(MTNodeWire.domained(domain, [older.secret, newer.secret]))
    }
    private static func hex16(_ d: Data) -> String { d.prefix(16).map { String(format: "%02x", $0) }.joined() }
    /// This pipe's place in the one order both ends compute alike: a quantity kept for good, the same bytes before the walk erased
    /// the secret and after, so two ends order alike whatever build either runs.
    var sameRank: Data { floor?.rank ?? MTNodeWire.domained("mt-same-rank", [secret]) }

    /// The local name of a correspondence (MTPipeBook.establish): SHA-256 of the secret, sixteen bytes in hex, kept in the floor;
    /// it never leaves the device, and a stranger holding it learns nothing they could reach anyone with.
    private var refBytes: Data? {
        if let floor { return floor.ref }
        guard secret.count == 32 else { return nil }
        // LOCAL-HASH-OK: a filing name inside one device, not a quantity of the protocol.
        return Data(Data(SHA256.hash(data: secret)).prefix(16))
    }
    var reference: String? {
        guard isWhole, let r = refBytes else { return nil }
        return r.map { String(format: "%02x", $0) }.joined()
    }

    // ── what a correspondence keeps of its secret for good (22.10.2026, OZ 3 phase 2 step 1) ──────────────────────────────────
    /// The record of the permanent derivatives, made at the pipe's birth (MTPipeBook.kept) and carried by the floor after it.
    func kept() -> MTPipeKept {
        if let f = floor {
            return MTPipeKept(root: f.root, fingerprint: f.fingerprint, faceBid: f.faceBid.map { String(format: "%02x", $0) }.joined(),
                              faceKey: f.faceKey, pair: f.pair, ref: reference)
        }
        var face = Data("mt-pipe-f".utf8); face.append(0); face.append(secret)
        var faceKey = Data("mt-pipe-fk".utf8); faceKey.append(0); faceKey.append(secret)
        return MTPipeKept(root: Self.root(secret),
                          fingerprint: MTNodeWire.fingerprintMaterial(secret),
                          faceBid: SHA256.hash(data: face).map { String(format: "%02x", $0) }.joined(),
                          faceKey: Data(SHA256.hash(data: faceKey)),
                          pair: Data(HMAC<SHA256>.authenticationCode(for: Data("mt-coin-pair-v1".utf8), using: SymmetricKey(data: secret))),
                          ref: reference)
    }
    private static func unhex(_ s: String) -> Data? {
        let b = Array(s.utf8)
        guard b.count % 2 == 0 else { return nil }
        var out = Data()
        for i in stride(from: 0, to: b.count, by: 2) {
            guard let v = UInt8(String(decoding: b[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            out.append(v)
        }
        return out
    }

    // ── THE FORMS A STORE OF THIS DEVICE SEALS — the one road the bytes take out of this type ─────────────────────────────────
    /// A book as a store keeps it before sealing it: reference -> the bytes, the JSON every build has written (form), and read
    /// back (book). Their callers are named by tools/mt-pipe-owner-check.py: the book's vault (MTPipeBook) and the shelf's
    /// files (MTSeats); the extension's ears (MTNodeWire.ShelfEar) carry the same map inside their own record (stored, held).
    /// The mirror below is this file's own. Every form is floored on the day it is written and on the day it is read: from
    /// eraseDay no store sealed here holds the established secret, and a form read with it is walked and erased on the spot.
    /// A pipe's bytes are its thirty-two established bytes, or the floor: 0x01 ‖ F (8, little-endian) ‖ the walk's value on F ‖
    /// root ‖ rank ‖ fingerprint material ‖ face name ‖ face key ‖ pair tag (32 each) ‖ reference (16) -- 249 bytes.
    static let floorForm: UInt8 = 0x01
    static let floorFormSize = 1 + 8 + 32 * 7 + 16
    private var sealedForm: Data {
        guard let f = floor else { return secret }
        var d = Data([Self.floorForm])
        var day = f.day.littleEndian
        withUnsafeBytes(of: &day) { d.append(contentsOf: $0) }
        for p in [f.value, f.root, f.rank, f.fingerprint, f.faceBid, f.faceKey, f.pair, f.ref] { d.append(p) }
        return d
    }
    private init(sealed raw: Data) {
        let d = Data(raw)
        guard d.count == Self.floorFormSize, d[0] == Self.floorForm else { self.init(d); return }
        var day: UInt64 = 0
        for i in 0..<8 { day |= UInt64(d[1 + i]) << (8 * UInt64(i)) }
        func part(_ n: Int) -> Data { let at = 9 + 32 * n; return d.subdata(in: at..<(at + 32)) }
        self.init(floor: Floor(day: day, value: part(0), root: part(1), rank: part(2), fingerprint: part(3), faceBid: part(4),
                               faceKey: part(5), pair: part(6), ref: d.subdata(in: (9 + 32 * 7)..<Self.floorFormSize)))
    }
    static func form(_ keys: [String: MTPipeKey], day: UInt64 = MTNodeWire.dayWindow()) -> Data? {
        try? JSONEncoder().encode(stored(keys, day: day))
    }
    static func book(_ form: Data?, day: UInt64 = MTNodeWire.dayWindow()) -> [String: MTPipeKey] {
        guard let form, let m = try? JSONDecoder().decode([String: Data].self, from: form) else { return [:] }
        return held(m, day: day)
    }
    static func stored(_ keys: [String: MTPipeKey], day: UInt64 = MTNodeWire.dayWindow()) -> [String: Data] {
        keys.mapValues { k in k.floored(day: day).sealedForm }
    }
    static func held(_ stored: [String: Data], day: UInt64 = MTNodeWire.dayWindow()) -> [String: MTPipeKey] {
        stored.mapValues { s in MTPipeKey(sealed: s).floored(day: day) }
    }
    /// Whether a form sealed on the disk holds more than the walk allows on the day: the book then writes itself again.
    static func lags(_ form: Data?, day: UInt64 = MTNodeWire.dayWindow()) -> Bool {
        guard let form, let m = try? JSONDecoder().decode([String: Data].self, from: form) else { return false }
        return stored(held(m, day: day), day: day) != m
    }
    /// The head the archive seals under the seed (MontanaArchive.writeHead, «s:»): the one place a pipe may outlive the device
    /// key, and what a restore by the words answers the correspondence from -- from eraseDay the floor, never the secret; a
    /// head read with the secret after it is walked and erased on reading.
    /// The head is written from the pipe as floored on the day it is written (25.10.2026, decision 191): a key held in memory
    /// across the midnight into eraseDay, or born on it, never lays the established secret under the seed.
    var archiveHead: Data { archiveHead(day: MTNodeWire.dayWindow()) }
    func archiveHead(day: UInt64) -> Data {
        Data("s:".utf8) + Data(floored(day: day).sealedForm.base64EncodedString().utf8)   // COMPAT-LOCAL: an archive head form on the device
    }
    /// Whether a head read from the archive carries the established secret itself, not the floor's form: from eraseDay such a
    /// head is taken out of the folder's log and never filed again (MontanaArchive.dropSecretHeads, absorb).
    static func headHoldsSecret(_ head: String) -> Bool {
        guard head.hasPrefix("s:"), let s = Data(base64Encoded: String(head.dropFirst(2))) else { return false }   // COMPAT-LOCAL
        return MTPipeKey(sealed: s).holdsOrigin
    }
    init?(archiveHead head: String, day: UInt64 = MTNodeWire.dayWindow()) {
        guard head.hasPrefix("s:"), let s = Data(base64Encoded: String(head.dropFirst(2))) else { return nil }   // COMPAT-LOCAL
        let k = MTPipeKey(sealed: s)
        guard k.isWhole else { return nil }
        self = k.floored(day: day)
    }

    /// THE ROAD BACK FROM THE WORDS FLOORS BY THE LATER DAY (decision 188, E, 25.10.2026): a restore reads its heads on the later
    /// of the device's day and the trusted mark M (the highest day a node's Date confirmed, MTFloorGuard), so a device whose
    /// clock is behind does not keep a secret that a node's Date says is past its floor.
    static func recoveryDay(device day: UInt64, mark: UInt64?) -> UInt64 { max(day, mark ?? 0) }
    /// Whether the heads of one archive block all carry the established secret: from the floor day such a block leaves a
    /// folder's log and is not filed again (MontanaArchive.dropSecretHeads, absorb).
    static func onlySecretHeads(_ heads: [String]) -> Bool { !heads.isEmpty && heads.allSatisfy(headHoldsSecret) }
    /// What one frame of a folder's log holds, for the purge of the secret heads.
    enum LogFrame: Equatable, Sendable { case secretHead, floorHead, other }
    /// The purge of a folder's log from eraseDay: every frame of nothing but secret heads leaves; when no floor head follows the
    /// last of them, the floor of that very head takes its place (floorAt), so the last head still decides at a restore.
    static func purge(_ frames: [LogFrame]) -> (drop: [Int], floorAt: Int?) {
        guard let last = frames.lastIndex(of: .secretHead) else { return ([], nil) }
        let drop = frames.indices.filter { frames[$0] == .secretHead }
        return (drop, frames[(last + 1)...].contains(.floorHead) ? nil : last)
    }

    // ── THE EXTENSIONS' MIRROR (the app writes; the notification extension and the sheet read) ─────────────────────────────────
    /// The pipes the app mirrors into the shared keychain (device-only, WhenUnlocked) so the extensions open and seal letters on
    /// the device: the book's pipes, the first-meeting keys of live cards («rdv:<invite>») and the slots this phone keeps. The
    /// alias names the chat key a pipe filed under a local reference answers to.
    private static let mirrorKey = "nsePipeSecrets"
    private static let aliasKey = "nsePipeAlias"
    /// `day`: the day the book floors by (MTPipeBook.floorDay: the clock guard may withhold the first floor, decision 188).
    static func mirror(_ keys: [String: MTPipeKey], alias: [String: String], day: UInt64 = MTNodeWire.dayWindow()) {
        if let d = form(keys, day: day) { MontanaKeychain.set(mirrorKey, d) }
        if let d = try? JSONEncoder().encode(alias) { MontanaKeychain.set(aliasKey, d) }
    }
    static func mirrored() -> [String: MTPipeKey] { book(MontanaKeychain.get(mirrorKey)) }
    /// The pipe of a conversation in the mirror: under its own name, or walked through the alias both ways -- the pipe may live
    /// under a local name (ref) while the queue and the share grid name the chat key. One walk for the landing door and the sheet.
    static func mirrored(_ conv: String, in m: [String: MTPipeKey]) -> MTPipeKey? {
        if let k = m[conv] { return k }
        if let ad = MontanaKeychain.get(aliasKey), let alias = try? JSONDecoder().decode([String: String].self, from: ad) {
            if let ref = alias.first(where: { $0.value == conv })?.key, let k = m[ref] { return k }
            if let chat = alias[conv], let k = m[chat] { return k }
        }
        return nil
    }
    static func mirrored(for conv: String) -> MTPipeKey? { mirrored(conv, in: mirrored()) }

    // ── the frozen vectors of the walk (moved here from MTPipe.agreesWithCanon with the walk itself) ──────────────────────────
    /// The walk of the pipe secret by the day. The anchor day itself is the established secret (the earlier builds meet there),
    /// the next two are one and two steps down. What it rejects is named: an implementation that never steps (the key of the
    /// anchor's secret, a656c407...), one stepping once whatever the distance (1110b376...), one stepping by the day's number
    /// rather than its distance from the anchor (a walk of twenty thousand), and one without the domain (630dcd29...). The values
    /// are derived from the formula in Python apart from this code.
    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    static func agreesWithCanon() -> Bool {
        let bodySecret = Data((0..<32).map { UInt8($0) })
        let k = MTPipeKey(bodySecret)
        let a = walkAnchorDay
        guard hex(Data(k.bodyKey(window: 1000)))
                  == "e25542e65a84d1a5b5c72a13172ecb62319c18f21a59978a53e7dac2c22a966a",
              k.walked(a) == bodySecret,
              hex(k.walked(a + 1))
                  == "5dcfd87692fcd444a4344d756dfa37abe670d2eb252aa9b402646be97cf3c50a",
              hex(k.walked(a + 2))
                  == "0c31775e80ae463de61fecee68bee8bb4ebbcee8e6b2045f8714e93ef18cb1b0",
              hex(Data(k.bodyKey(window: (a + 2) * MTNodeWire.minutesPerDay)))
                  == "925378a4bb83e7137cbb1f8cdaba8b79fc37e30d3159e4158da6e0fee8518bb5",
              k.convW(day: a) == "d29425fcf807a325b74d8bb017420cfe2250cc47e8bdc6351f6006cd4a6bdc9b",
              k.convW(day: a + 2) == "c665fdca8978b9c6e54b9a4f16a06ccac657ba7da259df0a8f3e2550d7c2d518"
        else { return false }

        // The root of a conversation, what a coin SEND is blinded under past the anchor. It rejects a root without the zero
        // separator (3be77415...) and one that takes the walk's domain (5dcfd876..., the walk's first step), and the anchor day
        // still blinds under the established secret as the earlier builds do. Derived from the formula in Python apart from this code.
        guard hex(root(bodySecret)) == "d9c3e7f533da2d0ed10b6729601c478ab29d1b0cafed60443113ee6a63824e11",
              k.itemKey(day: a) == bodySecret,
              k.itemKey(day: a + 1) == root(bodySecret),
              k.itemKeys == [root(bodySecret), bodySecret]
        else { return false }

        // The author field of a letter stands on the same key: the root past the anchor, the established secret on the anchor
        // day, and a reader holds both. It rejects a signer that keeps the established secret past the anchor and a reader
        // that tries the root alone.
        let person = Data(repeating: 0x33, count: 32)
        let rootTag = MTNodeWire.authorTag(key: person, secret: root(bodySecret), mid: "m", text: "t")
        let anchorTag = MTNodeWire.authorTag(key: person, secret: bodySecret, mid: "m", text: "t")
        guard rootTag.utf8.elementsEqual(anchorTag.utf8) == false,
              k.withAuthor(Data(), person: person, mid: "m", text: "t", day: a + 1)
                == Data(count: 7) + Data(rootTag.utf8) + Data([0]),
              k.withAuthor(Data(), person: person, mid: "m", text: "t", day: a)
                == Data(count: 7) + Data(anchorTag.utf8) + Data([0]),
              k.authorHolds(rootTag, person: person, mid: "m", text: "t"),
              k.authorHolds(anchorTag, person: person, mid: "m", text: "t")
        else { return false }

        // THE PASSAGE BY THE DAY (OZ1, decision 126). The tag: over the established secret the day before Y (an earlier build's
        // tag), over the walked value of Y from Y, the earlier tag still accepted on Y and no longer on Y + 2; the floor of the
        // day after Y + 2 (F = 20759: the walk's fifth step), its form byte for byte, and a floored pipe deriving what the pipe
        // derived. It rejects a tag that never walks (cc699748... on Y), a tag walking before Y (the earlier builds would meet no
        // tag), an old tag accepted past Y + 1, a floor one day off, a floor that keeps the secret, and a form in another order.
        // Derived from the formula in Python apart from this code.
        let y = tagWalkDay, e = eraseDay, mpd = MTNodeWire.minutesPerDay
        let floored = k.floored(day: e + 1)
        guard hex(k.tag(window: (y - 1) * mpd + 5)) == "ec0c1a23e2450dd465356cd0b8175c4f",
              hex(k.tag(window: y * mpd + 5)) == "96d8937ada4908bcba9fd12c78b9c11c",
              k.tags(window: y * mpd + 5).map(hex) == ["96d8937ada4908bcba9fd12c78b9c11c", "cc6997487bfa3ed9c4a7542be4fc2bbb"],
              k.tags(window: e * mpd + 5).count == 1,
              k.floored(day: e - 1) == k, k.holdsOrigin,
              !floored.holdsOrigin, floored.isWhole, floored.walked(20759) == floored.walked(0),
              hex(floored.walked(20759)) == "047f100cb7db75364efcefe4b58cf0038b1e1bc441884b06b5674eaf7b857523",
              floored.sealedForm.count == floorFormSize,
              hex(Data(SHA256.hash(data: floored.sealedForm))) == "da6e42f21c5935263ba7339fdc38adfd36db060a69d335f97e21f0dfbf1ae119",
              hex(floored.tag(window: (e + 1) * mpd + 5)) == "9e0c92b8f91b94880bf15eee1ca672c7",
              floored.tag(window: (e + 1) * mpd + 5) == k.tag(window: (e + 1) * mpd + 5),
              floored.bodyKey(window: (e + 3) * mpd) == k.bodyKey(window: (e + 3) * mpd),
              floored.convW(day: e + 1) == k.convW(day: e + 1),
              floored.kept() == k.kept(), floored.reference == k.reference, floored.sameRank == k.sameRank,
              MTPipeKey(sealed: floored.sealedForm) == floored, floored.floored(day: e + 1) == floored
        else { return false }
        return true
    }
}

// ── THE CLOCK GUARD OF THE FIRST FLOOR (decision 188, #38: the rule of DinetPDA 17:59 UTC as the chair confirmed it at 18:11 UTC
// with both corrections, and the five readings of 19:2x UTC) ──────────────────────────────────────────────────────────────────
/// The device's day alone decides the floor (MTPipeKey.floored(day:)), and the floor is irreversible: a clock running ahead floors
/// a book early, and it can no longer open what its peer lays under the earlier days. The guard withholds the first floor, and
/// only it, while the device day stands more than one day ahead of every day a node's Date confirmed, for at most N days (the
/// box's four); sources that disagree never withhold it, and a hostile door can only raise M, which ends the wait -- the safe
/// side. The one case with no end is a clock frozen ahead with every door cut: a traced residual (floor_held, left unchanged),
/// never closed by an uptime count. The client's own key schedule, not consensus; the node Date is read for nothing else.
/// M, H and Hc are device state sealed beside the pipe book (MTPipeBook), never in the archive.
struct MTFloorGuard: Codable, Equatable, Sendable {
    /// M: the highest day a node's Date confirmed. It only rises, and only from a node Date.
    var mark: UInt64?
    /// H and Hc: the device day and the confirmed day at the first moment the first floor was withheld.
    var since: UInt64?
    var sinceConfirmed: UInt64?
    /// The first floor applied: the guard is never asked again (rule 4), even when a write of the floored book failed.
    var done = false

    /// N: the days a box read listens at (MTNodeWire.boxDays), four.
    static let width = UInt64(MTNodeWire.boxDays(around: 2).count)

    enum Verdict: Equatable, Sendable {
        case early                                    // before eraseDay: nothing floors, H and Hc stay
        case floor                                    // the floor applies on the device day (rule 2 with nothing held, rule 4)
        case free                                     // the floor applies and clears a withholding (rule 2)
        case held(since: UInt64, left: UInt64)        // the first floor withheld (rule 3)
        case ceiling(since: UInt64, byDevice: Bool)   // the wait ended at its ceiling (rule 3)
    }

    /// A node's Date names a day: M rises to it. Whether it rose.
    mutating func heard(_ day: UInt64) -> Bool {
        guard day > (mark ?? 0) else { return false }
        mark = day
        return true
    }
    /// c: the higher of M and the day of a node Date heard in this run, never projected forward by the time since; nil with neither.
    func confirmed(heard: UInt64?) -> UInt64? { [mark, heard].compactMap { $0 }.max() }
    /// The rule, asked wherever the book floors; `floored`: a key of the book is floored already.
    mutating func decide(day d: UInt64, heard: UInt64?, floored: Bool) -> Verdict {
        if floored || done { return .floor }                       // rule 4: after the first floor the guard is never asked
        if d < MTPipeKey.eraseDay { return .early }                // rule 1
        let n = Self.width
        guard let c = confirmed(heard: heard), d > c + 1 else {     // rule 2: no confirmed source, or the device day is not ahead
            let was = since != nil
            since = nil; sinceConfirmed = nil; done = true
            return was ? .free : .floor
        }
        if since == nil { since = d; sinceConfirmed = c }          // rule 3: the first moment of the withholding
        let h = since ?? d, hc = sinceConfirmed ?? c
        if d >= h + n || c >= hc + n {                               // the ceiling: whichever count ends first
            since = nil; sinceConfirmed = nil; done = true
            return .ceiling(since: h, byDevice: d >= h + n)
        }
        return .held(since: h, left: min(h + n - d, hc + n - c))  // the nearer of the two ends
    }
    /// The day the book floors by under a verdict: while withheld, the day before eraseDay, on which nothing floors.
    static func floorDay(_ v: Verdict, day d: UInt64) -> UInt64 {
        if case .held = v { return MTPipeKey.eraseDay - 1 }
        return d
    }
    /// The trace, one format on every port: the days as plain integers, no names, no keys.
    static func trace(_ v: Verdict, day d: UInt64, confirmed c: UInt64?) -> (String, String)? {
        let cs = c.map { String($0) } ?? "none"
        switch v {
        case .early, .floor: return nil
        case .free: return ("floor_free", "d=\(d) c=\(cs)")
        case let .held(h, left): return ("floor_held", "d=\(d) c=\(cs) since=\(h) left=\(left)")
        case let .ceiling(h, byDevice): return ("floor_ceiling", "d=\(d) c=\(cs) since=\(h) by=\(byDevice ? "device" : "confirmed")")
        }
    }
    /// What a run writes for a verdict: floor_held once per run and again only when d, c or left changes; floor_ceiling and
    /// floor_free when they happen. `told` is the run's last floor_held (d, c, left).
    static func line(_ v: Verdict, day d: UInt64, confirmed c: UInt64?, told: inout [UInt64]?) -> (String, String)? {
        let line = trace(v, day: d, confirmed: c)
        if case let .held(_, left) = v {
            let now = [d, c ?? 0, left]
            if told == now { return nil }
            told = now
        } else if line != nil {
            told = nil
        }
        return line
    }
}

/// What a correspondence derives from its secret once and for good. Each field names its one owner formula; none walks with
/// the day, so none may be read from the walked secret.
struct MTPipeKept: Codable, Equatable {
    let root: Data          // MTPipeKey.root: SHA-256("mt-conv-root" ‖ 0x00 ‖ secret)
    let fingerprint: Data   // MTNodeWire.fingerprintMaterial: the safety number and a testimony's addressee
    let faceBid: String     // SHA-256("mt-pipe-f" ‖ 0x00 ‖ secret), hex: the name of the pipe face's blob
    let faceKey: Data       // SHA-256("mt-pipe-fk" ‖ 0x00 ‖ secret): the key of the pipe face
    let pair: Data          // HMAC-SHA-256(secret, "mt-coin-pair-v1"): the coin pair's tag (MTCoinTx.pairTag)
    let ref: String?        // MTPipeKey.reference; absent from a record kept before it was born here
}
