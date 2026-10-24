package quest.montana.app

import android.content.Context
import android.util.Log
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

// ─────────────────────────── the coins' history, folded once (iOS MTWalletScreen: MTCoinHistory) ───────────────────────────

/**
 * THE HISTORY IS FOLDED OFF THE SCREEN'S THREAD, ONCE A CHANGE OF THE BOOK (iOS MTCoinHistory, MTWalletScreen.swift:595-798; the
 * author's words 12.10.2026 15:2x MSK: «the history in the Time Coins on T1 lags; make the analytics a separate button so it opens and
 * nothing lags; at the history's opening the transactions open at once»). T1 on 2194, a book of 24 320 moves, stood 823 ms on the
 * screen's thread at the history's opening. Every move of the book is folded once, on its own thread -- the lines day after day, a
 * day's minting one line of it, a day's small expenses one line of each source and kind, the months' and the whole's sums by source,
 * the transfers with each person -- and kept whole for the history, the analytics and a person's page alike; the pages only read it.
 * The fold reads the local book (CoinBook) and what the phone holds of the people (Book, Groups), and writes nothing, anywhere.
 */
object CoinHistory {
    /** One line of the history: a move of the book, or a day's minting or small expenses folded into one (iOS Line). `glyph` is the
     *  drawable of iOS's symbol; `tx` the record's name when the move is a transfer's, its address in the Explorer. */
    class Line(val id: String, val at: Double, val signed: Long, val title: String, val category: String, val glyph: Int,
               val source: String, val ref: String, val peer: String?, val tx: String?, val count: Int)
    /** One day of the book (iOS Day): its start on this phone's clock in ms, its lines newest first, their sum. */
    class Day(val id: Long, val lines: List<Line>, val sum: Long)
    /** Where coins came from or went over a period (iOS Share): the source's word, its coins signed, the coins it moved either way. */
    class Share(val name: String, val signed: Long, val moved: Long)
    /** A month of the book, or the whole of it (iOS Month): its start in ms (the whole's the distant past), what went out, what came
     *  in, and every source's share, the most moved first. */
    class Month(val id: Long, val spending: Long, val income: Long, val shares: List<Share>)
    /** The one fold (iOS Fold): the days and the months newest first, the whole, the transfers with each person -- and the book's count,
     *  its person (CoinBook.generation) and the language it was folded in, so a door folds again only when one of them moved. */
    class Fold(val days: List<Day>, val months: List<Month>, val whole: Month, val byPeer: Map<String, List<Line>>, val moves: Int,
               val gen: Int, val lang: String)
    /** What a fold needs of the screen's world, read on the screen's thread once (iOS Ask): the sources' words, the folded lines' words
     *  and the neutral name of a person whose name is unknown. The people's names and the channels are read on the fold's own thread,
     *  from the books that are safe there (Book, Groups). */
    class Ask(val words: Map<String, String>, val minted: String, val mintedDay: String, val burnedDay: String, val spentDay: String,
              val peer: String, val lang: String) {
        companion object {
            fun of(c: Context) = Ask(TimeChain.SOURCES.associateWith { c.chainName(it) }, c.getString(R.string.ch_minted),
                c.getString(R.string.ch_minting_day), c.getString(R.string.ch_burning_day), c.getString(R.string.ch_spending_day),
                c.getString(R.string.peer), c.resources.configuration.locales[0].toLanguageTag())
        }
    }
    /** The operations a page shows (iOS MTCoinHistoryPage.Flow, MTWalletScreen.swift:806-817): every one, the spending, the income. */
    enum class Flow(val word: Int) {
        ALL(R.string.ch_all), SPENDING(R.string.ch_spending), INCOME(R.string.ch_income);
        fun holds(signed: Long): Boolean = this == ALL || (if (this == SPENDING) signed < 0 else 0 < signed)
    }

    /** The fold the pages read (iOS @Published fold): null until the first fold stands. */
    @Volatile var fold: Fold? = null; private set
    /** The fold of the person on the phone now: a person forgotten takes their lines with them (CoinBook.setAside), never shown to the next. */
    fun current(): Fold? = fold?.takeIf { it.gen == CoinBook.generation }

