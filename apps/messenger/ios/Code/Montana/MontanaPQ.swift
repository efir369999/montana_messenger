// Montana post-quantum E2E — Swift wrapper over the mt-bindings engine (C ABI).
// ML-KEM-768 PQXDH + KEM ratchet. Same engine as web (WASM) — byte-identical.
import Foundation
import CryptoKit
import MontanaBindings
import Security

enum MontanaPQ {
    // Sizes (spec Stage 1/5): ML-DSA pk 1952, ML-KEM pub 1184 / sk 2400.
    static let MLDSA_PUB = 1952, MLKEM_PUB = 1184, MLKEM_SK = 2400

    // ── account key derivation from the mnemonic ──
    /// master_seed (64) from the mnemonic — derived in ONE place (MontanaQueueKeys).
    private static func masterSeed(_ mnemonic: String) -> Data? { MontanaQueueKeys.masterSeed(mnemonic) }
    /// 32-byte account_key seed (role "mt-account-key") — input for e2e_build_handshake.
    /// app_kem_key (ML-KEM-768) from the mnemonic: (pub 1184, sk 2400).
    /// ML-KEM-768 keypair from a 64-byte seed (for signed_prekey / one-time prekeys).
    /// ML-DSA-65 account_key signature over a message. `seckey` — account sk (4032).
    static func sign(seckey: Data, message: Data) -> Data? {
        guard seckey.count == 4032 else { return nil }   // size guard BEFORE FFI
        var out = [UInt8](repeating: 0, count: 3309)
        let rc = seckey.withUnsafeBytes { skp in
            message.withUnsafeBytes { mp -> Int32 in
                mt_sign(skp.bindMemory(to: UInt8.self).baseAddress,
                        mp.bindMemory(to: UInt8.self).baseAddress, message.count, &out)
            }
        }
        return rc == 0 ? Data(out) : nil
    }
    // ML-DSA-65 verify via mt-bindings (SSOT): verification of bundle/anchor signatures.
    static func verify(pubkey: Data, message: Data, signature: Data) -> Bool {
        guard pubkey.count == 1952, signature.count == 3309 else { return false }
        let rc = pubkey.withUnsafeBytes { pk in message.withUnsafeBytes { mp in signature.withUnsafeBytes { sp -> Int32 in
            mt_verify(pk.bindMemory(to: UInt8.self).baseAddress,
                      mp.bindMemory(to: UInt8.self).baseAddress, message.count,
                      sp.bindMemory(to: UInt8.self).baseAddress)
        }}}
        return rc == 0
    }
    // account_id = SHA-256("mt-account"||0x00||suite_le||pubkey) via the core (not a Swift hash).

    // ── E2E engine (owned buffers via out-parameters + mt_e2e_free) ──
    private static func take(_ ptr: UnsafeMutablePointer<UInt8>?, _ len: Int) -> Data {
        guard let p = ptr, len > 0 else { return Data() }
        let d = Data(bytes: p, count: len)
        mt_e2e_free(p, len)
        return d
    }

    /// Alice: handshake + session. Returns (initialHandshake, sessionBlob).

    /// Bob: handshake processing -> sessionBlob. opk by opk_id from hs.

    /// (new session, ciphertext) from the blob + plaintext.
    static func encrypt(session: Data, plaintext: Data, rngSeed: Data) -> (session: Data, msg: Data)? {
        var os: UnsafeMutablePointer<UInt8>? = nil; var osl = 0
        var om: UnsafeMutablePointer<UInt8>? = nil; var oml = 0
        let rc = session.withUnsafeBytes { s in plaintext.withUnsafeBytes { p in rngSeed.withUnsafeBytes { r -> Int32 in
            mt_e2e_encrypt(s.bindMemory(to: UInt8.self).baseAddress, session.count,
                           p.bindMemory(to: UInt8.self).baseAddress, plaintext.count,
                           r.bindMemory(to: UInt8.self).baseAddress, &os, &osl, &om, &oml)
        }}}
        guard rc == 0 else { return nil }
        return (take(os, osl), take(om, oml))
    }

    /// Core code «replay below the receive cursor» (MT_ERR_REPLAY, mt-bindings): the session is alive,
    /// the envelope is a duplicate; reset and rekey are not performed (spec Stage 6, exactly-once).
    static let errReplay: Int32 = -12

    /// Stage 13: encryption key for call media frames from call_seed (delivered post-quantum over the ratchet).
    /// FFI mt_e2e_call_key → out(64) = call_key(32)‖sframe_key(32); returns sframe_key.
    static func sframeKey(callSeed: Data) -> Data? {
        guard callSeed.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 64)
        let rc = callSeed.withUnsafeBytes { cs in
            mt_e2e_call_key(cs.bindMemory(to: UInt8.self).baseAddress, &out)
        }
        guard rc == 0 else { return nil }
        return Data(out[32..<64])
    }

    /// Stage 8: pair safety number (60 ASCII digits) from two 32-byte account_id values.
    /// Via FFI mt-bindings — SSOT, without reimplementing the formula on the client.
    /// (new session, plaintext) from the blob + ciphertext.
    static func decrypt(session: Data, msg: Data) -> (session: Data, plaintext: Data)? {
        decryptRC(session: session, msg: msg).result
    }

    /// Same + core code: the caller distinguishes a replay (errReplay) from a broken chain.
    static func decryptRC(session: Data, msg: Data) -> (rc: Int32, result: (session: Data, plaintext: Data)?) {
        var os: UnsafeMutablePointer<UInt8>? = nil; var osl = 0
        var op: UnsafeMutablePointer<UInt8>? = nil; var opl = 0
        let rc = session.withUnsafeBytes { s in msg.withUnsafeBytes { m -> Int32 in
            mt_e2e_decrypt(s.bindMemory(to: UInt8.self).baseAddress, session.count,
                           m.bindMemory(to: UInt8.self).baseAddress, msg.count, &os, &osl, &op, &opl)
        }}
        guard rc == 0 else { return (rc, nil) }
        return (rc, (take(os, osl), take(op, opl)))
    }
}


// Versions for the first screen: app version (iOS) and SSOT core version (Rust mt-bindings).
/// A window into this machine's sources of randomness: what was taken, whether samples differ and whether the source is alive.
///
/// The measures are computed by the core -- the app only reads and shows them. Not one source byte
/// arrives here: four numbers per source arrive, because a person has the right to see the measures
/// while nobody has the right to see the samples themselves.
enum MontanaEntropy {
    struct Source: Identifiable {
        let id: Int
        let samples: Int
        let distinct: Int
        let maxRepeat: Int
        let alive: Bool
        /// The share of the most frequent sample -- the very measure by which a source counts as alive.
        var repeatShare: Int { samples > 0 ? maxRepeat * 100 / samples : 100 }
    }

    /// The order is the same as the addition in the core. The names are catalogue keys, the translation comes from there.
    static let names = ["System generator", "Execution jitter", "Memory access",
                        "Quartz drift", "Scheduling", "Timer overshoot"]

    static var minLive: Int { Int(mt_entropy_min_live()) }

    static func measure() -> [Source] {
        var buf = [UInt8](repeating: 0, count: 6 * 7)
        var len = 0
        guard mt_entropy_sources(&buf, buf.count, &len) == 0, len == buf.count else { return [] }
        return (0..<6).map { i in
            let at = i * 7
            let u16 = { (o: Int) in Int(UInt16(buf[at + o]) | (UInt16(buf[at + o + 1]) << 8)) }
            return Source(id: i, samples: u16(0), distinct: u16(2), maxRepeat: u16(4), alive: buf[at + 6] == 1)
        }
    }

