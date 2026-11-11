import Foundation
import CryptoKit
import UIKit
import MontanaBindings

/// THE RULES OF THE FABRIC OF TIME, AS THE CORE STATES THEM (the author's words 17.10.2026 19:24 UTC: «the 3rd level is the count of
/// levels of the chats real with regular calls over the last 14 days -- t2 -- and it bears on the Global level by the rule of the
/// minimum»; 19:41: «one's own is one's own global level»; 19:50: «a new level that sets the global one, named Fabric of Time»;
/// 17.10.2026 21:4x: «not tied to the turns of t2 -- the current result of a sliding window of t2 over live activity: chats, calls,
/// transfers, [...], games, video, audio, media, stickers, GIFs»; 07:2x: a correspondent weighed by their ceiling, «yes, do it»;
/// Canon, «The level of the wallet», «The level of the fabric of time», «The half of the fabric», «The level of a person», «The
/// testimony of an exchange»). Byte for byte the core's mt-derive levels.rs -- the same functions and the same frozen vectors
/// (selfCheck) -- so a phone and a node that read one testimony name it by one identifier.
enum MTFabricRules {
    /// A call is a live act of the fabric when each side received the other's voice this long (Canon, call_seconds).
    static let callSeconds = 60
    /// τ₂ and its half (Canon, «The half of the fabric»): the last τ₂ is two halves, and a regular correspondent stands in each.
    static let tau2Windows: UInt64 = 20_160   // two weeks of one-minute windows; selfCheck holds it to the core's vectors
    static let halfWindows = tau2Windows / 2
    /// A segment, Genesis segment_windows (τ₂ / 14): a signer gives one addressee one testimony a segment, a holder keeps one.
    static let segmentWindows = tau2Windows / 14
    static let suite: UInt16 = 1             // Canon, the suite table: row 1, ML-DSA-65
    static let signatureLength = 3309        // Canon, the suite table: the signature of row 1
    static let scopeLength = 43              // Canon, «The testimony of an exchange»: 2 + 32 + 8 + 1
    static let testimonyLength = 3352        // Canon, testimony_len
    static let mostLevels = 19               // Canon: the most levels the wallet holds, which no ceiling exceeds

    #if !MONTANA_MESSENGER   // no coins in Messenger (cut C6): no level of a balance
    /// The level of the wallet (Canon: the count of the prefixes of π the balance reaches), its one reading: nineteen digits of π,
    /// the most a count of coins holds. The coins' levels (MTPiLevels) read the same prefixes and this reading (slice S2b b7e).
    static let piDigits = "3141592653589793238"
    static let piPrefixes: [Int] = (1...piDigits.count).map { Int(piDigits.prefix($0)) ?? 0 }
    static func walletLevel(_ balance: Int) -> Int { piPrefixes.filter { $0 <= balance }.count }
    #endif
    /// H: the greatest g for which at least g of the values stand at g or above. It counts people, not weight, in any order.
    static func fabricLevel(_ values: [Int]) -> Int {
        var level = 0
        for value in values.sorted(by: >) {
            if value <= level { break }
            level += 1
        }
        return level
    }
    /// The half of the last τ₂ a testimony stands in: 0 the newer, 1 the older, 2 and beyond out of the window. The difference
    /// saturates, so a testimony one window ahead of the reading stands in 0.
    static func half(_ now: UInt64, _ window: UInt64) -> UInt64 { (window < now ? now - window : 0) / halfWindows }
    static func segment(_ window: UInt64) -> UInt64 { window / segmentWindows }
    /// The level of a person (Canon: min(p, w, f)): the lowest of the three -- the person's, the wallet's, the fabric's -- never a
    /// sum or a mean of them. An edition without coins hands Int.max at w, which is no term (link 14822).
    static func levelOfPerson(_ p: Int, _ w: Int, _ f: Int) -> Int { min(p, w, f) }
    static func weaves(_ heard: Int) -> Bool { callSeconds <= heard }
    /// A LIVE ACT (App, «The fabric of time a client weighs»): what stands in a conversation -- words, voice and video messages,
    /// photographs, files and media, stickers and animations, transfers, a game's moves -- never a receipt, a sign of typing or of
    /// presence, a group's word or the fabric's own; a call is one when it weaves (MTFabric.callClosed).
    nonisolated static func isLiveAct(_ text: String) -> Bool {
        guard !text.hasPrefix(MTGroup.mark) else { return false }
        return !isControlMarker(text) || text.hasPrefix(mediaMark) || text.hasPrefix(voiceMark) || text.hasPrefix(stickerMark)
            || text.hasPrefix(appMark)
    }
    /// DEVIATION (Canon, «The half of the fabric»: «w is the network's window as the device read it from the network»): a phone holds
    /// no window of the core, so its window is the nodes' second -- learned from their answers (MontanaWakePush.nodeNow), the seconds
    /// the chain of the person counts too (MTPersonChain.answered) -- over sixty, counted from the Unix epoch.
    static func windowNow() -> UInt64 { UInt64(max(0, MontanaWakePush.nodeNow())) / MTPipe.windowSeconds }

