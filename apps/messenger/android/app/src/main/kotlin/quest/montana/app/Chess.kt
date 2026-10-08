package quest.montana.app

import org.json.JSONObject
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sign

// ─────────────────────────── chess, the rules and the replay (iOS MTChessRules, MTChessWire, MTChessGame) ───────────────────────────

enum class ChessSide(val raw: String) {
    WHITE("white"), BLACK("black");
    val other: ChessSide get() = if (this == WHITE) BLACK else WHITE
}

enum class ChessKind(val raw: String, val points: Int) {
    PAWN("p", 1), KNIGHT("n", 3), BISHOP("b", 3), ROOK("r", 5), QUEEN("q", 9), KING("k", 0);
    companion object { fun of(raw: String): ChessKind? = values().firstOrNull { it.raw == raw } }
}

data class ChessPiece(val side: ChessSide, val kind: ChessKind) {
    /** The author's piece, byte for byte (iOS MTChessPalette.asset: Chess + w/b + the kind's letter). */
    val art: Int get() = when (side) {
        ChessSide.WHITE -> when (kind) { ChessKind.PAWN -> R.drawable.chess_wp; ChessKind.KNIGHT -> R.drawable.chess_wn; ChessKind.BISHOP -> R.drawable.chess_wb
            ChessKind.ROOK -> R.drawable.chess_wr; ChessKind.QUEEN -> R.drawable.chess_wq; ChessKind.KING -> R.drawable.chess_wk }
        ChessSide.BLACK -> when (kind) { ChessKind.PAWN -> R.drawable.chess_bp; ChessKind.KNIGHT -> R.drawable.chess_bn; ChessKind.BISHOP -> R.drawable.chess_bb
            ChessKind.ROOK -> R.drawable.chess_br; ChessKind.QUEEN -> R.drawable.chess_bq; ChessKind.KING -> R.drawable.chess_bk }
    }
    val glyph: String get() = when (kind) {
        ChessKind.KING -> if (side == ChessSide.WHITE) "♔" else "♚"
        ChessKind.QUEEN -> if (side == ChessSide.WHITE) "♕" else "♛"
        ChessKind.ROOK -> if (side == ChessSide.WHITE) "♖" else "♜"
        ChessKind.BISHOP -> if (side == ChessSide.WHITE) "♗" else "♝"
        ChessKind.KNIGHT -> if (side == ChessSide.WHITE) "♘" else "♞"
        ChessKind.PAWN -> if (side == ChessSide.WHITE) "♙" else "♟"
    }
}

data class ChessMove(val from: Int, val to: Int, val promotion: ChessKind? = null) {
    val uci: String get() = ChessPosition.square(from) + ChessPosition.square(to) + (promotion?.raw ?: "")
    companion object {
        fun of(uci: String): ChessMove? {
            if (uci.length != 4 && uci.length != 5) return null
            val from = ChessPosition.index(uci.substring(0, 2)) ?: return null
            val to = ChessPosition.index(uci.substring(2, 4)) ?: return null
            if (uci.length == 5) {
                val kind = ChessKind.of(uci.substring(4)) ?: return null
                if (kind !in listOf(ChessKind.QUEEN, ChessKind.ROOK, ChessKind.BISHOP, ChessKind.KNIGHT)) return null
                return ChessMove(from, to, kind)
            }
            return ChessMove(from, to)
        }
    }
}

