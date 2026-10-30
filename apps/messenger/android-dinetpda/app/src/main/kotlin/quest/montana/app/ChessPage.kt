package quest.montana.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.util.UUID

// ─────────────────────────── chess between two phones (iOS MTChessScreen: MTChessSend, MTChessCoins, MTChessAnchor, MTChessWords, MTChessPage, MTChessGameScreen) ───────────────────────────

/**
 * THE GAME'S LETTERS RIDE THE PAIR'S OWN ROAD (iOS MTChessSend): a letter of a game is an ordinary letter of the pair; only the
 * invitation and the closing letter ring, every other step rides a silent push and stands in the feed for the board alone.
 * THE GAME'S POT (iOS MTChessCoins, the author's words 06.10.2026 19:0x-19:1x MSK): a move names its maker's level times a
 * thousand into the pot, each side's stake leaves its book as its letter leaves, and the end pays the pot from the replay both
 * phones share — the winner mints every coin of the moves and takes both stakes, a draw or an ended game gives each their own.
 */
object ChessSend {
    const val CHAT_CLOCK = 600
    private const val POT = "chess-pot:"
    private const val STAKE = "chess-stake:"
    private const val BACK = "chess-back:"
    private const val MOVE_TIMES = 1000L
    fun now(): Long = System.currentTimeMillis()

    /** The game's letter a row is in its own right: a forward, a reply, an edited row or a file is none. */
    fun letterOf(m: Msg): ChessLetter? = if (m.qt != null || m.edited || m.file != null) null else ChessLetter.parse(m.text)
    fun entries(ref: String): List<ChessEntry> = Book.chat(ref)?.msgs?.mapNotNull { m -> letterOf(m)?.let { ChessEntry(it, m.mine) } } ?: emptyList()
    /** A game as the replay reads it now, against the pair's one game: a game a newer invitation replaced reads as over. */
    fun state(ref: String, game: String): ChessGame? {
        val all = entries(ref)
        return ChessGame.of(all.filter { it.letter.game == game }, game)?.replaced(ChessGame.current(all))
    }
    fun canPlay(ref: String): Boolean = CoinSend.canPay(ref)

    fun send(c: Context, ref: String, packet: ChessLetter): Boolean {
        if (!canPlay(ref)) { Log.i("Montana", "chess_refused kind=" + packet.kind + " why=pair"); return false }
        val invite = if (packet.kind == ChessLetter.INVITE) packet
            else entries(ref).firstOrNull { it.letter.kind == ChessLetter.INVITE && it.letter.game == packet.game }?.letter
        val pooled = invite?.pooled ?: false
        if (pooled && packet.kind == ChessLetter.MOVE) packet.coins = moveCoins()
        val stake = if (pooled && (packet.kind == ChessLetter.INVITE || packet.kind == ChessLetter.ACCEPT)) invite?.stake ?: 0L else 0L
        if (0L < stake && !put(stake, packet.game, ref)) { Log.i("Montana", "chess_refused kind=" + packet.kind + " why=stake"); return false }
        val text = packet.text(c.getString(R.string.chess_title))
        val mid = Marks.mintMid()
        Book.edit(ref) { it.msgs.add(Msg(mid, text, true, Marks.birthMs(mid) ?: now())) }
        Post.send(ref, mid, text)
        Log.i("Montana", "chess_tx kind=" + packet.kind + " game=" + packet.game.take(8))
        settle(ref)
        return true
    }

    /** A step of theirs landed (Post): kept as a row for the board, read at once, receipted; the closing letter rings. */
    fun landed(ref: String, mid: String, text: String) {
        val letter = ChessLetter.parse(text) ?: return
        var fresh = false
        Book.edit(ref) { c ->
            if (c.msgs.none { it.mid == mid }) {
                c.msgs.add(Msg(mid, text, false, Marks.birthMs(mid) ?: now(), state = 3, statusAt = now()))
                c.msgs.sortBy { it.at }
                fresh = true
            }
        }
        Post.receiptFor(ref, mid)
        if (fresh && letter.rings && shownGame != letter.game) Notify.letter(ref, text)
        settle(ref)
    }

    fun invite(c: Context, ref: String, seconds: Int, stake: Long = 0): String? {
        val id = UUID.randomUUID().toString().lowercase()
        val packet = ChessLetter(id, id, "", ChessLetter.INVITE, now(), seconds = seconds, stake = if (0L < stake) minOf(stake, ChessLetter.MOST_COINS) else null)
        return if (send(c, ref, packet)) id else null
    }
    /** ENTERING IS THE PERSON'S PRESS (iOS join): an unanswered invitation of theirs, accepted by the replay's own action. */
    fun join(c: Context, ref: String, game: String): String? {
        val now = state(ref, game) ?: return null
        if (now.status != ChessGame.Status.INVITED || now.whiteIsMine) return null
        val event = now.action(ChessLetter.ACCEPT, now()) ?: return null
        return if (send(c, ref, event)) event.id else null
    }
    fun awaitsMe(ref: String, game: String): Boolean = state(ref, game)?.let { it.status == ChessGame.Status.INVITED && !it.whiteIsMine } ?: false

    /** The game on the screen: its own letters raise no banner (iOS MTChessGameScreen.shownGame). */
    @Volatile var shownGame: String? = null

