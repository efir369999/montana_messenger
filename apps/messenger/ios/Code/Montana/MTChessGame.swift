import Foundation

struct MTChessEntry: Equatable, Sendable {
    let letter: MTChessLetter
    let mine: Bool
}

struct MTChessGame: Sendable {
    enum Status: Equatable, Sendable {
        case invited, playing, declined, whiteWon, blackWon, drawn, conflict, ended
        var finished: Bool { self != .invited && self != .playing }
    }
    private(set) var id: String
    /// THE ONE WHO INVITES PLAYS WHITE (checked 29.09 at the author's word «make sure who is white and who is black»): each
    /// phone reads the colours from the invitation's own side. The phone that sent it holds it as its own letter and plays
    /// white; the phone that received it plays black. Every later letter is judged by the same side (apply: the actor is white
    /// when the letter's side is the invitation's), and a letter of mine on one phone is a letter of theirs on the other, so
    /// the two replicas can never both hold one colour.
    private(set) var whiteIsMine: Bool
    private(set) var seconds: Int
    private(set) var status: Status = .invited
    private(set) var position = MTChessPosition()
    private(set) var positions = [MTChessPosition()]
    private(set) var moves: [MTChessMove] = []
    private(set) var notation: [String] = []
    private(set) var last: MTChessLetter
    private(set) var whiteMs: Int64
    private(set) var blackMs: Int64
    private(set) var drawOfferedBy: MTChessSide?
    private(set) var repetitions: [String: Int] = [:]
    private(set) var waitingForHistory = false
    private(set) var acceptedIDs: Set<String> = []
    var mySide: MTChessSide { whiteIsMine ? .white : .black }
    var canClaimDraw: Bool { position.halfmoves >= 100 || (repetitions[position.repetitionKey] ?? 0) >= 3 }
    /// The side whose clock runs: the side to move, while a game under a clock is being played; none otherwise.
    var running: MTChessSide? { seconds != 0 && status == .playing ? position.turn : nil }

    init?(entries: [MTChessEntry], game: String) {
        let relevant = entries.filter { $0.letter.game == game }
        guard let root = relevant.first(where: { $0.letter.kind == .invite }),
              root.letter.id == game, root.letter.parent.isEmpty,
              let duration = root.letter.seconds, MTChessLetter.timeControls.contains(duration) else { return nil }
        id = game; whiteIsMine = root.mine; seconds = duration
        last = root.letter; whiteMs = Int64(duration) * 1000; blackMs = whiteMs
        acceptedIDs = [game]
        repetitions[position.repetitionKey] = 1
        var unique: [String: MTChessEntry] = [:]
        for entry in relevant {
            if let previous = unique[entry.letter.id], previous.letter != entry.letter || previous.mine != entry.mine {
                status = .conflict; return
            }
            unique[entry.letter.id] = entry
        }
        let children = Dictionary(grouping: unique.values.filter { $0.letter.id != game }, by: { $0.letter.parent })
        var visited: Set<String> = [game]
        while !status.finished {
            let possible = (children[last.id] ?? []).compactMap { entry -> MTChessGame? in
                var next = self
                return next.apply(entry) ? next : nil
            }
            // AN END CLOSES THE GAME OVER WHATEVER CROSSED IT (29.09): either side's end letter first, then a resignation,
            // which concedes the game including when the peer's next move crossed it.
            let endings = possible.filter { $0.last.kind == .end }.sorted { $0.last.id < $1.last.id }
            let concessions = possible.filter { $0.last.kind == .resign }.sorted { $0.last.id < $1.last.id }
            let concedingSides = Set(concessions.compactMap { unique[$0.last.id]?.mine })
            if endings.isEmpty, concedingSides.count > 1 { status = .drawn; return }
            let next = endings.first ?? concessions.first ?? (possible.count == 1 ? possible.first : nil)
            guard let next else {
                if possible.count > 1 { status = .conflict }
                break
            }
            guard visited.insert(next.last.id).inserted else { status = .conflict; break }
            self = next
            acceptedIDs.insert(last.id)
        }
        // AN END WHOSE PARENT NEVER CAME STILL ENDS THE GAME (29.09): the end letter is the way out of a game whose earlier
        // moves are missing on this phone, so it is read from the letters themselves, not from the chain.
        if !status.finished, let stray = unique.values.filter({ $0.letter.kind == .end }).min(by: { $0.letter.id < $1.letter.id }) {
            status = .ended; last = stray.letter; acceptedIDs.insert(stray.letter.id)
        }
        // A child whose parent has not arrived is held, never applied to a guessed position; an ended game holds nothing.
        waitingForHistory = status != .ended && unique.values.contains { $0.letter.kind != .invite && unique[$0.letter.parent] == nil }
    }

