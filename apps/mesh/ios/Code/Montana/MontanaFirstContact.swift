import Foundation
import CryptoKit
import MontanaBindings

/// First contact with a claimed name.
///
/// A name resolves into the ability to reach someone and NEVER into where they are. The slot of a
/// name publishes one value — the contact key — and everything else follows from it: a stranger
/// encapsulates to that key once, the holder decapsulates, and both then hold the same secret. From
/// there the correspondence runs under ordinary tags, and a letter begun by a name differs from one
/// begun by acquaintance in nothing an implementation or an observer can name.
enum MontanaFirstContact {

    /// The pair a name publishes. The secret half never leaves the device; what the slot carries is
    /// the encapsulation key alone. Derived per NAME, not per person: deriving it once per person
    /// would join two names of one holder.
    static func contactPair(masterSeed: Data, slot: Data) -> (root: Data, secret: Data)? {
        var seed = [UInt8](repeating: 0, count: 64)
        let rc = masterSeed.withUnsafeBytes { m -> Int32 in
            slot.withUnsafeBytes { s -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress,
                      let sb = s.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_name_contact_seed(mb, masterSeed.count, sb, &seed)
            }
        }
        guard rc == 0 else { return nil }
        var pk = [UInt8](repeating: 0, count: 1184), sk = [UInt8](repeating: 0, count: 2400)
        guard mt_mlkem_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return (Data(pk), Data(sk))
    }

    /// Where a stranger knocks in this window. It takes the shape of any other tag and its own
    /// domain, so it never collides with a tag standing on a secret two parties already hold.
    static func knock(at contactRoot: Data, window: UInt64) -> Data? {
        var out = [UInt8](repeating: 0, count: 16)
        let rc = contactRoot.withUnsafeBytes { r -> Int32 in
            guard let rb = r.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_name_first_tag(rb, contactRoot.count, window, &out)
        }
        return rc == 0 ? Data(out) : nil
    }

    /// The stranger's side: one encapsulation to the contact key, and the secret every later tag of
    /// this correspondence stands on.
    static func begin(toward contactRoot: Data) -> (ciphertext: Data, secret: Data)? {
        var ct = [UInt8](repeating: 0, count: 1088), ss = [UInt8](repeating: 0, count: 32)
        let rc = contactRoot.withUnsafeBytes { r -> Int32 in
            guard let rb = r.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_mlkem_encaps(rb, &ct, &ss)
        }
        guard rc == 0 else { return nil }
        guard let secret = firstSecret(ss: Data(ss), contactRoot: contactRoot, ciphertext: Data(ct)) else { return nil }
        return (Data(ct), secret)
    }

    /// KEY CONFIRMATION. ML-KEM decapsulation does not refuse: on a foreign or corrupted ciphertext
    /// the standard returns deterministic garbage (implicit rejection, FIPS 203).
    /// So a pipe is not born from decapsulation alone -- the letter carries a value that cannot be
    /// produced without the real shared secret short of finding a SHA-256 preimage. That is the
    /// named cryptographic prohibition the law stands on.
    static func firstConfirm(secret: Data, ct: Data) -> String {
        MTPipe.domained("mt-first-conf", [secret, ct]).prefix(16).base64urlNoPad
    }

    /// Constant-time comparison: an early-exit compare is a timing oracle over the secret.
    static func sameConfirm(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !x.isEmpty else { return false }
        var d: UInt8 = 0
        for i in 0..<x.count { d |= x[i] ^ y[i] }
        return d == 0
    }

    /// The holder's side: decapsulate what arrived and arrive at the same secret.
    static func accept(ciphertext: Data, contactSecret: Data, contactRoot: Data) -> Data? {
        var ss = [UInt8](repeating: 0, count: 32)
        let rc = contactSecret.withUnsafeBytes { sk -> Int32 in
            ciphertext.withUnsafeBytes { c -> Int32 in
                guard let skb = sk.bindMemory(to: UInt8.self).baseAddress,
                      let cb = c.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_mlkem_decaps(skb, cb, &ss)
            }
        }
        guard rc == 0 else { return nil }
        return firstSecret(ss: Data(ss), contactRoot: contactRoot, ciphertext: ciphertext)
    }

    /// The contact root enters the derivation so that two people writing to one name never land on
    /// one secret, and the ciphertext enters it so that two letters from one stranger do not either.
    private static func firstSecret(ss: Data, contactRoot: Data, ciphertext: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = ss.withUnsafeBytes { s -> Int32 in
            contactRoot.withUnsafeBytes { r -> Int32 in
                ciphertext.withUnsafeBytes { c -> Int32 in
                    guard let sb = s.bindMemory(to: UInt8.self).baseAddress,
                          let rb = r.bindMemory(to: UInt8.self).baseAddress,
                          let cb = c.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                    return mt_name_first_secret(sb, ss.count, rb, contactRoot.count, cb, ciphertext.count, &out)
                }
            }
        }
        return rc == 0 ? Data(out) : nil
    }

    /// The frozen vectors of the set for the knock. A knock computed differently lands where nobody
    /// listens, and the two sides never meet.
    static func agreesWithCanon() -> Bool {
        let root = Data(repeating: 0xCC, count: 1184)
        guard let a = knock(at: root, window: 1000), let b = knock(at: root, window: 1001) else { return false }
        return a.montanaHexString == "45468cdd9bcdebe6f622c46257c27fe3"
            && b.montanaHexString == "2751a149c51e219b73fadc85ca8b107b"
    }
}


// ── Acquaintance, in the shape the set gives it ──────────────────────────────────────────────
//
// An invitation carries a NAME and nothing else.
//
// The contact key has one place — the slot of that name publishes it — and a link that carried a
// copy would be a second place for one value. It would also pin a holder for good: a name is held
// by renewal and can pass to somebody else, and a stranger scanning yesterday's paper would
// encapsulate to whoever held it then, and the letter would go nowhere in silence.
//
// So a link resolves rather than carries: the name is normalized, the slot is computed from it,
// and the key is read out of the plane of names at the moment of meeting — one reach per window,
// bounded by a nullifier that names nobody.
//
// A person holding no name cannot be met at all, and that is the set speaking rather than a gap:
// someone who never claimed a name is indistinguishable from someone who does not exist.
extension MontanaFirstContact {

    static let invitationPrefix = "montana://"
    /// THE NAME'S LINK IS A WEB LINK (24.09, the author's word: «bind pzr.me, so a link to one's profile
    /// stands for good»). A scheme is plain text in every other messenger and in mail; pzr.me followed by
    /// the name is a link everywhere, opens this app through the associated domain when it is installed,
    /// and lands on a page offering the app otherwise. The domain holds nothing: no list, no lookup — the
    /// name after the slash is resolved by the plane of names, exactly as the scheme form always was, and
    /// both forms are read ([P2P-COMPAT]: a build that knows only montana:// meets the scheme form on the
    /// page).
    static let webNamePrefix = "https://pzr.me/"

    /// What this person hands to a stranger: their name, in the form every messenger links. Nil when no
    /// name is held — there is nothing to publish and nothing to resolve.
    static func invitation() -> String? {
        guard let n = MontanaNames.heldName, !n.isEmpty else { return nil }   // a lapsed name is handed to nobody (P5)
        return webNamePrefix + n
    }

    /// The name inside an invitation, normalized as the set normalizes it, or nil when the text is
    /// not an invitation. An address handed over in this shape is refused: it is not a name. A pasted
    /// link may have lost its scheme or gained «www.», a query or a closing slash on the way; none of
    /// them is part of a name, and a second path segment means it is not one.
    static func name(inInvitation text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = t.lowercased()
        let forms = [webNamePrefix, "https://www.pzr.me/", "http://pzr.me/", "http://www.pzr.me/", "pzr.me/", "www.pzr.me/", invitationPrefix]
        guard let form = forms.first(where: { low.hasPrefix($0) }) else { return nil }
        t = String(t.dropFirst(form.count))
        if let cut = t.firstIndex(where: { $0 == "?" || $0 == "#" }) { t = String(t[..<cut]) }
        if t.hasSuffix("/") { t.removeLast() }
        guard !t.isEmpty, !t.contains("/") else { return nil }
        return MontanaNames.normalize(t)
    }

    /// The slot a name occupies — where the plane of names is asked for its contact key.
    static func slot(inInvitation text: String) -> Data? {
        guard let n = name(inInvitation: text) else { return nil }
        return MontanaNames.slot(normalized: n)
    }

    /// Meeting somebody whose contact key the plane of names has just answered with: one
    /// encapsulation, and both sides hold the secret every later tag of this correspondence stands
    /// on. What comes back is the local name of that correspondence and the ciphertext the FIRST
    /// letter must carry — the holder derives the same secret from it and from nothing else.
    static func meet(contactRoot root: Data) -> (reference: String, ciphertext: Data)? {
        guard root.count == 1184, let started = begin(toward: root),
              let ref = MTPipeBook.establish(secret: started.secret) else { return nil }
        // Where the first letter must be addressed. The other side cannot derive the pipe secret
        // until that letter reaches them, so it cannot be addressed by the tag of the pipe.
        MTPipeBook.rememberRoot(root, for: ref)
        // The pipe appeared -- subscriptions (letters and voip) and extension mirrors refresh AT ONCE:
        // without this the initiator lived unregistered until the next activation -- the answering
        // receipt and the oncoming letter hit 404, and the NSE could not open the new pipe envelope.
        MontanaWakePush.registerConvs()
        layPipeFace(conv: ref)   // the face goes beside the pipe at its birth: the other side wears it with the first letter
        return (ref, started.ciphertext)
    }

    /// The holder's side: a first letter arrived carrying its ciphertext, and the same secret comes
    /// out of it. From here on the correspondence is indistinguishable from one begun by
    /// acquaintance — the same tags, the same shape, the same everything.
    static func accept(firstLetter ciphertext: Data, masterSeed: Data, confirmed: (Data) -> Bool) -> String? {
        guard let n = MontanaNames.heldName, let sl = MontanaNames.slot(normalized: n),
              let pair = contactPair(masterSeed: masterSeed, slot: sl),
              let secret = accept(ciphertext: ciphertext, contactSecret: pair.secret, contactRoot: pair.root)
        else { return nil }
        // The same law as for cards: the garbage secret of a foreign letter does not open the seal.
        guard confirmed(secret) else {
            MontanaP2PTrace.mark("first_ghost", "card=name"); return nil
        }
        let ref = MTPipeBook.establish(secret: secret)
        if ref != nil { MontanaWakePush.registerConvs() }   // the pipe stood up -- subscriptions at once
        if let ref { readPipeFace(conv: ref) }   // the beginner's face, laid beside the pipe at its birth
        return ref
    }

    // ── THE FACE BESIDE THE PIPE (23.09, the author's word: «at the chat's creation — the name and the face at
    // once»). The side that was scanned read the scanner's name in the first letter itself, and the face only in a
    // letter of its own, which the law of state letters holds back until the other side answers (state_pointless):
    // a drawn initial for eight seconds (T3 17:15, measured). The one who begins a correspondence lays its face on
    // the node the moment the pipe is born, under a name and a seal derived from the pipe's own secret — held by
    // exactly the two of them; the other side reads it the moment the first letter hands it that secret. An empty
    // seal says «no face». A build that knows nothing of it neither lays nor asks: the face comes by its letter as
    // before, and an unread blob dies by the node's term ([P2P-COMPAT]). The node learns nothing the meeting has not
    // shown it already — the same pair at the same moment, the size the face letter carries anyway.
    private static func pipeFaceBid(_ secret: Data) -> String {
        var m = Data("mt-pipe-f".utf8); m.append(0); m.append(secret)
        return SHA256.hash(data: m).map { String(format: "%02x", $0) }.joined()
    }
    private static func pipeFaceKey(_ secret: Data) -> Data {
        var m = Data("mt-pipe-fk".utf8); m.append(0); m.append(secret)
        return Data(SHA256.hash(data: m))
    }

    /// The beginner's side, at the pipe's birth.
    static func layPipeFace(conv: String) {
        guard let secret = MTPipeBook.secret(for: conv) else { return }
        let face = E2E.myAvatarData() ?? Data()
        guard let sealed = MontanaP2PDirect.seal(key: [UInt8](pipeFaceKey(secret)), face) else { return }
        let bid = pipeFaceBid(secret)
        Task.detached(priority: .userInitiated) {
            let ok = await MontanaWakePush.putBlob(bid, data: sealed, over: true)
            MontanaP2PTrace.mark("pipe_face_up", "\(ok ? "ok" : "FAIL") bytes=\(face.count) conv=\(String(conv.prefix(10)))")
        }
    }

    /// The accepting side, once per correspondence: asked at once and twice more across eight seconds (the face
    /// may still be on its way up); a face that came first by the person's own letter is kept.
    private static let pipeFaceLock = NSLock()
    private static var pipeFaceAsked: Set<String> = []
    static func readPipeFace(conv: String) {
        pipeFaceLock.lock(); let first = pipeFaceAsked.insert(conv).inserted; pipeFaceLock.unlock()
        guard first, let secret = MTPipeBook.secret(for: conv) else { return }
        let bid = pipeFaceBid(secret), key = pipeFaceKey(secret)
        Task.detached(priority: .userInitiated) {
            for (i, pause) in [UInt64(0), 2, 6].enumerated() {
                if pause != 0 { try? await Task.sleep(nanoseconds: pause * 1_000_000_000) }
                guard let sealed = await MontanaWakePush.getBlob(bid) else { continue }
                guard let face = MontanaP2PDirect.open(key: [UInt8](key), sealed), face.count <= 262_144 else {
                    MontanaP2PTrace.mark("pipe_face", "unreadable conv=\(String(conv.prefix(10)))"); return
                }
                if face.isEmpty { MontanaP2PTrace.mark("pipe_face", "none conv=\(String(conv.prefix(10))) try=\(i + 1)"); return }
                let worn = await MontanaCard.wearFace(face, conv: conv, onlyIfBare: true)
                MontanaP2PTrace.mark("pipe_face", "ok bytes=\(face.count) conv=\(String(conv.prefix(10))) try=\(i + 1) worn=\(worn ? 1 : 0)")
                return
            }
            MontanaP2PTrace.mark("pipe_face", "absent conv=\(String(conv.prefix(10)))")
        }
    }
}