    fun moveCoins(): Long = runCatching { Math.multiplyExact(PiLevels.multiplier(CoinBook.balance), MOVE_TIMES) }.getOrDefault(0L).coerceAtMost(ChessLetter.MOST_COINS)
    /** The stake leaves the book into the game's pot; a stake already put is not put twice; a short balance refuses it. */
    private fun put(stake: Long, game: String, peer: String): Boolean =
        stake <= CoinBook.coins(POT + game) || CoinBook.spend(stake, POT + game, peer, STAKE + game)
    /** This side's share of a finished pot: what it mints, what comes back, what it put (iOS share). */
    fun share(g: ChessGame): Triple<Long, Long, Long>? {
        if (!g.pooled || !g.status.finished) return null
        val won: Boolean? = if (g.status == ChessGame.Status.WHITE_WON) g.whiteIsMine else if (g.status == ChessGame.Status.BLACK_WON) !g.whiteIsMine else null
        val mineIn = if (g.whiteIsMine || g.accepted) g.stake else 0L
        val theirsIn = if (!g.whiteIsMine || g.accepted) g.stake else 0L
        return when (won) {
            true -> Triple(g.mintedMine + g.mintedTheirs, mineIn + theirsIn, mineIn)
            false -> Triple(0L, 0L, mineIn)
            null -> Triple(g.mintedMine, mineIn, mineIn)
        }
    }
    /** What the game gave or took (iOS net): this side's share against what it put. */
    fun net(g: ChessGame): Long? = share(g)?.let { it.first + it.second - it.third }
    /** THE POT PAID AT THE END: each phone books its own side once, by the game's names. */
    fun settle(ref: String) {
        val all = entries(ref)
        if (all.isEmpty()) return
        val current = ChessGame.current(all)
        for ((id, list) in all.groupBy { it.letter.game }) {
            val g = ChessGame.of(list, id)?.replaced(current) ?: continue
            val s = share(g) ?: continue
            val got = if (0L < s.first) CoinBook.mint(s.first, POT + id) else 0L
            val back = 0L < s.second && CoinBook.receive(s.second, ref, BACK + id)
            if (0L < got || back) Log.i("Montana", "chess_coin game=" + id.take(8) + " pot minted=" + got + " back=" + back)
        }
    }

    /** Every pair's games settled, at the app's front. */
    fun settleAll() { for (c in Book.all()) if (c.msgs.any { it.text.startsWith(ChessLetter.MARK) }) settle(c.ref) }
}

/**
 * WHEN THE RUNNING CLOCK BEGAN, ON THIS PHONE (iOS MTChessAnchor): my turn from the moment the correspondent's letter landed here,
 * theirs from the moment their phone confirmed mine — a letter on the road is nobody's thinking; a letter whose moment this phone
 * never saw runs from its own stamp.
 */
class ChessAnchor private constructor(private val kind: Int, private val at: Long) {
    val runs: Boolean get() = kind != 0
    fun elapsed(now: Long = System.currentTimeMillis()): Long = if (kind == 0) 0L else maxOf(0L, now - at)
    companion object {
        val STANDING = ChessAnchor(0, 0)
        fun of(g: ChessGame, ref: String): ChessAnchor {
            val side = g.running ?: return STANDING
            val row = Book.chat(ref)?.msgs?.lastOrNull { ChessSend.letterOf(it)?.id == g.last.id } ?: return ChessAnchor(2, g.last.at)
            if (side == g.mySide) return if (0L < row.statusAt) ChessAnchor(1, row.statusAt) else ChessAnchor(2, g.last.at)
            return if (row.state == 2 || row.state == 3) ChessAnchor(1, row.statusMoment) else STANDING
        }
    }
}

/** The words of a game (iOS MTChessWords). */
object ChessWords {
    fun status(c: Context, g: ChessGame): String {
        if (g.waitingForHistory) return c.getString(R.string.chess_waiting_history)
        return c.getString(when (g.status) {
            ChessGame.Status.INVITED -> if (g.whiteIsMine) R.string.chess_waiting_accept else R.string.chess_invitation
            ChessGame.Status.PLAYING -> if (g.position.checked(g.position.turn)) R.string.chess_check
                else if (g.position.turn == g.mySide) R.string.chess_your_move else R.string.chess_their_move
            ChessGame.Status.DECLINED -> R.string.chess_declined
            ChessGame.Status.WHITE_WON -> R.string.chess_white_wins
            ChessGame.Status.BLACK_WON -> R.string.chess_black_wins
            ChessGame.Status.DRAWN -> R.string.chess_draw
            ChessGame.Status.ENDED -> R.string.chess_ended
            ChessGame.Status.CONFLICT -> R.string.chess_conflict
        })
    }
    fun control(c: Context, seconds: Int): String = if (seconds == 0) c.getString(R.string.chess_no_clock) else (seconds / 60).toString() + ":00"
    /** The invitation says who plays which colour, with the clock, and its stake when it names one. */
    fun seat(c: Context, l: ChessLetter, mine: Boolean): String {
        val seat = c.getString(if (mine) R.string.chess_you_white else R.string.chess_you_black) + " · " + control(c, l.seconds ?: 0)
        val stake = l.stake ?: 0L
        return if (0L < stake) seat + " · " + c.getString(R.string.chess_stake, CoinText.count(stake)) else seat
    }
    fun clock(ms: Long): String {
        val s = maxOf(0L, (ms + 999) / 1000)
        return (s / 60).toString() + ":" + (s % 60).toString().padStart(2, '0')
    }
    fun score(c: Context, s: ChessScore): String = c.getString(R.string.chess_score, s.mine, s.theirs, s.drawn)
}

