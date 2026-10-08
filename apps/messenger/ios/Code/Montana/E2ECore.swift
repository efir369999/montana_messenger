//
//  E2ECore.swift — shared Montana crypto core (post-quantum: ML-KEM-768 + PQXDH + KEM ratchet + ChaCha20-Poly1305).
//  Used by BOTH the app AND the notification extension (single source of truth for crypto).
//  NO UI/network dependencies here — only Foundation/CryptoKit/Security.
//

import Foundation
import CryptoKit
import MontanaBindings
import CommonCrypto
import Security

extension SharedSecret { var e2eRaw: Data { withUnsafeBytes { Data($0) } } }

func e2b64e(_ d: Data) -> String { d.base64EncodedString() }
func e2b64d(_ s: String) -> Data { Data(base64Encoded: s) ?? Data() }
func e2HKDF(_ ikm: Data, _ info: String) -> Data {
    let k = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm),
                                   salt: Data(count: 32), info: Data(info.utf8), outputByteCount: 32)
    return k.withUnsafeBytes { Data($0) }
}

// Call signaling types (Stage 13) — Codable, available to both the app and the NSE.
struct CallSDP: Codable { var type: String; var sdp: String }
struct CallICE: Codable { var candidate: String; var sdpMid: String?; var sdpMLineIndex: Int32? }
// `av` — this phone reads an ANSWER that arrives by the wake road (13.09). A build that does not
// know the flag simply never sets it, and its correspondent keeps the lane road for the answer;
// an unknown key in the JSON is ignored on decoding, so the word costs older builds nothing.
// rejoin (24.09): this build rebuilds a call in place when the far run comes back into it -- the far side waits for it
// and its rejoin is answered without a ring. Old builds skip the key; a peer that never said it is never sent a rejoin.
struct CallCaps: Codable { var tier: String?; var ver: Int?; var opus_max: Int?; var hw_aec: Bool?; var sframe: Bool?; var av: Bool?; var rejoin: Bool? }
struct E2EPlain: Codable { var body: String; var conv: String; var mid: String?; var ts: Int?
    var ctrl: String?; var sdp: CallSDP?; var candidate: CallICE?; var video: Bool?; var caps: CallCaps?; var call_seed: String? }
struct E2ESession: Codable { var blob: String }
struct E2EKeyState: Codable {
    var deviceId: String
    var spkId: Int; var spkPub: String; var spkSk: String
}
struct E2EPeerDevice: Codable {
    var deviceId: String
    var signPub: String
    var appKemPub: String
    var appKemSig: String

    /// A device the channel is ALREADY open with: seal takes the ratchet from sessions by
    /// "reference|deviceId" and needs no key material, which is only used when a channel is first
    /// built. This lets a letter go without asking the network for a key bundle.
    /// Empty keys are safe here: if the session turns out to be missing, seal returns nil on the
    /// key-size check (1952/1184/1184) and the letter goes to the queue for a retry, where the
    /// bundle is fetched again.
    static func sessionOnly(_ deviceId: String) -> E2EPeerDevice {
        E2EPeerDevice(deviceId: deviceId, signPub: "", appKemPub: "", appKemSig: "")
    }
}

// ── Device linking: transferring the history key between devices of one account via
// QR + ephemeral ML-KEM-768 (post-quantum, [I-1]). The new device publishes an ephemeral
// KEM key in the QR; the old one encapsulates a shared secret to it and wraps acc_key under
// ChaCha20-Poly1305. Anything outside the device sees an opaque wrapper — it can neither read acc_key,
// nor substitute the device; a quantum adversary recording traffic does not recover the history key.
struct LinkOffer: Codable { var v: Int; var dev: String; var epk: String; var nonce: String }
struct LinkGrant: Codable { var t: String; var kct: String; var ct: String }   // t = "lnk"; kct = ML-KEM ciphertext

