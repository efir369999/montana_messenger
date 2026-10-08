import Foundation
import Security

// The contour identifier is ONE value from which everything else is derived ([I-10]/[C-1]).
// The app is called `p2p.montana.app`, its extensions append a fourth part to that name. So the
// contour name is the first three parts of our own identifier, and it is the same in the app and in
// every extension, with no second list and no branching on "if this is that build contour". A new
// extension and a new contour need not one edit here.
enum MontanaContour {
    static let appId: String = {
        let parts = (Bundle.main.bundleIdentifier ?? "p2p.montana.app").split(separator: ".")
        return parts.prefix(3).joined(separator: ".")
    }()
    static let teamPrefix = "S8JCA5MBVD"
    static let keychainGroup = "\(teamPrefix).\(appId).shared"   // the entitlements grant exactly this name
    static let appGroup = "group.\(appId)"                        // the entitlements grant exactly this name too
    static let wakeTask = "\(appId).wake"
    /// The Darwin note the share sheet rings the app with: system-wide, so it carries the contour's name -- the
    /// share sheet of a forked app (the Business, the VPN) never wakes the Messenger beside it.
    static let sharePending = "\(appId).share.pending"
    /// The app's own link scheme and site, as Info.plist states them (MONTANA_URL_SCHEME, MONTANA_DOMAIN in the project).
    static let urlScheme: String = {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return ((types?.first?["CFBundleURLSchemes"] as? [String])?.first ?? "").lowercased()
    }()
    static let domain: String = (Bundle.main.object(forInfoDictionaryKey: "MontanaDomain") as? String ?? "").lowercased()
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