/** One rules owner, independent of the screen, transport, clock and storage (iOS MTChessPosition), line for line. */
class ChessPosition private constructor(
    val board: Array<ChessPiece?>, val turn: ChessSide, val castling: Set<Int>, val enPassant: Int?, val halfmoves: Int, val ply: Int
) {
    companion object {
        fun start(): ChessPosition {
            val b = arrayOfNulls<ChessPiece>(64)
            val back = listOf(ChessKind.ROOK, ChessKind.KNIGHT, ChessKind.BISHOP, ChessKind.QUEEN, ChessKind.KING, ChessKind.BISHOP, ChessKind.KNIGHT, ChessKind.ROOK)
            for (f in 0 until 8) {
                b[f] = ChessPiece(ChessSide.WHITE, back[f]); b[8 + f] = ChessPiece(ChessSide.WHITE, ChessKind.PAWN)
                b[48 + f] = ChessPiece(ChessSide.BLACK, ChessKind.PAWN); b[56 + f] = ChessPiece(ChessSide.BLACK, back[f])
            }
            return ChessPosition(b, ChessSide.WHITE, setOf(0, 7, 56, 63), null, 0, 0)
        }
        fun square(n: Int): String = if (n in 0 until 64) "abcdefgh"[n % 8].toString() + (n / 8 + 1) else ""
        fun index(square: String): Int? {
            if (square.length != 2) return null
            val f = square[0] - 'a'; val r = square[1] - '1'
            return if (f in 0..7 && r in 0..7) r * 8 + f else null
        }
    }
    fun piece(at: Int): ChessPiece? = if (at in 0 until 64) board[at] else null
    fun checked(side: ChessSide): Boolean {
        val king = board.indexOf(ChessPiece(side, ChessKind.KING))
        if (king < 0) return true
        return attacked(king, side.other)
    }
    fun attacked(target: Int, by: ChessSide): Boolean {
        val tf = target % 8; val tr = target / 8
        for (from in 0 until 64) {
            val p = board[from] ?: continue
            if (p.side != by) continue
            val df = tf - from % 8; val dr = tr - from / 8
            when (p.kind) {
                ChessKind.PAWN -> if (abs(df) == 1 && dr == (if (by == ChessSide.WHITE) 1 else -1)) return true
                ChessKind.KNIGHT -> if (abs(df) * abs(dr) == 2) return true
                ChessKind.KING -> if (max(abs(df), abs(dr)) == 1) return true
                else -> {
                    if (df == 0 && dr == 0) continue
                    val diagonal = abs(df) == abs(dr); val straight = df == 0 || dr == 0
                    if (!((p.kind != ChessKind.ROOK && diagonal) || (p.kind != ChessKind.BISHOP && straight))) continue
                    val sf = df.sign; val sr = dr.sign
                    var f = from % 8 + sf; var r = from / 8 + sr; var clear = true
                    while (f != tf || r != tr) {
                        if (board[r * 8 + f] != null) { clear = false; break }
                        f += sf; r += sr
                    }
                    if (clear) return true
                }
            }
        }
        return false
    }
    fun legalMoves(source: Int? = null): List<ChessMove> {
        val out = ArrayList<ChessMove>()
        for (from in 0 until 64) {
            if (source != null && from != source) continue
            val p = board[from] ?: continue
            if (p.side != turn) continue
            for (m in candidates(from, p)) if (!applyingUnchecked(m).checked(turn)) out.add(m)
        }
        return out
    }
    private fun candidates(from: Int, p: ChessPiece): List<ChessMove> {
        val out = ArrayList<ChessMove>()
        val file = from % 8; val rank = from / 8
        fun add(f: Int, r: Int) {
            if (f !in 0..7 || r !in 0..7) return
            val to = r * 8 + f
            if (board[to]?.side == p.side || board[to]?.kind == ChessKind.KING) return
            if (p.kind == ChessKind.PAWN && (r == 0 || r == 7)) {
                for (k in listOf(ChessKind.QUEEN, ChessKind.ROOK, ChessKind.BISHOP, ChessKind.KNIGHT)) out.add(ChessMove(from, to, k))
            } else out.add(ChessMove(from, to))
        }
        when (p.kind) {
            ChessKind.PAWN -> {
                val d = if (p.side == ChessSide.WHITE) 1 else -1; val next = rank + d
                if (next in 0..7) {
                    if (board[next * 8 + file] == null) {
                        add(file, next)
                        if (rank == (if (p.side == ChessSide.WHITE) 1 else 6) && board[(rank + 2 * d) * 8 + file] == null) add(file, rank + 2 * d)
                    }
                    for (f in listOf(file - 1, file + 1)) {
                        if (f !in 0..7) continue
                        val to = next * 8 + f
                        if (board[to]?.side == p.side.other) add(f, next)
                        else if (to == enPassant && board[to] == null && board[rank * 8 + f] == ChessPiece(p.side.other, ChessKind.PAWN)) add(f, next)
                    }
                }
            }
            ChessKind.KNIGHT -> for ((df, dr) in listOf(1 to 2, 2 to 1, 2 to -1, 1 to -2, -1 to -2, -2 to -1, -2 to 1, -1 to 2)) add(file + df, rank + dr)
            ChessKind.KING -> {
                for (df in -1..1) for (dr in -1..1) if (df != 0 || dr != 0) add(file + df, rank + dr)
                val base = if (p.side == ChessSide.WHITE) 0 else 56
                if (from == base + 4 && !checked(p.side)) {
                    for ((rook, landing, gaps) in listOf(Triple(base + 7, base + 6, listOf(5, 6)), Triple(base, base + 2, listOf(1, 2, 3)))) {
                        if (rook !in castling || board[rook] != ChessPiece(p.side, ChessKind.ROOK) || !gaps.all { board[base + it] == null }) continue
                        // the transit square is tested with the king moved off its starting square
                        val transit = from + (if (from < landing) 1 else -1)
                        if (!applyingUnchecked(ChessMove(from, transit)).checked(p.side)) add(landing % 8, rank)
                    }
                }
            }
            else -> {
                val diagonal = listOf(1 to 1, 1 to -1, -1 to 1, -1 to -1)
                val straight = listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1)
                val directions = if (p.kind == ChessKind.BISHOP) diagonal else if (p.kind == ChessKind.ROOK) straight else diagonal + straight
                for ((df, dr) in directions) {
                    var f = file + df; var r = rank + dr
                    while (f in 0..7 && r in 0..7) {
                        add(f, r)
                        if (board[r * 8 + f] != null) break
                        f += df; r += dr
                    }
                }
            }
        }
        return out
    }
    fun applying(move: ChessMove): ChessPosition? = if (move in legalMoves(move.from)) applyingUnchecked(move) else null
    private fun applyingUnchecked(m: ChessMove): ChessPosition {
        val p = piece(m.from) ?: return this
        if (m.to !in 0 until 64) return this
        val b = board.copyOf()
        val capture = board[m.to] != null || (p.kind == ChessKind.PAWN && m.to == enPassant)
        b[m.from] = null
        if (p.kind == ChessKind.PAWN && m.to == enPassant && board[m.to] == null) b[m.to + (if (p.side == ChessSide.WHITE) -8 else 8)] = null
        b[m.to] = ChessPiece(p.side, m.promotion ?: p.kind)
        val c = castling.toMutableSet()
        if (p.kind == ChessKind.KING) {
            val base = if (p.side == ChessSide.WHITE) 0 else 56
            c.remove(base); c.remove(base + 7)
            if (abs(m.to - m.from) == 2) {
                val rook = if (m.from < m.to) base + 7 else base
                b[(m.to + m.from) / 2] = b[rook]; b[rook] = null
            }
        }
        c.remove(m.from); c.remove(m.to)
        val ep = if (p.kind == ChessKind.PAWN && abs(m.to - m.from) == 16) (m.to + m.from) / 2 else null
        val half = if (p.kind == ChessKind.PAWN || capture) 0 else halfmoves + 1
        return ChessPosition(b, turn.other, c, ep, half, ply + 1)
    }
    fun notation(move: ChessMove): String? {
        val legal = legalMoves()
        if (move !in legal) return null
        val p = board[move.from] ?: return null
        val next = applyingUnchecked(move)
        var word = ""
        if (p.kind == ChessKind.KING && abs(move.to - move.from) == 2) word = if (move.from < move.to) "O-O" else "O-O-O"
        else {
            val capture = board[move.to] != null || (p.kind == ChessKind.PAWN && move.to == enPassant)
            if (p.kind != ChessKind.PAWN) {
                word = p.kind.raw.uppercase()
                val rivals = legal.filter { it.to == move.to && it.from != move.from && board[it.from]?.kind == p.kind }
                if (rivals.isNotEmpty()) {
                    if (rivals.none { it.from % 8 == move.from % 8 }) word += square(move.from).take(1)
                    else if (rivals.none { it.from / 8 == move.from / 8 }) word += (move.from / 8 + 1).toString()
                    else word += square(move.from)
                }
            } else if (capture) word += square(move.from).take(1)
            if (capture) word += "x"
            word += square(move.to)
            if (move.promotion != null) word += "=" + move.promotion.raw.uppercase()
        }
        if (next.checked(next.turn)) word += if (next.legalMoves().isEmpty()) "#" else "+"
        return word
    }
    val repetitionKey: String get() {
        val pieces = board.joinToString("") { p -> p?.let { if (it.side == ChessSide.WHITE) it.kind.raw.uppercase() else it.kind.raw } ?: "." }
        // an unusable en-passant target does not distinguish positions (including a pinned pawn)
        val ep = enPassant?.takeIf { target -> legalMoves().any { it.to == target && board[it.from]?.kind == ChessKind.PAWN } }
        return pieces + turn.raw + castling.sorted().joinToString(",") + ":" + (ep?.toString() ?: "-")
    }
    val deadMaterial: Boolean get() {
        val men = board.withIndex().filter { it.value != null && it.value!!.kind != ChessKind.KING }
        if (men.isEmpty()) return true
        if (men.size == 1) return men[0].value!!.kind == ChessKind.BISHOP || men[0].value!!.kind == ChessKind.KNIGHT
        return men.all { it.value!!.kind == ChessKind.BISHOP } && men.map { (it.index / 8 + it.index % 8) % 2 }.toSet().size == 1
    }
    fun matingMaterial(side: ChessSide): Boolean {
        val own = board.filterNotNull().filter { it.side == side && it.kind != ChessKind.KING }
        if (own.isEmpty() || deadMaterial) return false
        // with opposing material, a lone minor can sometimes mate with the opponent's help
        val opponent = board.filterNotNull().filter { it.side != side && it.kind != ChessKind.KING }
        if (opponent.isEmpty() && own.size == 1 && (own[0].kind == ChessKind.BISHOP || own[0].kind == ChessKind.KNIGHT)) return false
        return true
    }
}