/**
 * THE BOARD (iOS MTChessBoardCanvas): the supplied board's two greens sampled in sRGB, the last move and the selected square lit,
 * the king in check on red, the author's pieces drawn into their squares, the destinations as dots and rings, the files and ranks
 * in the corner ink. A tap names its square; the board takes no finger while no move can be made.
 */
class ChessBoardView(c: Context) : View(c) {
    var position: ChessPosition = ChessPosition.start()
    var facing = ChessSide.WHITE
    var selected: Int? = null
    var destinations: Set<Int> = emptySet()
    var lastMove: ChessMove? = null
    var enabledMoves = false
    var onSquare: ((Int) -> Unit)? = null
    private val art = HashMap<Int, Bitmap>()
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply { isFakeBoldText = true }
    private val src = Rect()
    private val box = RectF()
    companion object {
        val LIGHT = Color.rgb(238, 238, 214)
        val DARK = Color.rgb(124, 149, 92)
        val LAST_LIGHT = Color.rgb(246, 246, 146)
        val LAST_DARK = Color.rgb(186, 202, 68)
    }
    private fun bitmap(res: Int): Bitmap = art.getOrPut(res) { BitmapFactory.decodeResource(resources, res) }
    private fun square(row: Int, col: Int): Int = if (facing == ChessSide.WHITE) (7 - row) * 8 + col else row * 8 + 7 - col
    fun redraw() { invalidate(); contentDescription = context.getString(R.string.chess_title) }
    override fun onMeasure(w: Int, h: Int) { val s = MeasureSpec.getSize(w); setMeasuredDimension(s, s) }
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!enabledMoves) return false
        if (e.actionMasked == MotionEvent.ACTION_UP) {
            val cell = width / 8f
            if (0f < cell) onSquare?.invoke(square(minOf(7, (e.y / cell).toInt()), minOf(7, (e.x / cell).toInt())))
            performClick()
        }
        return true
    }
    override fun performClick(): Boolean { super.performClick(); return true }
    override fun onDraw(canvas: Canvas) {
        val cell = width / 8f
        val check = ChessSide.values().filter { position.checked(it) }.toSet()
        for (row in 0 until 8) for (col in 0 until 8) {
            val sq = square(row, col)
            val light = (sq / 8 + sq % 8) % 2 == 1
            box.set(col * cell, row * cell, (col + 1) * cell, (row + 1) * cell)
            val lit = lastMove?.from == sq || lastMove?.to == sq || selected == sq
            fill.style = Paint.Style.FILL
            fill.color = if (lit) (if (light) LAST_LIGHT else LAST_DARK) else (if (light) LIGHT else DARK)
            canvas.drawRect(box, fill)
            val p = position.piece(sq)
            if (p != null) {
                if (p.kind == ChessKind.KING && p.side in check) { fill.color = Color.argb(140, 255, 69, 58); canvas.drawRect(box, fill) }
                val b = bitmap(p.art)
                src.set(0, 0, b.width, b.height)
                canvas.drawBitmap(b, src, box, null)
            }
            if (sq in destinations) {
                if (p == null) {
                    fill.color = Color.argb(51, 0, 0, 0)
                    canvas.drawOval(RectF(box.left + cell * 0.36f, box.top + cell * 0.36f, box.right - cell * 0.36f, box.bottom - cell * 0.36f), fill)
                } else {
                    fill.style = Paint.Style.STROKE; fill.strokeWidth = cell * 0.07f; fill.color = Color.argb(64, 0, 0, 0)
                    canvas.drawOval(RectF(box.left + cell * 0.055f, box.top + cell * 0.055f, box.right - cell * 0.055f, box.bottom - cell * 0.055f), fill)
                    fill.style = Paint.Style.FILL
                }
            }
            ink.color = if (light) DARK else LIGHT
            ink.textSize = maxOf(10f * resources.displayMetrics.density, cell * 0.16f)
            if (col == 0) canvas.drawText((sq / 8 + 1).toString(), box.left + 3f, box.top + ink.textSize, ink)
            if (row == 7) canvas.drawText(ChessPosition.square(sq).take(1), box.right - cell * 0.18f, box.bottom - cell * 0.06f, ink)
        }
    }
}

/** The game's state on its own plate over the board: the app's glass while no move can be made (iOS MTChessStatePlate). */
private fun Context.statePlate(build: LinearLayout.() -> Unit) = vstack {
    background = rounded(Color.argb(235, 28, 28, 30), 22)
    setPadding(dp(22), dp(10), dp(22), dp(10))
    minimumWidth = dp(180)
    build()
}

/** A round mark of the bar: the glyph alone, the word for the screen reader (iOS MontanaBarMark). */
private fun Context.barMark(glyph: Int, word: Int, tint: Int = Color.WHITE, onTap: () -> Unit) = icon(glyph, tint).apply {
    setPadding(dp(10), dp(10), dp(10), dp(10)); contentDescription = getString(word); pressable(onTap)
}

/**
 * THE GAME'S SCREEN (iOS MTChessGameScreen): the move strip, the correspondent above and me below with our faces, the pieces each
 * has taken and the clocks, the board between, the game's state on its plate over the board while no move can be made, the
 * status, the delivery of my last letter, and the bar: the moves, the chat, the move before and after. The menu holds the
 * flip, the live position, the draws, the resignation, the end and the next game under the pair's score.
 */
