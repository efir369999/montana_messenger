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

    /// A WRITE THAT CHANGES NOTHING WRITES NOTHING, AND A WRITE NEVER LEAVES THE KEY ABSENT (23.10.2026, the author's words
    /// 09:16 UTC: «I quit Montana on the Mac, and it hangs and starts by itself»). Every wake by a push walks the ninety doors
    /// that write here, and each write was a delete and an add: 114 deletes and 111 adds in the 36 s of one background launch
    /// on the Mac (system log 09:17:45-09:18:20), most of them the same bytes again -- and between the delete and the add an
    /// extension reading the key found none. The same bytes under the same class: nothing is written. Otherwise the item is
    /// updated where it stands, added only where none stands, and recreated only when the keychain refuses the update.
    @discardableResult static func set(_ key: String, _ data: Data) -> Bool {
        var base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key,
                                   kSecAttrAccessGroup as String: group]
        base.merge(sameEverywhere) { a, _ in a }
        // Readable while the device is unlocked once, for extensions running in the background;
        // never leaves this device and never reaches a backup.
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        defer { MTColdMirror.wrote(key) }
        if stands(base, data) { return true }
        var st = SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        if st != errSecSuccess {
            if st != errSecItemNotFound { SecItemDelete(base as CFDictionary) }
            var add = base
            add.merge(attrs) { _, new in new }
            st = SecItemAdd(add as CFDictionary, nil)
        }
        return st == errSecSuccess
    }

    private static func stands(_ base: [String: Any], _ data: Data) -> Bool {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let found = out as? [String: Any] else { return false }
        return found[kSecValueData as String] as? Data == data
            && found[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
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
        MTColdMirror.wrote(key)
    }
}

