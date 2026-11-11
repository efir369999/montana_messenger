import Foundation
import MontanaBindings
import CryptoKit

enum MontanaQueueKeys {

    /// Hex to bytes: the reading side of the pair below, kept beside it so the two cannot drift.
    static func hexToData(_ hex: String) -> Data {
        var d = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) {
            if let b = UInt8(hex[idx..<next], radix: 16) { d.append(b) } else { break }
            idx = next
        }
        return d
    }
    static func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }

    // MARK: queue key derivation

    // Memory of the root derivation, for one launch. The derivation costs 2^20 stretching iterations --
    // 7.5 s measured on the author's machine -- and it costs them ON PURPOSE: stretching exists to slow
    // down whoever walks through phrases. There is nothing to pay that price twice for: the answer is
    // the same, while ten places call it on each of their actions, and one of them called it on the
    // main thread every time the app came to the screen -- the app froze on exactly that.
    //
    // Keeping the root beside us is no more dangerous than keeping the phrase it is derived from: it is
    // one secret, and it makes no second copy. It leaves by the same boundary as everything else.
    //
    // THE ROOT IS STRETCHED ONCE ON THE DEVICE, IN ONE PLACE (the author's decision 494 = (b) and words 01.11.2026 15:35 UTC,
    // links 14169-14170: «if they have none, option b suits us better»; «work by the SSOT principle and ask the key's root in one
    // place, not 18»): the measure of 2330 on T1 (links 14164, 14172) -- every cold opening held the main thread 1943-2064 ms
    // here, because the warm-up and the main thread stretched the same words side by side. Now the stretch is serialized (one
    // in flight; a second asker waits for its answer and never stretches again), and the seated person's root is kept by its
    // one owner (MontanaSeed.root) in the keychain beside the words, so a cold opening reads it instead of stretching.
    // A password is stretched only when it is typed, never on every opening.
    private static let seedLock = NSLock()
    private static let stretchLock = NSLock()
    private static var seedCache: (key: Data, seed: Data)?

    static func masterSeed(_ mnemonic: String) -> Data? {
        let key = sha256(Data(mnemonic.utf8))
        if let s = cached(key) { return s }
        if let s = MontanaSeed.keptRoot(key) { remember(key, s); return s }
        // Written before the lock: a wait on main for another's stretch is the same breach as stretching there.
        if Thread.isMainThread { MontanaLog.event("MAIN COLD what=master-seed") }   // NOT-UI: the diary's line -- the law's breach, seen
        stretchLock.lock(); defer { stretchLock.unlock() }
        if let s = cached(key) { return s }
        var out = [UInt8](repeating: 0, count: 64)
        let rc = mnemonic.withCString { mt_mnemonic_to_master_seed($0, &out) }
        guard rc == 0 else { return nil }
        let seed = Data(out)
        remember(key, seed)
        MontanaSeed.keepRoot(key, seed)
        return seed
    }
    private static func cached(_ key: Data) -> Data? {
        seedLock.lock(); defer { seedLock.unlock() }
        if let c = seedCache, c.key == key { return c.seed }
        return nil
    }
    private static func remember(_ key: Data, _ seed: Data) {
        seedLock.lock(); seedCache = (key, seed); seedLock.unlock()
    }

    /// The seed left the device -- so does the root derived from it, in memory and in the keychain.
    static func forgetMasterSeed() {
        seedLock.lock(); seedCache = nil; keysCache = nil; seedLock.unlock()
        MontanaSeed.forgetRoot()
    }
    static func routingSecret(_ mnemonic: String) -> Data? {
        guard let master = masterSeed(mnemonic) else { return nil }
        let role = Array("mt-routing-secret".utf8)
        let m = [UInt8](master)
        var out = [UInt8](repeating: 0, count: 32)
        let rc = m.withUnsafeBufferPointer { mp in
            role.withUnsafeBufferPointer { rp in
                mt_mldsa_seed_for_role(mp.baseAddress, rp.baseAddress, role.count, &out)
            }
        }
        return rc == 0 ? Data(out) : nil
    }
    /// author_key = HKDF-Expand(master_seed, "mt-letter-author", 32): the person's key for the author field of a letter
    /// (MTNodeWire.authorTag), the same on every device of the words and on none other.
    static func authorKey(_ mnemonic: String) -> Data? {
        guard let master = masterSeed(mnemonic) else { return nil }
        let role = Array("mt-letter-author".utf8)
        let m = [UInt8](master)
        var out = [UInt8](repeating: 0, count: 32)
        let rc = m.withUnsafeBufferPointer { mp in
            role.withUnsafeBufferPointer { rp in
                mt_mldsa_seed_for_role(mp.baseAddress, rp.baseAddress, role.count, &out)
            }
        }
        return rc == 0 ? Data(out) : nil
    }
    // The queue keys keep the same memory as the root (19.09): their derivation walks the same
    // 2^20 stretching, and it stood 3 s on the main thread of a tester's phone (1647,
    // mt_muq_derive_queue_keys → pbkdf2). Same answer for the same phrase — paid once per launch.
    private static var keysCache: (key: Data, keys: (recvPk: Data, recvSk: Data, sendPk: Data, sendSk: Data))?
    static func queueKeys(_ mnemonic: String) -> (recvPk: Data, recvSk: Data, sendPk: Data, sendSk: Data)? {
        let key = sha256(Data(mnemonic.utf8))
        seedLock.lock()
        if let c = keysCache, c.key == key { seedLock.unlock(); return c.keys }
        seedLock.unlock()
        guard let rs = routingSecret(mnemonic) else { return nil }
        let r = [UInt8](rs)
        var rpk = [UInt8](repeating: 0, count: 1952), rsk = [UInt8](repeating: 0, count: 4032)
        var spk = [UInt8](repeating: 0, count: 1952), ssk = [UInt8](repeating: 0, count: 4032)
        let rc = r.withUnsafeBufferPointer { rp in
            mt_muq_derive_queue_keys(rp.baseAddress, 0, &rpk, &rsk, &spk, &ssk)
        }
        guard rc == 0 else { return nil }
        let keys = (Data(rpk), Data(rsk), Data(spk), Data(ssk))
        seedLock.lock(); keysCache = (key, keys); seedLock.unlock()
        return keys
    }

    // MARK: recv_id/send_id — random, persisted in the Keychain (queue endpoints)
    static var recvId: Data { persistId("mt_queue_recv_id", older: "9ef24a85f3294136") }
    static var sendId: Data { persistId("mt_queue_send_id", older: "09fb0c6a092da2cd") }
    private static func persistId(_ key: String, older: String) -> Data {
        if let d = E2EKeychain.getDeviceOnly(key), d.count == 32 { return d }
        // THE QUEUE'S IDS UNDER THEIR OWN NAMES (08.10.2026): an upgraded phone holds them under older names, found by their prints
        // (E2EKeychain.storedName). An id moves once and the older entry leaves only once the new one reads back; a new id is drawn
        // only when neither stood.
        if let old = E2EKeychain.storedName(older), let d = E2EKeychain.getDeviceOnly(old), d.count == 32 {
            if E2EKeychain.setDeviceOnly(key, d) == errSecSuccess, E2EKeychain.getDeviceOnly(key) == d { E2EKeychain.delete(old) }
            return d
        }
        var out = [UInt8](repeating: 0, count: 32)
        _ = mt_muq_gen_queue_id(&out)
        let d = Data(out)
        E2EKeychain.setDeviceOnly(key, d)
        return d
    }

    // MARK: queue serialization for register (secured: send_pk)
    static func queueWire(_ mnemonic: String) -> Data? {
        guard let keys = queueKeys(mnemonic) else { return nil }
        let rid = [UInt8](recvId), sid = [UInt8](sendId)
        let rpk = [UInt8](keys.recvPk)
        var out = [UInt8](repeating: 0, count: 4096)
        // Unsecured (send_pk=null): a LAN neighbor deposits without send_sk (serverless automatic mode).
        let n = rid.withUnsafeBufferPointer { ridP in sid.withUnsafeBufferPointer { sidP in
            rpk.withUnsafeBufferPointer { rpkP in
                mt_muq_queue_serialize(ridP.baseAddress, sidP.baseAddress, rpkP.baseAddress, nil, 1, 64, &out, out.count)
            }}}
        return n > 0 ? Data(out[0..<Int(n)]) : nil
    }
}

