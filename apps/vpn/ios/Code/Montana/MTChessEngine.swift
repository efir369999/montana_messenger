import Foundation

/// THE PHONE'S OWN OPPONENT (the author's word 29.09: «so that I can also play the computer, without people, and train; the
/// level is set by a slider before the game»). A search on this phone over its own compact board -- material and the widely
/// published placement tables, negamax with alpha-beta, captures followed until the position is quiet -- whose depth, time
/// and bounded error are set by the level: a weak level plays plausible moves, a strong one its best. The rules owner
/// (MTChessPosition) names the legal moves at the root -- castling, en passant and every promotion -- and judges the move the
/// game receives; below the root the search walks the same rules in a form fast enough to walk (castling and en passant
/// stand at the root only, a promotion below it is to a queen). Nothing leaves the phone.
enum MTChessEngine {
    static let levels = 1...10

    struct Plan: Equatable, Sendable {
        let depth: Int        // the deepest full-width search
        let quiet: Bool       // captures followed past the depth until the position is quiet
        let error: Int        // centipawns a chosen move may lose against the best one found
        let budget: Double    // seconds; the first depth always completes
    }
    static func plan(_ level: Int) -> Plan {
        switch min(max(level, levels.lowerBound), levels.upperBound) {
        case 1: return Plan(depth: 1, quiet: false, error: 400, budget: 0.3)
        case 2: return Plan(depth: 1, quiet: true, error: 250, budget: 0.4)
        case 3: return Plan(depth: 2, quiet: true, error: 150, budget: 0.6)
        case 4: return Plan(depth: 2, quiet: true, error: 80, budget: 0.8)
        case 5: return Plan(depth: 3, quiet: true, error: 45, budget: 1.0)
        case 6: return Plan(depth: 3, quiet: true, error: 20, budget: 1.2)
        case 7: return Plan(depth: 4, quiet: true, error: 8, budget: 1.6)
        case 8: return Plan(depth: 4, quiet: true, error: 0, budget: 2.0)
        case 9: return Plan(depth: 5, quiet: true, error: 0, budget: 3.0)
        default: return Plan(depth: 6, quiet: true, error: 0, budget: 4.0)
        }
    }

    /// The engine's move in this position, or none when there is no legal move.
    static func reply(to position: MTChessPosition, level: Int) -> MTChessMove? {
        let legal = position.legalMoves()
        guard let only = legal.first else { return nil }
        if legal.count == 1 { return only }
        let plan = plan(level)
        let root = Board(position)
        let children = legal.map { root.child($0) }
        var search = Search(quiet: plan.quiet,
                            deadline: DispatchTime.now().uptimeNanoseconds + UInt64(plan.budget * 1_000_000_000))
        var order = Array(legal.indices)
        var scores = [Int](repeating: 0, count: legal.count)
        for depth in 1...plan.depth {
            search.timed = depth != 1   // the first depth always completes: there is always a move to give
            var round = [Int](repeating: -Search.infinity, count: legal.count)
            var best = -Search.infinity
            for i in order {
                var board = children[i]
                // A move worse than the best by more than the level's error is never chosen: its exact score is not needed.
                let floor = best == -Search.infinity ? -Search.infinity : best - plan.error - 1
                let score = -search.negamax(&board, depth - 1, -Search.infinity, -floor, 1)
                if search.aborted { break }
                round[i] = score
                best = max(best, score)
            }
            if search.aborted { break }
            scores = round
            order.sort { scores[$0] > scores[$1] }
            if best >= Search.mate - 64 { break }   // a mate is found: a deeper search cannot improve on it
        }
        // The level's error: a move within it of the best may be taken instead, never a worse one.
        var chosen = order[0], top = Int.min
        for i in order {
            let noisy = scores[i] + (plan.error > 0 ? Int.random(in: 0...plan.error) : 0)
            if noisy > top { top = noisy; chosen = i }
        }
        return legal[chosen]
    }

    /// The compact board the search walks: a signed code per square (1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king;
    /// white positive, black negative), square 0 = a1.
    struct Board: Sendable {
        struct Step: Sendable { let from: Int; let to: Int; let promote: Int8; let order: Int }
        var cells: [Int8]
        var side: Int8            // 1: white to move, -1: black
        var whiteKing: Int
        var blackKing: Int