/// Resolving a name into the ability to reach its holder, and taking one.
///
/// The set puts one value at the slot of a claimed name — the contact root — and gives the ORDER of a
/// slot to the chain. Until the chain carries names, the nodes carry the Canon's reveal and ONE node keeps
/// the order (a door's «name» capability; which node keeps it is the nodes' own configuration, never the
/// phone's). The keeper hands out no link of anybody's chain; the phone proves a name its own by reading
/// the reveal under it and finding its own key there — and by nothing else (the critic's P1).
enum MontanaNamePlane {
    enum Answer {
        case found(contactRoot: Data)
        case unknown        // the keeper said that nobody holds it
        case unreachable    // no door answered, or a door's memory disputes the keeper
    }
    enum Taking {
        case taken(String)  // the keeper recorded it as this device's
        case held           // somebody else holds it
        case full           // the keeper's quota is spent
        case busy           // the keeper asked to wait
        case unreachable
        case refused        // not a lawful name, or no seed to take it with
    }

    static func slot(of raw: String) -> Data? {
        guard let n = MontanaNames.normalize(raw) else { return nil }
        return MontanaNames.slot(normalized: n)
    }

    static func known(_ raw: String) -> Data? {
        guard let n = MontanaNames.normalize(raw) else { return nil }
        return MTPipeBook.contactRoot(forName: n)
    }

    /// The doors that carry the plane of names — by their own word (the capability map), in the network's
    /// order, the elected first.
    private static func doors() -> [String] { MontanaWakePush.orderedBases(for: "name") }

    /// One question to one door. The code is knowledge in itself — 409 is «held», 404 is «nobody», 507 is
    /// «full» — so it comes back whole, never folded into «failed».
    private static func ask(_ door: String, _ path: String, _ body: [String: Any]) async -> (code: Int, obj: [String: Any]) {
        guard let url = URL(string: door + path),   // SERVER-DEBT-ACK: the plane of names, carried by the nodes until the chain carries it
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return (-1, [:]) }
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the plane of names, carried by the nodes until the chain carries it
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = payload
        req.timeoutInterval = MTNodeWire.postTimeoutS
        guard let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the plane of names, carried by the nodes until the chain carries it
              let code = (resp as? HTTPURLResponse)?.statusCode else {
            MontanaP2PTrace.mark("name_ask", "\(path) unreachable at=\(URL(string: door)?.host ?? "-")")
            return (-1, [:])
        }
        let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        return (code, obj)
    }

    /// A 404 is «nobody holds it» ONLY in the keeper's own words: a door that carries no names answers 404 too
    /// («no such capability here», or an older node's «not found»), and on a cold start, before the doors have
    /// named what they hold, those doors are asked as well — their 404 says nothing about the name.
    private static func nobody(_ code: Int, _ obj: [String: Any]) -> Bool {
        code == 404 && (obj["error"] as? String) == "no such name"
    }

    /// ONE DOOR AT A TIME (the critic's P10): the elected door first, the next only when a door is silent, fails,
    /// or carries no names. Asking every door at once put one question before the keeper twice — once straight,
    /// once through the other door.
    private static func askFirst(_ path: String, _ body: [String: Any]) async -> (code: Int, obj: [String: Any]) {
        var last: (code: Int, obj: [String: Any]) = (-1, [:])
        for d in doors() {
            let a = await ask(d, path, body)
            if [200, 400, 409, 429, 507].contains(a.code) || nobody(a.code, a.obj) { return a }
            last = a
        }
        return last
    }

    /// The contact root inside the Canon's reveal of `name` (serialize(name_reveal): the name's length, the
    /// name zero-padded to 32, the blinding factor, the contact root), or nil when the bytes are not that.
    /// A reveal of another name under this slot is refused here, whatever the door says.
    static func root(inReveal d: Data, of name: String) -> Data? {
        let b = [UInt8](d)
        guard b.count == 1249 else { return nil }
        let n = Int(b[0])
        guard (4...32).contains(n), Array(b[1...n]) == Array(name.utf8),
              b[(1 + n)..<33].allSatisfy({ $0 == 0 }) else { return nil }
        return Data(b[65..<1249])
    }

    static func resolve(_ raw: String) async -> Answer {
        guard let n = MontanaNames.normalize(raw), let sl = MontanaNames.slot(normalized: n) else { return .unknown }
        let all = doors()
        guard !all.isEmpty else { return fallback(n, why: "no door carries names") }
        var remembered: Data? = nil
        for d in all {
            let (code, obj) = await ask(d, "/name-get", ["slot": sl.montanaHexString])
            if code == 200, let b64 = obj["reveal"] as? String, let bytes = Data(base64Encoded: b64),
               let r = root(inReveal: bytes, of: n) {
                // A door's memory is not the keeper's word (the critic's P12): it stands only while no door says
                // otherwise.
                if (obj["stale"] as? Bool) == true { remembered = remembered ?? r; continue }
                MTPipeBook.rememberName(n, contactRoot: r)
                MontanaP2PTrace.mark("name_resolve", "found")
                return .found(contactRoot: r)
            }
            if nobody(code, obj) {
                if remembered != nil {
                    MontanaP2PTrace.mark("name_resolve", "DISPUTED — a door's memory against the keeper's «nobody»")
                    return .unreachable
                }
                MontanaP2PTrace.mark("name_resolve", "nobody holds it")
                return .unknown
            }
        }
        if let r = remembered {
            MontanaP2PTrace.mark("name_resolve", "from a door's memory — the keeper is silent")
            return .found(contactRoot: r)
        }
        return fallback(n, why: "no door answered")
    }

    /// The doors are silent: the root this device heard last — ONLY for a name already met here (the critic's P12),
    /// and named in the diary, because a name may have changed hands since.
    private static func fallback(_ n: String, why: String) -> Answer {
        if let r = MTPipeBook.contactRoot(forName: n), MontanaMeeting.cardMet(root: r) != nil {
            MontanaP2PTrace.mark("name_resolve", "from memory, a name met before — \(why)")
            return .found(contactRoot: r)
        }
        MontanaP2PTrace.mark("name_resolve", "unreachable — \(why)")
        return .unreachable
    }

    /// Whether the reveal under a name carries this device's own key — the one proof a phone has that a name it
    /// believes its own is its own. Nil when the keeper did not answer.
    private static func ownsSlot(_ name: String, master: Data) async -> Bool? {
        guard let sl = MontanaNames.slot(normalized: name),
              let mine = MontanaFirstContact.contactPair(masterSeed: master, slot: sl)?.root else { return nil }
        let (code, obj) = await askFirst("/name-get", ["slot": sl.montanaHexString])
        if code == 200, let b64 = obj["reveal"] as? String, let bytes = Data(base64Encoded: b64), (obj["stale"] as? Bool) != true {
            return root(inReveal: bytes, of: name) == mine
        }
        if nobody(code, obj) { return false }
        return nil
    }

    private enum Probe { case taken(step: Int, until: Double?), ours(step: Int), held, full, busy, unreachable, exhausted }

    /// Taking a slot with the first link of this phone's chain the keeper has not seen. A chain is a function of the
    /// seed and the slot and outlives its holding, so an earlier holding of the same seed may have published links:
    /// the keeper answers «spent» for those, and the probe doubles (1, 2, 4, …) — a retaking wastes at most as many
    /// links as were already spent.
    private static func probe(_ p: MontanaNames.Prepared, from start: Int, master: Data) async -> Probe {
        var k = max(0, start)
        while k <= MontanaNames.chainLength {
            let (code, obj) = await askFirst("/name-take", ["reveal": p.reveal.base64EncodedString(), "last": p.chain[k].montanaHexString])
            switch code {
            case 200: return .taken(step: k, until: obj["until"] as? Double)
            case 409 where (obj["spent"] as? Bool) == true:
                k = k == 0 ? 1 : k * 2
            case 409:
                switch await ownsSlot(p.name, master: master) {
                case true?: return .ours(step: k)
                case false?: return .held
                case nil: return .unreachable
                }
            case 507: return .full
            case 429: return .busy
            default: return .unreachable
            }
        }
        MontanaP2PTrace.mark("name_take", "every probed link is spent")
        return .exhausted
    }

    /// Taking a name at the keeper. The device holds it only once the keeper says so — or once the reveal under the
    /// name proves to carry this device's own key; a new name releases the one held before it, and the release is
    /// final (Identity: «releasing is not reversible»).
    static func take(_ raw: String) async -> Taking {
        guard let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn),
              let p = MontanaNames.prepare(raw, masterSeed: master) else { return .refused }
        let recorded = MontanaNames.currentName
        let former = (recorded != nil && recorded != p.name && MontanaNames.isHeld()) ? MontanaNames.nextRenewal(masterSeed: master) : nil
        let start = recorded == p.name ? (MontanaNames.heldStep ?? -1) + 1 : 0
        let window = UInt32(MTPipe.window())
        switch await probe(p, from: start, master: master) {
        case .taken(let step, let until):
            MontanaNames.hold(p, window: window, step: step, until: until)
            if let former { await release(slot: former.slot, link: former.link) }
            return settle(p.name, master: master, trace: "taken at step \(step)")
        case .ours(let step):
            // Our own reveal stands under the name (a taking whose answer was lost, another device of this seed):
            // held from here, and a renewal reads the keeper's step and term back.
            MontanaNames.hold(p, window: window, step: step, until: nil)
            if let former { await release(slot: former.slot, link: former.link) }
            await renew(masterSeed: master)
            return settle(p.name, master: master, trace: "ours again")
        case .held: return .held
        case .full: return .full
        case .busy: return .busy
        case .unreachable, .exhausted: return .unreachable
        }
    }

    private static func settle(_ n: String, master: Data, trace: String) -> Taking {
        if let root = MontanaNames.contactRoot(masterSeed: master) { MTPipeBook.rememberName(n, contactRoot: root) }
        MTPipeBook.dropFirstIndex()   // the device listens at the point of the new name from this window
        MontanaNames.keepInStep(masterSeed: master)
        MontanaP2PTrace.mark("name_take", trace)
        DispatchQueue.main.async { NotificationCenter.default.post(name: .montanaNameChanged, object: nil) }
        return .taken(n)
    }

    // ONE RENEWAL AT A TIME (the critic's P3): every return used to start its own, and links were published twice.
    private static let renewGate = NSLock()
    private static var renewing = false
    private static func claimRenewal() -> Bool {
        renewGate.lock(); defer { renewGate.unlock() }   // LOCK-OK: one flag in memory
        if renewing { return false }
        renewing = true
        return true
    }
    private static func endRenewal() {
        renewGate.lock(); renewing = false; renewGate.unlock()   // LOCK-OK: one flag in memory
    }

    /// Extends the term at the keeper with the next link. The step moves only when the keeper takes it, the term is
    /// the keeper's word, and after every renewal the reveal under the name is read: a name that carries another key
    /// is not this device's, whatever its chain says (the critic's P1).
    static func renew(masterSeed: Data) async {
        guard claimRenewal() else { MontanaP2PTrace.mark("name_renew", "one renewal is already on its way"); return }
        await renewOnce(masterSeed, again: true)
        endRenewal()
    }

    private static func renewOnce(_ master: Data, again: Bool) async {
        guard let n = MontanaNames.currentName, let step = MontanaNames.heldStep,
              let ch = MontanaNames.heldChain(masterSeed: master), let sl = MontanaNames.slot(normalized: n) else { return }
        let next = step + 1
        guard next <= MontanaNames.chainLength else { MontanaP2PTrace.mark("name_renew", "the chain is spent"); return }
        let window = UInt32(MTPipe.window())
        let (code, obj) = await askFirst("/name-renew", ["slot": sl.montanaHexString, "link": ch[next].montanaHexString])
        switch code {
        case 200 where (obj["again"] as? Bool) == true:
            // The keeper already held that link: the answer to its publishing was lost. The term stands as the keeper
            // says it; the renewal that was due is the link after it, once.
            MontanaNames.renewed(step: next, window: nil, until: obj["until"] as? Double)
            MontanaP2PTrace.mark("name_renew", "again at step \(next)")
            if again { await renewOnce(master, again: false) }
        case 200:
            MontanaNames.renewed(step: next, window: window, until: obj["until"] as? Double)
            MontanaP2PTrace.mark("name_renew", "ok step=\(next)")
            if await ownsSlot(n, master: master) == false { lost("another key stands under the name") }
        case 409:
            switch await ownsSlot(n, master: master) {
            case true?: await walk(from: next + 1, chain: ch, slot: sl)
            case false?: lost("another chain holds the slot")
            case nil: MontanaP2PTrace.mark("name_renew", "409 and the reveal did not come — asked again at the next return")
            }
        case 404 where nobody(code, obj):
            // The keeper holds no such name: the term lapsed unseen. It is taken again from the first link this phone
            // has not published; a stranger who took it meanwhile answers «held», and the phone lets it go out loud.
            guard let p = MontanaNames.prepare(n, masterSeed: master) else { return }
            switch await probe(p, from: next, master: master) {
            case .taken(let s, let until):
                MontanaNames.hold(p, window: window, step: s, until: until)
                MontanaP2PTrace.mark("name_renew", "taken again at step \(s)")
            case .ours(let s):
                MontanaNames.hold(p, window: window, step: s, until: nil)
            case .held:
                lost("taken by another after a lapse")
            default:
                MontanaP2PTrace.mark("name_renew", "the retaking did not go through — asked again at the next return")
            }
        default:
            MontanaP2PTrace.mark("name_renew", "code=\(code) — asked again at the next return")
        }
    }

    /// The phone stands behind the keeper on its own chain (a copy restored, answers lost): it walks forward to the
    /// link the keeper holds. Bounded: a phone that has not caught up in sixteen links is not on this chain.
    private static func walk(from start: Int, chain ch: [Data], slot sl: Data) async {
        let window = UInt32(MTPipe.window())
        var k = start
        while k <= min(start + 15, MontanaNames.chainLength) {
            let (code, obj) = await askFirst("/name-renew", ["slot": sl.montanaHexString, "link": ch[k].montanaHexString])
            if code == 200 {
                let again = (obj["again"] as? Bool) == true
                MontanaNames.renewed(step: k, window: again ? nil : window, until: obj["until"] as? Double)
                if again, k + 1 <= MontanaNames.chainLength {
                    let (c2, o2) = await askFirst("/name-renew", ["slot": sl.montanaHexString, "link": ch[k + 1].montanaHexString])
                    if c2 == 200 { MontanaNames.renewed(step: k + 1, window: window, until: o2["until"] as? Double) }
                }
                MontanaP2PTrace.mark("name_renew", "caught up at step \(k)")
                return
            }
            if code != 409 { MontanaP2PTrace.mark("name_renew", "the walk stopped code=\(code)"); return }
            k += 1
        }
        lost("the keeper holds a chain this phone does not continue")
    }

    /// The name is not this device's any more. The record goes, the device stops listening at its point, the code
    /// page falls back to the permanent card, and the person is told — never a silent disappearance.
    private static func lost(_ why: String) {
        MontanaNames.forget()
        MontanaP2PTrace.mark("name_lost", why)
        MTPipeBook.dropFirstIndex()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .montanaNameChanged, object: nil)
            NotificationCenter.default.post(name: .montanaMeetVerdict, object: nil,
                                            userInfo: ["msg": "Your name is no longer yours: the node that keeps names holds another key under it."])
        }
    }

    /// THE NAME LEAVES WITH THE ACCOUNT (App Review 5.1.1(v), 08.10.2026): the name this device holds is released at its keeper
    /// as a new name releases the one before it -- with the next link of its chain, while the words still derive it.
    static func releaseHeld() async {
        guard MontanaNames.isHeld(), let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn),
              let held = MontanaNames.nextRenewal(masterSeed: master) else { return }
        await release(slot: held.slot, link: held.link)
    }
    /// The name held before a new one: released with a link nobody has seen. A keeper out of reach leaves it to
    /// lapse by its term — the device no longer renews it either way.
    private static func release(slot: Data, link: Data) async {
        let (code, obj) = await askFirst("/name-drop", ["slot": slot.montanaHexString, "link": link.montanaHexString])
        if code == 200 { MontanaP2PTrace.mark("name_release", "released") }
        else if nobody(code, obj) { MontanaP2PTrace.mark("name_release", "the keeper held nothing — it had lapsed") }
        else { MontanaP2PTrace.mark("name_release", "code=\(code) — the former name lapses by its term") }
    }
}

