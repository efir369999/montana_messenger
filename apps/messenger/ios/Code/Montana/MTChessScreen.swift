import SwiftUI

extension Message {
    var chessLetter: MTChessLetter? {
        guard !isForwarded, !edited, replyText == nil,
              imageFile == nil, videoFile == nil, audioFile == nil, docFile == nil else { return nil }
        return MTChessLetter.parse(text)
    }
    /// A letter of a game after its invitation (MTChessLetter.isStep): the feed, the list record, the unread count and the
    /// banner pass it by.
    var isChessStep: Bool { chessLetter?.isStep == true }
}

struct MTChessOpen: Identifiable {
    let id = UUID()
    var chat: String? = nil
    var game: String? = nil
}

/// A game on the chess page's stack: one with a correspondent, by its conversation and name, or the training game.
enum MTChessSelection: Hashable {
    case game(chat: String, id: String)
    case computer
    case timer
}

/// A GAME OPENED FROM ITS INVITATION (the author's word 29.09: «a tap on the invitation's bubble opens the game's page, as
/// a post opens whole»): pushed on the conversation's own stack, as a post's whole letter is (MTLetterPage) -- the system's
/// back leads home to the letters, and the chat is never closed under it.
struct MTChessPush: Hashable, Identifiable {
    let game: String
    var id: String { game }
}

/// Who sits across the board: a correspondent through their conversation, or this phone's own engine.
enum MTChessSeat: Hashable {
    case correspondent(Chat, game: String)
    case computer
}

/// A GAME ALREADY REPLAYED, WITH THE LETTERS IT WAS REPLAYED FROM (29.09): a replay walks every move through the rules, and
/// a change anywhere in the store -- any letter of any chat -- asked for it anew. The same letters give the same game, so
/// only a game whose own letters changed is replayed again.
struct MTChessKnown: Sendable {
    let entries: [MTChessEntry]
    let game: MTChessGame?
    func replay(_ entries: [MTChessEntry], id: String) -> MTChessGame? {
        entries == self.entries ? game : MTChessGame(entries: entries, game: id)
    }
}

private struct MTChessRecord: Identifiable {
    let chat: String
    let game: MTChessGame
    var id: String { chat + ":" + game.id }
    static func entries(_ messages: [Message]) -> [MTChessEntry] {
        messages.compactMap { m in
            guard let letter = m.chessLetter else { return nil }
            return MTChessEntry(letter: letter, mine: m.isFromMe)
        }
    }
    static func read(_ messages: [String: [Message]], known: [String: MTChessKnown]) -> ([Self], [String: MTChessKnown]) {
        var records: [Self] = []
        var book: [String: MTChessKnown] = [:]
        for (chat, rows) in messages {
            let pair = ofPair(chat, rows: rows, known: known)
            records += pair.records
            book.merge(pair.book) { _, new in new }
        }
        return (records.sorted {
            if $0.game.status.finished != $1.game.status.finished { return !$0.game.status.finished }
            if $0.game.last.at != $1.game.last.at { return $0.game.last.at > $1.game.last.at }
            return $0.id < $1.id
        }, book)
    }
    /// ONE PAIR'S GAMES (30.09): every game of one conversation replayed against the pair's one game (MTChessGame.current),
    /// with that game's name -- the chess page's list, and the board's score and next game, read one replay.
    static func ofPair(_ chat: String, rows: [Message], known: [String: MTChessKnown])
        -> (records: [Self], book: [String: MTChessKnown], current: String?) {
        var records: [Self] = []
        var book: [String: MTChessKnown] = [:]
        let all = entries(rows), current = MTChessGame.current(all)
        for (id, entries) in Dictionary(grouping: all, by: { $0.letter.game }) {
            let key = chat + ":" + id
            let game = known[key]?.replay(entries, id: id) ?? MTChessGame(entries: entries, game: id)
            book[key] = MTChessKnown(entries: entries, game: game)
            if let game { records.append(.init(chat: chat, game: game.replaced(by: current))) }
        }
        return (records, book, current)
    }
}

/// WHEN THE RUNNING CLOCK BEGAN, ON THIS PHONE (the author's word 29.09: «when the correspondent taps the invitation, the game
/// and its clocks start at once»): the running turn began with the game's last letter -- my turn from the moment the
/// correspondent's letter landed here, theirs from the moment their phone confirmed mine; until that confirmation their
/// clock stands, for a letter on the road is nobody's thinking. A letter whose moment this phone never saw (a history laid
/// back from a copy, a landing under an older build) runs from its own stamp by the node's clock.
enum MTChessAnchor: Equatable {
    case standing
    case here(Double)     // this phone's seconds
    case stamp(Int64)     // the node's milliseconds
    var runs: Bool { self != .standing }
    func elapsed(at moment: Date = Date()) -> Int64 {
        switch self {
        case .standing: return 0
        case .here(let at): return Int64(max(0, moment.timeIntervalSince1970 - at) * 1000)
        case .stamp(let at): return max(0, MTChessWords.now - at)
        }
    }
    static func of(_ game: MTChessGame, rows: [Message]) -> MTChessAnchor {
        guard let side = game.running else { return .standing }
        guard let row = rows.last(where: { $0.chessLetter?.id == game.last.id }) else { return .stamp(game.last.at) }
        if side == game.mySide { return row.statusAt > 0 ? .here(row.statusAt) : .stamp(game.last.at) }
        return row.deliveryStatus == .delivered || row.deliveryStatus == .read ? .here(row.statusMoment) : .standing
    }
}