enum MontanaLink {
    // New device: ephemeral pair + QR payload. Returns (private key b64, offer).
    static func makeOffer(deviceId: String) -> (ephPriv: String, offer: LinkOffer)? {
        var seed = Data(count: 64)
        // The seed of a handshake comes from the CORE, which folds the sources of the machine and
        // refuses when fewer than three are alive. Taking it from one source means trusting one source.
        guard seed.withUnsafeMutableBytes({ p -> Bool in
            guard let base = p.bindMemory(to: UInt8.self).baseAddress else { return false }
            return mt_random_fast(base, 64) == 0
        }) else { return nil }
        var ephPub = [UInt8](repeating: 0, count: 1184); var ephSk = [UInt8](repeating: 0, count: 2400)
        let kg = seed.withUnsafeBytes { sp -> Int32 in mt_mlkem_keypair_from_seed(sp.bindMemory(to: UInt8.self).baseAddress, &ephPub, &ephSk) }
        guard kg == 0 else { return nil }
        // The nonce is folded into the key that wraps the account key — same source as the seed.
        var n = Data(count: 16)
        guard n.withUnsafeMutableBytes({ p -> Bool in
            guard let base = p.bindMemory(to: UInt8.self).baseAddress else { return false }
            return mt_random_fast(base, 16) == 0
        }) else { return nil }
        let offer = LinkOffer(v: 1, dev: deviceId, epk: e2b64e(Data(ephPub)), nonce: e2b64e(n))
        return (e2b64e(Data(ephSk)), offer)   // ephPriv = ML-KEM seckey
    }
    // Old device: wrap acc_key under the presented offer.
    static func makeGrant(offer: LinkOffer, accKey: Data) -> LinkGrant? {
        let peerPub = e2b64d(offer.epk)
        guard offer.v == 1, peerPub.count == 1184,
              let nonce = Data(base64Encoded: offer.nonce), !nonce.isEmpty else { return nil }
        var ct = [UInt8](repeating: 0, count: 1088); var ss = [UInt8](repeating: 0, count: 32)
        let rc = peerPub.withUnsafeBytes { pk -> Int32 in mt_mlkem_encaps(pk.bindMemory(to: UInt8.self).baseAddress, &ct, &ss) }
        guard rc == 0 else { return nil }
        let wrapKey = SymmetricKey(data: e2HKDF(Data(ss) + nonce, MontanaDomain.link))
        guard let sealed = try? ChaChaPoly.seal(accKey, using: wrapKey) else { return nil }
        return LinkGrant(t: "lnk", kct: e2b64e(Data(ct)), ct: e2b64e(sealed.combined))
    }
    // New device: unwrap acc_key from the grant with its ephemeral private key.
}

// device_key — the ONLY encryption key for the local DB (SSOT, spec Stage 2).
// 32 B CSPRNG, device-local (AfterFirstUnlockThisDeviceOnly), not synchronized, not in backups.
// It never leaves the device. Erased when the device forgets the person.
enum MontanaDeviceKey {
    private static let K = "mt_device_key"
    private static var cached: SymmetricKey?

    // A key is returned only when it was actually drawn. The former path discarded the
    // status of the draw, so a failing source produced thirty-two zero bytes, the vault
    // was sealed under them, and nothing anywhere said so.
    static var key: SymmetricKey? {
        if let c = cached { return c }
        let read = E2EKeychain.getDeviceOnlyStatus(K)
        if let d = read.data, d.count == 32 {
            let k = SymmetricKey(data: d); cached = k; return k
        }
        // A new key may be drawn ONLY when the keychain authoritatively said "no such item".
        // Any other answer (busy, interaction not allowed, an unlock race) means wait:
        // the store is closed for an instant, not empty. The former path drew a new key over a live
        // one, and the whole pipe book turned to garbage from one cold start off a tap.
        guard read.status == errSecItemNotFound else {
            NSLog("[DeviceKey] keychain busy (status=\(read.status)) — the vault waits, no redraw")
            return nil
        }
        // The key that seals the whole vault lives as long as the device does — so it is drawn by
        // the core, which folds six sources and refuses when fewer than three are alive.
        var d = Data(count: 32)
        let status = d.withUnsafeMutableBytes { p -> Int32 in
            guard let base = p.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_random_fast(base, 32)
        }
        guard status == 0, isHealthy(d) else {
            NSLog("[DeviceKey] draw refused: status=\(status) — the vault stays sealed shut")
            return nil
        }
        E2EKeychain.setDeviceOnly(K, d)   // AfterFirstUnlockThisDeviceOnly — readable with the screen locked
        guard let back = E2EKeychain.getDeviceOnly(K), back == d else {
            NSLog("[DeviceKey] keychain did not read the key back — refusing to use it")
            return nil
        }
        let k = SymmetricKey(data: d); cached = k; return k
    }

