import Foundation

/// IS THIS LETTER A ROW, AND WHAT DOES THE ROW SAY? One vocabulary, one answer, and both doors
/// ask it — the extension that meets a letter while the app is dead, and the app itself.
///
/// The two doors used to decide this separately. The extension wrote the row record for EVERY
/// letter it opened, including the service words that are not messages at all — a receipt, a
/// typing signal, a presence beat, an exchanged name or face. For those it had no word to show,
/// so it wrote «New message», stamped the conversation with the moment, and counted one unread.
/// The app then met the same letters through its own door, saw they were service, and rewrote the
/// row back to the real message. That rewriting is what a person sees as «it says new, then turns
/// into the text», and it is also why a conversation could jump for no reason: a presence beat is
/// not an event of the correspondence, but it was stamped as one.
///
/// The rule is one sentence: a letter that is not a row does not write a row.
enum MTRowLetter {
    // The invisible prefixes of the wire. A service word carries two of them plus a token.
    private static let svc = "\u{200B}\u{200B}"
    private static let sticker = "\u{2063}\u{2063}"

    /// The service words that ARE messages in the list: a voice letter, a media letter, a missed
    /// call, a call record. Every other token of the vocabulary is machinery between the two
    /// devices and has no place in the list.
    private static let rowTokens: Set<String> = ["VC:", "MD:", "MC:", "CL:", "GE:"]   // GE: a group's event row (stage R)
    /// A GROUP'S EVENT ROW SPEAKS IN THE APP'S WORDS (MTGroup.eventWords: the people by the names the group knows them by); set
    /// once at launch. The extension never lays such a row, so it never asks.
    static var eventWords: (String) -> String? = { _ in nil }

    /// Does this letter change what a conversation's row shows?
    static func changesRow(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if MTChessLetter.isStep(text) { return false }         // a step of a chess game is the board's, not the row's (29.09)
        if text.hasPrefix(sticker) { return true }             // a sticker is a message
        if text.hasPrefix(svc) {
            let token = String(text.dropFirst(svc.count).prefix(3))
            return rowTokens.contains(token)
        }
        // A single invisible prefix marks the machinery: receipts, signals, references. The
        // long-letter reference is the one exception — it IS the message, only carried.
        if text.hasPrefix("\u{2063}LB:") { return true }
        if text.hasPrefix("\u{2063}") || text.hasPrefix("\u{2064}") || text.hasPrefix("\u{200B}") {
            return false
        }
        return true
    }

    /// What the row says for a letter that is a row. The words are the ones the list already
    /// uses; the point is that there is now one place that chooses them.
    // WHAT THE WORDS OF A LETTER ARE — one answer for everybody who takes them out of a letter.
    // The clipboard and the selectable text in the menu used to take their own copy of the same
    // thing, so a stray edge — a trailing newline a keyboard left, the blank line a paste carried —
    // travelled into the field of whoever pasted it. The edges are cut here, once, and the words
    // inside are not touched: a letter is what a person wrote. Sender or receiver makes no
    // difference; a letter has one text and one place that says so.
    static func words(_ text: String) -> String {
        if text.hasPrefix(svc + "GE:") { return eventWords(text) ?? "" }
        if MTMoneyFlowRow.of(text) { return String(localized: "Money flow has begun", bundle: MTLanguage.bundle) }
        return MTWallCard.of(text)?.words ?? text.trimmingCharacters(in: .whitespacesAndNewlines)   // a post's card: the post's words, never its record
    }
    /// A ROW OF THIS PHONE'S OWN, NOT A LETTER (a post's card, the money flow's beginning): no edit, no rung, nothing passed on.
    static func ownRow(_ text: String) -> Bool {
        MTWallCard.of(text) != nil || MTMoneyFlowRow.of(text) || text.hasPrefix(svc + "GE:")
    }

