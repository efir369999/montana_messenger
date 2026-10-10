import Foundation
import Security

// THE APPLE ACCOUNT CARRIES NO SEED (the author's word 10.10.2026 16:2x MSK: «the button ... restore by the Apple account --
// eradicate it wholly, everywhere»; his choice of 08.10 20:3x: «remove it completely», the records already lying in iCloud are
// not touched). Nothing here writes, reads or offers a seed through the account: an identity opens by its 24 words alone. The
// one act left is the person's own word: «Delete account» takes this installation's record, written by a build before, out of
// the iCloud Keychain with the seed, so a secret of the person does not stay behind a door that closed.
enum MontanaAppleID {
    static let recordKey = "mt.apple.signin.id"            // NOT-UI: the name of this installation's record, this device's own
    private static let service = "montana.apple-account"   // NOT-UI: the records' service name
    private static let recordPrefix = "mt_apple_id_seed."  // NOT-UI: a record per installation, under this prefix

    /// «Delete account»: this installation's record, when a build before wrote one, leaves with the seed. A twin's record of
    /// the same words is the twin's, and stands.
    static func withdrawOwn() {
        guard let s = UserDefaults.standard.string(forKey: recordKey), !s.isEmpty else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: recordPrefix + s,
                                kSecAttrSynchronizable as String: true,
                                kSecUseDataProtectionKeychain as String: true]
        let st = SecItemDelete(q as CFDictionary)
        MontanaTrace.mark("apple_id", "own record withdrawn st=" + String(st))
    }
}