    // The same four tests the core applies to the root of an identity: a block that repeats
    // itself, leans on a few values or carries too little variety is a broken source, not a key.
    private static func isHealthy(_ d: Data) -> Bool {
        guard d.count == 32 else { return false }
        let bytes = [UInt8](d)
        var run = 1, maxRun = 1
        for i in 1..<bytes.count {
            run = bytes[i] == bytes[i - 1] ? run + 1 : 1
            maxRun = max(maxRun, run)
        }
        var counts = [Int](repeating: 0, count: 256)
        for b in bytes { counts[Int(b)] += 1 }
        let distinct = counts.filter { $0 > 0 }.count
        return maxRun < 8 && (counts.max() ?? 0) <= 12 && distinct >= 8
    }

    static func reset() { cached = nil; E2EKeychain.delete(K) }
}

// The ONLY local encryption mechanism (SSOT): ChaCha20-Poly1305 under device_key.
// The entire local database (history, chat metadata) goes through seal/open — not piecemeal.
enum MontanaLocalVault {
    static func seal(_ plain: Data, _ aad: Data) -> Data? {
        guard let key = MontanaDeviceKey.key else { return nil }
        return try? ChaChaPoly.seal(plain, using: key, authenticating: aad).combined
    }
    static func open(_ sealed: Data, _ aad: Data) -> Data? {
        guard let key = MontanaDeviceKey.key,
              let box = try? ChaChaPoly.SealedBox(combined: sealed) else { return nil }
        return try? ChaChaPoly.open(box, using: key, authenticating: aad)
    }
    // Wrappers over UserDefaults: cipher with AAD = key name (SC-04: a blob can't be swapped between keys);
    // read with one-time migration (legacy without AAD -> reseal; legacy plaintext -> return as is).
    // A write that cannot be sealed is reported, not swallowed: without the device key the
    // data never reaches storage, and a caller that believes otherwise loses it silently.
    @discardableResult
    static func setEncrypted(_ key: String, _ plain: Data) -> Bool {
        guard let sealed = seal(plain, Data(key.utf8)) else {
            NSLog("[Vault] write refused for \(key): no device key — nothing was stored")
            return false
        }
        UserDefaults.standard.set(sealed, forKey: key)
        return true
    }
    /// THE DEFAULTS ON THE DISK, NOW (26.09). The platform's own words (UserDefaults): a written value is updated in memory
    /// «right away» and written «to disk asynchronously»; synchronize() «waits for any pending asynchronous updates to the
    /// defaults database» -- the one road to know that a value just written will outlive this process. It is asked before
    /// a promise leaves the device that my screen holds a person's word (the receipt of their name, face, bio or ground).
    /// 25.09 on T1: a correspondent's face was stored 2.6 s before the system ended the app, its receipt left, the map that
    /// named the face never reached the disk, and the sender, holding the receipt, never sent it again -- for a day the face
    /// stood missing on T1 while the file lay on its disk.
    @discardableResult
    static func commit() -> Bool { UserDefaults.standard.synchronize() }

    static func getDecrypted(_ key: String) -> Data? {
        guard let raw = UserDefaults.standard.data(forKey: key) else { return nil }
        if let opened = open(raw, Data(key.utf8)) { return opened }
        if let legacy = open(raw, Data()) { setEncrypted(key, legacy); return legacy }   // migration of blobs without AAD
        // It looks like a sealed block but does not open with OUR key -- this is foreign ciphertext
        // (the key changed or is unavailable), NOT a plaintext legacy. Re-sealing it as "legacy"
        // means destroying data forever; the honest answer is "I cannot read it".
        if (try? ChaChaPoly.SealedBox(combined: raw)) != nil {
            MontanaTrace.mark("vault_foreign_seal", "key=\(key) bytes=\(raw.count)")
            return nil
        }
        // A plaintext legacy: a value written by earlier builds lay here as is and was read as if
        // nothing were wrong -- that is, "everything is encrypted" was a statement about new writes,
        // not about the contents. It is sealed RIGHT NOW, on the very first read, and a refusal to
        // seal is named aloud: silence here would leave the value open forever.
        if setEncrypted(key, raw) {
            MontanaTrace.mark("vault_resealed", "key=\(key) bytes=\(raw.count)")
        } else {
            MontanaTrace.mark("vault_reseal_failed", "key=\(key)")
        }
        return raw
    }
    // String: write encrypted; read with one-time migration of legacy String (@AppStorage stored plaintext).
    @discardableResult
    static func setString(_ key: String, _ s: String) -> Bool { setEncrypted(key, Data(s.utf8)) }
    static func getString(_ key: String) -> String? {
        if let d = getDecrypted(key), let s = String(data: d, encoding: .utf8) { return s }
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            setString(key, legacy); return legacy   // migration: rewrite encrypted
        }
        return nil
    }
    // String array (chat names/social graph): JSON under device_key; migration of legacy stringArray.
    static func setStringArray(_ key: String, _ a: [String]) {
        if let d = try? JSONEncoder().encode(a) { setEncrypted(key, d) }
    }
    static func getStringArray(_ key: String) -> [String]? {
        if let d = getDecrypted(key), let a = try? JSONDecoder().decode([String].self, from: d) { return a }
        if let legacy = UserDefaults.standard.stringArray(forKey: key) {
            setStringArray(key, legacy); return legacy
        }
        return nil
    }
}