extension Notification.Name { static let montanaNameChanged = Notification.Name("montanaNameChanged") }


// ── The card: acquaintance when no name has been claimed ─────────────────────────────────────
//
// A name is the ordinary way to be met, and it needs the plane of names to answer with a contact
// key. Until that plane carries over the mesh — and for a person who holds no name at all, whom
// the set says is indistinguishable from someone who does not exist — there remains the shape the
// set gives such a meeting: a card handed over once, in person or down any channel the two already
// trust.
//
// The card carries a fresh encapsulation key and nothing else. Not a name, not a number, nothing
// that outlives the meeting: whoever photographs it over a shoulder learns one key that opens one
// correspondence with its owner, and learns nothing about any other. The secret both sides end up
// with is derived exactly as the secret of a first letter is derived — one mechanism, one domain,
// one set of frozen vectors.
enum MontanaCard {

    static let prefix = "montana://c/"
    /// A rendezvous invitation: only 32 bytes in the code; the full meeting key is exchanged by the
    /// sides through the storage node at the moment of the scan. The link is 30 times shorter, the QR coarse-module.
    static let shortPrefix = "montana://r/"
    /// THE LINK IS A WEB LINK (15.15, the author's word 07.09: «clickable always and everywhere»).
    /// A custom scheme is plain text in every other messenger and in mail; an https link is a link
    /// everywhere, opens this app through the associated domain when it is installed, and lands on
    /// montana.quest/r/ otherwise — a page that offers the app and carries the scheme form for a
    /// build that only knows it ([P2P-COMPAT]: both forms are read, the web form is written).
    static let webPrefix = "https://montana.quest/r/"
    /// THE KIND IN THE LINK (the author's word 17.09): /perp/ for the permanent link, /temp/ for the
    /// daily one. All three forms are read; the site's page for each hands the scheme form to a
    /// build that knows only montana://r/ ([P2P-COMPAT]).
    static let permPrefix = "https://montana.quest/perp/"
    static let tempPrefix = "https://montana.quest/temp/"
    /// ONE CARD, ONE NODE, TWO SITES (07.10.2026, carried over from MT Business): the Business writes its invitations on
    /// montana.xxx, whose page opens Montana by montana://r/ where only Montana stands. This app writes montana.quest and
    /// reads the /r/, /perp/ and /temp/ forms of both sites -- the hosts the Business reads -- so its own scanner opens a
    /// Business code as well.
    static let linkHosts = Set(["montana.quest", "montana.xxx", "www.montana.xxx"])
    /// Every written form an invitation is read from.
    static let readPrefixes: [String] =
        linkHosts.sorted().flatMap { h in ["r", "perp", "temp"].map { k in "https://" + h + "/" + k + "/" } } + [shortPrefix]
    private static let store = "cardKeys"
    /// One lock for BOTH stores (card keys and invitations): spending in the mesh flow and the birth
    /// of a new card on the main one ran in parallel, and the read-modify-write of the spend erased a
    /// fresh secret with its own stale snapshot. Result: the invitation exists on screen and on the
    /// node, the secret nowhere -- the scanner knocks forever (precedent 19:00: rdv_up ok with cards=0).
    static let cardLock = NSRecursiveLock()
    /// UNDER THE LOCK — ONLY THE WORD IN MEMORY; THE VAULT FOLLOWS, IN ORDER (25.09, the tablet: two deaths at one
    /// activation, 15:19:53 and 15:31, iPadOS's report 0x8BADF00D). A vault write is a synchronous broadcast: UserDefaults
    /// posts its change on the writing thread, and every @AppStorage observer answers by taking SwiftUI's graph lock —
    /// the lock the main thread holds for the whole of a screen update. The birth of the day's card wrote its record
    /// under cardLock on a utility thread and stood there for the graph lock, while the main thread, inside the update
    /// that sends the daily link to everyone, stood for cardLock: nobody moved, and the system ended the app ten seconds
    /// after it left the screen. So no record reaches the vault under the lock: the lock covers the records in memory and
    /// the ORDER of their writes, and each write leaves on one serial queue in that order — the vault's last word for a
    /// record is the memory's, and a reader under the lock still sees the records as one snapshot. Every record is read
    /// from the vault once; a copy laid over the store hands its values in by the same door (lay), and a departing
    /// person's records leave by it (wipe), so no write of the moment before lands over either (tools/mt-lock-check.py,
    /// rule 4). What is written here in memory is exactly what the vault will hold; nothing else reads these keys.
    private static let cardIO = DispatchQueue(label: "montana.card.io", qos: .utility)
    private static var held: [String: Data?] = [:]   // a record by its vault key: the truth once read; nil — the vault has none
    private static var owned: [String] { [store, rdvStore, rdvPermKey, rdvCurrentKey, rdvBornKey] }
    /// A record, under cardLock: the memory's word, or the vault's on the first ask.
    private static func record(_ key: String) -> Data? {
        if let h = held[key] { return h }
        let d = MontanaLocalVault.getDecrypted(key)
        if MontanaDeviceKey.key != nil { held[key] = .some(d) }   // a sealed vault must not latch «nothing» (the class of 22.08)
        return d
    }
    /// A record's new word, under cardLock: memory now, the vault next in order. False when the vault would refuse it
    /// (no device key): nothing is promised that will not be kept.
    @discardableResult
    private static func write(_ key: String, _ d: Data) -> Bool {
        guard MontanaDeviceKey.key != nil else { return false }
        held[key] = .some(d)
        cardIO.async {
            if !MontanaLocalVault.setEncrypted(key, d) { MontanaP2PTrace.mark("card_write", "REFUSED key=\(key)") }
        }
        return true
    }
    /// The vault keys the card store answers for — a copy lays their values through the store, never around it.
    static func owns(_ key: String) -> Bool { owned.contains(key) }
    /// A value laid by a copy: merged with what stands here by the copy's own law, written in order after every write
    /// already on its way, and the memory holds it at once.
    static func lay(_ key: String, _ d: Data, merge: ((Data) -> Data)? = nil) {
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: the read-modify-write of a laid record
        let word: Data
        if let merge, let have = record(key) { word = merge(have) } else { word = d }
        write(key, word)
    }
    /// The store was replaced under the living: the records are read again — after every write on its way has landed.
    static func forgetHeld() { cardIO.async { cardLock.lock(); held = [:]; cardLock.unlock() } }
    /// A move between seats (MTSeats) goes on after every record already on its way has landed: the next step runs on the
    /// main thread once the queue has written them, and the main thread never waits on the queue.
    static func afterWrites(_ then: @escaping () -> Void) { cardIO.async { DispatchQueue.main.async(execute: then) } }
    /// The person leaves: the records go by the same door, after every write already on its way.
    static func wipe() {
        cardIO.async {
            for k in owned { UserDefaults.standard.removeObject(forKey: k) }
            cardLock.lock(); held = [:]; cardLock.unlock()
        }
    }