    /// A record into telemetry: how many are alive and which exactly. Written at the birth of an
    /// identity and on every opening of the window -- so that the verdict on a machine can be read, not recalled.
    static func report(_ why: String) {
        let m = measure()
        guard !m.isEmpty else { MontanaTelemetry.shared.event("ENTROPY \(why) -- the core gave no measures"); return }
        let alive = m.filter { $0.alive }.count
        let flags = m.map { $0.alive ? "1" : "0" }.joined()
        let shares = m.map { String($0.repeatShare) }.joined(separator: ",")
        MontanaTelemetry.shared.event("ENTROPY \(why) alive=\(alive)/6 need=\(minLive) flags=\(flags) repeat%=\(shares)")
    }

    /// THE SEED IS GATHERED BEFORE ANYONE DRAWS (19.09). The first draw of a process instantiates the
    /// core's DRBG — a gather of six sources (a scheduler thread, thirty-two timer sleeps, a walk of a
    /// 512 KiB chain). It used to run wherever the first call landed: under cardLock on the main thread
    /// (1614: 4.6 s, then 0x8BADF00D), inside hmac on the main thread (1688). Now a utility thread pays
    /// it at launch. And the diary names what the run's randomness stands on — which sources the core
    /// found alive, in which proof window, at what clock step: on the iPhone 17 the core refused
    /// randomness eleven times in a week and no line said why («keygen FAIL» named the place, not the
    /// cause). Counts only, not one byte of a source.

    static func warm() {
        let t = Thread {
            var b = [UInt8](repeating: 0, count: 16)
            let rc = mt_random_fast(&b, 16)
            var r = [UInt8](repeating: 0, count: 16)
            let line: String
            if mt_entropy_last_report(&r, 16) == 0 {
                let step = UInt32(r[8]) | UInt32(r[9]) << 8 | UInt32(r[10]) << 16 | UInt32(r[11]) << 24
                line = "rc=\(rc) alive=\(r[0])/6 os=\(r[1]) jitter=\(r[2]) memory=\(r[3]) quartz=\(r[4]) scheduler=\(r[5]) timer=\(r[6]) window=\(r[7]) step_ns=\(step)"
            } else {
                line = "rc=\(rc) report=none"
            }
            MontanaLog.event("ENTROPY " + line)
            MontanaTrace.mark("entropy_report", line)
        }
        t.name = "mt-entropy-warm"
        t.qualityOfService = .utility
        t.start()
    }
}

enum MontanaVersion {
    static var app: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
    // SSOT = the mt-bindings crypto core (single source of truth of the protocol). ABI version.
    static var ssot: String { String(mt_abi_version()) }
    static var footer: String { "iOS \(app) · SSOT \(ssot)" }
}

/// The local name of a correspondence — and there is nothing else a conversation can be called.
///
/// The set is flat about it: no identifier of a person exists ([I-17].2), and no address exists
/// ([I-17].3) — a participant is reached by a tag standing on a secret two of them share, living
/// for one window. So a conversation is not named after whom it is with. It is named after the
/// secret that began it, that name is computed on this device, and it never leaves it.
///
/// What stood here before asked whether a string was an address. It asked about the shape of a
/// public name instead of about possession, it could never be true of any string, and everything
/// it gated stood shut.
enum MontanaConv {

    /// A correspondence this device can answer for, because it holds the secret its tags stand on.
    static func holds(_ conv: String) -> Bool { MTPipeBook.holds(conv) }

    /// The one wording of an invitation, for every place that offers one. What travels is a name or
    /// a card — never a standing string that names a person, because no such string exists here.
    /// What «Share» hands over (the author's word 07.09): «I'm in Montana!» in the sender's
    /// language, then the link on its own line — a line that is only the https link is a link in
    /// every messenger and in mail, and the sentence above it says who is asking.
    /// «<Name> is in Montana!» + the link — what leaves when a person shares a correspondent's
    /// contact (the author's word 15.09); the link opens a new chat with them.
    static func contactMessage(name: String, link: String) -> String {
        guard !link.isEmpty else { return "" }
        let key = "%@ is in Montana!"
        return String(format: MTLanguage.bundle.localizedString(forKey: key, value: key, table: nil), name) + "\n" + link
    }
    /// The words before the link (the author's word 17.09): the kind named, the link itself follows
    /// as its own message.
    static func inviteMessage(permanent: Bool) -> String {
        let key = permanent ? "I'm in Montana! Here is my permanent link:" : "I'm in Montana! Here is my temporary link:"
        return MTLanguage.bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// What a person may hand this client to begin a correspondence: a name, or a card. Anything
    /// shaped like a standing identifier is REFUSED rather than quietly ignored — a person who was
    /// given an old address deserves to be told that addresses are gone, not to watch a scan do
    /// nothing.
    enum Meeting {
        case name(String)
        case card(String)
        case refused
    }

    static func meeting(fromInput raw: String) -> Meeting {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The compact form a camera reads: the same card, packed for the code rather than for a
        // person. It becomes the ordinary card text here, once, so every node below is unchanged.
        if let asCard = MontanaCard.text(fromQR: t) { t = asCard }
        if MontanaCard.isShort(t) { return .card(t) }   // a short invitation: the node unfolds it into a meet
        if MontanaCard.root(inCard: t) != nil { return .card(t) }
        if let n = MontanaFirstContact.name(inInvitation: t) { return .name(n) }
        if let n = MontanaNames.normalize(t.hasPrefix("@") ? String(t.dropFirst()) : t) { return .name(n) }
        return .refused
    }

    /// What a former address looks like, so a person handing one over is told plainly instead of
    /// watching a scan do nothing. Nothing decodes it — there is nothing left to decode it into.
    /// It is recognised by its shape alone: a long run of Base58 letters behind the old prefix,
    /// far past anything a name may be.
    static func looksLikeFormerRef(_ t: String) -> Bool {
        guard t.hasPrefix("mt"), t.count >= 40 else { return false }
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return t.dropFirst(2).allSatisfy { base58.contains($0) }
    }

    /// Short form for JOURNALS. Never for anything a person reads: a conversation is shown by the
    /// name of the person it is with, and when there is none, by a neutral caption.
    static func short(_ c: String) -> String {
        guard c.count > 16 else { return c }
        return String(c.prefix(8)) + "…" + String(c.suffix(6))
    }

    /// Display with clean wrapping: invisible break points prevent auto-hyphenation of a long string.
    static func wrapped(_ a: String) -> String { a.map(String.init).joined(separator: "\u{200B}") }
}

// Stage 1 of the second front — local archive «Montana/Chats/<label>/» (mirror of the app).
// Conversation identity = stable conv_address (address), NOT the displayed label (spec s.2 v0.3.1).
// block_seq is assigned by the core as a per-identity running counter (seq.bin) — the client doesn't pass seq.
// Media is encrypted under media_key (a separate seed branch, ≠ history_key).
// SSOT of archive path names (Swift layer) — BYTE-FOR-BYTE mirror of Rust archive.rs (CHATS_DIR/
// MEDIA_DIR/LOG_FILE). The only place in Swift; all paths reference here, no hardcoding.
enum MontanaPaths {
    static let root = "Montana"          // root directory in Documents
    static let chats = "Chats"           // = archive.rs CHATS_DIR
    static let media = "Media"           // = archive.rs MEDIA_DIR
    static let log = "conversation.mtlog" // = archive.rs LOG_FILE
    static let diagnostics = "Diagnostics"
}

enum MontanaArchive {
    // One-time directory migration ru->en. The Russian names below are DATA, not code language:
    // they name folders created by earlier builds and must stay byte-exact or the migration
    // nested paths are already English via SSOT MontanaPaths.
    static func migrateToEnglishPaths() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let oldRoot = docs.appendingPathComponent("Монтана")   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
        let newRoot = docs.appendingPathComponent(MontanaPaths.root)
        if fm.fileExists(atPath: oldRoot.path) && !fm.fileExists(atPath: newRoot.path) {
            try? fm.moveItem(at: oldRoot, to: newRoot)
        }
        // inside Montana: Chats and Diagnostics
        for (ru, en) in [("Чаты", MontanaPaths.chats), ("Диагностика", MontanaPaths.diagnostics)] {   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
            let o = newRoot.appendingPathComponent(ru), n = newRoot.appendingPathComponent(en)
            if fm.fileExists(atPath: o.path) && !fm.fileExists(atPath: n.path) { try? fm.moveItem(at: o, to: n) }
        }
        // in each chat: Media and the conversation log
        let chats = newRoot.appendingPathComponent(MontanaPaths.chats)
        if let dirs = try? fm.contentsOfDirectory(atPath: chats.path) {
            for d in dirs {
                let cdir = chats.appendingPathComponent(d)
                for (ru, en) in [("Медиа", MontanaPaths.media), ("переписка.mtlog", MontanaPaths.log)] {   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
                    let o = cdir.appendingPathComponent(ru), n = cdir.appendingPathComponent(en)
                    if fm.fileExists(atPath: o.path) && !fm.fileExists(atPath: n.path) { try? fm.moveItem(at: o, to: n) }
                }
            }
        }
    }