    // ── THE CHESS WORDS OF A BANNER, one vocabulary for both doors (29.09) ──
    /// TWO LETTERS OF A GAME RING (the author's word 29.09: «only two notices of chess -- you are invited, tap to enter;
    /// and the game is over, with the result»): the invitation names the colour the receiver plays and the clock and asks
    /// for the tap that enters; the closing letter names the receiver's outcome, the cause and the moves. Nil for a letter
    /// that rings nothing (MTChessLetter.rings). Read by the app's banner door (MontanaNotify) and by the extension, which
    /// holds one letter and no board -- the same words at both.
    /// THE BANNER'S WORDS, ONE FUNCTION (the author's word 06.10.2026 23:5x MSK: «natively, as in the chat -- any word, a transfer,
    /// a game -- one function»): what the banner of a letter says, for the app's banner door (MontanaNotify) and the extension alike
    /// -- a game's invitation and end, a coin letter's coins, a voice, a media letter, the words; nil -- a word of the machine, or a
    /// step of a game, that rings nothing.
    static func bannerWords(_ text: String, revealCaption: Bool = true) -> String? {
        if let chess = MTChessLetter.parse(text) { return chessBanner(chess) }
        if coinCount(text) != nil { return preview(text) }
        if text.hasPrefix("\u{200B}\u{200B}VC:") { return "🎤 " + String(localized: "Voice message", bundle: MTLanguage.bundle) }
        if text.hasPrefix("\u{200B}\u{200B}MD:") { return mediaWords(letter: text, revealCaption: revealCaption) }
        if let f = text.unicodeScalars.first, f.value == 0x200B || f.value == 0x2063 || f.value == 0x2064 { return nil }
        return text.isEmpty ? String(localized: "New message", bundle: MTLanguage.bundle) : text
    }
    static func chessBanner(_ letter: MTChessLetter) -> String? {
        let mark = "♟ "
        if letter.kind == .invite {
            return mark + String(localized: "Chess invitation", bundle: MTLanguage.bundle) + " · "
                + chessSeat(mine: false, seconds: letter.seconds ?? 0) + "\n"
                + String(localized: "Tap to join", bundle: MTLanguage.bundle)
        }
        guard let end = letter.end else { return nil }
        if end.outcome == .ended {
            return mark + String(localized: "Chess", bundle: MTLanguage.bundle) + " · "
                + String(localized: "Game ended", bundle: MTLanguage.bundle)
        }
        if end.outcome == .declined {
            let word = end.cause == .withdrawn ? String(localized: "Invitation withdrawn", bundle: MTLanguage.bundle)
                                               : String(localized: "Invitation declined", bundle: MTLanguage.bundle)
            return mark + String(localized: "Chess", bundle: MTLanguage.bundle) + " · " + word
        }
        let outcome: String
        switch end.mirrored {
        case .won: outcome = String(localized: "You won", bundle: MTLanguage.bundle)
        case .lost: outcome = String(localized: "You lost", bundle: MTLanguage.bundle)
        default: outcome = String(localized: "Draw", bundle: MTLanguage.bundle)
        }
        let cause: String
        switch end.cause {
        case .mate: cause = String(localized: "Checkmate", bundle: MTLanguage.bundle)
        case .stalemate: cause = String(localized: "Stalemate", bundle: MTLanguage.bundle)
        case .resign: cause = String(localized: "Resignation", bundle: MTLanguage.bundle)
        case .time: cause = String(localized: "Out of time", bundle: MTLanguage.bundle)
        case .agreement: cause = String(localized: "By agreement", bundle: MTLanguage.bundle)
        case .claim: cause = String(localized: "By claim", bundle: MTLanguage.bundle)
        case .material: cause = String(localized: "Insufficient material", bundle: MTLanguage.bundle)
        case .repetition: cause = String(localized: "Repetition", bundle: MTLanguage.bundle)
        case .moves: cause = String(localized: "75-move rule", bundle: MTLanguage.bundle)
        case .declined, .withdrawn, .ended: cause = ""
        }
        let full = (end.moves + 1) / 2
        return mark + String(localized: "Game over", bundle: MTLanguage.bundle) + " · " + outcome
            + (cause.isEmpty ? "" : " · " + cause) + " · " + String(localized: "Moves: \(full)", bundle: MTLanguage.bundle)
    }
    /// The seat an invitation gives, with the clock: the one who invites plays white (MTChessGame.whiteIsMine).
    static func chessSeat(mine: Bool, seconds: Int) -> String {
        (mine ? String(localized: "You play white", bundle: MTLanguage.bundle)
              : String(localized: "You play black", bundle: MTLanguage.bundle)) + " · " + chessControl(seconds)
    }
    /// THE COIN LETTER'S NUMBER (MTCoinLetter, 03.10), read here by its shape alone: this file is the extension's too, and the
    /// extension does not carry the coin book. The first line is «🪙 N», the last the coin's machine line.
    static func coinCount(_ text: String) -> Int? {
        guard text.hasPrefix("🪙 "), text.utf8.count <= 512 else { return nil }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].hasPrefix("montana://coin/1/") else { return nil }   // NOT-UI: the coin letter's machine line
        return Int(parts[0].dropFirst(2)).flatMap { 0 < $0 ? $0 : nil }
    }
    static func chessControl(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "No clock", bundle: MTLanguage.bundle) : "\(seconds / 60):00"
    }

    static func preview(_ text: String) -> String {
        if text.hasPrefix(svc + "GE:") { return eventWords(text) ?? "" }
        if MTMoneyFlowRow.of(text) { return "🪙 " + String(localized: "Money flow has begun", bundle: MTLanguage.bundle) }
        if let c = MTWallCard.of(text) { return String(localized: "Wall post", bundle: MTLanguage.bundle) + (c.words.isEmpty ? "" : " · " + c.words) }
        if MTChessLetter.parse(text) != nil { return "♟ " + String(localized: "Chess", bundle: MTLanguage.bundle) }
        if let n = coinCount(text) { return "🪙 " + String(n) + " " + String(localized: "coins", bundle: MTLanguage.bundle) }
        // A SECRET SHARED FROM PASSWORDS names nothing of itself in a list or a banner: no title, no content (06.10.2026).
        if text.hasPrefix("🔑 "), text.contains("montana://secret/1/") { return "🔑 " + String(localized: "Shared password", bundle: MTLanguage.bundle) }   // NOT-UI: the letter's machine line
        if text.hasPrefix(svc + "VC:") { return "\u{1F3A4} " + String(localized: "Voice message", bundle: MTLanguage.bundle) }
        if text.hasPrefix(svc + "MC:") { return "\u{1F4DE} " + String(localized: "Missed call", bundle: MTLanguage.bundle) }
        if text.hasPrefix(svc + "CL:") {
            let json = String(text.dropFirst((svc + "CL:").count))
            if let d = json.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let video = (o["v"] as? Bool) ?? false
                let missed = (o["miss"] as? Bool) ?? false
                let incoming = (o["inc"] as? Bool) ?? false
                let icon = video ? "\u{1F4F9}" : "\u{1F4DE}"
                if missed { return icon + " " + String(localized: incoming ? "Missed call" : "Unanswered call", bundle: MTLanguage.bundle) }
                return icon + " " + String(localized: video ? "Video call" : "Voice call", bundle: MTLanguage.bundle)
            }
            return "\u{1F4DE} " + String(localized: "Voice call", bundle: MTLanguage.bundle)
        }
        if text.hasPrefix(svc + "MD:") { return mediaWords(letter: text) }
        // A letter that reached here is the person's own text — including a sticker, which is its
        // own emoji, and a long letter whose body could not be pulled in time.
        if text.hasPrefix("\u{2063}LB:") { return String(localized: "New message", bundle: MTLanguage.bundle) }
        if text.hasPrefix(sticker) { return String(text.dropFirst(sticker.count)) }
        return text.isEmpty ? String(localized: "New message", bundle: MTLanguage.bundle) : text
    }

    /// THE WORDS OF A MEDIA LETTER — one answer for the list row, the banner and the folded type
    /// (SSOT-CONSOLIDATE 15.09: four copies of this switch lived apart — the row vocabulary, the
    /// notifier's body, the notifier's type-only body, the extension's banner — and a round note
    /// was a plain «Video» in all of them). A round video note is a video MESSAGE, as a voice is
    /// a voice message: the words the player bar already says (the author's word 15.09: a note
    /// arrives as what it is, not as «media»).
    static func mediaWords(kind: String, round: Bool = false, caption: String = "", name: String? = nil,
                           revealCaption: Bool = true) -> String {
        let cap = revealCaption ? caption.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        switch kind {
        case "img": return "\u{1F4F7} " + (cap.isEmpty ? String(localized: "Photo", bundle: MTLanguage.bundle) : cap)
        case "vid", "video":
            if round { return "\u{1F4F9} " + String(localized: "Video message", bundle: MTLanguage.bundle) }
            return "\u{1F4F9} " + (cap.isEmpty ? String(localized: "Video", bundle: MTLanguage.bundle) : cap)
        case "aud": return "\u{1F3A4} " + String(localized: "Voice message", bundle: MTLanguage.bundle)
        case "doc": return "\u{1F4C4} " + ((revealCaption ? name : nil) ?? String(localized: "File", bundle: MTLanguage.bundle))
        default: return String(localized: "Media", bundle: MTLanguage.bundle)
        }
    }
    /// The manifest's own answer — kind, roundness, caption and name read from the MD letter.
    static func mediaWords(letter text: String, revealCaption: Bool = true) -> String {
        guard let o = manifest(text) else { return String(localized: "Media", bundle: MTLanguage.bundle) }
        return mediaWords(kind: (o["k"] as? String) ?? "", round: (o["r"] as? Bool) ?? false,
                          caption: (o["cap"] as? String) ?? "", name: (o["n"] as? String) ?? (o["name"] as? String),
                          revealCaption: revealCaption)
    }
    /// What the row's thumbnail stands for: «aud» for a voice, «vnote» for a round note, nil else.
    static func mediaKind(letter text: String) -> String? {
        guard let o = manifest(text) else { return nil }
        switch (o["k"] as? String) ?? "" {
        case "aud": return "aud"
        case "vid", "video": return ((o["r"] as? Bool) ?? false) ? "vnote" : nil
        default: return nil
        }
    }
    private static func manifest(_ text: String) -> [String: Any]? {
        guard text.hasPrefix(svc + "MD:") else { return nil }
        let json = String(text.dropFirst((svc + "MD:").count))
        guard let d = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}