        init(_ position: MTChessPosition) {
            var cells = [Int8](repeating: 0, count: 64)
            for square in 0..<64 {
                if let piece = position.piece(at: square) {
                    cells[square] = Int8(Self.code(piece.kind)) * (piece.side == .white ? 1 : -1)
                }
            }
            self.cells = cells
            side = position.turn == .white ? 1 : -1
            whiteKing = cells.firstIndex(of: 6) ?? 4
            blackKing = cells.firstIndex(of: -6) ?? 60
        }
        static func code(_ kind: MTChessKind) -> Int {
            switch kind {
            case .pawn: return 1
            case .knight: return 2
            case .bishop: return 3
            case .rook: return 4
            case .queen: return 5
            case .king: return 6
            }
        }

        /// A root move on a copy, exactly as the rules owner moves: castling carries its rook, en passant takes the pawn beside.
        func child(_ move: MTChessMove) -> Board {
            var next = self
            let piece = cells[move.from], kind = abs(Int(piece))
            if kind == 1, move.from % 8 != move.to % 8, cells[move.to] == 0 { next.cells[move.to - 8 * Int(side)] = 0 }
            if kind == 6, abs(move.to - move.from) == 2 {
                let rook = move.to > move.from ? move.from + 3 : move.from - 4
                next.cells[(move.from + move.to) / 2] = next.cells[rook]
                next.cells[rook] = 0
            }
            next.cells[move.to] = move.promotion.map { Int8(Self.code($0)) * side } ?? piece
            next.cells[move.from] = 0
            if piece == 6 { next.whiteKing = move.to } else if piece == -6 { next.blackKing = move.to }
            next.side = -side
            return next
        }

        mutating func make(_ step: Step) -> Int8 {
            let piece = cells[step.from], taken = cells[step.to]
            cells[step.to] = step.promote == 0 ? piece : step.promote * side
            cells[step.from] = 0
            if piece == 6 { whiteKing = step.to } else if piece == -6 { blackKing = step.to }
            side = -side
            return taken
        }
        mutating func unmake(_ step: Step, _ taken: Int8) {
            side = -side
            let piece = step.promote == 0 ? cells[step.to] : side
            cells[step.from] = piece
            cells[step.to] = taken
            if piece == 6 { whiteKing = step.from } else if piece == -6 { blackKing = step.from }
        }

        /// The side to move is in check.
        var inCheck: Bool { attacked(side == 1 ? whiteKing : blackKing, by: -side) }
        /// After a move: the side that made it left its own king attacked, and the move was not legal.
        var moverExposed: Bool { attacked(side == 1 ? blackKing : whiteKing, by: side) }

        static let knightJumps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        static let kingSteps = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        static let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        static let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        static let queenRays = straight + diagonal
        static let sliders: [([(Int, Int)], Int8)] = [(straight, 4), (diagonal, 3)]
        static let worth = [0, 100, 320, 330, 500, 900, 20000]

        func attacked(_ square: Int, by attacker: Int8) -> Bool {
            let file = square % 8, rank = square / 8
            let behind = rank - Int(attacker)   // an attacking pawn stands one rank behind, the way it moves
            if (0..<8).contains(behind) {
                if file > 0, cells[behind * 8 + file - 1] == attacker { return true }
                if file < 7, cells[behind * 8 + file + 1] == attacker { return true }
            }
            for (df, dr) in Self.knightJumps {
                let f = file + df, r = rank + dr
                if (0..<8).contains(f), (0..<8).contains(r), cells[r * 8 + f] == 2 * attacker { return true }
            }
            for (df, dr) in Self.kingSteps {
                let f = file + df, r = rank + dr
                if (0..<8).contains(f), (0..<8).contains(r), cells[r * 8 + f] == 6 * attacker { return true }
            }
            for (rays, slider) in Self.sliders {
                for (df, dr) in rays {
                    var f = file + df, r = rank + dr
                    while (0..<8).contains(f), (0..<8).contains(r) {
                        let piece = cells[r * 8 + f]
                        if piece != 0 {
                            if piece == slider * attacker || piece == 5 * attacker { return true }
                            break
                        }
                        f += df; r += dr
                    }
                }
            }
            return false
        }