/** HOW A GAME ENDED, IN THE WORDS OF THE LETTER THAT ENDED IT (iOS MTChessEnd): the outcome as its sender saw it, the cause, the half-moves. */
class ChessEnd(val outcome: String, val cause: String, val moves: Int) {
    fun json(): JSONObject = JSONObject().put("outcome", outcome).put("cause", cause).put("moves", moves)
    val mirrored: String get() = when (outcome) { "won" -> "lost"; "lost" -> "won"; else -> outcome }
    companion object {
        val OUTCOMES = setOf("won", "lost", "drawn", "declined", "ended")
        val CAUSES = setOf("mate", "stalemate", "resign", "time", "agreement", "claim", "material", "repetition", "moves", "declined", "withdrawn", "ended")
    }
}

/**
 * A LETTER OF A GAME (iOS MTChessLetter): an ordinary, receipted letter of the pair — the knight and the title on the first line,
 * montana://chess/1/ and the letter's JSON in base64 with the URL's two letters under it — the same keys the iPhone writes, so
 * both phones replay one game from the same letters. Every letter after the invitation is a step of the game: the board reads it,
 * the feed, the list, the unread count and the banner pass it by; only the invitation and the letter that ends the game ring.
 */
class ChessLetter(
    val game: String, val id: String, val parent: String, val kind: String, val at: Long,
    var move: String? = null, var seconds: Int? = null, var offerDraw: Boolean? = null, var spent: Long? = null,
    var end: ChessEnd? = null, var coins: Long? = null, var stake: Long? = null
) {
    companion object {
        const val INVITE = "invite"; const val ACCEPT = "accept"; const val DECLINE = "decline"; const val MOVE = "move"
        const val RESIGN = "resign"; const val DRAW = "draw"; const val CLAIM = "claim"; const val TIMEOUT = "timeout"; const val END = "end"
        private val KINDS = setOf(INVITE, ACCEPT, DECLINE, MOVE, RESIGN, DRAW, CLAIM, TIMEOUT, END)
        const val LINK = "montana://chess/1/"
        const val MARK = "♟ "
        val TIME_CONTROLS = listOf(0, 300, 600, 900, 1800)
        /** The longest turn a letter may report: a day, so a report is bounded before it is judged. */
        const val LONGEST_TURN = 86_400_000L
        const val MOST_COINS = 1_000_000_000_000L
        /** The author's word of the pot, 06.10.2026 16:10:00 UTC: a game invited from it on has a pot. */
        const val POT_SINCE = 1_791_303_000_000L
        fun isStep(text: String): Boolean = text.startsWith(MARK) && parse(text)?.isStep == true
        /** A step that does not end the game rides a silent push: only the invitation and the closing letter ring. */
        fun silent(text: String): Boolean = text.startsWith(MARK) && parse(text)?.let { it.isStep && !it.rings } == true
        private fun isUuid(s: String): Boolean = s.length == 36 && s.withIndex().all { (i, ch) ->
            if (i == 8 || i == 13 || i == 18 || i == 23) ch == '-' else ch in '0'..'9' || ch in 'a'..'f' || ch in 'A'..'F'
        }
        fun parse(text: String): ChessLetter? {
            if (!text.startsWith(MARK) || 2048 < text.toByteArray(Charsets.UTF_8).size) return null
            val line = text.split("\n").last()
            if (!line.startsWith(LINK)) return null
            val code = line.removePrefix(LINK).replace('-', '+').replace('_', '/')
            val o = runCatching { JSONObject(String(android.util.Base64.decode(code, android.util.Base64.DEFAULT), Charsets.UTF_8)) }.getOrNull() ?: return null
            return runCatching {
                val kind = o.getString("kind")
                if (kind !in KINDS) return null
                val end = o.optJSONObject("end")?.let { e ->
                    val out = e.getString("outcome"); val cause = e.getString("cause")
                    if (out !in ChessEnd.OUTCOMES || cause !in ChessEnd.CAUSES) return null
                    ChessEnd(out, cause, e.getInt("moves"))
                }
                val l = ChessLetter(o.getString("game"), o.getString("id"), o.getString("parent"), kind, o.getLong("at"),
                    if (o.has("move")) o.getString("move") else null, if (o.has("seconds")) o.getInt("seconds") else null,
                    if (o.has("offerDraw")) o.getBoolean("offerDraw") else null, if (o.has("spent")) o.getLong("spent") else null,
                    end, if (o.has("coins")) o.getLong("coins") else null, if (o.has("stake")) o.getLong("stake") else null)
                if (!isUuid(l.game) || !isUuid(l.id) || !(l.parent.isEmpty() || isUuid(l.parent))) return null
                if (l.at !in 0L..32_503_680_000_000L) return null
                if (l.move != null && 5 < l.move!!.toByteArray().size) return null
                if (l.spent != null && !(l.onTurn && l.spent!! in 0L..LONGEST_TURN)) return null
                if (l.end != null && !(l.kind != INVITE && l.kind != ACCEPT && l.end!!.moves in 0..10_000)) return null
                if (l.coins != null && !(l.kind == MOVE && l.coins!! in 0L..MOST_COINS)) return null
                if (l.stake != null && !(l.kind == INVITE && l.stake!! in 1L..MOST_COINS)) return null
                if (l.kind == INVITE) {
                    if (l.id != l.game || l.parent.isNotEmpty() || l.seconds !in TIME_CONTROLS || l.move != null || l.offerDraw != null) return null
                } else {
                    if (l.id == l.game || l.parent.isEmpty() || l.seconds != null) return null
                    if (l.kind != MOVE && l.offerDraw != null) return null
                    if (l.kind != MOVE && l.kind != CLAIM && l.move != null) return null
                }
                l
            }.getOrNull()
        }
    }
    val isStep: Boolean get() = kind != INVITE
    val rings: Boolean get() = kind == INVITE || end != null
    val onTurn: Boolean get() = kind == MOVE || kind == DRAW || kind == CLAIM || kind == TIMEOUT
    val pooled: Boolean get() = kind == INVITE && POT_SINCE <= at
    fun json(): JSONObject = JSONObject().put("game", game).put("id", id).put("parent", parent).put("kind", kind).put("at", at).apply {
        move?.let { put("move", it) }; seconds?.let { put("seconds", it) }; offerDraw?.let { put("offerDraw", it) }
        spent?.let { put("spent", it) }; end?.let { put("end", it.json()) }; coins?.let { put("coins", it) }; stake?.let { put("stake", it) }
    }
    fun text(title: String): String {
        val code = android.util.Base64.encodeToString(json().toString().toByteArray(Charsets.UTF_8), android.util.Base64.NO_WRAP).replace('+', '-').replace('/', '_')
        return MARK + title + "\n" + LINK + code
    }
    override fun equals(other: Any?): Boolean = other is ChessLetter && other.json().toString() == json().toString()
    override fun hashCode(): Int = id.hashCode()
}