/// A POST ON A WALL OF THE PAIR, A ROW OF THEIR CHAT (the author's word 30.09: «if I publish on a friend's wall, let this post
/// appear in his chat»). Each phone lays its own row, as each lays its own call's (callMark): the writer's the moment the post
/// leaves for the wall's owner (MTBoard.lay), the owner's the moment the post is taken onto the wall (MTBoard.apply, «post»)
/// -- one birth, ChatStore.appendWallPost. Nothing new rides the wire: the post's own word of the wall is the only one, so an
/// older build loses nothing it had. The row names the post by the name the post was born with, so a post stands in the chat
/// once whatever carries its word twice. COMPAT-LOCAL: the row never leaves this phone; a copy of it arriving from outside is a
/// service word no build knows and is buried unread (mtUnknownServiceWord) -- the card is seen by the two whose wall and chat it is.
/// THE MONEY FLOW BEGAN, A ROW OF THE CHAT (the author's word 03.10.2026 16:49 MSK: «when the money flow is switched on, an
/// active animation and a system message, as in chess, that the game of money flow has begun, with one turn of the coin»). This
/// phone's own row, as a call's is: laid the moment the coin comes on (ChatStore.appendMoneyFlow) and drawn as the chess
/// invitation's card, our coin turning once. COMPAT-LOCAL: it never leaves this phone; a copy arriving from outside is a service
/// word no build knows and is buried unread (mtUnknownServiceWord).
enum MTMoneyFlowRow {
    static let mark = "\u{200B}\u{200B}MF:"   // COMPAT-LOCAL: this phone's own row, never on the wire
    static func of(_ text: String) -> Bool { text.hasPrefix(mark) }
}