        /// The moves of the side to move, own king's safety not yet judged, the likeliest good ones first.
        func steps(capturesOnly: Bool, into out: inout [Step]) {
            out.removeAll(keepingCapacity: true)
            for from in 0..<64 {
                let piece = cells[from]
                guard piece != 0, (piece > 0) == (side > 0) else { continue }
                let kind = abs(Int(piece)), file = from % 8, rank = from / 8
                func add(_ to: Int, promote: Int8 = 0) {
                    let target = cells[to]
                    let gain = target == 0 ? 0 : Self.worth[abs(Int(target))] * 16 - kind
                    out.append(Step(from: from, to: to, promote: promote, order: gain + (promote == 0 ? 0 : 8000)))
                }
                func enemy(_ target: Int8) -> Bool { target != 0 && (target > 0) != (side > 0) }
                switch kind {
                case 1:
                    let ahead = rank + Int(side)
                    guard (0..<8).contains(ahead) else { break }
                    let last = ahead == 0 || ahead == 7
                    let promote: Int8 = last ? 5 : 0
                    if cells[ahead * 8 + file] == 0, !capturesOnly || last {
                        add(ahead * 8 + file, promote: promote)
                        let two = rank + 2 * Int(side)
                        if !capturesOnly, rank == (side == 1 ? 1 : 6), cells[two * 8 + file] == 0 { add(two * 8 + file) }
                    }
                    for df in [-1, 1] {
                        let f = file + df
                        if (0..<8).contains(f), enemy(cells[ahead * 8 + f]) { add(ahead * 8 + f, promote: promote) }
                    }
                case 2, 6:
                    for (df, dr) in kind == 2 ? Self.knightJumps : Self.kingSteps {
                        let f = file + df, r = rank + dr
                        guard (0..<8).contains(f), (0..<8).contains(r) else { continue }
                        let target = cells[r * 8 + f]
                        if target == 0 ? !capturesOnly : enemy(target) { add(r * 8 + f) }
                    }
                default:
                    for (df, dr) in kind == 3 ? Self.diagonal : (kind == 4 ? Self.straight : Self.queenRays) {
                        var f = file + df, r = rank + dr
                        while (0..<8).contains(f), (0..<8).contains(r) {
                            let target = cells[r * 8 + f]
                            if target != 0 {
                                if enemy(target) { add(r * 8 + f) }
                                break
                            }
                            if !capturesOnly { add(r * 8 + f) }
                            f += df; r += dr
                        }
                    }
                }
            }
            out.sort { $0.order > $1.order }
        }

        /// Material and placement, from the side to move. The tables read from white's side with the eighth rank first, so a
        /// white piece's square is mirrored and a black piece's is read as it stands.
        func evaluate() -> Int {
            var officers = 0
            for piece in cells where piece != 0 {
                let kind = abs(Int(piece))
                if kind != 1, kind != 6 { officers += Self.worth[kind] }
            }
            let late = officers <= 2600
            var score = 0
            for square in 0..<64 {
                let piece = cells[square]
                guard piece != 0 else { continue }
                let kind = abs(Int(piece)), white = piece > 0
                let table = kind == 6 && late ? Self.kingLate : Self.placement[kind]
                let value = Self.worth[kind] + table[white ? square ^ 56 : square]
                score += white ? value : -value
            }
            return score * Int(side)
        }