class ChessEntry(val letter: ChessLetter, val mine: Boolean)

/**
 * THE REPLAY (iOS MTChessGame): the game read from its letters alone, the same on both phones. The one who invites plays white;
 * every letter is judged by the side it came from; a branch nobody can choose is a conflict, never a guess; a letter whose parent
 * has not come is held.
 */
class ChessGame private constructor(val id: String, val whiteIsMine: Boolean, val seconds: Int, last0: ChessLetter) {
    enum class Status { INVITED, PLAYING, DECLINED, WHITE_WON, BLACK_WON, DRAWN, CONFLICT, ENDED;
        val finished: Boolean get() = this != INVITED && this != PLAYING }
    var status = Status.INVITED; private set
    var position: ChessPosition = ChessPosition.start(); private set
    var positions: MutableList<ChessPosition> = mutableListOf(position); private set
    var moves: MutableList<ChessMove> = mutableListOf(); private set
    var notation: MutableList<String> = mutableListOf(); private set
    var last: ChessLetter = last0; private set
    var whiteMs: Long = seconds * 1000L; private set
    var blackMs: Long = seconds * 1000L; private set
    var drawOfferedBy: ChessSide? = null; private set
    var repetitions: MutableMap<String, Int> = mutableMapOf(); private set
    var waitingForHistory = false; private set
    var acceptedIDs: MutableSet<String> = mutableSetOf(); private set
    var pooled = false; private set
    var stake = 0L; private set
    var accepted = false; private set
    var mintedMine = 0L; private set
    var mintedTheirs = 0L; private set
    /** The pot's two parts: the stakes put in, and the coins the accepted moves minted (iOS stakes, movesPool, pot). */
    val stakes: Long get() = stake * (if (accepted) 2 else 1)
    val movesPool: Long get() = mintedMine + mintedTheirs
    val pot: Long get() = movesPool + stakes
    val mySide: ChessSide get() = if (whiteIsMine) ChessSide.WHITE else ChessSide.BLACK
    val canClaimDraw: Boolean get() = 100 <= position.halfmoves || 3 <= (repetitions[position.repetitionKey] ?: 0)
    /** The side whose clock runs: the side to move, while a game under a clock is being played. */
    val running: ChessSide? get() = if (seconds != 0 && status == Status.PLAYING) position.turn else null

