import Foundation

/// HOW A GAME ENDED, IN THE WORDS OF THE LETTER THAT ENDED IT (the author's word 29.09: «only two notices of chess -- you
/// are invited, tap to enter; and the game is over, with the result»): the outcome as its SENDER saw it, the cause and the
/// half-moves played, judged by the replay the letter passed before it left (MTChessGame.action). The door that holds one
/// letter and no history -- the notification extension -- reads it to say «you won by resignation» in the receiver's
/// language; the replay itself never reads it, the board's truth is the letters' order. The receiver reads the outcome
/// mirrored.
struct MTChessEnd: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable { case won, lost, drawn, declined, ended }
    enum Cause: String, Codable, Sendable {
        case mate, stalemate, resign, time, agreement, claim, material, repetition, moves, declined, withdrawn, ended
    }
    let outcome: Outcome
    let cause: Cause
    let moves: Int
    var mirrored: Outcome {
        switch outcome {
        case .won: return .lost
        case .lost: return .won
        default: return outcome
        }
    }
}

// Ordinary, receipted letters: older clients display the title and link. They never receive
// an unknown service command, and cannot accept a game merely by receiving its invitation.
struct MTChessLetter: Codable, Equatable, Sendable {
    /// EITHER SIDE MAY END THE GAME (the author's word 29.09: an End game item in the board's menu, as the training game's
    /// menu has New game): an end letter closes the game with no winner, from any unfinished state -- an unanswered
    /// invitation, a game being played, a game whose earlier moves never came -- and rings as the closing letter does.
    enum Kind: String, Codable, Sendable { case invite, accept, decline, move, resign, draw, claim, timeout, end }
    static let link = "montana://chess/1/"
    static let timeControls = [0, 300, 600, 900, 1800]
    /// The longest turn a letter may report: a day, far past the longest control, so a report is bounded before it is judged.
    static let longestTurn: Int64 = 86_400_000
    /// ONCE A GAME IS MADE, THE CHAT HOLDS ONLY ITS INVITATION (the author's word 29.09: «inside the chat, once the game is
    /// created, no notices are needed»; the morning's word before it: «during a game take the notices of the moves out»):
    /// every letter after the invitation -- the acceptance, a move, a decline, a resignation, a draw, a claim, a clock -- is
    /// read by the board alone: no bubble, no unread, no banner, a silent push. The invitation stands in the chat and opens
    /// the game.
    var isStep: Bool { kind != .invite }
    static func isStep(_ text: String) -> Bool { text.hasPrefix("♟ ") && parse(text)?.isStep == true }
    /// TWO LETTERS OF A GAME RING, AND ONLY TWO (the author's word 29.09): the invitation and the letter that ends the game
    /// ride a loud push and wear a banner; every other letter is the board's alone. A closing step that rode silent slept
    /// with the phone: T1's resignation of 15:21:42 reached the iPhone 15 at 15:33, when its app was opened by hand.
    var rings: Bool { kind == .invite || end != nil }
    /// A letter made on its sender's own turn: it spends the sender's clock.
    var onTurn: Bool { kind == .move || kind == .draw || kind == .claim || kind == .timeout }
    let game: String
    let id: String
    let parent: String
    let kind: Kind
    let at: Int64
    var move: String? = nil
    var seconds: Int? = nil
    var offerDraw: Bool? = nil
    /// THE TURN AS ITS OWNER MEASURED IT (29.09): the milliseconds from the moment the correspondent's letter landed on the
    /// sender's phone to this letter. A letter on the road is nobody's thinking: the difference of two stamps charged the road
    /// to the one who had not yet seen the move (T1 and the iPhone 15, 28.09: an acceptance held 2 min 41 s on a phone with
    /// no road out would have come off white's clock before white saw it). Absent in the letters of earlier builds, which
    /// keep the difference of stamps.
    var spent: Int64? = nil
    /// THE LETTER THAT ENDS THE GAME SAYS HOW (29.09, MTChessEnd): set by the sender's replay, read by the banner doors.
    var end: MTChessEnd? = nil

    func text(title: String) -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let code = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "♟ " + title + "\n" + Self.link + code
    }
    static func parse(_ text: String) -> Self? {
        guard text.hasPrefix("♟ "), text.utf8.count <= 2048,
              let line = text.split(separator: "\n", omittingEmptySubsequences: false).last,
              line.hasPrefix(link) else { return nil }
        let code = line.dropFirst(link.count).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: code),
              let letter = try? JSONDecoder().decode(Self.self, from: data),
              UUID(uuidString: letter.game) != nil, UUID(uuidString: letter.id) != nil,
              letter.parent.isEmpty || UUID(uuidString: letter.parent) != nil,
              letter.game.count == 36, letter.id.count == 36, letter.parent.count <= 36,
              (0...32_503_680_000_000).contains(letter.at),
              letter.move == nil || (letter.move?.utf8.count ?? 0) <= 5,
              letter.spent == nil || letter.onTurn && (0...longestTurn).contains(letter.spent ?? -1),
              letter.end == nil || letter.kind != .invite && letter.kind != .accept && (0...10_000).contains(letter.end?.moves ?? -1)
        else { return nil }
        if letter.kind == .invite {
            guard letter.id == letter.game, letter.parent.isEmpty,
                  let seconds = letter.seconds, timeControls.contains(seconds),
                  letter.move == nil, letter.offerDraw == nil else { return nil }
        } else {
            guard letter.id != letter.game, !letter.parent.isEmpty, letter.seconds == nil,
                  letter.kind == .move || letter.offerDraw == nil,
                  letter.kind == .move || letter.kind == .claim || letter.move == nil else { return nil }
        }
        return letter
    }
}
