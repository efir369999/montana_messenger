import Foundation
import UserNotifications
import UIKit
import Intents
import CryptoKit

// SSOT notifications ([I-10]/[C-1]): ONE definition of what a Montana message banner is — title,
// body, grouping, badge, sound, and the Communication-Notification avatar. Compiled into both the
// app and the notification extension, so a banner looks and behaves identically no matter which
// process raised it.
//
// Transport is irrelevant here by design.

enum MontanaNotify {

    // ── what the banner says ──────────────────────────────────────────────────
    // nil = this text is a control signal (receipt, typing, name, avatar, reaction, call, wipe) and
    // must never raise a banner.
    /// Service or letter is decided BY SHAPE, not by a list of names. Every service signal
    /// starts with an invisible marker; while a list of marks stood here it covered exactly
    /// as much as it managed to enumerate, and every new mark slipped through as a banner.
    static func isService(_ text: String) -> Bool {
        guard let f = text.unicodeScalars.first else { return false }
        return f.value == 0x200B || f.value == 0x2063 || f.value == 0x2064
    }

    static func body(for text: String) -> String? { MTRowLetter.bannerWords(text) }


    // What kind of payload this is, for the trace. Without it the log shows only a message id, and a
    // conversation wipe reads exactly like an ordinary line — which is how a delivery that worked
    // looked, for a while, like one that never happened.
    // EVERY WORD THE TREE SENDS HAS ITS NAME HERE (the critic 24.09): «CS:» and «CD:» named marks no build sends,
    // while the ring, the call's signal, the wipe of a conversation, an edit, a card, the address, the exit's door, the
    // wake's handle, a sticker and a set's word all read «service» — and the slowest landings named nothing. The names
    // the first letter holds back (MontanaPhoneNode: live-draft, typing, watch, presence, draft, read, receipt) stand.
    static func kind(for text: String) -> String {
        if text.hasPrefix("\u{200B}\u{2063}") { return "read" }
        if text.hasPrefix("\u{200B}\u{2064}") { return "receipt" }
        if text.hasPrefix("\u{200B}\u{200B}TY:") { return "typing" }
        if text.hasPrefix("\u{200B}\u{200B}WA:") { return "watch" }
        if text.hasPrefix("\u{200B}\u{200B}AP:") { return "presence" }
        if text.hasPrefix("\u{200B}\u{200B}RC:") { return "reaction" }
        if text.hasPrefix("\u{200B}\u{200B}AV:") { return "avatar" }
        if text.hasPrefix("\u{200B}\u{200B}NM:") { return "name" }
        if text.hasPrefix("\u{200B}\u{200B}AB:") { return "about" }
        if text.hasPrefix("\u{200B}\u{200B}RG:") { return "ring" }
        if text.hasPrefix("\u{200B}\u{200B}CL:") { return "call-log" }
        if text.hasPrefix("\u{200B}\u{200B}RL:") { return "release" }
        if text.hasPrefix("\u{200B}\u{200B}MC:") { return "missed-call" }
        if text.hasPrefix("\u{200B}\u{200B}CG:") { return "cargo-lost" }   // service: no banner
        if text.hasPrefix("\u{200B}\u{200B}DL:") { return "delete" }
        if text.hasPrefix("\u{200B}\u{200B}ED:") { return "edit" }
        if text.hasPrefix("\u{200B}\u{200B}DF:") { return "draft" }
        if text.hasPrefix("\u{200B}\u{200B}PN:") { return "pin" }
        if text.hasPrefix("\u{200B}\u{200B}QC:") { return "card" }
        if text.hasPrefix("\u{200B}\u{200B}WH:") { return "wake-handle" }
        if text.hasPrefix("\u{200B}\u{200B}PA:") { return "address" }
        if text.hasPrefix("\u{200B}\u{200B}EX:") { return "exit-door" }
        if text.hasPrefix("\u{200B}\u{200B}SP:") { return "sticker-set" }
        if text.hasPrefix("\u{200B}\u{200B}WL:") { return "wall" }
        if text.hasPrefix("\u{200B}\u{200B}GR:") { return "group" }   // a group's invitation, letter or answer (MTGroup, 05.10)
        if text.hasPrefix("\u{200B}\u{200B}SM:") { return "same-ask" }
        if text.hasPrefix("\u{200B}\u{200B}SY:") { return "same-yes" }
        if text.hasPrefix("\u{200B}\u{200B}PX:") { return "pipe-closed" }
        if text.hasPrefix("\u{200B}\u{200B}VC:") { return "voice" }
        if text.hasPrefix("\u{200B}\u{200B}MD:") { return "media" }
        if text.hasPrefix("\u{2063}\u{2063}") { return "sticker" }
        // COMPAT-LOCAL: the diary's reading of two words the tree has long spoken (callSignalMark, convDelMark) —
        // nothing on these lines rides the wire.
        if text.hasPrefix("\u{2063}mtcall:") { return "call-signal" }
        if text.hasPrefix("\u{2063}mtconvdel:") { return "convdel" }
        if text.hasPrefix("\u{2063}mtdraft:") { return "live-draft" }
        if text.hasPrefix("\u{2063}LB:") { return "letter-blob" }
        if isService(text) { return "service" }
        if text.hasPrefix("♟ "), MTChessLetter.parse(text) != nil { return "chess" }   // a letter of a game, by the one parser (29.09)
        return "text"
    }

