import Foundation
import SwiftUI

/// THE CROWN IS GIVEN, NEVER TYPED (the author's word 03.10: «a system ban on crowns before a name -- only a Royal hands them
/// out, as a verification»): no name a person types or a correspondent sends wears a crown or one of its look-alikes; the
/// Montana room alone wears it (montanaRoomTitle). A crown a Royal hands out will stand beside a name by its own proof.
enum MTCrown {
    private static let marks: Set<Unicode.Scalar> = ["\u{1F451}", "\u{2654}", "\u{2655}", "\u{265A}", "\u{265B}"]
    static func plain(_ name: String) -> String {
        guard name.unicodeScalars.contains(where: { marks.contains($0) }) else { return name }
        var out = String.UnicodeScalarView()
        var afterMark = false
        for s in name.unicodeScalars {
            if marks.contains(s) { afterMark = true; continue }
            if afterMark && (s == "\u{FE0F}" || s == "\u{FE0E}") { continue }
            afterMark = false
            out.append(s)
        }
        return String(out).split(separator: " ").joined(separator: " ")
    }
}

enum MTNameBook {
    static var declared: [String: String] = [:]         // mirror of ChatStore.peerNames (kept in sync there)
    private static var manualCache: [String: String]?   // renames made by hand, BY ADDRESS
    private static func manual() -> [String: String] {
        if let m = manualCache { return m }
        var m: [String: String] = [:]
        if let d = MontanaLocalVault.getDecrypted("manualNames"),
           let x = try? JSONDecoder().decode([String: String].self, from: d) { m = x }
        // A SEALED VAULT MUST NOT LATCH THE CACHE (stage 9): on a true cold start the device
        // key is nil for the first moments — caching that emptiness kept «Correspondent» for
        // the WHOLE session even after the key arrived. Empty-with-no-key = «not read yet».
        if MontanaDeviceKey.key == nil { return m }
        manualCache = m
        return m
    }
    /// WHAT MY HAND DID NOT CHANGE IS NOT MINE (the author's word 20.09: «the profile shows the old
    /// name and the old face everywhere»). The edit page prefills the fields with the name the
    /// person gave themselves and the photo they published; «Done» handed both back here, and the
    /// book pinned them as «set by you» — from that moment every rename and every new face of theirs
    /// was hidden behind my own copy of their old word. The rule lives in the ONE writer, for every
    /// door: a value equal to their own word clears the pin instead of setting it.
    static func setManual(conv: String, first: String?, last: String?) {
        let f = (first ?? "").trimmingCharacters(in: .whitespaces)
        let l = (last ?? "").trimmingCharacters(in: .whitespaces)
        var full = (f + " " + l).trimmingCharacters(in: .whitespaces)
        if let theirs = declared[conv], !theirs.isEmpty, full == theirs { full = "" }   // their own word — not a pin
        var m = manual()
        m[conv] = full.isEmpty ? nil : full          // clearing the field restores the declared name
        manualCache = m
        if let d = try? JSONEncoder().encode(m) { MontanaLocalVault.setEncrypted("manualNames", d) }
        mirrorCold(conv, full.isEmpty ? (known(conv) ?? "") : full)   // the cold mirror follows the door (stage 9); cleared — the book's next answer, not the raw declared word
    }
    static func manualName(_ conv: String) -> String? { manual()[conv] }

    /// The peer name, if this device already knows it. There is nobody outside to ask: a person says
    /// their name over the channel the two of you share, and until then the book holds what it holds.
    static func ensureName(_ conv: String) {
        _ = names()[conv]
    }
    // The peer nickname is a public name, learned at an introduction by @name or announced over the
    // encrypted channel. It is kept by address: it belongs to the person, not to the conversation.
    private static var nameCache: [String: String]?
    private static func names() -> [String: String] {
        if let m = nameCache { return m }
        var m: [String: String] = [:]
        if let d = MontanaLocalVault.getDecrypted("peerUsernames"),
           let x = try? JSONDecoder().decode([String: String].self, from: d) { m = x }
        if MontanaDeviceKey.key == nil { return m }   // sealed vault must not latch the cache (stage 9)
        nameCache = m
        return m
    }
    static func setName(conv: String, _ name: String?) {
        let v = (name ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "@", with: "")
        var m = names()
        m[conv] = v.isEmpty ? nil : v
        nameCache = m
        if let d = try? JSONEncoder().encode(m) {
            MontanaLocalVault.setEncrypted("peerUsernames", d)
            MontanaKeychain.set("peerUsernames", d)   // the shared place both the app and its extensions read
        }
        syncContactName(conv: conv, v)   // the contact card is kept in step with the name book
    }

