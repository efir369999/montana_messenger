import Foundation

enum MTChessSide: String, Codable, Sendable {
    case white, black
    var other: Self { self == .white ? .black : .white }
}

enum MTChessKind: String, Codable, CaseIterable, Sendable {
    case pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q", king = "k"
    var points: Int {
        switch self { case .pawn: return 1; case .knight, .bishop: return 3
        case .rook: return 5; case .queen: return 9; case .king: return 0 }
    }
}

struct MTChessPiece: Equatable, Sendable {
    let side: MTChessSide
    let kind: MTChessKind
    var glyph: String {
        let white = side == .white
        switch kind {
        case .king: return white ? "♔" : "♚"
        case .queen: return white ? "♕" : "♛"
        case .rook: return white ? "♖" : "♜"
        case .bishop: return white ? "♗" : "♝"
        case .knight: return white ? "♘" : "♞"
        case .pawn: return white ? "♙" : "♟"
        }
    }
}

struct MTChessMove: Equatable, Hashable, Sendable {
    let from: Int
    let to: Int
    var promotion: MTChessKind? = nil
    var uci: String { MTChessPosition.square(from) + MTChessPosition.square(to) + (promotion?.rawValue ?? "") }
    init(from: Int, to: Int, promotion: MTChessKind? = nil) {
        self.from = from; self.to = to; self.promotion = promotion
    }
    init?(_ uci: String) {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5,
              let from = MTChessPosition.index(String(chars[0...1])),
              let to = MTChessPosition.index(String(chars[2...3])) else { return nil }
        self.from = from; self.to = to
        if chars.count == 5 {
            guard let kind = MTChessKind(rawValue: String(chars[4])),
                  [.queen, .rook, .bishop, .knight].contains(kind) else { return nil }
            promotion = kind
        }
    }
}

// One rules owner, independent of the screen, transport, clock and storage.
struct MTChessPosition: Equatable, Sendable {
    private(set) var board: [MTChessPiece?]
    private(set) var turn: MTChessSide = .white
    private(set) var castling: Set<Int> = [0, 7, 56, 63]
    private(set) var enPassant: Int?
    private(set) var halfmoves = 0
    private(set) var ply = 0