/// THE MIRRORS ARE READ FROM THE KEYCHAIN ONCE A WRITE (the author's words 18.10.2026 11:3x-11:4x UTC: «the chats lag»; «as the
/// critic, find the cause of all the lags and fix it in 2242»). Every «is this person refused», «is this chat pinned» asked the
/// keychain afresh -- the system's keychain service, a decode, a set -- and the walk of the walls asked it once per correspondent
/// on the main thread: T1 on 2241, 11:38:36Z, a frame of the chat list held 161 ms inside SecItemCopyMatching under MTBoard.send
/// (ChatStore.refusesCold), and the same question stands in the groups' walks, the list's filter and the delivery queue. In the
/// app every write of a key passes MontanaKeychain.set and delete, so the decoded set stands until that door writes the key; an
/// extension reads afresh, for the app writes behind its back. A read that a write overtook is not kept (turn).
enum MTColdMirror {
    private static let lock = NSLock()
    private static var sets: [String: Set<String>] = [:]
    private static var turn = 0
    private static let keeps = Bundle.main.bundleURL.pathExtension == "app"
    static func set(_ key: String) -> Set<String> {
        lock.lock(); let held = keeps ? sets[key] : nil; let seen = turn; lock.unlock()
        if let held { return held }
        let read = MontanaKeychain.get(key).flatMap { try? JSONDecoder().decode([String].self, from: $0) }.map { Set($0) } ?? []
        lock.lock(); if keeps, seen == turn { sets[key] = read }; lock.unlock()
        return read
    }
    static func wrote(_ key: String) {
        lock.lock(); turn &+= 1; sets[key] = nil; lock.unlock()
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
    /// The name of the one notice the share sheet leaves when it hands a post to my wall (ShareWallHandoff.bell): its tap brings the
    /// app forward on the wall's new-post page, and the page takes it off the list as it rises (MTBoardComposer.present).
    static let wallNotice = "wall-new"   // NOT-UI: a notification's identifier
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

/// WHAT LEFT THIS APP IS KNOWN BY ITS PRINT ALONE (the author's word 08.10.2026 12:1x UTC): a stored value or a letter of an older
/// build is recognised by the first sixteen hex digits of the SHA-256 of its name, so this app names nothing it no longer has -- and
/// still forgets every trace of it on the phone. WHAT CAME BACK IS NO LONGER RETIRED (the author's word 11.10.2026 09:1x UTC, No.60:
/// the VPN, the coins, the mesh, the Passwords app and the P2P wall return to Montana): their values, letters, ops, rooms, diary and
/// keychain item are this app's own again and leave this list; only the switch of the seed in the Apple Account stays retired.
enum MTRetired {
    static func print(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    private static let values: Set<String> = [
        "893dae5f6adc44d7"]   // the switch of the seed in the Apple Account (10.10.2026: the door closed, the switch leaves)
    /// A letter's machine line, by its first seventeen or nineteen characters: no kind of letter is retired now.
    private static let letterLines = Set<String>()

    static func value(_ key: String) -> Bool { values.contains(print(key)) }
    /// An older build's letter: its last line opens with a retired machine line. It is buried unread and rings nothing.
    static func letter(_ text: String) -> Bool {
        guard !letterLines.isEmpty, text.utf8.count <= 65_536,
              let last = text.split(separator: "\n", omittingEmptySubsequences: false).last else { return false }
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
}

/// THE SYSTEM HEARS A CONVERSATION'S ALIAS, NEVER ITS LINK (12.10.2026, No.66; No.65's open item 3 under the rule of absolute
/// privacy): a letter's notice and the share sheet's suggestion handed the system the conversation link -- as the thread, the user
/// info, the person's handle, the conversation and the donation's group. The system keeps delivered notices and donations outside our
/// seal, in its backup and on the account's other devices, and the link is the same on both phones of a pair: every letter stood in one
/// trail of who-with-whom-when. Each conversation now wears one alias on this device -- sixteen random bytes, made of nothing,
/// different on the other phone of the pair -- mapped back here alone, in the shared keychain the app, the notification extension and
/// the share sheet all read. One alias a conversation keeps its notices one thread; a call's notice keeps its own one-time token
/// (MontanaMissedCall.noticeToken).
enum MTNoticeAlias {
    private static let key = "noticeAliases"
    private static let q = DispatchQueue(label: "montana.notice.alias")
    static let head = "n:"   // NOT-UI: an alias's mark: a value of the builds before (the link itself) is told from it
    // BOUND-OK: one row a conversation that rang or was offered; a conversation erased takes its row (forget).
    private static func rows() -> [String: String] {
        guard let d = MontanaKeychain.get(key), let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }
    /// The alias a conversation wears on this device, born once, of nothing.
    static func of(_ conv: String) -> String {
        guard !conv.isEmpty else { return conv }
        // MAIN-SAFE-SYNC: a private queue that never waits on main or on any lock; one small keychain record, read and written in order.
        return q.sync {
            var m = rows()
            if let a = m.first(where: { r in r.value == conv })?.key { return a }
            let a = head + (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            m[a] = conv
            if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set(key, d) }
            return a
        }
    }
    /// A value the system handed back: an alias read to its conversation; any other value (a link of the builds before) as it is.
    static func open(_ value: String) -> String {
        guard value.hasPrefix(head) else { return value }
        // MAIN-SAFE-SYNC: the same private queue, one keychain read.
        return q.sync { rows()[value] } ?? value
    }
    /// A conversation erased: its alias leaves the map and is said, so its donations go with it.
    @discardableResult static func forget(_ conv: String) -> [String] {
        // MAIN-SAFE-SYNC: the same private queue, one keychain read and write.
        q.sync {
            var m = rows()
            let gone = m.filter { r in r.value == conv }.map { r in r.key }
            guard !gone.isEmpty else { return [] }
            for a in gone { m[a] = nil }
            if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set(key, d) }
            return gone
        }
    }
    /// The person left the device: no alias of theirs stays.
    static func forgetAll() {
        // MAIN-SAFE-SYNC: the same private queue, one keychain write.
        _ = q.sync { MontanaKeychain.set(key, Data()) }
    }
}

/// ONE BANNER PER LETTER ACROSS BOTH PROCESSES, BY ONE ATOMIC CLAIM (16.10.2026; the author's words 21:19-21:20 UTC: «two empty
/// messages on T1 ... in fact one message, which showed no sender and doubled»). The ledger of shown letters stood in one keychain
/// item that the app and the extension each rewrote whole -- read, append, delete, add -- so two processes reading it in the same
/// moment both saw the letter as new and both rang it (about thirty pairs on 16.10). A claim is now a FILE created with O_CREAT and
/// O_EXCL in the contour's shared folder: the kernel admits exactly one creator, whichever process it is, and the other finds the
/// file and stays quiet. No lock is ever held -- a lock in the hand of a suspended process is 0xdead10cc. The file is named by the
/// sha256 of the letter's bare name, so nothing of the wire names a file here; a claim older than a day leaves at the app's
/// housekeeping and behind the extension's hand-over ([I-14]). Both processes compile this file.
enum MTShownOnce {
    static var dir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) else { return nil }
        let d = base.appendingPathComponent("shown", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return d
    }
    private static func bare(_ mid: String) -> String { mid.hasPrefix("mid:") ? String(mid.dropFirst(4)) : mid }
    private static func url(_ mid: String) -> URL? {
        let m = bare(mid)
        guard !m.isEmpty, let d = dir else { return nil }
        return d.appendingPathComponent(SHA256.hash(data: Data(m.utf8)).map { String(format: "%02x", $0) }.joined())
    }
    /// True when THIS call is the first to show the letter. An empty name claims nothing and reads as first: a spare ring over
    /// one silently eaten.
    @discardableResult
    static func claim(_ mid: String) -> Bool {
        guard !bare(mid).isEmpty else { return true }
        guard let u = url(mid) else { return legacyClaim(mid) }
        let fd = open(u.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if 0 <= fd {
            close(fd)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: u.path)
            return true
        }
        if errno == EEXIST { return false }
        return legacyClaim(mid)   // the folder refused for another reason: the older notebook decides
    }
    /// The notebook of the builds before 17.10 (the keychain item nseShownMids, rewritten whole): the road only where the contour
    /// has no shared folder.
    private static func legacyClaim(_ mid: String) -> Bool {
        let m = bare(mid)
        var arr: [String] = []
        if let d = MontanaKeychain.get("nseShownMids"), let a = try? JSONDecoder().decode([String].self, from: d) { arr = a }
        guard !arr.contains(m) else { return false }
        arr.append(m)
        if 300 < arr.count { arr.removeFirst(arr.count - 300) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseShownMids", d) }
        return true
    }
    /// [I-14] A claim older than a day leaves: a letter's rings are a matter of seconds, its resends of hours at most.
    static func sweep() {
        guard let d = dir, let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return }
        let old = Date().addingTimeInterval(-86400)
        for n in names {
            let u = d.appendingPathComponent(n)
            if let at = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, at < old {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }
}

/// THE EXTENSION'S DIARY IS APPEND-ONLY (17.10.2026). Its breaths stood in one keychain item of twenty-four lines, rewritten whole by
/// every breath and zeroed by the app at its drain: a breath drawn between the app's read and its zeroing was lost, two pushes served
/// in one process overwrote each other's, and the twenty-fifth line pushed the first out. Each line is now one write with O_APPEND
/// into a file of the contour's shared folder -- the kernel places every such write at the end, whole -- and the app takes the file
/// by renaming it (atomic): a breath drawn after the rename opens a new file and waits for the next drain. Bounded: a file past the
/// cap is turned over once, so two files at most stand here, and the app reads both. The one breath still lost is one whose open
/// preceded the rename and whose write follows the read -- microseconds, where the keychain scheme lost whole seconds.
enum MTExtensionDiary {
    private static let cap = 256 * 1024
    private static let live = "nse.log"
    private static let turned = "nse.old.log"
    private static let taking = "nse.drain."
    static var dir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) else { return nil }
        let d = base.appendingPathComponent("diary", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return d
    }
    /// The extension's side: one line, one write, at the end.
    static func append(_ line: String) {
        guard let d = dir else { return }
        let u = d.appendingPathComponent(live)
        if let size = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber, cap < size.intValue {
            _ = rename(u.path, d.appendingPathComponent(turned).path)   // atomic; a writer already inside keeps its place in the turned file
        }
        let fd = open(u.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard 0 <= fd else { return }
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
    /// The app's side: every line written so far, oldest first, taken off the shelf. A file left by a drain that died mid-way is
    /// read first, so no line is read twice or dropped.
    static func drain() -> [String] {
        guard let d = dir, let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return [] }
        var out: [String] = []
        func take(_ u: URL) {
            if let text = try? String(contentsOf: u, encoding: .utf8) { out += text.split(separator: "\n").map(String.init) }
            try? FileManager.default.removeItem(at: u)
        }
        for n in names.filter({ $0.hasPrefix(taking) }).sorted() { take(d.appendingPathComponent(n)) }
        for n in [turned, live] {
            let src = d.appendingPathComponent(n)
            let dst = d.appendingPathComponent(taking + UUID().uuidString)
            guard FileManager.default.fileExists(atPath: src.path), rename(src.path, dst.path) == 0 else { continue }
            take(dst)
        }
        return out
    }
}

/// A CUT OF A LIST, A SET OR A PIECE OF A STRING IS NO PROPERTY LIST (the author's words 18.10.2026 11:1x UTC: «check the
/// telemetry directly at both and fix it at the root»). 2239 and 2240 died at every launch on T1 and on the Mac --
/// NSInvalidArgumentException «Attempt to insert non-property list object ArraySlice([...]) for key mt.twin.asked»: suffix
/// hands back an ArraySlice, and the settings store takes property lists only. The store's door takes the three shapes Swift
/// makes on its own and writes what they hold, an array or a string: the compiler picks these over set(_: Any?, forKey:) by
/// the value's type, wherever the value was made, so no cut and no set reaches the store as itself. Here, beside the
/// keychain, because the app and its extensions all carry this file.
extension UserDefaults {
    func set<Element>(_ value: ArraySlice<Element>, forKey defaultName: String) { set(Array(value), forKey: defaultName) }
    func set<Element>(_ value: Set<Element>, forKey defaultName: String) { set(Array(value), forKey: defaultName) }
    func set(_ value: Substring, forKey defaultName: String) { set(String(value), forKey: defaultName) }
}