    // Localized folder display names for the Files app (Apple `.localized` mechanism):
    // the on-disk names stay stable English (MontanaPaths SSOT), while Files shows the
    // device-language name. Data never moves — switching language is instant and lossless.
    static func ensureLocalizedFolderNames() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let rootURL = docs.appendingPathComponent(MontanaPaths.root)
        func writeLocalized(_ folder: URL, _ key: String, _ ru: String, _ zh: String) {
            guard fm.fileExists(atPath: folder.path) else { return }
            let loc = folder.appendingPathComponent(".localized")
            try? fm.createDirectory(at: loc, withIntermediateDirectories: true)
            for (lang, val) in [("ru", ru), ("zh-Hans", zh), ("en", key), ("Base", key)] {   // NOT-UI: the folder's language names
                let line = "\"\(key)\" = \"\(val)\";\n"
                try? line.data(using: .utf8)?.write(to: loc.appendingPathComponent("\(lang).strings"))
            }
        }
        writeLocalized(rootURL, MontanaPaths.root, "Монтана", "蒙大拿")   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
        writeLocalized(rootURL.appendingPathComponent(MontanaPaths.chats), MontanaPaths.chats, "Чаты", "聊天")   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
        writeLocalized(rootURL.appendingPathComponent(MontanaPaths.diagnostics), MontanaPaths.diagnostics, "Диагностика", "诊断")   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
        let chats = rootURL.appendingPathComponent(MontanaPaths.chats)
        if let dirs = try? fm.contentsOfDirectory(atPath: chats.path) {
            for d in dirs where !d.hasPrefix(".") {
                let media = chats.appendingPathComponent(d).appendingPathComponent(MontanaPaths.media)
                writeLocalized(media, MontanaPaths.media, "Медиа", "媒体")   // CYRILLIC-DATA-OK: folder names created by earlier builds; changing them breaks migration and the localized Files names
            }
        }
    }

    static var rootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(MontanaPaths.root)
    }
    private static var hk: Data?
    private static var mk: Data?
    private static var acct: Data?
    /// The seed left — the keys derived from it leave with it. Cached keys outliving an identity
    /// would seal the next person's archive under the previous person's branch.
    static func forgetKeys() { hk = nil; mk = nil; acct = nil }
    /// Whether the keys already stand in the cache — a main-thread reader may use them; nobody on the
    /// main thread may derive them (see keys()).
    static var isWarm: Bool { hk != nil }
    /// THE KEYS ARE DERIVED OFF THE MAIN THREAD (15.18). The first call of keys() derives the
    /// master seed from the phrase — a deliberately slow function, about two seconds on a phone —
    /// and it used to happen on the main thread at launch, inside the block that applies the
    /// history: the screen stood, the globe stayed grey, the faces waited (measured 07.09 08:36
    /// and 08:41: history read → applied = 2.0 s both times). The derivation runs on the archive
    /// queue; `done` follows on main once the cache holds the keys (or at once when it already does).
    static func whenReady(_ done: @escaping () -> Void) {
        if hk != nil { done(); return }
        ioQueue.async { _ = keys(); DispatchQueue.main.async(execute: done) }
    }
    static func warm() { whenReady {} }
    /// Runs `done` on main once every write queued so far is on disk. The door out waits on
    /// it: a head still in the queue when the seed leaves is a head never written — and the
    /// main thread never blocks on the queue (the layout law, section 6).
    static func whenWritten(_ done: @escaping () -> Void) { ioQueue.async { DispatchQueue.main.async(execute: done) } }
    /// A ROAD THAT MUST NOT CROSS THE WRITER OF THE LOG RUNS HERE (the critic, 23.09). The copy reads
    /// the same files a letter is appended to; on any other queue it would one day read a block cut in
    /// half by an arriving letter and file a copy short of it, silently. The queue that owns the
    /// writing is the only place where that cannot happen — the ownership is the closure, not a retry.
    ///
    /// URGENT when a person is waiting for it (the author, 23.09 18:24: the copy asked for by the switch
    /// sealed 2.9 GB for two and a half minutes behind a spinner): the block rides at user-initiated
    /// priority, and the queue is lifted for it alone; the daily copy stays at the queue's own.
    static func onOwnQueue(urgent: Bool = false, _ work: @escaping () -> Void) {
        if urgent { ioQueue.async(qos: .userInitiated, flags: .enforceQoS, execute: work) } else { ioQueue.async(execute: work) }
    }
    // Sequential background disk-write queue: removes stalls on every
    // message/media (seal+file no longer on the main thread). Order is preserved.
    private static let ioQueue = DispatchQueue(label: "montana.archive.io", qos: .utility)
    /// THE KEY IS BORN ONCE, OFF THE MAIN THREAD (22.09, the critic). T3 (iPhone XS, 1854): the first
    /// letter after a cold start reached archiveRow before warm() had finished, asked for the folder
    /// label, and this function derived the master seed a second time — on the main thread, 2.65 s
    /// (main_slow what=media:archive ms=2653), the screen standing, the bubble waiting. Now: the cache
    /// answers anyone; a cold cache on the main thread answers «no» and writes keys_on_main — the folder
    /// is then resolved on the archive's own queue by the road that asked (archive, heads, media,
    /// deletion all take a convRef and resolve there); off the main thread a single derivation runs
    /// on the key's own serial queue and every other asker waits for it instead of deriving its own copy.
    private static let keyQueue = DispatchQueue(label: "montana.archive.key", qos: .userInitiated)
    private static func keys() -> (hk: Data, mk: Data, acct: Data)? {
        if let h = hk, let m = mk, let a = acct { return (h, m, a) }
        if Thread.isMainThread {
            MontanaTrace.markFolded("keys_on_main", "refused — the archive resolves the folder on its own queue", window: 60)
            return nil
        }
        // MAIN-SAFE-SYNC: never reached from the main thread (refused above); the waiters are the archive's
        // queue, a restore's utility queue and the wire's thread, and what they wait for is the one derivation.
        return keyQueue.sync { deriveKeys() }
    }
    /// Queue-only (keyQueue): the derivation itself, once; a second caller finds the cache.
    private static func deriveKeys() -> (hk: Data, mk: Data, acct: Data)? {
        if let h = hk, let m = mk, let a = acct { return (h, m, a) }
        guard let mn = MontanaSeed.mnemonic,
              let ent = MontanaSeedKeys.entropyFrom(mnemonic: mn) else { return nil }
        var ho = [UInt8](repeating: 0, count: 32)
        var mo = [UInt8](repeating: 0, count: 32)
        let r1 = ent.withUnsafeBytes { mt_history_key($0.bindMemory(to: UInt8.self).baseAddress, &ho) }
        let r2 = ent.withUnsafeBytes { mt_media_key($0.bindMemory(to: UInt8.self).baseAddress, &mo) }
        guard r1 == 0, r2 == 0 else { return nil }
        guard MontanaVault.historyKeyKAT(), MTPipe.agreesWithCanon() else {
            MontanaLog.event("ARCHIVE ✗ frozen vectors of the Canon do not reproduce — history is not written")
            return nil
        }
        // The archive binds its records to the person by the owner branch of their seed: it is
        // derived on the device, never leaves it, and changes exactly when the seed does. What used
        // to stand here was the account identifier — a quantity the set does not have.
        guard let master = MontanaQueueKeys.masterSeed(mn), let owner = MTPipe.ownerSecret(masterSeed: master) else { return nil }
        hk = Data(ho); mk = Data(mo); acct = owner
        return (hk!, mk!, acct!)
    }
    // 16-byte device_id for writer_tag (Stage 1): stable per-install, derived from the stable device string.
    // Distinct devices of one seed → distinct writer_tag → no nonce reuse under a shared history_key.
    /// Per-device tag from the spec (s.2 Stage 1): SHA-256("mt-history-writer" ‖ 0x00 ‖ device_id)[0:4],
    /// derived by the core rather than reimplemented here. It separates nonces of several devices under
    /// one history_key, and it is the only thing that distinguishes my phone from my other phone —
    /// the answering identity is identical on both, being derived from the same seed.
    static func writerTagHex() -> String {
        var out = [UInt8](repeating: 0, count: 4)
        let did = writerTag16()
        guard did.count == 16,
              did.withUnsafeBytes({ mt_writer_tag($0.bindMemory(to: UInt8.self).baseAddress, &out) }) == 0
        else { return "" }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    /// The identifier of THIS device under one seed. Local by nature: it never leaves the device
    /// and names nothing outside it, so it is computed here rather than asked of the core.
    static func writerTag16() -> Data {
        let s = E2E.deviceTag()
        let h = SHA256.hash(data: Data(s.utf8))   // LOCAL-HASH-OK: device-local, not a protocol value
        return Data(Array(h).prefix(16))
    }
    // ArchiveRoot (Stage 2) over the whole local archive — the archive fingerprint for anchoring and
    // cross-device convergence checks. nil if the archive is empty or keys are unavailable.

    // sanitize the folder name — byte-for-byte like in Rust ArchiveStore (path-traversal protection)
    static func sanitizeName(_ n: String) -> String {
        let cleaned = String(n.map { ("/\\:\0".contains($0)) ? "_" : $0 })
        let t = cleaned.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return t.isEmpty ? "_" : t
    }
    // Label rename → migration of folder Montana/Chats/<old> → <new> (conv_id identity does not change).
    // If a folder with the new name already exists — MERGE, not rejection: the log is appended
    // (the length-prefixed stream concatenates correctly), media is moved, duplicates are not overwritten.
    static func renameChatFolder(from old: String, to new: String) {
        let fm = FileManager.default
        let so = sanitizeName(old), sn = sanitizeName(new)
        guard so != sn else { return }
        let chats = rootURL.appendingPathComponent(MontanaPaths.chats)
        let src = chats.appendingPathComponent(so), dst = chats.appendingPathComponent(sn)
        guard fm.fileExists(atPath: src.path) else { return }
        if !fm.fileExists(atPath: dst.path) {
            try? fm.moveItem(at: src, to: dst)
            return
        }
        // merge: the conversation log is appended; media files not present in the destination are moved
        let srcLog = src.appendingPathComponent(MontanaPaths.log)
        let dstLog = dst.appendingPathComponent(MontanaPaths.log)
        if let data = try? Data(contentsOf: srcLog), !data.isEmpty {
            if fm.fileExists(atPath: dstLog.path), let h = try? FileHandle(forWritingTo: dstLog) {
                defer { try? h.close() }
                try? h.seekToEnd(); try? h.write(contentsOf: data)
            } else {
                try? data.write(to: dstLog)
            }
        }
        let srcMedia = src.appendingPathComponent(MontanaPaths.media)
        let dstMedia = dst.appendingPathComponent(MontanaPaths.media)
        if let files = try? fm.contentsOfDirectory(atPath: srcMedia.path) {
            try? fm.createDirectory(at: dstMedia, withIntermediateDirectories: true)
            for f in files where !fm.fileExists(atPath: dstMedia.appendingPathComponent(f).path) {
                try? fm.moveItem(at: srcMedia.appendingPathComponent(f), to: dstMedia.appendingPathComponent(f))
            }
        }
        try? fm.removeItem(at: src)
    }

    // Encrypt media under media_key → Montana/Chats/<label>/Media/<blobId> (other apps see only ciphertext).
    /// THE ONE OWNER OF A CONVERSATION'S FOLDER NAME (22.09, the critic; [C-1]). Every road into the
    /// archive — a letter, a head, a name, a face, a deletion, a migration — names the conversation by
    /// its reference and lets THIS resolve the folder, on the archive's own queue, where the keys are
    /// born: the label from the seed branch, and the folder's old names (the reference itself, the
    /// caption of the row) migrated into it once per process. Nine callers used to resolve the folder
    /// themselves on the main thread through chatFolderName — nine places to derive the key on the
    /// screen's thread.
    private static var migrated = Set<String>()   // queue-only
    private static func resolveFolder(convRef: String, legacy: [String]) -> String? {
        guard let label = folderLabel(for: convRef) else { return nil }   // no seed at hand — nothing to write under
        if migrated.insert(convRef).inserted {
            for old in ([convRef] + legacy) where !old.isEmpty && old != label { renameChatFolder(from: old, to: label) }
        }
        rememberFolder(convRef: convRef, folder: label)
        return label
    }
    /// Merge the folders of a conversation's historical names into its label — on the queue, once.
    static func migrate(convRef: String, legacy: [String]) {
        ioQueue.async { _ = resolveFolder(convRef: convRef, legacy: legacy) }
    }
    static func putMedia(convRef: String, legacy: [String], blobId: String, data: Data) {
        ioQueue.async {
            guard let folder = resolveFolder(convRef: convRef, legacy: legacy) else { return }
            putMediaIn(folder: folder, blobId: blobId, data: data)
        }
    }
    /// Queue-only: the sealed write itself, under a folder already resolved.
    private static func putMediaIn(folder: String, blobId: String, data: Data) {
        guard let (_, m, a) = keys() else { return }
        let base = rootURL.path
        _ = base.withCString { bp in folder.withCString { cn in blobId.withCString { bid in
            m.withUnsafeBytes { mp in a.withUnsafeBytes { ap in data.withUnsafeBytes { dp in
                mt_archive_put_media(bp, cn, bid,
                    mp.bindMemory(to: UInt8.self).baseAddress,
                    ap.bindMemory(to: UInt8.self).baseAddress,
                    data.isEmpty ? nil : dp.bindMemory(to: UInt8.self).baseAddress, data.count)
            }}}
        }}}
    }
    // Decrypt media from the chat folder (for playback/display) — client only, by seed.
    // Buffer = sealed file size (plaintext ≤ sealed), so a video of any size is read.
    static func getMedia(folder: String, blobId: String) -> Data? {
        guard let (_, m, a) = keys() else { return nil }
        let path = rootURL.appendingPathComponent(MontanaPaths.chats).appendingPathComponent(sanitizeName(folder))
            .appendingPathComponent(MontanaPaths.media).appendingPathComponent(sanitizeName(blobId))
        let sealedSize = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? nil
        let cap = max(sealedSize ?? 0, 1024)
        var out = [UInt8](repeating: 0, count: cap)
        let n = rootURL.path.withCString { bp in folder.withCString { cn in blobId.withCString { bid in
            m.withUnsafeBytes { mp in a.withUnsafeBytes { ap in
                mt_archive_get_media(bp, cn, bid,
                    mp.bindMemory(to: UInt8.self).baseAddress,
                    ap.bindMemory(to: UInt8.self).baseAddress, &out, out.count)
            }}
        }}}
        if n > 0 { return Data(out.prefix(Int(n))) }
        // A FACE IS ITS OWN FOLDER'S OR NONE (04.10, T1 03.10 23:49 MSK: one portrait on most of the book): every folder names its
        // face by the one word «face», so the search below handed the first folder's face to every correspondent without one.
        guard blobId != faceBlob else { return nil }
        // The folder could have been named otherwise yesterday -- by callsign, by link, by a word common
        // to all. A file name is unique across the whole archive, so it is searched for across the
        // archive rather than guessed at: renaming a folder must not tear an attachment from its letter.
        for other in conversations() where other != folder {
            let alt = rootURL.appendingPathComponent(MontanaPaths.chats).appendingPathComponent(sanitizeName(other))
                .appendingPathComponent(MontanaPaths.media).appendingPathComponent(sanitizeName(blobId))
            guard FileManager.default.fileExists(atPath: alt.path) else { continue }
            let size = ((try? FileManager.default.attributesOfItem(atPath: alt.path)[.size] as? Int) ?? nil) ?? 0
            var buf = [UInt8](repeating: 0, count: max(size, 1024))
            let k = rootURL.path.withCString { bp in other.withCString { cn in blobId.withCString { bid in
                m.withUnsafeBytes { mp in a.withUnsafeBytes { ap in
                    mt_archive_get_media(bp, cn, bid,
                        mp.bindMemory(to: UInt8.self).baseAddress,
                        ap.bindMemory(to: UInt8.self).baseAddress, &buf, buf.count)
                }}
            }}}
            if k > 0 { return Data(buf.prefix(Int(k))) }
        }
        return nil
    }

    // Message archive: convRef → stable conv_id; folder → displayed label. The core assigns block_seq.
    static func archive(convRef: String, legacy: [String], isFromMe: Bool, createdAt: Double, text: String) {
        guard !text.isEmpty else { return }
        let conv = MontanaQueueKeys.sha256(Data(convRef.utf8))
        let content = Data(text.utf8)
        let dir: UInt8 = isFromMe ? 0 : 1
        let st = UInt64(max(0, createdAt))
        let base = rootURL.path
        let dev16 = Self.writerTag16()
        ioQueue.async {
            guard let folder = resolveFolder(convRef: convRef, legacy: legacy),
                  let (h, _, a) = keys() else { return }   // the folder and the key are born HERE, never on the screen's thread
            _ = base.withCString { bp in folder.withCString { cn in
                h.withUnsafeBytes { hp in a.withUnsafeBytes { ap in dev16.withUnsafeBytes { dp in conv.withUnsafeBytes { cp in content.withUnsafeBytes { ctp in
                    mt_archive_append(bp, cn,
                        hp.bindMemory(to: UInt8.self).baseAddress,
                        ap.bindMemory(to: UInt8.self).baseAddress,
                        dp.bindMemory(to: UInt8.self).baseAddress,
                        cp.bindMemory(to: UInt8.self).baseAddress, dir, st,
                        ctp.bindMemory(to: UInt8.self).baseAddress, content.count)
                }}}}}
            }}
        }
    }
}

