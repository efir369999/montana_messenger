import Foundation
import Security

// THE SEED OF THE APPLE ACCOUNT (the author's word 28.09: «sign in by the Apple ID, on every Apple device of the
// account»). The platform already carries one secret of a person to every device signed in with their Apple
// Account and to no other place: the iCloud Keychain, the store of their passwords and passkeys, sealed end to
// end under keys of the devices themselves (Apple Platform Security Guide, «iCloud Keychain security overview»:
// the syncing circle of device keys, and an escrow record opened only by the device passcode with ten tries at
// the HSM). The words ride there, and a new device of the same account finds them before a person has typed a
// word: «Continue with your Apple Account» on the page «Open identity» opens the seed (the first page of the Montana
// road gave it away by the author's word 29.09), and the copy the account holds in iCloud comes back after it.
//
// What stays as it was: the ACTIVE seed of this device lives device-only, as ever (E2ECore.swift), and nothing
// here writes over it. The account's records are a second reading of the same words, published by the person's
// switch (standing by default) and withdrawn by it.
//
// ONE RECORD PER INSTALLATION (the critic, 28.09). The first cut kept ONE item for the whole account, and the last
// device to launch wrote its seed over it: two phones of one account under two seeds took turns being «the
// identity», and a device that forgot its seed left that seed standing in the account -- the first screen of the
// same phone then offered to open the very identity it had just forgotten. Now every installation writes a record
// of its own, named by a random name drawn once on this device (mt.apple.signin.id, this device's own and never in
// a copy); the page of opening reads every record and offers each distinct seed; «Forget this device» withdraws this
// device's record alone, so a twin's record of the same words stands; the switch off withdraws every record of
// this app. The one record of the builds before is read as one more record and leaves once this device has
// written its own with the same words. No record is ever written over by another device.
enum MontanaAppleID {
    static let switchKey = "mt.apple.signin"               // NOT-UI: the person's switch, carried by a copy
    static let recordKey = "mt.apple.signin.id"            // NOT-UI: the name of this installation's record, this device's own
    private static let service = "montana.apple-account"   // NOT-UI: the records' service name
    private static let legacyRecord = "mt_apple_id_seed"   // NOT-UI: the one record of the builds before, one per account
    private static let recordPrefix = "mt_apple_id_seed."  // NOT-UI: a record per installation, under this prefix

    /// One seed the account carries: the words, the moment a record of them was last written, how many installations
    /// wrote them, and whether one of those installations is this one.
    struct Carried: Equatable {
        let words: String
        let at: Date
        let devices: Int
        let mine: Bool
    }

    static var on: Bool {
        let ud = UserDefaults.standard
        return ud.object(forKey: switchKey) == nil ? true : ud.bool(forKey: switchKey)
    }
    static func set(on v: Bool) {
        UserDefaults.standard.set(v, forKey: switchKey)
        if v { publish() } else { withdrawAll() }
    }

    /// The name of this installation's record: drawn once per person on this phone (SeedScope.seatKeys: a second person
    /// seated here draws a record of their own and never writes over the first), never in a copy, so a
    /// reinstall writes a new record and never another installation's.
    private static var ownRecord: String {
        let ud = UserDefaults.standard
        if let s = ud.string(forKey: recordKey), !s.isEmpty { return recordPrefix + s }
        let s = UUID().uuidString.lowercased()
        ud.set(s, forKey: recordKey)
        return recordPrefix + s
    }
    /// The name of this installation's record when one was drawn, else nil -- a reading, never a draw.
    private static var ownRecordIfDrawn: String? {
        guard let s = UserDefaults.standard.string(forKey: recordKey), !s.isEmpty else { return nil }
        return recordPrefix + s
    }