enum MTChessWords {
    static func status(_ game: MTChessGame, computer: Bool = false) -> String {
        if game.waitingForHistory { return String(localized: "Waiting for earlier moves", bundle: MTLanguage.bundle) }
        switch game.status {
        case .invited:
            return game.whiteIsMine ? String(localized: "Waiting for the invitation to be accepted", bundle: MTLanguage.bundle)
                : String(localized: "Chess invitation", bundle: MTLanguage.bundle)
        case .playing:
            if game.position.checked(game.position.turn) { return String(localized: "Check!", bundle: MTLanguage.bundle) }   // the chess word, not the verb (29.09)
            if game.position.turn == game.mySide { return String(localized: "Your move", bundle: MTLanguage.bundle) }
            return computer ? String(localized: "The computer is thinking", bundle: MTLanguage.bundle)
                : String(localized: "Opponent's move", bundle: MTLanguage.bundle)
        case .declined: return String(localized: "Invitation declined", bundle: MTLanguage.bundle)
        case .whiteWon: return String(localized: "White wins", bundle: MTLanguage.bundle)
        case .blackWon: return String(localized: "Black wins", bundle: MTLanguage.bundle)
        case .drawn: return String(localized: "Draw", bundle: MTLanguage.bundle)
        case .ended: return String(localized: "Game ended", bundle: MTLanguage.bundle)
        case .conflict: return String(localized: "Conflicting moves — start a new game", bundle: MTLanguage.bundle)
        }
    }
    /// THE INVITATION SAYS WHO PLAYS WHICH COLOUR (29.09): read from the letter alone -- the one who invites plays white
    /// (MTChessGame.whiteIsMine) -- with the clock the game is played under.
    /// The invitation's seat and clock (06.10).
    static func seat(_ letter: MTChessLetter, mine: Bool) -> String {
        MTRowLetter.chessSeat(mine: mine, seconds: letter.seconds ?? 0)
    }
    static func piece(_ p: MTChessPiece) -> String {
        switch (p.side, p.kind) {
        case (.white, .pawn): return String(localized: "White pawn", bundle: MTLanguage.bundle)
        case (.white, .knight): return String(localized: "White knight", bundle: MTLanguage.bundle)
        case (.white, .bishop): return String(localized: "White bishop", bundle: MTLanguage.bundle)
        case (.white, .rook): return String(localized: "White rook", bundle: MTLanguage.bundle)
        case (.white, .queen): return String(localized: "White queen", bundle: MTLanguage.bundle)
        case (.white, .king): return String(localized: "White king", bundle: MTLanguage.bundle)
        case (.black, .pawn): return String(localized: "Black pawn", bundle: MTLanguage.bundle)
        case (.black, .knight): return String(localized: "Black knight", bundle: MTLanguage.bundle)
        case (.black, .bishop): return String(localized: "Black bishop", bundle: MTLanguage.bundle)
        case (.black, .rook): return String(localized: "Black rook", bundle: MTLanguage.bundle)
        case (.black, .queen): return String(localized: "Black queen", bundle: MTLanguage.bundle)
        case (.black, .king): return String(localized: "Black king", bundle: MTLanguage.bundle)
        }
    }
    static func control(_ seconds: Int) -> String { MTRowLetter.chessControl(seconds) }   // one vocabulary with the banner (MTRowLetter, 29.09)
    static func clock(_ ms: Int64) -> String {
        let seconds = max(0, (ms + 999) / 1000)
        return String(format: "%lld:%02lld", seconds / 60, seconds % 60)
    }
    static func computer(_ level: Int) -> String {
        String(localized: "Computer, level \(level)", bundle: MTLanguage.bundle)
    }
    /// The pair's score from this phone's seat (MTChessScore): one line, the menu's header.
    static func score(_ score: MTChessScore) -> String {
        String(localized: "Wins \(score.mine) · Losses \(score.theirs) · Draws \(score.drawn)", bundle: MTLanguage.bundle)
    }
    static var now: Int64 { Int64(MontanaWakePush.nodeNow() * 1000) }
}

enum MTChessSend {
    /// THE CLOCK OF A GAME BEGUN FROM THE CHAT (29.09): ten minutes a side -- the one value the chat's mark invites under and
    /// the new-game sheet offers first.
    static let chatClock = 600
    @MainActor static func conversation(_ original: Chat, store: ChatStore) -> Chat {
        let ref = MTSamePair.root(original.convRef)
        var current = ((store.chatsShelf() ?? []) + store.storedArchived()).first { $0.convRef == ref } ?? original
        current.name = MTSamePair.root(current.name)
        current.convId = ref
        return current
    }
    @MainActor static func letter(_ packet: MTChessLetter, to chat: Chat, store: ChatStore) -> Bool {
        let chat = conversation(chat, store: store)
        let conv = chat.convId ?? chat.name
        // A REFUSED LETTER SAYS WHY (03.10, T1 and the iPhone 15 on 2082: T1 held both invitations and stood on the board, and
        // not one chess letter left it -- the road refused in silence and the diary had no word of it).
        let why = chat.isGroup ? "group" : ChatStore.isLocalRoom(chat.name) ? "room" : !MontanaConv.holds(conv) ? "no-pipe"
            : store.refuses(conv) ? "refused" : store.closedChats.contains(conv) ? "closed" : !store.historyLoaded ? "history" : ""
        guard why.isEmpty, let text = packet.text(title: String(localized: "Chess", bundle: MTLanguage.bundle)) else {
            MontanaTrace.mark("chess_refused", "kind=\(packet.kind.rawValue) why=\(why.isEmpty ? "text" : why) conv=\(String(conv.prefix(10))) chat=\(String(chat.name.prefix(10)))")
            return false
        }
        MontanaTrace.mark("chess_tx", "kind=\(packet.kind.rawValue) game=\(String(packet.game.prefix(8))) conv=\(String(conv.prefix(10)))")
        // ONLY THE INVITATION AND THE CLOSING LETTER RING (29.09, MTChessLetter.rings): every other step rides a silent push
        // and the board shows it. A closing step that rode silent slept with the phone: T1's resignation of 15:21:42 reached
        // the iPhone 15 at 15:33, when its app was opened by hand.
        _ = store.send(text: text, chat: chat.name, convRef: conv, silent: !packet.rings, noLinkCard: true)
        return true
    }
    /// THE CHAT'S OWN GAME (the author's word 29.09: «the chess mark enters the current game, the one the correspondent sees;
    /// a game is either active or finished»): the pair's one game (MTChessGame.current), whatever its state -- a finished one
    /// opens to be looked at and offers the next game on its board -- or nil when the two never played, so the mark invites.
    @MainActor static func pairGame(in original: Chat, store: ChatStore) -> String? {
        let chat = conversation(original, store: store)
        return MTChessGame.current(MTChessRecord.entries(store.messages[chat.name] ?? []))
    }
    /// THE PAIR'S GAME WHILE IT IS PLAYED (the author's word 30.09 23:26): the pair's one game when it is invited or on the board;
    /// nil when the two never played or the game is over -- the chess mark is ringed by it and enters it.
    @MainActor static func playedGame(in original: Chat, store: ChatStore) -> String? {
        let chat = conversation(original, store: store)
        let rows = store.messages[chat.name] ?? []
        guard let id = MTChessGame.current(MTChessRecord.entries(rows)), let now = state(id, rows: rows), !now.status.finished else { return nil }
        return id
    }
    /// A game with this correspondent as the replay reads it now, against the pair's one game: a game a newer invitation
    /// replaced reads as over (MTChessGame.replaced).
    static func state(_ game: String, rows: [Message]) -> MTChessGame? {
        let all = MTChessRecord.entries(rows)
        return MTChessGame(entries: all.filter { $0.letter.game == game }, game: game)?.replaced(by: MTChessGame.current(all))
    }
    @MainActor static func invite(to chat: Chat, seconds: Int, store: ChatStore) -> String? {
        let id = UUID().uuidString.lowercased()
        let packet = MTChessLetter(game: id, id: id, parent: "", kind: .invite, at: MTChessWords.now, seconds: seconds)
        return letter(packet, to: chat, store: store) ? id : nil
    }
    /// ENTERING THE GAME IS THE ACCEPTANCE (the author's word 29.09: «when the correspondent taps the invitation, the game
    /// itself and the clocks start at once»; and again: «once the person tapped in the chat and entered the chess, the
    /// invitation is accepted»): an invitation from them to me that nobody has answered is accepted by whatever opens its
    /// board -- the bubble's tap, the banner's tap, the chess page's row, and the board itself when it appears
    /// (MTChessGameScreen.reload) -- judged by the replay of the game's letters against the pair's one game, so a duplicate
    /// row, a letter that already answered it, or an invitation a newer one replaced changes nothing. The acceptance is the
    /// replay's own action, so the same rules judge it. Returns the
    /// acceptance's id when one left, so the board can hold it as pending and never send a second.
    @MainActor @discardableResult static func join(_ game: String, in original: Chat, store: ChatStore) -> String? {
        let chat = conversation(original, store: store)
        let now = state(game, rows: store.messages[chat.name] ?? [])
        guard let now, now.status == .invited, !now.whiteIsMine,
              let event = now.action(.accept, at: MTChessWords.now) else {
            MontanaTrace.mark("chess_join", "game=\(String(game.prefix(8))) sent=0 rows=\(store.messages[chat.name]?.count ?? -1) "
                                 + "status=\(now.map { "\($0.status)" } ?? "none") mine=\(now?.whiteIsMine == true ? 1 : 0) "
                                 + "waiting=\(now?.waitingForHistory == true ? 1 : 0)")
            return nil
        }
        return letter(event, to: chat, store: store) ? event.id : nil
    }
    /// AN INVITATION THAT WAITS FOR MY ANSWER (the author's word 06.10.2026 23:2x MSK: «below, two buttons -- the blue system Accept
    /// and the red burgundy Decline»): theirs to me, unanswered, read by the same replay the acceptance is judged by.
    static func awaitsMe(_ game: String, rows: [Message]) -> Bool {
        guard let now = state(game, rows: rows) else { return false }
        return now.status == .invited && !now.whiteIsMine
    }
    /// The invitation declined from its letter: the replay's own action, as the acceptance is (join), so the same rules judge it.
    @MainActor static func decline(_ game: String, in original: Chat, store: ChatStore) {
        let chat = conversation(original, store: store)
        guard let now = state(game, rows: store.messages[chat.name] ?? []), now.status == .invited, !now.whiteIsMine,
              let event = now.action(.decline, at: MTChessWords.now) else { return }
        _ = letter(event, to: chat, store: store)
    }
    /// The window of a meeting: one presence life (ChatStore.presenceLife -- the life a presence word proves its speaker
    /// there), in the replay's milliseconds.
    @MainActor static var meetingLife: Int64 { Int64(ChatStore.presenceLife * 1000) }
}