    /// THE FAR VOICE, AS THIS PHONE RECEIVED IT (App: «A call weaves when each side received the other's voice for at least
    /// call_seconds»): one stretch of the engine's received voice stream -- its played seconds, their energy, the samples received and
    /// the ones the engine made up for packets that never came. A stretch counts when its level stands at a voice's floor or above, and
    /// only by the share of it that was received: a muted microphone sends silence, which carries no energy, and a broken road is
    /// made-up samples -- neither is a voice. The floor is -40 dBov (level 0.01): speech stands near -26 dBov, a quiet room and the
    /// engine's comfort noise near -60 and below, so a stretch holding spoken words stands above it and a silent one below.
    static let voiceFloor = 0.01
    static func voiced(seconds: Double, energy: Double, received: Double, concealed: Double) -> Double {
        guard 0 < seconds, 0 < received, 0 <= energy, voiceFloor <= (energy / seconds).squareRoot() else { return 0 }
        return seconds * max(0, min(1, (received - concealed) / received))
    }

    /// What a correspondent signs on a live act received from the person (Canon, «The testimony of an exchange»; levels.rs, Testimony).
    struct Testimony: Equatable {
        /// The one refusal (levels.rs): a ceiling past the most levels. The Canon names it by the wallet, whose levels the most are;
        /// Messenger carries no coins (cut C6) and names it by the most. `beyond` is the case, whichever the edition calls it.
        enum Refusal: String {
            #if MONTANA_MESSENGER
            case ceilingBeyondTheMost
            static let beyond = Refusal.ceilingBeyondTheMost
            #else
            case ceilingBeyondTheWallet
            static let beyond = Refusal.ceilingBeyondTheWallet
            #endif
        }
        var suite: UInt16
        var addressee: Data
        var window: UInt64
        var ceiling: UInt8
        /// The signed scope: every field before the signature, unsigned and little-endian, in the canonical order.
        var scope: Data {
            var out = Data()
            out.append(contentsOf: [UInt8(suite & 0xFF), UInt8(suite >> 8)])
            out.append(addressee)
            out.append(contentsOf: (0..<8).map { i in UInt8((window >> (8 * UInt64(i))) & 0xFF) })
            out.append(ceiling)
            return out
        }
        /// testimony_id = SHA-256("mt-exchange-testimony" || 0x00 || signed_scope), by the tree's one composition (MTPipe.domained).
        var id: Data { MTPipe.domained("mt-exchange-testimony", [scope]) }
        /// What it states of itself that a holder refuses before anything else is asked (levels.rs, refusal).
        var refusal: Refusal? { MTFabricRules.mostLevels < Int(ceiling) ? .beyond : nil }
        /// The testimony and its signature; one of any other length than testimony_len is refused before it is parsed (Canon).
        static func parse(_ bytes: Data) -> (Testimony, Data)? {
            let b = [UInt8](bytes)
            guard b.count == MTFabricRules.testimonyLength else { return nil }
            func le(_ at: Int, _ n: Int) -> UInt64 { (0..<n).reduce(UInt64(0)) { v, i in v | UInt64(b[at + i]) << (8 * UInt64(i)) } }
            let t = Testimony(suite: UInt16(le(0, 2)), addressee: Data(b[2..<34]), window: le(34, 8), ceiling: b[42])
            return (t, Data(b[MTFabricRules.scopeLength...]))
        }
    }