fun chessBoardPage(act: MainActivity, ref: String, game0: String, inChat: Boolean, onBack: () -> Unit): View {
    val c: Context = act
    var gameId = game0
    var game: ChessGame? = null
    var anchor = ChessAnchor.STANDING
    var browsing: Int? = null
    var selected: Int? = null
    var flipped = false
    var offerDraw = false
    var claimWithMove = false
    var pending: String? = null
    var pairOver = true
    var sawLive = false
    var timeoutAsked: String? = null   // the clock's end is asked once a turn, never again at every tick
    var score = ChessScore(emptyList())
    val main = Handler(Looper.getMainLooper())

    val board = ChessBoardView(c)
    val plateHolder = FrameLayout(c)
    val strip = c.hstack { setPadding(dp(12), 0, dp(12), 0) }
    val stripScroll = HorizontalScrollView(c).apply { isHorizontalScrollBarEnabled = false; addView(strip) }
    val topRow = c.hstack { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), dp(8), dp(14), dp(8)) }
    val bottomRow = c.hstack { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), dp(8), dp(14), dp(8)) }
    val status = c.text("", 15f)
    val drawMark = c.barMark(R.drawable.ic_equal, R.string.chess_accept_draw) { }
    val notes = c.text("", 12f, MT.gray, center = true)
    val delivery = c.hstack { gravity = Gravity.CENTER }
    val clocks = HashMap<ChessSide, TextView>()

    fun chat() = Book.chat(ref)
    fun allowed() = ChessSend.canPlay(ref)
    fun canSend() = pending == null && allowed() && game?.waitingForHistory == false
    fun live() = browsing == null && canSend()
    fun failed() { AlertDialog.Builder(act).setTitle(R.string.chess_move_failed).setPositiveButton(R.string.ok, null).show() }

    lateinit var draw: () -> Unit
    lateinit var reload: () -> Unit

    fun send(kind: String, move: String? = null, drawing: Boolean = false) {
        val g = game ?: return
        val free = pending == null && allowed()
        if (!(if (kind == ChessLetter.END) free else canSend())) return
        if (!(kind == ChessLetter.END || kind == ChessLetter.TIMEOUT || browsing == null)) return
        selected = null
        // the action is judged against the letters as they stand now, never against an older board on the screen
        val current = ChessSend.state(ref, gameId)
        if (current == null || current.last.id != g.last.id) { failed(); return }
        val spent = if (current.running == current.mySide) ChessAnchor.of(current, ref).elapsed() else null
        val event = current.action(kind, ChessSend.now(), move, drawing, spent)
        if (event == null) { failed(); return }
        pending = event.id
        if (!ChessSend.send(c, ref, event)) { pending = null; failed() }
        reload()
    }
    fun play(m: ChessMove) {
        if (claimWithMove) { send(ChessLetter.CLAIM, m.uci); claimWithMove = false }
        else { send(ChessLetter.MOVE, m.uci, offerDraw); offerDraw = false }
    }
    fun promote(moves: List<ChessMove>) {
        val g = game ?: return
        lateinit var dialog: AlertDialog
        val row = c.hstack {
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(16), dp(12), dp(8))
            for (m in moves) {
                val kind = m.promotion ?: continue
                addView(ImageView(c).apply {
                    setImageResource(ChessPiece(g.mySide, kind).art); setPadding(dp(4), dp(4), dp(4), dp(4))
                    pressable { dialog.dismiss(); play(m) }
                }, lp(dp(60), dp(60)).apply { marginEnd = dp(10) })
            }
        }
        dialog = AlertDialog.Builder(act).setTitle(R.string.chess_promote).setView(row).setNegativeButton(R.string.chess_cancel, null).create()
        dialog.show()
    }
    fun press(sq: Int) {
        val g = game ?: return
        if (!live() || g.status != ChessGame.Status.PLAYING || g.mySide != g.position.turn) return
        val sel = selected
        if (sel != null) {
            val moves = g.position.legalMoves(sel).filter { it.to == sq }
            if (1 < moves.size) { promote(moves); return }
            if (moves.isNotEmpty()) { play(moves[0]); return }
        }
        selected = if (g.position.piece(sq)?.side == g.mySide && sel != sq) sq else null
        draw()
    }
    fun browse(delta: Int) {
        val g = game ?: return
        val n = maxOf(0, minOf(g.moves.size, (browsing ?: g.moves.size) + delta))
        browsing = if (n == g.moves.size) null else n; selected = null; draw()
    }
    fun again(g: ChessGame) {
        browsing = null; selected = null
        val id = ChessSend.invite(c, ref, g.seconds, g.stake)
        if (id == null) failed() else { gameId = id; ChessSend.shownGame = id; reload() }
    }
    fun captured(g: ChessGame, side: ChessSide): String {
        val step = minOf(browsing ?: g.moves.size, g.moves.size)
        val remaining = g.positions[step].board.filterNotNull()
        val taken = ArrayList<ChessPiece>()
        for (i in 0 until step) {
            val m = g.moves[i]; val before = g.positions[i]
            if (before.turn != side) continue
            val mover = before.piece(m.from) ?: continue
            val piece = before.piece(m.to)
            if (piece != null) taken.add(piece) else if (mover.kind == ChessKind.PAWN && m.from % 8 != m.to % 8) taken.add(ChessPiece(side.other, ChessKind.PAWN))
        }
        val advantage = remaining.filter { it.side == side }.sumOf { it.kind.points } - remaining.filter { it.side != side }.sumOf { it.kind.points }
        return taken.sortedBy { it.kind.points }.joinToString("") { it.glyph } + (if (0 < advantage) " +" + advantage else "")
    }
    fun player(row: LinearLayout, g: ChessGame, side: ChessSide) {
        val mine = side == g.mySide
        row.removeAllViews()
        val name = if (mine) Prefs.userName.ifBlank { c.getString(R.string.coin_you) } else (chat()?.shown?.ifBlank { null } ?: c.getString(R.string.peer))
        row.addView(if (mine) c.avatar(SelfFace.load(c), name, 42) else c.peerFace(ref, name, 42), lp(c.dp(42), c.dp(42)))
        row.gap(10)
        row.addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(name, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() })   // USER-DATA: a player's name
            addView(c.text(captured(g, side), 18f, MT.gray))
        }, lp(0, WRAP, 1f))
        val clock = c.text("", 20f, Color.WHITE, bold = true, center = true).apply {
            setPadding(dp(12), 0, dp(12), 0); minWidth = dp(94); minHeight = dp(44); gravity = Gravity.CENTER
            contentDescription = c.getString(if (side == ChessSide.WHITE) R.string.chess_white_clock else R.string.chess_black_clock)
        }
        clocks[side] = clock
        row.addView(clock, lp(WRAP, WRAP))
    }
    fun tick() {
        val g = game ?: return
        for ((side, clock) in clocks) {
            val active = g.running == side && anchor.runs
            val ms = g.remaining(side, if (active) anchor.elapsed() else 0L)
            clock.text = if (g.seconds == 0) "∞" else ChessWords.clock(ms)   // USER-DATA: a clock
            clock.setTextColor(if (active) Color.BLACK else Color.WHITE)
            clock.background = c.rounded(if (active) Color.WHITE else Color.argb(18, 255, 255, 255), 8)
            if (active && side == g.mySide && 0 < g.seconds && ms == 0L && pending == null && timeoutAsked != g.last.id) {
                timeoutAsked = g.last.id
                send(ChessLetter.TIMEOUT)
            }
        }
    }
    val ticker = object : Runnable { override fun run() { tick(); main.postDelayed(this, 250) } }

    draw = {
        val g = game
        if (g != null) {
            val step = minOf(browsing ?: g.moves.size, g.moves.size)
            val position = g.positions[step]
            val facing = if (flipped) g.mySide.other else g.mySide
            board.position = position; board.facing = facing; board.selected = selected
            board.destinations = selected?.let { s -> position.legalMoves(s).map { it.to }.toSet() } ?: emptySet()
            board.lastMove = if (0 < step) g.moves[step - 1] else null
            board.enabledMoves = live() && g.status == ChessGame.Status.PLAYING && g.position.turn == g.mySide
            board.redraw()
            strip.removeAllViews()
            g.notation.forEachIndexed { i, word ->
                strip.addView(c.text((if (i % 2 == 0) (i / 2 + 1).toString() + ". " else "") + word, 15f, Color.WHITE, bold = (browsing ?: g.moves.size) == i + 1).apply {
                    typeface = android.graphics.Typeface.MONOSPACE; gravity = Gravity.CENTER; minHeight = c.dp(44); minWidth = c.dp(44)
                    pressable { browsing = if (i + 1 == g.moves.size) null else i + 1; selected = null; draw() }
                }, lp(WRAP, WRAP).apply { marginEnd = c.dp(16) })
            }
            if (browsing == null) stripScroll.post { stripScroll.fullScroll(View.FOCUS_RIGHT) }
            player(topRow, g, facing.other); player(bottomRow, g, facing)
            plateHolder.removeAllViews()
            if (browsing == null && (g.waitingForHistory || g.status != ChessGame.Status.PLAYING)) {
                plateHolder.addView(c.statePlate {
                    addView(c.text(ChessWords.status(c, g), 17f, Color.WHITE, bold = true, center = true).apply { maxLines = 3 }, lp(WRAP, WRAP))
                    if (g.pooled && 0L < g.pot) addView(c.text(c.getString(R.string.chess_pot, CoinText.count(g.pot)), 15f, MT.gray, center = true), lp(WRAP, WRAP))
                    val short = g.pooled && g.status == ChessGame.Status.INVITED && !g.whiteIsMine && CoinBook.balance < g.stake
                    if (short) addView(c.text(c.getString(R.string.chess_stake_short), 12f, MT.gray, center = true), lp(WRAP, WRAP))
                    addView(c.hstack {
                        gravity = Gravity.CENTER
                        if (g.status == ChessGame.Status.INVITED) {
                            if (!g.whiteIsMine && !short) addView(c.barMark(R.drawable.ic_check, R.string.chess_accept_invitation) { send(ChessLetter.ACCEPT) }, lp(c.dp(44), c.dp(44)))
                            addView(c.barMark(R.drawable.ic_close, if (g.whiteIsMine) R.string.chess_withdraw else R.string.chess_decline_invitation) { send(ChessLetter.DECLINE) }, lp(c.dp(44), c.dp(44)))
                        } else if (g.status.finished && pairOver) addView(c.barMark(R.drawable.ic_plus, R.string.chess_new_game) { again(g) }, lp(c.dp(44), c.dp(44)))
                        alpha = if (live()) 1f else 0.4f
                    }, lp(WRAP, WRAP))
                }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            }
            status.text = if (g.status == ChessGame.Status.PLAYING && !g.waitingForHistory) ChessWords.status(c, g) else ""
            drawMark.visibility = if (g.drawOfferedBy == g.mySide.other && g.status == ChessGame.Status.PLAYING) View.VISIBLE else View.GONE
            notes.text = listOfNotNull(if (!allowed()) c.getString(R.string.chess_unavailable) else null,
                if (claimWithMove) c.getString(R.string.chess_claim_hint) else null).joinToString("\n")
            delivery.removeAllViews()
            val row = chat()?.msgs?.lastOrNull { ChessSend.letterOf(it)?.id == g.last.id }
            if (row != null && row.mine) delivery.addView(c.text(c.getString(when (row.state) {
                -1 -> R.string.chess_not_sent; 0 -> R.string.chess_sending; 1 -> R.string.chess_sent; 2 -> R.string.chess_delivered; else -> R.string.chess_read
            }), 12f, MT.gray))
            tick()
        }
    }
    reload = {
        val all = ChessSend.entries(ref)
        val current = ChessGame.current(all)
        val games = all.groupBy { it.letter.game }.mapNotNull { (id, list) -> ChessGame.of(list, id)?.replaced(current) }
        val next = games.firstOrNull { it.id == gameId }
        if (game?.last?.id != next?.last?.id || game?.status != next?.status) selected = null
        game = next
        anchor = next?.let { ChessAnchor.of(it, ref) } ?: ChessAnchor.STANDING
        score = ChessScore(games)
        pairOver = games.firstOrNull { it.id == current }?.status?.finished ?: true
        val waiting = pending
        if (waiting != null && (next?.acceptedIDs?.contains(waiting) == true || next?.status?.finished == true)) pending = null
        // THE GAME THAT ENDS ON THE SCREEN LEAVES IT: a moment on the final position and its plate, then the conversation
        if (next != null) {
            if (!next.status.finished) sawLive = true
            else if (sawLive) {
                sawLive = false
                val id = gameId
                main.postDelayed({ if (ChessSend.shownGame == id) { onBack(); if (!inChat) act.push { back -> conversationPage(act, ref, back) } } }, 1200)
            }
        }
        draw()
    }
    drawMark.setOnClickListener { send(ChessLetter.DRAW) }

    val menu = c.barMark(R.drawable.ic_more_horiz, R.string.chess_actions) { }
    menu.setOnClickListener {
        val g = game
        val pm = PopupMenu(c, menu)
        val m = pm.menu
        m.add(0, 9, 0, ChessWords.score(c, score)).isEnabled = false
        m.add(0, 1, 1, R.string.chess_flip)
        m.add(0, 2, 2, R.string.chess_live)
        if (g != null && g.status == ChessGame.Status.PLAYING) {
            m.add(0, 3, 3, R.string.chess_offer_draw).apply { isCheckable = true; isChecked = offerDraw }
            m.add(0, 4, 4, R.string.chess_claim_with_move).apply { isCheckable = true; isChecked = claimWithMove; isEnabled = live() && g.position.turn == g.mySide }
            m.add(0, 5, 5, R.string.chess_claim).isEnabled = live() && g.position.turn == g.mySide && g.canClaimDraw
            m.add(0, 6, 6, R.string.chess_resign).isEnabled = live()
        }
        if (g != null && !g.status.finished) m.add(0, 7, 7, R.string.chess_end).isEnabled = pending == null && allowed()
        if (g != null) m.add(0, 8, 8, R.string.chess_new_game).isEnabled = pairOver && pending == null && allowed()
        pm.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> { flipped = !flipped; draw() }
                2 -> { browsing = null; selected = null; draw() }
                3 -> offerDraw = !offerDraw
                4 -> { claimWithMove = !claimWithMove; draw() }
                5 -> send(ChessLetter.CLAIM)
                6 -> AlertDialog.Builder(act).setTitle(R.string.chess_resign_q).setPositiveButton(R.string.chess_resign) { _, _ -> send(ChessLetter.RESIGN) }.setNegativeButton(R.string.chess_cancel, null).show()
                7 -> AlertDialog.Builder(act).setTitle(R.string.chess_end_q).setPositiveButton(R.string.chess_end) { _, _ -> send(ChessLetter.END) }.setNegativeButton(R.string.chess_cancel, null).show()
                8 -> game?.let { again(it) }
            }
            true
        }
        pm.show()
    }
    board.onSquare = { press(it) }

    val bar = FrameLayout(c).apply {
        setPadding(c.dp(8), 0, c.dp(8), 0)
        addView(c.barMark(R.drawable.ic_arrow_back_ios_new, R.string.coin_close) { onBack() }, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(c.getString(R.string.chess_title), 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        addView(menu, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    fun moveList() {
        val g = game ?: return
        val list = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), dp(8), dp(16), dp(8)) }
        lateinit var dialog: AlertDialog
        g.notation.forEachIndexed { i, word ->
            list.addView(c.text((i / 2 + 1).toString() + "." + (if (i % 2 == 1) ".." else "") + " " + word, 16f).apply {
                minHeight = c.dp(44); gravity = Gravity.CENTER_VERTICAL
                pressable { browsing = if (i + 1 == g.moves.size) null else i + 1; selected = null; dialog.dismiss(); draw() }
            }, lp())
        }
        dialog = AlertDialog.Builder(act).setTitle(R.string.chess_moves).setView(ScrollView(c).apply { addView(list) }).setNegativeButton(R.string.coin_close, null).create()
        dialog.show()
    }
    val tools = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(22), dp(8), dp(22), dp(8))
        addView(c.barMark(R.drawable.ic_list_bullet, R.string.chess_moves) { moveList() }, lp(c.dp(44), c.dp(44)))
        spacer()
        addView(c.barMark(R.drawable.ic_bar_chats, R.string.chess_chat) {
            if (inChat) onBack() else act.push { back -> conversationPage(act, ref, back) }
        }, lp(c.dp(44), c.dp(44)))
        spacer()
        addView(c.barMark(R.drawable.ic_arrow_back_ios_new, R.string.chess_previous) { browse(-1) }, lp(c.dp(44), c.dp(44)))
        spacer()
        addView(c.barMark(R.drawable.ic_chevron_right, R.string.chess_next) { browse(1) }, lp(c.dp(44), c.dp(44)))
    }
    val column = c.vstack(Gravity.NO_GRAVITY) {
        addView(stripScroll, lp(MATCH, c.dp(44)))
        addView(topRow, lp())
        addView(FrameLayout(c).apply {
            addView(board, FrameLayout.LayoutParams(MATCH, WRAP))
            addView(plateHolder, FrameLayout.LayoutParams(MATCH, MATCH))
        }, lp())
        addView(bottomRow, lp())
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = c.dp(44); setPadding(c.dp(16), 0, c.dp(16), 0)
            addView(status, lp(0, WRAP, 1f)); addView(drawMark, lp(c.dp(44), c.dp(44)))
        }, lp())
        addView(notes, lp())
        addView(delivery, lp())
        addView(tools, lp())
    }
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, c.dp(52)))
            addView(ScrollView(c).apply { addView(column) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
    val heard: () -> Unit = { reload() }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { ChessSend.shownGame = gameId; Book.listen(heard); reload(); main.post(ticker) }
        override fun onViewDetachedFromWindow(v: View) { if (ChessSend.shownGame == gameId) ChessSend.shownGame = null; Book.unlisten(heard); main.removeCallbacks(ticker) }
    })
    return page
}

