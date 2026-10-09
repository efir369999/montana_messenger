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
// Transport is irrelevant here by design. A message delivered by the direct channel, by the
// Bluetooth mesh or through a transit peer ends in the same place — the delivery layer is a
// layer, not a notification system. `willPresent` in MontanaApp stays the one
// place deciding show/hide (open chat -> silent, muted -> badge only).

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

    // ONE FUNCTION OF THE BANNER'S WORDS (MTRowLetter.bannerWords): the extension says the same -- a coin letter's coins, and
    // nothing else of the wallet rings (the author's words 09.10.2026 18:0x-18:1x MSK).
    static func body(for text: String) -> String? { MTRowLetter.bannerWords(text) }


    // What kind of payload this is, for the trace. Without it the log shows only a message id, and a
    // conversation wipe reads exactly like an ordinary line — which is how a delivery that worked
    // looked, for a while, like one that never happened.
    // EVERY WORD THE TREE SENDS HAS ITS NAME HERE (the critic 24.09): «CS:» and «CD:» named marks no build sends,
    // while the ring, the call's signal, the wipe of a conversation, an edit, a card, the address, the exit's door, the
    // wake's handle, a sticker and a set's word all read «service» — and the slowest landings named nothing. The names
    // the first letter holds back (MontanaP2PNode: live-draft, typing, watch, presence, draft, read, receipt) stand.
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
        if text.hasPrefix("\u{200B}\u{200B}KP:") { return "keep" }    // the keeping of a copy (MTKeeping, 08.10): service, no banner
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
            MontanaP2PTrace.mark("notify_skip", mid: nil, "why=disabled kind=release"); return
        }
        let content = UNMutableNotificationContent()
        let body = String(localized: "New version", bundle: MTLanguage.bundle) + " " + (version.isEmpty ? "" : version + " ") + "(" + String(build) + ")"
        decorate(content, from: montanaRoomKey, chat: montanaRoomKey, body: body, countUnread: false)
        content.title = montanaRoomTitle
        // FROM MONTANA, NOT FROM A CONVERSATION (the author's word 03.10): the room speaks as one sender of its own, with no
        // conversation's group name over it.
        let final = withCommunication(content, from: montanaRoomKey, group: false) ?? content
        MontanaP2PTrace.mark("notify", mid: nil, "kind=release build=\(build)")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "release-\(build)", content: final, trigger: nil)) { err in
            if let err { MontanaP2PTrace.mark("notify_failed", mid: nil, "err=\(err.localizedDescription)") }
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
        content.categoryIdentifier = "MESSAGE"          // the one category: no answer, no call back
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

    // ── the system's memory of the people ─────────────────────────────────────
    /// THE WALLET OFFERS NOBODY IN THE SHARE SHEET (the author's words 09.10.2026 18:0x-18:1x MSK: «the calls and the chats do not
    /// touch the wallet»): it has no share sheet and donates no conversation; a coin's banner alone names its sender. What older
    /// builds donated is taken back with the person it names.
    /// A deleted chat leaves the system's suggestions and its notification donations.
    static func forgetSuggestions(_ ref: String) {
        guard !ref.isEmpty else { return }
        INInteraction.delete(with: ref) { _ in }
    }
    /// The person left the device: every donation of theirs goes.
    static func forgetAllSuggestions() {
        INInteraction.deleteAll { _ in }
    }

    // ── app side: raise the banner for a message that just arrived over ANY layer ──
    // Called from the single inbound funnel. Delivery layer, delivery time and delivery order are
    // none of this function's business: a message landed, the user is told.
    /// Where the banner's title came from, said plainly — «from nobody» and «from a short address»
    /// are different defects with different fixes, and until this was recorded they looked alike.
    /// The step is the resolver's own answer, never a second reading beside it.
    static func titleSource(for ref: String) -> String { resolvedName(for: ref).source }

    static func present(from: String, chat: String, text: String, mid: String) {
        // ONE notebook of shown letters for BOTH processes ([C-1]): the push extension
        // writes nseShownMids on every banner it shows; the app consults and writes THE
        // SAME notebook. In-process memory was blind to the second ringer — the push
        // extension is another process (precedent 23.08: two notifications, one video).
        let ud = UserDefaults.standard
        let kind = kind(for: text)
        let enabled = ud.object(forKey: "notifEnabled") as? Bool ?? true
        let raw = body(for: text)
        if !enabled || raw == nil {
            // [P2P-COMPAT] the service check stands FIRST: a control letter must not touch the
            // shown-mids notebook below — the presence heartbeat used to write the keychain
            // every second, and the journal printed a «ring» that never rang.
            // Every refusal is named. Silence here read as «the banner was shown», and a whole
            // class of «notifications are wrong» had nothing in the log to stand on.
            // D-3: a control letter never rings BY CONSTRUCTION — logging that non-decision
            // printed two lines per incoming presence beat. Only the person's own setting speaks.
            if !enabled { MontanaP2PTrace.mark("notify_skip", mid: mid, "why=disabled kind=\(kind)") }
            return
        }
        let key = mid.hasPrefix("mid:") ? String(mid.dropFirst(4)) : mid
        if !key.isEmpty {
            var rang: [String] = []
            if let d = MontanaKeychain.get("nseShownMids"),
               let a = try? JSONDecoder().decode([String].self, from: d) { rang = a }
            guard !rang.contains(key) else {
                MontanaP2PTrace.mark("notify_skip", mid: key, "why=already-rang")
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
                 body: preview ? (raw ?? "") : MTRowLetter.hiddenCoinWords, countUnread: false)
        if !showSender { content.title = "Montana" }
        let comm = showSender ? withCommunication(content, from: from) : nil
        let final = comm ?? content
        let id = mid.isEmpty ? UUID().uuidString : mid
        let src = showSender ? titleSource(for: from) : "hidden"
        // A drawn initial is always there; what the diary asks is whether the person's photo stood.
        let photo = showSender && facePhoto(for: from) != nil
        MontanaP2PTrace.mark("notify", mid: mid,
                             "kind=\(kind) title_src=\(src) title_len=\(content.title.count) "
                             + "body_len=\(content.body.count) preview=\(preview ? 1 : 0) "
                             + "sender=\(showSender ? 1 : 0) face=\(photo ? "photo" : "drawn") "
                             + "comm=\(comm != nil ? 1 : 0) from=\(String(from.prefix(10)))")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: final, trigger: nil)) { err in
            if let err { MontanaP2PTrace.mark("notify_failed", mid: mid, "err=\(err.localizedDescription)") }
        }
    }
}