    static func isShort(_ text: String) -> Bool {
        invite(inShort: text) != nil
    }
    static func invite(inShort text: String) -> Data? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let form = readPrefixes.first(where: { p in t.hasPrefix(p) }) else { return nil }
        let code = String(t.dropFirst(form.count))
        guard let d = Data(base64urlNoPad: code), d.count == 32 else { return nil }
        return d
    }
    private static func rdvKey(_ invite: Data) -> Data {
        var m = Data("mt-rdv-k".utf8); m.append(0); m.append(invite)
        return Data(SHA256.hash(data: m))
    }
    private static func rdvBid(_ invite: Data) -> String {
        var m = Data("mt-rdv-a".utf8); m.append(0); m.append(invite)
        return SHA256.hash(data: m).map { String(format: "%02x", $0) }.joined()
    }

    // ── THE PERMANENT CARD (the author's word 17.09): the same card, never rotated and never buried.
    // The daily code is a temporary link; the permanent one is a standing address of one's own
    // choosing — whoever holds it can always write. It lives in its own record so the daily
    // rotation never tombs it; its secret lies in the one card-key store like every other card's.
    // Beside it on the node lies a small mark under its own bid: a new build that met through this
    // link asks the mark and keeps the person in its book; an old build never asks ([P2P-COMPAT]).
    private static let rdvPermKey = "rdvPermanent"
    private static let permMagic = "mt-rdv-perm"
    private static func permLoad() -> [String: Data] {
        guard let d = record(rdvPermKey),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }
    private static func permSave(_ m: [String: Data]) {
        if let d = try? JSONEncoder().encode(m) { write(rdvPermKey, d) }
    }
    /// Every live invitation — the daily generations and the permanent one.
    private static func rdvAll() -> [String: Data] { rdvLoad().merging(permLoad()) { a, _ in a } }
    private static func permBid(_ invite: Data) -> String {
        var m = Data("mt-rdv-p".utf8); m.append(0); m.append(invite)
        return SHA256.hash(data: m).map { String(format: "%02x", $0) }.joined()
    }
    private static func uploadPermMark(invite: Data) {
        guard let sealed = MontanaP2PDirect.seal(key: [UInt8](rdvKey(invite)), Data(permMagic.utf8)) else { return }
        Task {
            var ok = await MontanaWakePush.putBlob(permBid(invite), data: sealed, over: true)
            MontanaP2PTrace.mark("rdv_perm_up", "\(ok ? "ok" : "FAIL") bid=\(String(permBid(invite).prefix(8)))")
            guard !ok else { return }
            try? await Task.sleep(nanoseconds: 20_000_000_000)   // the permanent mark, like its card, tries once more
            ok = await MontanaWakePush.putBlob(permBid(invite), data: sealed, over: true)
            MontanaP2PTrace.mark("rdv_perm_up", "\(ok ? "ok" : "FAIL") bid=\(String(permBid(invite).prefix(8))) late=1")
        }
    }
    /// The scanner's side: was the link a permanent one? Asked once, after the meeting.
    static func isPermanent(invite: Data) async -> Bool {
        guard let sealed = await MontanaWakePush.getBlob(permBid(invite)),
              let d = MontanaP2PDirect.open(key: [UInt8](rdvKey(invite)), sealed) else { return false }
        return d == Data(permMagic.utf8)
    }
    /// The offering side: did the letter come through the permanent card's point?
    static func isPermanentRoot(_ root: Data) -> Bool {
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: one read of the permanent record
        return permLoad().values.contains { $0.prefix(1184) == root }
    }
    /// The permanent link: born once, shown as long as the person keeps it, topped up by term.
    static func offerPermanent() -> String? {
        var live: (cur: String, inv: Data, payload: Data)? = nil
        cardLock.lock()   // LOCK-OK: the permanent record and the card keys read as one snapshot
        if let (cur, payload) = permLoad().first, let inv = Data(base64urlNoPad: cur),
           load()[payload.prefix(1184).base64urlNoPad] != nil {
            live = (cur, inv, payload)
        }
        cardLock.unlock()
        if let live {
            // THE BODY WEARS TODAY'S NAME AT EVERY SHOWING (21.09, measured: the tablet's card still carried
            // the callsign of its birth after a rename, and the two-hourly refresh put that snapshot back
            // on the node as it was). The record holds the key; the name is the profile's alone — the
            // one owner — and is appended here, at the moment the link is shown.
            let np = reminted(live.payload)
            let renamed = np != live.payload
            if renamed {
                cardLock.lock(); permSave([live.cur: np]); cardLock.unlock()   // LOCK-OK: one rewrite of the permanent record
                MontanaP2PTrace.mark("rdv_reminted", "cards=1 name=1 at=show")
            }
            let last = UserDefaults.standard.double(forKey: "rdvPermUpOk")
            if renamed || Date().timeIntervalSince1970 - last > 7200 {
                uploadRdv(invite: live.inv, payload: np, stamp: "rdvPermUpOk")
                uploadPermMark(invite: live.inv)
            }
            return permPrefix + live.cur
        }
        // The birth writes the permanent record as one step under the lock; the trace and the
        // uploads run with the lock let go (tools/mt-lock-check.py). The randomness — the card
        // seed and the invitation — is drawn BEFORE the lock (19.09): the first draw of a process
        // gathers six sources, and under cardLock on the main thread it stood 4.6 s until the
        // system's watchdog (1614).
        guard let seed = cardSeed(), let invite = inviteBytes() else { return nil }
        cardLock.lock()   // LOCK-OK: the birth of the permanent card writes its record as one step
        guard let full = offer(seed: seed), let payload = payload(inCard: full) else { cardLock.unlock(); return nil }
        permSave([invite.base64urlNoPad: payload])
        cardLock.unlock()
        uploadRdv(invite: invite, payload: payload, stamp: "rdvPermUpOk")
        uploadPermMark(invite: invite)
        MontanaP2PTrace.mark("rdv_perm", "born")
        return permPrefix + invite.base64urlNoPad
    }

    /// THE STANDING LINK (24.09, the author's word: «a link to one's profile that stands, instead of the
    /// current permanent one»): the name's own web link when a name is held — readable, resolved by the plane
    /// of names — and the permanent card otherwise. The permanent card stays up behind it either way
    /// (keepLiveCardsUp), so every /perp/ link already handed out keeps working ([P2P-COMPAT]).
    static func offerStanding() -> String? {
        // The permanent card is born and kept up either way: it is what every /perp/ link already out opens.
        let card = offerPermanent()
        return MontanaFirstContact.invitation() ?? card
    }

    /// THE CARDS WEAR THE NAME OF TODAY (21.09): a rename re-mints the body of the permanent card and
    /// of the living daily one — the same key, the same link in everyone's hands, a new name behind
    /// it on the node. Without this the permanent card carried the callsign of the day it was born
    /// for the rest of its life, and every scan named the person by it.
    /// The card's key with the profile's name of this moment behind it — the only way a body is made.
    private static func reminted(_ payload: Data) -> Data {
        let mine = E2E.myDisplayName().trimmingCharacters(in: .whitespacesAndNewlines)
        var p = payload.prefix(1184)
        if !mine.isEmpty, let d = mine.data(using: .utf8), d.count <= nameLimit { p.append(d) }
        return p
    }
    static func refreshCards() {
        let mine = E2E.myDisplayName().trimmingCharacters(in: .whitespacesAndNewlines)
        var ups: [(Data, Data, Bool)] = []
        cardLock.lock()   // LOCK-OK: the two card records are rewritten as one step; the uploads run after
        var perm = permLoad()
        for (inv64, pl) in perm {
            let np = reminted(pl)
            guard np != pl, let inv = Data(base64urlNoPad: inv64) else { continue }
            perm[inv64] = np; ups.append((inv, np, true))
        }
        if !ups.isEmpty { permSave(perm) }
        var daily = rdvLoad()
        let cur = record(rdvCurrentKey).flatMap { String(data: $0, encoding: .utf8) }
        var dailyChanged = false
        for (inv64, pl) in daily where inv64 == cur {
            let np = reminted(pl)
            guard np != pl, let inv = Data(base64urlNoPad: inv64) else { continue }
            daily[inv64] = np; dailyChanged = true; ups.append((inv, np, false))
        }
        if dailyChanged { rdvSave(daily) }
        cardLock.unlock()
        for (inv, np, isPerm) in ups {
            uploadRdv(invite: inv, payload: np)
            if isPerm { uploadPermMark(invite: inv) }
        }
        if !ups.isEmpty { MontanaP2PTrace.mark("rdv_reminted", "cards=\(ups.count) name=\(mine.isEmpty ? 0 : 1)") }
    }

    private static let rdvStore = "rdvCards"
    private static func rdvLoad() -> [String: Data] {
        guard let d = record(rdvStore),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }
    @discardableResult private static func rdvSave(_ m: [String: Data]) -> Bool {
        guard let d = try? JSONEncoder().encode(m) else { return false }
        return write(rdvStore, d)
    }

    /// The short card is the ONE showing: the code is born instantly (invitation and key are local),
    /// the key blob is poured onto the node in the background with retries and re-laid on every start
    /// while the card lives -- a stale blob heals itself.
    /// Privacy is unchanged: whoever knows the invitation gets ONLY the public key (one can write,
    /// there is nothing to read with); the card secret never leaves the device, spending as always.
    /// The vault key: the invitation of the LIVE card. One live code per device: showing the screen
    /// does NOT change it, only SPENDING does. Before, every showing gave birth to a new card -- five
    /// listening points accumulated, and a repeat introduction on a live chat started a twin chat.
    private static let rdvCurrentKey = "rdvCurrent"

    /// The author's word 22.08: the code, the link and their unfolding share ONE term -- exactly one
    /// day. The code changes neither from a showing nor from a meeting; exactly 24 hours later the
    /// next one is born, and the old gets a gravestone -- yesterday's link honestly answers "spent".
    static let cardLifetimeSeconds: TimeInterval = 24 * 3600
    private static let rdvBornKey = "rdvCurrentBorn"
    /// The live daily link together with the moment it was born: what a correspondent may hand
    /// on for us. Born is what makes the copy honest: the receiver knows when it dies.
    static func currentShortWithBorn() -> (link: String, born: TimeInterval)? {
        guard let link = offerShort() else { return nil }
        cardLock.lock(); let mark = record(rdvBornKey); cardLock.unlock()   // LOCK-OK: one read of the birth mark
        let born = mark.flatMap { String(data: $0, encoding: .utf8) }.flatMap { TimeInterval($0) }
            ?? Date().timeIntervalSince1970
        return (link, born)
    }
    private static func currentAge() -> TimeInterval? {
        guard let d = record(rdvBornKey),
              let s = String(data: d, encoding: .utf8), let t = TimeInterval(s) else { return nil }
        return Date().timeIntervalSince1970 - t
    }

    /// THE LIVE CARDS STAY UP, BY TERM (24.09, the noticed point 1). The daily card's turn (rotateIfStale) had one
    /// caller, applicationDidBecomeActive, which UIKit never calls: the card turned only when something asked for it, and
    /// its blob and the permanent card's were topped up only at a showing. On every return to the person: the daily card
    /// is born anew when its day is over (offerShort, whose birth rings its own doorbell), and each live card is topped
    /// up at most once in two hours — never at every opening, which was a beacon of the owner's activity for the node (the
    /// card audit, stage 24b). A permanent card is kept up only when the person holds one: none is born here.
    static func keepLiveCardsUp() {
        guard MontanaSeed.hasSeed else { return }   // SILENT-OK: the first screen — no identity, no card (the second critic's pass)
        _ = offerShort()
        if hasLivePermanent() { _ = offerPermanent() }
    }
    /// The permanent card the person holds, whole: its key in place. A record whose key is gone is no card, and
    /// offerPermanent would give birth to another — a standing address changes only by the person's own hand.
    private static func hasLivePermanent() -> Bool {
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: one read of the permanent record and the card keys
        guard let payload = permLoad().first?.value else { return false }
        return load()[payload.prefix(1184).base64urlNoPad] != nil
    }

    static func offerShort() -> String? {
        // THE LIVE CARD IS READ UNDER THE LOCK, THE TOP-UP ACTS AFTER IT (16.09): the code screen asks
        // this on the main thread; a receive holding the lock over a network call would stall it.
        var live: (cur: String, inv: Data, payload: Data)? = nil
        cardLock.lock()   // LOCK-OK: the two card records are read as one snapshot
        let m0 = rdvLoad()
        if let cur = record(rdvCurrentKey).flatMap({ String(data: $0, encoding: .utf8) }),
           let payload = m0[cur], let inv = Data(base64urlNoPad: cur),
           load()[payload.prefix(1184).base64urlNoPad] != nil,   // the secret is in place -- the card is whole
           let age = currentAge(), age < cardLifetimeSeconds {   // and the day still has time to run
            live = (cur, inv, payload)
        }
        cardLock.unlock()
        if let live {
            // Topping up goes BY TERM, not on every showing or activation: a per-showing top-up was a
            // beacon of the owner's activity for the node (the card audit, stage 24b). Once in two hours
            // is enough: the node blob lives for days, and the daily rotation lays out a new one itself.
            let last = UserDefaults.standard.double(forKey: "rdvUpOk")
            if Date().timeIntervalSince1970 - last > 7200 {
                uploadRdv(invite: live.inv, payload: live.payload, stamp: "rdvUpOk")
            }
            return tempPrefix + live.cur
        }
        // The current one without a secret (a victim of the old race) is dead: a scanner would knock forever.
        // From here the ordinary path: a new card, the old ones spent — the read-modify-write of both
        // stores is one step under the lock. The randomness is drawn before it (19.09, see offerPermanent).
        guard let seed = cardSeed(), let invite = inviteBytes() else { return nil }
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: the birth of a card rewrites both card records as one step
        // THE BIRTH LOOKS AGAIN UNDER ITS LOCK (24.09, the second critic's pass): the snapshot above is read before the
        // randomness, and two askers of one activation — the daily link to every correspondent on the main thread, the
        // cards kept up off it — both found the day over and both gave birth: the second, working from the stale
        // snapshot, erased the secret of yesterday's card while letters were still on their way to it, and left the
        // first newborn a secret without a record. A card born meanwhile is the card.
        let m = rdvLoad()
        let prev = record(rdvCurrentKey).flatMap { String(data: $0, encoding: .utf8) }
        if let prev, let pl = m[prev], load()[pl.prefix(1184).base64urlNoPad] != nil,
           let age = currentAge(), age < cardLifetimeSeconds {
            return tempPrefix + prev
        }
        guard let full = offer(seed: seed), let payload = payload(inCard: full) else { return nil }
        // A new daily code extinguishes old LINKS immediately (a gravestone on the blob -- yesterday's
        // tap answers "spent"), but the PREVIOUS generation still ACCEPTS: a letter honestly sent on
        // its day and still travelling has no right to die of a rotation (E-1: a return from sleep
        // longer than 24 h would kill travelling letters as first_miss). The previous secret lives
        // until the next rotation; older ones are buried whole.
        var keep: [String: Data] = [:]
        if let prev, let pl = m[prev] { keep[prev] = pl }   // the receiving generation: the secret stays
        keep[invite.base64urlNoPad] = payload
        // A CARD THAT DID NOT SETTLE IS NO CARD (24.09, the second critic's pass): with the vault shut the writes fell
        // through unread, every asker gave birth again, and the doorbell below — whose redraw asks again — made a loop of
        // it. The birth counts once the vault will keep it — a device key in hand, the record's word in memory and its
        // write on the queue (25.09); until then nothing is buried, laid on the node or rung for.
        guard rdvSave(keep),
              write(rdvCurrentKey, Data(invite.base64urlNoPad.utf8)),
              write(rdvBornKey, Data(String(Date().timeIntervalSince1970).utf8)) else {
            var keys = load(); if keys.removeValue(forKey: payload.prefix(1184).base64urlNoPad) != nil { save(keys) }
            DispatchQueue.main.async { MontanaP2PTrace.mark("rdv_born", "FAIL unsettled") }
            return nil
        }
        for (inv64, pl) in m {
            if let oldInv = Data(base64urlNoPad: inv64),
               let tomb = MontanaP2PDirect.seal(key: [UInt8](rdvKey(oldInv)), Data(spentMagic.utf8)) {
                Task { _ = await MontanaWakePush.putBlob(rdvBid(oldInv), data: tomb, over: true) }
            }
            if inv64 == prev { continue }   // the receiving generation: the secret stays
            let root64 = pl.prefix(1184).base64urlNoPad
            var keys = load(); if keys.removeValue(forKey: root64) != nil { save(keys) }
        }
        MTPipeBook.dropFirstIndex()
        // THE TERM STARTS AT THE BIRTH (24.09, the second critic's pass): the birth laid the card without its stamp, and
        // the next asker laid it again at once, face and all.
        cardIO.async {   // in order after the record; the term's stamp is the node's word, written by uploadRdv (07.10)
            uploadRdv(invite: invite, payload: payload, stamp: "rdvUpOk")
        }
        // A NEW DAILY CARD RINGS ITS OWN DOORBELL (24.09, the noticed point 1): the turn registered the new invitation only
        // through rotateIfStale, which no road called — a card born here stood unregistered at the node, and the first
        // letter of whoever scanned it woke nobody, nor could the extension open it (mirrorSecrets). The registration and
        // the code screen's redraw leave once the card's lock is let go.
        DispatchQueue.main.async {
            MontanaP2PTrace.mark("rdv_born", "daily")
            MontanaWakePush.registerConvs()
            NotificationCenter.default.post(name: .montanaCardSpent, object: nil)   // the screen, if open, draws the new one
        }
        return tempPrefix + invite.base64urlNoPad
    }

    /// A CARD THAT DID NOT REACH THE NODE IS NOT COUNTED AS UP (23.09, the class of «the code did not work the first
    /// time»): the term stamp was written before the answer, so a card whose three tries all failed stood off the node
    /// until the next launch or two hours later, and every scan of it in between was refused. A failed card tries once
    /// more twenty seconds later; a card no node took keeps no stamp, and the next showing of the code lays it again.
    /// THE STAMP IS THE NODE'S WORD, NOT THE INTENT (06.10.2026, measured in MT Business, whose card code is this file's: T1
    /// scanned T2's code and T2 scanned T1's, and every node answered "gone" for both). T1's permanent card was born in a
    /// process the installer ended before its upload ran, and the term's stamp, written BEFORE the upload, kept every later
    /// showing from laying it for two hours -- the code on the screen named a card no node held. Carried over here on
    /// 07.10.2026: the stamp is written when a node took the card, and only while the card is still the seat's own (a person
    /// may change seats while it flies); a card on its way is not sent again by the same process. The stamps carry new names
    /// (rdvPermUpOk, rdvUpOk) that only a node's ok ever wrote, so a stamp an earlier build wrote before its upload decides nothing.
    private static let flyLock = NSLock()
    private static var flying = Set([String]())
    private static func takeOff(_ bid: String) -> Bool {
        flyLock.lock(); defer { flyLock.unlock() }   // LOCK-OK: one word in memory
        return flying.insert(bid).inserted
    }
    private static func landed(_ bid: String) {
        flyLock.lock()   // LOCK-OK: one word in memory
        flying.remove(bid)
        flyLock.unlock()
    }
    /// The card is still the one its stamp speaks for: the person's permanent card, or the current daily one.
    private static func stillOwn(_ invite: Data, stamp: String) -> Bool {
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: one read of the card records
        let code = invite.base64urlNoPad
        if stamp == "rdvPermUpOk" { return permLoad()[code] != nil }
        return record(rdvCurrentKey).flatMap { d in String(data: d, encoding: .utf8) } == code
    }
    private static func uploadRdv(invite: Data, payload: Data, stamp: String? = nil) {
        let bid = rdvBid(invite)
        guard takeOff(bid) else { return }   // this card is on its way already
        guard let sealed = MontanaP2PDirect.seal(key: [UInt8](rdvKey(invite)), payload) else { landed(bid); return }
        Task {
            defer { landed(bid) }
            var ok = await MontanaWakePush.putBlob(bid, data: sealed, over: true)
            MontanaP2PTrace.mark("rdv_up", "\(ok ? "ok" : "FAIL") bid=\(String(bid.prefix(8)))")
            if !ok {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                ok = await MontanaWakePush.putBlob(bid, data: sealed, over: true)
                MontanaP2PTrace.mark("rdv_up", "\(ok ? "ok" : "FAIL") bid=\(String(bid.prefix(8))) late=1")
            }
            // A card no node took keeps no stamp: the next showing lays it again.
            if ok, let stamp, stillOwn(invite, stamp: stamp) { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stamp) }
        }
        uploadFace(invite: invite)
    }

    // ── The face beside the card (15.32, the author's word 07.09: «opening the link, I must
    // already see the face»). The card carries the key and the name; the face rode only in the
    // first letter after the meeting, so a fresh chat stood under a drawn initial. Now the face
    // lies on the node under the SAME invitation, in its own blob and under its own key: a build
    // that knows nothing of it never asks, an unreadable blob is buried unread ([P2P-COMPAT]).
    // Whoever holds the link gets what the person hands out anyway at every first exchange.
    private static func faceBid(_ invite: Data) -> String {
        var m = Data("mt-rdv-f".utf8); m.append(0); m.append(invite)
        return SHA256.hash(data: m).map { String(format: "%02x", $0) }.joined()
    }
    private static func faceKey(_ invite: Data) -> Data {
        var m = Data("mt-rdv-fk".utf8); m.append(0); m.append(invite)
        return Data(SHA256.hash(data: m))
    }
    private static func faceStamp(_ invite: Data) -> String { "rdvFaceUp:" + invite.base64urlNoPad }

    /// The face goes up with the card and is topped up by term; the same face is not poured
    /// again while its record is fresh. A cleared face leaves an empty blob — «no face» is an
    /// answer, so yesterday's picture cannot outlive its owner's decision.
    private static func uploadFace(invite: Data) {
        let face = UserDefaults.standard.data(forKey: "avatarData") ?? Data()
        let stamp = faceStamp(invite)
        let fp = SHA256.hash(data: face).map { String(format: "%02x", $0) }.joined().prefix(16)
        if let last = UserDefaults.standard.string(forKey: stamp) {
            let parts = last.split(separator: ":")
            if parts.count == 2, parts[0] == fp, let at = Double(parts[1]),
               Date().timeIntervalSince1970 - at < 5 * 86400 { return }
        } else if face.isEmpty { return }   // nothing lay beside the card, nothing to clear
        guard let sealed = MontanaP2PDirect.seal(key: [UInt8](faceKey(invite)), face) else { return }
        Task {
            let ok = await MontanaWakePush.putBlob(faceBid(invite), data: sealed, over: true)
            if ok { UserDefaults.standard.set(fp + ":" + String(Date().timeIntervalSince1970), forKey: stamp) }
            MontanaP2PTrace.mark("rdv_face_up", "\(ok ? "ok" : "FAIL") bytes=\(face.count) bid=\(String(faceBid(invite).prefix(8)))")
        }
    }

    /// The scanner's side: the face the inviter published under this invitation, or nil.
    static func face(invite: Data) async -> Data? {
        guard let sealed = await MontanaWakePush.getBlob(faceBid(invite)),
              let d = MontanaP2PDirect.open(key: [UInt8](faceKey(invite)), sealed),
              !d.isEmpty, d.count <= 262_144 else { return nil }
        return d
    }

    /// My face changed: every live card gets the new one beside it at once.
    static func faceChanged() { reuploadRdv() }

    /// Every live card goes onto the node again — a new face, a restored copy: a blob has no right to go stale before its
    /// card. Spent ones are cleaned out by the spending (accept). Not at every opening: that is keepLiveCardsUp, by term.
    static func reuploadRdv() {
        for (inv64, payload) in rdvAll() {
            guard let inv = Data(base64urlNoPad: inv64) else { continue }
            uploadRdv(invite: inv, payload: payload)
        }
        for inv64 in permLoad().keys { if let inv = Data(base64urlNoPad: inv64) { uploadPermMark(invite: inv) } }
    }

    private static func rdvForget(root: Data) {
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: read-modify-write of the invitation record and the current-card mark
        var m = rdvLoad()
        let before = m.count
        let spent = m.filter { $0.value.prefix(1184) == root }.keys
        m = m.filter { !($0.value.prefix(1184) == root) }
        if m.count != before { rdvSave(m) }
        // A link outlives a card: the node blob survived the spending, and a stale tap unfolded into
        // an endless knock at a point nobody listens to. A gravestone under the same bid closes the
        // unfolding with an honest "spent" (F-3).
        for inv64 in spent {
            guard let inv = Data(base64urlNoPad: inv64),
                  let tomb = MontanaP2PDirect.seal(key: [UInt8](rdvKey(inv)), Data(spentMagic.utf8)) else { continue }
            Task {
                UserDefaults.standard.removeObject(forKey: "rdvFaceUp:" + inv64)
                let ok = await MontanaWakePush.putBlob(rdvBid(inv), data: tomb, over: true)
                MontanaP2PTrace.mark("rdv_tomb", "\(ok ? "ok" : "FAIL") inv=\(String(inv64.prefix(8)))")
            }
        }
        // The current one is spent -- the code has served its one meeting: the screen, if open, draws a new one.
        if let cur = record(rdvCurrentKey).flatMap({ String(data: $0, encoding: .utf8) }),
           spent.contains(cur) {
            write(rdvCurrentKey, Data())
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .montanaCardSpent, object: nil)
            }
        }
    }

    /// Scanning a short code: invitation -> blob from the node -> an ordinary card. From there the
    /// whole introduction mechanics is as before, to the byte.
    /// "Did not unfold" and "spent" are different answers (a rhyme with 6.8: a break is not "the node
    /// said NO"): a break waits and retries, while a gravestone from a live node means "the card is
    /// spent, the link is dead forever" -- and that is said to the person aloud, not to a journal (F-3, F-4).
    enum ExpandAnswer { case card(String); case spent; case unreachable }
    static let spentMagic = "mt-rdv-spent"

    static func expand(short text: String) async -> ExpandAnswer {
        guard let inv = invite(inShort: text) else {
            MontanaP2PTrace.mark("rdv_expand", "FAIL why=bad-invite")
            return .unreachable
        }
        for attempt in 0..<4 {
            if let sealed = await MontanaWakePush.getBlob(rdvBid(inv)),
               let payload = MontanaP2PDirect.open(key: [UInt8](rdvKey(inv)), sealed) {
                if payload == Data(spentMagic.utf8) {
                    MontanaP2PTrace.mark("rdv_expand", "spent bid=\(String(rdvBid(inv).prefix(8)))")
                    return .spent
                }
                if payload.count >= 1184, payload.count <= 1184 + nameLimit {
                    MontanaP2PTrace.mark("rdv_expand", "ok try=\(attempt + 1)")
                    return .card(prefix + payload.base64urlNoPad)
                }
            }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 900_000_000) }
        }
        MontanaP2PTrace.mark("rdv_expand", "FAIL bid=\(String(rdvBid(inv).prefix(8)))")
        return .unreachable
    }

    private static func load() -> [String: Data] {
        guard let d = record(store),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }
    private static func save(_ m: [String: Data]) {
        if let d = try? JSONEncoder().encode(m) { write(store, d) }
    }

    /// How many name bytes a card carries. The channel name announcement accepts the same: two bounds
    /// for one value would drift apart, and one of the two names would come out cut.
    /// The name from a card met again: the weakest witness, applied only past no dated word of the person.
    @MainActor static func renameFromCard(_ c: String, conv: String) {
        guard let n = MontanaCard.name(inCard: c) else { return }
        MontanaDeliveryEngine.shared.store?.setPeerName(ref: conv, name: n, at: 0, source: "card-rescan")
        MontanaP2PTrace.mark("meet_rename", "conv=\(String(conv.prefix(10)))")
    }
    /// THE FACE COMES WITH THE NAME ON A RESCAN TOO (21.09, measured 13:49:59: the name stood at once, the face
    /// only 5.5 s later — by the person's own word after the first letter, and never without one). The card's
    /// face lies beside the card under the same invitation; whoever re-reads the name re-reads the face.
    static func refaceFromCard(invite: Data, conv: String) async {
        let face = await MontanaCard.face(invite: invite)
        MontanaP2PTrace.mark("rdv_face", face == nil ? "none conv=\(String(conv.prefix(10))) rescan" : "ok bytes=\(face?.count ?? 0) conv=\(String(conv.prefix(10))) rescan")
        guard let face else { return }
        await wearFace(face, conv: conv)
    }

    /// A face fetched from the node goes on a conversation — the one road for the card's face and the pipe's.
    /// `onlyIfBare`: a face that came first by the person's own letter is kept.
    @discardableResult
    static func wearFace(_ face: Data, conv: String, onlyIfBare: Bool = false) async -> Bool {
        let shaped = MontanaSelfFace.isNormal(face) ? face : (MontanaSelfFace.normalize(face) ?? face)
        return await MainActor.run { () -> Bool in
            guard let store = MontanaDeliveryEngine.shared.store else { return false }
            if onlyIfBare, store.peerAvatars[conv] != nil { return false }
            store.setPeerAvatar(ref: conv, data: shaped, owned: true)   // the face its owner laid beside their own card
            return true
        }
    }

    /// THE OFFERING SIDE, ONCE PER CORRESPONDENCE (23.09, the author's word: «when the one who scanned my page
    /// writes, the page closes by itself»). Every road that accepts a first letter through a card — the live
    /// point, the push box, the walk — ends here: the page showing THIS card is told (the person in front of it
    /// has written), and the face laid beside the pipe is read.
    private static let metLock = NSLock()
    private static var metOnce: Set<String> = []
    private static func offerMet(ref: String, root: Data) {
        metLock.lock(); let first = metOnce.insert(ref).inserted; metLock.unlock()
        guard first else { return }
        cardLock.lock()   // LOCK-OK: one read of the invitation records
        let inv = rdvAll().first(where: { $0.value.prefix(1184) == root })?.key ?? ""
        cardLock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .montanaCardMet, object: nil, userInfo: ["inv": inv])
        }
        MontanaFirstContact.readPipeFace(conv: ref)
    }
    static let nameLimit = 64

    /// Offer a card. The keypair is drawn by the core, not by the app: the source of randomness and
    /// its health tests belong to the protocol, not to whichever implementation is holding it.
    ///
    /// A card carries the key AND THE NAME of the one showing it. The name is not an "extra value" here:
    /// a person hands the card to the very one they introduce themselves to, and without it the scanner
    /// starts a conversation with a nameless peer while the name arrives later -- that is, the chat is
    /// called something it is not for a while. The card carries nothing else: no address, no identifier, no term.
    ///
    /// The seed comes in from the caller, drawn with no lock in hand (19.09): the draw is the one
    /// step of a card's birth that may cost a gather, and a gather under a lock is a stalled thread.
    static func cardSeed() -> [UInt8]? {
        var seed = [UInt8](repeating: 0, count: 64)
        return mt_random_fast(&seed, seed.count) == 0 ? seed : nil
    }
    static func inviteBytes() -> Data? {
        var invite = Data(count: 32)
        let ok = invite.withUnsafeMutableBytes { b -> Int32 in
            guard let p = b.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return mt_random_fast(p, 32)
        }
        return ok == 0 ? invite : nil
    }
    static func offer(seed: [UInt8]) -> String? {
        cardLock.lock(); defer { cardLock.unlock() }   // LOCK-OK: read-modify-write of the card-key record
        var pk = [UInt8](repeating: 0, count: 1184), sk = [UInt8](repeating: 0, count: 2400)
        guard mt_mlkem_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        let root = Data(pk)
        var m = load()
        m[root.base64urlNoPad] = Data(sk)   // the card key stays ONE key: the name does not name it
        save(m)
        MTPipeBook.dropFirstIndex()   // one more node to listen at
        var payload = root
        let mine = E2E.myDisplayName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !mine.isEmpty, let d = mine.data(using: .utf8), d.count <= nameLimit { payload.append(d) }
        return prefix + payload.base64urlNoPad
    }

    /// The alphabet a QR code packs at five and a half bits per character instead of eight. The
    /// card is the same value either way; what changes is how many modules it takes to draw it.
    private static let b45 = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")
    private static func b45decode(_ text: String) -> [UInt8]? {
        let body = Array(text)
        var bytes = [UInt8]()
        var i = 0
        while i < body.count {
            let left = body.count - i
            guard left >= 2, let c0 = b45.firstIndex(of: body[i]), let c1 = b45.firstIndex(of: body[i + 1]) else { return nil }
            if left >= 3, let c2 = b45.firstIndex(of: body[i + 2]) {
                let v = c0 + c1 * 45 + c2 * 2025
                guard v <= 0xFFFF else { return nil }
                bytes.append(UInt8(v >> 8)); bytes.append(UInt8(v & 0xFF))
                i += 3
            } else {
                let v = c0 + c1 * 45
                guard v <= 0xFF else { return nil }
                bytes.append(UInt8(v))
                i += 2
            }
        }
        return bytes
    }
    static let qrPrefix = "MTC1:"
    static let qrShortPrefix = "MTR1:"

    /// The card as a code a camera reads quickly: a short prefix and the contact key in base45.
    static func qrText(_ text: String) -> String? {
        // A short invitation -- the LINK ITSELF goes into the code (55 characters): it is read both by
        // our scanner and by the system camera (the montana:// scheme is registered -- it will offer to open).
        // A special format at 32 bytes gives nothing while it weaned the camera off the link.
        if isShort(text) { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let root = payload(inCard: text) else { return nil }
        var out = qrPrefix
        var i = root.startIndex
        while i < root.endIndex {
            let a = Int(root[i])
            let next = root.index(after: i)
            if next < root.endIndex {
                let v = a * 256 + Int(root[next])
                out.append(b45[v % 45]); out.append(b45[(v / 45) % 45]); out.append(b45[v / 2025])
                i = root.index(after: next)
            } else {
                out.append(b45[a % 45]); out.append(b45[a / 45])
                i = next
            }
        }
        return out
    }

    /// The scanner's side of the same form: back into the text every other node already reads.
    static func text(fromQR scanned: String) -> String? {
        let s = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(qrShortPrefix) {
            guard let bytes = b45decode(String(s.dropFirst(qrShortPrefix.count))), bytes.count == 32 else { return nil }
            return webPrefix + Data(bytes).base64urlNoPad
        }
        guard s.hasPrefix(qrPrefix) else { return nil }
        guard let bytes = b45decode(String(s.dropFirst(qrPrefix.count))) else { return nil }
        guard bytes.count >= 1184, bytes.count <= 1184 + nameLimit else { return nil }
        return prefix + Data(bytes).base64urlNoPad
    }

    /// Everything a card carries: the key and, if the one showing it named themselves, their name.
    static func payload(inCard text: String) -> Data? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(prefix) else { return nil }
        let body = String(t.dropFirst(prefix.count))
        guard let d = Data(base64urlNoPad: body), d.count >= 1184, d.count <= 1184 + nameLimit else { return nil }
        return d
    }

    /// The contact key inside a card, or nil when the text is not one.
    static func root(inCard text: String) -> Data? {
        guard let d = payload(inCard: text) else { return nil }
        return d.prefix(1184)
    }

    /// The name the card holder introduced themselves by. Empty means they did not, and that is an
    /// answer, not a gap: the conversation then honestly stands under a neutral caption.
    static func name(inCard text: String) -> String? {
        guard let d = payload(inCard: text), d.count > 1184,
              let n = String(data: d.dropFirst(1184), encoding: .utf8) else { return nil }
        let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The scanner's side: one encapsulation, and the correspondence exists. What comes back is the
    /// local name of it and the ciphertext the first letter must carry.
    static func meet(card text: String) -> (reference: String, ciphertext: Data)? {
        guard let root = root(inCard: text) else {
            MontanaP2PTrace.mark("meet_refused", "side=scanner")
            return nil
        }
        let met = MontanaFirstContact.meet(contactRoot: root)
        MontanaP2PTrace.mark(met != nil ? "meet_card" : "meet_refused", "side=scanner")
        return met
    }

    /// The offering side: a first letter arrived carrying its ciphertext, and one of the cards this
    /// device handed out opens it. A card that opened a letter is spent and forgotten — it existed
    /// for one meeting, and keeping it would make it a standing address by another name.
    /// Acceptance by DELIVERY POINT: the letter arrived in a mailbox opened under one card -- that one
    /// is tried, exactly one. There is no walk, so there is no phantom candidate: ML-KEM on a foreign
    /// key does not refuse (implicit rejection, FIPS 203) and always yields a plausible secret, so
    /// "it decrypted" was never a proof. The proof is the body seal.
    static func accept(firstLetter ct: Data, root: Data, confirmed: (Data) -> Bool) -> String? {
        // THE LOCK COVERS THE LOOKUP ONLY (16.09): a meeting does not spend the card, nothing here writes
        // the store — the key is copied out, and the decapsulation, the proof, the pipe's birth and the
        // trace run with the lock let go, so the code screen on the main thread never waits behind a
        // receive. Guard: tools/mt-lock-check.py.
        let root64 = root.base64urlNoPad
        cardLock.lock(); let sk = load()[root64]; cardLock.unlock()   // LOCK-OK: one read of the card-key record
        guard let sk else { return nil }   // not my card's point -- the name path
        guard let secret = MontanaFirstContact.accept(ciphertext: ct, contactSecret: sk, contactRoot: root),
              confirmed(secret) else {
            MontanaP2PTrace.mark("first_ghost", "card=\(MontanaMeetBook.fp(root64)) by-point")
            return nil
        }
        guard let ref = MTPipeBook.establish(secret: secret) else { return nil }
        MontanaP2PTrace.mark("first_accept", "ref=\(String(ref.prefix(10))) by-point")
        MontanaWakePush.registerConvs()
        MTPipeBook.rememberRoot(root, for: ref)
        if isPermanentRoot(root) { ContactsTabView.keepInBook(ref: ref) }   // came by the permanent link: kept
        MontanaP2PTrace.mark("meet_accept", "side=offer")
        offerMet(ref: ref, root: root)
        return ref
    }

    /// Acceptance from a push: the card is named by the invitation that opened the letter's OUTER seal
    /// in the extension -- trying it against other cards does not happen at all, and a body for the
    /// seal is not needed here: the seal was already presented to the extension.
    static func accept(firstLetter ct: Data, invite inv64: String, conf: String) -> String? {
        cardLock.lock()   // LOCK-OK: one read of the invitation records
        let root64 = rdvAll()[inv64].map { $0.prefix(1184).base64urlNoPad }
        cardLock.unlock()
        guard let root64 else {
            MontanaP2PTrace.mark("first_miss", "invite-unknown"); return nil
        }
        // The letter's outer seal is derived from the INVITATION, and an invitation is handed out by
        // the person: whoever holds the link can assemble a letter with garbage ciphertext inside a
        // genuine seal. So key confirmation is mandatory here -- there is no body seal on this path.
        cardLock.lock(); let sk = load()[root64]; cardLock.unlock()   // LOCK-OK: one read of the card-key record; the work runs after it
        guard let sk, let root = Data(base64urlNoPad: root64), root.count == 1184,
              let secret = MontanaFirstContact.accept(ciphertext: ct, contactSecret: sk, contactRoot: root)
        else {
            MontanaP2PTrace.mark("first_miss", "card=\(MontanaMeetBook.fp(root64)) only-card"); return nil
        }
        guard MontanaFirstContact.sameConfirm(conf, MontanaFirstContact.firstConfirm(secret: secret, ct: ct)) else {
            MontanaP2PTrace.mark("first_ghost", "card=\(MontanaMeetBook.fp(root64)) conf=\(conf.isEmpty ? "absent" : "bad")")
            return nil
        }
        guard let ref = MTPipeBook.establish(secret: secret) else {
            MontanaP2PTrace.mark("first_miss", "card=\(MontanaMeetBook.fp(root64)) establish"); return nil
        }
        MontanaP2PTrace.mark("first_accept", "ref=\(String(ref.prefix(10))) only-card")
        MontanaWakePush.registerConvs()
        MTPipeBook.rememberRoot(root, for: ref)
        if isPermanentRoot(root) { ContactsTabView.keepInBook(ref: ref) }   // came by the permanent link: kept
        MontanaP2PTrace.mark("meet_accept", "side=offer")
        offerMet(ref: ref, root: root)
        return ref
    }

    static func accept(firstLetter ct: Data, confirmed: (Data) -> Bool) -> String? {
        cardLock.lock(); let cards = load(); cardLock.unlock()   // LOCK-OK: one read of the card-key record; the walk runs after it
        // A reception miss goes IN BLACK AND WHITE: frames arrive, and there is nothing to accept them
        // with (the key store is empty or does not match). Precedent: a wipe took cardKeys away, the
        // points went on listening to emptiness, the sender hammered first_stuck x61 -- and nobody said why.
        if cards.isEmpty { MontanaP2PTrace.mark("first_miss", "cards=0"); return nil }
        for (rootB64, sk) in cards {
            guard let root = Data(base64urlNoPad: rootB64), root.count == 1184,
                  let secret = MontanaFirstContact.accept(ciphertext: ct, contactSecret: sk, contactRoot: root)
            else { continue }
            // ACCEPT MEANS PROVE, not decrypt. ML-KEM decapsulation on a FOREIGN key does not refuse --
            // the standard returns deterministic garbage (implicit rejection). The letter was tried
            // against ALL of the holder's cards (there are two: the current one and the previous
            // generation), a foreign one "opened" too, and from ONE letter a phantom chat was born with
            // a secret nobody holds: measured 25.08 -- one scan on T2, two first_accept on T1 119 ms
            // apart (15f1bc66f4 real, 573b4987ea phantom, nonexistent on T2; dictionary order differs
            // per call, so now one, now the other was accepted). The proof is the seal: the secret must
            // open the letter body. A garbage secret never opens a seal.
            // A garbage secret never opens the body seal.
            guard confirmed(secret) else {
                MontanaP2PTrace.mark("first_ghost", "card=\(MontanaMeetBook.fp(rootB64))")
                continue
            }
            guard let ref = MTPipeBook.establish(secret: secret) else { continue }
            MontanaP2PTrace.mark("first_accept", "ref=\(String(ref.prefix(10))) cards=\(cards.count)")
            // The author's decision 22.08: the code is DAILY, a meeting does NOT spend it. The former
            // "one meeting = one spend" match gave birth to a carousel: a letter spends the card ->
            // a new one is born -> the next tap meets the new one -> a new twin chat (three first_accept
            // in 11 seconds, 21:33). One code a day for everyone: as many people knock, as many pipes
            // stand up -- the point lives by age, not by a meeting.
            MontanaWakePush.registerConvs()   // the pipe stood up -- subscriptions at once (its own debounce)
            MTPipeBook.rememberRoot(root, for: ref)
            if isPermanentRoot(root) { ContactsTabView.keepInBook(ref: ref) }   // came by the permanent link: kept
            MontanaP2PTrace.mark("meet_accept", "side=offer")
            offerMet(ref: ref, root: root)
            return ref
        }
        MontanaP2PTrace.mark("first_miss", "cards=\(cards.count) none-matched")
        return nil
    }

    /// How many cards are outstanding — countable without opening anything.
    static var outstanding: Int { load().count }

    /// The contact keys of those cards. A card handed out is a node this device must listen at:
    /// whoever scanned it addresses their first letter to the point derived from this very key.
    static func outstandingRoots() -> [Data] {
        load().keys.compactMap { Data(base64urlNoPad: $0) }.filter { $0.count == 1184 }
    }

    /// Invitations of live cards -- for wake subscriptions (F-2): the owner listens to the first
    /// letter not only by a live channel but also by the accelerator node doorbell.
    static func outstandingInvites() -> [Data] {
        cardLock.lock(); defer { cardLock.unlock() }
        return rdvAll().keys.compactMap { Data(base64urlNoPad: $0) }.filter { $0.count == 32 }
    }
}