/// THE TIMER (the author's word 04.10.2026 00:10 MSK: «a game Timer for offline chess: on one phone switch whose move it is»): a
/// chess clock for two at one board. Each half is one player's -- the upper one turned to the player across the table -- and a tap
/// on one's own half ends one's move; the side to move thinks and its clock runs.
struct MTChessTimer: View {
    enum Side { case top, bottom }
    @State private var turn: Side?
    @State private var used: [Side: Int64] = [:]
    var body: some View {
        VStack(spacing: 0) {
            half(.top).rotationEffect(.degrees(180))
            Divider()
            half(.bottom)
        }
        .montanaPageGround()
        .navigationTitle("Timer")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: turn) { await run() }
    }
    private static func word(_ turn: Side?, moving: Bool) -> LocalizedStringKey {
        turn == nil ? "Tap to start" : moving ? "Your move" : "Waiting"
    }
    private func half(_ side: Side) -> some View {
        let moving = turn == side
        return Button { pass(side) } label: {
            VStack(spacing: 12) {
                // USER-DATA: the time this side has thought, minutes and seconds
                Text(verbatim: MTChessWords.clock(used[side] ?? 0)).font(.system(size: 64, weight: .semibold).monospacedDigit())
                Text(Self.word(turn, moving: moving)).font(.headline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(moving ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(turn != nil && !moving)
    }
    private func pass(_ side: Side) {
        guard turn == nil || turn == side else { return }
        turn = side == .top ? .bottom : .top
    }
    private func run() async {
        while let side = turn, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, turn == side else { return }
            used[side, default: 0] += 1000
        }
    }
}

/// THE TRAINING GAME (the author's word 29.09: «so that I can also play the computer, without people, and train; the level
/// is set by a slider before the game»): one game with this phone's own engine (MTChessEngine), kept in the very letters a
/// correspondent game is made of, so the one replay (MTChessGame) judges every move and the end. Nothing of it leaves the
/// phone; the person's own letters are the game's content, the level they last chose is their setting.
@MainActor final class MTChessComputer: ObservableObject {
    static let shared = MTChessComputer()
    nonisolated static let gameKey = "chess.computer.game"
    nonisolated static let levelKey = "chess.computer.level"
    private struct Kept: Codable { let level: Int; let letters: [MTChessLetter]; let mine: [Bool] }
    @Published private(set) var game: MTChessGame?
    @Published private(set) var level = 3
    @Published private(set) var thinking = false
    private var entries: [MTChessEntry] = []
    private var answering: Task<Void, Never>?
    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.gameKey),
              let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.letters.count == kept.mine.count,
              let first = kept.letters.first else { return }
        level = min(max(kept.level, 1), 10)
        entries = zip(kept.letters, kept.mine).map { MTChessEntry(letter: $0, mine: $1) }
        let snapshot = entries, id = first.game
        Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) { MTChessGame(entries: snapshot, game: id) }.value
            guard let self, self.entries.count == snapshot.count else { return }
            self.game = built
            self.answerIfDue()
        }
    }

    /// A new game at the chosen level; the one who invites plays white, so the person invites when they take white.
    func start(level: Int, white: Bool) {
        answering?.cancel(); answering = nil; thinking = false
        let id = UUID().uuidString.lowercased(), at = Self.now
        let invitation = MTChessLetter(game: id, id: id, parent: "", kind: .invite, at: at, seconds: 0)
        let acceptance = MTChessLetter(game: id, id: UUID().uuidString.lowercased(), parent: id, kind: .accept, at: at)
        self.level = min(max(level, MTChessEngine.levels.lowerBound), MTChessEngine.levels.upperBound)
        entries = [.init(letter: invitation, mine: white), .init(letter: acceptance, mine: !white)]
        game = MTChessGame(entries: entries, game: id)
        save()
        answerIfDue()
    }
    /// The person's own action, judged by the replay; the engine answers when the turn becomes its.
    func play(_ kind: MTChessLetter.Kind, move: String? = nil) -> Bool {
        guard !thinking, let game, let event = game.action(kind, at: Self.now, move: move),
              let next = game.adding(.init(letter: event, mine: true)) else { return false }
        commit(next, .init(letter: event, mine: true))
        return true
    }
    /// A training game takes a move back: the person's last move and the engine's answer to it.
    var canTakeBack: Bool { !thinking && entries.contains { $0.mine && $0.letter.kind == .move } }
    func takeBack() {
        guard let cut = entries.lastIndex(where: { $0.mine && $0.letter.kind == .move }), let first = entries.first else { return }
        answering?.cancel(); answering = nil; thinking = false
        entries = Array(entries.prefix(cut))
        game = MTChessGame(entries: entries, game: first.letter.game)
        save()
    }

    private func commit(_ next: MTChessGame, _ entry: MTChessEntry) {
        entries.append(entry)
        game = next
        save()
        answerIfDue()
    }
    private func answerIfDue() {
        guard answering == nil, let game, game.status == .playing, game.position.turn != game.mySide else { return }
        thinking = true
        let position = game.position, level = level, last = game.last.id
        answering = Task { [weak self] in
            let began = Date()
            let move = await Task.detached(priority: .userInitiated) { MTChessEngine.reply(to: position, level: level) }.value
            // An answer never lands in the same frame as the person's move: the board shows their move first.
            let rest = 0.35 - Date().timeIntervalSince(began)
            if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            self.answering = nil
            self.thinking = false
            guard let move, let game = self.game, game.last.id == last,
                  let event = game.action(.move, at: Self.now, move: move.uci, mine: false),
                  let next = game.adding(.init(letter: event, mine: false)) else { return }
            self.commit(next, .init(letter: event, mine: false))
        }
    }
    private func save() {
        let kept = Kept(level: level, letters: entries.map(\.letter), mine: entries.map(\.mine))
        guard let data = try? JSONEncoder().encode(kept) else { return }
        UserDefaults.standard.set(data, forKey: Self.gameKey)
    }
}