// Domain separators — SSOT for the Swift layer (mirror of the core mt-codec::domain registry).
// One literal per domain: signing and verification reference a single constant, silent drift is impossible.
enum MontanaDomain {
    static let link = "montana-link"   // history key wrapping on device linking
}

enum E2EKeychain {
    private static func fileURL(_ key: String) -> URL {
        var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MontanaE2E", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? dir.setResourceValues(rv)   // SC-01: file fallback outside iCloud/iTunes backup
        return dir.appendingPathComponent(key)
    }
    // Update-first, like setDeviceOnly: the former Delete→Add left a window in which the old
    // entry was gone and the new one never arrived, and the caller was told nothing.
    /// The keychain on a Mac is a DIFFERENT keychain unless asked otherwise: macOS keeps the old
    /// file-based one, which knows no accessibility classes, and the same one as on the phone. By
    /// default the request goes to the old one, the "after first unlock" class is unknown to it, and
    /// the write is refused -- silently. One line asks for the same keychain everywhere.
    private static func q(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
         kSecUseDataProtectionKeychain as String: true]
    }

    @discardableResult
    static func set(_ key: String, _ data: Data) -> Bool {
        let q: [String: Any] = Self.q(key)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var st = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            var add = q; add.merge(attrs) { _, new in new }
            st = SecItemAdd(add as CFDictionary, nil)
        }
        if st != errSecSuccess { NSLog("[Keychain] set(\(key)) FAIL status=\(st)") }
        let fileOK = (try? data.write(to: fileURL(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
        return st == errSecSuccess || fileOK
    }
    // The keychain read lives in getDeviceOnly; this adds the file fallback for values that also
    // have one. Two readers of the same store would drift the moment one of them is corrected.
    static func get(_ key: String) -> Data? {
        getDeviceOnly(key) ?? (try? Data(contentsOf: fileURL(key)))
    }
    // Seed — device-only (not in backups/iCloud), access AFTER FIRST UNLOCK.
    // WhenUnlocked broke calls: CallKit runs with the screen off, the seed became unreadable, and
    // every action that carries its own proof died before it reached the wire — there is no session
    // to fall back on, so an unreadable seed is a dead phone (incident 22:54 UTC).
    // AfterFirstUnlock — the industry standard for messengers with calls (Signal identity likewise).
    @discardableResult
    static func setDeviceOnly(_ key: String, _ data: Data) -> OSStatus {
        // Atomic: Update, if absent — Add. The former Delete→Add ignoring OSStatus had
        // a window «record erased, new one not written» and silently lost the token when storage was unavailable.
        let q: [String: Any] = Self.q(key)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var st = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            var add = q; add.merge(attrs) { _, new in new }
            st = SecItemAdd(add as CFDictionary, nil)
        } else if st != errSecSuccess {
            SecItemDelete(q as CFDictionary)   // protection class change: recreate
            var add = q; add.merge(attrs) { _, new in new }
            st = SecItemAdd(add as CFDictionary, nil)
        }
        if st != errSecSuccess { NSLog("[Keychain] setDeviceOnly(\(key)) FAIL status=\(st)") }
        return st
    }

    // Migration of existing records to the new attribute (rewrite by re-reading). Works
    // only when storage is available — called on startup and on device unlock.
    static func migrateDeviceOnlyAccessibility() {
        for key in ["mt_active_mnemonic", "mt_active_entropy"] {
            if let d = getDeviceOnly(key) { setDeviceOnly(key, d) }
        }
    }
    static func getDeviceOnly(_ key: String) -> Data? {
        getDeviceOnlyStatus(key).data
    }
    /// "No such item" and "the keychain does not answer right now" are DIFFERENT answers. Confusing
    /// them cost the whole store: an instant of a busy keychain on a cold start read as "there is no
    /// key", and a new one was drawn over a live key -- every previous seal turned to garbage (22:51).
    static func getDeviceOnlyStatus(_ key: String) -> (data: Data?, status: OSStatus) {
        var q: [String: Any] = Self.q(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecSuccess, let d = out as? Data { return (d, st) }
        return (nil, st)
    }
    static func delete(_ key: String) {
        SecItemDelete(Self.q(key) as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL(key))   // SC-02: remove the file fallback
    }
    /// The name an older build stored under on this device, found by its print (MTRetired.print): read once to move what it
    /// holds, never named here.
    static func storedName(_ printed: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true,
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return nil }
        return items.lazy.compactMap { $0[kSecAttrAccount as String] as? String }.first { MTRetired.print($0) == printed }
    }
    static func deleteSynced(_ key: String) {
        var q = Self.q(key)
        q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(q as CFDictionary)
    }
}