    /// The nickname in a contact card is the same value as in the name book. Two stores of one value
    /// drift apart by construction, so the write goes in one call.
    static func syncContactName(conv: String, _ name: String) {
        // The contact store is a local vault, not UserDefaults: a second path to the same data is the
        // very desynchronisation this method is written for.
        let raw = MontanaLocalVault.getString("mtContacts") ?? ""
        guard let d = raw.data(using: .utf8),
              var arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: d),
              let i = arr.firstIndex(where: { $0.ref == conv }), arr[i].name != name else { return }
        arr[i].name = name
        if let out = try? JSONEncoder().encode(arr), let s = String(data: out, encoding: .utf8) {
            MontanaLocalVault.setString("mtContacts", s)
            invalidateContacts()
        }
    }
    static func name(_ conv: String) -> String? { names()[conv] }

    // THE FACE GLYPH IS DERIVED FROM THE NAME, NEVER STORED (20.09, the critic — CLIENT-FIX). A callsign
    // carries its emoji first, so the glyph is a function of the name the book already holds. A stored
    // copy of it was raised only by a letter, a call or a wake — a NAME letter left it behind, and the
    // profile derived the new callsign's face while the list and the chat header still wore the emoji
    // of the last letter. One derivation, one owner: MontanaAvatar.initial over the displayed name;
    // the wire's «g» is still spoken for the older builds and buried unread here ([P2P-COMPAT]).
    // THE FACE IS THEIRS EVEN UNDER MY NAME FOR THEM (the author's word 20.09: «it did not bring back
    // the original — on T3 it is another»): the glyph a person wears is the emoji of the callsign THEY
    // chose, exactly as a photo they published stays theirs when I rename them. Their own word first;
    // my word for them only when they never said one.
    static func faceGlyph(_ conv: String) -> String? {
        let theirs = declared[conv].flatMap { $0.isEmpty ? nil : $0 }
        guard let n = theirs ?? known(conv) else { return nil }
        return MontanaAvatar.initial(title: n, name: conv)
    }
    /// The letter or emoji of a face with a title to fall back on — the one door for every circle.
    static func face(_ conv: String, title: String) -> String {
        faceGlyph(conv) ?? MontanaAvatar.initial(title: title, name: conv)
    }

    /// A name comes from the person it belongs to and from nobody else. There is no registry to
    /// ask: until they say it over the channel, the page shows the reference — which is honest,
    /// whereas a name fetched from a third party is someone else's word for who this is.
    // Avatar tint derived from the displayed name — one derivation, so a row, a menu and a header
    // of the same person always agree.
    // Avatar file for a peer, resolved in ONE place: an explicitly set local picture wins, then
    // the photo the peer published over the encrypted channel; nil means «draw the initial».
    static var published: [String: String] = [:]        // mirror of ChatStore.peerAvatars
    private static var manualPhotoCache: [String: String]?
    private static func manualPhotos() -> [String: String] {
        if let m = manualPhotoCache { return m }
        var m: [String: String] = [:]
        if let d = MontanaLocalVault.getDecrypted("manualPhotos"),
           let x = try? JSONDecoder().decode([String: String].self, from: d) { m = x }
        manualPhotoCache = m
        return m
    }
    // A picture set by hand belongs to the PERSON, keyed by address — not to a chat object, which
    // the contacts tab and the calls log cannot see (the same mistake the manual name once made).
    static func setManualPhoto(conv: String, file: String?) {
        var m = manualPhotos()
        // The photo they published is their own word — handing it back is not a pin (see setManual).
        let pin = (file?.isEmpty ?? true) || file == published[conv] ? nil : file
        m[conv] = pin
        manualPhotoCache = m
        forgetPictures()
        if let d = try? JSONEncoder().encode(m) { MontanaLocalVault.setEncrypted("manualPhotos", d) }
        // ITS OWN COLD MIRROR (20.09, the critic): a picture set by hand used to be written into the
        // cold mirror of the faces peers PUBLISHED — the profile then called my own choice «their
        // own», and taking my picture away erased the record of theirs. Two writers of one map.
        manualColdCache = m
        if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set("photosManualCold", d) }
        ChatStore.live?.mirrorFaceToShared(conv)   // the banner and the call screen wear it at once
    }

    // THE FACE GETS THE MIRROR THE NAME ALREADY HAS. Which file belongs to which person is kept
    // in the vault, and a true cold start has no key for it for the first moments — so the list
    // opened with letters in the circles and the faces arrived a second later, in front of the
    // person watching. The name was rescued from exactly this by a keychain mirror; the face was
    // left behind. It is the same mirror, written by the same doors that learn a face, and the
    // picture files themselves need no key at all - only the map to them did.
    private static var coldPhotoCache: [String: String]?
    private static func coldPhotos() -> [String: String] {
        if let c = coldPhotoCache { return c }
        var m: [String: String] = [:]
        if let d = MontanaKeychain.get("photosCold"),
           let x = try? JSONDecoder().decode([String: String].self, from: d) { m = x }
        coldPhotoCache = m
        return m
    }
    static func mirrorColdPhotos(_ files: [String: String]) {
        var m = coldPhotos(); var changed = false
        for (k, v) in files where !v.isEmpty && m[k] != v { m[k] = v; changed = true }
        // A face taken away is as much an answer as a face given, so the mirror loses it too.
        for k in m.keys where files[k] == nil { m[k] = nil; changed = true }
        if changed {
            coldPhotoCache = m
            if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set("photosCold", d) }
        }
    }
    /// WHOSE FACE IS SHOWN — two honest answers, read by the profile (the author's word 20.09: «it is
    /// not clear whether this is their photo or one I set»): the picture set by my hand, and the one
    /// they published themselves. The screen names each aloud and offers the other.
    static func manualPhoto(_ conv: String) -> String? {
        if let m = manualPhotos()[conv], pictureExists(m) { return m }
        return manualColdPhotos()[conv].flatMap { pictureExists($0) ? $0 : nil }
    }
    /// A face may be shown only when its bytes name one correspondent inside its own source map.
    /// Old builds could write one portrait into several new files; comparing file names let that
    /// copied face reach strangers.  The file's digest, not its random file name, is the owner key.
    private static var pictureDigestCache: [String: String] = [:]
    private static var pictureSizeCache: [String: Int] = [:]
    private static func pictureURL(_ file: String) -> URL? {
        let attachment = attachmentURL(file)
        if FileManager.default.fileExists(atPath: attachment.path) { return attachment }
        let avatar = avatarsDirURL().appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: avatar.path) ? avatar : nil
    }
    private static func pictureSize(_ file: String) -> Int? {
        pictureLock.lock(); let cached = pictureSizeCache[file]; pictureLock.unlock()
        if let cached { return cached == 0 ? nil : cached }
        let size = pictureURL(file).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
        pictureLock.lock(); pictureSizeCache[file] = size; pictureLock.unlock()
        return size == 0 ? nil : size
    }
    private static func pictureDigest(_ file: String) -> String? {
        pictureLock.lock(); let cached = pictureDigestCache[file]; pictureLock.unlock()
        if let cached { return cached.isEmpty ? nil : cached }
        let data = pictureURL(file).flatMap { try? Data(contentsOf: $0) }
        let digest = data.map { MontanaQueueKeys.sha256($0).map { String(format: "%02x", $0) }.joined() } ?? ""
        pictureLock.lock(); pictureDigestCache[file] = digest; pictureLock.unlock()
        return digest.isEmpty ? nil : digest
    }
    /// The digest of a face file's bytes, as the owner check reads it (ChatStore.publishedFace).
    static func digestOf(_ file: String) -> String? { pictureDigest(file) }
    private static func uniquelyOwned(_ file: String, in files: [String: String]) -> Bool {
        guard let size = pictureSize(file), let digest = pictureDigest(file) else { return false }
        return files.values.reduce(into: 0) { count, candidate in
            if pictureSize(candidate) == size, pictureDigest(candidate) == digest { count += 1 }
        } == 1
    }
    /// A picture chosen in the contact editor remains a deliberate local choice.  A legacy map
    /// that maps its bytes to more than one contact is not evidence of any of those choices.
    static func uniqueManualPhoto(_ conv: String) -> String? {
        let warm = manualPhotos()
        if let file = warm[conv], pictureExists(file), uniquelyOwned(file, in: warm) { return file }
        let cold = manualColdPhotos()
        if let file = cold[conv], pictureExists(file), uniquelyOwned(file, in: cold) { return file }
        return nil
    }
    /// A peer-published face is accepted only from the active person's map and only when no other
    /// reference in that map carries the same image bytes.  Ambiguity deliberately resolves to nil.
    static func uniquePublishedPhoto(_ conv: String, files: [String: String]) -> String? {
        guard let file = files[conv], pictureExists(file), uniquelyOwned(file, in: files) else { return nil }
        return file
    }
    /// Every visible peer face asks the active chat store.  There is no visible fallback to the
    /// book's cross-seat mirror: before a store exists, only an unambiguous local choice may draw.
    static func displayedPhoto(_ conv: String) -> String? {
        ChatStore.live?.avatarFor(ref: conv) ?? uniqueManualPhoto(conv)
    }
    /// ACCIDENTAL PINS ARE SWEPT ONCE AT LAUNCH (20.09): pins written by the old «Done» that only
    /// repeated the peer's own word — a name equal to the declared one, a photo that is the published
    /// file or points at a file the face update has since removed — go, and the peer's word shows.
    static func sweepAccidentalPins() {
        var names = 0, photos = 0
        #if DEBUG
        // THE TEST PHONES' PINS WERE ALL BORN OF THE OLD «DONE» (the author's word 20.09: nothing was
        // renamed by hand): a pin that copied a word the peer has since changed cannot be told from a
        // rename by hand, so on the Debug builds every pin goes once. A release keeps a person's renames.
        // A NAME ON A CONTACT CARD IS THE PERSON'S OWN WORD (the author's word 20.09: «all my contacts
        // lost their names»): the wipe of 1782 took the rename book whole, and the names typed into the
        // cards — «Create new contact», a phone card attached — live in that same book. The cards still
        // hold the words (the wipe never touched them), so the book takes them back once; the wipe
        // itself leaves a card's name alone on a device that has not run it yet.
        if MontanaDeviceKey.key != nil, !UserDefaults.standard.bool(forKey: "pinsWiped1782") {   // a sealed vault answers nothing — not yet
            let carded = contacts()
            for (conv, _) in manual() where carded[conv] == nil { setManual(conv: conv, first: "", last: ""); names += 1 }
            for (conv, _) in manualPhotos() { setManualPhoto(conv: conv, file: nil); photos += 1 }
            UserDefaults.standard.set(true, forKey: "pinsWiped1782")
            MontanaP2PTrace.mark("pins_wiped", "debug once names=\(names) photos=\(photos)")
            names = 0; photos = 0
        }
        if MontanaDeviceKey.key != nil, !UserDefaults.standard.bool(forKey: "phoneNamesRestored1787") {
            UserDefaults.standard.set(true, forKey: "phoneNamesRestored1787")
            ContactsTabView.MTContact.restoreNamesFromPhone()   // the phone's cards outlived the sweep of 1786
        }
        if MontanaDeviceKey.key != nil, !UserDefaults.standard.bool(forKey: "cardNamesRestored1784") {
            var back = 0
            if let data = (MontanaLocalVault.getString("mtContacts") ?? "").data(using: .utf8),
               let arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: data) {
                for c in arr where manual()[c.ref] == nil && !c.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
                    setManual(conv: c.ref, first: c.firstName, last: c.lastName)
                    if manual()[c.ref] != nil { back += 1 }
                }
            }
            UserDefaults.standard.set(true, forKey: "cardNamesRestored1784")
            MontanaP2PTrace.mark("card_names_restored", "debug once names=\(back)")
        }
        #endif
        // A RENAME BY HAND STANDS, WHATEVER THE WORD (the author's word 20.09: «if I renamed a contact it
        // shows so»): the only word that is not mine is the one equal to what the peer says NOW.
        for (conv, name) in manual() where declared[conv] == name { setManual(conv: conv, first: "", last: ""); names += 1 }
        for (conv, file) in manualPhotos() where file == published[conv] || !pictureExists(file) {
            setManualPhoto(conv: conv, file: nil); photos += 1
        }
        if names + photos > 0 { MontanaP2PTrace.mark("pins_swept", "names=\(names) photos=\(photos)") }
    }
    private static var manualColdCache: [String: String]?
    private static func manualColdPhotos() -> [String: String] {
        if let c = manualColdCache { return c }
        var m: [String: String] = [:]
        if let d = MontanaKeychain.get("photosManualCold"),
           let x = try? JSONDecoder().decode([String: String].self, from: d) { m = x }
        manualColdCache = m
        return m
    }
    static func publishedPhoto(_ conv: String) -> String? {
        if let p = published[conv], pictureExists(p) { return p }
        if let c = coldPhotos()[conv], pictureExists(c) { return c }
        return nil
    }
    static func avatarFile(for conv: String, local: String? = nil) -> String? {
        if let l = local, pictureExists(l) { return l }          // groups pass their own file
        if let m = manualPhoto(conv) { return m }                 // by hand — warm store, then its own cold mirror
        if let p = published[conv], pictureExists(p) { return p }
        // The mirror answers LAST, and only while the warm stores are still locked.
        if let c = coldPhotos()[conv], pictureExists(c) { return c }
        return nil
    }
    static func color(for name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo]
        return palette[abs(name.hashValue) % palette.count]
    }
    // Keep the address-book entry in step with a manual rename, so the two manual stores never
    // disagree about the same person.
    static func syncContact(conv: String, first: String?, last: String?) {
        let raw = MontanaLocalVault.getString("mtContacts") ?? ""
        guard let data = raw.data(using: .utf8),
              var arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: data),
              let i = arr.firstIndex(where: { $0.ref == conv }) else { return }
        // THE CARD MIRRORS THE BOOK (20.09): a word the one writer refused as a pin — the peer's own,
        // prefilled into the fields — does not land on the card as mine either.
        let held = mine(conv) != nil
        arr[i].firstName = held ? (first ?? "").trimmingCharacters(in: .whitespaces) : ""
        arr[i].lastName = held ? (last ?? "").trimmingCharacters(in: .whitespaces) : ""
        if let d = try? JSONEncoder().encode(arr), let js = String(data: d, encoding: .utf8) {
            MontanaLocalVault.setString("mtContacts", js)
            invalidateContacts()
        }
    }
    private static var contactCache: [String: String]?
    static func invalidateContacts() {
        contactCache = nil
        bookLock.lock(); bookRefs = nil; bookLock.unlock()
        // A WALL KEPT FOR CONTACTS FOLLOWS THE BOOK (the critic 25.09): one taken out of the book is carried the empty page,
        // one put in it the page — the wall's push reads the rule anew at every change of the book.
        if MTBoardRule.current(.see) == .contacts || MTBoardRule.current(.write) == .contacts {
            DispatchQueue.main.async { MTBoard.shared.renewVersion(own: true) }
        }
        if MTBoardRule.current(.vpn) == .contacts { Task { @MainActor in MTVPNWall.shared.schedulePush() } }   // the VPN wall follows the book too (29.09)
    }
    /// THE BOOK'S PEOPLE, BY REFERENCE (the author's word 25.09: «only contacts», for who sees my wall and who writes on
    /// it): every card of the book, named or not. Read for every presence word and from any thread — held under its own
    /// lock, and let go with the book's other caches at every change of the book.
    private static let bookLock = NSLock()
    private static var bookRefs: Set<String>?
    static func isContact(_ conv: String) -> Bool {
        bookLock.lock(); let held = bookRefs; bookLock.unlock()
        if let held { return held.contains(conv) }
        var s = Set<String>()
        if let data = (MontanaLocalVault.getString("mtContacts") ?? "").data(using: .utf8),
           let arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: data) {
            for c in arr where !c.ref.isEmpty { s.insert(c.ref) }
        }
        if MontanaDeviceKey.key != nil { bookLock.lock(); bookRefs = s; bookLock.unlock() }   // a sealed vault must not latch it
        return s.contains(conv)
    }
    private static func contacts() -> [String: String] {
        if let c = contactCache { return c }
        var m: [String: String] = [:]
        if let data = (MontanaLocalVault.getString("mtContacts") ?? "").data(using: .utf8),
           let arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: data) {
            for c in arr where !c.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
                m[c.ref] = c.fullName
            }
        }
        if MontanaDeviceKey.key == nil { return m }   // sealed vault must not latch the cache (stage 9)
        contactCache = m
        return m
    }
    /// The person's name, if it is KNOWN to this device, and `nil` when nobody named themselves.
    ///
    /// ONE place where a name is assembled ([C-1]). The callers differ in exactly one thing -- the
    /// words they say "there is no name" with: a screen says it with a neutral caption, service paths
    /// with the short link form. While there were several assemblies of the name, they drifted apart:
    /// the chat list read neither book and showed the neutral caption to everyone.
    ///
    /// The order: a local rename -> a manual rename -> the contact card -> the name the person said
    /// about themselves -> the nickname.
    // COLD MIRROR (stage 9): the vault opens with the device key, and a true cold start has
    // none for the first moments — but a known name must NEVER give way to the neutral
    // caption. The mirror lives in the keychain (readable from the first instant, same
    // protection class as the extension inbox) and is written by the name doors themselves.
    private static var coldCache: [String: String]?
    private static func coldNames() -> [String: String] {
        if let c = coldCache { return c }
        var m: [String: String] = [:]
        if let d = MontanaKeychain.get("namesCold"),
           let x = try? JSONDecoder().decode([String: String].self, from: d) { m = x }
        coldCache = m
        return m
    }
    static func mirrorCold(_ conv: String, _ name: String) {
        var m = coldNames()
        guard !conv.isEmpty, m[conv] != name else { return }
        if name.isEmpty { m[conv] = nil } else { m[conv] = name }
        coldCache = m
        if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set("namesCold", d) }
    }
    static func mirrorColdAll(_ names: [String: String]) {
        // THE MIRROR HOLDS THE BOOK'S ANSWER, NOT THE PEER'S WORD (the author's word 18.09): written
        // raw, the declared name overwrote a manual rename here, and the cold first frame and the
        // cold incoming call showed the peer's name over mine. A sealed vault gives no honest
        // answer, so nothing is written until it opens.
        guard MontanaDeviceKey.key != nil else { return }
        var m = coldNames(); var changed = false
        for (k, v) in names where !v.isEmpty {
            let r = known(k) ?? v
            if m[k] != r { m[k] = r; changed = true }
        }
        if changed {
            coldCache = m
            if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set("namesCold", d) }
        }
    }
    static func wipeCold() {
        coldCache = [:]; MontanaKeychain.delete("namesCold")
        coldPhotoCache = [:]; MontanaKeychain.delete("photosCold")
    }

    /// THE NAME THIS DEVICE GAVE THE PERSON, or nil: a rename by hand, else the contact card.
    /// WHO NAMED THEM is one question with one answer ([C-1], the author's word 18.09): «me» when
    /// this returns a name, «them» when the only name is the one they said about themselves.
    /// My word stands over any letter or call envelope; their word is freshest in the envelope
    /// itself, and the books only echo it. Two stores of one word could not tell these apart,
    /// and a person's fresh self-rename lost to a stale echo (18:58 T1).
    /// ONLY THE RENAME BOOK IS «MINE» (18.09, T1 19:05: the card said «Tyrannosaurus by=me» — a
    /// word the peer once called themselves, copied into the card's name fields by the old doors,
    /// never typed by the person). The contact card's name fields are a mirror for the phone's
    /// address book, not a source of who named whom; a name that comes from the person's hand
    /// — the rename field, the phone card they attach — enters this book through setManual.
    static func mine(_ conv: String) -> String? {
        if let m = manual()[conv], !m.isEmpty { return m }
        return nil
    }

    // ONE DOOR FOR A PERSON'S OWN NAME, AND ONE TIME (21.09, the critic: a chat born under the callsign
    // printed into a card weeks ago; a letter that slept a day in the box renaming a person back).
    // Seven doors wrote the declared name and one of them asked when the word was spoken. Now every
    // witness of the word — the NM: word itself, a letter's envelope, the card, the call, the box
    // stash, an old history — passes here with the MOMENT the word was spoken, and a word older than
    // the one held is refused. The card is the weakest witness (at = 0): it lands only in an empty
    // book, and the first word of the person covers it; a witness that knows no moment says 0 too.
    private static let declaredAtKey = "declaredAt"
    private static var declaredAtCache: [String: Double]?
    private static func declaredAts() -> [String: Double] {
        if let c = declaredAtCache { return c }
        var m: [String: Double] = [:]
        if let d = MontanaLocalVault.getDecrypted(declaredAtKey),
           let x = try? JSONDecoder().decode([String: Double].self, from: d) { m = x }
        if MontanaDeviceKey.key == nil { return m }   // a sealed vault must not latch the cache
        declaredAtCache = m
        return m
    }
    /// True when the word is at least as fresh as the one held and may be applied; the moment is
    /// recorded. An older word is refused out loud (`name_stale`), never silently.
    static func admitDeclared(conv: String, name: String, at: Double, source: String) -> Bool {
        var m = declaredAts()
        let held = m[conv] ?? 0
        if at < held {
            MontanaP2PTrace.markFolded("name_stale", "\(source) word \(at == 0 ? "undated" : "older than the held one by \(Int(held - at))s") peer=\(String(conv.prefix(10)))", window: 60, key: "ns:" + conv)
            return false
        }
        if at > held || m[conv] == nil {
            m[conv] = at
            declaredAtCache = m
            if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(declaredAtKey, d) }
        }
        return true
    }
    /// ONE-TIME SWEEP of the old doors' residue: a card name that is not in the rename book was
    /// never typed here — it is the peer's old word, copied. Cleared, so neither the card editor
    /// nor the phone's address book carries someone else's stale word as mine.
    static func purgeCopiedCardNames() {
        let flag = "cardNamesPurged"
        guard !UserDefaults.standard.bool(forKey: flag), MontanaDeviceKey.key != nil else { return }
        let raw = MontanaLocalVault.getString("mtContacts") ?? ""
        guard let data = raw.data(using: .utf8),
              var arr = try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: data) else { return }
        var changed = 0
        for i in arr.indices where !arr[i].fullName.trimmingCharacters(in: .whitespaces).isEmpty {
            if manual()[arr[i].ref] == nil { arr[i].firstName = ""; arr[i].lastName = ""; changed += 1 }
        }
        if changed != 0, let d = try? JSONEncoder().encode(arr), let js = String(data: d, encoding: .utf8) {
            MontanaLocalVault.setString("mtContacts", js)
            invalidateContacts()
        }
        UserDefaults.standard.set(true, forKey: flag)
        MontanaLog.event("NAME card sweep: cleared \(changed) copied card names")
    }
    static func namedBy(_ conv: String) -> String { mine(conv) == nil ? "them" : "me" }

    static func known(_ conv: String, localFirst: String? = nil, localLast: String? = nil) -> String? {
        let f = (localFirst ?? "").trimmingCharacters(in: .whitespaces)
        let l = (localLast ?? "").trimmingCharacters(in: .whitespaces)
        let local = MTCrown.plain((f + " " + l).trimmingCharacters(in: .whitespaces))
        if !local.isEmpty { return local }
        if let m = mine(conv).map(MTCrown.plain), !m.isEmpty { return m }
        if let d = declared[conv].map(MTCrown.plain), !d.isEmpty { return d }
        // The cold mirror answers LAST among real names and BEFORE the neutral caption:
        // «Correspondent» is reachable only when no store — warm or cold — holds a name.
        if let c = coldNames()[conv].map(MTCrown.plain), !c.isEmpty { return c }
        return nil
    }

    static func display(conv: String, localFirst: String? = nil, localLast: String? = nil,
                        fallback: String? = nil) -> String {
        if let n = known(conv, localFirst: localFirst, localLast: localLast) { return n }
        if let f = fallback, !f.isEmpty { return f }
        // A RECOVERED HISTORY SAYS WHAT IT IS (24.09, the author's word «do it»): a conversation restored from the archive
        // without its key and without a name is no correspondent anyone can reach — under the neutral caption it read as an
        // unknown person who could not be answered (T1 arc:d7f0fd, «Correspondent» since 17.09).
        if ChatStore.isTranscript(conv) { return String(localized: "Recovered history", bundle: MTLanguage.bundle) }
        // A public account without a nickname does not exist, so "there is no nickname" means "the
        // account is private", and there is nothing to show. The address is never substituted here: it
        // is eternal and ties all of a person's actions together, while a name is held by activity, changes and is released.
        // The neutral caption is one for the whole client -- there are never two words for one "no name".
        return String(localized: "Correspondent", bundle: MTLanguage.bundle)
    }

    /// Whether a picture named this way is actually on the device. A name without a file behind it
    /// draws an empty square, and an empty square reads as a broken picture rather than as none.
    // THE DISK IS ASKED ONCE PER FILE, NOT ONCE PER FRAME (15.14). The row print of the chat
    // list asked this for every row on every apply — three file-system calls per row, about
    // once a second, on the main thread (measured 07.09: 261 applies of six rows in a day on
    // T1). The answer changes only when a picture file is written or removed, and every door
    // that does so says forgetPictures().
    private static var pictureCache: [String: Bool] = [:]
    private static let pictureLock = NSLock()
    static func forgetPictures() {
        pictureLock.lock(); pictureCache.removeAll(); pictureDigestCache.removeAll(); pictureSizeCache.removeAll(); pictureLock.unlock()
    }
    /// A COPY LAID, OR A SEED CHANGED (23.09): every cache of the book lets go, so the next question reads the
    /// store as it now stands — a cache kept would write the moment before back over it on the next word — and
    /// the extensions' mirrors of the book are raised from the store at once.
    static func forgetStored() {
        manualCache = nil; nameCache = nil; manualPhotoCache = nil; manualColdCache = nil
        invalidateContacts(); declaredAtCache = nil; coldCache = nil; coldPhotoCache = nil
        published = [:]
        forgetPictures()
        if let d = MontanaLocalVault.getDecrypted("peerUsernames") { MontanaKeychain.set("peerUsernames", d) }
        if let d = MontanaLocalVault.getDecrypted("manualPhotos") { MontanaKeychain.set("photosManualCold", d) }
    }
    private static func pictureExists(_ ref: String) -> Bool {
        guard !ref.isEmpty else { return false }
        pictureLock.lock(); let cached = pictureCache[ref]; pictureLock.unlock()
        if let cached { return cached }
        let found: Bool = {
            if UIImage(named: ref) != nil { return true }
            if FileManager.default.fileExists(atPath: attachmentURL(ref).path) { return true }
            // Faces received over the wire live in Application Support/Avatars (saveChatAvatar):
            // a gate that only knew the attachments folder rejected a saved photo and drew the
            // letter over a picture that was right there on disk.
            let av = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Avatars").appendingPathComponent(ref)
            return FileManager.default.fileExists(atPath: av.path)
        }()
        pictureLock.lock(); pictureCache[ref] = found; pictureLock.unlock()
        return found
    }
}