/// THE FACE AND THE CHAT MEET IN ONE PLACE (23.09): the face asked beside the unfolding and the conversation the
/// meeting gives birth to arrive in either order, and whichever comes second puts the face on — a face in hand
/// before the birth goes on at the birth, so a fresh chat is never shown under a drawn initial it does not need.
final class MTFaceMeet: @unchecked Sendable {
    private let lock = NSLock()
    private var arrived = false
    private var face: Data?
    private var conv: String?

    /// The face came back (nil: the card carries none) — the conversation to put it on, if it is born already.
    func landed(_ f: Data?) -> String? {
        lock.withLock { () -> String? in arrived = true; face = f; return conv }
    }

    /// The conversation is born; a face that came first goes on now.
    func born(_ c: String) async {
        let (ready, f) = lock.withLock { () -> (Bool, Data?) in conv = c; return (arrived, face) }
        if ready { await Self.wear(f, on: c, at: "birth") }
    }

    static func wear(_ f: Data?, on conv: String, at: String) async {
        guard let f else { MontanaP2PTrace.mark("rdv_face", "none conv=\(String(conv.prefix(10))) at=\(at)"); return }
        await MontanaCard.wearFace(f, conv: conv)
        MontanaP2PTrace.mark("rdv_face", "ok bytes=\(f.count) conv=\(String(conv.prefix(10))) at=\(at)")
    }
}