    private fun copy(): ChessGame = ChessGame(id, whiteIsMine, seconds, last).also { g ->
        g.status = status; g.position = position; g.positions = positions.toMutableList(); g.moves = moves.toMutableList()
        g.notation = notation.toMutableList(); g.whiteMs = whiteMs; g.blackMs = blackMs; g.drawOfferedBy = drawOfferedBy
        g.repetitions = repetitions.toMutableMap(); g.waitingForHistory = waitingForHistory; g.acceptedIDs = acceptedIDs.toMutableSet()
        g.pooled = pooled; g.stake = stake; g.accepted = accepted; g.mintedMine = mintedMine; g.mintedTheirs = mintedTheirs
    }
    private fun take(g: ChessGame) {
        status = g.status; position = g.position; positions = g.positions; moves = g.moves; notation = g.notation; last = g.last
        whiteMs = g.whiteMs; blackMs = g.blackMs; drawOfferedBy = g.drawOfferedBy; repetitions = g.repetitions
        waitingForHistory = g.waitingForHistory; acceptedIDs = g.acceptedIDs; pooled = g.pooled; stake = g.stake; accepted = g.accepted
        mintedMine = g.mintedMine; mintedTheirs = g.mintedTheirs
    }

    companion object {
        fun of(entries: List<ChessEntry>, game: String): ChessGame? {
            val relevant = entries.filter { it.letter.game == game }
            val root = relevant.firstOrNull { it.letter.kind == ChessLetter.INVITE } ?: return null
            val duration = root.letter.seconds ?: return null
            if (root.letter.id != game || root.letter.parent.isNotEmpty() || duration !in ChessLetter.TIME_CONTROLS) return null
            val g = ChessGame(game, root.mine, duration, root.letter)
            g.pooled = root.letter.pooled; g.stake = if (g.pooled) root.letter.stake ?: 0L else 0L
            g.acceptedIDs.add(game)
            g.repetitions[g.position.repetitionKey] = 1
            val unique = LinkedHashMap<String, ChessEntry>()
            for (e in relevant) {
                val prev = unique[e.letter.id]
                if (prev != null && (prev.letter != e.letter || prev.mine != e.mine)) { g.status = Status.CONFLICT; return g }
                unique[e.letter.id] = e
            }
            val children = unique.values.filter { it.letter.id != game }.groupBy { it.letter.parent }
            val visited = mutableSetOf(game)
            while (!g.status.finished) {
                val possible = (children[g.last.id] ?: emptyList()).mapNotNull { e -> g.copy().takeIf { it.apply(e) } }
                // AN END CLOSES THE GAME OVER WHATEVER CROSSED IT: either side's end first, then a resignation
                val endings = possible.filter { it.last.kind == ChessLetter.END }.sortedBy { it.last.id }
                val concessions = possible.filter { it.last.kind == ChessLetter.RESIGN }.sortedBy { it.last.id }
                val conceding = concessions.mapNotNull { unique[it.last.id]?.mine }.toSet()
                if (endings.isEmpty() && 1 < conceding.size) { g.status = Status.DRAWN; return g }
                val next = endings.firstOrNull() ?: concessions.firstOrNull() ?: (if (possible.size == 1) possible[0] else null)
                if (next == null) { if (1 < possible.size) g.status = Status.CONFLICT; break }
                if (!visited.add(next.last.id)) { g.status = Status.CONFLICT; break }
                g.take(next)
                g.acceptedIDs.add(g.last.id)
            }
            // AN END WHOSE PARENT NEVER CAME STILL ENDS THE GAME
            if (!g.status.finished) {
                unique.values.filter { it.letter.kind == ChessLetter.END }.minByOrNull { it.letter.id }?.let { stray ->
                    g.status = Status.ENDED; g.last = stray.letter; g.acceptedIDs.add(stray.letter.id)
                }
            }
            // a child whose parent has not arrived is held, never applied to a guessed position; an ended game holds nothing
            g.waitingForHistory = g.status != Status.ENDED && unique.values.any { it.letter.kind != ChessLetter.INVITE && unique[it.letter.parent] == null }
            return g
        }
        /** THE PAIR'S ONE GAME: the newest invitation between the two, by its stamp, then its name. */
        fun current(entries: List<ChessEntry>): String? =
            entries.map { it.letter }.filter { it.kind == ChessLetter.INVITE }.maxWithOrNull(compareBy<ChessLetter>({ it.at }, { it.id }))?.game
    }