        static let placement: [[Int]] = [[], pawn, knight, bishop, rook, queen, kingEarly]
        static let pawn = [
              0,   0,   0,   0,   0,   0,   0,   0,
             50,  50,  50,  50,  50,  50,  50,  50,
             10,  10,  20,  30,  30,  20,  10,  10,
              5,   5,  10,  25,  25,  10,   5,   5,
              0,   0,   0,  20,  20,   0,   0,   0,
              5,  -5, -10,   0,   0, -10,  -5,   5,
              5,  10,  10, -20, -20,  10,  10,   5,
              0,   0,   0,   0,   0,   0,   0,   0]
        static let knight = [
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20,   0,   0,   0,   0, -20, -40,
            -30,   0,  10,  15,  15,  10,   0, -30,
            -30,   5,  15,  20,  20,  15,   5, -30,
            -30,   0,  15,  20,  20,  15,   0, -30,
            -30,   5,  10,  15,  15,  10,   5, -30,
            -40, -20,   0,   5,   5,   0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50]
        static let bishop = [
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10,   0,   0,   0,   0,   0,   0, -10,
            -10,   0,   5,  10,  10,   5,   0, -10,
            -10,   5,   5,  10,  10,   5,   5, -10,
            -10,   0,  10,  10,  10,  10,   0, -10,
            -10,  10,  10,  10,  10,  10,  10, -10,
            -10,   5,   0,   0,   0,   0,   5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20]
        static let rook = [
              0,   0,   0,   0,   0,   0,   0,   0,
              5,  10,  10,  10,  10,  10,  10,   5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
              0,   0,   0,   5,   5,   0,   0,   0]
        static let queen = [
            -20, -10, -10,  -5,  -5, -10, -10, -20,
            -10,   0,   0,   0,   0,   0,   0, -10,
            -10,   0,   5,   5,   5,   5,   0, -10,
             -5,   0,   5,   5,   5,   5,   0,  -5,
              0,   0,   5,   5,   5,   5,   0,  -5,
            -10,   5,   5,   5,   5,   5,   0, -10,
            -10,   0,   5,   0,   0,   0,   0, -10,
            -20, -10, -10,  -5,  -5, -10, -10, -20]
        static let kingEarly = [
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
             20,  20,   0,   0,   0,   0,  20,  20,
             20,  30,  10,   0,   0,  10,  30,  20]
        static let kingLate = [
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10,   0,   0, -10, -20, -30,
            -30, -10,  20,  30,  30,  20, -10, -30,
            -30, -10,  30,  40,  40,  30, -10, -30,
            -30, -10,  30,  40,  40,  30, -10, -30,
            -30, -10,  20,  30,  30,  20, -10, -30,
            -30, -30,   0,   0,   0,   0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50]
    }

    struct Search {
        static let infinity = 1_000_000
        static let mate = 100_000
        let quiet: Bool
        let deadline: UInt64
        var timed = false
        var aborted = false
        var nodes = 0

        init(quiet: Bool, deadline: UInt64) { self.quiet = quiet; self.deadline = deadline }

        private mutating func expired() -> Bool {
            nodes += 1
            if timed, nodes & 1023 == 0, DispatchTime.now().uptimeNanoseconds > deadline { aborted = true }
            return aborted
        }

        mutating func negamax(_ board: inout Board, _ depth: Int, _ alphaIn: Int, _ beta: Int, _ ply: Int) -> Int {
            if expired() { return 0 }
            if depth <= 0 { return quiet ? quiesce(&board, alphaIn, beta, 0) : board.evaluate() }
            var alpha = alphaIn, legal = false
            var list: [Board.Step] = []
            board.steps(capturesOnly: false, into: &list)
            for step in list {
                let taken = board.make(step)
                if board.moverExposed { board.unmake(step, taken); continue }
                legal = true
                let score = -negamax(&board, depth - 1, -beta, -alpha, ply + 1)
                board.unmake(step, taken)
                if aborted { return 0 }
                if score >= beta { return beta }
                if score > alpha { alpha = score }
            }
            // No legal move: mated (the sooner, the worse) or stalemated.
            if !legal { return board.inCheck ? -Self.mate + ply : 0 }
            return alpha
        }

        mutating func quiesce(_ board: inout Board, _ alphaIn: Int, _ beta: Int, _ depth: Int) -> Int {
            if expired() { return 0 }
            let stand = board.evaluate()
            if stand >= beta { return beta }
            var alpha = max(alphaIn, stand)
            if depth >= 8 { return alpha }
            var list: [Board.Step] = []
            board.steps(capturesOnly: true, into: &list)
            for step in list {
                let taken = board.make(step)
                if board.moverExposed { board.unmake(step, taken); continue }
                let score = -quiesce(&board, -beta, -alpha, depth + 1)
                board.unmake(step, taken)
                if aborted { return 0 }
                if score >= beta { return beta }
                if score > alpha { alpha = score }
            }
            return alpha
        }
    }
}