    /// THE FROZEN VECTORS (Canon, «Frozen vectors»), each named by the wrong reading it refuses: a wallet of 3 and of 314 refuse a
    /// strict comparison, 313 a count of digits, the nineteenth prefix a level capped at the thirteen a page shows; H(5) refuses a
    /// weight, H(2 x 6) a count of correspondents, H(9, 1, 7, 2, 6) values read as already sorted, H() a person who writes to nobody
    /// left without an answer; the age 10079 refuses a half rounded upward, 10080 a boundary drawn after half of τ₂ (and, its windows
    /// exchanged, a subtraction the other way), 20160 a window keeping a testimony τ₂ old; the level of a person refuses a dropped
    /// fabric, a first or a last term, a mean; the testimony's eight distinct bytes of its window refuse a big-endian window and its
    /// ceiling after the window a ceiling written first; a parse that misplaces a field gives another testimony back; the voice
    /// refuses a level read as its energy (0.05 counts, 0.0025 would not), a floor left out (0.001 counts nothing) and made-up samples.
    static func selfCheck() -> Bool {
        #if !MONTANA_MESSENGER
        guard walletLevel(2) == 0, walletLevel(3) == 1, walletLevel(313) == 2, walletLevel(314) == 3,
              walletLevel(3_141_592_653_589_793_238) == 19 else { return false }
        #endif
        guard fabricLevel([]) == 0, fabricLevel([5]) == 1, fabricLevel([3, 3, 3]) == 3, fabricLevel([9, 1, 7, 2, 6]) == 3,
              fabricLevel([2, 2, 2, 2, 2, 2]) == 2 else { return false }
        guard halfWindows == 10_080, segmentWindows == 1_440, half(20_160, 10_081) == 0, half(20_160, 10_080) == 1,
              half(20_160, 0) == 2, half(10_080, 20_160) == 0 else { return false }
        guard levelOfPerson(20, 5, 3) == 3, levelOfPerson(7, 2, 9) == 2, levelOfPerson(0, 9, 9) == 0 else { return false }
        var t = Testimony(suite: 1, addressee: Data(repeating: 0x22, count: 32), window: 0x0102_0304_0506_0708, ceiling: 9)
        let signature = Data(repeating: 0x5A, count: signatureLength)
        guard t.scope.count == scopeLength, t.refusal == nil,
              t.id.montanaHexString == "ea5deddd35b6355762867a5e744e4d3fdc76c3e72d9e70d17d5907a3b056d5da",
              let back = Testimony.parse(t.scope + signature), back.0 == t, back.1 == signature,
              Testimony.parse(t.scope) == nil else { return false }
        t.ceiling = 19
        guard t.refusal == nil else { return false }
        t.ceiling = 20
        guard t.refusal == .beyond else { return false }
        guard voiced(seconds: 2, energy: 2 * 0.05 * 0.05, received: 96_000, concealed: 0) == 2,
              voiced(seconds: 2, energy: 2 * 0.05 * 0.05, received: 96_000, concealed: 48_000) == 1,
              voiced(seconds: 2, energy: 2 * 0.001 * 0.001, received: 96_000, concealed: 0) == 0,
              voiced(seconds: 2, energy: 0, received: 96_000, concealed: 0) == 0 else { return false }
        return true
    }
}

/// THE FABRIC'S WORD FOR A READER OFF THE MAIN ACTOR (MTPersonChain.global, the call's caps): the level of the fabric now and the
/// person's own ceiling as every testimony states it -- written by MTFabric at every reading; nil until this life has read them, so an
/// unknown level is never said as none.
enum MTFabricLevel {
    private static let lock = NSLock()
    private static var held: Int?
    private static var told: Int?
    static var now: Int? { lock.lock(); defer { lock.unlock() }; return held }
    static var ceiling: Int? { lock.lock(); defer { lock.unlock() }; return told }
    static func set(_ level: Int?, ceiling: Int?) { lock.lock(); held = level; told = ceiling; lock.unlock() }
}

/// ONE CALL AS THE FABRIC WEIGHS IT (App, «The fabric of time a client weighs»), kept by the call machine for every call it holds, by
/// the call's name: the identifier its caller drew and its setup carried, the window the call stood from, and the seconds of the far
/// voice this phone received (MTFabricRules.voiced).
struct MTWeave {
    var call: Data?
    var from: UInt64?
    var heard: Double = 0
    var seen: [String: [Double]] = [:]   // a received stream's last counters: seconds, energy, received, made up
    /// A received stream's counters now: what they grew by since that stream's last sample is weighed, and nothing else.
    mutating func hears(_ id: String, seconds: Double, energy: Double, received: Double, concealed: Double) {
        let last = seen[id] ?? [0, 0, 0, 0]
        seen[id] = [seconds, energy, received, concealed]
        let ds = seconds - last[0], de = energy - last[1], dr = received - last[2], dc = concealed - last[3]
        guard 0 < ds, 0 <= de, 0 < dr, 0 <= dc else { return }
        heard += MTFabricRules.voiced(seconds: ds, energy: de, received: dr, concealed: dc)
    }
}

