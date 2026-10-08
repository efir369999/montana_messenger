//  MontanaMissedCall.swift — THE missed-call banner, one birth per call ([C-1]).
//  Compiled into the app AND the notification extension: the seed notebook in the shared
//  keychain and the one look of the banner, so whichever process learns of the call first
//  rings, and the other stays silent.

import Foundation
import UserNotifications
import UIKit
import Intents
import CryptoKit

enum MontanaMissedCall {
    // ── THE missed-call banner: ONE birth per call across the app and the extension ([C-1]) ──
    // A missed call has three roads to a person's eyes — the ring that dies on this device, the
    // caller's «missed» letter through the extension, the same letter through the app — and they
    // race (measured 09.09 11:47 on T1: ring posted at .795, the letter's banner at 41.199, the
    // app's banner for the letter at 41.705, the ring's own banner at 42.161 — three banners, one
    // call). The call's seed is its one name. This notebook, shared through the keychain, says
    // what each seed already got: `alive` — this device saw the call itself, a letter about it is
    // redundant; `rang` — a banner already stands, nobody rings again.
    private static let seedLock = NSLock()
    static func state(_ seed: String) -> String? {
        guard !seed.isEmpty else { return nil }
        seedLock.lock(); defer { seedLock.unlock() }   // LOCK-OK: one read of that record
        return seedBook()[seed]?.0
    }
    static func note(_ seed: String, _ state: String) {
        guard !seed.isEmpty else { return }
        seedLock.lock(); defer { seedLock.unlock() }   // LOCK-OK: read-modify-write of one small keychain record
        var book = seedBook()
        if state == "alive", book[seed]?.0 == "rang" { return }   // a shown banner outranks a late ring
        let now = Date().timeIntervalSince1970
        book[seed] = (state, now)
        book = book.filter { now - $0.value.1 < 7 * 86400 }   // the term of the letter queue
        let raw = book.mapValues { [$0.0, String($0.1)] }
        if let d = try? JSONEncoder().encode(raw) { MontanaKeychain.set("missedCallSeeds", d) }
    }
    private static func seedBook() -> [String: (String, Double)] {
        guard let d = MontanaKeychain.get("missedCallSeeds"),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: d) else { return [:] }
        var out: [String: (String, Double)] = [:]
        for (k, v) in raw where v.count == 2 { out[k] = (v[0], Double(v[1]) ?? 0) }
        return out
    }
    /// THE CALL'S SHORT NAME for a notification identifier: the seed's first twelve letters and
    /// digits. The bell letter rides under «bell-<tag>» as its wake mid, Apple keeps that mid
    /// as the notification's identifier (apns-collapse-id), and whoever ends the call — the
    /// native ring, the missed letter, the cleanup — removes the bell by the same name.
    static func tag(_ seedB64: String) -> String { String(seedB64.filter { $0.isLetter || $0.isNumber }.prefix(12)) }
    /// The seed and the video flag of a «missed call» letter: JSON {v,s} after the mark.
    static func letter(_ text: String) -> (seed: String, video: Bool) {
        let json = String(text.dropFirst("\u{200B}\u{200B}MC:".count))
        let o = json.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return ((o?["s"] as? String) ?? "", (o?["v"] as? Bool) ?? false)
    }

    /// The one look of a missed call (the author's word 09.09: one variant, never two): the red
    /// handset word, the face in the avatar slot — the photo when there is one, the red handset
    /// pictogram otherwise. Composed here for both processes; nobody else composes it.
    static func content(peer: String, name: String, video: Bool) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = "☎️ " + String(localized: "Missed call", bundle: MTLanguage.bundle)
        content.sound = .default
        content.threadIdentifier = peer
        content.categoryIdentifier = "MISSED_CALL"   // preview-off lock screens still label it; long-press = Call back
        content.userInfo = ["chat": peer, "from": peer, "missed_call": true, "video": video]
        var img: INImage? = nil
        let key = "av_" + SHA256.hash(data: Data(peer.utf8)).map { String(format: "%02x", $0) }.joined()
        if let d = MontanaKeychain.get(key), !d.isEmpty { img = INImage(imageData: d) }
        if img == nil, let d = handsetIcon() { img = INImage(imageData: d) }
        var comp = PersonNameComponents(); comp.nickname = name
        let sender = INPerson(personHandle: INPersonHandle(value: peer, type: .unknown),
                              nameComponents: comp, displayName: name, image: img,
                              contactIdentifier: nil, customIdentifier: peer, isMe: false, suggestionType: .none)
        let me = INPerson(personHandle: INPersonHandle(value: "0", type: .unknown), nameComponents: nil,
                          displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil,
                          isMe: true, suggestionType: .none)
        let intent = INSendMessageIntent(recipients: [me], outgoingMessageType: .outgoingMessageText,
                                         content: content.body, speakableGroupName: INSpeakableString(spokenPhrase: name),
                                         conversationIdentifier: peer, serviceName: nil, sender: sender, attachments: nil)
        if let img { intent.setImage(img, forParameterNamed: \.sender) }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.groupIdentifier = peer   // a deleted chat takes this donation with it
        interaction.donate { _ in }
        if let updated = (try? content.updating(from: intent)) as? UNMutableNotificationContent { return updated }
        return content
    }

    // Red incoming-handset in a dark circle — the missed-call pictogram.
    static func handsetIcon() -> Data? {
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.16, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            let cfg = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
            let sym = UIImage(systemName: "phone.arrow.down.left.fill", withConfiguration: cfg)
                ?? UIImage(systemName: "phone.down.fill", withConfiguration: cfg)
            if let s = sym?.withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                let r = CGRect(x: (size.width - s.size.width) / 2, y: (size.height - s.size.height) / 2,
                               width: s.size.width, height: s.size.height)
                s.draw(in: r)
            }
        }
        return img.pngData()
    }
}
