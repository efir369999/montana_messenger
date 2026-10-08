import Foundation
import UIKit

/// THE SET'S WORD ON THE WIRE (the author's word 22.09: do it all, leave no remainder).
///
/// [P2P-COMPAT] by construction. Nothing here touches the media road, no kind is added, no key of
/// the manifest changes: the set speaks in a service word of its own, «SP:», under the invisible
/// prefix every build reads. A build that does not know the token BURIES it unread (the vocabulary
/// gate of 1091, ContentView.mtUnknownServiceWord) -- so an older phone receives a sticker exactly
/// as it receives a card sticker today, and never sees a line of this.
///
/// Three shapes under one token, told apart by «t» inside:
///   id    the passport of a sticker letter: which set it belongs to, which sticker it is, its glyph
///   ask   send me that set
///   pack  a page of a set: its name, its title, and up to a few stickers with their bytes
///
/// A page rides the long-letter road already in the tree (MontanaWakePush.sealLongLetter): a word
/// too long for the envelope is sealed into a blob by the delivery engine itself and the receiver
/// opens it before the word is read. So a set of any size travels without a road of its own.
enum MontanaStickerWire {
    static let mark = "\u{200B}\u{200B}SP:"
    /// Stickers in one page of a set: six pictures of half a megabyte stay well inside the node's body.
    static let page = 6

    // -- leaving ------------------------------------------------------------------------------

    /// The passport of a sticker letter, sent right behind it and named by the SAME letter the
    /// picture rides under (store.letterMidFor) -- the two meet on the other side by that name.
    static func sendPassport(letter: String, file: String, pack: String, title: String, to peer: String, chat: String,
                             quote: String = "", quoteMid: String = "") {
        guard !peer.isEmpty, !letter.isEmpty else { return }
        let book = MontanaStickerBook.shared
        var body: [String: Any] = ["t": "id", "m": letter, "p": pack, "s": book.stickerId(of: file),
                                   "n": title, "o": MontanaP2PNode.myRef(),
                                   "c": pack == book.mineId ? book.names.count : (book.pack(pack)?.expected ?? 0)]
        // THE QUOTE OF A STICKER RIDES HERE (22.09): the picture road carries no reply, so the
        // letter it answers is named in its passport and the receiver's row grows the plate.
        if !quote.isEmpty { body["rq"] = quote; body["rm"] = quoteMid }
        send(body, to: peer, chat: chat)
        MontanaP2PTrace.mark("sticker_wire", "passport letter=\(letter.prefix(12)) pack=\(pack.prefix(8))")
    }

    /// «Send me that set» -- asked of the one who gave it, never of a stranger.
    static func ask(pack: String, from peer: String, chat: String) {
        guard !peer.isEmpty, !pack.isEmpty else { return }
        send(["t": "ask", "p": pack], to: peer, chat: chat)
        MontanaP2PTrace.mark("sticker_wire", "ask pack=\(pack.prefix(8)) of=\(peer.prefix(10))")
    }

    /// The set itself, in pages. Only a set this phone owns is answered: what we hold of someone
    /// else's is their word to give, not ours.
    static func answer(pack: String, to peer: String, chat: String) {
        let book = MontanaStickerBook.shared
        guard pack == book.mineId else {
            MontanaP2PTrace.mark("sticker_wire", "ask refused: not this phone's set")
            return
        }
        let names = book.names
        let pages = max(1, (names.count + page - 1) / page)
        for i in 0..<pages {
            var items: [[String: String]] = []
            for name in names.dropFirst(i * page).prefix(page) {
                guard let d = try? Data(contentsOf: MontanaMediaStore.url(name)) else { continue }
                items.append(["s": book.stickerId(of: name), "d": d.base64EncodedString()])
            }
            let body: [String: Any] = ["t": "pack", "p": pack, "n": "Montana", "o": MontanaP2PNode.myRef(),
                                       "i": i, "of": pages, "c": names.count, "items": items]
            send(body, to: peer, chat: chat)
        }
        MontanaP2PTrace.mark("sticker_wire", "answer pack=\(pack.prefix(8)) pages=\(pages) n=\(names.count)")
    }