    /// One vocabulary for a media letter (MTRowLetter): the row, the banner and this say the same.
    static func mediaBody(_ text: String) -> String { MTRowLetter.mediaWords(letter: text) }

    // Content type without revealing the text (used when "show message text" is off).
    static func typeOnlyBody(_ t: String) -> String {
        if t.hasPrefix("\u{200B}\u{200B}VC:") { return "🎤 " + String(localized: "Voice message", bundle: MTLanguage.bundle) }
        if t.hasPrefix("\u{200B}\u{200B}MD:") { return MTRowLetter.mediaWords(letter: t, revealCaption: false) }
        if MTChessLetter.parse(t) != nil { return "♟ " + String(localized: "Chess", bundle: MTLanguage.bundle) }
        return String(localized: "New message", bundle: MTLanguage.bundle)
    }

    // ── who it is from ────────────────────────────────────────────────────────
    static func displayName(for ref: String, fallback: String = "") -> String {
        resolvedName(for: ref, fallback: fallback).name
    }

    /// The one resolver of a banner's title, together with the step that answered: the diary names the real
    /// source instead of guessing it from a second reading (23.09: a title the book gave was written
    /// «short-address», because the witness asked only the share mirror).
    static func resolvedName(for ref: String, fallback: String = "") -> (name: String, source: String) {
        // ONE name resolver for the whole client: the contact rename first, then the name the
        // person said about themselves (callsign included), and only then the short reference
        // form. A private copy of that parsing showed a truncated reference where a name existed.
        let byResolver = MontanaName.of(ref)
        if !byResolver.isEmpty, byResolver != MontanaConv.short(ref) { return (byResolver, "book") }
        if let d = MontanaKeychain.get("shareChats"),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]],
           let hit = arr.first(where: { $0["name"] == ref }),
           let t = hit["title"], !t.isEmpty { return (t, "mirror") }
        if !fallback.isEmpty && fallback != ref { return (fallback, "fallback") }
        if ref.count > 12 { return (String(ref.prefix(6)) + "…" + String(ref.suffix(4)), "short-address") }
        return (ref, "raw")
    }

    /// The person's own photo mirrored for the banner, or nil — the drawn initial is not a photo.
    static func facePhoto(for ref: String) -> Data? {
        let key = "av_" + SHA256.hash(data: Data(ref.utf8)).map { String(format: "%02x", $0) }.joined()
        if let d = MontanaKeychain.get(key), !d.isEmpty { return d }
        return nil
    }

    static func avatarData(for ref: String, display: String) -> Data? {
        if ref == montanaRoomKey, let face = UIImage(named: montanaRoomFace)?.pngData() { return face }   // the room's face is the app's icon (03.10)
        return facePhoto(for: ref) ?? drawAvatar(for: display)
    }

    /// A NEW BUILD IN TESTFLIGHT RINGS AS A LETTER OF MONTANA (the author's word 29.09): the room's name and face, the
    /// version in the body; one banner per build, named by it. The person's own switch for banners stands.
    static func presentRelease(build: Int, version: String) {
        guard UserDefaults.standard.object(forKey: "notifEnabled") as? Bool ?? true else {
            MontanaTrace.mark("notify_skip", mid: nil, "why=disabled kind=release"); return
        }
        let content = UNMutableNotificationContent()
        let body = String(localized: "New version", bundle: MTLanguage.bundle) + " " + (version.isEmpty ? "" : version + " ") + "(" + String(build) + ")"
        decorate(content, from: montanaRoomKey, chat: montanaRoomKey, body: body, countUnread: false)
        content.title = montanaRoomTitle
        // FROM MONTANA, NOT FROM A CONVERSATION (the author's word 03.10): the room speaks as one sender of its own, with no
        // conversation's group name over it.
        let final = withCommunication(content, from: montanaRoomKey, group: false) ?? content
        MontanaTrace.mark("notify", mid: nil, "kind=release build=\(build)")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "release-\(build)", content: final, trigger: nil)) { err in
            if let err { MontanaTrace.mark("notify_failed", mid: nil, "err=\(err.localizedDescription)") }
        }
    }

    static func drawAvatar(for name: String) -> Data? {
        // The face in the banner is THE SAME face as in the list: same resolver, same black
        // circle, same glyph size. A private drawing stood here — a palette color with a letter
        // on top — and a person saw one face in the notification and another in the chat.
        let initial = MontanaAvatar.initial(title: name, name: "")
        let size = CGSize(width: 180, height: 180)
        let r = UIGraphicsImageRenderer(size: size)
        let img = r.image { ctx in
            UIColor.black.setFill(); ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * MontanaAvatar.glyphScale(initial), weight: .semibold),
                .foregroundColor: UIColor(red: 0.831, green: 0.686, blue: 0.216, alpha: 1)]
            let s = NSAttributedString(string: initial, attributes: attrs)
            let b = s.size()
            s.draw(at: CGPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2))
        }
        return img.jpegData(compressionQuality: 0.9)
    }

    // ── the banner itself ─────────────────────────────────────────────────────
    // `countUnread` is true only for the extension: the app owns the badge and recalculates it, so
    // it must not add on top (double counting).
    static func decorate(_ content: UNMutableNotificationContent, from: String, chat: String,
                         body bodyText: String, countUnread: Bool) {
        content.categoryIdentifier = "MESSAGE"          // inline "Reply" action
        content.title = displayName(for: from, fallback: content.title)
        content.body = bodyText
        content.threadIdentifier = chat                 // grouping + targeted dismissal by the app
        content.userInfo["chat"] = chat                 // willPresent reads this to honour the open chat
        content.userInfo["from"] = from

        if countUnread, !MTQuietChats.holds(chat) {
            var counts = MontanaKeychain.get("unreadCounts").flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
            if !chat.isEmpty { counts[chat, default: 0] += 1 }
            content.badge = NSNumber(value: counts.values.reduce(0, +))
            MontanaKeychain.set("unreadCounts", (try? JSONEncoder().encode(counts)) ?? Data())
        }

        let quiet = MTQuietChats.holds(chat)
        let soundOn = (MontanaKeychain.get("notifSound")?.first ?? 1) == 1
        content.sound = (soundOn && !quiet) ? .default : nil
        if quiet { content.interruptionLevel = .passive; content.badge = nil }   // a muted or archived chat says nothing (MTQuietChats)
    }

        // native rich style for messaging. Returns nil when the intent cannot be applied.
    static func withCommunication(_ content: UNMutableNotificationContent, from: String, group: Bool = true) -> UNNotificationContent? {
        let display = content.title.isEmpty ? from : content.title
        let image = avatarData(for: from, display: display).map { INImage(imageData: $0) }
        var nameComp = PersonNameComponents(); nameComp.nickname = display
        let handle = INPersonHandle(value: from, type: from.contains("@") ? .emailAddress : .unknown)
        let sender = INPerson(personHandle: handle, nameComponents: nameComp, displayName: display,
                              image: image, contactIdentifier: nil, customIdentifier: from,
                              isMe: false, suggestionType: .none)
        let me = INPerson(personHandle: INPersonHandle(value: "0", type: .unknown), nameComponents: nil,
                          displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil,
                          isMe: true, suggestionType: .none)
        let intent = INSendMessageIntent(recipients: [me], outgoingMessageType: .outgoingMessageText,
                                         content: content.body, speakableGroupName: group ? INSpeakableString(spokenPhrase: display) : nil,
                                         conversationIdentifier: from, serviceName: nil, sender: sender, attachments: nil)
        if let img = image { intent.setImage(img, forParameterNamed: \.sender) }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.groupIdentifier = from   // a deleted chat takes this donation with it (forgetSuggestions)
        interaction.donate { _ in }
        return (try? content.updating(from: intent))
    }

    // ── the share sheet's suggestions ─────────────────────────────────────────
    /// A PERSON'S CHATS IN THE SYSTEM'S SHARE SHEET (the author's word 23.09: «when Siri's suggestions for sharing are
    /// on, Montana's contacts and chats are offered»). The system offers the conversations an app donates as sent
    /// messages, and shows them only while the person's own switch stands (Settings › Siri › Suggestions › When
    /// Sharing). A donation carries the chat's local name, the person's name and face — never a word of a letter — and
    /// is made at most once a day per chat, so the system learns whom and which day, not every letter's moment. A chat
    /// deleted takes its donations with it; a person who leaves the device takes them all.
    private static let suggestLock = NSLock()
    private static var suggestedDay: [String: Int] = [:]
    static func suggest(_ ref: String) {
        guard !ref.isEmpty else { return }
        let day = Int(Date().timeIntervalSince1970 / 86400)
        let due = suggestLock.withLock { () -> Bool in
            if suggestedDay[ref] == day { return false }
            suggestedDay[ref] = day
            return true
        }
        guard due else { return }
        let display = displayName(for: ref)
        let image = avatarData(for: ref, display: display).map { INImage(imageData: $0) }
        let person = INPerson(personHandle: INPersonHandle(value: ref, type: .unknown), nameComponents: nil,
                              displayName: display, image: image, contactIdentifier: nil, customIdentifier: ref)
        let intent = INSendMessageIntent(recipients: [person], outgoingMessageType: .outgoingMessageText, content: nil,
                                         speakableGroupName: INSpeakableString(spokenPhrase: display),
                                         conversationIdentifier: ref, serviceName: nil, sender: nil, attachments: nil)
        if let image { intent.setImage(image, forParameterNamed: \.speakableGroupName) }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.groupIdentifier = ref
        interaction.donate { error in
            MontanaTrace.mark("share_suggest", error == nil ? "given to=\(String(ref.prefix(10)))" : "refused code=\((error as NSError?)?.code ?? 0)")
        }
    }
    /// The chats the share sheet shows at once after an update: the top of the person's own list, as the share mirror
    /// orders it (pinned, then the freshest) — once a process, each still at most once a day.
    private static var seeded = false
    static func seedSuggestions() {
        let first = suggestLock.withLock { () -> Bool in
            if seeded { return false }
            seeded = true
            return true
        }
        guard first, let d = MontanaKeychain.get("shareChats"),
              let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: String]] else { return }
        for ref in rows.compactMap({ $0["name"] }).filter({ !$0.isEmpty }).prefix(8) { suggest(ref) }
    }
    /// A deleted chat leaves the system's suggestions and its notification donations.
    static func forgetSuggestions(_ ref: String) {
        guard !ref.isEmpty else { return }
        INInteraction.delete(with: ref) { _ in }
        suggestLock.withLock { suggestedDay[ref] = nil }
    }
    /// The person left the device: every donation of theirs goes.
    static func forgetAllSuggestions() {
        INInteraction.deleteAll { _ in }
        suggestLock.withLock { suggestedDay.removeAll() }
    }

    // ── app side: raise the banner for a message that just arrived over ANY layer ──
    // Called from the single inbound funnel. Delivery layer, delivery time and delivery order are
    // none of this function's business: a message landed, the user is told.
    /// Where the banner's title came from, said plainly — «from nobody» and «from a short address»
    /// are different defects with different fixes, and until this was recorded they looked alike.
    /// The step is the resolver's own answer, never a second reading beside it.
    static func titleSource(for ref: String) -> String { resolvedName(for: ref).source }

    /// Somebody started writing. This raises ONE banner per conversation and replaces it rather
    /// than adding a second: a person needs to know that words are coming, not to watch them being
    /// typed. The window closes when a letter actually arrives, so the next round of typing is
    /// announced once again.
    private static let typingLock = NSLock()
    private static var typingShownAt: [String: Date] = [:]
    private static let typingWindow: TimeInterval = 90

    /// A reminder from Saved Messages (15.52): the system rings at the chosen moment.
    static func scheduleReminder(id: UUID, text: String, at: Double) {
        let c = UNMutableNotificationContent()
        c.title = String(localized: "Reminder", bundle: MTLanguage.bundle)
        c.body = text
        c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                    from: Date(timeIntervalSince1970: at))
        let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "remind-" + id.uuidString, content: c, trigger: trig))
        MontanaTrace.mark("remind_set", "in=\(Int(at - Date().timeIntervalSince1970))s")
    }

    static func presentTyping(from: String, chat: String) {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "notifEnabled") as? Bool ?? true else {
            MontanaTrace.mark("notify_skip", mid: nil, "why=disabled kind=typing")
            return
        }
        typingLock.lock()
        let last = typingShownAt[chat] ?? .distantPast
        let fresh = Date().timeIntervalSince(last) > typingWindow
        if fresh { typingShownAt[chat] = Date() }
        typingLock.unlock()
        guard fresh else {
            MontanaTrace.mark("notify_skip", mid: nil, "why=typing-already-announced")
            return
        }
        let content = UNMutableNotificationContent()
        decorate(content, from: from, chat: chat, body: String(localized: "is typing…", bundle: MTLanguage.bundle), countUnread: false)
        let final = withCommunication(content, from: from) ?? content
        MontanaTrace.mark("notify", mid: nil, "kind=typing from=\(String(from.prefix(10)))")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "typing-\(chat)", content: final, trigger: nil)) { err in
            if let err { MontanaTrace.mark("notify_failed", mid: nil, "err=\(err.localizedDescription)") }
        }
    }

    /// THE PEER PINNED A LETTER (the author's word 22.09: both are told): the app's own banner — the
    /// person's name, the pin and the letter's words (or the plain fact when previews are off); one
    /// banner per letter, named by the letter, so a repeat of the word rings nothing twice.
    static func presentPinned(from: String, chat: String, words: String, sid: String) {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "notifEnabled") as? Bool ?? true else {
            MontanaTrace.mark("notify_skip", mid: nil, "why=disabled kind=pin")
            return
        }
        let preview = ud.object(forKey: "notifPreview") as? Bool ?? true
        let body = "📌 " + (preview && !words.isEmpty ? words : String(localized: "Pinned a message", bundle: MTLanguage.bundle))
        let content = UNMutableNotificationContent()
        decorate(content, from: from, chat: chat, body: body, countUnread: false)
        let final = withCommunication(content, from: from) ?? content
        MontanaTrace.mark("notify", mid: nil, "kind=pin from=\(String(from.prefix(10)))")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pin-\(chat)-\(sid)", content: final, trigger: nil)) { err in
            if let err { MontanaTrace.mark("notify_failed", mid: nil, "err=\(err.localizedDescription)") }
        }
    }

    /// A GROUP'S LETTER LANDED WHILE THE APP RUNS (MTGroup, 05.10): the group's title over its speaker's words, the face the
    /// extension gives the same letter while the app sleeps. The one notebook of shown letters answers by the copy's own name --
    /// the name the extension wrote when it showed this copy -- so one copy rings once, by whichever process.
    static func presentGroup(title: String, body: String, chat: String, copy: String, mentioned: Bool = false) {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "notifEnabled") as? Bool ?? true else {
            MontanaTrace.mark("notify_skip", mid: nil, "why=disabled kind=group")
            return
        }
        let key = copy.hasPrefix("mid:") ? String(copy.dropFirst(4)) : copy
        if !key.isEmpty {
            var rang: [String] = []
            if let d = MontanaKeychain.get("nseShownMids"), let a = try? JSONDecoder().decode([String].self, from: d) { rang = a }
            guard !rang.contains(key) else {
                MontanaTrace.mark("notify_skip", mid: key, "why=already-rang kind=group")
                return
            }
            rang.append(key)
            if 300 < rang.count { rang.removeFirst(rang.count - 300) }
            if let d = try? JSONEncoder().encode(rang) { MontanaKeychain.set("nseShownMids", d) }
        }
        let preview = ud.object(forKey: "notifPreview") as? Bool ?? true
        let content = UNMutableNotificationContent()
        decorate(content, from: chat, chat: chat, body: preview ? body : String(localized: "New message", bundle: MTLanguage.bundle), countUnread: false)
        content.title = title
        if mentioned {   // A MENTION RINGS THROUGH THE MUTE (stage R, as the reference rings one): the person was named
            content.interruptionLevel = .active
            content.sound = (MontanaKeychain.get("notifSound")?.first ?? 1) == 1 ? .default : nil
        }
        MontanaTrace.mark("notify", mid: key.isEmpty ? nil : key, "kind=group body_len=\(content.body.count) preview=\(preview ? 1 : 0)")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: key.isEmpty ? UUID().uuidString : "group-" + key, content: content, trigger: nil)) { err in
            if let err { MontanaTrace.mark("notify_failed", mid: nil, "err=\(err.localizedDescription)") }
        }
    }

    /// A letter arrived — the typing announcement has done its work and the next one is due again.
    static func typingEnded(_ chat: String) {
        typingLock.lock(); typingShownAt[chat] = nil; typingLock.unlock()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["typing-\(chat)"])
    }

    static func present(from: String, chat: String, text: String, mid: String) {
        // ONE notebook of shown letters for BOTH processes ([C-1]): the push extension
        // writes nseShownMids on every banner it shows; the app consults and writes THE
        // SAME notebook. In-process memory was blind to the second ringer — the push
        // extension is another process (precedent 23.08: two notifications, one video).
        let ud = UserDefaults.standard
        let kind = kind(for: text)
        let enabled = ud.object(forKey: "notifEnabled") as? Bool ?? true
        let raw = body(for: text)
        // Live chat raises no banner at all — not as a stream, not as one «started typing».
        // A person learns of a letter when the letter is sent, and not a moment sooner.
        if enabled, raw != nil { typingEnded(chat) }
        if !enabled || raw == nil {
            // Every refusal is named. Silence here read as «the banner was shown», and a whole
            // class of «notifications are wrong» had nothing in the log to stand on. D-3: a
            // control letter never rings BY CONSTRUCTION — logging that non-decision printed two
            // lines per incoming presence beat. Only the person's own setting speaks.
            if !enabled { MontanaTrace.mark("notify_skip", mid: mid, "why=disabled kind=\(kind)") }
            return
        }
        let key = mid.hasPrefix("mid:") ? String(mid.dropFirst(4)) : mid
        if !key.isEmpty {
            var rang: [String] = []
            if let d = MontanaKeychain.get("nseShownMids"),
               let a = try? JSONDecoder().decode([String].self, from: d) { rang = a }
            guard !rang.contains(key) else {
                MontanaTrace.mark("notify_skip", mid: key, "why=already-rang")
                MontanaTelemetry.shared.event("[notify] skip mid=\(key.prefix(8)) why=already-rang")
                return
            }
            rang.append(key)
            if rang.count > 300 { rang.removeFirst(rang.count - 300) }
            if let d = try? JSONEncoder().encode(rang) { MontanaKeychain.set("nseShownMids", d) }
            MontanaTelemetry.shared.event("[notify] ring mid=\(key.prefix(8))")
        }
        let preview = ud.object(forKey: "notifPreview") as? Bool ?? true
        let showSender = ud.object(forKey: "notifSender") as? Bool ?? true
        let content = UNMutableNotificationContent()
        decorate(content, from: from, chat: chat,
                 body: preview ? (raw ?? "") : typeOnlyBody(text), countUnread: false)
        if !showSender { content.title = "Montana" }
        // A GAME'S BANNER NAMES ITS GAME (29.09): the tap enters the game itself (MontanaOutsideOpen.pendingGame), and the
        // foreground judge tells a game's end -- which has no bubble in the chat -- from a letter the open chat shows.
        if let chess = MTChessLetter.parse(text) {
            content.userInfo["game"] = chess.game
            if chess.end != nil { content.userInfo["game_end"] = 1 }
        }
        let comm = showSender ? withCommunication(content, from: from) : nil
        let final = comm ?? content
        let id = mid.isEmpty ? UUID().uuidString : mid
        let src = showSender ? titleSource(for: from) : "hidden"
        // A drawn initial is always there; what the diary asks is whether the person's photo stood.
        let photo = showSender && facePhoto(for: from) != nil
        MontanaTrace.mark("notify", mid: mid,
                             "kind=\(kind) title_src=\(src) title_len=\(content.title.count) "
                             + "body_len=\(content.body.count) preview=\(preview ? 1 : 0) "
                             + "sender=\(showSender ? 1 : 0) face=\(photo ? "photo" : "drawn") "
                             + "comm=\(comm != nil ? 1 : 0) from=\(String(from.prefix(10)))")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: final, trigger: nil)) { err in
            if let err { MontanaTrace.mark("notify_failed", mid: mid, "err=\(err.localizedDescription)") }
        }
    }
}