// -- A short invitation: first contact without an address ---------------------
// A post-quantum key bundle is ~10 KB and DOES NOT FIT into a scannable code (the bound is ~3 KB).
// So the invitation carries 32 bytes of secret and the cell coordinates, while the bundle travels on
// the SECOND step: the guest puts theirs into the cell, the owner answers with theirs. Exactly the
// same resolution as in SMP, where the first message into a queue carries the sender key.
//
// The cell keys are derived by BOTH sides from one invitation secret -- so the card need carry
// neither the 4 KB write-permission key nor the 1184 bytes of the postman key.
struct MontanaInviteShort: Codable {
    var host: String        // the postman address, for example 192.0.2.1:8445
    var secret: String      // 32 bytes in hexadecimal -- the cell keys are derived from it
    static let prefix = "mt:v:"

    func encoded() -> String {
        guard let d = try? JSONEncoder().encode(self) else { return "" }
        return Self.prefix + d.base64EncodedString()
    }
    static func decode(_ s: String) -> MontanaInviteShort? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(prefix), let d = Data(base64Encoded: String(t.dropFirst(prefix.count))),
              let i = try? JSONDecoder().decode(MontanaInviteShort.self, from: d),
              MontanaQueueKeys.hexToData(i.secret).count == 32, !i.host.isEmpty else { return nil }
        return i
    }
}
