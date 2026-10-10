import Foundation
import Security
import CryptoKit

// The contour identifier is ONE value from which everything else is derived ([I-10]/[C-1]).
// The app is called `quest.montana.app`, its extensions append a fourth part to that name. So the
// contour name is the first three parts of our own identifier, and it is the same in the app and in
// every extension, with no second list and no branching on "if this is that build contour". A new
// extension and a new contour need not one edit here.
enum MontanaContour {
    static let appId: String = {
        let parts = (Bundle.main.bundleIdentifier ?? "quest.montana.app").split(separator: ".")
        return parts.prefix(3).joined(separator: ".")
    }()
    static let teamPrefix = "S8JCA5MBVD"
    static let keychainGroup = "\(teamPrefix).\(appId).shared"   // the entitlements grant exactly this name
    static let appGroup = "group.\(appId)"                        // the entitlements grant exactly this name too
    static let wakeTask = "\(appId).wake"
}

// THE shared-keychain accessor, and the only one ([I-10]/[C-1]). The app and the share extension
// are separate processes with one keychain access group between them; the rules for reaching it —
// which group, which accessibility class — are stated once, here, and both targets compile this file.
//
// The group carries the contour's own name. The entitlement grants exactly
// `<appId>.shared`, so a hardcoded base name is not merely untidy: asking for a group
// the entitlement does not list fails, and it fails silently, leaving every mirrored value empty.
/// THE ONE LANGUAGE THE APP SPEAKS ([C-15], the author's word 24.09: «I switch the language to English in the settings,
/// and Saved Messages speaks Russian and the profile's tabs stay Russian -- a broken invariant; and a system language
/// that is not ours -- Greek, Spanish, any -- must give English»). The person's choice; with none, the system's FIRST
/// language when the app has it; otherwise English -- never a later language of the system's list (Greek then Russian
/// gave Russian). Every road to a visible word asks here: SwiftUI's locale, the bundle the UIKit lookups go through,
/// and every String(localized:) by its bundle -- one with no bundle answers in the language the process was launched
/// with, whatever was chosen since. The app's choice is mirrored into the shared keychain, so the extensions that
/// carry this file (the banners, the share sheet) speak it too. Here, beside the keychain, for that reason alone.
/// A CHAT THE PERSON SILENCED SAYS NOTHING (the author's words 03.10 21:48: «it annoys me that notifications come even when I
/// turned the chat's sound off»; «and from the archive all the more»). One answer for the app and its notification extension,
/// read from the mirrors the store writes into the shared keychain: the muted chats and the archived ones.
enum MTQuietChats {
    static func holds(_ conv: String) -> Bool {
        guard !conv.isEmpty else { return false }
        for key in ["mutedChats", "archivedCold"] {
            if let d = MontanaKeychain.get(key), let arr = try? JSONDecoder().decode([String].self, from: d), arr.contains(conv) { return true }
        }
        return false
    }
}