    init() {
        board = Array(repeating: nil, count: 64)
        let back: [MTChessKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for f in 0..<8 {
            board[f] = MTChessPiece(side: .white, kind: back[f])
            board[8 + f] = MTChessPiece(side: .white, kind: .pawn)
            board[48 + f] = MTChessPiece(side: .black, kind: .pawn)
            board[56 + f] = MTChessPiece(side: .black, kind: back[f])
        }
    }

    init?(fen: String) {
        let fields = fen.split(separator: " ")
        guard fields.count == 6, fields[1] == "w" || fields[1] == "b",
              let half = Int(fields[4]), (0...150).contains(half),
              let full = Int(fields[5]), (1...10000).contains(full) else { return nil }
        board = Array(repeating: nil, count: 64)
        let ranks = fields[0].split(separator: "/")
        guard ranks.count == 8 else { return nil }
        for (r, text) in ranks.enumerated() {
            var f = 0
            for c in text {
                if let n = c.wholeNumberValue, (1...8).contains(n) { f += n }
                else {
                    guard f < 8, let k = MTChessKind(rawValue: String(c).lowercased()) else { return nil }
                    board[(7 - r) * 8 + f] = MTChessPiece(side: c.isUppercase ? .white : .black, kind: k)
                    f += 1
                }
                guard f <= 8 else { return nil }
            }
            guard f == 8 else { return nil }
        }
        guard board.compactMap({ $0 }).filter({ $0 == MTChessPiece(side: .white, kind: .king) }).count == 1,
              board.compactMap({ $0 }).filter({ $0 == MTChessPiece(side: .black, kind: .king) }).count == 1 else { return nil }
        turn = fields[1] == "w" ? .white : .black
        castling = []
        for c in fields[2] {
            switch c { case "K": castling.insert(7); case "Q": castling.insert(0)
            case "k": castling.insert(63); case "q": castling.insert(56)
            case "-": break; default: return nil }
        }
        if fields[3] != "-" {
            guard let ep = Self.index(String(fields[3])), ep / 8 == (turn == .white ? 5 : 2) else { return nil }
            enPassant = ep
        }
        halfmoves = half; ply = (full - 1) * 2 + (turn == .black ? 1 : 0)
    }

    static func square(_ n: Int) -> String {
        guard (0..<64).contains(n) else { return "" }
        return String(Array("abcdefgh")[n % 8]) + String(n / 8 + 1)
    }
    static func index(_ square: String) -> Int? {
        let s = Array(square.utf8)
        guard s.count == 2, (97...104).contains(s[0]), (49...56).contains(s[1]) else { return nil }
        return Int(s[1] - 49) * 8 + Int(s[0] - 97)
    }
    func piece(at square: Int) -> MTChessPiece? { (0..<64).contains(square) ? board[square] : nil }
    func checked(_ side: MTChessSide) -> Bool {
        guard let king = board.firstIndex(of: MTChessPiece(side: side, kind: .king)) else { return true }
        return attacked(king, by: side.other)
    }
    func attacked(_ target: Int, by side: MTChessSide) -> Bool {
        let tf = target % 8, tr = target / 8
        for from in 0..<64 {
            guard let p = board[from], p.side == side else { continue }
            let df = tf - from % 8, dr = tr - from / 8
            switch p.kind {
            case .pawn:
                if abs(df) == 1 && dr == (side == .white ? 1 : -1) { return true }
            case .knight:
                if abs(df) * abs(dr) == 2 { return true }
            case .king:
                if max(abs(df), abs(dr)) == 1 { return true }
            case .bishop, .rook, .queen:
                guard df != 0 || dr != 0 else { continue }
                let diagonal = abs(df) == abs(dr), straight = df == 0 || dr == 0
                guard (p.kind != .rook && diagonal) || (p.kind != .bishop && straight) else { continue }
                let sf = df.signum(), sr = dr.signum()
                var f = from % 8 + sf, r = from / 8 + sr, clear = true
                while f != tf || r != tr {
                    if board[r * 8 + f] != nil { clear = false; break }
                    f += sf; r += sr
                }
                if clear { return true }
            }
        }
        return false
    }

    func legalMoves(from source: Int? = nil) -> [MTChessMove] {
        var out: [MTChessMove] = []
        for from in 0..<64 where source == nil || from == source {
            guard let p = board[from], p.side == turn else { continue }
            for m in candidates(from, p) {
                if !applyingUnchecked(m).checked(turn) { out.append(m) }
            }
        }
        return out
    }

    private func candidates(_ from: Int, _ p: MTChessPiece) -> [MTChessMove] {
        var out: [MTChessMove] = []
        let file = from % 8, rank = from / 8
        func add(_ f: Int, _ r: Int) {
            guard (0..<8).contains(f), (0..<8).contains(r) else { return }
            let to = r * 8 + f
            guard board[to]?.side != p.side, board[to]?.kind != .king else { return }
            if p.kind == .pawn && (r == 0 || r == 7) {
                for k: MTChessKind in [.queen, .rook, .bishop, .knight] { out.append(.init(from: from, to: to, promotion: k)) }
            } else { out.append(.init(from: from, to: to)) }
        }
        switch p.kind {
        case .pawn:
            let d = p.side == .white ? 1 : -1, next = rank + d
            if (0..<8).contains(next) {
                if board[next * 8 + file] == nil {
                    add(file, next)
                    if rank == (p.side == .white ? 1 : 6), board[(rank + 2 * d) * 8 + file] == nil { add(file, rank + 2 * d) }
                }
                for f in [file - 1, file + 1] where (0..<8).contains(f) {
                    let to = next * 8 + f
                    if board[to]?.side == p.side.other { add(f, next) }
                    else if to == enPassant, board[to] == nil,
                            board[rank * 8 + f] == MTChessPiece(side: p.side.other, kind: .pawn) { add(f, next) }
                }
            }
        case .knight:
            for (df, dr) in [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)] { add(file + df, rank + dr) }
        case .king:
            for df in -1...1 { for dr in -1...1 where df != 0 || dr != 0 { add(file + df, rank + dr) } }
            let base = p.side == .white ? 0 : 56
            if from == base + 4, !checked(p.side) {
                for (rook, landing, gaps) in [(base + 7, base + 6, [5,6]), (base, base + 2, [1,2,3])] {
                    guard castling.contains(rook), board[rook] == MTChessPiece(side: p.side, kind: .rook),
                          gaps.allSatisfy({ board[base + $0] == nil }) else { continue }
                    // The transit square is tested with the king moved off its starting square.
                    let transit = from + (landing > from ? 1 : -1)
                    if !applyingUnchecked(.init(from: from, to: transit)).checked(p.side) { add(landing % 8, rank) }
                }
            }
        case .bishop, .rook, .queen:
            let diagonal = [(1,1),(1,-1),(-1,1),(-1,-1)]
            let straight = [(1,0),(-1,0),(0,1),(0,-1)]
            let directions = p.kind == .bishop ? diagonal : (p.kind == .rook ? straight : diagonal + straight)
            for (df, dr) in directions {
                var f = file + df, r = rank + dr
                while (0..<8).contains(f) && (0..<8).contains(r) {
                    add(f, r)
                    if board[r * 8 + f] != nil { break }
                    f += df; r += dr
                }
            }
        }
        return out
    }