/** A page of chess: the bar with its cross or chevron and a trailing mark, the list that scrolls. */
private fun chessFrame(act: MainActivity, title: String, cross: Boolean, onLead: () -> Unit, trailing: View?, body: LinearLayout): View {
    val c: Context = act
    val bar = FrameLayout(c).apply {
        setPadding(c.dp(8), 0, c.dp(8), 0)
        addView(c.barMark(if (cross) R.drawable.ic_close else R.drawable.ic_arrow_back_ios_new, R.string.coin_close) { onLead() },
            FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        if (trailing != null) addView(trailing, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, c.dp(52)))
            addView(ScrollView(c).apply { addView(body.apply { setPadding(c.dp(16), 0, c.dp(16), c.dp(32)) }) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/**
 * THE CHESS PAGE (iOS MTChessPage): every pair's games, the unfinished first and then the newest, each with the correspondent's
 * face, the game's state and its clock; the plus begins a new game.
 */
fun chessLobbyPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    val list = c.vstack(Gravity.NO_GRAVITY)
    fun draw() {
        list.removeAllViews()
        class Record(val ref: String, val game: ChessGame)
        val records = ArrayList<Record>()
        for (chat in Book.all()) {
            if (chat.msgs.none { it.text.startsWith(ChessLetter.MARK) }) continue
            val all = ChessSend.entries(chat.ref)
            val current = ChessGame.current(all)
            for ((id, l) in all.groupBy { it.letter.game }) ChessGame.of(l, id)?.replaced(current)?.let { records.add(Record(chat.ref, it)) }
        }
        records.sortWith(compareBy<Record>({ it.game.status.finished }, { -it.game.last.at }, { it.ref + ":" + it.game.id }))
        if (records.isEmpty()) {
            list.addView(c.vstack {
                setPadding(0, dp(48), 0, dp(24))
                addView(ImageView(c).apply { setImageResource(R.drawable.chess_wn) }, lp(dp(72), dp(72)))
                gap(10)
                addView(c.text(c.getString(R.string.chess_title), 22f, Color.WHITE, bold = true, center = true))
                addView(c.text(c.getString(R.string.chess_invite_someone), 15f, MT.gray, center = true))
            }, lp())
            return
        }
        list.addView(c.plate {
            records.forEachIndexed { i, r ->
                if (0 < i) divider()
                val chat = Book.chat(r.ref)
                val name = chat?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(16), dp(10), dp(16), dp(10))
                    addView(c.peerFace(r.ref, name, 44), lp(dp(44), dp(44)))
                    gap(12)
                    addView(c.vstack(Gravity.NO_GRAVITY) {
                        addView(c.text(name, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() })   // USER-DATA: the name
                        addView(c.text(ChessWords.status(c, r.game), 15f, MT.gray))
                    }, lp(0, WRAP, 1f))
                    addView(c.text(ChessWords.control(c, r.game.seconds), 15f, Color.WHITE))
                    pressable { act.push { back -> chessBoardPage(act, r.ref, r.game.id, false, back) } }
                }, lp())
            }
        }, lp().apply { topMargin = c.dp(12) })
    }
    body.addView(list, lp())
    val plus = c.barMark(R.drawable.ic_plus, R.string.chess_new_game) { act.push { back -> newChessPage(act, back) } }
    val page = chessFrame(act, c.getString(R.string.chess_title), true, onClose, plus, body)
    val heard: () -> Unit = { draw() }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(heard); draw() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(heard) }
    })
    return page
}