    /// THE PAIR'S ONE GAME (the author's word 29.09: «the chess mark enters the current game, the one the correspondent sees;
    /// a game is either active or finished»): the game of the newest invitation between the two -- by its stamp, then its
    /// name -- read from the same letters on both phones, so both name the same game. The rule «the newest unfinished game by
    /// its last letter» named different games on the two phones: a game left without an end (an unanswered invitation, a
    /// clock run out while its owner was away, an end an older build could not read) stood open forever, and one late letter
    /// in it made it the newest again (T1 and the iPhone 15 on 1990, 29.09 21:12).
    static func current(_ entries: [MTChessEntry]) -> String? {
        entries.lazy.map(\.letter).filter { $0.kind == .invite }.max { ($0.at, $0.id) < ($1.at, $1.id) }?.game
    }
    /// A GAME A NEWER INVITATION REPLACED IS OVER (29.09): closed as an end closes it, by the pair's letters alone -- no letter
    /// is sent -- so no move, acceptance or clock of it is taken any more, and its board stays to be looked at.
    func replaced(by current: String?) -> MTChessGame {
        guard let current, current != id, !status.finished else { return self }
        var next = self
        next.status = .ended
        next.waitingForHistory = false
        return next
    }

    /// BOTH IN THE CHAT, THE GAME BEGINS AT ONCE (the author's word 30.09: «when both are in the chat, let them get into the
    /// game at once»): an invitation from the correspondent that nobody has answered, made within one presence life of now --
    /// its maker stands on its board this moment, for making one raises the maker's board -- is entered at once by the phone
    /// whose screen holds the pair as it lands, and the entry is the acceptance (MTChessSend.join): no new word rides the wire,
    /// and an older build receives an ordinary invitation. An older invitation, or my own, waits for its tap.
    func meets(at now: Int64, within life: Int64) -> Bool {
        status == .invited && !whiteIsMine && !waitingForHistory && abs(now - last.at) < life
    }
    /// The time a side holds by the letters alone: the control, less every turn its owner reported.
    func held(_ side: MTChessSide) -> Int64 { side == .white ? whiteMs : blackMs }
    /// A side's time with the running turn taken off, the turn as this phone measures it (MTChessAnchor).
    func remaining(_ side: MTChessSide, elapsed: Int64) -> Int64 {
        guard running == side else { return held(side) }
        return max(0, held(side) - max(0, elapsed))
    }
    /// The letter of an action, judged before it leaves: nil when the replay would refuse it. A letter on its sender's
    /// turn carries the turn as the sender measured it (spent); the training game's engine acts as the side that is not mine.
    func action(_ kind: MTChessLetter.Kind, at: Int64, move: String? = nil, offeringDraw: Bool = false,
                spent: Int64? = nil, mine: Bool = true) -> MTChessLetter? {
        guard kind == .end || !waitingForHistory, !status.finished else { return nil }
        var event = MTChessLetter(game: id, id: UUID().uuidString.lowercased(), parent: last.id,
            kind: kind, at: max(last.at, at), move: move, offerDraw: kind == .move ? offeringDraw : nil)
        if seconds != 0, event.onTurn, let spent { event.spent = min(max(0, spent), MTChessLetter.longestTurn) }
        var next = self
        guard next.apply(.init(letter: event, mine: mine)) else { return nil }
        // THE CLOSING LETTER NAMES THE END (29.09): judged by the replay it has just passed, in its sender's own words.
        if next.status.finished { event.end = next.ending(by: mine == whiteIsMine ? .white : .black, kind: kind) }
        return event
    }
    /// The end this replay reached, from the side of the one whose letter reached it (MTChessEnd).
    private func ending(by actor: MTChessSide, kind: MTChessLetter.Kind) -> MTChessEnd {
        let outcome: MTChessEnd.Outcome
        switch status {
        case .whiteWon: outcome = actor == .white ? .won : .lost
        case .blackWon: outcome = actor == .black ? .won : .lost
        case .declined: outcome = .declined
        case .ended: outcome = .ended
        default: outcome = .drawn
        }
        let cause: MTChessEnd.Cause
        switch kind {
        case .decline: cause = actor == .white ? .withdrawn : .declined
        case .resign: cause = .resign
        case .timeout: cause = .time
        case .draw: cause = .agreement
        case .claim: cause = .claim
        case .end: cause = .ended
        default:
            if position.legalMoves().isEmpty { cause = position.checked(position.turn) ? .mate : .stalemate }
            else if position.deadMaterial { cause = .material }
            else if position.halfmoves >= 150 { cause = .moves }
            else { cause = .repetition }
        }
        return MTChessEnd(outcome: outcome, cause: cause, moves: moves.count)
    }
    /// The state one letter later, for a game this phone holds whole (the training game): the replay's own judge.
    func adding(_ entry: MTChessEntry) -> MTChessGame? {
        var next = self
        guard next.apply(entry) else { return nil }
        next.acceptedIDs.insert(entry.letter.id)
        return next
    }
    private mutating func win(_ side: MTChessSide) { status = side == .white ? .whiteWon : .blackWon }
    private mutating func apply(_ entry: MTChessEntry) -> Bool {
        let event = entry.letter, actor: MTChessSide = entry.mine == whiteIsMine ? .white : .black
        guard event.parent == last.id, event.at >= last.at else { return false }
        if event.kind == .end { status = .ended; last = event; return true }
        if status == .invited {
            guard actor == .black && (event.kind == .accept || event.kind == .decline)
                    || actor == .white && event.kind == .decline else { return false }
            status = event.kind == .accept ? .playing : .declined
            last = event; return true
        }
        guard status == .playing else { return false }
        if event.kind == .resign {
            if position.matingMaterial(actor.other) { win(actor.other) } else { status = .drawn }
            last = event; return true
        }
        guard actor == position.turn else { return false }
        // The turn's cost: its owner's own measure when the letter carries one, the difference of stamps before it did.
        let time = held(actor) - (event.spent ?? max(0, event.at - last.at))
        if event.kind == .timeout {
            // Only the owner of a clock concedes it, and only when its own measure has run out.
            guard seconds > 0, time <= 0 else { return false }
            if actor == .white { whiteMs = 0 } else { blackMs = 0 }
            if position.matingMaterial(actor.other) { win(actor.other) } else { status = .drawn }
            last = event; return true
        }
        guard seconds == 0 || time > 0 else { return false }
        if event.kind == .draw {
            guard drawOfferedBy == actor.other else { return false }
            status = .drawn; last = event; return true
        }
        if event.kind == .claim {
            var valid = canClaimDraw
            if let uci = event.move, let move = MTChessMove(uci), let next = position.applying(move) {
                valid = next.halfmoves >= 100 || (repetitions[next.repetitionKey] ?? 0) >= 2
            }
            guard valid else { return false }
            status = .drawn; last = event; return true
        }
        guard event.kind == .move, let uci = event.move, let move = MTChessMove(uci),
              let word = position.notation(move), let next = position.applying(move) else { return false }
        if seconds > 0 { if actor == .white { whiteMs = time } else { blackMs = time } }
        position = next; positions.append(next); moves.append(move); notation.append(word)
        drawOfferedBy = event.offerDraw == true ? actor : nil
        last = event
        let key = position.repetitionKey
        repetitions[key, default: 0] += 1
        if position.legalMoves().isEmpty {
            if position.checked(position.turn) { win(actor) } else { status = .drawn }
        } else if position.deadMaterial || position.halfmoves >= 150 || (repetitions[key] ?? 0) >= 5 { status = .drawn }
        return true
    }
}

/// THE PAIR'S SCORE (the author's word 30.09: «in the top right corner, in the menu -- start a new game and see the overall
/// score of the games»): every game of the pair counted by its own replay -- a win to the side that won, a draw to both; a
/// game ended, declined, replaced, in conflict or still under way has no result and counts nothing. Read from the letters
/// alone, so the two phones count the same games, each from its own side.
struct MTChessScore: Equatable, Sendable {
    private(set) var mine = 0
    private(set) var theirs = 0
    private(set) var drawn = 0
    init(_ games: [MTChessGame] = []) {
        for game in games {
            switch game.status {
            case .whiteWon: if game.whiteIsMine { mine += 1 } else { theirs += 1 }
            case .blackWon: if game.whiteIsMine { theirs += 1 } else { mine += 1 }
            case .drawn: drawn += 1
            default: break
            }
        }
    }
}