/// Whether THIS device can keep an identity -- a question answered before the person presses
/// "create", not after the seed is lost.
///
/// A store failure looks the same on every platform -- like silence: a write "goes through", a read
/// returns empty, and the app learns of it the only way, by losing the seed. One probe at launch
/// reverses the order: it writes its own record, reads it back, removes it -- and names the failure
/// by name and code at a moment when there is still nothing to lose. What proves is the read-back.
enum E2EStore {
    @discardableResult
    static func witness() -> Bool {
        let key = "mt_store_witness"
        let probe = Data("mt".utf8)
        let st = E2EKeychain.setDeviceOnly(key, probe)
        let back = E2EKeychain.getDeviceOnly(key) == probe
        E2EKeychain.delete(key)
        MontanaTrace.mark("audit_store", "st=\(st) back=\(back ? 1 : 0)")
        if !back { NSLog("[Store] this device refuses to keep an identity: status=\(st)") }
        return back
    }
}
/// Whether this is the first launch of THIS installation.
///
/// The keychain outlives the app: iOS keeps its items when an app is deleted, so a person who
/// deletes Montana — meaning to be forgotten by it — is met on reinstall by an identity they never
/// created, already active, with a seed they never saw. UserDefaults dies with the app, so its
/// silence is the one honest sign of a fresh install, and it is read once, before any screen.
enum MontanaInstall {
    private static let K = "mt.install.marker"
    static func forgetLeftoverSeed(_ wipe: () -> Void) {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: K) else { return }
        MTSeats.forgetRecords()   // the persons on the shelf of the previous installation leave with it, first (the second identity checklist, stage 7)
        if MontanaSeed.hasSeed {
            NSLog("[install] fresh install over a leftover keychain — the previous identity is forgotten")
            wipe()
        }
        ud.set(true, forKey: K)
    }
}