enum MTLanguage {
    static let own = ["en", "ru", "zh-Hans"]
    private static let lock = NSLock()
    private static var mirrored: String?                  // an extension's reading of the app's choice, once a process
    private static var held: (code: String, bundle: Bundle)?
    /// The person's choice ("" -- the system's): the app's own setting, or its mirror in an extension.
    static var chosen: String {
        if let c = UserDefaults.standard.string(forKey: "AppLanguage") { return c }
        if let m = lock.withLock({ mirrored }) { return m }
        let m = MontanaKeychain.get("AppLanguage").flatMap { String(data: $0, encoding: .utf8) } ?? ""
        lock.withLock { mirrored = m }
        return m
    }
    /// The system's FIRST language when it is one of ours; nil otherwise.
    static var systemOwn: String? {
        let first = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
        switch first.languageCode?.identifier {
        case "en": return "en"
        case "ru": return "ru"
        case "zh": return first.maximalIdentifier.contains("Hans") ? "zh-Hans" : nil
        default: return nil
        }
    }
    /// The language the words come in.
    static var code: String {
        let c = chosen
        return own.contains(c) ? c : (systemOwn ?? "en")
    }
    /// The words of that language: its own folder of the app, read as a bundle of its own.
    static var bundle: Bundle {
        let c = code
        if let h = lock.withLock({ held }), h.code == c { return h.bundle }
        let b = Bundle.main.path(forResource: c, ofType: "lproj").flatMap { Bundle(path: $0) } ?? .main
        lock.withLock { held = (c, b) }
        return b
    }
    /// The locale every word is drawn and formatted with -- SwiftUI's, every date, size, length and duration
    /// formatter's (a formatter left on the system's locale speaks the system's language: the minutes stood in
    /// Russian in the contacts of a phone switched to English, 24.09): the system's own while it speaks ours and
    /// nothing was chosen; otherwise that language under the system's region, so the clock keeps its region.
    static var locale: Locale {
        let c = code
        if chosen.isEmpty, systemOwn == c { return .autoupdatingCurrent }
        let lang = Locale.Language(identifier: c)
        return Locale(languageCode: lang.languageCode, script: lang.script, languageRegion: Locale.current.region)
    }
    /// The app's choice, mirrored for the extensions -- written only when it differs.
    static func mirror() {
        let now = Data((UserDefaults.standard.string(forKey: "AppLanguage") ?? "").utf8)
        if MontanaKeychain.get("AppLanguage") != now { MontanaKeychain.set("AppLanguage", now) }
    }
}

enum MontanaKeychain {
    static let group: String = MontanaContour.keychainGroup

    /// The keychain on a Mac is a DIFFERENT keychain unless asked otherwise.
    ///
    /// macOS keeps two: the old file-based one, which knows neither access groups nor accessibility
    /// classes, and the same one as on the phone. By default the request goes to the old one, and a
    /// write with a group is refused -- silently, because the failure comes back as a code, not a window.
    /// One line asks for the same keychain as on the phone, and the environment stops deciding anything:
    /// one code, one behaviour on the phone, the tablet and the Mac.
    private static let sameEverywhere: [String: Any] = [kSecUseDataProtectionKeychain as String: true]

    @discardableResult static func set(_ key: String, _ data: Data) -> Bool {
        var base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key,
                                   kSecAttrAccessGroup as String: group]
        base.merge(sameEverywhere) { a, _ in a }
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        // Readable while the device is unlocked once, for extensions running in the background;
        // never leaves this device and never reaches a backup.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> Data? {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecAttrAccessGroup as String: group,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        q.merge(sameEverywhere) { a, _ in a }
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func delete(_ key: String) {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecAttrAccessGroup as String: group]
        q.merge(sameEverywhere) { a, _ in a }
        SecItemDelete(q as CFDictionary)
    }
}

/// THE LETTERS THIS DEVICE HOLDS (02.10, the critic). A banner exists only for a letter new to this device: a sender
/// that missed our receipt resends a letter the chat already holds, and the extension rang it as new (iPhone 15
/// 08:52:14Z rang a letter of 30.09 that the app then judged a copy). The app notes every letter row it lands or
/// finds standing; the extension stays silent for a letter the device holds. Both processes compile this file.
enum MTHeldLetters {
    private static let key = "heldMids"
    private static let cap = 1000

    static func holds(_ mid: String) -> Bool {
        let m = bare(mid)
        return !m.isEmpty && load().contains(m)
    }

    static func note(_ mid: String) {
        let m = bare(mid)
        guard !m.isEmpty else { return }
        var arr = load()
        guard !arr.contains(m) else { return }
        arr.append(m)
        if cap < arr.count { arr.removeFirst(arr.count - cap) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set(key, d) }
    }

    private static func bare(_ mid: String) -> String { mid.hasPrefix("mid:") ? String(mid.dropFirst(4)) : mid }