    // the pages that read the fold hear it stand (iOS ObservableObject); on the screen's thread
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }

    private const val THROTTLE_MS = 1500L
    private var watchers = 0   // the screen's thread
    private var lastAt = 0L
    private var due = false
    /** The book moved while a page reads the history (CoinBook.changed posts it to the screen's thread). */
    private val moved: () -> Unit = { MainThread.post { throttled() } }
    /**
     * A PAGE THAT READS THE HISTORY STANDS (iOS watch, MTWalletScreen.swift:631-638): the book's moves fold at once, then again as the book
     * moves, at most one fold a second and a half, the newest book each (iOS $entries.throttle(1.5 s, latest)). The book's moves are its
     * entries: the seconds of a game or a call move the balance in their window and fold nothing until the window closes into a move.
     */
    fun watch(c: Context) {
        asked = Ask.of(c)
        watchers++
        if (watchers != 1) return
        CoinBook.listen(moved)
        lastAt = System.currentTimeMillis()
        refold(force = true)
    }
    fun unwatch() {
        watchers = maxOf(0, watchers - 1)
        if (watchers == 0) CoinBook.unlisten(moved)
    }
    /** The wallet's page stands, or a person's page opens its transactions (iOS warm, MTWalletScreen.swift:643-647): one fold ahead of the
     *  door, so the door opens on lines, never on an empty page -- and none when the fold already holds the book. */
    fun warm(c: Context) {
        asked = Ask.of(c)
        refold(force = false)
    }
    private fun throttled() {
        if (watchers == 0 || due) return
        val wait = THROTTLE_MS - (System.currentTimeMillis() - lastAt)
        if (wait <= 0) { lastAt = System.currentTimeMillis(); refold(force = false); return }
        due = true
        MainThread.later(wait, Runnable { due = false; if (0 < watchers) { lastAt = System.currentTimeMillis(); refold(force = false) } })
    }

    // ONE FOLD AT A TIME, ON ITS OWN THREAD (iOS refold, folding and again, MTWalletScreen.swift:648-670): a fold asked while one is
    // waiting joins it; one asked while one runs runs after it, with the newest book
    private val q = Executors.newSingleThreadExecutor { r -> Thread(r, "montana.CoinHistory").apply { isDaemon = true } }
    private val queued = AtomicBoolean(false)
    @Volatile private var forced = false
    @Volatile private var asked: Ask? = null
    private var held: Fold? = null   // on q: the last fold made, the measure of whether the next is needed
    private var loggedAt = 0L   // on q
    private fun refold(force: Boolean) {
        if (force) forced = true
        if (!queued.compareAndSet(false, true)) return
        q.execute {
            queued.set(false)
            val ask = asked ?: return@execute
            val must = forced
            forced = false
            val gen = CoinBook.generation
            val h = held
            if (!must && h != null && h.gen == gen && h.lang == ask.lang && h.moves == CoinBook.size()) return@execute
            val started = System.currentTimeMillis()
            val f = runCatching { foldBook(CoinBook.all(), ask, gen) }.getOrElse { e ->
                Log.w("Montana", "coin_history fold: " + e.javaClass.simpleName)
                return@execute
            }
            held = f
            // the diary hears the fold's measure once a minute at most (iOS MontanaTrace.markFolded, window 60)
            if (60_000L <= started - loggedAt) {
                loggedAt = started
                Log.i("Montana", "coin_history fold moves=" + f.moves + " days=" + f.days.size + " ms=" + (System.currentTimeMillis() - started))
            }
            MainThread.post { fold = f; synchronized(listeners) { listeners.toList() }.forEach { it() } }
        }
    }

    /** The tallies saturate, never wrap (iOS MTCoinCounts.plus, MTWalletCore.swift:2377-2382): a sum past the integer stands at its edge. */
    fun plus(a: Long, b: Long): Long {
        val s = a + b
        return if (((a xor s) and (b xor s)) < 0) (if (0 < b) Long.MAX_VALUE else Long.MIN_VALUE) else s
    }
    /** A move's kind as its glyph (iOS glyph(_:), MTWalletScreen.swift:671-679): sparkles, arrow.down.left, arrow.up.right, hand.thumbsup, flame. */
    fun glyph(k: String): Int = when (k) {
        CoinEntry.EARN -> R.drawable.ic_sparkles
        CoinEntry.RECEIVE -> R.drawable.ic_call_received
        CoinEntry.SEND -> R.drawable.ic_call_made
        CoinEntry.SPEND -> R.drawable.ic_hand_thumbsup
        else -> R.drawable.ic_flame_line
    }
    /**
     * A DAY'S SMALL EXPENSES FOLD AS ITS MINTING DOES (iOS small(_:_:), MTWalletScreen.swift:680-687; the author's word 17.10.2026 13:46
     * MSK): a burn or a spend of no more coins than a second of life mints at most (CoinBook.LIMIT) -- a coin on a letter or a post, a
     * comment's coin, a small move of a game. A transfer to a person, a call's seconds and a larger expense stay lines of their own.
     */
    fun small(e: CoinEntry, source: String): Boolean = (e.k == CoinEntry.SPEND || e.k == CoinEntry.BURN) && source != "calls" && e.c <= CoinBook.LIMIT


    private class Agg { var spending = 0L; var income = 0L; val by = HashMap<String, LongArray>() }   // a source's word → its signed, its moved
    private class Tally { var sum = 0L; var count = 0; var at = 0.0 }
    private data class Small(val day: Long, val source: String, val kind: String)   // a day, a source and a kind (iOS Small)

    /**
     * EVERY MOVE OF THE BOOK FOLDED ONCE (iOS fold(_:_:), MTWalletScreen.swift:688-773): the lines day after day, a day's minting one line
     * of it, a day's small expenses one line of each source and kind, the months' and the whole's sums by source, and the transfers with
     * each person. A day is found by the interval of the day the moment before fell in, and a quarter-hour's memory of the days asked,
     * never by a calendar's question for every move; a person's name is asked once a fold.
     */
    private fun foldBook(moves: List<CoinEntry>, ask: Ask, gen: Int): Fold {
        val cal = Calendar.getInstance()
        var low = 0.0
        var high = -1.0
        var current = 0L
        val quarters = HashMap<Long, LongArray>()   // a quarter of an hour → the start of its day and of the next, in ms
        fun dayOf(at: Double): Long {
            if (low <= at && at < high) return current
            val span = quarters.getOrPut(Math.floor(at / 900).toLong()) {
                cal.timeInMillis = (at * 1000).toLong()
                cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
                val d = cal.timeInMillis
                cal.add(Calendar.DAY_OF_MONTH, 1)
                longArrayOf(d, cal.timeInMillis)
            }
            current = span[0]; low = span[0] / 1000.0; high = span[1] / 1000.0
            return current
        }
        val monthOfDay = HashMap<Long, Long>()
        fun monthOf(day: Long): Long = monthOfDay.getOrPut(day) { cal.timeInMillis = day; cal.set(Calendar.DAY_OF_MONTH, 1); cal.timeInMillis }
        fun add(a: Agg, e: CoinEntry, name: String) {
            if (e.signed < 0) a.spending = plus(a.spending, -e.signed) else a.income = plus(a.income, e.signed)
            val had = a.by.getOrPut(name) { LongArray(2) }
            had[0] = plus(had[0], e.signed); had[1] = plus(had[1], e.c)
        }
        // THE PEOPLE BY THEIR CONVERSATIONS, AS THE CHATS NAME THEM (iOS MTTimeChainRows.names, MTWalletScreen.swift:1405-1413): once a
        // fold, each person once; a conversation the phone does not hold names its first ten letters
        val names = HashMap<String, String>()
        fun who(p: String): String = names.getOrPut(p) { Book.chat(p)?.let { ch -> ch.shown.ifBlank { null }?.let { spokenName(it) } ?: ask.peer } ?: p.take(10) }
        val byMonth = HashMap<Long, Agg>()
        val whole = Agg()
        val byDay = HashMap<Long, ArrayList<Line>>()
        val minted = HashMap<Long, Tally>()
        val smalls = LinkedHashMap<Small, Tally>()
        val byPeer = HashMap<String, ArrayList<Line>>()
        for (e in moves) {
            val day = dayOf(e.at)
            val source = TimeChain.source(e)
            val name = ask.words[source] ?: source
            add(byMonth.getOrPut(monthOf(day)) { Agg() }, e, name)
            add(whole, e, name)
            if (e.k == CoinEntry.EARN) {
                val t = minted.getOrPut(day) { Tally() }
                t.sum = plus(t.sum, e.c); t.count++; t.at = maxOf(t.at, e.at)
                continue
            }
            if (small(e, source)) {
                // only the line folds: the months' and the whole's sums took the move above, one by one
                val t = smalls.getOrPut(Small(day, source, e.k)) { Tally() }
                t.sum = plus(t.sum, e.c); t.count++; t.at = maxOf(t.at, e.at)
                continue
            }
            val peer = e.peer
            val title = if (peer != null) who(peer) else name
            val tx = if (e.ref.startsWith(CoinTx.REF_PREFIX)) e.ref.substring(CoinTx.REF_PREFIX.length) else null
            val line = Line(e.id, e.at, e.signed, title, name, glyph(e.k), source, e.ref, peer, tx?.takeIf { it.length == 64 }, 1)
            byDay.getOrPut(day) { ArrayList() }.add(line)
            if (peer != null && (source == "sent" || source == "received")) byPeer.getOrPut(peer) { ArrayList() }.add(line)
        }
        for ((day, m) in minted) byDay.getOrPut(day) { ArrayList() }.add(Line("minted:" + day / 1000, m.at, m.sum, ask.minted,
            ask.mintedDay, R.drawable.ic_sparkles, "mint", "", null, null, m.count))
        for ((k, m) in smalls) byDay.getOrPut(k.day) { ArrayList() }.add(Line("small:" + k.kind + ":" + k.source + ":" + k.day / 1000, m.at,
            -m.sum, ask.words[k.source] ?: k.source, if (k.kind == CoinEntry.BURN) ask.burnedDay else ask.spentDay, glyph(k.kind), k.source,
            "", null, null, m.count))
        val days = byDay.map { (d, lines) ->
            val sorted = lines.sortedByDescending { it.at }
            var sum = 0L
            for (l in sorted) sum = plus(sum, l.signed)
            Day(d, sorted, sum)
        }.sortedByDescending { it.id }
        fun month(id: Long, a: Agg) = Month(id, a.spending, a.income, a.by.map { (k, v) -> Share(k, v[0], v[1]) }.sortedByDescending { it.moved })
        return Fold(days, byMonth.map { (k, v) -> month(k, v) }.sortedByDescending { it.id }, month(Long.MIN_VALUE, whole),
            byPeer.mapValues { (_, v) -> v.sortedByDescending { it.at } }, moves.size, gen, ask.lang)
    }

    /** What a page of the history shows (iOS shown's answer): the days, and whether lines stand past them. */
    class Shown(val days: List<Day>, val more: Boolean)
    /**
     * THE HISTORY AS ITS PAGE SHOWS IT (iOS shown(_:query:limit:), MTWalletScreen.swift:774-790): the lines of a flow and a search, day after
     * day, newest first, at most `limit` of them -- a page of the book, never the whole; `more` says lines stand past it. A search reads
     * who or what the line was with.
     */
    fun shown(flow: Flow, query: String, limit: Int): Shown {
        val f = current() ?: return Shown(emptyList(), false)
        val all = flow == Flow.ALL && query.isEmpty()
        val out = ArrayList<Day>()
        var n = 0
        for (d in f.days) {
            val lines = if (all) d.lines else d.lines.filter { l -> flow.holds(l.signed) && (query.isEmpty() || l.title.contains(query, ignoreCase = true)) }
            if (lines.isEmpty()) continue
            if (limit <= n) return Shown(out, true)
            val cut = lines.take(limit - n)
            var sum = 0L
            if (!all) for (l in lines) sum = plus(sum, l.signed)
            out.add(Day(d.id, cut, if (all) d.sum else sum))
            n += cut.size
            if (cut.size < lines.size) return Shown(out, true)
        }
        return Shown(out, false)
    }
    /** THE TRANSFERS WITH ONE PERSON (iOS with(_:), MTWalletScreen.swift:791-797; the author's word 12.10.2026 15:2x MSK): the coins sent
     *  and received under every conversation of the pair, newest first. */
    fun with(peers: Set<String>): List<Line> {
        val f = current() ?: return emptyList()
        val all = peers.flatMap { f.byPeer[it].orEmpty() }
        return if (peers.size <= 1) all else all.sortedByDescending { it.at }
    }
}