    func applying(_ move: MTChessMove) -> Self? {
        guard legalMoves(from: move.from).contains(move) else { return nil }
        return applyingUnchecked(move)
    }
    private func applyingUnchecked(_ m: MTChessMove) -> Self {
        var next = self
        guard let p = piece(at: m.from), (0..<64).contains(m.to) else { return next }
        let capture = board[m.to] != nil || (p.kind == .pawn && m.to == enPassant)
        next.board[m.from] = nil
        if p.kind == .pawn, m.to == enPassant, board[m.to] == nil { next.board[m.to + (p.side == .white ? -8 : 8)] = nil }
        next.board[m.to] = MTChessPiece(side: p.side, kind: m.promotion ?? p.kind)
        if p.kind == .king {
            let base = p.side == .white ? 0 : 56
            next.castling.subtract([base, base + 7])
            if abs(m.to - m.from) == 2 {
                let rook = m.to > m.from ? base + 7 : base
                next.board[(m.to + m.from) / 2] = next.board[rook]; next.board[rook] = nil
            }
        }
        next.castling.remove(m.from); next.castling.remove(m.to)
        next.enPassant = p.kind == .pawn && abs(m.to - m.from) == 16 ? (m.to + m.from) / 2 : nil
        next.halfmoves = p.kind == .pawn || capture ? 0 : halfmoves + 1
        next.ply += 1; next.turn = turn.other
        return next
    }

    func notation(_ move: MTChessMove) -> String? {
        let legal = legalMoves()
        guard legal.contains(move), let p = board[move.from] else { return nil }
        let next = applyingUnchecked(move)
        var word = ""
        if p.kind == .king && abs(move.to - move.from) == 2 { word = move.to > move.from ? "O-O" : "O-O-O" }
        else {
            let capture = board[move.to] != nil || (p.kind == .pawn && move.to == enPassant)
            if p.kind != .pawn {
                word = p.kind.rawValue.uppercased()
                let rivals = legal.filter { $0.to == move.to && $0.from != move.from && board[$0.from]?.kind == p.kind }
                if !rivals.isEmpty {
                    if !rivals.contains(where: { $0.from % 8 == move.from % 8 }) { word += String(Self.square(move.from).prefix(1)) }
                    else if !rivals.contains(where: { $0.from / 8 == move.from / 8 }) { word += String(move.from / 8 + 1) }
                    else { word += Self.square(move.from) }
                }
            } else if capture { word += String(Self.square(move.from).prefix(1)) }
            if capture { word += "x" }
            word += Self.square(move.to)
            if let promote = move.promotion { word += "=" + promote.rawValue.uppercased() }
        }
        if next.checked(next.turn) { word += next.legalMoves().isEmpty ? "#" : "+" }
        return word
    }

    var repetitionKey: String {
        let pieces = board.map { p in p.map { $0.side == .white ? $0.kind.rawValue.uppercased() : $0.kind.rawValue } ?? "." }.joined()
        // An unusable en-passant target does not distinguish positions (including a pinned pawn).
        let ep = enPassant.flatMap { target in legalMoves().contains { $0.to == target && board[$0.from]?.kind == .pawn } ? target : nil }
        return pieces + turn.rawValue + castling.sorted().map(String.init).joined(separator: ",") + ":" + (ep.map(String.init) ?? "-")
    }
    var deadMaterial: Bool {
        let men = board.enumerated().compactMap { i, p -> (Int, MTChessPiece)? in
            guard let p, p.kind != .king else { return nil }; return (i, p)
        }
        if men.isEmpty { return true }
        if men.count == 1 { return men[0].1.kind == .bishop || men[0].1.kind == .knight }
        return men.allSatisfy { $0.1.kind == .bishop }
            && Set(men.map { ($0.0 / 8 + $0.0 % 8) % 2 }).count == 1
    }
    func matingMaterial(_ side: MTChessSide) -> Bool {
        let own = board.compactMap { $0 }.filter { $0.side == side && $0.kind != .king }
        if own.isEmpty || deadMaterial { return false }
        // With opposing material, a lone minor can sometimes mate with the opponent's help.
        let opponent = board.compactMap { $0 }.filter { $0.side != side && $0.kind != .king }
        if opponent.isEmpty, own.count == 1, own[0].kind == .bishop || own[0].kind == .knight { return false }
        return true
    }
}