// SINGLE SOURCE OF TRUTH of the active identity.
// The seed of the ACTIVE identity is stored ONLY here:
//  - Keychain device-local (AfterFirstUnlockThisDeviceOnly): iOS hardware-backed encryption,
//    NOT synchronized to iCloud (a second phone with the same Apple ID doesn't overwrite it), NOT in backups.
// setActive erases ALL other/stale seed stores -> the active seed is the only one.
// Everything in the app (account_id, keys, signature) is derived FROM HERE.
enum MontanaSeed {
    private static let MN = "mt_active_mnemonic"
    private static let EN = "mt_active_entropy"   // legacy store, erased on sight
    // The root is kept in ONE representation: the words a person wrote down. The entropy is
    // the same secret in another shape, and a second copy only doubles what has to be erased —
    // it is derived from the words by the core whenever it is needed.
    // Returns whether the seed is actually in storage, read back after the write. A person
    // who is told "your identity exists" and whose seed never reached the keychain loses
    // it on the next launch, and nothing before that moment says a word.
    @discardableResult
    static func setActive(mnemonic: String, entropy: Data? = nil) -> Bool {
        E2EKeychain.setDeviceOnly(MN, Data(mnemonic.utf8))   // AfterFirstUnlockThisDeviceOnly (calls with the screen off)
        E2EKeychain.delete(EN)
        E2EKeychain.deleteSynced(EN)
        purgeOthers()
        let stored = E2EKeychain.getDeviceOnly(MN).flatMap { String(data: $0, encoding: .utf8) } == mnemonic
        writeAudit(words: mnemonic.split(separator: " ").count)
        if !stored { NSLog("[SEED-AUDIT] seed did NOT reach the keychain — the account must not be presented as created") }
        return stored
    }
    // Seed write diagnostics — WHERE and HOW (without the value itself). os_log + a file in the «Montana» folder (Files).
    private static func writeAudit(words: Int) {
        let mnBack = E2EKeychain.getDeviceOnly(MN) != nil
        let enBack = E2EKeychain.getDeviceOnly(EN) != nil   // must read back as false: the legacy copy is gone
        let dkBack = MontanaDeviceKey.key != nil
        let line = "MontanaSeed WRITE -> Keychain (device-local): "
            + "key=\(MN) [mnemonic, \(words) words]; legacy key=\(EN) erased; "
            + "accessible=AfterFirstUnlockThisDeviceOnly; synchronizable=NO (not iCloud); backupExcluded=YES; file=NO; UserDefaults=NO; "
            + "readback: mnemonic=\(mnBack), entropy=\(enBack), device_key(mt_device_key)=\(dkBack ? "present" : "missing"). "
            + "The seed stays on this device. SEED VALUE IS NOT LOGGED."   // NOT-UI: the system log's own line
        NSLog("[SEED-AUDIT] \(line)")   // system log only; we don't write seed-write-audit.txt to the folder
    }
    static var mnemonic: String? {
        guard let d = E2EKeychain.getDeviceOnly(MN), let m = String(data: d, encoding: .utf8), !m.isEmpty else { return nil }
        return m
    }
    // Derived from the words through the core, never stored: one root, one representation.
    static var entropy: Data? {
        guard let m = mnemonic else { return nil }
        return MontanaSeedKeys.entropyFrom(mnemonic: m)
    }
    static var hasSeed: Bool { mnemonic != nil }
    // Erase all other seed stores (including iCloud-synchronized ones) -> the active seed is the only one.
    static func purgeOthers() {
        for k in ["mt_seed_mnemonic", "mt_seed_entropy"] { E2EKeychain.deleteSynced(k) }
        for k in ["mt_seed_mnemonic", "mt_seed_entropy", "royalMnemonic", "royalSeckey"] { E2EKeychain.delete(k) }
    }
    static func clear() {
        E2EKeychain.delete(MN); E2EKeychain.delete(EN); E2EKeychain.deleteSynced(EN)
        purgeOthers()
    }
}


extension Data {
    /// The writing side of the pair below: one place holds both, so a value written here is read
    /// there and a change to either cannot pass unnoticed.
    var base64urlNoPad: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64urlNoPad s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}


// history_key = HKDF-SHA-256(0×32, entropy_32, "mt-history-key", 32) — from the SEED (spec Stage 10).
// Any device with the same seed derives the same key; it is derived on use, not stored separately.
enum MontanaVault {
    static func historyKey(seed: Data) -> Data {
        // SSOT: history_key is derived by the mt-bindings core (mt_history_key), not reimplemented in Swift.
        guard seed.count == 32 else { return Data() }
        var out = [UInt8](repeating: 0, count: 32)
        let rc = seed.withUnsafeBytes { ep -> Int32 in
            mt_history_key(ep.bindMemory(to: UInt8.self).baseAddress, &out)
        }
        return rc == 0 ? Data(out) : Data()
    }
    // Spec binding vector (history_key_kat): entropy = 55×32 -> history_key.
    static func historyKeyKAT() -> Bool {
        historyKey(seed: Data(repeating: 0x55, count: 32)).map { String(format: "%02x", $0) }.joined()
            == "e6a7dc51003770589d9f731c1231c1523be7348c7769383875dd34bd6c578def"
    }
}
