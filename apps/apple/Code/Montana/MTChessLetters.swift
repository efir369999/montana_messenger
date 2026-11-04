import Foundation

// ── THE CHESS WORDS OF A BANNER, one vocabulary for both doors (29.09) ──
// They stood in MTRowLetter, the shared vocabulary of a row, until the chess door (docs/APPS-API.md, slice S4b): an edition that
// carries no game carries none of its words. This file is the app's and the extension's both; MTChessWire stays the wire alone,
// so the rules' own test (tools/chess-rules-tests.swift) still compiles it with the board's files and nothing else.
extension MTChessLetter {
    /// TWO LETTERS OF A GAME RING (the author's word 29.09: «only two notices of chess -- you are invited, tap to enter;
    /// and the game is over, with the result»): the invitation names the colour the receiver plays and the clock and asks
    /// for the tap that enters; the closing letter names the receiver's outcome, the cause and the moves. Nil for a letter
    /// that rings nothing (rings). Read by the app's banner door (MontanaNotify) and by the extension, which holds one letter
    /// and no board -- the same words at both.
    var banner: String? {
        let mark = "♟ "
        if kind == .invite {
            return mark + String(localized: "Chess invitation", bundle: MTLanguage.bundle) + " · "
                + Self.seat(mine: false, seconds: seconds ?? 0) + "\n"
                + String(localized: "Tap to join", bundle: MTLanguage.bundle)
        }
        guard let end = end else { return nil }
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
    static func seat(mine: Bool, seconds: Int) -> String {
        (mine ? String(localized: "You play white", bundle: MTLanguage.bundle)
              : String(localized: "You play black", bundle: MTLanguage.bundle)) + " · " + control(seconds)
    }
    static func control(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "No clock", bundle: MTLanguage.bundle) : "\(seconds / 60):00"
    }
}

/// THE READER OF CHESS LETTERS (MTEditionLetters.game, slice S4b): what shared code and the extension ask of a game's letter,
/// answered by its one parser.
struct MTChessLetters: MTGameLetters {
    func read(_ text: String) -> MTGameLetter? {
        MTChessLetter.parse(text).map { MTGameLetter(game: $0.game, invite: $0.kind == .invite, ends: $0.end != nil) }
    }
    func banner(_ text: String) -> String? { MTChessLetter.parse(text)?.banner }
    /// THE GAME'S LETTER IN THE CHAT (the author's words 06.10.2026 20:2x UTC): the invitation says who plays which colour
    /// with the clock (29.09); the closing letter says how the game ended; every other letter opens the game.
    func face(_ text: String, mine: Bool) -> String {
        let open = String(localized: "Open game", bundle: MTLanguage.bundle)
        guard let letter = MTChessLetter.parse(text) else { return open }
        if letter.kind == .invite { return MTChessLetter.seat(mine: mine, seconds: letter.seconds ?? 0) }
        guard letter.end != nil, let words = letter.banner else { return open }
        return String(words.drop { ch in ch == "♟" || ch == " " })
    }
    var preview: String { "♟ " + String(localized: "Chess", bundle: MTLanguage.bundle) }
    var link: String { MTChessLetter.link }
}
