import Foundation
import MontanaBindings

/// The naming layer on the client side.
///
/// Only calls into the core and the state a device must not lose. Every derivation — the
/// normalization, the slot, the chain, the commitment — lives in `mt-names`, and is not rewritten
/// in Swift: one implementation per project, otherwise a client and a node resolve one written
/// name to two slots on the very first name.
enum MontanaNames {

    private static let ok: Int32 = 0

    /// The normalized name, or nil when it does not pass the rules of the layer.
    static func normalize(_ raw: String) -> String? {
        var out = [UInt8](repeating: 0, count: 64)
        var len = 0
        let rc = raw.withCString { mt_name_normalize($0, &out, out.count, &len) }
        guard rc == ok, len > 0 else { return nil }
        return String(bytes: out[0..<len], encoding: .utf8)
    }

    /// The slot of a name. Takes the normalized form ONLY: the core refuses raw input, and rightly —
    /// otherwise a chain would carry the slot of what a person typed rather than of what is written.
    static func slot(normalized: String) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = normalized.withCString { mt_name_slot($0, &out) }
        return rc == ok ? Data(out) : nil
    }

    /// The far end of the chain: the branch of a seed that TAKES THE SLOT, so two names of one
    /// holder yield two chains that cannot be joined.
    static func nameOwn(masterSeed: Data, slot: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = masterSeed.withUnsafeBytes { m -> Int32 in
            slot.withUnsafeBytes { s -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress,
                      let sb = s.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_name_own(mb, masterSeed.count, sb, &out)
            }
        }
        return rc == ok ? Data(out) : nil
    }

    /// The whole chain of renewals: links of 32 bytes, link 0 being the tip a commitment carries.
    static func chain(nameOwn: Data) -> [Data]? {
        let count = chainLength + 1
        var out = [UInt8](repeating: 0, count: count * 32)
        let rc = nameOwn.withUnsafeBytes { o -> Int32 in
            guard let ob = o.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_name_chain(ob, &out, out.count)
        }
        guard rc == ok else { return nil }
        return (0..<count).map { Data(out[$0 * 32..<($0 + 1) * 32]) }
    }

    static func commit(slot: Data, blind: Data, tip: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = slot.withUnsafeBytes { s in blind.withUnsafeBytes { b in tip.withUnsafeBytes { t -> Int32 in
            guard let sb = s.bindMemory(to: UInt8.self).baseAddress,
                  let bb = b.bindMemory(to: UInt8.self).baseAddress,
                  let tb = t.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_name_commit(sb, bb, tb, &out)
        }}}
        return rc == ok ? Data(out) : nil
    }

    /// One renewal proves continuity by a single hash: the published link hashes once to the link
    /// published before it. A signature would name a key, so there is none.
    static func verifyLink(previous: Data, link: Data) -> Bool {
        previous.withUnsafeBytes { p in link.withUnsafeBytes { l -> Bool in
            guard let pb = p.bindMemory(to: UInt8.self).baseAddress,
                  let lb = l.bindMemory(to: UInt8.self).baseAddress else { return false }
            return mt_name_verify_link(pb, lb) == 1
        }}
    }

    /// The naming derivations of the Canon, stated in the document together with their values. A
    /// name taken under derivations that differ by one byte is a name inside one implementation
    /// only: another client computes a different slot and a different commitment, and the two
    /// never meet.
    static func agreesWithCanon() -> Bool {
        guard let sl = slot(normalized: "alice"),
              sl.montanaHexString == "b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e"
        else { return false }
        let own = Data(repeating: 0xEE, count: 32)
        let blind = Data(repeating: 0xDD, count: 32)
        guard let ch = chain(nameOwn: own), ch.count == chainLength + 1,
              ch[chainLength - 1].montanaHexString == "83be15d760052903e3b1a2d304f56861ad92b8fed97a0b08452c6eb029fe1b5a",
              ch[0].montanaHexString == "b49373b194e6358022b8fbcbecb5beccdd4f0b275d1ccd53be130f76a1367a8e"
        else { return false }
        guard let cm = commit(slot: sl, blind: blind, tip: ch[0]),
              cm.montanaHexString == "929fccf5c511d3d1123707db473cf21732a9349bcb578ddea91ca08b2d9dae41"
        else { return false }
        // A knock computed differently lands where nobody listens, so it is proved here too.
        return MontanaFirstContact.agreesWithCanon()
    }

    /// What is happening to the name right now. Shown to a person in words, never as silence.
    enum State: Equatable {
        case none                          // no name — the account answers by its reference alone
        case committed(revealBy: UInt32)   // committed, awaiting its reveal before that window
        case held(renewBy: UInt32)         // taken, renewed up to that window
        case expired                       // a term went by; the slot is free
    }

    /// The constants of the layer — the numbers the Canon states.
    static let tau2Windows: UInt32 = 20_160
    static let renewWindows: UInt32 = 6 * tau2Windows
    static let revealMaxWindows: UInt32 = 2 * tau2Windows
    static let chainLength = 128

    private static let vaultKey = "mt.name"

    private struct Held: Codable {
        var name: String
        var commitWindow: UInt32
        var lastRenewWindow: UInt32
        var step: Int
        var nonce: Data
        var commitment: Data
        /// THE KEEPER'S TERM (24.09, the critic's P3): the term's end in seconds, as the keeper said it in the answer
        /// that proved the holding — never computed here. Absent in a record from before the keeper spoke.
        var until: Double? = nil
    }

    private static func load() -> Held? {
        MontanaLocalVault.getDecrypted(vaultKey).flatMap { try? JSONDecoder().decode(Held.self, from: $0) }
    }
    private static func save(_ h: Held) {
        if let d = try? JSONEncoder().encode(h) { MontanaLocalVault.setEncrypted(vaultKey, d) }
    }

    /// The name this device's record names — held or lapsed. What is shown, handed out and listened at is
    /// `heldName`.
    static var currentName: String? { load()?.name }
    /// The index of the last link the keeper holds, and the keeper's term.
    static var heldStep: Int? { load()?.step }
    static var heldUntil: Double? { load()?.until }

    static func state(now: UInt32) -> State {
        guard let h = load() else { return .none }
        if let until = h.until {
            let nowS = Double(now) * Double(MTPipe.windowSeconds)
            return nowS < until ? .held(renewBy: UInt32(until / Double(MTPipe.windowSeconds))) : .expired
        }
        if h.lastRenewWindow > 0 {
            let due = h.lastRenewWindow + renewWindows
            return now > due ? .expired : .held(renewBy: due)
        }
        if h.commitWindow > 0 {
            let due = h.commitWindow + revealMaxWindows
            return now > due ? .expired : .committed(revealBy: due)
        }
        return .none
    }

    /// What a taking publishes, and what the device keeps once the keeper of the order says the name is
    /// ours. The reveal is the Canon's own object (serialize(name_reveal), «The three objects of a name»):
    /// the name's length, the name zero-padded to 32, the blinding factor, the contact root.
    static func isHeld(now: UInt32 = UInt32(MTPipe.window())) -> Bool {
        if case .held = state(now: now) { return true }
        return false
    }
    /// The name this device holds right now. A name whose term ran out is neither shown, nor handed out, nor
    /// listened at (the critic's P5): its slot may be somebody else's already.
    static var heldName: String? { isHeld() ? currentName : nil }

    /// serialize(name_reveal) (Canon, «The three objects of a name»): the name's length, the name zero-padded to
    /// 32, the blinding factor, the contact root — 1 249 bytes. The node parses these bytes; the digest of one case
    /// is frozen on both sides (MontanaTests, test_names.py), so neither side checks itself with its own helper.
    static func reveal(name: String, blind: Data, root: Data) -> Data? {
        let bytes = Data(name.utf8)
        guard (4...32).contains(bytes.count), blind.count == 32, root.count == 1184 else { return nil }
        var r = Data([UInt8(bytes.count)])
        r.append(bytes)
        r.append(Data(count: 32 - bytes.count))
        r.append(blind)
        r.append(root)
        return r
    }

    struct Prepared {
        let name: String
        let slot: Data
        let chain: [Data]      // link k at index k; link 0 is the tip a taking publishes
        let blind: Data
        let commitment: Data
        let reveal: Data
    }

    /// Taking a name, prepared: normalize, slot, chain, a fresh blinding factor, the commitment and the
    /// reveal. NOTHING is kept here: a name becomes this device's only when the keeper answers that it is
    /// (MontanaNamePlane.take), so a refused taking leaves whatever the device held untouched.
    ///
    /// Refused outright while the core and the Canon disagree by a byte: a name taken under the
    /// derivations of one implementation is not a name in the network, and taking it would tell a
    /// person otherwise.
    static func prepare(_ raw: String, masterSeed: Data) -> Prepared? {
        guard agreesWithCanon() else {
            MontanaLog.event("NAME ✗ derivations differ from the Canon — a name is not taken")
            return nil
        }
        guard let n = normalize(raw), let sl = slot(normalized: n),
              let own = nameOwn(masterSeed: masterSeed, slot: sl),
              let ch = chain(nameOwn: own),
              let root = MontanaFirstContact.contactPair(masterSeed: masterSeed, slot: sl)?.root, root.count == 1184
        else { return nil }
        // The blinding factor of a commitment outlives the frame by years: it is what keeps the name
        // hidden until it is revealed. A quantity of the set is drawn by the core, not by the phone.
        var nonce = Data(count: 32)
        let gen = nonce.withUnsafeMutableBytes { p -> Int32 in
            guard let base = p.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_random_fast(base, 32)
        }
        guard gen == 0, let cm = commit(slot: sl, blind: nonce, tip: ch[0]),
              let r = reveal(name: n, blind: nonce, root: root) else { return nil }
        return Prepared(name: n, slot: sl, chain: ch, blind: nonce, commitment: cm, reveal: r)
    }

    /// The keeper said the name is ours. Kept sealed at rest (the blinding factor in the clear would join a
    /// slot to a commitment for anyone who reads the disk), held from this window, the chain spent up to
    /// `step` — the index of the last link the keeper holds.
    static func hold(_ p: Prepared, window: UInt32, step: Int, until: Double?) {
        save(Held(name: p.name, commitWindow: window, lastRenewWindow: window, step: step, nonce: p.blind,
                  commitment: p.commitment, until: until))
    }

    /// The name went to somebody else while this device thought it held it (a term lapsed unseen): the
    /// record goes, and the person is told by the screen that reads `currentName`.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: vaultKey)   // the vault lives in the defaults, sealed per key
    }

    /// The chain of the name this device holds: where a keeper's «last link» is looked up. A link that is
    /// not in it is somebody else's.
    static func heldChain(masterSeed: Data) -> [Data]? {
        guard let h = load(), let sl = slot(normalized: h.name),
              let own = nameOwn(masterSeed: masterSeed, slot: sl) else { return nil }
        return chain(nameOwn: own)
    }

    /// The link the next renewal publishes, WITHOUT spending it: the step moves only when the keeper takes
    /// the link (`renewed`), so a renewal lost on the way is published again rather than skipped — a
    /// skipped link would never hash to what the keeper holds, and the name would die of its own renewal.
    static func nextRenewal(masterSeed: Data) -> (slot: Data, link: Data)? {
        guard let h = load(), let sl = slot(normalized: h.name), let ch = heldChain(masterSeed: masterSeed) else { return nil }
        let next = h.step + 1
        guard next <= chainLength else { return nil }   // the chain is spent and the slot is released
        // The link is proved by the same single hash a verifier uses: if it does not hash to the one
        // published before it, it is not a renewal, and publishing it would spend a step for nothing.
        guard verifyLink(previous: ch[next - 1], link: ch[next]) else { return nil }
        return (sl, ch[next])
    }

    /// The keeper holds link `step`, and said the term's end. `window` is the moment of a renewal the keeper took
    /// NOW; nil when the keeper only confirmed a renewal taken earlier («again»), and the clock of the next one
    /// stays where it was.
    static func renewed(step: Int, window: UInt32?, until: Double?) {
        guard var h = load() else { return }
        h.step = step
        if let window { h.lastRenewWindow = window }
        if let until { h.until = until }
        save(h)
    }

    /// A renewal is due at the first return six weeks after the last one — half the keeper's term — or whenever
    /// less than τ₂ of the term is left. So whoever opens the app at least once every six weeks never loses the
    /// name: the first return past six weeks renews it while six more weeks of the term still stand (the critic's
    /// P6; the screen promises exactly this). The system's background window asks the same question.
    static let halfTermWindows: UInt32 = 3 * tau2Windows
    static func renewalDue(now: UInt32) -> Bool {
        guard let h = load(), case .held(let due) = state(now: now) else { return false }
        return now >= h.lastRenewWindow + halfTermWindows || now + tau2Windows >= due
    }

    /// Everything a name requires of a device when the person returns to the app. Three things happen
    /// under one condition -- there is a name -- so they stand in one place: the term is extended at the
    /// keeper when it has come due (off the caller's thread, and ONLY then: a question at every return
    /// would tell the keeper when the holder is present); our own pair of the name and its contact root
    /// lands in the book so that our own name resolves without asking; the device takes its stand at the
    /// point strangers knock at in this window.
    @discardableResult
    static func keepInStep(masterSeed: Data, now: UInt32 = UInt32(MTPipe.window())) -> Bool {
        guard let n = heldName, !n.isEmpty, !masterSeed.isEmpty else { return false }
        if renewalDue(now: now) {
            Task.detached(priority: .utility) { await MontanaNamePlane.renew(masterSeed: masterSeed) }
        }
        if let root = contactRoot(masterSeed: masterSeed) { MTPipeBook.rememberName(n, contactRoot: root) }
        MontanaWake.listenForKnocks(masterSeed: masterSeed)
        return true
    }

    /// The value the slot of this name publishes: the key a stranger encapsulates to. It is derived
    /// per name, so two names of one holder do not join, and its secret half never leaves here.
    static func contactRoot(masterSeed: Data) -> Data? {
        guard let n = heldName, let sl = slot(normalized: n),
              let pair = MontanaFirstContact.contactPair(masterSeed: masterSeed, slot: sl) else { return nil }
        return pair.root
    }

    /// Where a stranger knocks for this name in the given window.
    static func knockPoint(masterSeed: Data, window: UInt64) -> Data? {
        guard let root = contactRoot(masterSeed: masterSeed) else { return nil }
        return MontanaFirstContact.knock(at: root, window: window)
    }

    /// The name a person is shown. The sign stands ONLY before a name the network vouched for;
    /// anything else is text somebody sent.
    static func display(_ name: String, resolved: Bool) -> String {
        resolved ? "@" + name : name
    }
}