// ═══════════════════════════════════════════════════════════════ History across a person's own
// devices.
//
// One person, one identity, several devices. Every device is its own writer in the shared archive:
// the core stamps each block with (writer_tag, block_seq), and a block is sealed under the history
// key before it ever leaves the device. Replication therefore carries bytes nobody else can read —
// the phone that relays them sees a length, not a conversation.
//
// Both devices answer to that one reference, so a device reaching its twin needs nothing new — no
// store, no account server, no third party holding the bytes.
//
// The receiver tells a history block from a media chunk by opening it: a block that authenticates
// under this person's history key is history, and nothing on the wire says which is which.
// Duplicates cost nothing — the core drops a block whose (writer_tag, block_seq) it already holds,
// so the same block may arrive over any transport, any number of times.
extension MontanaArchive {
    private static let cursorKey = "mt.history.pushed"

    static func writerTag() -> Data? {
        var out = [UInt8](repeating: 0, count: 4)
        let did = writerTag16()
        let rc = did.withUnsafeBytes { dp in mt_writer_tag(dp.bindMemory(to: UInt8.self).baseAddress, &out) }
        return rc == 0 ? Data(out) : nil
    }

    /// The on-disk name of a conversation folder -- a value that says NOTHING to whoever sees it.
    ///
    /// The app folder is open in Files and travels into the backup, and a folder name is encrypted by
    /// nothing -- by it alone the whole list of peers was read, without a single decryption: here stood
    /// the person's callsign, and in the fallback case the conversation link itself, the very one next
    /// to which it is written "never leaves the device". That one name opened every door at once --
    /// Files, the wire, the backup, any future export outward -- and so it is closed, rather than the
    /// doors one by one.
    ///
    /// LOCAL-HASH-OK: the label is derived from the seed history branch by the same SHA-256 as the whole
    /// archive; nothing of our own is invented here. From the seed -- so that after a recovery by the
    /// same words the folders are found, and so that nobody but the owner can derive the label.
    /// A main-thread reader's question: the label when the keys already stand, nil when they do not —
    /// it never derives (the audit of the list asks this way; a cold answer is «unknown yet», not a stall).
    static func labelIfWarm(for conv: String) -> String? { isWarm ? folderLabel(for: conv) : nil }
    /// The label asked ON THE ARCHIVE'S QUEUE, where the key may be born (the copy's road leaves a
    /// conversation out by its folder). The main thread gets no answer here, as everywhere.
    static func labelOnQueue(for conv: String) -> String? { Thread.isMainThread ? nil : folderLabel(for: conv) }
    private static func folderLabel(for conv: String) -> String? {
        guard !conv.isEmpty, let (hk, _, _) = keys() else { return nil }
        var m = Data("mt-archive-label".utf8); m.append(0); m.append(hk); m.append(0)
        m.append(contentsOf: conv.utf8)
        return SHA256.hash(data: m).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Folders left from DELETED conversations are named the old way -- by callsign or by link -- and
    /// their names alone still tell whom the person spoke with. A live conversation is renamed by its
    /// own path (the resolver, resolveFolder); everything else lands here.
    /// The data is not touched: only the name changes, and with it the meaning.
    static func sealOrphanFolderNames(keeping live: Set<String>) {
        // The same queue as the moves of live conversations: otherwise a pass would seal a name an
        // instant before the conversation moves by it, and there would be nothing left to move.
        ioQueue.async {
            let chats = rootURL.appendingPathComponent(MontanaPaths.chats)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: chats.path)) ?? []
            for n in names where !n.hasPrefix(".") && !live.contains(n) && !isLabel(n) {
                guard let sealed = folderLabel(for: n) else { return }   // no seed -- nothing to derive from, we wait
                renameChatFolder(from: n, to: sealed)
            }
        }
    }

    static func isLabel(_ n: String) -> Bool {
        n.count == 32 && n.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// The names of every sealed attachment in the archive, in one list. By it one sees which open copy
    /// on disk is already redundant: what lies sealed needs no second instance.
    static func mediaNames() -> Set<String> {
        var out = Set<String>()
        let chats = rootURL.appendingPathComponent(MontanaPaths.chats)
        for folder in conversations() {
            let dir = chats.appendingPathComponent(sanitizeName(folder)).appendingPathComponent(MontanaPaths.media)
            for n in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !n.hasPrefix(".") {
                out.insert(n)
            }
        }
        return out
    }

    /// The size of a sealed attachment WITHOUT decryption. The "we do not take larger into memory"
    /// bound was checked after reading, that is, memory was already fully taken: at three hundred
    /// megabytes the app was killed before the bound could fire.
    static func mediaSize(blobId: String) -> Int {
        let chats = rootURL.appendingPathComponent(MontanaPaths.chats)
        for folder in conversations() {
            let u = chats.appendingPathComponent(sanitizeName(folder))
                .appendingPathComponent(MontanaPaths.media).appendingPathComponent(sanitizeName(blobId))
            if let n = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? nil { return n }
        }
        return .max   // no file -- we count it "too large": there is nothing to read anyway
    }

    /// An attachment by name, across the whole archive. A file name is unique across the archive (att_
    /// or voice_ plus a random identifier), so knowing the conversation is not needed to read: the
    /// showing code need not remember where the file lies, and renaming a folder does not tear it away.
    static func findMedia(blobId: String) -> Data? {
        for folder in conversations() {
            if let d = getMedia(folder: folder, blobId: blobId) { return d }
        }
        return nil
    }

    /// No conversation means no trace of it on disk: letters, sealed attachments, the folder itself.
    /// Deleting for oneself and deleting for both erase the SAME local storage.
    static func deleteChatFolder(convRef: String) {
        ioQueue.async {
            guard let label = folderLabel(for: convRef) else { return }
            let dir = rootURL.appendingPathComponent(MontanaPaths.chats).appendingPathComponent(sanitizeName(label))
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Conversations this device holds, by their folder name under Chats/.
    static func conversations() -> [String] {
        let chats = rootURL.appendingPathComponent(MontanaPaths.chats)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: chats.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
    }

    /// Send every block this device wrote and the twin has not seen yet. Called when the person's own
    /// reference becomes reachable — the same event that drains a pending letter.
    static func replicate(to ref: String) {
        guard !ref.isEmpty, let wt = writerTag() else { return }
        ioQueue.async {
            var cursor = (MontanaLocalVault.getDecrypted(cursorKey)
                .flatMap { try? JSONDecoder().decode([String: UInt64].self, from: $0) }) ?? [:]
            var sentBlocks = 0
            for chat in conversations() {
                let from = cursor[chat] ?? 0
                guard let stream = export(chat: chat, writerTag: wt, fromSeq: from) else { continue }
                var top = from
                for (seq, sealed) in stream {
                    let id = blobId(of: sealed)
                    if MontanaPhoneNode.shared.sendBlobDirect(to: ref, blobId: id, sealed: sealed) {
                        sentBlocks += 1
                        top = max(top, seq + 1)
                    }
                }
                if top != from { cursor[chat] = top }
            }
            if let d = try? JSONEncoder().encode(cursor) { MontanaLocalVault.setEncrypted(cursorKey, d) }
            if sentBlocks > 0 { MontanaLog.event("HISTORY → own device: \(sentBlocks) blocks") }
        }
    }

    /// A sealed blob arrived. If it opens under this person's history key it is a block of their own
    /// history and is filed; otherwise it belongs to another path and this returns false untouched.
    @discardableResult
    static func absorb(_ sealed: Data) -> Bool {
        guard let (h, _, a) = keys(), let conv = peekConv(sealed, hk: h, acct: a) else { return false }
        let folder = folderName(forConv: conv) ?? conv.montanaHexString
        let base = rootURL.path
        let rc = base.withCString { bp in folder.withCString { cn in
            h.withUnsafeBytes { hp in a.withUnsafeBytes { ap in sealed.withUnsafeBytes { sp in
                mt_archive_ingest(bp, cn,
                    hp.bindMemory(to: UInt8.self).baseAddress,
                    ap.bindMemory(to: UInt8.self).baseAddress,
                    sp.bindMemory(to: UInt8.self).baseAddress, sealed.count)
            }}}
        }}
        if rc == 1 {
            MontanaLog.event("HISTORY ← own device: block filed in \(folder.prefix(12))")
            // The block is filed — and now it is READ: the same road the phrase walks, so the
            // twin's rows reach the feed instead of resting sealed beside it (Stage 6, both ends).
            NotificationCenter.default.post(name: .montanaArchiveIngested, object: nil, userInfo: ["folder": folder])
        }
        return rc >= 0
    }

    /// Which conversation a sealed block belongs to — readable only by the holder of the history key.
    private static func peekConv(_ sealed: Data, hk h: Data, acct a: Data) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = h.withUnsafeBytes { hp in a.withUnsafeBytes { ap in sealed.withUnsafeBytes { sp in
            mt_archive_peek_conv(hp.bindMemory(to: UInt8.self).baseAddress,
                                 ap.bindMemory(to: UInt8.self).baseAddress,
                                 sp.bindMemory(to: UInt8.self).baseAddress, sealed.count, &out)
        }}}
        return rc == 0 ? Data(out) : nil
    }

    /// The blocks this device wrote in one conversation, from a sequence number onward.
    private static func export(chat: String, writerTag wt: Data, fromSeq: UInt64) -> [(UInt64, Data)]? {
        var buf = [UInt8](repeating: 0, count: 1 << 20)
        let n = rootURL.path.withCString { bp in chat.withCString { cn in
            wt.withUnsafeBytes { wp in
                mt_archive_export(bp, cn, wp.bindMemory(to: UInt8.self).baseAddress, fromSeq, &buf, buf.count)
            }
        }}
        guard n > 0 else { return nil }
        var out: [(UInt64, Data)] = []
        var i = 0
        let total = Int(n)
        while i + 4 <= total {
            let len = Int(UInt32(buf[i]) | UInt32(buf[i+1]) << 8 | UInt32(buf[i+2]) << 16 | UInt32(buf[i+3]) << 24)
            i += 4
            guard len > 0, i + len <= total else { break }
            let sealed = Data(buf[i..<(i+len)])
            i += len
            if let seq = blockSeq(of: sealed) { out.append((seq, sealed)) }
        }
        return out.isEmpty ? nil : out
    }

    private static func blockSeq(of sealed: Data) -> UInt64? {
        var tag = [UInt8](repeating: 0, count: 4)
        var seq: UInt64 = 0
        let rc = sealed.withUnsafeBytes { sp in
            mt_archive_block_id(sp.bindMemory(to: UInt8.self).baseAddress, sealed.count, &tag, &seq)
        }
        return rc == 0 ? seq : nil
    }

    /// Wire name of a sealed block: the same name a media chunk gets, computed by the same core
    /// function — so the shape of what travels says nothing about what it is.
    private static func blobId(of sealed: Data) -> String { MontanaMedia.blobIdHex(sealed) }

    /// Folder a conversation is filed under. Learned where history is written, so a replicated block
    /// lands beside the letters it belongs with instead of a folder named after a hash.
    private static let folderMapKey = "mt.history.folders"
    /// Queue-only (the resolver calls it): the conv → folder map and the folder's head.
    private static func rememberFolder(convRef: String, folder: String) {
        let conv = MontanaQueueKeys.sha256(Data(convRef.utf8)).montanaHexString
        var map = (MontanaLocalVault.getDecrypted(folderMapKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
        guard map[conv] != folder else { return }
        map[conv] = folder
        if let d = try? JSONEncoder().encode(map) { MontanaLocalVault.setEncrypted(folderMapKey, d) }
        writeHeadIn(convRef: convRef, folder: folder)
    }

    // ── THE READING ROAD (15.10) ───────────────────────────────────────────────
    // The archive used to be a write-only mirror: letters went in sealed under the seed, the
    // twin received them sealed, and nothing ever turned a block back into a row. «Forget this
    // device» wiped the feed and left the archive whole, and the 24 words brought back the
    // identity in front of empty chats (the author, 06.09). Two things close it: the log is read
    // and opened through the core, and every folder carries a HEAD record with the address of
    // the correspondence — a block holds only sha256(address), and the folder name is a keyed
    // hash, so without the head a restored chat would be a transcript nobody can answer.

    /// dir of a head item.
    static let headDir: UInt8 = 2
    private static let headsKey = "mt.history.heads.form"

    /// The address of the correspondence, sealed into its own folder. The marker keys on the FORM
    /// of the head, not on the folder: a head written as a bare address while the device did not
    /// yet hold the secret (builds 1345–1348) is followed by the secret head the moment the book
    /// holds it. A folder marked «written» once and never again froze the address form on every
    /// folder of T2, and an address names nothing to a device whose book is empty after a restore
    /// by seed (07.09: archive_restore headed=0 on every folder). A duplicate head is harmless —
    /// restore takes the secret first — so the marker is only an economy.
    static func writeHead(convRef: String, legacy: [String]) {
        ioQueue.async {
            guard let folder = resolveFolder(convRef: convRef, legacy: legacy) else { return }
            writeHeadIn(convRef: convRef, folder: folder)
        }
    }
    /// Queue-only: the head under a folder already resolved.
    private static func writeHeadIn(convRef: String, folder: String) {
        var heads = (MontanaLocalVault.getDecrypted(headsKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
        // The head is the PIPE SECRET when the device holds it (the reference — the chat key — is
        // sha256 of it, so the address needs no second field), and the bare address otherwise.
        // A secret is born at first contact and derives from nothing; the archive is the one
        // place sealed under the seed where it may live, and without it a restored chat could be
        // read but never answered (critic pass 06.09).
        let content: Data, form: String
        if let sec = MTPipeBook.secret(for: convRef), MTPipeBook.reference(of: sec) == convRef {
            content = Data("s:".utf8) + Data(sec.base64EncodedString().utf8); form = "s"
        } else {
            content = Data("a:".utf8) + Data(convRef.utf8); form = "a"
        }
        guard heads[folder] != form else { return }
        heads[folder] = form
        if let d = try? JSONEncoder().encode(heads) { MontanaLocalVault.setEncrypted(headsKey, d) }
        appendHead(convRef: convRef, folder: folder, content: content)
        MontanaTrace.mark("archive_head", "folder=\(folder.prefix(8)) form=\(form)")
    }
    /// THE PIPE CLOSED AT THE OTHER END (24.09): the conversation's folder says so in its own log, so no restore — this
    /// device's next cold start, or a copy taken back on another — revives the pipe from the secret the folder also holds.
    static func closeHead(convRef: String, legacy: [String]) {
        ioQueue.async {
            guard let folder = resolveFolder(convRef: convRef, legacy: legacy) else { return }
            var heads = (MontanaLocalVault.getDecrypted(headsKey)
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
            heads[folder] = "x"
            if let d = try? JSONEncoder().encode(heads) { MontanaLocalVault.setEncrypted(headsKey, d) }
            appendHead(convRef: convRef, folder: folder, content: Data("x:".utf8))   // COMPAT-LOCAL: a head form of the archive on the device
            MontanaTrace.mark("archive_head", "folder=\(folder.prefix(8)) form=x")
        }
    }
    /// Queue-only: one head block appended to a folder's log.
    private static func appendHead(convRef: String, folder: String, content: Data) {
        let conv = MontanaQueueKeys.sha256(Data(convRef.utf8))
        let base = rootURL.path
        let dev16 = Self.writerTag16()
        let st = UInt64(Date().timeIntervalSince1970)
        guard let (h, _, a) = keys() else { return }
        _ = base.withCString { bp in folder.withCString { cn in
            h.withUnsafeBytes { hp in a.withUnsafeBytes { ap in dev16.withUnsafeBytes { dp in conv.withUnsafeBytes { cp in content.withUnsafeBytes { ctp in
                mt_archive_append(bp, cn,
                    hp.bindMemory(to: UInt8.self).baseAddress,
                    ap.bindMemory(to: UInt8.self).baseAddress,
                    dp.bindMemory(to: UInt8.self).baseAddress,
                    cp.bindMemory(to: UInt8.self).baseAddress, headDir, st,
                    ctp.bindMemory(to: UInt8.self).baseAddress, content.count)
            }}}}}
        }}
    }

    struct RestoredItem { let mine: Bool; let sentAt: Double; let text: String }
    struct RestoredChat { let folder: String; let ref: String?; let name: String?; let face: Data?; let items: [RestoredItem] }
    /// The correspondent's face, sealed beside their letters under the media key of the seed.
    static let faceBlob = "face"
    /// The face file of the open avatar store, read here (off the screen file) and sealed into
    /// the folder. False when there is no such file or it is empty.
    static func sealFace(convRef: String, legacy: [String], avatarFile: String) -> Bool {
        guard let d = try? Data(contentsOf: avatarsDirURL().appendingPathComponent(avatarFile)), !d.isEmpty else { return false }
        putMedia(convRef: convRef, legacy: legacy, blobId: faceBlob, data: d)
        return true
    }

    private static let nameHeadsKey = "mt.history.nameheads"
    /// The correspondent's declared name, sealed beside their letters: a restored chat wears its
    /// name instead of «Correspondent». Rewritten when the name changes (the marker keys on the
    /// name too); restore takes the last one.
    static func writeNameHead(convRef: String, legacy: [String], name: String) {
        ioQueue.async {
            guard let folder = resolveFolder(convRef: convRef, legacy: legacy) else { return }
            writeNameHeadIn(convRef: convRef, folder: folder, name: name)
        }
    }
    /// Queue-only: the name head under a folder already resolved.
    private static func writeNameHeadIn(convRef: String, folder: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return }
        var marks = (MontanaLocalVault.getDecrypted(nameHeadsKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
        guard marks[folder] != trimmed else { return }
        marks[folder] = trimmed
        if let d = try? JSONEncoder().encode(marks) { MontanaLocalVault.setEncrypted(nameHeadsKey, d) }
        let conv = MontanaQueueKeys.sha256(Data(convRef.utf8))
        let content = Data("n:".utf8) + Data(trimmed.utf8)
        let base = rootURL.path
        let dev16 = Self.writerTag16()
        let st = UInt64(Date().timeIntervalSince1970)
        guard let (h, _, a) = keys() else { return }
        _ = base.withCString { bp in folder.withCString { cn in
            h.withUnsafeBytes { hp in a.withUnsafeBytes { ap in dev16.withUnsafeBytes { dp in conv.withUnsafeBytes { cp in content.withUnsafeBytes { ctp in
                mt_archive_append(bp, cn,
                    hp.bindMemory(to: UInt8.self).baseAddress,
                    ap.bindMemory(to: UInt8.self).baseAddress,
                    dp.bindMemory(to: UInt8.self).baseAddress,
                    cp.bindMemory(to: UInt8.self).baseAddress, headDir, st,
                    ctp.bindMemory(to: UInt8.self).baseAddress, content.count)
            }}}}}
        }}
    }

    /// The sealed blocks of one folder, in file order: (u32 LE length ‖ sealed)×N — the same
    /// layout the core writes (archive.rs read_blocks).
    private static func readLog(folder: String) -> [Data] {
        let url = rootURL.appendingPathComponent(MontanaPaths.chats).appendingPathComponent(folder)
            .appendingPathComponent(MontanaPaths.log)
        guard let data = try? Data(contentsOf: url) else { return [] }
        var out: [Data] = []; var i = 0; let n = data.count
        while i + 4 <= n {
            let len = Int(UInt32(data[i]) | UInt32(data[i+1]) << 8 | UInt32(data[i+2]) << 16 | UInt32(data[i+3]) << 24)
            i += 4
            guard len > 0, i + len <= n else { break }
            out.append(data.subdata(in: i..<(i+len))); i += len
        }
        return out
    }

    /// One block opened by the core and decoded from the canonical block encoding.
    private static func openBlock(_ sealed: Data, hk h: Data, acct a: Data) -> [(conv: Data, dir: UInt8, at: UInt64, content: Data)] {
        var buf = [UInt8](repeating: 0, count: max(1024, sealed.count + 64))
        let n = h.withUnsafeBytes { hp in a.withUnsafeBytes { ap in sealed.withUnsafeBytes { sp in
            mt_archive_open_block(hp.bindMemory(to: UInt8.self).baseAddress, ap.bindMemory(to: UInt8.self).baseAddress,
                                  sp.bindMemory(to: UInt8.self).baseAddress, sealed.count, &buf, buf.count)
        }}}
        guard n > 12 else { return [] }
        let d = Data(buf[0..<Int(n)])
        func u32(_ o: Int) -> Int { Int(UInt32(d[o]) | UInt32(d[o+1]) << 8 | UInt32(d[o+2]) << 16 | UInt32(d[o+3]) << 24) }
        func u64(_ o: Int) -> UInt64 { var v: UInt64 = 0; for k in 0..<8 { v |= UInt64(d[o+k]) << (8*UInt64(k)) }; return v }
        var items: [(Data, UInt8, UInt64, Data)] = []
        let count = u32(8); var o = 12
        for _ in 0..<count {
            guard o + 32 + 1 + 8 + 4 <= d.count else { break }
            let conv = d.subdata(in: o..<(o+32)); o += 32
            let dir = d[o]; o += 1
            let at = u64(o); o += 8
            let len = u32(o); o += 4
            guard o + len <= d.count else { break }
            items.append((conv, dir, at, d.subdata(in: o..<(o+len)))); o += len
        }
        return items
    }

    /// Every conversation the sealed archive holds, opened under the seed: the head gives the
    /// address, the letters give the rows. A folder without a head (written by an older build)
    /// comes back as a transcript under its folder name — readable, not answerable.
    static func restoreAll() -> [RestoredChat] { restore(folders: conversations()) }

    /// folder label → address, for every correspondence the pipe book answers for.
    static func refBook() -> [String: String] {
        var m: [String: String] = [:]
        for conv in MTPipeBook.all() { if let f = folderLabel(for: conv) { m[f] = conv } }
        return m
    }

    static func restore(folders: [String]) -> [RestoredChat] {
        guard let (h, _, a) = keys() else { return [] }
        let book = refBook()
        var out: [RestoredChat] = []
        var headsS = 0, headsA = 0, headsN = 0, faces = 0
        for folder in folders {
            var ref: String? = nil
            var name: String? = nil
            var items: [RestoredItem] = []
            var headSecret: Data? = nil
            var closedThere = false
            for sealed in readLog(folder: folder) {
                for it in openBlock(sealed, hk: h, acct: a) {
                    if it.dir == headDir {
                        guard let s = String(data: it.content, encoding: .utf8) else { continue }
                        // COMPAT-LOCAL: the head forms s:/a:/n: live only in the sealed archive on the
                        // device, never on the wire; an older archive's bare address is read below.
                        if s.hasPrefix("s:"), let sec = Data(base64Encoded: String(s.dropFirst(2))), sec.count == 32 {
                            // The secret re-establishes the pipe once the whole log is read: from there the device
                            // answers for the correspondence again, and the reference is its chat key.
                            headsS += 1
                            headSecret = sec
                        } else if s.hasPrefix("x:") {   // COMPAT-LOCAL: the pipe was closed at the other end (24.09)
                            closedThere = true
                        } else if s.hasPrefix("a:") {   // COMPAT-LOCAL: archive head, see above
                            headsA += 1
                            if ref == nil, MontanaConv.holds(String(s.dropFirst(2))) { ref = String(s.dropFirst(2)) }
                        } else if s.hasPrefix("n:") {
                            headsN += 1
                            name = String(s.dropFirst(2))
                        } else if ref == nil, MontanaConv.holds(s) {
                            ref = s
                        }
                        continue
                    }
                    guard let text = String(data: it.content, encoding: .utf8), !text.isEmpty else { continue }
                    items.append(RestoredItem(mine: it.dir == 0, sentAt: Double(it.at), text: text))
                }
            }
            // A PIPE CLOSED AT THE OTHER END IS NAMED, NEVER RE-ESTABLISHED (24.09): the history is the conversation's,
            // and the other side holds the secret no more — a revived pipe would be a composer writing into nothing.
            if let sec = headSecret {
                if closedThere { ref = MTPipeBook.reference(of: sec) }
                else if let r = MTPipeBook.establish(secret: sec, seal: false) { ref = r }
            }
            // No head, or none this device can use: the folder name is the keyed hash of the
            // address, so every correspondence the device still answers for names its own folder.
            // This is what a healthy device relies on — a head is only for a device that lost its book.
            if ref == nil, let known = book[folder] { ref = known }
            // The person's own «Saved Messages» carries no head — there is no secret to hold for
            // oneself — but its label derives from the seed alone, so a restored device names it
            // itself instead of filing its own notes as a transcript of a stranger (T2, 07.09).
            if ref == nil, folder == folderLabel(for: savedMessagesKey) { ref = savedMessagesKey }
            guard !items.isEmpty || ref != nil else { continue }
            items.sort { $0.sentAt < $1.sentAt }
            if let ref = ref { ioQueue.async { rememberFolder(convRef: ref, folder: folder) } }   // the map is the queue's to write
            let face = ref == nil ? nil : getMedia(folder: folder, blobId: faceBlob)
            if face != nil { faces += 1 }
            out.append(RestoredChat(folder: folder, ref: ref, name: name, face: face, items: items))
        }
        MontanaTrace.mark("archive_restore", "chats=\(out.count) rows=\(out.reduce(0) { $0 + $1.items.count }) headed=\(out.filter { $0.ref != nil }.count) heads=s\(headsS)/a\(headsA)/n\(headsN) faces=\(faces)")
        return out
    }
    private static func folderName(forConv conv: Data) -> String? {
        (MontanaLocalVault.getDecrypted(folderMapKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) })?[conv.montanaHexString]
    }
}