// ── The ONE meeting resolver ────────────────────────────────────────────────────────────────
//
// Every node a person may hand something to — the scanner, a pasted line, a tapped montana://
// link — comes HERE. One implementation of acceptance and one of refusal, because the nodes
// diverged the moment there were two: the scanner remembered the ciphertext of the first
// letter and the name-link node did not, so a correspondence begun by link could never open.
// A second copy of this switch anywhere is that defect waiting to happen again.
enum MontanaMeeting {

    /// Meets whatever was handed over — a name or a one-time card — and returns the local
    /// reference of the correspondence it opens. Anything shaped like a standing identifier of
    /// a person is refused out loud: no such string exists in this tree, and no node accepts one.
    /// My scans: invitation -> the conversation it opened. A repeat scan of THE SAME code does not
    /// give birth to a second pipe (and a twin chat) but returns into the already open conversation.
    private static let scannedKey = "rdvScanned"
    /// The link book and the root book. Both are MontanaMeetBook: a record first lands in process
    /// memory (which cannot refuse), then in the vault, and a vault refusal is named in the trace.
    /// Precedent 25.08: two taps on ONE link in one process 68 seconds apart gave birth to a twin
    /// chat -- both books stayed silent, and the trace could not name whether the record was lost or
    /// the key missed. Now there is nothing to be silent with: process memory answers even with a
    /// dead vault, and every miss and every write carries a key fingerprint.
    static let scanBook = MontanaMeetBook(name: "scan", vaultKey: scannedKey)

    /// The meeting key is THE LINK ITSELF (the author's decision 25.08: the link is the same however
    /// many taps happen). An invitation, when it reads, gives a stable key; when unreadable, the whole
    /// normalized string becomes the key. Dedup has no right to depend on whether something inside
    /// the link parsed.
    static func meetKey(_ raw: String) -> String {
        if let inv = MontanaCard.invite(inShort: raw) { return inv.base64urlNoPad }
        // A name has many written forms — alice, @alice, pzr.me/alice, montana://alice — and one gate: the name.
        if case .name(let n) = MontanaConv.meeting(fromInput: raw) { return "name:" + n }
        return raw
    }

    static func rememberScan(invite inv64: String, conv: String) {
        scanBook.put(inv64, conv)
    }
    /// The invitation a conversation was born from goes to the delivery engine: ring the owner's
    /// doorbell when the first letter is really on its way (F-2).
    static func invite(forConv conv: String) -> Data? {
        deadLock.lock()
        let metaInv = metaLoad()[conv]?.inv
        deadLock.unlock()
        if let inv64 = metaInv { return Data(base64urlNoPad: inv64) }
        guard let inv64 = scanBook.load().first(where: { $0.value == conv })?.key else { return nil }
        return Data(base64urlNoPad: inv64)
    }

    /// `nameless`: every door that carries names answered that nobody holds the name — said as such, not
    /// as a link that «could not be opened».
    enum Outcome { case opened(String); case spent; case refused; case nameless; case ownName }

    /// One meeting per invitation -- at once, not "from memory afterwards". This door has three
    /// entrances (a link tap, a code scan, a search by name), and two of them easily happen back to
    /// back: the 24.08 measurement gave TWO unfoldings of one invitation in two seconds and two
    /// identical conversations on both sides from one message. Meeting memory is written at the end,
    /// so a second meeting slipped past it; the latch holds the entrance until the first has finished.
    /// THE MEETING BOOK BY CARD ROOT. A link carries everything needed, so the birth of a tunnel must
    /// be a FUNCTION OF THE LINK: one root, one tunnel, by whichever way it was entered (tap, scan,
    /// search by name, cold start, a repeat after the answer).
    ///
    /// Before, two records played this role, and both lost the answer sooner than it stopped being
    /// needed: scan memory was keyed by the INVITATION, which changes on the daily rotation; the
    /// address root died together with the first letter (it was "where to address", not "whom we know").
    /// Two meanings lived in one record -- and at either of the two boundaries the next tap wove a
    /// SECOND rope to the same person: both sides got a twin chat, the second letter went into the
    /// fresh one, the first hung. Here the meanings are separated: the address root stays as before
    /// and dies as before, while this book remembers the acquaintance while the pipe lives.
    private static let cardMetKey = "cardMetByRoot"
    static let cardBook = MontanaMeetBook(name: "card", vaultKey: cardMetKey)