/// THE FABRIC OF TIME OF THIS SEED ON THIS PHONE (App, «The fabric of time a client weighs»; Identity, «The fabric of time»): the
/// testimonies of exchanges the person's correspondents gave, the window this phone last spoke to each correspondent and the
/// segment it last gave each a testimony in, the hash each correspondent told it to name them by, and the level of the fabric --
/// H over the values of the correspondents regular in the window that slides with the network's, a value being the lowest ceiling a
/// correspondent stated in the testimonies of the last τ₂; through the first τ₂ of the fabric on this seed, the ceiling. A
/// correspondent is told apart by the key its testimonies verify under (the hash its fingerprint is read from), and by nothing it
/// states of itself. One file beside the seconds of the person, at the same protection (TimeChain/fabric-v2.json); one link at
/// every change of the level in its chain (TimeChain/wallet-fabric.jsonl), sealed as every chain. What it holds lives τ₂ and then
/// leaves ([I-14]): a testimony counts in the two halves of the last τ₂ and nowhere after them.
///
/// THE CORRESPONDENCE A TESTIMONY STANDS ON (Canon, «The testimony of an exchange»: its addressee is the value the thirty digits two
/// people compare out of band are read from, and it is signed by the key the two of them compare). The two of this client compare the
/// fingerprint of the correspondence's secret (MTPipe.fingerprint, a deviation named in Audit/AUDIT.md), so the addressee is that hash,
/// computed by both ends from the secret alone and told by neither -- a testimony handed to a third person names a correspondence that
/// person does not hold -- and the signer's key is drawn from the seed for that correspondence alone, the same on every device of the
/// seed. [I-17]: no key and no value of a testimony is the same in two correspondences, so none names the person to anyone else.
@MainActor final class MTFabric: ObservableObject {
    static let shared = MTFabric()
    struct Held: Codable { var id: String; var key: String; var conv: String; var window: UInt64; var ceiling: Int; var body: String }
    struct Change: Codable { var window: UInt64; var level: Int; var digest: String }
    private struct Kept: Codable {
        var opened: UInt64?                  // the window the fabric opened in on this seed
        var held: [Held] = []
        var keys: [String: String] = [:]     // the hash a fingerprint is read from: the key its testimonies verify under
        var sent: [String: UInt64] = [:]     // a pipe: the window this phone last left a live act on it
        var given: [String: UInt64] = [:]    // a pipe: the segment this phone last gave a testimony on it
        var changes: [Change] = []
    }
    @Published private(set) var level: Int?
    @Published private(set) var ceiling: Int?
    @Published private(set) var regulars = 0
    @Published private(set) var testimonies = 0
    @Published private(set) var graceDays: Int?
    @Published private(set) var links: [MTTimeChain.Link] = []
    private var kept = Kept()
    private var loaded = false, keepDue = false
    private static var file: URL? { MTTimeChainPlace.dir()?.appendingPathComponent("fabric-v2.json") }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let u = Self.file, let d = try? Data(contentsOf: u), let k = try? JSONDecoder().decode(Kept.self, from: d) { kept = k }
        links = Self.chain(kept.changes)
    }
    private func keep() {
        guard loaded, let u = Self.file, let d = try? JSONEncoder().encode(kept) else { return }
        MTDiskDoor.write(d, to: u, "weave-kept", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func keepSoon() {
        guard !keepDue else { return }
        keepDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.keepDue = false; self?.keep() }
    }
    /// A person lifted into the seat: the fabric of the person who left goes with their folder; the seated person's is read next.
    func reread() {
        loaded = false; kept = Kept()
        level = nil; ceiling = nil; regulars = 0; testimonies = 0; graceDays = nil; links = []
        pairs = [:]
        MTFabricLevel.set(nil, ceiling: nil)
    }
    /// The fabric is read before a level is asked of it.
    func prime() { load() }
    /// The hash a correspondence's fingerprint is read from (MTPipe.fingerprintMaterial over its secret): the addressee of every
    /// testimony on it, both ways. Derived once, at the pipe's birth, and kept by the book (MTPipeKept).
    private var pairs: [String: Data] = [:]
    private func pair(_ conv: String) -> Data? {
        if let m = pairs[conv] { return m }
        guard let m = MTPipeBook.kept(for: conv)?.fingerprint else { return nil }
        pairs[conv] = m
        return m
    }
    /// The key this person signs a correspondence's testimonies with: HKDF-Expand(master_seed, "mt-fabric-key", 0x00 and the
    /// correspondence's hash, 32) into ML-DSA-65 -- one on every device of the words, another in every correspondence, and no relation
    /// to the account's key or the coins'.
    nonisolated static func signer(pair: Data) -> (pk: Data, sk: Data)? {
        guard pair.count == 32, let master = MontanaSeed.root, master.count == 64 else { return nil }
        let info = [UInt8](Data("mt-fabric-key".utf8) + Data([0]) + pair)
        var seed = [UInt8](repeating: 0, count: 32)
        let rc = master.withUnsafeBytes { m -> Int32 in
            info.withUnsafeBufferPointer { r -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_mldsa_seed_for_role(mb, r.baseAddress, info.count, &seed)
            }
        }
        guard rc == 0 else { return nil }
        var pk = [UInt8](repeating: 0, count: 1952), sk = [UInt8](repeating: 0, count: 4032)
        guard mt_mldsa_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return (Data(pk), Data(sk))
    }

    /// THE READING (App): the ceiling, the regular correspondents and their values, the level -- again whenever what they stand on
    /// moved: the person's seconds, the balance, a testimony coming or leaving the window. A handful of testimonies: it costs nothing.
    func refresh() {
        load()
        let w = MTFabricRules.windowNow()
        guard 0 < w else { return }   // the nodes' clock not heard yet: no window to read in
        var moved = prune(w)
        if kept.opened == nil { kept.opened = w; moved = true }
        var ceil: Int? = nil
        #if MONTANA_MESSENGER
        if let p = MTPersonLevel.now { ceil = min(MTFabricRules.mostLevels, p) }   // no coins in Messenger (cut C6): the person's level alone
        #else
        if let p = MTPersonLevel.now, let wl = MTPersonChain.walletTerm { ceil = min(MTFabricRules.mostLevels, p, wl) }
        #endif
        let opened = kept.opened ?? w
        let grace = w < opened + MTFabricRules.tau2Windows
        let regs = regulars(w)
        // THE LEVEL: through the first τ₂ the ceiling; past it H over the regulars' values, read now -- no turn, no estimate.
        let lvl: Int? = grace ? ceil : MTFabricRules.fabricLevel(regs.map { k in value(k, w) })
        if let l = lvl, kept.changes.last?.level != l {
            kept.changes.append(Change(window: w, level: l, digest: digest(regs, w)))
            moved = true
            links = Self.chain(kept.changes)
            writeChain()
            MontanaTrace.mark("fabric_level", "level=\(l) regulars=\(regs.count) grace=\(grace ? 1 : 0)")
        }
        MTFabricLevel.set(lvl, ceiling: ceil)
        let left = Double((opened + MTFabricRules.tau2Windows) * MTPipe.windowSeconds) - MontanaWakePush.nodeNow()
        let days: Int? = grace ? max(1, Int((left / 86_400).rounded(.up))) : nil
        let count = kept.held.filter { h in MTFabricRules.half(w, h.window) < 2 }.count
        if level != lvl { level = lvl }
        if ceiling != ceil { ceiling = ceil }
        if regulars != regs.count { regulars = regs.count }
        if testimonies != count { testimonies = count }
        if graceDays != days { graceDays = days }
        if moved { keepSoon() }
    }
    /// The correspondents regular now: a testimony from them in each half of the last τ₂ (Canon, «The half of the fabric»).
    private func regulars(_ w: UInt64) -> [String] {
        var halves: [String: Set<UInt64>] = [:]
        for h in kept.held {
            let x = MTFabricRules.half(w, h.window)
            if x < 2 { halves[h.key, default: []].insert(x) }
        }
        return halves.filter { e in e.value.count == 2 }.keys.sorted()
    }
    /// A correspondent's value: the lowest ceiling they stated in the testimonies of the last τ₂.
    private func value(_ key: String, _ w: UInt64) -> Int {
        kept.held.filter { h in h.key == key && MTFabricRules.half(w, h.window) < 2 }.map(\.ceiling).min() ?? 0
    }
    /// The set a change of the level stood on as its link names it: SHA-256 over the identifiers of the regulars' testimonies in the
    /// window, sorted -- a value of this device alone, never on the wire (LOCAL-HASH-OK), so two readings of one set give one link.
    private func digest(_ regs: [String], _ w: UInt64) -> String {
        let on = Set(regs)
        let ids = kept.held.filter { h in on.contains(h.key) && MTFabricRules.half(w, h.window) < 2 }.map(\.id).sorted()
        return SHA256.hash(data: Data(ids.joined(separator: "\n").utf8)).map { b in String(format: "%02x", b) }.joined()
    }
    /// [I-14]: a testimony leaves at its half 2, a pipe's marks a τ₂ after they were made; a key leaves with its last testimony.
    private func prune(_ w: UInt64) -> Bool {
        let before = (kept.held.count, kept.sent.count, kept.given.count)
        kept.held.removeAll { h in 2 <= MTFabricRules.half(w, h.window) }
        kept.sent = kept.sent.filter { e in MTFabricRules.half(w, e.value) < 2 }
        kept.given = kept.given.filter { e in MTFabricRules.half(w, e.value * MTFabricRules.segmentWindows) < 2 }
        let keys = Set(kept.held.map(\.key))
        kept.keys = kept.keys.filter { e in keys.contains(e.key) }
        if 200 < kept.changes.count { kept.changes.removeFirst(kept.changes.count - 200) }
        return before != (kept.held.count, kept.sent.count, kept.given.count)
    }
    /// One link at every change of the level, named by its window and the set it stood on, sealed on the one before
    /// (MTTimeChain.seal); its moment is the window on the nodes' clock, so the same changes give the same chain.
    nonisolated static func chain(_ changes: [Change]) -> [MTTimeChain.Link] {
        var out: [MTTimeChain.Link] = [], prev = MTTimeChain.genesis
        for c in changes {
            let n = out.count + 1, at = Int64(c.window * MTPipe.windowSeconds) * 1000
            let ref = "w:" + String(c.window) + ":" + String(c.digest.prefix(16))
            let hash = MTTimeChain.seal(n: n, at: at, k: "level", c: c.level, ref: ref, prev: prev)
            out.append(MTTimeChain.Link(n: n, at: at, k: "level", c: c.level, ref: ref, prev: prev, hash: hash))
            prev = hash
        }
        return out
    }
    private func writeChain() {
        guard let u = MTTimeChainPlace.file("fabric") else { return }
        var body = Data()
        for l in links { if let d = try? JSONEncoder().encode(l) { body.append(d); body.append(0x0A) } }
        MTDiskDoor.write(body, to: u, "fabric-chain", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// A LIVE ACT THIS PHONE LEFT FOR A CORRESPONDENT (App: a testimony is given «while it has itself sent that correspondent a live act
    /// within the last half of τ₂»): the window it last spoke on the pipe (MontanaDeliveryEngine.enqueue, MTFabricRules.isLiveAct).
    func spoke(_ conv: String) {
        guard !conv.isEmpty, !MTGroup.isKey(conv) else { return }
        load()
        let w = MTFabricRules.windowNow()
        guard 0 < w, kept.sent[conv] != w else { return }
        kept.sent[conv] = w
        keepSoon()
    }
    /// A LIVE ACT CAME FROM A CORRESPONDENT (App, «When a testimony is given»): when this phone spoke to them within the last half of τ₂
    /// and gave them no testimony this segment, it signs one -- the window it heard them in and its own ceiling -- naming the
    /// correspondence by the hash its secret gives, and gives it by the pair's own road, inside what only they open. A person who only
    /// writes is given none.
    func heard(_ conv: String) {
        guard !conv.isEmpty, !MTGroup.isKey(conv) else { return }
        prime()
        let w = MTFabricRules.windowNow()
        guard 0 < w, let s = kept.sent[conv], MTFabricRules.half(w, s) == 0 else { return }
        let seg = MTFabricRules.segment(w)
        guard kept.given[conv] != seg else { return }
        guard let named = pair(conv) else {
            return MontanaTrace.markFolded("fabric_tx", "held: no secret of the correspondence here", window: 600, key: conv)
        }
        guard let c = MTFabricLevel.ceiling else { return MontanaTrace.mark("fabric_tx", "held: this life has not read its own levels yet") }
        let t = MTFabricRules.Testimony(suite: MTFabricRules.suite, addressee: named, window: w, ceiling: UInt8(clamping: c))
        kept.given[conv] = seg
        keepSoon()
        let scope = t.scope
        Task.detached(priority: .utility) {
            guard let k = MTFabric.signer(pair: named), let sig = MontanaSeedKeys.sign(scope, seckey: k.sk), sig.count == MTFabricRules.signatureLength,
                  let d = try? JSONSerialization.data(withJSONObject: ["t": (scope + sig).base64EncodedString(), "k": k.pk.base64EncodedString()]),
                  let body = String(data: d, encoding: .utf8) else {
                MontanaTrace.mark("fabric_tx", "FAIL the seed's key did not sign")
                return
            }
            await MainActor.run {
                MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: ChatStore.mintMid().mid, text: fabricMark + body, silent: true)
                MontanaTrace.mark("fabric_tx", "to=\(String(conv.prefix(10))) ceiling=\(t.ceiling)")
            }
        }
    }
    /// A CALL OF TWO CLOSED (App: «a call that wove» is a live act): a call this phone heard the far voice in for a minute or more is a
    /// live act both ways -- this side spoke in it and heard.
    func callClosed(conv: String, weave: MTWeave) {
        let heardSeconds = Int(weave.heard)
        MontanaTrace.mark("fabric_call", "heard_s=\(heardSeconds)")
        guard MTFabricRules.weaves(heardSeconds), !conv.isEmpty else { return }
        spoke(conv)
        heard(conv)
    }

    /// THE FABRIC'S WORD CAME (Canon, «Invariants of a testimony»): a testimony of an exchange. It counts only once every question is
    /// answered, in this order -- its length, what it states of itself, that it names this correspondence, that its window stands no more than
    /// one window past this phone's reading and inside the last τ₂, that its signature holds under the key it came with. One a segment
    /// from one key is kept, the one stating the lower ceiling: a second adds nothing (Canon).
    func received(_ payload: String, from conv: String, at: Double) {
        prime()
        guard let d = payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return refuse("unreadable", conv)
        }
        guard o["t"] != nil else { return }   // a word of an older build: a ceiling and an estimate, which this fabric does not weigh
        guard let body = (o["t"] as? String).flatMap({ s in Data(base64Encoded: s) }),
              let key = (o["k"] as? String).flatMap({ s in Data(base64Encoded: s) }) else { return refuse("unreadable", conv) }
        guard let parsed = MTFabricRules.Testimony.parse(body) else { return refuse("length", conv) }
        let t = parsed.0, sig = parsed.1
        guard t.suite == MTFabricRules.suite else { return refuse("suite", conv) }
        if let r = t.refusal { return refuse(r.rawValue, conv) }
        guard let held = pair(conv), t.addressee == held else { return refuse("addressee", conv) }
        let w = MTFabricRules.windowNow()
        guard t.window <= w + 1 else { return refuse("window", conv) }
        guard MTFabricRules.half(w, t.window) < 2 else { return }   // older than the window: it counts nothing
        guard MontanaPQ.verify(pubkey: key, message: t.scope, signature: sig) else { return refuse("signature", conv) }
        let id = t.id.montanaHexString
        guard !kept.held.contains(where: { h in h.id == id }) else { return }
        let signer = MTPipe.fingerprintMaterial(key).montanaHexString
        let seg = MTFabricRules.segment(t.window)
        if let i = kept.held.firstIndex(where: { h in h.key == signer && MTFabricRules.segment(h.window) == seg }) {
            guard Int(t.ceiling) < kept.held[i].ceiling else { return }
            kept.held.remove(at: i)
        }
        kept.held.append(Held(id: id, key: signer, conv: conv, window: t.window, ceiling: Int(t.ceiling), body: body.base64EncodedString()))
        kept.keys[signer] = key.base64EncodedString()
        keep()
        refresh()
        MontanaTrace.mark("fabric_rx", "ceiling=\(t.ceiling) half=\(MTFabricRules.half(w, t.window))")
    }
    private func refuse(_ why: String, _ conv: String) {
        MontanaTrace.mark("fabric_refused", "why=\(why) from=\(String(conv.prefix(10)))")
    }
}

// MARK: - THE COIN CORE OF THE APP (the author's words 03.10 10:40, 10:52 and 10:53 UTC)