struct MTWallCard: Codable, Hashable {
    static let mark = "\u{200B}\u{200B}WP:"   // COMPAT-LOCAL: this phone's own row, never on the wire
    static let wordsKept = 300                 // the card shows the post's first lines; the post itself lives on the wall
    var id: String
    var tx: String
    var k: String? = nil                       // the first file's kind, for a post without words: img, vid, aud or doc
    init(id: String, text: String, kind: String?) {
        self.id = id
        tx = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.wordsKept))
        k = kind
    }
    static func of(_ text: String) -> MTWallCard? {
        guard text.hasPrefix(mark), let d = String(text.dropFirst(mark.count)).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MTWallCard.self, from: d)
    }
    /// The row's words, written in this one place.
    var row: String? {
        guard let d = try? JSONEncoder().encode(self), let js = String(data: d, encoding: .utf8) else { return nil }
        return Self.mark + js
    }
    /// What the card says: the post's own words, or the kind of its first file.
    var words: String {
        if !tx.isEmpty { return tx }
        switch k ?? "" {
        case "img": return String(localized: "Photo", bundle: MTLanguage.bundle)
        case "vid": return String(localized: "Video", bundle: MTLanguage.bundle)
        case "aud": return String(localized: "Music", bundle: MTLanguage.bundle)
        case "doc": return String(localized: "File", bundle: MTLanguage.bundle)
        default: return ""
        }
    }
}
