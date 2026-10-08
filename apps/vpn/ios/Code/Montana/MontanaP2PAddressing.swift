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
    private static let seedLock = NSLock()
    private static var seedCache: (key: Data, seed: Data)?

    static func masterSeed(_ mnemonic: String) -> Data? {
        let key = sha256(Data(mnemonic.utf8))
        seedLock.lock()
        if let c = seedCache, c.key == key { seedLock.unlock(); return c.seed }
        seedLock.unlock()
        var out = [UInt8](repeating: 0, count: 64)
        let rc = mnemonic.withCString { mt_mnemonic_to_master_seed($0, &out) }
        guard rc == 0 else { return nil }
        let seed = Data(out)
        seedLock.lock(); seedCache = (key, seed); seedLock.unlock()
        return seed
    }

    /// The seed left the device -- so does the root derived from it.
    static func forgetMasterSeed() {
        seedLock.lock(); seedCache = nil; keysCache = nil; seedLock.unlock()
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
    static var recvId: Data { persistId("mt_p2p_recv_id") }
    static var sendId: Data { persistId("mt_p2p_send_id") }
    private static func persistId(_ key: String) -> Data {
        if let d = E2EKeychain.getDeviceOnly(key), d.count == 32 { return d }
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