/// THE PERSON'S AUTHOR KEY ON THIS PHONE (MTNodeWire.authorTag, 11.10.2026): derived from the words once, off the main thread --
/// the root costs 2^20 stretching the first time in a launch -- held in memory for the person seated and mirrored for the
/// extensions (wakeMyAuthor, parked and lifted with the seat). Asked before it stands, it answers with the mirror and starts the
/// derivation; a letter born in that instant rides unsigned, as every letter of an older build does.
enum MTLetterAuthor {
    private static let lock = NSLock()
    private static var held: (words: Data, key: Data)?
    private static var deriving = false
    static var key: Data? {
        guard let m = MontanaSeed.mnemonic else { return nil }
        let words = MontanaQueueKeys.sha256(Data(m.utf8))
        let have: Data? = lock.withLock { held.flatMap { h in h.words == words ? h.key : nil } }
        if let have { return have }
        warm(m, words)
        return MTNodeWire.mirroredAuthorKey()
    }
    private static func warm(_ m: String, _ words: Data) {
        let go: Bool = lock.withLock {
            if deriving { return false }
            deriving = true
            return true
        }
        guard go else { return }
        DispatchQueue.global(qos: .utility).async {
            let k = MontanaQueueKeys.authorKey(m)
            lock.withLock {
                deriving = false
                if let k { held = (words, k) }
            }
            if let k { MontanaKeychain.set("wakeMyAuthor", k) }
            MontanaTrace.mark("letter_author", "key=" + (k == nil ? "0" : "1"))
        }
    }
    /// Whether a letter in this conversation was written by this person -- on this device or another of the same words.
    static func mine(_ tag: String, conv: String, mid: String, text: String) -> Bool {
        guard !tag.isEmpty, let pipe = MTPipeBook.key(for: conv) else { return false }
        return pipe.authorHolds(tag, person: key, mid: mid, text: text)
    }
}