/**
 * A NEW GAME (iOS MTChessNewGame): the time control, then the correspondents, each with the stake typed beside the name as an
 * offer — both players put it into the game's pot — and our send; the invitation opens its board.
 */
fun newChessPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    var seconds = ChessSend.CHAT_CLOCK
    val controls = c.hstack { gravity = Gravity.CENTER_VERTICAL }
    fun drawControls() {
        controls.removeAllViews()
        for (s in ChessLetter.TIME_CONTROLS) controls.addView(c.text(ChessWords.control(c, s), 15f, Color.WHITE, bold = true).apply {
            background = c.rounded(if (s == seconds) MT.blue else Color.rgb(58, 58, 60), 16)
            setPadding(dp(12), dp(8), dp(12), dp(8)); minHeight = dp(44); gravity = Gravity.CENTER
            pressable { seconds = s; drawControls() }
        }, lp(WRAP, WRAP).apply { marginEnd = c.dp(6) })
    }
    drawControls()
    body.addView(c.text(c.getString(R.string.chess_time_control), 13f, MT.gray).apply { setPadding(dp(16), dp(22), dp(16), dp(6)) }, lp())
    body.addView(HorizontalScrollView(c).apply { isHorizontalScrollBarEnabled = false; addView(controls) }, lp())
    val people = Book.all().filter { ChessSend.canPlay(it.ref) }.sortedBy { it.shown.lowercase() }
    body.addView(c.text(c.getString(R.string.chess_invite_correspondent), 13f, MT.gray).apply { setPadding(dp(16), dp(22), dp(16), dp(6)) }, lp())
    body.addView(c.plate {
        if (people.isEmpty()) addView(c.text(c.getString(R.string.chess_no_correspondents), 16f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) }, lp())
        people.forEachIndexed { i, ch ->
            if (0 < i) divider()
            val stake = EditText(c).apply {
                inputType = InputType.TYPE_CLASS_NUMBER; filters = arrayOf(InputFilter.LengthFilter(13)); hint = "0"
                gravity = Gravity.END or Gravity.CENTER_VERTICAL; setTextColor(Color.WHITE); setHintTextColor(MT.gray)
                background = c.rounded(Color.rgb(44, 44, 46), 8); setPadding(dp(8), 0, dp(8), 0)
                contentDescription = c.getString(R.string.chess_stake_field)
            }
            fun offer() {
                val coins = stake.text.toString().toLongOrNull() ?: 0L
                if (CoinBook.balance < coins) { Toast.makeText(c, R.string.coin_not_enough, Toast.LENGTH_SHORT).show(); return }
                val id = ChessSend.invite(c, ch.ref, seconds, coins)
                if (id == null) { AlertDialog.Builder(act).setTitle(R.string.chess_invite_failed).setPositiveButton(R.string.ok, null).show(); return }
                onBack()
                act.push { back -> chessBoardPage(act, ch.ref, id, false, back) }
            }
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(8), dp(8), dp(8))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(44)
                    addView(c.peerFace(ch.ref, ch.shown, 44), lp(dp(44), dp(44)))
                    gap(12)
                    addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 16f).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                    pressable { offer() }
                }, lp(0, WRAP, 1f))
                addView(stake, lp(dp(96), dp(44)))
                addView(c.barMark(R.drawable.ic_paperplane, R.string.coin_send, MT.blue) { offer() }, lp(dp(44), dp(44)))
            }, lp())
        }
    }, lp())
    body.addView(c.text(c.getString(R.string.chess_pot_footer), 12f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) }, lp())
    return chessFrame(act, c.getString(R.string.chess_new_game), false, onBack, null, body)
}