    static func rememberCardMet(root: Data, conv: String) {
        guard root.count == 1184, !conv.isEmpty else { return }
        // Dead acquaintances do not pile up, but the sweeper judges ONLY the old: before, the filter
        // stood AFTER the insert, and a lagging holds() view could eat a record just born.
        cardBook.put(root.base64urlNoPad, conv, pruneOld: { MTPipeBook.holds($0) })
    }
    static func cardMet(root: Data) -> String? {
        cardBook.get(root.base64urlNoPad)
    }

    private static let meetGate = NSLock()
    private static var meetingNow: Set<String> = []

    private static func takeGate(_ key: String) -> Bool {
        meetGate.lock(); defer { meetGate.unlock() }
        if meetingNow.contains(key) { return false }
        meetingNow.insert(key); return true
    }
    private static func dropGate(_ key: String) {
        meetGate.lock(); meetingNow.remove(key); meetGate.unlock()
    }

    static func meet(_ raw: String) async -> Outcome {
        // ONE PERSON, ONE CONVERSATION (24.09, MTSamePair): a pipe folded into a conversation is never opened as a page.
        let o = await meetOnce(raw)
        if case .opened(let ref) = o { return .opened(MTSamePair.root(ref)) }
        return o
    }
    private static func meetOnce(_ raw: String) async -> Outcome {
        // A meeting decision is not taken from an UNREADABLE book. Sealed storage on a cold start
        // answers with emptiness, and emptiness here read as "we are strangers" -- giving birth to a
        // twin exactly when the person tapped a link right after launch (measured 24.08: a tap at the
        // 860th millisecond of the app's life, and a second conversation stood beside the old one).
        var waited = 0
        while MontanaDeviceKey.key == nil, waited < 20 {
            try? await Task.sleep(nanoseconds: 250_000_000); waited += 1
        }
        guard MontanaDeviceKey.key != nil else {
            MontanaP2PTrace.mark("meet_refused", "why=vault-closed")
            return .refused
        }
        scanBook.drain(); cardBook.drain()
        let gateKey = meetKey(raw)
        if !takeGate(gateKey) {
            // The same door is already opening. We wait for it and enter THAT conversation, not a second.
            MontanaP2PTrace.mark("meet_gate", "waiting")
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                let done: String? = scanBook.get(gateKey)
                if let done, MTPipeBook.holds(done), !MTPipeBook.isDying(done) {
                    MontanaP2PTrace.mark("meet_gate", "joined conv=\(String(done.prefix(10)))")
                    return .opened(done)
                }
                var busy = false
                meetGate.lock(); busy = meetingNow.contains(gateKey); meetGate.unlock()
                if !busy { break }
            }
            guard takeGate(gateKey) else {
                MontanaP2PTrace.mark("meet_gate", "gave up")
                return .refused
            }
        }
        defer { dropGate(gateKey) }
        var raw = raw
        var scannedInvite: String? = nil
        var faces: MTFaceMeet? = nil   // the face asked with the unfolding meets the chat born from it
        // A short invitation unfolds into an ordinary card BEFORE the pipeline: the full key comes
        // from the node, and the whole lower part of the introduction stays as before, to the byte.
        if MontanaCard.isShort(raw) {
            // A repeat tap or scan of THE SAME code returns into the conversation already born -- even
            // while the first exchange is unfinished: before, every tap gave birth to a twin chat and
            // ate the owner's card (F-5, a triple first_accept within a second). The knocking of the
            // existing conversation's first letter continues by itself -- the delivery engine repeats it anyway.
            // The link book is asked by the LINK KEY -- whether the invitation reads or not.
            // The answer is named in the trace with the key fingerprint: the next twin, should there be
            // one, will name its branch in one line instead of an hour of digging.
            let known: String? = scanBook.get(gateKey)
            let scanWord: String = {
                guard let k = known else { return "miss" }
                if MTPipeBook.isDying(k) { return "dying" }
                return MTPipeBook.holds(k) ? "hit" : "gone"
            }()
            MontanaP2PTrace.mark("meet_books", "key=\(MontanaMeetBook.fp(gateKey)) scan=\(scanWord) n=\(scanBook.count)")
            // A dying conversation (a burial notice in flight) is NOT an entrance: a tap at 23:06:27
            // brought it back, and four seconds later the pipe died under letters (a send_refused storm).
            // The dead and the dying do not meet -- a fresh one is born, the link = a new empty chat.
            if let known, MTPipeBook.holds(known), !MTPipeBook.isDying(known) {
                MontanaP2PTrace.mark("meet_rescan", "conv=\(String(known.prefix(10)))")
                // A RESCAN RE-READS THE NAME (21.09, measured 16:35: the same link opened the same empty
                // chat under the callsign of the first scan, and the card behind the link — which by now
                // wore the person's current name — was never looked at). The body is fetched beside, the
                // chat opens at once; the name enters the book as the weakest witness (never past a dated word).
                let short = raw
                Task.detached(priority: .utility) {
                    if case .card(let full) = await MontanaCard.expand(short: short) { await MontanaCard.renameFromCard(full, conv: known) }
                    if let inv = MontanaCard.invite(inShort: short) { await MontanaCard.refaceFromCard(invite: inv, conv: known) }
                }
                return .opened(known)
            }
            scannedInvite = MontanaCard.invite(inShort: raw)?.base64urlNoPad
            // THE FACE STARTS WITH THE UNFOLDING (23.09, the author's word: «the name and the face at once, at the
            // chat's creation»). It was asked only once the meeting had finished, so every fresh chat stood a third of
            // a second under a drawn initial (T2 17:15:32, measured). The face and the card lie beside one invitation:
            // asked together, the face is in hand when the pipe is born and goes on at the birth; a slower one goes
            // on the moment it lands.
            if let inv = MontanaCard.invite(inShort: raw) {
                let meetFace = MTFaceMeet()
                faces = meetFace
                Task.detached(priority: .userInitiated) {
                    let face = await MontanaCard.face(invite: inv)
                    if let conv = meetFace.landed(face) { await MTFaceMeet.wear(face, on: conv, at: "landing") }
                }
            }
            switch await MontanaCard.expand(short: raw) {
            case .card(let full): raw = full
            case .spent:
                MontanaLog.event("CARD x the invitation is spent (the card was used)")
                return .spent
            case .unreachable:
                MontanaLog.event("CARD x the invitation did not unfold (blob not found or would not open)")
                MontanaP2PTrace.mark("meet_refused", "why=expand-unreachable")
                return .refused
            }
        }
        switch MontanaConv.meeting(fromInput: raw) {
        case .card(let c):
            // Dedup by card ROOT: if the first letter to this point is already knocking, it is the same
            // meeting, an entrance into it, not a second encapsulation (F-5, the regression root 21:10).
            // One root, one tunnel. The meeting book is asked FIRST and outlives the answer to the
            // first letter; the address root stays a second witness while the knocking goes on.
            if let root = MontanaCard.root(inCard: c) {
                let inBook = cardMet(root: root)
                let knocking = MTPipeBook.convKnocking(at: root)
                let cardWord: String = {
                    guard let k = inBook else { return "miss" }
                    if MTPipeBook.isDying(k) { return "dying" }
                    return MTPipeBook.holds(k) ? "hit" : "gone"
                }()
                MontanaP2PTrace.mark("meet_books", "root=\(MontanaMeetBook.fp(root.base64urlNoPad)) card=\(cardWord) "
                    + "knock=\(knocking == nil ? "miss" : "hit") n=\(cardBook.count)")
                if let known = inBook, MTPipeBook.holds(known), !MTPipeBook.isDying(known) {
                    MontanaP2PTrace.mark("meet_rescan", "card-book conv=\(String(known.prefix(10)))")
                    scanBook.put(gateKey, known)
                    await MontanaCard.renameFromCard(c, conv: known)
                    await faces?.born(known)   // the face asked with the unfolding — a rescan re-reads it too
                    return .opened(known)
                }
                if let existing = knocking, !MTPipeBook.isDying(existing) {
                    MontanaP2PTrace.mark("meet_rescan", "root conv=\(String(existing.prefix(10)))")
                    await MontanaCard.renameFromCard(c, conv: existing)
                    await faces?.born(existing)
                    rememberCardMet(root: root, conv: existing)
                    scanBook.put(gateKey, existing)
                    return .opened(existing)
                }
                // A NEW tunnel is born -- and it is said aloud together with the key fingerprints.
                MontanaP2PTrace.mark("meet_new", "key=\(MontanaMeetBook.fp(gateKey)) root=\(MontanaMeetBook.fp(root.base64urlNoPad))")
            }
            // A card is met on the spot: one encapsulation, and the correspondence exists.
            // The ciphertext waits for the first letter to carry it.
            guard let met = MontanaCard.meet(card: c) else {
                MontanaLog.event("CARD ✗ a card that does not open")
                MontanaP2PTrace.mark("meet_refused", "why=card-unopenable")
                return .refused
            }
            MTPipeBook.rememberFirst(met.ciphertext, for: met.reference)
            // The name arrives TOGETHER with the acquaintance, because it lies in the card itself.
            // Before, it travelled as a separate letter after, and the conversation managed to live a
            // while under a neutral caption -- while the person had named themselves long before the meeting.
            // THE CARD'S NAME IS A SNAPSHOT OF ITS MINTING DAY (21.09, the critic: the permanent card was
            // minted once and never again, so a chat was born under a person's first callsign). It enters
            // the book as the weakest witness — it lands only in an empty book; the person's first word
            // covers it and no older letter can bring it back.
            if let n = MontanaCard.name(inCard: c) {
                await MainActor.run { MontanaDeliveryEngine.shared.store?.setPeerName(ref: met.reference, name: n, at: 0, source: "card") }
            }
            // The face comes with the acquaintance too (15.32): asked together with the unfolding, it goes on at
            // the chat's birth when it came first, and the moment it lands otherwise (MTFaceMeet).
            await faces?.born(met.reference)
            scanBook.put(gateKey, met.reference)
            if let root = MontanaCard.root(inCard: c) { rememberCardMet(root: root, conv: met.reference) }
            rememberFirstMeta(conv: met.reference, invite: scannedInvite)
            // ONE PERSON, ONE CONVERSATION (24.09, MTSamePair): whether we already share a pipe is asked at once — the
            // silent first letter, which carries the card's ciphertext to its owner.
            MTSamePair.ask(new: met.reference)
            // A permanent link keeps the person in the book (the author's word 17.09): the mark beside
            // the card says so; asked once, after the meeting, and only by a build that knows to ask.
            if let inv64 = scannedInvite, let inv = Data(base64urlNoPad: inv64) {
                let conv = met.reference
                Task.detached(priority: .utility) {
                    if await MontanaCard.isPermanent(invite: inv) { await MainActor.run { ContactsTabView.keepInBook(ref: conv) } }
                }
            }
            return .opened(met.reference)
        case .name(let n):
            // One's own name opens nothing: a correspondence with oneself is a ghost in both books.
            if n == MontanaNames.currentName {
                MontanaP2PTrace.mark("meet_refused", "why=own-name")
                return .ownName
            }
            let root: Data
            switch await MontanaNamePlane.resolve(n) {
            case .found(let r): root = r
            case .unknown:
                MontanaLog.event("NAME ✗ nobody holds this name")
                MontanaP2PTrace.mark("meet_refused", "why=name-unknown")
                return .nameless
            case .unreachable:
                MontanaLog.event("NAME ✗ the plane of names did not answer")
                MontanaP2PTrace.mark("meet_refused", "why=name-unreachable")
                return .refused
            }
            // ONE ROOT, ONE TUNNEL — for a name as for a card. The name's link is the standing link now, and a
            // second tap on it after the first letter was answered would otherwise weave a second rope to the
            // same person: the meeting book by root is asked first, the knocking point second.
            if let known = cardMet(root: root), MTPipeBook.holds(known), !MTPipeBook.isDying(known) {
                MontanaP2PTrace.mark("meet_rescan", "name-book conv=\(String(known.prefix(10)))")
                scanBook.put(gateKey, known)
                return .opened(known)
            }
            if let existing = MTPipeBook.convKnocking(at: root), !MTPipeBook.isDying(existing) {
                MontanaP2PTrace.mark("meet_rescan", "root conv=\(String(existing.prefix(10)))")
                rememberCardMet(root: root, conv: existing)
                return .opened(existing)
            }
            guard let met = MontanaFirstContact.meet(contactRoot: root) else {
                MontanaLog.event("NAME ✗ the contact root of the name does not open")
                MontanaP2PTrace.mark("meet_refused", "why=name-meet-failed")
                return .refused
            }
            MTPipeBook.rememberFirst(met.ciphertext, for: met.reference)
            rememberFirstMeta(conv: met.reference, invite: nil)
            MTSamePair.ask(new: met.reference)   // one person, one conversation (24.09): the same question, by name
            rememberCardMet(root: root, conv: met.reference)
            scanBook.put(gateKey, met.reference)
            // The name's link keeps the person in the book, as the permanent link it stands in for does
            // (the author's word 17.09).
            await MainActor.run {
                MTNameBook.setName(conv: met.reference, n)
                ContactsTabView.keepInBook(ref: met.reference)
            }
            return .opened(met.reference)
        case .refused:
            MontanaLog.event("MEET ✗ refused: neither a name nor a card")
            // The most frequent and formerly the most mute: the link is recognised neither as a name nor as a card.
            MontanaP2PTrace.mark("meet_refused", "why=neither-name-nor-card")
            return .refused
        }
    }

    // -- the SSOT of the LINK entrance (montana://...) -- F-4, F-6, F-7, F-8 --
    //
    // A link, unlike a scan, comes from foreign hands: a keyboard capitalises the scheme, a messenger
    // encodes bytes and glues punctuation on, and one can tap before an identity is born and after a
    // card is spent. Each of those outcomes was silent; here each one has a voice.
    static let pendingInviteKey = "pendingInvite"

    static func normalizeLink(_ s: String) -> String {
        var raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // The messenger encoded the link bytes -- give them back as they were (F-7).
        if raw.contains("%"), let d = raw.removingPercentEncoding { raw = d }
        // Trailing punctuation stuck on during linkification (F-7).
        while let last = raw.last, ".,;:!?)]}>»›\"'’”…".contains(last) { raw.removeLast() }
        // The scheme is case-insensitive (RFC 3986); a keyboard capitalises the first word (F-6).
        if let r = raw.range(of: "://") {
            raw = raw[..<r.lowerBound].lowercased() + raw[r.lowerBound...]
        }
        return raw
    }

    /// The last link handled and when (main thread only: every door of a link lands there).
    private static var lastLink: (raw: String, at: Date)?
    static func handleLink(_ given: URL) {
        // The mark BEFORE all the guards: a tap that left no trace was impossible to investigate (F-6).
        MontanaP2PTrace.mark("link_open", "len=\(given.absoluteString.count) scheme=\(given.scheme ?? "-")")
        // A GROUP'S INVITE LINK IS ITS OWNER'S CARD AND THE GROUP'S MARK (stage R.6, the reference folder's «Invite Link»):
        // the mark waits for the meeting, and the card goes on by the one road of a link
        var url = given
        if let j = MTGroup.joinMark(in: given) {
            url = j.url
            DispatchQueue.main.async { MTGroup.shared.waitJoin(j.g, j.mark) }
        }
        if MTBoardComments.open(url) { return }
        // THE BOT'S OWN SIGN-IN COMES BACK (06.10): the link the other app opens after its native confirmation carries the code to
        // the number's page that waits for it (MTPhoneFlow.cameBackWith) -- before the scheme's guard, which would read it as an
        // invitation and answer that it could not be opened.
        if MTPhoneReturn.matches(url) {
            MontanaP2PTrace.mark("link_done", "phone sign-in back")
            Task { @MainActor in MTPhoneFlow.current?.cameBackWith(url) }
            return
        }
        // A WALL'S LINK IS NEVER AN INVITATION (02.10): a post this phone does not hold yet is said so -- the invitation road
        // below answered it «the invitation could not be opened».
        if url.scheme?.lowercased() == "montana", url.host?.lowercased() == "wall" {
            MontanaP2PTrace.mark("link_done", "wall post not held")
            verdict("This post is not on this phone yet. Open the writer's page, then tap the link again.")
            return
        }
        // A RETIRED LINK OF AN OLDER BUILD (the author's word 08.10.2026: the coins leave Montana wholly for their own app, Montana
        // Wallet): it opens nothing here and is no invitation either -- the invitation road below would answer «could not be opened».
        if url.scheme?.lowercased() == "montana", url.host?.lowercased() == "coin" {
            MontanaP2PTrace.mark("link_done", "retired link")
            return
        }
        let host = url.host?.lowercased() ?? ""
        let webForm = url.scheme?.lowercased() == "https"
            && ((MontanaCard.linkHosts.contains(host) && ["/r/", "/perp/", "/temp/"].contains { url.path.hasPrefix($0) })
                || ((host == "pzr.me" || host == "www.pzr.me") && url.path.count > 1))   // a name's link (24.09)
        guard url.scheme?.lowercased() == "montana" || webForm else {
            // A mute refusal by scheme ate the tap whole: the trace kept one line "a link arrived" and
            // emptiness after it -- exactly what was seen on 24.08 on the seventeenth.
            MontanaP2PTrace.mark("link_refused", "why=scheme scheme=\(url.scheme ?? "-")")
            verdict("This link is not a Montana invitation.")
            return
        }
        let raw = normalizeLink(url.absoluteString)
        // ONE LINK IS HANDLED ONCE, WHICHEVER DOOR IT CAME BY (23.09): a universal link may be handed both as an
        // activity and as a URL. The same link within three seconds is the same tap -- the first handling carries it.
        if let l = lastLink, l.raw == raw, Date().timeIntervalSince(l.at) < 3 {
            MontanaP2PTrace.mark("link_open", "repeat within 3s -- the first handling carries it")
            return
        }
        lastLink = (raw, Date())
        // A SET'S LINK IS NOT AN INVITATION (22.09): it names a set and nobody else. The hand that
        // passed it was remembered when the letter landed, so the set is asked of that hand and the
        // page opens in that very conversation. A link from nowhere opens nothing: there is no
        // register to ask, and no address is going to be guessed.
        if let found = MontanaStickerPack.idIn(text: raw) {
            let book = MontanaStickerBook.shared
            MontanaP2PTrace.mark("sticker_link", "opened pack=\(found.id.prefix(8))")
            guard let giver = book.giver(of: found.id), !giver.isEmpty else {
                verdict("Ask the person who sent this set for it.")
                return
            }
            if !book.holds(found.id) {
                book.meet(pack: found.id, title: found.title.isEmpty ? "Montana" : found.title, owner: giver, expected: 0)
            }
            MontanaStickerWire.ask(pack: found.id, from: giver, chat: giver)
            MontanaStickerOpen.pack = found.id
            MontanaOutsideOpen.chat(giver)
            return
        }
        guard MontanaSeed.hasSeed else {
            // There is no identity yet -- the invitation waits for it, and the person is told so (F-8).
            UserDefaults.standard.set(raw, forKey: pendingInviteKey)
            MontanaP2PTrace.mark("link_wait", "identity=0")
            verdict("Create your identity first — the invitation will open right after.")
            return
        }
        resolveInvite(raw)
    }

    /// The identity is born -- the invitation that waited for it opens by itself (F-8).
    static func replayPendingInvite() {
        guard MontanaSeed.hasSeed,
              let raw = UserDefaults.standard.string(forKey: pendingInviteKey), !raw.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: pendingInviteKey)
        resolveInvite(raw)
    }

    private static func resolveInvite(_ raw: String) {
        // The link form is named BEFORE the meeting: "short" and "card" lead by different roads, and
        // without this line one cannot say which way the matter went.
        MontanaP2PTrace.mark("link_shape", MontanaCard.isShort(raw) ? "short" : "long")
        Task {
            switch await meet(raw) {
            case .opened(let ref):
                MontanaP2PTrace.mark("link_done", "opened conv=\(String(ref.prefix(10)))")
                await MainActor.run {
                    MontanaOutsideOpen.chat(ref)
                    MTGroup.shared.askJoin(through: ref)   // a group's link: the join is asked of the owner just met (stage R.6)
                }
            case .spent:
                MontanaP2PTrace.mark("link_done", "spent")
                verdict("Invitation expired. Ask for a new code.")
            case .refused:
                MontanaP2PTrace.mark("link_done", "refused")
                verdict("The invitation could not be opened. Check the link or try again.")
            case .nameless:
                MontanaP2PTrace.mark("link_done", "nameless")
                verdict("Nobody holds this name.")
            case .ownName:
                MontanaP2PTrace.mark("link_done", "own-name")
                verdict("This is your own name.")
            }
        }
    }

    // -- First-knock metadata: born together with the knock, nothing to lose --
    //
    // Before, a conversation invitation lived only in scan memory (invitation -> conversation), and a
    // lost record made a ghost unsilenceable: an audit had nothing to ask the node with. Now the
    // metadata (invitation plus birth time) is written AT THE MOMENT of the meeting beside the point root.
    private struct FirstMeta: Codable { var inv: String?; var born: UInt64 }
    private static let firstMetaKey = "pipeFirstMeta"
    private static func metaLoad() -> [String: FirstMeta] {
        MontanaLocalVault.getDecrypted(firstMetaKey)
            .flatMap { try? JSONDecoder().decode([String: FirstMeta].self, from: $0) } ?? [:]
    }
    private static func metaSave(_ m: [String: FirstMeta]) {
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(firstMetaKey, d) }
    }
    static func rememberFirstMeta(conv: String, invite inv64: String?) {
        deadLock.lock(); defer { deadLock.unlock() }
        var m = metaLoad()
        if var e = m[conv] { if e.inv == nil { e.inv = inv64; m[conv] = e } }
        else { m[conv] = FirstMeta(inv: inv64, born: UInt64(Date().timeIntervalSince1970)) }
        metaSave(m)
    }
    /// The pipe died -- so does the meeting memory: the invitation binding and the metadata. Otherwise a
    /// link tap resurrected a dead conversation (23:06), and an audit rang the doorbell on a foreign account.
    static func forgetConv(_ conv: String) {
        scanBook.removeValues { $0 == conv }
        cardBook.removeValues { $0 == conv }
        forgetFirstMeta(conv: conv)
    }
    /// A folded conversation's cards and links open the older one (MTSamePair, 24.09).
    static func repoint(from newer: String, to older: String) {
        scanBook.repoint(newer, to: older)
        cardBook.repoint(newer, to: older)
    }

    static func forgetFirstMeta(conv: String) {
        deadLock.lock(); defer { deadLock.unlock() }
        var m = metaLoad()
        guard m.removeValue(forKey: conv) != nil else { return }
        metaSave(m)
    }

    // -- Dead knocks: giving up on a gravestone (class 6.8 -- only the provably dead is given up) --
    //
    // A first letter whose card was spent by ANOTHER encapsulation knocks forever and holds the queue
    // ahead of the living (21:08: a live letter waited 3.5 minutes behind ghosts). Death is proven by
    // a gravestone on the node: two consecutive "spent" answers with a pause -- the knocking is silenced.
    private static var spentSeen: [String: Int] = [:]
    private static var spentCheckedAt: [String: UInt64] = [:]
    private static var deadSet: Set<String> = []
    private static let deadLock = NSLock()

    static func firstKnockAllowed(conv: String) -> Bool {
        deadLock.lock(); defer { deadLock.unlock() }
        return !deadSet.contains(conv)
    }

    /// Called by the delivery engine on a first-letter attempt: about once every 5 minutes it asks the
    /// node whether a gravestone lies on the point. A link break resets the count -- only a "NO" silences.
    /// A conversation without metadata (a legacy from before 922) gets it here.
    /// NO HORIZON OF AGE (07.10, MTRefusal): a first contact older than seven days used to be declared dead, and every letter to it
    /// went red at once -- an acquaintance the other side had not yet opened (a phone asleep, a second account in a seat not in
    /// use) is not a refusal. Only the gravestone kills a knock; each letter ends by its own carriage.
    static func auditFirst(conv: String) {
        deadLock.lock()
        let born = metaLoad()[conv]?.born
        deadLock.unlock()
        if born == nil { rememberFirstMeta(conv: conv, invite: nil) }
        guard let inv = invite(forConv: conv) else { return }
        let w = MTPipe.window() / 5
        deadLock.lock()
        let due = spentCheckedAt[conv] != w
        if due { spentCheckedAt[conv] = w }
        deadLock.unlock()
        guard due else { return }
        Task {
            switch await MontanaCard.expand(short: "montana://r/" + inv.base64urlNoPad) {
            case .spent:
                deadLock.lock()
                let n = (spentSeen[conv] ?? 0) + 1
                spentSeen[conv] = n
                if n >= 2 { deadSet.insert(conv) }
                deadLock.unlock()
                if n >= 2 { MontanaP2PTrace.mark("first_dead", "conv=\(String(conv.prefix(10))) spent×\(n)") }
            case .card, .unreachable:
                deadLock.lock(); spentSeen[conv] = 0; deadLock.unlock()
            }
        }
    }

    /// A loud outcome instead of a journal line (F-4): the person tapped, so the person is answered.
    private static func verdict(_ key: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .montanaMeetVerdict, object: nil, userInfo: ["msg": key])
        }
    }
}


