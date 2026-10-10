// NotificationService.swift — decrypting the notification on the device.
//
// SSOT-DEBT-ACK: bodyKey and openBlob are copied from MTPipe.swift because MTPipe and
// MontanaDirect pull the network layer and do not compile into the extension. The formula is
// frozen by the Canon vectors (MTPipe.agreesWithCanon) — divergence from the set fails on the
// vector inside the app.

import UserNotifications
import CryptoKit
import UIKit
import Intents
import MontanaBindings

final class NotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var best: UNMutableNotificationContent?
    /// The banner in the chat's own face, made once the banner is composed (nativeFace): the expiry hands it over (06.10).
    private var ready: UNNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        Self.servingId = request.identifier
        Self.sweepQuiet()
        let began = Date()
        best = request.content.mutableCopy() as? UNMutableNotificationContent
        guard let content = best else { contentHandler(request.content); return }
        content.categoryIdentifier = "MESSAGE"
        let info = request.content.userInfo
        // The first breath is written BEFORE any network: its absence in the trace now proves
        // the extension was not invoked at all — not that it died somewhere inside. Precedent
        // 26.08 19:03: a loud wake arrived, the trace held zero extension lines, and it was
        // impossible to tell «not called» from «killed mid-way».
        Self.diagLine("wake: env=\((info["env"] as? String)?.isEmpty == false ? 1 : 0) at=\((info["at"] as? Int) ?? 0)")
        // THE BREATH REACHES THE DIARY AT ONCE (21.09, the critic): the keychain line is read by the
        // app at its next drain — on a tablet that opened once in fifteen hours the question «was the
        // extension ever invoked» had no witness. The line rides to the node's diary door now, as the
        // sheet's does; a line that does not make it is a line lost, never a banner held.
        Self.shipLive("wake: env=\((info["env"] as? String)?.isEmpty == false ? 1 : 0) at=\((info["at"] as? Int) ?? 0)")
        Self.tellHeard((info["mid"] as? String) ?? "")

        // The conversation key is conv from DECRYPTION (the shared tag the app keys the chat
        // and avatar by), NOT from the payload's from (the sender address is a different key
        // and begets a twin chat on tap).
        var convKey = (info["from"] as? String) ?? ""
        var senderGlyph = ""
        var openedMid = ""
        var openedQuiet = false
        var cargoLetter: (mid: String, text: String)? = nil   // the media letter whose small cargo this process brings (29.09)
        // A FIRST-MEETING letter: the envelope under the card key carries the encapsulation,
        // the text and the name. FIRST the letter into the box — the app will beget the pipe
        // and the chat from it on opening — THEN the classic banner: a notification is the
        // RESULT of the placement, not a promise (class 6.8 «notification exists — no letter»
        // forbidden by this order by construction).
        if let envB64 = info["env"] as? String, let sealed = Data(base64Encoded: envB64),
           let rdv = Self.openRdvLetter(sealed, at: Self.sealMoment(info)) {
            let text = rdv.text.hasPrefix("\u{2063}LB:") ? (Self.resolveLongLetterSync(rdv.text) ?? rdv.text) : rdv.text
            Self.stashRdv(mid: rdv.mid, text: text, name: rdv.name, glyph: rdv.glyph, ct64: rdv.ct64,
                          invite: rdv.invite, conf: rdv.conf)
            _ = Self.firstTimeShown(rdv.mid)
            var t = rdv.name
            if t.hasPrefix("@") { t.removeFirst() }
            var glyph = rdv.glyph
            if glyph.isEmpty, let f = t.first, MontanaAvatar.isEmoji(f) { glyph = String(f) }
            content.title = t.isEmpty ? "Montana" : MontanaAvatar.spokenName(t)
            content.body = Self.bannerBody(text)
            Self.diagLine("rdv-letter: stored and shown mid=\(rdv.mid.prefix(8))")
            Self.deliverWithAvatar(content, from: "", glyph: glyph, handler: contentHandler)
            return
        }
        if let envB64 = info["env"] as? String, !envB64.isEmpty,
           let sealed = Data(base64Encoded: envB64),
           let (openedConv, mid, rawText, envName, envGlyph, envQt, envQm, envLp) = Self.openWithOwnPipes(sealed, at: Self.sealMoment(info)) {
            // A CALL IN THE PIPE OF A SLOT THIS PHONE KEEPS (MTKeeping in the app, 08.10): never stashed -- the app answers it from
            // the box. A loud call (the restoring phone heard nothing for minutes) wears one banner with the owner's name, and the
            // tap opens the app, which answers; a quiet one rings nobody.
            if openedConv.hasPrefix("keep:") {
                let owner = String(openedConv.dropFirst("keep:".count).prefix(while: { $0 != "#" }))   // «conv#slot»: a keeper of the ring holds several
                guard rawText.contains("\"loud\":1") else {
                    Self.diagLine("keep call quiet mid=\(mid.prefix(8))")
                    contentHandler(Self.quietFace())
                    return
                }
                content.title = Self.mirroredName(for: owner) ?? "Montana"
                content.body = String(localized: "Is restoring their account: open Montana to give back the part of their copy you keep", bundle: MTLanguage.bundle)
                content.sound = .default
                content.threadIdentifier = owner
                content.userInfo["chat"] = owner
                Self.diagLine("keep call banner mid=\(mid.prefix(8))")
                contentHandler(content)
                return
            }
            let conv = Self.chatKey(for: openedConv)   // opening key -> CHAT key (the alias dictionary)
            Self.lastOpened = openedConv
            Self.diag(opened: openedConv, ui: conv, envName: envName, envGlyph: envGlyph)
            // A BLOCKED PERSON IS REFUSED THE MOMENT THEY ARE KNOWN (the critic's word 15.09,
            // measured 13:56: the missed-call look and the ring letter stood before this question
            // and a blocked caller's «missed call» rang the banner). Nothing of theirs is stored,
            // composed or shown; the node that no longer holds our subscription is the first wall,
            // this is the second.
            if Self.isBlocked(conv) {
                Self.diagLine("blocked conv=\(conv.prefix(10)) — refused at the envelope")
                contentHandler(Self.quietFace())
                return
            }
            // A long reference letter: pull the blob (the extension has network) — the full
            // text into both the banner and the chat. Out of time — the generic banner, the
            // app pulls the rest itself.
            let text = rawText.hasPrefix("\u{2063}LB:") ? (Self.resolveLongLetterSync(rawText) ?? rawText) : rawText
            Self.stashLetter(conv: conv, mid: mid, text: text, name: envName, glyph: envGlyph,
                             qt: envQt, qm: envQm, lp: envLp)
            openedMid = mid
            openedQuiet = Self.isQuietText(rawText)
            cargoLetter = (mid, text)
            // A ring letter never wears a banner: the system call screen (voip road, 12.1)
            // is the one face of an incoming call. Old senders still send it loud — the
            // letter is stashed above, the banner is swallowed whole.
            if rawText.hasPrefix("\u{200B}\u{200B}RG:") {
                // THE SECOND BELL (13.09): a ring letter marked «b» is the caller's word that Apple
                // kept the voip wake away — it wears the one banner of an incoming call; the tap
                // opens the app, and the app rings natively while the seed is alive. The native
                // ring, the missed letter and the call's end remove it by its name «bell-<tag>».
                let json = String(rawText.dropFirst("\u{200B}\u{200B}RG:".count))
                let o = json.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if (o?["b"] as? Int) == 1, let seed = o?["s"] as? String, !seed.isEmpty, MontanaMissedCall.state(seed) == nil {
                    content.title = Self.title(conv: conv, envName: envName)
                    content.body = ((o?["v"] as? Bool) ?? false) ? "📹 " + String(localized: "Incoming video call. Tap to answer", bundle: MTLanguage.bundle)
                                                                  : "📞 " + String(localized: "Incoming call. Tap to answer", bundle: MTLanguage.bundle)
                    content.sound = .default
                    content.threadIdentifier = conv
                    content.userInfo["chat"] = conv
                    content.userInfo["mid"] = mid
                    Self.diagLine("bell banner mid=\(mid.prefix(8)) seed=\(seed.prefix(8))")
                    Self.deliverWithAvatar(content, from: conv, glyph: envGlyph, handler: contentHandler)
                    return
                }
                Self.diagLine("ring letter stashed silently mid=\(mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            if Self.serveMissedLetter(rawText, mid: mid, conv: conv, name: envName, handler: contentHandler) { return }
            // A TRANSFER LETTER RINGS NOTHING HERE (the author's word 10.10.2026 15:3x MSK: «transfers do not touch Montana at all»;
            // T1 12:24:29Z: an older build's transfer letter showed «New message» and its chat stood empty -- the app buries it
            // unread, MTRowLetter.retiredLetter): it is stashed for the app without a face and turns no badge.
            if MTRowLetter.retiredLetter(text) {
                Self.diagLine("transfer letter stashed silently mid=\(mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            // TWO LETTERS OF A GAME RING (29.09, MTChessLetter.rings): the invitation and the letter that ends the game wear
            // the chess words and name their game for the tap; a step an older build sent loud is stashed for the board
            // and swallowed here.
            if let chess = MTChessLetter.parse(text) {
                guard chess.rings else {
                    Self.diagLine("chess step stashed silently mid=\(mid.prefix(8))")
                    contentHandler(Self.quietFace())
                    return
                }
                content.userInfo["game"] = chess.game
                if chess.end != nil { content.userInfo["game_end"] = 1 }
            }
            // A GROUP'S WORD (MTGroup in the app, 05.10): a letter and an invitation wear the group's own face, the tap opens the
            // group; an answer to a letter is stashed for the app without a face.
            let group = Self.groupFace(rawText)
            if rawText.hasPrefix("\u{200B}\u{200B}GR:"), group == nil {
                Self.diagLine("group word stashed silently mid=\(mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            // The title is MY record of the person (the mirror), the letter's word only for a
            // stranger — see title(conv:envName:). A leading emoji is a face, not text: it goes
            // to the circle, the title stays clean.
            senderGlyph = envGlyph
            if senderGlyph.isEmpty, let f = Self.cleanEnvName(envName).first, MontanaAvatar.isEmoji(f) { senderGlyph = String(f) }
            content.title = group?.title ?? Self.title(conv: conv, envName: envName)
            content.body = group?.body ?? Self.bannerBody(text)
            if let group { openedQuiet = false; senderGlyph = ""; content.userInfo["mid"] = group.mid.isEmpty ? mid : group.mid }
            else { content.userInfo["mid"] = mid }     // the foreground judge suppresses a double by this
            if let room = Self.invitedRoom(rawText) { content.userInfo["room"] = room }   // the tap goes into the room (MTGroupRoom)
            convKey = group?.chat ?? conv
            content.threadIdentifier = convKey
            content.userInfo["chat"] = convKey   // the tap opens the EXISTING chat by conv, not a twin by from
            Self.applySettings(content, conv: convKey)
            Self.diagLine("banner shown mid=\(mid.prefix(8)) quiet=\(openedQuiet)")
            // The node box (7.2c): the push is the one surviving ring, so waiting envelopes
            // are collected on it too — time-boxed: the banner above is already composed and
            // must not become hostage to a broken box road (precedent 26.08 19:03: the scoop
            // stood FIRST, its chunk waits burned the ~30s budget, iOS killed the extension,
            // Apple's bare fallback showed, the letter inside the push went unprocessed).
            ready = Self.nativeFace(content, from: convKey, glyph: senderGlyph)
            _ = Self.fetchBoxSync(deadline: Self.within(6, of: began))
        } else if let envB64 = info["env"] as? String, let sealed = Data(base64Encoded: envB64), let sh = Self.openForShelf(sealed, at: Self.sealMoment(info)) {
            // A LETTER TO A PERSON ON THE SHELF (07.10, MTShelfPost): the sender's name, and under it whose the letter is; the tap
            // seats that person. Nothing is stashed in the inbox of the person seated: the letter stays on the node for the
            // shelf's own pickup. A service word rings nobody.
            if sh.text.hasPrefix("\u{200B}") || sh.text.hasPrefix("\u{2063}") {
                Self.diagLine("shelf word quiet seat=\(sh.seat) mid=\(sh.mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            var t = sh.name
            if t.hasPrefix("@") { t.removeFirst() }
            content.title = t.isEmpty ? "Montana" : MontanaAvatar.spokenName(t)
            content.subtitle = sh.seatName
            content.body = Self.bannerBody(sh.text)
            content.threadIdentifier = "seat:" + sh.seat
            content.userInfo["seat"] = sh.seat
            content.badge = nil
            Self.diagLine("shelf banner seat=\(sh.seat) mid=\(sh.mid.prefix(8))")
            contentHandler(content)
            return
        } else if let sc = Self.fetchBoxSync(deadline: Self.within(8, of: began)) {
            // The push's own envelope did not open (or is absent), but the box yielded
            // letters — the banner carries the LAST one collected: the class «notification
            // exists — no letter» is closed here too.
            var glyph = sc.glyph
            if glyph.isEmpty, let f0 = Self.cleanEnvName(sc.name).first, MontanaAvatar.isEmoji(f0) { glyph = String(f0) }
            let group = Self.groupFace(sc.text)   // a group's word wears the group's face here too (MTGroup in the app)
            if sc.text.hasPrefix("\u{200B}\u{200B}GR:"), group == nil {
                Self.diagLine("group word from the box stashed silently mid=\(sc.mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            if group != nil { glyph = "" }
            if let room = Self.invitedRoom(sc.text) { content.userInfo["room"] = room }   // the tap goes into the room (MTGroupRoom)
            content.title = group?.title ?? Self.title(conv: sc.conv, envName: sc.name)
            content.body = group?.body ?? Self.bannerBody(sc.text)
            if let chat = group?.chat ?? (sc.conv.isEmpty ? nil : sc.conv) {
                content.threadIdentifier = chat
                content.userInfo["chat"] = chat
                convKey = chat
                Self.applySettings(content, conv: chat)
            }
            senderGlyph = glyph
            openedMid = sc.mid
            openedQuiet = group == nil && Self.isQuietText(sc.text)
            cargoLetter = (sc.mid, sc.text)
            if sc.text.hasPrefix("\u{200B}\u{200B}RG:") {
                Self.diagLine("ring letter from the box stashed silently mid=\(sc.mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            if Self.serveMissedLetter(sc.text, mid: sc.mid, conv: sc.conv, name: sc.name, handler: contentHandler) { return }
            if MTRowLetter.retiredLetter(sc.text) {   // a transfer letter from the box rings nothing either (10.10.2026)
                Self.diagLine("transfer letter from the box stashed silently mid=\(sc.mid.prefix(8))")
                contentHandler(Self.quietFace())
                return
            }
            if let chess = MTChessLetter.parse(sc.text) {
                guard chess.rings else {
                    Self.diagLine("chess step from the box stashed silently mid=\(sc.mid.prefix(8))")
                    contentHandler(Self.quietFace())
                    return
                }
                content.userInfo["game"] = chess.game
                if chess.end != nil { content.userInfo["game_end"] = 1 }
            }
            Self.diagLine("banner from the box: mid=\(sc.mid.prefix(8))")
            ready = Self.nativeFace(content, from: convKey, glyph: senderGlyph)
        } else {
            // THIS BRANCH WAS SILENT, AND THE SILENCE COST A LETTER. Envelope unopened -> the
            // letter is NOT stored, yet the notification still shows with generic text: the
            // person sees «arrived», opens the conversation and finds nothing. Exactly that
            // case 20.08 19:29 — and there was nothing to dissect it with, because not one
            // line was written here. The cause is named by name: no envelope / base64 did
            // not parse / no pipe secret matched (the secret mirror is stale or never written).
            let envB64 = (info["env"] as? String) ?? ""
            let why: String
            if envB64.isEmpty { why = "no envelope in the push" }
            else if Data(base64Encoded: envB64) == nil { why = "envelope failed base64 len=\(envB64.count)" }
            else { why = "no pipe secret matched: secrets=\(Self.pipeSecretCount()) envelope=\(Data(base64Encoded: envB64)?.count ?? 0)B" }
            Self.diagLine("LETTER NOT STORED: \(why)")
        }
        // The badge with the app closed: the extension keeps the count (a carry-over of the
        // production mechanics), the app resets it on opening. A muted conversation does not
        // turn the badge. The badge is honest per mid: a repeated envelope of the same letter
        // (sender retry, push double) does not turn the count — the server model kept a
        // shown-ledger, so do we. The dictionary is ONE for app and extension ([C-1], server
        // model): the app is the authoritative writer (rewrites whole on every recount), the
        // NSE only adds. A second dictionary hoarded the count forever — the icon showed the
        // sum of all time.
        // ANY LETTER TO YOU IS A WINDOW TO SEND YOURS (18.09, the author's word). This process holds
        // the network for these seconds even when the app is gone: the loud letters waiting in the
        // shared queue knock now, by the sheet's proven road — time-boxed, after the banner is composed.
        Self.knockOutgoingSync(deadline: Self.within(6, of: began))
        // THE SMALL CARGO COMES WITH THE BANNER (29.09): the letter's pieces are laid onto the contour's shelf in this process's own
        // budget, so the app assembles the file at its next breath and asks no door. Big cargo, and a manifest on the node, are the app's.
        if let c = cargoLetter { Self.bringSmallCargoSync(mid: c.mid, text: c.text, began: began, deadline: Self.within(8, of: began)) }
        if !convKey.isEmpty, Self.isBlocked(convKey) {
            Self.diagLine("blocked conv=\(convKey.prefix(10)) — no banner")
            contentHandler(Self.quietFace())
            return
        }
        // A RESENT LETTER RINGS NOTHING (02.10, the critic): the ledger answered «already shown» for the badge alone and
        // the banner went out anyway; a letter the app landed live was never in it. Shown or held -- quiet.
        // QUIET IS THE LETTER'S OWN FACE, NEVER AN EMPTY ONE (02.10 15:04, T1 on 2062): without the filtering entitlement an
        // empty content is still shown, and the node names every ring of a letter by its mid (apns-collapse-id), so the
        // empty repeat REPLACED the banner shown a second earlier with a blank plate. The repeat hands over the same words,
        // passive: no sound, no badge, nothing new on the screen.
        let fresh = Self.firstTimeShown(openedMid)
        let held = MTHeldLetters.holds(openedMid)
        if !openedMid.isEmpty, !fresh || held {
            Self.diagLine("repeat mid=\(openedMid.prefix(8)) shown=\(!fresh) held=\(held) — quiet, same face")
            content.sound = nil
            content.badge = nil
            content.interruptionLevel = .passive
            Self.deliverWithAvatar(content, from: convKey, glyph: senderGlyph, handler: contentHandler)
            return
        }
        // A MUTED OR ARCHIVED CHAT SAYS NOTHING (MTQuietChats): the sound alone was taken, the banner, the vibration and the lit
        // screen stayed. An extension without the filtering entitlement cannot withhold a notification -- an empty content is
        // still shown -- so the letter is handed over passive: no banner over what the person is doing, no sound, no vibration,
        // no lit screen, no badge; it lies in the list alone.
        if !convKey.isEmpty, MTQuietChats.holds(convKey) {
            Self.diagLine("quiet conv=\(convKey.prefix(10)) — passive, no banner, no sound, no badge")
            content.sound = nil
            content.badge = nil
            content.interruptionLevel = .passive
            Self.deliverWithAvatar(content, from: convKey, glyph: senderGlyph, handler: contentHandler)
            return
        }
        // THE SHARE SHEET'S ORDER FOLLOWS THE LETTER (MTShareOrder): the chat goes up in the sheet's mirror as it goes up in the list.
        if !convKey.isEmpty, !openedQuiet { MTShareOrder.raise(convKey) }
        if !convKey.isEmpty, !openedQuiet {
            var counts: [String: Int] = [:]
            if let d = MontanaKeychain.get("unreadCounts"),
               let m = try? JSONDecoder().decode([String: Int].self, from: d) { counts = m }
            counts[convKey, default: 0] += 1
            if let d = try? JSONEncoder().encode(counts) { MontanaKeychain.set("unreadCounts", d) }
            content.badge = NSNumber(value: counts.values.reduce(0, +))
            Self.diagLine("badge conv=\(convKey.prefix(10)) total=\(counts.values.reduce(0, +)) src=nse")
        }
        Self.deliverWithAvatar(content, from: convKey, glyph: senderGlyph, handler: contentHandler)
    }

    // A long reference letter resolves synchronously (the extension lives until the content is
    // handed over). The node address comes from the keychain (the app writes it at launch):
    // configuration, not a hardcode.
    private static func resolveLongLetterSync(_ text: String) -> String? {
        guard let baseD = MontanaKeychain.get("wakeBase"),
              let baseS = String(data: baseD, encoding: .utf8),
              let d = text.dropFirst("\u{2063}LB:".count).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String],
              let bid = o["r"], let mkB64 = o["k"], let mk = Data(base64Encoded: mkB64),
              let url = URL(string: baseS + "/blob-get") else { return nil }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["bid": bid])
        let sem = DispatchSemaphore(value: 0)
        var sealed: Data? = nil
        URLSession.shared.dataTask(with: req) { d2, resp, _ in
            defer { sem.signal() }
            guard let d2, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
                  let b64 = obj["data"] as? String else { return }
            sealed = Data(base64Encoded: b64)
        }.resume()
        _ = sem.wait(timeout: .now() + 8)
        guard let sealed, let plain = openBlob(key: [UInt8](mk), sealed: sealed),
              let sep = plain.firstIndex(of: 0),
              let full = String(data: plain[plain.index(after: sep)...], encoding: .utf8), !full.isEmpty
        else { return nil }
        return full
    }

    // The person's notification settings (mirrored from the keychain: notifSound/notifPreview/
    // notifSender + mutedChats). The extension lives in the background — it reads the same
    // values the user sees on the Notifications screen.
    /// The caller's «missed call» letter: ONE banner per call across both processes ([C-1],
    /// the author's word 09.09). The seed notebook says whether this device saw the call ring
    /// or already rang for it — then silence; otherwise the one missed-call look, composed by
    /// MontanaMissedCall, the same the app's own ring serves. Returns true when the letter is handled.
    private static func serveMissedLetter(_ text: String, mid: String, conv: String, name: String,
                                          handler: @escaping (UNNotificationContent) -> Void) -> Bool {
        guard text.hasPrefix("\u{200B}\u{200B}MC:") else { return false }
        let (seed, video) = MontanaMissedCall.letter(text)
        if !seed.isEmpty {   // the bell of this call, if it still hangs, yields to the missed word
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["bell-" + MontanaMissedCall.tag(seed)])
        }
        if let st = MontanaMissedCall.state(seed) {
            diagLine("missed letter silent mid=\(mid.prefix(8)) seed=\(seed.prefix(8)) state=\(st)")
            handler(quietFace())
            return true
        }
        MontanaMissedCall.note(seed, "rang")
        _ = firstTimeShown(mid)
        let title = Self.title(conv: conv, envName: name)
        diagLine("missed banner mid=\(mid.prefix(8)) seed=\(seed.prefix(8))")
        let look = MontanaMissedCall.content(peer: conv, name: title, video: video)
        // THE ICON BADGE COUNTS THIS MISSED CALL (the author's word 18.09): one added to the
        // shared missed count (the app rewrites it with its own truth on waking), shown as the
        // unread letters plus the missed calls — the app's own sum.
        var missed = Int(String(data: MontanaKeychain.get("missedUnseen") ?? Data(), encoding: .utf8) ?? "") ?? 0
        missed += 1
        MontanaKeychain.set("missedUnseen", Data(String(missed).utf8))
        var unread = 0
        if let d = MontanaKeychain.get("unreadCounts"), let m = try? JSONDecoder().decode([String: Int].self, from: d) {
            unread = m.values.reduce(0, +)
        }
        if let c = look.mutableCopy() as? UNMutableNotificationContent {
            c.badge = NSNumber(value: unread + missed)
            diagLine("badge missed=\(missed) total=\(unread + missed) src=nse")
            handler(worded(c))
        } else {
            handler(worded(look))
        }
        return true
    }

    private static func prefOn(_ key: String) -> Bool {
        guard let d = MontanaKeychain.get(key), let b = d.first else { return true }  // no key = on by default
        return b != 0
    }
    /// A blocked person's letter raises nothing (Guideline 1.2): the app's block set, mirrored here.
    private static func isBlocked(_ conv: String) -> Bool {
        for key in ["blockedChats", "barredPeers"] {   // the person's own block and the network's bar
            if let d = MontanaKeychain.get(key), let arr = try? JSONDecoder().decode([String].self, from: d), arr.contains(conv) { return true }
        }
        return false
    }
    private static func applySettings(_ content: UNMutableNotificationContent, conv: String) {
        if !prefOn("notifSender") { content.title = "Montana" }          // hide the sender name
        // The person's own language, here too (13.09): the preview-off body stood as an English
        // literal while every other «New message» in this file goes through the catalog — a Russian
        // phone with previews hidden read English on every letter.
        if !prefOn("notifPreview") { content.body = String(localized: "New message", bundle: MTLanguage.bundle) }
        // The fold reaches the banner (Guideline 1.2): the app's filter switch is mirrored here.
        else if prefOn("objectionableFilterOn"), MontanaContentFilter.flags(content.body) { content.body = String(localized: "Hidden by the filter", bundle: MTLanguage.bundle) }
        if MTQuietChats.holds(conv) || !prefOn("notifSound") { content.sound = nil } // no sound
        else { content.sound = .default }
    }

    // Communication Notification: the sender's avatar on the left.
    // Requires IntentsSupported=[INSendMessageIntent] in Info.plist and INImage(imageData:) —
    // bytes inside the intent, since the extension has no App Group and INImage(url:) to a
    // private temp is unreadable to the renderer. Did not work (no entitlement) — degrade to
    // the attachment thumbnail.
    /// THE WHOLE WAKE HAS ONE BUDGET (the author's word 06.10.2026 23:5x MSK; T1 20:51Z on 2143: the box gave 26 letters, the diary
    /// held no line after it, the phone no crash and no memory event, and the banner went out as the bare composed plate without its
    /// person): every walk of the network ends by 22 s from the wake, whatever its own seconds.
    private static func within(_ seconds: TimeInterval, of began: Date) -> Date {
        min(Date().addingTimeInterval(seconds), began.addingTimeInterval(22))
    }
    private static func deliverWithAvatar(_ content: UNMutableNotificationContent, from: String,
                                          glyph: String, handler: @escaping (UNNotificationContent) -> Void) {
        handler(worded(nativeFace(content, from: from, glyph: glyph)))
    }
    /// THE CHAT'S OWN FACE, MADE AS SOON AS THE BANNER IS COMPOSED (06.10): the person's name and face in the communication style;
    /// the end of the wake hands it over, and so does the system's expiry (ready) -- never the bare plate. Nothing of the given
    /// content is changed.
    private static func nativeFace(_ content: UNMutableNotificationContent, from: String, glyph: String) -> UNNotificationContent {
        let display = content.title.isEmpty ? (from.isEmpty ? "Contact" : from) : content.title
        // Without a real name the communication intent is not built: the system would draw the
        // title from past donations (precedent «receiver's name instead of the sender's»).
        // An ordinary banner is more honest.
        if display == String(localized: "Contact", bundle: MTLanguage.bundle) || display == from { return content }
        // The face: the photo when there is one; else the circle with the glyph FROM THE
        // LETTER (the sender's callsign emoji, exactly their profile avatar); old envelopes
        // without a glyph — the mirror's old title.
        let faceSeed = fullTitle(for: from) ?? display
        let img = avatarData(for: from, glyph: glyph, display: faceSeed).flatMap { INImage(imageData: $0) }
        var nameComp = PersonNameComponents(); nameComp.nickname = display
        // The handle is «peer:<key>», NOT the bare key: the bare one collided with older
        // donations where the name was a nick or someone else's, and the system drew the title
        // from them (precedent «receiver's name»). The new unique handle matches only itself —
        // there is nothing to substitute.
        let handle = INPersonHandle(value: "peer:" + (from.isEmpty ? "0" : from), type: .unknown)
        let sender = INPerson(personHandle: handle, nameComponents: nameComp, displayName: display,
                              image: img, contactIdentifier: nil, customIdentifier: "peer:" + from,
                              isMe: false, suggestionType: .none)
        let me = INPerson(personHandle: INPersonHandle(value: "0", type: .unknown), nameComponents: nil,
                          displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil,
                          isMe: true, suggestionType: .none)
        let intent = INSendMessageIntent(recipients: [me], outgoingMessageType: .outgoingMessageText,
                                         content: content.body, speakableGroupName: INSpeakableString(spokenPhrase: display),
                                         conversationIdentifier: from, serviceName: nil, sender: sender, attachments: nil)
        if let img = img { intent.setImage(img, forParameterNamed: \.sender) }
        let interaction = INInteraction(intent: intent, response: nil); interaction.direction = .incoming
        interaction.groupIdentifier = from   // a deleted chat takes this donation with it
        interaction.donate { _ in }
        if let updated = (try? content.updating(from: intent)) as? UNMutableNotificationContent {
            // Insurance: after the system's assembly the title MUST remain the name from the
            // letter. Diverged — serve our own content without the communication style: an
            // honest name is worth more than the style.
            diagLine("ut=\(String(updated.title.prefix(12))) want=\(String(display.prefix(12)))")
            if updated.title != display { updated.title = display }
            return updated
        }
        guard let plain = content.mutableCopy() as? UNMutableNotificationContent else { return content }
        if let data = avatarData(for: from, glyph: glyph, display: display) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("av_\(UUID().uuidString).jpg")
            if (try? data.write(to: tmp)) != nil,
               let att = try? UNNotificationAttachment(identifier: "avatar", url: tmp, options: nil) {
                plain.attachments = [att]
            }
        }
        return plain
    }

    // The avatar: the real photo from the shared keychain (key av_<sha256(addr)>), else the drawn circle.
    private static func avatarData(for ref: String, glyph: String, display: String) -> Data? {
        if !ref.isEmpty {
            let key = "av_" + SHA256.hash(data: Data(ref.utf8)).map { String(format: "%02x", $0) }.joined()
            if let d = MontanaKeychain.get(key), !d.isEmpty { return d }
            // The photo from the list mirror; no photo — the circle: the glyph FROM THE LETTER
            // outranks the mirror (the sender's profile face, fresh with every letter), the
            // colour — the list's palette.
            var mirrorGlyph: String? = nil; var mirrorColor: String? = nil
            if let d = MontanaKeychain.get("shareChats"),
               let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] {
                let hit = arr.first(where: { $0["name"] == ref }) ?? arr.first(where: { $0["name"] == Self.lastOpened })
                if let t = hit?["thumb"], let img = Data(base64Encoded: t), !img.isEmpty { return img }
                mirrorGlyph = hit?["initial"]; mirrorColor = hit?["colorHex"]
            }
            let g = glyph.isEmpty ? (mirrorGlyph ?? "") : glyph
            if !g.isEmpty {
                return drawListCircle(glyph: g, colorHex: mirrorColor ?? MontanaAvatar.colorHex(ref))
            }
        }
        return drawAvatar(for: display)
    }

    /// The circle is the client's shared render (MontanaFace), pixel-for-pixel with the list.
    private static func drawListCircle(glyph: String, colorHex: String?) -> Data? {
        MontanaFace.circleImage(glyph: glyph, colorHex: colorHex).jpegData(compressionQuality: 0.9)
    }

    private static func drawAvatar(for name: String) -> Data? {
        // The last fallback is the same avatar as the profile: a black circle, a gold letter (SSOT).
        let initial = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return drawListCircle(glyph: initial, colorHex: nil)
    }

    /// Whether this is the letter's first showing: the shown-mid ledger (cap 300). An empty
    /// mid (envelope did not open) counts as first — better a spare badge than one silently eaten.
    private static func firstTimeShown(_ mid: String) -> Bool {
        guard !mid.isEmpty else { return true }
        var arr: [String] = []
        if let d = MontanaKeychain.get("nseShownMids"),
           let a = try? JSONDecoder().decode([String].self, from: d) { arr = a }
        guard !arr.contains(mid) else { return false }
        arr.append(mid)
        if arr.count > 300 { arr.removeFirst(arr.count - 300) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseShownMids", d) }
        return true
    }

    override func serviceExtensionTimeWillExpire() {
        if let h = handler, let c = ready ?? best { h(Self.worded(c)) }
    }

    // THE NOTIFICATION THAT SAYS NOTHING IS NEVER HANDED OVER (03.10, the author's word: empty notifications
    // on the lock screen). This extension holds no filtering entitlement (com.apple.developer.usernotifications
    // .filtering, granted by Apple on request), and without it an empty UNNotificationContent is not swallowed:
    // iOS shows it as a blank plate under the app's name, no title and no text. Seven roads handed exactly that
    // over: a ring letter the call screen serves, a game step, a blocked person at the envelope and at the end,
    // a missed call this device already rang, and the same two from the node box. Each of them now hands over
    // the push's own generic words, passive (no sound, no badge, the screen does not light), and writes the
    // request down, so the plate is taken off the list: by this process a moment later, by the next wake on
    // its first line, and by the app when it next comes to the foreground (MontanaWakePush.drainInbox).
    static var servingId = ""
    static func quietFace() -> UNNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "Montana"   // NOT-UI: the app's own name, the same word in every language
        c.body = String(localized: "New message", bundle: MTLanguage.bundle)
        c.sound = nil
        c.badge = nil
        c.interruptionLevel = .passive
        c.relevanceScore = 0
        c.threadIdentifier = "montana-quiet"   // NOT-UI: the group the quiet plates fall into, never shown
        let id = servingId
        diagLine("quiet face id=\(id.prefix(8)) — no blank plate")
        guard !id.isEmpty else { return c }
        var ids: [String] = []
        if let d = MontanaKeychain.get("nseQuietIds"), let a = try? JSONDecoder().decode([String].self, from: d) { ids = a }
        if !ids.contains(id) { ids.append(id) }
        if ids.count > 64 { ids.removeFirst(ids.count - 64) }
        if let d = try? JSONEncoder().encode(ids) { MontanaKeychain.set("nseQuietIds", d) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
        return c
    }
    /// The quiet plates written down by earlier wakes leave the list (the request being served stays).
    static func sweepQuiet() {
        guard let d = MontanaKeychain.get("nseQuietIds"), let ids = try? JSONDecoder().decode([String].self, from: d),
              !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids.filter { $0 != servingId })
        MontanaKeychain.set("nseQuietIds", Data())
    }
    /// Words on every plate handed over: a name that was only an emoji (the face goes to the circle, the title
    /// to MontanaAvatar.spokenName, which leaves nothing) or a text that resolved to nothing never reaches the
    /// screen bare. The node's own push words stand in: «Montana», «New message».
    static func worded(_ c: UNNotificationContent) -> UNNotificationContent {
        let blankTitle = c.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let blankBody = c.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard blankTitle || blankBody, let m = c.mutableCopy() as? UNMutableNotificationContent else { return c }
        if blankTitle { m.title = "Montana" }   // NOT-UI: the app's own name, the same word in every language
        if blankBody { m.body = String(localized: "New message", bundle: MTLanguage.bundle) }
        diagLine("blank words filled: title=\(blankTitle ? 1 : 0) body=\(blankBody ? 1 : 0)")
        return m
    }

    /// A letter from the envelope — into the shared keychain: the app on activation places it
    /// into the chat by the same reception road as any incoming. Mid dedup on both ends. Cap 200.
    private static func stashLetter(conv: String, mid: String, text: String, name: String, glyph: String,
                                    qt: String = "", qm: String = "", lp: String = "", sentAt: Double = 0) {
        guard !mid.isEmpty, !text.isEmpty else { return }
        var arr: [[String: String]] = []
        if let d = MontanaKeychain.get("nseInbox"),
           let a = try? JSONDecoder().decode([[String: String]].self, from: d) { arr = a }
        guard !arr.contains(where: { $0["m"] == mid }) else { return }
        var row = ["c": conv, "m": mid, "t": text]
        if sentAt > 0 { row["at"] = String(Int(sentAt)) }   // the moment the sender handed it to the node
        if !name.isEmpty { row["n"] = name }
        if !glyph.isEmpty { row["g"] = glyph }
        if !qt.isEmpty { row["qt"] = qt; row["qm"] = qm }
        if !lp.isEmpty { row["lp"] = lp }
        arr.append(row)
        if arr.count > 200 { arr.removeFirst(arr.count - 200) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseInbox", d) }
        // STAGE 9: the extension is a LANDING DOOR too — the list record must follow the
        // letter, or the first frame after a notification tap shows the previous message
        // (the record lagged by exactly the letters the app never saw). Written to the
        // shared keychain like the unread counts; the app merges it into the record at
        // cold start and clears it once the letters land through the ordinary door.
        // A LETTER THAT IS NOT A ROW DOES NOT WRITE A ROW (one vocabulary, MTRowLetter). The
        // record used to be written for every opened letter, service words included: for those
        // there was no word to show, so the row said «New message», the conversation was stamped
        // with the moment and one unread was counted — and the app rewrote all three a moment
        // later, in front of the person.
        guard MTRowLetter.changesRow(text) else { return }
        var ov: [String: [String: String]] = [:]
        if let od = MontanaKeychain.get("chatListOverlay"),
           let m = try? JSONDecoder().decode([String: [String: String]].self, from: od) { ov = m }
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        var rec = ["p": MTRowLetter.preview(text), "t": fmt.string(from: Date())]
        if let k = MTRowLetter.mediaKind(letter: text) { rec["k"] = k }   // the row's thumbnail kind (a voice's orb, a note's poster); the file comes with the app's door
        rec["id"] = mid
        // The cold frame shows the BOOK'S word (21.09): the envelope's only when the book holds none.
        if let known = mirroredName(for: conv) { rec["n"] = known }
        else if !name.isEmpty { rec["n"] = name }
        else if let n = ov[conv]?["n"], !n.isEmpty { rec["n"] = n }
        // A LANDING DOOR WRITES THE WHOLE ROW, not a third of it. Stage 9 taught this door the row's
        // TEXT; the ORDER and the COUNT were left to the ordinary door, so a person tapping a
        // notification met yesterday's order and yesterday's counters until the drain caught up (the
        // author's word 29.08: «came back» — it had never been closed, only its visible third). «at»
        // is when this letter landed (the order stamp), «u» is how many letters this door has
        // delivered and the app has not yet taken through the ordinary door. The moment this letter
        // landed, in the unit the app keeps the order in.
        rec["at"] = String(Int(Date().timeIntervalSince1970))
        rec["atm"] = String(Int(Date().timeIntervalSince1970 * 1000))
        rec["u"] = String((Int(ov[conv]?["u"] ?? "0") ?? 0) + 1)
        ov[conv] = rec
        if let od = try? JSONEncoder().encode(ov) { MontanaKeychain.set("chatListOverlay", od) }
    }

    /// A first-meeting envelope: [encapsulation 1088][mid\0 text\0 name\0 glyph\0 padding] =
    /// 1536, the key derived from the live card's invite (mirror «rdv:<invite>»).
    /// THE MINUTES A SEAL IS TRIED UNDER (the author's word 10.10.2026 12:5x MSK: «notifications reinforced concrete»). The seal's
    /// minute is the sender's; a push Apple held for a phone that was away arrives minutes or hours later, and tried only around
    /// this phone's own minute its envelope never opened -- the banner fell back to the box and, the box's newest letter being an
    /// old one, said nothing new. The push names the moment the node sent it ("at"); the seal stands at it or a few minutes
    /// before (the door walk). A short ladder, not MTNodeWire.openBoxed's day: the extension has seconds and many pipes.
    private static func sealMinutes(_ at: Int) -> [UInt64] {
        let now = UInt64(Date().timeIntervalSince1970) / 60
        var out: [UInt64] = [now &- 1, now, now &+ 1]
        guard 0 < at else { return out }
        let a = UInt64(at) / 60
        for w in [a, a &- 1, a &+ 1, a &- 2, a &- 3, a &- 4, a &- 5] where !out.contains(w) { out.append(w) }
        return out
    }

    private static func openRdvLetter(_ sealed: Data, at: Int)
        -> (mid: String, text: String, name: String, glyph: String, ct64: String, invite: String,
            conf: String)? {
        let secrets = pipeSecrets().filter { $0.key.hasPrefix("rdv:") }
        guard !secrets.isEmpty else { return nil }
        let minutes = sealMinutes(at)
        for (key, secret) in secrets {
            for w in minutes {
                guard let plain = openBlob(key: bodyKey(secret: secret, window: w), sealed: sealed),
                      plain.count > 1092 else { continue }
                let ct = plain.prefix(1088)
                var fields: [String] = []
                var rest = plain.dropFirst(1088)
                for _ in 0..<5 {
                    guard let z = rest.firstIndex(of: 0) else { fields.append(""); continue }
                    fields.append(String(data: rest[rest.startIndex..<z], encoding: .utf8) ?? "")
                    rest = rest[rest.index(after: z)...]
                }
                guard !fields[0].isEmpty, !fields[1].isEmpty else { continue }
                // Whichever seal opened it — that card is what the app tries: trying all of
                // them begot a phantom chat from another key's implicit-rejection garbage.
                return (fields[0], fields[1], fields[2], fields[3], Data(ct).base64EncodedString(),
                        String(key.dropFirst(4)), fields[4])
            }
        }
        return nil
    }

    /// A LETTER TO A PERSON ON THE SHELF (07.10, MTShelfPost): opened with the keys the app mirrors for the persons waiting on
    /// this phone's shelf (MTNodeWire.ShelfEar), shown with whose it is, and left on the node -- the shelf's own pickup files
    /// it in that person's inbox, and the landing door opens it at their lift.
    private static func openForShelf(_ sealed: Data, at: Int) -> (seat: String, seatName: String, mid: String, text: String, name: String)? {
        let minutes = sealMinutes(at)
        for ear in MTNodeWire.shelfEars() {
            for (key, secret) in ear.keys {
                for w in minutes {
                    guard let plain = openBlob(key: bodyKey(secret: secret, window: w), sealed: sealed) else { continue }
                    let rdv = key.hasPrefix("rdv:")
                    guard !rdv || plain.count > 1092 else { continue }
                    let f = parseFields(rdv ? Data(plain.dropFirst(1088)) : plain)
                    guard !f[0].isEmpty, !f[1].isEmpty else { continue }
                    return (ear.seat, ear.name, f[0], f[1], f[2])
                }
            }
        }
        return nil
    }

    /// The first-meeting letter — into the same box, with the encapsulation: the app begets the pipe from it.
    private static func stashRdv(mid: String, text: String, name: String, glyph: String, ct64: String,
                                 invite: String, conf: String) {
        guard !mid.isEmpty, !text.isEmpty else { return }
        var arr: [[String: String]] = []
        if let d = MontanaKeychain.get("nseInbox"),
           let a = try? JSONDecoder().decode([[String: String]].self, from: d) { arr = a }
        guard !arr.contains(where: { $0["m"] == mid }) else { return }
        var row = ["c": "rdv", "m": mid, "t": text, "k": ct64, "i": invite, "cf": conf]
        if !name.isEmpty { row["n"] = name }
        if !glyph.isEmpty { row["g"] = glyph }
        arr.append(row)
        if arr.count > 200 { arr.removeFirst(arr.count - 200) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseInbox", d) }
    }

    private static func openWithOwnPipes(_ sealed: Data, at: Int)
        -> (conv: String, mid: String, text: String, name: String, glyph: String, qt: String, qm: String, lp: String)? {
        let secrets = pipeSecrets()
        guard !secrets.isEmpty else { return nil }
        let minutes = sealMinutes(at)
        for (conv, secret) in secrets {
            for w in minutes {
                let key = bodyKey(secret: secret, window: w)
                if let plain = openBlob(key: key, sealed: sealed), plain.contains(0) {
                    // Fields split by 0x00: mid ‖ text ‖ sender name ‖ face glyph ‖ padding.
                    // An old envelope carried two fields — name and glyph read empty, fallback below.
                    var fields: [String] = []; var rest = plain[plain.startIndex...]
                    while fields.count < 7 {
                        guard let z = rest.firstIndex(of: 0) else { fields.append(String(data: rest, encoding: .utf8) ?? ""); break }
                        fields.append(String(data: rest[..<z], encoding: .utf8) ?? "")
                        rest = rest[rest.index(after: z)...]
                    }
                    while fields.count < 7 { fields.append("") }
                    if !fields[1].isEmpty { return (conv, fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]) }
                }
            }
        }
        return nil
    }

    // ── THE NODE BOX (7.2c): the ring wakes — the extension collects ALL waiting envelopes ──
    // APNs keeps one last push; letters live in the node box, and this is the pickup. Dedup in stash.
    // The wire formulas live in MTNodeWire (the one owner, canon-held) — references, not
    // frozen copies (SSOT-CONSOLIDATE, the author's word 29.08).
    private static func convW(_ secret: Data, window: UInt64) -> String { MTNodeWire.convW(secret, window: window) }
    private static func rdvConvW(_ invite: Data, window: UInt64) -> String { MTNodeWire.rdvConvW(invite, window: window) }
    private static func subId(_ conv: String, ref: String) -> String { MTNodeWire.subId(conv, ref: ref) }
    private static func b64urlData(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
    private static func parseFields(_ plain: Data) -> [String] {
        var fields: [String] = []; var rest = plain[plain.startIndex...]
        while fields.count < 7 {
            guard let z = rest.firstIndex(of: 0) else {
                fields.append(String(data: rest, encoding: .utf8) ?? ""); break
            }
            fields.append(String(data: rest[rest.startIndex..<z], encoding: .utf8) ?? "")
            rest = rest[rest.index(after: z)...]
        }
        while fields.count < 7 { fields.append("") }
        return fields
    }

    /// Collect the node box synchronously (the extension lives until the content is handed
    /// over). Returns the last stored letter — the banner carries IT when the push's own
    /// envelope did not open: an empty «arrived, yet nothing» banner is forbidden by construction.
    private static func fetchBoxSync(deadline: Date) -> (conv: String, mid: String, text: String, name: String, glyph: String)? {
        guard let baseD = MontanaKeychain.get("wakeBase"), let baseS = String(data: baseD, encoding: .utf8),
              let refD = MontanaKeychain.get("wakeMyAddr"), let ref = String(data: refD, encoding: .utf8),
              !ref.isEmpty, let url = URL(string: baseS + "/fetch") else { return nil }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        let secrets = pipeSecrets()
        guard !secrets.isEmpty else { return nil }
        var secretOf: [String: Data] = [:]; var rdvLabels = Set<String>()
        var invOf: [String: String] = [:]   // label -> invite: whichever seal, that card is tried
        var chatOf: [String: String] = [:]
        var subs: [String] = []; var sids: [String] = []
        let w0 = UInt64(Date().timeIntervalSince1970) / 86400
        for (key, secret) in secrets {
            if key.hasPrefix("rdv:") {
                // The label derives from the invite ITSELF — the mirror key carries it.
                guard let inv = b64urlData(String(key.dropFirst(4))) else { continue }
                for w in (w0 - 8)...(w0 + 1) {
                    let cw = rdvConvW(inv, window: w)
                    secretOf[cw] = secret; rdvLabels.insert(cw)
                    invOf[cw] = String(key.dropFirst(4))
                    subs.append(cw); sids.append(subId(cw, ref: ref))
                }
            } else {
                if isBlocked(key) { continue }   // a blocked person's letters stay in the box (15.09)
                for w in (w0 - 8)...(w0 + 1) {
                    let cw = convW(secret, window: w)
                    secretOf[cw] = secret; chatOf[cw] = key
                    subs.append(cw); sids.append(subId(cw, ref: ref))
                }
            }
        }
        guard !subs.isEmpty else { return nil }
        var last: (String, String, String, String, String)? = nil
        var got = 0
        for start in stride(from: 0, to: subs.count, by: 128) {   // 512 labels exceed the node body limit of 64KiB (413)
            // The deadline rules the walk: the extension lives ~30 seconds, and a broken box
            // road must cost seconds, not the whole budget (precedent 26.08 19:03).
            if Date() >= deadline { diagLine("box: deadline — walk stopped"); break }
            let end = min(start + 128, subs.count)
            for _ in 0..<2 {   // extension budget: at most two pages of 128 letters
                var req = URLRequest(url: url); req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.httpBody = try? JSONSerialization.data(withJSONObject:
                    ["subs": Array(subs[start..<end]), "sids": Array(sids[start..<end])])
                let sem = DispatchSemaphore(value: 0)
                var letters: [[String: Any]] = []
                var pageOk = false
                URLSession.shared.dataTask(with: req) { d, resp, _ in
                    defer { sem.signal() }
                    guard let d, (resp as? HTTPURLResponse)?.statusCode == 200,
                          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let ls = o["letters"] as? [[String: Any]] else { return }
                    pageOk = true
                    letters = ls
                }.resume()
                _ = sem.wait(timeout: .now() + min(3, max(0.5, deadline.timeIntervalSinceNow)))
                if !pageOk { diagLine("box: page refused — walk stopped"); return last }
                for l in letters {
                    guard let cw = l["c"] as? String, let e = l["e"] as? String,
                          let sealed = Data(base64Encoded: e), let secret = secretOf[cw] else { continue }
                    // The envelope wears the SEND minute; the node names the minute it TOOK the
                    // letter — the one opener walks back from it (MTNodeWire, 16.09).
                    let atS = UInt64(max(0, l["at"] as? Int ?? 0))
                    guard let opened = MTNodeWire.openBoxed(sealed, secret: secret, at: atS) else {
                        diagLine("box: envelope did not open within a day"); continue
                    }
                    let pl = opened.plain
                    if opened.back > 1 { diagLine("box: late seal \(opened.back) min") }
                    if rdvLabels.contains(cw) {
                        guard pl.count > 1092 else { continue }
                        let ct = pl.prefix(1088)
                        let f = parseFields(pl.dropFirst(1088))
                        guard !f[0].isEmpty, !f[1].isEmpty else { continue }
                        let text = f[1].hasPrefix("\u{2063}LB:") ? (resolveLongLetterSync(f[1]) ?? f[1]) : f[1]
                        stashRdv(mid: f[0], text: text, name: f[2], glyph: f[3],
                                 ct64: Data(ct).base64EncodedString(), invite: invOf[cw] ?? "", conf: f[4])
                        last = ("", f[0], text, f[2], f[3]); got += 1
                    } else if let chat = chatOf[cw] {
                        let f = parseFields(pl)
                        guard !f[0].isEmpty, !f[1].isEmpty else { continue }
                        let text = f[1].hasPrefix("\u{2063}LB:") ? (resolveLongLetterSync(f[1]) ?? f[1]) : f[1]
                        let ck = chatKey(for: chat)
                        stashLetter(conv: ck, mid: f[0], text: text, name: f[2], glyph: f[3],
                                    qt: f[4], qm: f[5], lp: f[6], sentAt: Double(Int(atS) - opened.back * 60))
                        // A STEP OF A GAME IS NOT THE BANNER'S LETTER (29.09): stashed for the board, it never titles the banner.
                        if MTChessLetter.isStep(text), MTChessLetter.parse(text)?.rings != true { got += 1; continue }
                        last = (ck, f[0], text, f[2], f[3]); got += 1
                    }
                }
                if letters.count < 128 { break }
            }
        }
        if got > 0 { diagLine("box: collected \(got)") }
        return last
    }

    // ── THE SMALL CARGO, LAID BY THE LANDING DOOR (29.09) ──
    /// The pieces of a media letter whose manifest rides inline: at most `cargoPieces` of them, asked one by one at the elected
    /// door within the deadline and laid sealed onto the shelf (MontanaHandoff.layBlob). A piece already there is not asked; a
    /// letter with more pieces, or with its manifest on the node (mref), is the app's. Measured 29.09: seventeen pieces of
    /// 8.6 MB came in 2.2 s, five pieces in 3.5 s with the assembly — the budget here is seconds, the wait it closes was
    /// twenty-one minutes. The diary names what was laid, so «the video waited for the app» is told from «the door had none».
    private static let cargoPieces = 8
    private static func bringSmallCargoSync(mid: String, text: String, began: Date, deadline: Date) {
        let mark = "\u{200B}\u{200B}MD:"
        guard text.hasPrefix(mark), let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let chunks = o["chunks"] as? [[String: Any]] else { return }
        let bids = chunks.compactMap { $0["bid"] as? String }
        guard !bids.isEmpty, bids.count == chunks.count else { return }
        guard bids.count <= cargoPieces else { diagLine("cargo: mid=\(mid.prefix(8)) pieces=\(bids.count) — the app's road"); return }
        let missing = bids.filter { !MontanaHandoff.hasBlob($0) }
        guard !missing.isEmpty else { diagLine("cargo: mid=\(mid.prefix(8)) pieces=\(bids.count) on the shelf already"); return }
        let doors = Array(MTNodeWire.electedFirst(MTNodeWire.mirroredDoors()).prefix(2))
        guard !doors.isEmpty else { return }
        let stop = min(deadline, began.addingTimeInterval(22))   // the process lives ~30 s; the banner is handed over after this
        let t0 = Date()
        var laid = 0, bytes = 0
        for bid in missing {
            if Date() >= stop { break }
            var got: Data? = nil
            for door in doors {
                let left = stop.timeIntervalSinceNow
                if left < 0.5 { break }
                guard let url = URL(string: door + "/blob-get") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                var req = URLRequest(url: url); req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.timeoutInterval = min(4, left)
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["bid": bid])
                let sem = DispatchSemaphore(value: 0)
                var sealed: Data? = nil
                URLSession.shared.dataTask(with: req) { d2, resp, _ in
                    defer { sem.signal() }
                    guard let d2, (resp as? HTTPURLResponse)?.statusCode == 200,
                          let obj = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
                          let b64 = obj["data"] as? String else { return }
                    sealed = Data(base64Encoded: b64)
                }.resume()
                _ = sem.wait(timeout: .now() + min(4.5, max(0.5, left)))
                if let s = sealed, !s.isEmpty { got = s; break }
            }
            guard let got, MontanaHandoff.layBlob(bid, got) else { continue }
            laid += 1; bytes += got.count
        }
        diagLine("cargo: mid=\(mid.prefix(8)) laid=\(laid)/\(missing.count) of \(bids.count) bytes=\(bytes) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
    }

    // ── THE LANDING DOOR SENDS (18.09): the shared outgoing queue, knocked from here ──
    /// The pipe may live under a local name (ref) while the queue names the chat key — the alias
    /// dictionary walks both ways, as the sheet's sender does.
    private static func pipeSecret(for conv: String, in m: [String: Data]) -> Data? {
        if let s = m[conv] { return s }
        if let ad = MontanaKeychain.get("nsePipeAlias"),
           let alias = try? JSONDecoder().decode([String: String].self, from: ad) {
            if let ref = alias.first(where: { $0.value == conv })?.key, let s = m[ref] { return s }
            if let chat = alias[conv], let s = m[chat] { return s }
        }
        return nil
    }
    private final class KnockBox: @unchecked Sendable { var k: MTNodeWire.Knock? = nil }
    /// Every loud letter still waiting in the shared queue knocks at the elected door — at most six,
    /// oldest first, inside the deadline; a call word and a missed word are the app's alone, a
    /// blocked person's letter does not ride. The ledger tells the app which letters a node took;
    /// the app marks them «sent» on its next drain and never learns of a knock that failed — the
    /// letter simply keeps its place. A letter that does not fit the envelope and carries no
    /// reference is the app's too (the blob road is not here).
    private static func knockOutgoingSync(deadline: Date) {
        guard case .items(let items) = MTOutbox.read(), !items.isEmpty else { return }
        guard let refD = MontanaKeychain.get("wakeMyAddr"), let twinRef = String(data: refD, encoding: .utf8), !twinRef.isEmpty else { return }
        let secrets = pipeSecrets()
        let name = MontanaKeychain.get("wakeMyName").flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let glyph = MontanaKeychain.get("wakeMyGlyph").flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let doors = Array(MTNodeWire.electedFirst(MTNodeWire.mirroredDoors()).prefix(2))
        let loud = items.filter {
            $0.kind == .letter && !$0.silent && !isQuietText($0.text)
                && !$0.text.hasPrefix("\u{200B}\u{200B}RG:") && !$0.text.hasPrefix("\u{200B}\u{200B}MC:")
                && !isBlocked($0.chat)
        }.sorted { $0.since < $1.since }
        guard !loud.isEmpty, !doors.isEmpty else { return }
        var tried = 0, boxed = 0, skipped = 0
        let t0 = Date()
        for it in loud.prefix(6) {
            if Date() >= deadline { break }
            guard let secret = pipeSecret(for: it.to, in: secrets),
                  let plain = MTNodeWire.padEnvelope(MTNodeWire.letterHead(mid: it.mid, text: it.wire ?? it.text, name: name, glyph: glyph,
                                                                            quoteText: it.qt, quoteMid: it.qm)) else { skipped += 1; continue }
            tried += 1
            let sem = DispatchSemaphore(value: 0)
            let box = KnockBox()
            Task.detached {
                box.k = await MTNodeWire.knockLetter(secret: secret, twinRef: twinRef, mid: it.mid, plain: plain, doors: doors, deadline: deadline)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + max(0.5, deadline.timeIntervalSinceNow))
            let k = box.k
            if let k, k.boxed { boxed += 1; MTOutbox.noteExtensionKnock(it.mid) }
            diagLine("out: mid=\(it.mid.prefix(8)) code=\(k?.code ?? -2) woken=\(k?.woken ?? -1) walked=\(k?.walked ?? 0)")
        }
        diagLine("outgoing: queued=\(items.count) loud=\(loud.count) tried=\(tried) boxed=\(boxed) skipped=\(skipped) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
    }

    // The body key and the core open live in MTNodeWire (the one owner) — references.
    private static func bodyKey(secret: Data, window: UInt64) -> [UInt8] { MTNodeWire.bodyKey(secret: secret, window: window) }
    private static func openBlob(key: [UInt8], sealed: Data) -> Data? { MTNodeWire.openBlob(key: key, sealed: sealed) }

    /// The key the chat lives under in the mirrors: the pipe may have opened under a local
    /// name (ref) while name/avatar/mute/tap key by the chat key. The app writes the
    /// dictionary (mirrorSecrets).
    /// Banner diagnostics — into the keychain (last 6); the app prints them to the trace on activation.
    /// How many pipe secrets the extension sees. Zero means the mirror was never written or
    /// is unavailable — then not one letter from a push can be opened, and that must be said aloud.
    static func pipeSecretCount() -> Int { pipeSecrets().count }

    private static let liveIso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    /// THE BELL IS HEARD (the author's word 10.10.2026 12:5x MSK: «notifications reinforced concrete»). Apple keeps one stored
    /// push per app for a phone that is away, and a silent push sent after the letter's bell took its place. The node keeps this
    /// token's last bell loud until this word reaches it -- every door at once, since the bell came from one of them.
    private static func tellHeard(_ mid: String) {
        guard !mid.isEmpty, let tok = MontanaKeychain.get("wakeOwnToken").flatMap({ String(data: $0, encoding: .utf8) }), !tok.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["token": tok, "mids": [mid]]) else { return }
        for b in Set(MTNodeWire.mirroredDoors()) {
            guard let u = URL(string: b + "/heard") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: u); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = 4
            req.httpBody = data
            URLSession.shared.dataTask(with: req).resume()   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        }
    }
    /// The seal stands at the bell's first sending: a bell sent again (the node's kept bell, "sat") names that moment.
    private static func sealMoment(_ info: [AnyHashable: Any]) -> Int { (info["sat"] as? Int) ?? (info["at"] as? Int) ?? 0 }

    private static func shipLive(_ line: String) {
        guard let dg = MontanaKeychain.get("diagId").flatMap({ String(data: $0, encoding: .utf8) }), !dg.isEmpty else { return }
        let stamped = liveIso.string(from: Date()) + "|0|nse_live|-|t=" + MTNodeWire.clock() + " " + line
        let body: [String: Any] = ["dg": dg, "file": "trace",
                                   // The device names itself as the app does (MTNodeWire, 25.09): «nse» as the model let the
                                   // diaries machine read a phone's folder as an extension.
                                   "dev": ["model": MTNodeWire.deviceModel(), "ios": MTNodeWire.osVersion(), "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
                                           "tz": TimeZone.current.secondsFromGMT(), "lang": MTNodeWire.screenLang(), "skew_ms": 0],
                                   "lines": [stamped]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let doors = MTNodeWire.mirroredDoors()
        Task.detached(priority: .utility) {
            for b in doors {
                guard let u = URL(string: b + "/diag-put") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
                var req = URLRequest(url: u); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.timeoutInterval = 4
                req.httpBody = data
                guard let (_, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                      (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                return
            }
        }
    }
    private static func diagLine(_ line: String) {
        var arr: [String] = []
        if let d = MontanaKeychain.get("nseDiag"), let a = try? JSONDecoder().decode([String].self, from: d) { arr = a }
        // The moment the breath was drawn rides with it: the app drains these lines at its next
        // foreground, and without the moment «when did Apple hand the push over» was
        // unknowable (13.09: a missed-call banner seen, its arrival time nowhere).
        // A clock, not an epoch: the diary hides long digit runs as addresses (13.09: «t=1757775013»
        // came out as «t=a:6ab1d3»); an all-digit hh:mm:ss is a clock to the scrubber and survives.
        arr.append("t=" + MTNodeWire.clock() + " " + line); if arr.count > 24 { arr.removeFirst(arr.count - 24) }
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseDiag", d) }
    }

    private static func diag(opened: String, ui: String, envName: String, envGlyph: String) {
        func has(_ key: String) -> Int { (MontanaKeychain.get(key)?.isEmpty == false) ? 1 : 0 }
        var aliasN = 0
        if let d = MontanaKeychain.get("nsePipeAlias"),
           let m = try? JSONDecoder().decode([String: String].self, from: d) { aliasN = m.count }
        var titleHit = 0; var thumbHit = 0
        if let d = MontanaKeychain.get("shareChats"),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] {
            if let hit = arr.first(where: { $0["name"] == ui }) { titleHit = 1; thumbHit = (hit["thumb"] != nil) ? 1 : 0 }
            else if arr.contains(where: { $0["name"] == opened }) { titleHit = 2 }
        }
        let userHit = 0   // nick book retired from profiles — diagnostics keep the column shape
        let avKeyUi = "av_" + SHA256.hash(data: Data(ui.utf8)).map { String(format: "%02x", $0) }.joined()
        var tPrefix = "-"; var by = "-"
        if let d = MontanaKeychain.get("shareChats"),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]],
           let hit = arr.first(where: { $0["name"] == ui }) ?? arr.first(where: { $0["name"] == opened }) {
            tPrefix = String((hit["title"] ?? "-").prefix(12)); by = hit["by"] ?? "-"
        }
        let line = "op=\(opened.prefix(10)) ui=\(ui.prefix(10)) alias=\(aliasN) title=\(titleHit):\(tPrefix) by=\(by) thumb=\(thumbHit) user=\(userHit) av=\(has(avKeyUi)) nm=\(envName.isEmpty ? "-" : String(envName.prefix(12))) g=\(envGlyph.isEmpty ? "-" : envGlyph)"
        diagLine(line)   // one funnel for every breath: the moment rides with this line too
    }

    private static func chatKey(for opened: String) -> String {
        guard let d = MontanaKeychain.get("nsePipeAlias"),
              let m = try? JSONDecoder().decode([String: String].self, from: d),
              let alias = m[opened] else { return opened }
        return alias
    }

    nonisolated(unsafe) static var lastOpened: String = ""   // the opening key — a second chance for the mirror lookup

    private static func pipeSecrets() -> [String: Data] {
        guard let d = MontanaKeychain.get("nsePipeSecrets"),
              let m = try? JSONDecoder().decode([String: Data].self, from: d) else { return [:] }
        return m
    }

    private static func looksLikeRef(_ s: String) -> Bool { s.hasPrefix("mt") && s.count > 20 && !s.contains(" ") }

    /// The chat's original title (as in the chat list, with the callsign emoji) — for the face circle.
    private static func fullTitle(for conv: String) -> String? {
        if let d = MontanaKeychain.get("shareChats"),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]],
           let hit = arr.first(where: { $0["name"] == conv }) ?? arr.first(where: { $0["name"] == Self.lastOpened }),
           let t = hit["title"], !t.isEmpty, !looksLikeRef(t) { return t }
        return nil
    }

    /// The name THIS DEVICE gave the person, as the chat list shows it: the app writes its
    /// resolved title (a rename, the contact card, else the declared name) into the mirror.
    /// `nil` when the mirror holds no row or only the neutral caption — a stranger.
    /// `by` = "me": only a name THIS DEVICE gave them (a rename, the card); nil: any name the
    /// mirror holds. A row without the mark is an older build's row — read as their own word.
    private static func mirroredName(for conv: String, by: String? = nil) -> String? {
        if let d = MontanaKeychain.get("shareChats"),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]],
           let hit = arr.first(where: { $0["name"] == conv }) ?? arr.first(where: { $0["name"] == Self.lastOpened }),
           by == nil || hit["by"] == by,
           let t = hit["title"], !t.isEmpty, !looksLikeRef(t), t != String(localized: "Correspondent", bundle: MTLanguage.bundle) {
            var clean = t
            if clean.hasPrefix("@") { clean.removeFirst() }   // the @ is always excess in a banner
            return stripLeadingEmoji(clean)
        }
        return nil
    }
    /// The envelope's name without the leading @ — the raw word, for the face glyph alone.
    private static func cleanEnvName(_ envName: String) -> String {
        var t = envName
        if t.hasPrefix("@") { t.removeFirst() }
        return t
    }
    /// MY RECORD FIRST (the author's word 18.09): the banner's title is the name this device gave
    /// the person; the letter's own word is the title only for a stranger the mirror holds no row
    /// for. Before, the letter's word stood first here while the app's own banner read the book —
    /// one person, two names, by the road the banner took.
    /// WHO NAMED THEM decides the order (the author's word 18.09): named by me — my word stands over
    /// the letter; named by themselves — the letter carries their freshest word (a self-rename a
    /// second ago), the mirror only echoes the last one it heard.
    private static func title(conv: String, envName: String) -> String {
        // THE BOOK'S ANSWER FIRST, WHOEVER NAMED THEM (21.09, the critic): the mirror is the book's word
        // — my rename, else the freshest word the person spoke; the letter's own word is at best as
        // fresh and, for a letter that slept in the box, older. It titles a stranger only.
        if !conv.isEmpty, let known = mirroredName(for: conv) { return known }
        let t = cleanEnvName(envName)
        if !t.isEmpty { return MontanaAvatar.spokenName(t) }
        // No nick exists in the profile; the address never enters the title.
        return conv.isEmpty ? "Montana" : String(localized: "Contact", bundle: MTLanguage.bundle)
    }

    /// The callsign emoji is a face, not a name: the leading emoji goes to the avatar (the
    /// circle draws exactly it), the title stays a clean word.
    private static func stripLeadingEmoji(_ t: String) -> String { MontanaAvatar.spokenName(t) }   // client SSOT [C-1]

    /// A quiet service letter (receipt, typing, draft, profile, deletion): the badge must not
    /// grow on it. New senders do not ring these at all; this guards against older builds.
    private static func isQuietText(_ t: String) -> Bool {
        if MTChessLetter.isStep(t) { return true }   // a step of a game turns no badge: the board is its reader (29.09)
        if MTRowLetter.retiredLetter(t) { return true }   // a transfer letter turns no badge: the app buries it unread (10.10.2026)
        if t.hasPrefix("\u{200B}\u{200B}VC:") || t.hasPrefix("\u{200B}\u{200B}MD:")
            || t.hasPrefix("\u{200B}\u{200B}RG:") || t.hasPrefix("\u{200B}\u{200B}MC:") { return false }   // voice, media, call, missed call — loud
        return t.hasPrefix("\u{2063}") || t.hasPrefix("\u{2064}") || t.hasPrefix("\u{200B}")
    }

    /// A GROUP'S WORD (MTGroup in the app, 05.10): a letter's face is its group's title over its speaker's name and words -- a
    /// channel's post speaks as the channel -- and an invitation's face names the group it opens. Nil for an answer to a letter
    /// and for anything unreadable: those are stashed without a face.
    private static func groupFace(_ raw: String) -> (title: String, body: String, chat: String, mid: String)? {
        let mark = "\u{200B}\u{200B}GR:"
        guard raw.hasPrefix(mark), let d = String(raw.dropFirst(mark.count)).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = o["t"] as? String, let g = o["g"] as? String, !g.isEmpty else { return nil }
        let title = ((o["ti"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let chat = "grp:" + g   // COMPAT-LOCAL: the group's feed key on this phone (MTGroup.keyHead), never a word on the wire
        let channel = (o["k"] as? String) == "c"
        switch t {
        case "say":
            guard let tx = o["tx"] as? String, !tx.isEmpty else { return nil }
            let words = bannerBody(tx)
            let who = ((o["n"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, channel || who.isEmpty ? words : who + ": " + words, chat, (o["id"] as? String) ?? "")
        case "inv":
            let body = channel ? String(localized: "You were added to the channel", bundle: MTLanguage.bundle)
                               : String(localized: "You were added to the group", bundle: MTLanguage.bundle)
            return (title, body, chat, "")
        case "room":
            // A ROOM'S INVITATION (MTGroupRoom, 07.10): it is carried to the seats it names alone (ts), so this phone is one of
            // them; the tap opens the group, where the bar over the chat is the way in. Every other room word stays silent.
            guard o["ts"] is [Any], let tx = o["tx"] as? String, let td = tx.data(using: .utf8),
                  let e = try? JSONSerialization.jsonObject(with: td) as? [String: Any], (e["e"] as? String) == "ask" else { return nil }
            guard roomMayRing(chat) else { return nil }   // [I-15] one group's invitations ring once in two minutes
            let who = ((o["n"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = who.isEmpty ? String(localized: "Correspondent", bundle: MTLanguage.bundle) : who
            let body: String
            if (e["m"] as? String) == "live" {
                body = String(localized: "\(shown) invites you to a live stream", bundle: MTLanguage.bundle)
            } else if (e["v"] as? Int) == 1 {
                body = String(localized: "\(shown) invites you to a video chat", bundle: MTLanguage.bundle)
            } else {
                body = String(localized: "\(shown) invites you to a voice chat", bundle: MTLanguage.bundle)
            }
            return (title, body, chat, (o["id"] as? String) ?? "")
        default:
            return nil
        }
    }

    /// The room a group's invitation names (its id), so the banner's tap goes straight into it; nil for every other word.
    private static func invitedRoom(_ raw: String) -> String? {
        let mark = "\u{200B}\u{200B}GR:"
        guard raw.hasPrefix(mark), let d = String(raw.dropFirst(mark.count)).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (o["t"] as? String) == "room",
              let tx = o["tx"] as? String, let td = tx.data(using: .utf8),
              let e = try? JSONSerialization.jsonObject(with: td) as? [String: Any], (e["e"] as? String) == "ask",
              let r = e["r"] as? String, r.count == 32 else { return nil }
        return r
    }

    /// [I-15] A GROUP'S ROOM INVITATIONS RING ONCE IN TWO MINUTES (MTGroupRoom.askerPause, the app's own measure): however many
    /// rooms a member of the group opens and invites this phone to, the banners do not follow one another; the bar over the chat
    /// still shows the room. The ledger is this person's (nseRoomRang), ten minutes deep.
    private static func roomMayRing(_ chat: String) -> Bool {
        var rang: [String: Double] = [:]
        if let d = MontanaKeychain.get("nseRoomRang"), let m = try? JSONDecoder().decode([String: Double].self, from: d) { rang = m }
        let now = Date().timeIntervalSince1970
        rang = rang.filter { now - $0.value < 600 }
        if let at = rang[chat], now - at < 120 { return false }
        rang[chat] = now
        if let d = try? JSONEncoder().encode(rang) { MontanaKeychain.set("nseRoomRang", d) }
        return true
    }

    // The banner's words: the one function the app's banner door reads too (MTRowLetter.bannerWords, 06.10).
    private static func bannerBody(_ t: String) -> String {
        MTRowLetter.bannerWords(t, revealCaption: false) ?? String(localized: "New message", bundle: MTLanguage.bundle)
    }
}