/// The computer's face: the platform's own glyph of a processor on a quiet round plate, as a person's face stands.
struct MTChessComputerFace: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "cpu")
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

struct MTChessPage: View {
    let open: MTChessOpen
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    @ObservedObject private var computer = MTChessComputer.shared
    @Environment(\.montanaClose) private var close
    @State private var records: [MTChessRecord] = []
    @State private var known: [String: MTChessKnown] = [:]
    @State private var path: [MTChessSelection] = []
    @State private var newGame = false
    @State private var entered = false
    var body: some View {
        NavigationStack(path: $path) {
            List {
                if records.isEmpty && computer.game == nil {
                    ContentUnavailableView {
                        MTChessIcon().frame(width: 72, height: 72)
                        Text("Chess")
                    } description: { Text("Invite a correspondent or play the computer.") }
                }
                if let game = computer.game {
                    NavigationLink(value: MTChessSelection.computer) {
                        HStack(spacing: 12) {
                            MTChessComputerFace(size: 44)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(MTChessWords.computer(computer.level)).font(.headline).lineLimit(1)
                                Text(MTChessWords.status(game, computer: true)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.vertical, 5)
                    }
                }
                // THE TIMER (the author's word 04.10 00:10): chess at one board, on one phone (MTChessTimer).
                NavigationLink(value: MTChessSelection.timer) {
                    HStack(spacing: 12) {
                        Image(systemName: "timer").font(.title2).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Timer").font(.headline).lineLimit(1)
                            Text("Offline chess on one phone").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 5)
                }
                ForEach(records) { record in
                    NavigationLink(value: MTChessSelection.game(chat: record.chat, id: record.game.id)) {
                        HStack(spacing: 12) {
                            MTChatAvatar(chat: chat(record.chat), size: 44)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.title(for: chat(record.chat))).font(.headline).lineLimit(1)
                                Text(MTChessWords.status(record.game)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(MTChessWords.control(record.game.seconds)).font(.subheadline.monospacedDigit())
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("Chess")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { close?() } }
                ToolbarItem(placement: .topBarTrailing) { MontanaBarMark(glyph: "plus", label: "New game") { newGame = true } }
            }
            .navigationDestination(for: MTChessSelection.self) { selection in
                switch selection {
                case .game(let name, let id): MTChessGameScreen(seat: .correspondent(chat(name), game: id))
                case .computer: MTChessGameScreen(seat: .computer)
                case .timer: MTChessTimer()
                }
            }
        }
        .tint(.primary)
        .task(id: store.messagesRev) {
            let snapshot = store.messages, before = known
            let built = await Task.detached(priority: .utility) { MTChessRecord.read(snapshot, known: before) }.value
            guard !Task.isCancelled else { return }
            records = built.0
            known = built.1
            if !entered {
                entered = true
                if let chat = open.chat, let game = open.game { path = [.game(chat: chat, id: game)] }
            }
        }
        .sheet(isPresented: $newGame) {
            MTChessNewGame(invite: { chat, seconds in
                guard let game = MTChessSend.invite(to: chat, seconds: seconds, store: store) else { return false }
                newGame = false; path.append(.game(chat: chat.name, id: game)); return true
            }, train: { level, white in
                computer.start(level: level, white: white)
                newGame = false; path.append(.computer)
            })
            .environmentObject(store)
        }
    }
    private func chat(_ name: String) -> Chat {
        let held = ((store.chatsShelf() ?? []) + store.storedArchived()).first { $0.name == name }
            ?? Chat(name: name, lastMessage: "", time: "", unread: 0, convId: name)
        return MTChessSend.conversation(held, store: store)
    }
}

/// A NEW GAME (the author's word 29.09: «on the plus, let me also play the computer without people and train; the level is
/// set before the game by a slider»): the computer with its level on the platform's slider and the colour chosen by its
/// piece, then the correspondents with the clock of the game.
private struct MTChessNewGame: View {
    let invite: (Chat, Int) -> Bool
    let train: (Int, Bool) -> Void
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MTChessComputer.levelKey) private var level = 3
    @State private var white = true
    @State private var seconds = MTChessSend.chatClock
    @State private var query = ""
    @State private var failed = false
    private func offer(_ chat: Chat) { failed = !invite(chat, seconds) }
    private var people: [Chat] {
        var seen: Set<String> = []
        return ((store.chatsShelf() ?? []) + store.storedArchived()).map {
            MTChessSend.conversation($0, store: store)
        }.filter { chat in
            let ref = chat.convId ?? chat.name
            return !chat.isGroup && !ChatStore.isLocalRoom(chat.name) && MontanaConv.holds(ref)
                && !store.refuses(ref) && !store.closedChats.contains(ref) && seen.insert(ref).inserted
                && (query.isEmpty || store.title(for: chat).localizedCaseInsensitiveContains(query))
        }.sorted { store.title(for: $0).localizedCompare(store.title(for: $1)) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Computer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Level \(level)").font(.subheadline.monospacedDigit())
                        Slider(value: Binding(get: { Double(level) }, set: { level = Int($0.rounded()) }),
                               in: Double(MTChessEngine.levels.lowerBound)...Double(MTChessEngine.levels.upperBound), step: 1) {
                            Text("Level")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                    .padding(.vertical, 4)
                    Picker("Your pieces", selection: $white) {
                        Text("♔").accessibilityLabel(Text("White pieces")).tag(true)
                        Text("♚").accessibilityLabel(Text("Black pieces")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    Button {
                        train(level, white)
                    } label: {
                        HStack(spacing: 12) {
                            MTChessComputerFace(size: 44)
                            Text("Play the computer")
                            Spacer()
                            Image(systemName: "play.fill")
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                }
                Section("Time control") {
                    Picker("Time per player", selection: $seconds) {
                        ForEach(MTChessLetter.timeControls, id: \.self) { Text(MTChessWords.control($0)).tag($0) }
                    }
                }
                Section {
                    if people.isEmpty { Text("No correspondents found").foregroundStyle(.secondary) }
                    ForEach(people) { chat in
                        Button { offer(chat) } label: {
                            HStack(spacing: 12) {
                                MTChatAvatar(chat: chat, size: 44)
                                Text(store.title(for: chat)).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "paperplane").frame(minWidth: 44, minHeight: 44)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.historyLoaded)
                    }
                } header: {
                    Text("Invite a correspondent")
                }
            }
            .searchable(text: $query)
            // THE KEYBOARD GOES WITH THE FINGER (the author's word 06.10.2026 23:0x MSK: «let the keyboard fold normally on the page
            // of a new game»): a drag of the list folds it.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } } }
            .alert("Invitation could not be sent", isPresented: $failed) { Button("OK", role: .cancel) {} }
        }
        .tint(.primary)
    }
}

struct MTChessGameScreen: View {
    let seat: MTChessSeat
    /// Pushed from the conversation itself (MTChessPush): the chat mark goes back to it instead of raising a second one.
    var inChat = false
    /// THE GAME ON THE SCREEN (29.09): the banner judge (MontanaApp.willPresent) shows no word of a game whose board the
    /// person is looking at.
    nonisolated(unsafe) static var shownGame: String?
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    @ObservedObject private var computer = MTChessComputer.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var replayed: MTChessGame?
    /// Every game of the pair as the last replay read it, by its letters (MTChessKnown): a game whose letters did not change
    /// is not replayed again.
    @State private var book: [String: MTChessKnown] = [:]
    @State private var anchor = MTChessAnchor.standing
    @State private var loaded = false
    @State private var selected: Int?
    @State private var browsing: Int?
    @State private var promotion: [MTChessMove] = []
    @State private var chatShown = false
    @State private var movesShown = false
    @State private var flipped = false
    @State private var offerDraw = false
    @State private var claimWithMove = false
    @State private var confirmResign = false
    @State private var confirmEnd = false
    @State private var failed = false
    @State private var pending: String?
    /// The next game begun from this board's plate (again): the board moves onto it.
    @State private var switched: String?
    /// The pair's one game (MTChessGame.current) is over, or the two never played: a new game may begin (nextGame).
    @State private var pairOver = false
    /// The pair's score as the last replay counted it (MTChessScore): the menu's header.
    @State private var score = MTChessScore()
    /// This board showed the game unfinished: its end, seen here, takes the person back to the chat (leave).
    @State private var sawLive = false
    @State private var paneSize: CGSize = .zero
    @AppStorage("bubbleColorIndex") private var bubbleColorIndex = 0
    private var isComputer: Bool { seat == .computer }
    private var gameID: String? {
        guard case .correspondent(_, let id) = seat else { return nil }
        return switched ?? id
    }
    private var game: MTChessGame? { isComputer ? computer.game : replayed }
    private var chat: Chat? {
        guard case .correspondent(let original, _) = seat else { return nil }
        return MTChessSend.conversation(original, store: store)
    }
    private var allowed: Bool {
        guard let chat else { return true }
        let ref = chat.convId ?? chat.name
        return !store.refuses(ref) && !store.closedChats.contains(ref) && store.historyLoaded
    }
    private var canSend: Bool {
        pending == nil && allowed && !(game?.waitingForHistory ?? true) && !(isComputer && computer.thinking)
    }
    private var live: Bool { browsing == nil && canSend }
    /// A NEW GAME BEGINS WHEN THE PAIR'S GAME IS OVER (30.09 -- the plate and the menu read this one rule): a game that stands
    /// keeps the pair, so its end comes first (End game); the training game begins anew at any moment.
    private var nextGame: Bool { isComputer || pairOver }
    // The body stays apart from the board, so the board's own long expression keeps the length the compiler types in reasonable time.
    var body: some View { board }
    private var board: some View {
        Group {
            if let game {
                GeometryReader { g in
                    let side = min(g.size.width, max(MTChessBoard.minimumSide, g.size.height - 270))
                    if chatShown && !inChat && chat != nil && g.size.width >= 760 {
                        HStack(spacing: 0) {
                            ScrollView(.vertical) {
                                table(game, width: min(g.size.width * 0.56, side)).frame(minHeight: g.size.height)
                            }
                            .frame(width: g.size.width * 0.56)
                            Divider()
                            chatPane(size: CGSize(width: g.size.width * 0.44, height: g.size.height))
                        }
                    } else {
                        ScrollView(.vertical) { table(game, width: side).frame(minHeight: g.size.height) }
                    }
                }
                .mtMeasureSize($paneSize)
            } else if loaded && !isComputer {
                ContentUnavailableView("Game history unavailable", systemImage: "clock.arrow.circlepath",
                    description: Text("Keep the invitation and moves in the conversation to continue this game."))
            } else { ProgressView() }
        }
        .montanaPageGround()
        .navigationTitle("Chess")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { bar }
        .task(id: store.messagesRev) { await reload() }
        .onChange(of: computer.game?.last.id) { _, _ in if isComputer { selected = nil; promotion = [] } }
        .sheet(isPresented: $movesShown) { moveList }
        .sheet(isPresented: Binding(get: { !promotion.isEmpty }, set: { if !$0 { promotion = [] } })) { promotionPicker }
        .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { send(.resign) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("End this game?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End game", role: .destructive) { send(.end) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Move could not be sent", isPresented: $failed) { Button("OK", role: .cancel) {} }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        .onChange(of: switched) { _, id in
            if let id { Self.shownGame = id }
            Task { await reload() }
        }
        .onAppear {
            if let gameID { Self.shownGame = gameID }
            // THE BOARD HOLDS THE NODE'S LANE (the author's word 29.09: «everything must be instant in the game»): a move
            // rides a silent push, and the system carries the first one at once and the next ones eight to fourteen seconds
            // late (T3 13:44:33.9 to T1 13:44:47.9, by the node's ring); the chat's held lane, on which the node says «box»
            // the moment a letter lands, died under the board (the chat's farewell when the board is pushed over it). The
            // board holds that lane in its OWN set (MontanaWakePush.boardConvs): held in the chat's set, the chat's farewell under
            // the pushed board took the board's hold with it (T1 15:25:10.656 left, 15:25:10.845 stop) and the moves rode the push again.
            if let chat { MontanaWakePush.startBoardPolling(chat.name) }
        }
        .onDisappear {
            if let gameID, Self.shownGame == gameID { Self.shownGame = nil }
            if let chat { MontanaWakePush.stopBoardPolling(chat.name) }
        }
    }

    @ToolbarContentBuilder private var bar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { gameMenu }
    }

    private func table(_ game: MTChessGame, width: CGFloat) -> some View {
        let step = min(browsing ?? game.moves.count, game.moves.count)
        let position = game.positions[step]
        let facing = flipped ? game.mySide.other : game.mySide
        let side = max(1, width)
        return VStack(spacing: 0) {
            moveStrip(game)
            player(game, side: facing.other)
            Spacer(minLength: 0)
            // THE GAME'S STATE STANDS ON THE BOARD, AT ITS CENTRE (the author's word 29.09: «waiting for the player and the
            // other states -- on the board, in the centre, in our native Montana style»): a plate of the app's own glass
            // (MTChessStatePlate) over the board while no move can be made -- an invitation waiting, earlier moves not yet
            // come, the game over -- with the invitation's marks and the next game's. It is the board's sibling in the
            // stack, never an overlay on the platform's board view, and it steps aside while the person browses the moves.
            ZStack {
                MTChessBoard(position: position, facing: facing, selected: selected,
                             destinations: Set(selected.map { position.legalMoves(from: $0).map(\.to) } ?? []),
                             lastMove: step > 0 ? game.moves[step - 1] : nil,
                             enabled: live && game.status == .playing && game.position.turn == game.mySide,
                             onSquare: press)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                    .clipped()
                if browsing == nil, game.waitingForHistory || game.status != .playing { statePlate(game) }
            }
            Spacer(minLength: 0)
            player(game, side: facing)
            HStack(spacing: 8) {
                if game.status == .playing, !game.waitingForHistory {
                    Text(MTChessWords.status(game, computer: isComputer)).font(.subheadline).lineLimit(2)
                }
                Spacer(minLength: 0)
                if game.drawOfferedBy == game.mySide.other && game.status == .playing {
                    MontanaBarMark(glyph: "equal", label: "Accept draw") { send(.draw) }
                }
            }
            .frame(minHeight: 44)
            .disabled(!live).padding(.horizontal, 16)
            if !allowed { Text("This conversation is unavailable").font(.caption).foregroundStyle(.secondary) }
            if claimWithMove { Text("Choose the move for your draw claim").font(.caption).foregroundStyle(.secondary) }
            delivery(game)
            HStack {
                MontanaBarMark(glyph: "list.bullet", label: "Moves") { movesShown = true }
                Spacer()
                if chat != nil {
                    MontanaBarMark(glyph: "bubble.left.and.bubble.right", label: "Chat") {
                        // THE CHAT OPENS BY THE APP'S ONE ROAD (the author's word 29.09: «during a game the chats open
                        // crooked, lag, the opening animation is crooked»): a game reached from its chat goes back to it; on a
                        // wide window the chat stands beside the board; on a phone the conversation slides in over the board
                        // as it slides in everywhere (UIState.openChat), and the platform's back swipe returns to the game.
                        // A sheet at a third of the height held the chat in its own host, with its own keyboard floor and its
                        // own back mark (T1 15:09:29): two motions for one opening, and a conversation in a slot.
                        if inChat { dismiss() }
                        else if paneSize.width >= 760 { chatShown.toggle() }
                        else if let chat { ui.openChat(chat) }
                    }
                    Spacer()
                }
                MontanaBarMark(glyph: "chevron.left", label: "Previous move") { browse(-1) }.disabled(step == 0)
                Spacer()
                MontanaBarMark(glyph: "chevron.right", label: "Next move") { browse(1) }.disabled(step == game.moves.count)
            }
            .padding(.horizontal, 22).padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }
    private func statePlate(_ game: MTChessGame) -> some View {
        VStack(spacing: 4) {
            Text(MTChessWords.status(game, computer: isComputer))
                .font(.headline).multilineTextAlignment(.center).lineLimit(3)
                .padding(.top, 6)
            HStack(spacing: 8) {
                if game.status == .invited {
                    if !game.whiteIsMine {
                        MontanaBarMark(glyph: "checkmark", label: "Accept invitation") { send(.accept) }
                    }
                    MontanaBarMark(glyph: "xmark", label: game.whiteIsMine ? "Withdraw invitation" : "Decline invitation") { send(.decline) }
                } else if game.status.finished, nextGame {
                    MontanaBarMark(glyph: "plus", label: "New game") { again(game) }
                }
            }
            .disabled(!live)
        }
        .padding(.horizontal, 22).padding(.vertical, 8)
        .frame(minWidth: 180)
        .background { MTChessStatePlate() }
        .padding(28)
    }
    private func player(_ game: MTChessGame, side: MTChessSide) -> some View {
        let mine = side == game.mySide
        return HStack(spacing: 10) {
            if mine {
                MTSelfFace(size: 42)
            } else if let chat {
                MTChatAvatar(chat: chat, size: 42, showPresence: true)
            } else {
                MTChessComputerFace(size: 42)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name(mine: mine)).font(.headline).lineLimit(1)
                Text(captured(game, by: side)).font(.system(size: 18)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isComputer {
                if !mine && computer.thinking { ProgressView().frame(minWidth: 44, minHeight: 44) }
            } else {
                MTChessClock(game: game, side: side, anchor: game.running == side ? anchor : .standing) {
                    if side == game.mySide && pending == nil { send(.timeout) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .leading) {
            MTBubbleStyle.fill(mine: mine, own: bubblePalette[min(max(bubbleColorIndex, 0), bubblePalette.count - 1)])
                .frame(width: 6).clipShape(Capsule()).padding(.vertical, 12)
        }
    }
    private func name(mine: Bool) -> String {
        if mine { return E2E.myDisplayName() }
        if let chat { return store.title(for: chat) }
        return MTChessWords.computer(computer.level)
    }
    private func captured(_ game: MTChessGame, by side: MTChessSide) -> String {
        let step = min(browsing ?? game.moves.count, game.moves.count)
        let remaining = game.positions[step].board.compactMap { $0 }
        var taken: [MTChessPiece] = []
        for index in 0..<step {
            let move = game.moves[index], before = game.positions[index]
            guard before.turn == side, let mover = before.piece(at: move.from) else { continue }
            if let piece = before.piece(at: move.to) { taken.append(piece) }
            else if mover.kind == .pawn && move.from % 8 != move.to % 8 {
                taken.append(.init(side: side.other, kind: .pawn))
            }
        }
        let advantage = remaining.filter { $0.side == side }.reduce(0) { $0 + $1.kind.points }
            - remaining.filter { $0.side != side }.reduce(0) { $0 + $1.kind.points }
        return taken.sorted { $0.kind.points < $1.kind.points }.map(\.glyph).joined()
            + (advantage > 0 ? " +\(advantage)" : "")
    }
    private func moveStrip(_ game: MTChessGame) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(game.notation.enumerated()), id: \.offset) { i, word in
                        Button { browsing = i + 1 == game.moves.count ? nil : i + 1; selected = nil } label: {
                            Text((i % 2 == 0 ? "\(i / 2 + 1). " : "") + word)
                                .font(.callout.monospaced()).fontWeight((browsing ?? game.moves.count) == i + 1 ? .bold : .regular)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .id(i)
                    }
                }.padding(.horizontal, 12)
            }
            .onChange(of: game.moves.count) { _, count in if count > 0 { proxy.scrollTo(count - 1, anchor: .trailing) } }
        }
        .frame(height: 44)
    }
    @ViewBuilder private var gameMenu: some View {
        Menu {
            Button("Flip board", systemImage: "arrow.triangle.2.circlepath") { flipped.toggle() }
            Button("Live position", systemImage: "forward.end") { browsing = nil; selected = nil }
            if let game, game.status == .playing {
                if !isComputer {
                    Toggle("Offer draw with next move", isOn: $offerDraw)
                    Toggle("Claim draw with intended move", isOn: $claimWithMove)
                        .disabled(!live || game.position.turn != game.mySide)
                }
                Button("Claim draw", systemImage: "equal") { send(.claim) }
                    .disabled(!live || game.position.turn != game.mySide || !game.canClaimDraw)
                if isComputer {
                    Button("Take back move", systemImage: "arrow.uturn.backward") { computer.takeBack(); browsing = nil }
                        .disabled(!computer.canTakeBack)
                }
                Button("Resign", systemImage: "flag", role: .destructive) { confirmResign = true }.disabled(!live)
            }
            if let game, !game.status.finished {
                // END THE GAME, EITHER SIDE, FROM ANY UNFINISHED STATE (the author's word 29.09: as the training game's menu
                // has New game): the way out of an unanswered invitation, a game being played, or one whose earlier moves never came.
                Button("End game", systemImage: "xmark.circle", role: .destructive) { confirmEnd = true }
                    .disabled(pending != nil || !allowed || (isComputer && computer.thinking))
            }
            // THE NEXT GAME AND THE PAIR'S SCORE (the author's word 30.09: «in the top right corner, in the menu -- start a new
            // game and see the overall score of the games»): the plate's own next game (again) -- the training game's new game
            // walks it too -- under the score of every game the two finished (MTChessScore), as the platform's menus title a group.
            if let game {
                Section {
                    Button("New game", systemImage: "plus") { again(game) }
                        .disabled(!nextGame || pending != nil || !allowed)
                } header: {
                    if !isComputer { Text(MTChessWords.score(score)) }
                }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Game actions"))
    }
    @ViewBuilder private func delivery(_ game: MTChessGame) -> some View {
        if let chat, let row = store.messages[chat.name]?.last(where: { MTChessLetter.parse($0.text)?.id == game.last.id }), row.isMine {
            HStack {
                Text(LocalizedStringKey(row.deliveryStatus.word)).font(.caption).foregroundStyle(.secondary)
                if row.deliveryStatus == .failed {
                    MontanaBarMark(glyph: "arrow.clockwise", label: "Retry") {
                        guard let mid = row.msgId else { return }
                        let bare = mid.hasPrefix("mid:") ? String(mid.dropFirst(4)) : mid
                        let ref = chat.convId ?? chat.name
                        store.settleByMid(conv: chat.name, mid: bare, .sending)
                        MontanaDeliveryEngine.shared.enqueue(to: ref, chat: chat.name, mid: bare, text: row.text, silent: !game.last.rings)
                    }
                }
            }
        }
    }
    @ViewBuilder private func chatPane(size: CGSize) -> some View {
        if let chat {
            ChatOverlay(chat: chat, initialSize: size, onClose: { chatShown = false })
                .environment(ui).environmentObject(store)
        }
    }
    private var moveList: some View {
        NavigationStack {
            List {
                if let game {
                    ForEach(Array(game.notation.enumerated()), id: \.offset) { i, word in
                        Button { browsing = i + 1 == game.moves.count ? nil : i + 1; selected = nil; movesShown = false } label: {
                            HStack { Text("\(i / 2 + 1).".appending(i % 2 == 1 ? ".." : "")); Text(word); Spacer() }
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("Moves")
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { movesShown = false } } }
        }.tint(.primary)
    }
    private var promotionPicker: some View {
        NavigationStack {
            HStack(spacing: 16) {
                ForEach(promotion, id: \.uci) { move in
                    if let kind = move.promotion, let game {
                        let piece = MTChessPiece(side: game.mySide, kind: kind)
                        Button { promotion = []; play(move) } label: {
                            Image(MTChessPalette.asset(piece)).resizable().scaledToFit()
                                .frame(width: 60, height: 60).contentShape(Rectangle())
                        }
                        .accessibilityLabel(MTChessWords.piece(piece))
                    }
                }
            }
            .navigationTitle("Promote pawn")
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { promotion = [] } } }
        }.presentationDetents([.height(180)])
    }
    @MainActor private func reload() async {
        guard let id = gameID, let chat else { loaded = true; return }
        let name = chat.name, snapshot = store.messages[name] ?? [], before = book
        // The pair's every game is replayed beside the shown one (MTChessRecord.ofPair): the score and the rule of the next
        // game read the same replay as the board.
        let built = await Task.detached(priority: .utility) {
            () -> (records: [MTChessRecord], book: [String: MTChessKnown], current: String?, anchor: MTChessAnchor) in
            let read = MTChessRecord.ofPair(name, rows: snapshot, known: before)
            let shown = read.records.first { $0.game.id == id }?.game
            return (read.records, read.book, read.current, shown.map { MTChessAnchor.of($0, rows: snapshot) } ?? .standing)
        }.value
        guard !Task.isCancelled, id == gameID else { return }
        let next = built.records.first { $0.game.id == id }?.game
        if replayed?.last.id != next?.last.id || replayed?.status != next?.status { selected = nil; promotion = [] }
        replayed = next; book = built.book; anchor = built.anchor; loaded = true
        score = MTChessScore(built.records.map(\.game))
        pairOver = built.records.first { $0.game.id == built.current }?.game.status.finished ?? true
        if let next {
            if !next.status.finished { sawLive = true } else if sawLive { leave(id) }
        }
        if let pending, next?.acceptedIDs.contains(pending) == true || next?.status.finished == true { self.pending = nil }
        // THE ACCEPTANCE IS THE PERSON'S PRESS ALONE (the author's words 06.10.2026 23:5x MSK: «accept or not -- the buttons in the
        // chat come before the chess board is shown»; «the last game began with no request at all: first the request is
        // confirmed, then the decision»): the board accepts nothing by appearing. An invitation it holds unanswered shows its
        // plate's marks (statePlate), and the chat's Accept is the other door (MTChessSend.join).
        // THE BOARD SAYS WHAT IT HOLDS (03.10): which game, in what state, whether it may send -- the one reading that tells a
        // board that waits for its acceptance from one whose acceptance was refused.
        MontanaTrace.markChanged("chess_board", "game=\(String(id.prefix(8))) status=\(next.map { "\($0.status)" } ?? "none") "
                                    + "mine=\(next?.whiteIsMine == true ? 1 : 0) waiting=\(next?.waitingForHistory == true ? 1 : 0) "
                                    + "allowed=\(allowed ? 1 : 0) current=\(built.current == id ? 1 : 0) pending=\(pending == nil ? 0 : 1)", every: 600)
        // BOTH AT THE BOARD, THE NEXT GAME BEGINS AT ONCE (the author's word 30.09: «when both are in the chat, let them get
        // into the game at once»): a board on the screen whose game is over follows the correspondent's fresh invitation onto
        // its game, as the maker's own board moved onto it (again), and its entry accepts (above, on the next reload). A chat laid
        // over the board keeps the invitation for its tap; the chat beside it on a wide window does not.
        if let current = built.current, current != id, next?.status.finished == true, Self.shownGame == id,
           scenePhase == .active, chatShown || store.openConv != chat.name,
           built.records.first(where: { $0.game.id == current })?.game.meets(at: MTChessWords.now, within: MTChessSend.meetingLife) == true {
            switched = current
        }
    }
    private func press(_ square: Int) {
        guard let game, live, game.status == .playing, game.mySide == game.position.turn else { return }
        if let selected {
            let moves = game.position.legalMoves(from: selected).filter { $0.to == square }
            if moves.count > 1 { promotion = moves; return }
            if let move = moves.first { play(move); return }
        }
        selected = game.position.piece(at: square)?.side == game.mySide && selected != square ? square : nil
    }
    private func play(_ move: MTChessMove) {
        if claimWithMove { send(.claim, move: move.uci); claimWithMove = false }
        else { send(.move, move: move.uci, drawing: offerDraw); offerDraw = false }
    }
    private func browse(_ delta: Int) {
        guard let game else { return }
        let next = max(0, min(game.moves.count, (browsing ?? game.moves.count) + delta))
        browsing = next == game.moves.count ? nil : next; selected = nil
    }
    private func send(_ kind: MTChessLetter.Kind, move: String? = nil, drawing: Bool = false) {
        // Browsing an earlier position never suspends the live clock.
        // An end leaves from any unfinished state: the history stuck or not, the board browsing or not.
        let free = pending == nil && allowed && !(isComputer && computer.thinking)
        guard game != nil, kind == .end ? free : canSend, kind == .end || kind == .timeout || browsing == nil,
              scenePhase == .active else { return }
        selected = nil
        if isComputer {
            if !computer.play(kind, move: move) { failed = true }
            return
        }
        guard let chat, let id = gameID, let shown = game else { return }
        let rows = store.messages[chat.name] ?? []
        // The action is judged against the letters as they stand now, never against an older board on the screen, and a
        // game a newer invitation replaced takes none (MTChessSend.state).
        guard let current = MTChessSend.state(id, rows: rows), current.last.id == shown.last.id
        else { failed = true; return }
        let spent = current.running == current.mySide ? MTChessAnchor.of(current, rows: rows).elapsed() : nil
        guard let event = current.action(kind, at: MTChessWords.now, move: move, offeringDraw: drawing, spent: spent)
        else { failed = true; return }
        pending = event.id
        if !MTChessSend.letter(event, to: chat, store: store) { pending = nil; failed = true }
    }
    /// THE GAME THAT ENDS ON THE SCREEN LEAVES IT (the author's word 29.09: «when the game ends, throw into the chat -- the
    /// game's screen does not hang»): a moment on the final position and its plate, then the conversation -- down the chat's
    /// own stack, or the chat opened over the chess page. A game opened already over stays to be looked at (the author's
    /// word: «if you enter that game again, you look at the old game there»); a board moved on to the next game stays.
    private func leave(_ id: String) {
        guard let chat else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard Self.shownGame == id else { return }
            dismiss()
            if !inChat { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ui.openChat(chat) } }
        }
    }
    /// THE NEXT GAME FROM THE BOARD OF THE LAST ONE (29.09): the chat's mark opens the pair's one game even when it is over;
    /// its plate invites again under the same clock, and the board moves onto the new game -- which is now the pair's.
    private func again(_ game: MTChessGame) {
        browsing = nil; selected = nil; promotion = []
        if isComputer { computer.start(level: computer.level, white: game.whiteIsMine); return }
        guard let chat, let id = MTChessSend.invite(to: chat, seconds: game.seconds, store: store) else { failed = true; return }
        switched = id
    }
}

/// The plate a game's state stands on over the board: the app's own glass where the native skin runs (MTGlassPlate, one
/// owner of a plate's glass), the bar's material elsewhere -- as the posts' plates are drawn (MTBoardPostPlate).
private struct MTChessStatePlate: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            MTGlassPlate(shape: shape)
        } else {
            shape.fill(MontanaOctagon.barMaterial)
        }
    }
}

private struct MTChessClock: View {
    let game: MTChessGame
    let side: MTChessSide
    let anchor: MTChessAnchor
    let expired: () -> Void
    @Environment(\.scenePhase) private var phase
    @State private var beat = Date()
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    var body: some View {
        let active = game.running == side && anchor.runs
        let ms = game.remaining(side, elapsed: active ? anchor.elapsed(at: beat) : 0)
        HStack(spacing: 6) {
            if active { Image(systemName: "clock") }
            Text(game.seconds == 0 ? "∞" : MTChessWords.clock(ms)).font(.title3.bold().monospacedDigit())
        }
        .padding(.horizontal, 12).frame(minWidth: 94, minHeight: 44)
        .foregroundStyle(active ? Color.black : Color.primary)
        .background(active ? Color.white : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(side == .white ? Text("White clock") : Text("Black clock"))
        .accessibilityValue(game.seconds == 0 ? MTChessWords.control(0) : MTChessWords.clock(ms))
        .onReceive(tick) { now in
            guard phase == .active, active else { return }
            beat = now
            if game.seconds > 0, game.remaining(side, elapsed: anchor.elapsed(at: now)) == 0 { expired() }
        }
    }
}