    /** A game a newer invitation replaced is over: closed by the pair's letters alone, no letter sent. */
    fun replaced(by: String?): ChessGame {
        if (by == null || by == id || status.finished) return this
        return copy().also { it.status = Status.ENDED; it.waitingForHistory = false }
    }
    fun held(side: ChessSide): Long = if (side == ChessSide.WHITE) whiteMs else blackMs
    fun remaining(side: ChessSide, elapsed: Long): Long = if (running != side) held(side) else max(0L, held(side) - max(0L, elapsed))

    /** The letter of an action, judged before it leaves: null when the replay would refuse it. */
    fun action(kind: String, at: Long, move: String? = null, offeringDraw: Boolean = false, spent: Long? = null, mine: Boolean = true): ChessLetter? {
        if (!(kind == ChessLetter.END || !waitingForHistory) || status.finished) return null
        val event = ChessLetter(id, UUID.randomUUID().toString().lowercase(), last.id, kind, max(last.at, at), move,
            offerDraw = if (kind == ChessLetter.MOVE) offeringDraw else null)
        if (seconds != 0 && event.onTurn && spent != null) event.spent = minOf(max(0L, spent), ChessLetter.LONGEST_TURN)
        val next = copy()
        if (!next.apply(ChessEntry(event, mine))) return null
        // THE CLOSING LETTER NAMES THE END, judged by the replay it has just passed, in its sender's own words
        if (next.status.finished) event.end = next.ending(if (mine == whiteIsMine) ChessSide.WHITE else ChessSide.BLACK, kind)
        return event
    }
    private fun ending(actor: ChessSide, kind: String): ChessEnd {
        val outcome = when (status) {
            Status.WHITE_WON -> if (actor == ChessSide.WHITE) "won" else "lost"
            Status.BLACK_WON -> if (actor == ChessSide.BLACK) "won" else "lost"
            Status.DECLINED -> "declined"
            Status.ENDED -> "ended"
            else -> "drawn"
        }
        val cause = when (kind) {
            ChessLetter.DECLINE -> if (actor == ChessSide.WHITE) "withdrawn" else "declined"
            ChessLetter.RESIGN -> "resign"
            ChessLetter.TIMEOUT -> "time"
            ChessLetter.DRAW -> "agreement"
            ChessLetter.CLAIM -> "claim"
            ChessLetter.END -> "ended"
            else -> if (position.legalMoves().isEmpty()) (if (position.checked(position.turn)) "mate" else "stalemate")
                else if (position.deadMaterial) "material" else if (150 <= position.halfmoves) "moves" else "repetition"
        }
        return ChessEnd(outcome, cause, moves.size)
    }
    private fun win(side: ChessSide) { status = if (side == ChessSide.WHITE) Status.WHITE_WON else Status.BLACK_WON }
    private fun apply(entry: ChessEntry): Boolean {
        val event = entry.letter
        val actor = if (entry.mine == whiteIsMine) ChessSide.WHITE else ChessSide.BLACK
        if (event.parent != last.id || event.at < last.at) return false
        if (event.kind == ChessLetter.END) { status = Status.ENDED; last = event; return true }
        if (status == Status.INVITED) {
            val ok = (actor == ChessSide.BLACK && (event.kind == ChessLetter.ACCEPT || event.kind == ChessLetter.DECLINE)) ||
                (actor == ChessSide.WHITE && event.kind == ChessLetter.DECLINE)
            if (!ok) return false
            status = if (event.kind == ChessLetter.ACCEPT) Status.PLAYING else Status.DECLINED
            accepted = event.kind == ChessLetter.ACCEPT
            last = event; return true
        }
        if (status != Status.PLAYING) return false
        if (event.kind == ChessLetter.RESIGN) {
            if (position.matingMaterial(actor.other)) win(actor.other) else status = Status.DRAWN
            last = event; return true
        }
        if (actor != position.turn) return false
        // the turn's cost: its owner's own measure when the letter carries one, the difference of stamps before it did
        val time = held(actor) - (event.spent ?: max(0L, event.at - last.at))
        if (event.kind == ChessLetter.TIMEOUT) {
            // only the owner of a clock concedes it, and only when its own measure has run out
            if (seconds <= 0 || 0L < time) return false
            if (actor == ChessSide.WHITE) whiteMs = 0 else blackMs = 0
            if (position.matingMaterial(actor.other)) win(actor.other) else status = Status.DRAWN
            last = event; return true
        }
        if (seconds != 0 && time <= 0) return false
        if (event.kind == ChessLetter.DRAW) {
            if (drawOfferedBy != actor.other) return false
            status = Status.DRAWN; last = event; return true
        }
        if (event.kind == ChessLetter.CLAIM) {
            var valid = canClaimDraw
            val m = event.move?.let { ChessMove.of(it) }
            val after = m?.let { position.applying(it) }
            if (after != null) valid = 100 <= after.halfmoves || 2 <= (repetitions[after.repetitionKey] ?: 0)
            if (!valid) return false
            status = Status.DRAWN; last = event; return true
        }
        if (event.kind != ChessLetter.MOVE) return false
        val move = event.move?.let { ChessMove.of(it) } ?: return false
        val word = position.notation(move) ?: return false
        val next = position.applying(move) ?: return false
        if (0 < seconds) { if (actor == ChessSide.WHITE) whiteMs = time else blackMs = time }
        position = next; positions.add(next); moves.add(move); notation.add(word)
        drawOfferedBy = if (event.offerDraw == true) actor else null
        last = event
        if (pooled) { if (entry.mine) mintedMine += event.coins ?: 0L else mintedTheirs += event.coins ?: 0L }
        val key = position.repetitionKey
        repetitions[key] = (repetitions[key] ?: 0) + 1
        if (position.legalMoves().isEmpty()) { if (position.checked(position.turn)) win(actor) else status = Status.DRAWN }
        else if (position.deadMaterial || 150 <= position.halfmoves || 5 <= (repetitions[key] ?: 0)) status = Status.DRAWN
        return true
    }
}

/** THE PAIR'S SCORE (iOS MTChessScore): every game counted by its own replay, from this phone's seat. */
class ChessScore(games: List<ChessGame>) {
    var mine = 0; private set
    var theirs = 0; private set
    var drawn = 0; private set
    init {
        for (g in games) when (g.status) {
            ChessGame.Status.WHITE_WON -> if (g.whiteIsMine) mine++ else theirs++
            ChessGame.Status.BLACK_WON -> if (g.whiteIsMine) theirs++ else mine++
            ChessGame.Status.DRAWN -> drawn++
            else -> {}
        }
    }
}