    private static func send(_ body: [String: Any], to peer: String, chat: String) {
        guard let d = try? JSONSerialization.data(withJSONObject: body),
              let js = String(data: d, encoding: .utf8) else { return }
        MontanaDeliveryEngine.shared.enqueue(to: peer, chat: chat, mid: UUID().uuidString,
                                             text: mark + js, silent: true)
    }

    // -- arriving -----------------------------------------------------------------------------

    /// A word of the set arrived. True when it was ours to read -- the letter is service and never
    /// becomes a row.
    @discardableResult
    static func handle(_ text: String, from peer: String, chat: String, store: ChatStore? = nil) -> Bool {
        guard text.hasPrefix(mark) else { return false }
        guard let d = String(text.dropFirst(mark.count)).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let kind = o["t"] as? String else { return true }
        let book = MontanaStickerBook.shared
        switch kind {
        case "id":
            guard let letter = o["m"] as? String, let pack = o["p"] as? String else { return true }
            let title = (o["n"] as? String) ?? "Montana"
            let owner = (o["o"] as? String) ?? peer
            let quote = (o["rq"] as? String) ?? ""
            book.note(passport: MontanaStickerBook.Passport(pack: pack, sticker: (o["s"] as? String) ?? "",
                                                            emoji: (o["e"] as? String) ?? "",
                                                            title: title, owner: owner,
                                                            quote: quote, quoteMid: (o["rm"] as? String) ?? ""),
                      for: letter)
            // The letter may already stand: its plate is grown here, by the one owner of a late
            // quote (enrichQuote). Arriving first, the passport waits and the landing file asks it.
            if !quote.isEmpty, let store {
                store.enrichQuote(chat, sid: "mid:" + MontanaStickerBook.bare(letter), qt: quote,
                                  qm: (o["rm"] as? String) ?? "")
            }
            if !book.holds(pack) { book.meet(pack: pack, title: title, owner: owner, expected: (o["c"] as? Int) ?? 0) }
            book.note(giver: owner, for: pack)
            MontanaP2PTrace.mark("sticker_wire", "passport in letter=\(letter.prefix(12))")
        case "ask":
            guard let pack = o["p"] as? String else { return true }
            answer(pack: pack, to: peer, chat: chat)
        case "pack":
            guard let pack = o["p"] as? String else { return true }
            let title = (o["n"] as? String) ?? "Montana"
            book.meet(pack: pack, title: title, owner: (o["o"] as? String) ?? peer, expected: (o["c"] as? Int) ?? 0)
            var landed = 0
            for item in (o["items"] as? [[String: String]]) ?? [] {
                guard let sid = item["s"], let b64 = item["d"], let png = Data(base64Encoded: b64) else { continue }
                if book.land(pack: pack, sticker: sid, png: png) != nil { landed += 1 }
            }
            MontanaP2PTrace.mark("sticker_wire", "page \(((o["i"] as? Int) ?? 0) + 1)/\((o["of"] as? Int) ?? 1) landed=\(landed)")
        default:
            break   // a shape from a newer build: buried in silence, as this build's own vocabulary demands
        }
        return true
    }

    /// A LETTER CARRYING A SET'S LINK NAMES ITS GIVER (22.09). The link itself holds no address of
    /// anybody -- so the one who handed it over is remembered here, at the moment the letter lands,
    /// and that is whom the set is asked of when the link is tapped.
    static func noteLink(in text: String, peer: String) {
        guard let found = MontanaStickerPack.idIn(text: text), !peer.isEmpty else { return }
        let book = MontanaStickerBook.shared
        if !book.holds(found.id) {
            book.meet(pack: found.id, title: found.title.isEmpty ? "Montana" : found.title, owner: peer, expected: 0)
        }
        book.note(giver: peer, for: found.id)
        MontanaP2PTrace.mark("sticker_wire", "link noted pack=\(found.id.prefix(8)) giver=\(peer.prefix(10))")
    }
}

/// THE SET A LINK ASKED FOR, waiting for the conversation to appear (22.09): the link entrance
/// names it and opens the giver's chat; the chat opens its page on the next frame. One field, one
/// reader -- the value is taken once and cleared, so a page never opens twice.
enum MontanaStickerOpen {
    nonisolated(unsafe) static var pack: String? = nil
    static func take() -> String? {
        defer { pack = nil }
        return pack
    }
}