/**
 * THE INVITATION'S BUBBLE (iOS the chess letter in the chat): the knight, the word, who plays which colour under which clock and
 * the stake; an invitation that waits for my answer wears the system's blue Accept and red Decline; a tap opens the board.
 */
fun Context.chessPlate(act: MainActivity?, ref: String, m: Msg, letter: ChessLetter, mine: Boolean): View = vstack(Gravity.NO_GRAVITY) {
    addView(hstack {
        gravity = Gravity.CENTER_VERTICAL
        addView(ImageView(context).apply { setImageResource(R.drawable.chess_wn) }, lp(dp(40), dp(40)))
        gap(10)
        addView(vstack(Gravity.NO_GRAVITY) {
            addView(text(getString(R.string.chess_title), 16f, BubbleStyle.text(mine), bold = true))
            addView(text(ChessWords.seat(context, letter, mine), 13f, BubbleStyle.time(mine)))
        }, lp(WRAP, WRAP))
    }, lp(WRAP, WRAP))
    if (act != null) {
        val game = letter.game
        if (!mine && ChessSend.awaitsMe(ref, game)) addView(hstack {
            setPadding(0, dp(8), 0, 0)
            val short = letter.pooled && CoinBook.balance < (letter.stake ?: 0L)
            addView(text(getString(R.string.chess_accept), 15f, Color.WHITE, bold = true, center = true).apply {
                background = rounded(MT.blue, 18); setPadding(dp(16), dp(8), dp(16), dp(8)); minHeight = dp(44); gravity = Gravity.CENTER
                alpha = if (short) 0.4f else 1f
                if (!short) pressable { if (ChessSend.join(act, ref, game) != null) act.push { back -> chessBoardPage(act, ref, game, true, back) } }
            }, lp(WRAP, WRAP).apply { marginEnd = dp(8) })
            addView(text(getString(R.string.chess_decline), 15f, Color.WHITE, bold = true, center = true).apply {
                background = rounded(Color.rgb(140, 30, 40), 18); setPadding(dp(16), dp(8), dp(16), dp(8)); minHeight = dp(44); gravity = Gravity.CENTER
                pressable {
                    val now = ChessSend.state(ref, game)
                    now?.action(ChessLetter.DECLINE, ChessSend.now())?.let { ChessSend.send(act, ref, it) }
                }
            }, lp(WRAP, WRAP))
        }, lp(WRAP, WRAP))
        pressable { act.push { back -> chessBoardPage(act, ref, game, true, back) } }
    }
}