    /// The one query shape: synchronizable generic passwords of this app's service in the data-protection keychain.
    /// A synchronizable item cannot wear a this-device-only class, so it wears after-first-unlock, as the calls need
    /// (E2ECore.swift). With a record name it is one record; without, every record of the service.
    private static func query(_ record: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrSynchronizable as String: true,
                                kSecUseDataProtectionKeychain as String: true]
        if let record { q[kSecAttrAccount as String] = record }
        return q
    }

    /// Every record of this app the account carries, as the keychain holds them right now.
    private static func records() -> [(name: String, words: String, at: Date)] {
        var q = query(nil)
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: AnyObject?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        guard st == errSecSuccess, let rows = out as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let name = r[kSecAttrAccount as String] as? String,
                  let d = r[kSecValueData as String] as? Data,
                  let m = String(data: d, encoding: .utf8), !m.isEmpty else { return nil }
            return (name, m, (r[kSecAttrModificationDate as String] as? Date) ?? .distantPast)
        }
    }

    /// The seeds the account carries, each once: this installation's own first, then the newest written first.
    static func held() -> [Carried] {
        let own = ownRecordIfDrawn
        var by: [String: Carried] = [:]
        for r in records() {
            if let c = by[r.words] {
                by[r.words] = Carried(words: r.words, at: max(c.at, r.at), devices: c.devices + 1, mine: c.mine || r.name == own)
            } else {
                by[r.words] = Carried(words: r.words, at: r.at, devices: 1, mine: r.name == own)
            }
        }
        return by.values.sorted { a, b in a.mine != b.mine ? a.mine : a.at > b.at }
    }

    /// This device's seed, written to this installation's own record: when the switch stands and a seed exists.
    /// Update first, add if absent -- the shape setDeviceOnly uses; a delete-then-add leaves a window with nothing
    /// in it. The one record of the builds before, when it carries these very words, leaves: it was this device's,
    /// and it stands now under the new name. A record another installation wrote is never touched.
    @discardableResult
    static func publish() -> Bool {
        guard on, let m = MontanaSeed.mnemonic else { return false }
        let name = ownRecord
        let rows = records()
        var st: OSStatus = errSecSuccess
        if rows.first(where: { $0.name == name })?.words != m {
            let attrs: [String: Any] = [kSecValueData as String: Data(m.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
            st = SecItemUpdate(query(name) as CFDictionary, attrs as CFDictionary)
            if st == errSecItemNotFound {
                var add = query(name); add.merge(attrs) { _, new in new }
                st = SecItemAdd(add as CFDictionary, nil)
            }
            MontanaTrace.mark("apple_id", "published st=" + String(st))
        }
        if rows.contains(where: { $0.name == legacyRecord && $0.words == m }) {
            let gone = SecItemDelete(query(legacyRecord) as CFDictionary)
            MontanaTrace.mark("apple_id", "the record of the builds before retired st=" + String(gone))
        }
        return st == errSecSuccess
    }

    /// «Forget this device»: this installation's record leaves with the seed. A twin's record of the same words
    /// stands -- the twin still holds that person.
    static func withdrawOwn() {
        guard let name = ownRecordIfDrawn else { return }
        let st = SecItemDelete(query(name) as CFDictionary)
        MontanaTrace.mark("apple_id", "own record withdrawn st=" + String(st))
    }

    /// The person's word, the switch off: the account carries no seed of this app any more, from any device.
    static func withdrawAll() {
        let st = SecItemDelete(query(nil) as CFDictionary)
        MontanaTrace.mark("apple_id", "all records withdrawn st=" + String(st))
    }

    /// One word for the row: what THIS PHONE'S keychain holds for the account, against this device's seed. The
    /// keychain answers for what was written here, not for what iCloud carried away: whether the Passwords and
    /// Keychain switch stands in iCloud's settings no app can read, and the row says so under it.
    enum Word: Equatable { case none, mine(others: Int), others(Int) }
    static func word() -> Word {
        let all = held()
        guard !all.isEmpty else { return .none }
        let m = MontanaSeed.mnemonic
        return all.contains { $0.words == m } ? .mine(others: all.count - 1) : .others(all.count)
    }
}