/// A meeting book one can trust. A record FIRST lands in process memory -- memory cannot refuse --
/// then tries to land in the vault; a vault refusal is named in the trace (meet_put vault=refused)
/// and arrives on the next write or on drain(). Reading is vault union memory, memory wins. The key
/// fingerprint (a domain SHA-256, 4 bytes) makes records comparable in the trace without revealing
/// the key. One implementation for both meeting books ([I-10]).
final class MontanaMeetBook {
    private let name: String
    private let vaultKey: String
    private let lock = NSRecursiveLock()
    private var overlay: [String: String] = [:]
    private var pendingVault = false
    /// The vault is substituted in tests: the book must be provable on an invented vault.
    var persist: (String, Data) -> Bool = { MontanaLocalVault.setEncrypted($0, $1) }
    var restore: (String) -> Data? = { MontanaLocalVault.getDecrypted($0) }

    init(name: String, vaultKey: String) { self.name = name; self.vaultKey = vaultKey }

    private func storedLocked() -> [String: String] {
        restore(vaultKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    func load() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return storedLocked().merging(overlay) { _, mem in mem }
    }
    func get(_ key: String) -> String? { load()[key] }
    var count: Int { load().count }

    /// pruneOld judges ONLY old records: a fresh one is laid after the sweep and cannot be eaten.
    func put(_ key: String, _ value: String, pruneOld: (String) -> Bool = { _ in true }) {
        lock.lock(); defer { lock.unlock() }
        overlay[key] = value
        persistLocked(pruneOld: pruneOld, fp: Self.fp(key))
    }
    func removeValues(_ dead: (String) -> Bool) {
        lock.lock(); defer { lock.unlock() }
        overlay = overlay.filter { !dead($0.value) }
        persistLocked(pruneOld: { !dead($0) }, fp: "forget")
    }
    func repoint(_ newer: String, to older: String) {
        lock.lock(); defer { lock.unlock() }
        var moved = false
        for (k, v) in storedLocked().merging(overlay, uniquingKeysWith: { _, mem in mem }) where v == newer { overlay[k] = older; moved = true }
        if moved { persistLocked(pruneOld: { _ in true }, fp: "repoint") }
    }
    /// The vault recovered -- what did not arrive arrives. Called at every meeting entrance: cheap and timely.
    func drain() {
        lock.lock(); defer { lock.unlock() }
        if pendingVault { persistLocked(pruneOld: { _ in true }, fp: "drain") }
    }
    private func persistLocked(pruneOld: (String) -> Bool, fp: String) {
        var m = storedLocked().filter { pruneOld($0.value) }
        m.merge(overlay) { _, mem in mem }
        guard let d = try? JSONEncoder().encode(m), persist(vaultKey, d) else {
            pendingVault = true
            MontanaP2PTrace.mark("meet_put", "book=\(name) fp=\(fp) n=\(m.count) vault=refused")
            return
        }
        pendingVault = false
        MontanaP2PTrace.mark("meet_put", "book=\(name) fp=\(fp) n=\(m.count) vault=ok")
    }
    static func fp(_ key: String) -> String {
        MTPipe.domained("mt-meet-fp", [Data(key.utf8)]).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
