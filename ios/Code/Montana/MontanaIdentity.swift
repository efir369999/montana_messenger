import Foundation
import MontanaBindings


// A Montana seed: the words, and the keys they open. Nothing else.
// There is no address in this protocol and no identifier of a person ([I-17].2, [I-17].3): a
// person is not named by a public string, and what a correspondent holds is the secret of the
// correspondence between the two of them.
// All crypto — via mt-bindings (the single protocol code), not reimplemented in Swift.
extension Data {
    init?(montanaHex hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8](); bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(b); i += 2
        }
        self.init(bytes)
    }
    var montanaHexString: String { map { String(format: "%02x", $0) }.joined() }
}

enum MontanaSeedKeys {
    /// What a seed opens. Keys, and nothing that names their holder: the set publishes no
    /// identifier of a person, so there is none here to carry one.
    struct Keys {
        let mnemonic: String      // 24 words
        let pubkey: Data          // ML-DSA-65, 1952
        let seckey: Data          // ML-DSA-65, 4032
    }

    static func entropyFrom(mnemonic m: String) -> Data? {
        var out = [UInt8](repeating: 0, count: 32)
        let rc = m.withCString { mt_mnemonic_to_entropy($0, &out) }
        return rc == 0 ? Data(out) : nil
    }

    static func keys(from m: String) -> Keys? {
        var pk = [UInt8](repeating: 0, count: 1952)
        var sk = [UInt8](repeating: 0, count: 4032)
        let rc = m.withCString { mt_seed_keys($0, &pk, &sk) }
        guard rc == 0 else { return nil }
        return Keys(mnemonic: m, pubkey: Data(pk), seckey: Data(sk))
    }

    // The root is drawn by the core, never by the app: the source and its health tests are
    // fixed by the protocol, so the quality of an identity does not depend on which
    // implementation a person happens to be holding.
    static func generate() -> Keys? {
        var out = [UInt8](repeating: 0, count: 1024)
        var outLen = 0
        let rc = mt_generate_mnemonic(&out, out.count, &outLen)
        guard rc == 0, outLen > 0,
              let m = String(bytes: out[0..<outLen], encoding: .utf8) else { return nil }
        return keys(from: m)
    }

    static func sign(_ message: Data, seckey: Data) -> Data? {
        guard seckey.count == 4032 else { return nil }
        var sig = [UInt8](repeating: 0, count: 3309)
        let rc = seckey.withUnsafeBytes { skp in
            message.withUnsafeBytes { mp in
                mt_sign(skp.bindMemory(to: UInt8.self).baseAddress,
                        mp.bindMemory(to: UInt8.self).baseAddress, message.count, &sig)
            }
        }
        return rc == 0 ? Data(sig) : nil
    }
}