    private static func load() -> [String] {
        guard let d = MontanaKeychain.get(key), let a = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return a
    }
}

/// THE HANDOFF SHELF (17.09). The sheet uploads a file to the node and used to hand the app only the
/// manifest — the app then downloaded its own file back (T1 21:56Z: 90 MB up, 90 MB down on cellular,
/// «media_fill» six times). One folder in the app group: the sheet lays the bytes there under a random
/// name, the share item carries that name («src»), the app moves the file into its media store under
/// the name the manifest computes, and the fill finds it on disk and asks nothing. No group, no file,
/// an older sheet without «src» — the old road, the download. Both processes compile this file.
enum MontanaHandoff {
    static var dir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) else { return nil }
        let d = base.appendingPathComponent("handoff", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return d
    }
    /// A shelf name is our own random word: nothing from the wire ever names a shelf file.
    static func url(_ src: String) -> URL? {
        guard !src.isEmpty, src.count <= 40, src.allSatisfy({ $0.isHexDigit || $0 == "-" }), let d = dir else { return nil }
        return d.appendingPathComponent(src)
    }
    /// The sheet's side: the bytes go on the shelf; the returned name travels in the item.
    static func lay(_ data: Data) -> String? {
        let name = UUID().uuidString
        guard let u = url(name),
              (try? data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return nil }
        return name
    }
    static func lay(file: URL) -> String? {
        let name = UUID().uuidString
        guard let u = url(name), (try? FileManager.default.copyItem(at: file, to: u)) != nil else { return nil }
        return name
    }
    /// A file nobody took in a week is a share the app never saw: it leaves the shelf.
    static func sweep() {
        guard let d = dir, let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return }
        let old = Date().addingTimeInterval(-7 * 86400)
        for n in names {
            let u = d.appendingPathComponent(n)
            if let born = (try? u.resourceValues(forKeys: [.creationDateKey]))?.creationDate, born < old {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }

    // THE CARGO SHELF (29.09): the one folder where the pieces of a media letter lie, for every process of the contour.
    // The pieces used to live in the app's own container, so only the app could bring one: a letter whose banner the
    // extension had already shown waited for the person to open the app (measured 29.09 on the sender's iPhone 15 Pro
    // Max: the banner at 13:31:48, the file at 13:53:20 — twenty-one minutes for three seconds of network). The landing
    // door lays the small cargo here in its own budget, the app assembles from the shelf and asks the doors for nothing.
    // No group — nil, and the store keeps its old folder.
    static var blobs: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) else { return nil }
        let d = base.appendingPathComponent("blobs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return d
    }
    /// A piece is named by its blob id alone — 64 hex characters; nothing else from the wire names a file here.
    static func blobURL(_ bid: String) -> URL? {
        guard bid.count == 64, bid.allSatisfy({ $0.isHexDigit }), let d = blobs else { return nil }
        return d.appendingPathComponent(bid)
    }
    static func hasBlob(_ bid: String) -> Bool {
        guard let u = blobURL(bid) else { return false }
        return FileManager.default.fileExists(atPath: u.path)
    }
    /// The landing door's side: a sealed piece onto the shelf, once; a piece already there is left as it lies.
    @discardableResult
    static func layBlob(_ bid: String, _ sealed: Data) -> Bool {
        guard let u = blobURL(bid) else { return false }
        if FileManager.default.fileExists(atPath: u.path) { return true }
        return (try? sealed.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
}

/// WHAT LEFT THIS APP IS KNOWN BY ITS PRINT ALONE (the author's word 08.10.2026 15:1x MSK: «not a string, not a comment, not a
/// mention»): a stored value, a diary, a room, a word or a letter of an older build is recognised by the first sixteen hex digits of
/// the SHA-256 of its name, so this app names nothing it no longer has -- and still forgets every trace of it on the phone.
enum MTRetired {
    static func print(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    private static let values: Set<String> = [
        "d3354b9e175be2f8", "383817792bdadb44", "767fecfd717784c4", "a2b8b401464b9d7a", "1b8f55df217ac12f", "21f133825350c64f",
        "09da477a6792b0a6", "f11b2f74abbe514c", "3c64d0e130b8e517", "40edac2b1436cf27", "8bd7580670ef12cd", "21290422d2788912",
        "1e847a7b99f7fb2f", "6dfb4dfc75a048bb", "a2c89a470c8b4e68", "b4ef431650d29952", "16dc366cf5d4ab7e", "b303a9915419595b",
        "cf5df0cfaf6abb42", "0ebfb5e39c166c31", "286e79df368bc274", "d9eab097aafefbad", "aecf27cf098af505", "066a6017681b9a29",
        "5465de8e02330255", "914177d545951a4a", "baec03f439ab049f", "bea05dfb708b7053", "f5f3635e36459afa", "02fd86fa4a224958",
        "20819e7cb6c89c93", "1319ba68952fb7a7",
        "893dae5f6adc44d7"]   // the switch of the seed in the Apple Account (10.10.2026: the door closed, the switch leaves)
    /// Values a conversation kept under its own key: the name up to and including its first dot.
    private static let valuePrefixes: Set<String> = ["877c3850af65880d", "1acf252d0dea4e14", "57e5c61ef47cc715", "8c8189a5f4adb303"]
    static let keychainItems: Set<String> = ["9a59fadd4343ec4b"]
    private static let diaries: Set<String> = ["7671790c02558dd8", "1d177e01bdf92927"]
    /// A letter's machine line, by its first seventeen or nineteen characters.
    private static let letterLines: Set<String> = ["71beceb0eafaa682", "81e52bba0644a78b"]
    private static let rooms: Set<String> = ["1619ec65489dc6bf"]
    /// An older build's reaction op, wall op and link host.
    private static let words: Set<String> = ["b3a1984ba0b1d8ad"]

    static func value(_ key: String) -> Bool {
        if values.contains(print(key)) { return true }
        guard let dot = key.firstIndex(of: ".") else { return false }
        return valuePrefixes.contains(print(String(key[...dot])))
    }
    static func diary(_ name: String) -> Bool { diaries.contains(print(name)) }
    static func room(_ name: String) -> Bool { rooms.contains(print(name)) }
    static func word(_ w: String) -> Bool { words.contains(print(w)) }
    /// An older build's letter: its last line opens with a retired machine line. It is buried unread and rings nothing.
    static func letter(_ text: String) -> Bool {
        guard text.utf8.count <= 65_536, let last = text.split(separator: "\n", omittingEmptySubsequences: false).last else { return false }
        return [17, 19].contains { n in last.count >= n && letterLines.contains(print(String(last.prefix(n)))) }
    }
    /// The stored values leave at launch, after a copy is laid and with the identity; the count is the trace's.
    @discardableResult static func forgetValues() -> Int {
        let ud = UserDefaults.standard
        let held = ud.dictionaryRepresentation().keys.filter { value($0) }
        for k in held { ud.removeObject(forKey: k) }
        return held.count
    }
    /// The stored name an older build wrote under, found by its print: read once to move what it holds, never named here.
    static func stored(_ printed: String) -> String? {
        UserDefaults.standard.dictionaryRepresentation().keys.first { print($0) == printed }
    }
    /// The retired diary's files leave the diary's folder, never shipped.
    static func forgetDiaries(in dir: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names where diary(n) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
    }
}

extension MontanaKeychain {
    /// The keychain items of an older build leave with the identity: every item of this app's group whose name prints as retired.
    static func forgetRetiredItems() {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccessGroup as String: group,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitAll]
        q.merge(sameEverywhere) { a, _ in a }
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return }
        for item in items {
            guard let name = item[kSecAttrAccount as String] as? String, MTRetired.keychainItems.contains(MTRetired.print(name)) else { continue }
            delete(name)
        }
    }
}
