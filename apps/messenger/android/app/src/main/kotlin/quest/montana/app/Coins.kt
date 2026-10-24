package quest.montana.app

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID

// ─────────────────────────── the coins of the app (iOS MTWalletCore: MTCoinEntry, MTLocalCoinLedger, MTPiLevels, MTPantheon, MTCoinLetter, MTCoinSend) ───────────────────────────

/**
 * ONE MOVE OF COINS (iOS MTCoinEntry): whole coins, always positive, the kind says which way; `ref` is the move's own name and a
 * name is taken once, ever. The line is the iPhone's own JSON line — k, c, ref, peer, on, at (seconds since 1970) — so a book
 * read on either phone reads the same.
 */
class CoinEntry(val k: String, val c: Long, val ref: String, val peer: String? = null, val on: String? = null, val at: Double) {
    val id: String get() = k + ":" + ref
    val signed: Long get() = if (k == EARN || k == RECEIVE) c else -c
    /**
     * A NAME A RESTORE GIVES A LETTER NAMES NO MOVE (iOS MTCoinEntry.restoredName, MTRestoredMid; the author's words 09.10.2026: «the
     * balance swelled, this person never had 5 million -- check it, it is a hole»): a letter moves its coins once, under its wire name; the
     * archive's «arc:» and the keepers' «given:» are this phone's names for its copies. Every door of the book passes such a move -- the
     * reading, the joining, the taking -- and so the vault never carries one to the seed's other devices. The same names under «mid:»
     * are the ones Android's settle once credited (CoinSend.wire).
     */
    val restoredName: Boolean get() = restored(ref)
    fun json(): JSONObject = JSONObject().put("k", k).put("c", c).put("ref", ref).apply {
        if (peer != null) put("peer", peer)
        if (on != null) put("on", on)
    }.put("at", at)
    fun line(): String = json().toString()

    companion object {
        const val EARN = "earn"
        const val RECEIVE = "receive"
        const val SPEND = "spend"
        const val SEND = "send"
        const val BURN = "burn"
        private val KINDS = setOf(EARN, RECEIVE, SPEND, SEND, BURN)
        fun of(line: String): CoinEntry? = runCatching { of(JSONObject(line)) }.getOrNull()
        /** One move as the iPhone's JSON holds it (a book's line, a vault piece's element); null for a kind this build does not know. */
        fun of(o: JSONObject): CoinEntry? = runCatching {
            val k = o.getString("k")
            if (k !in KINDS) return null
            CoinEntry(k, o.getLong("c"), o.getString("ref"), o.text("peer"), o.text("on"), o.getDouble("at"))
        }.getOrNull()
        private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).ifEmpty { null }
        fun restored(ref: String): Boolean = ref.removePrefix("mid:").let { it.startsWith("arc:") || it.startsWith(Keeping.RESTORED_GIVEN) }
    }
}

/** BIG NUMBERS PART THEIR THOUSANDS WITH COMMAS (iOS MTCoinText, the author's word 04.10.2026 04:20 MSK), in every language. */
object CoinText {
    const val PER_MONTANA = 1_000_000_000L
    fun count(n: Long): String {
        val digits = n.toString().removePrefix("-")
        val out = StringBuilder()
        for (i in digits.indices) {
            if (0 < i && (digits.length - i) % 3 == 0) out.append(',')
            out.append(digits[i])
        }
        return (if (n < 0) "-" else "") + out
    }
    /** The coins as Montana, in integers alone: one coin is 0.000000001 (iOS MTChatMint.montana). */
    fun montana(coins: Long): String {
        val whole = coins / PER_MONTANA
        val part = (coins % PER_MONTANA).toString().removePrefix("-")
        return count(whole) + "." + "0".repeat(9 - part.length) + part
    }
}

/**
 * THE LEVELS OF π (iOS MTPiLevels, the author's words 03.10-05.10.2026): level n holds the first n digits of π as whole coins; the
 * balance's level is how many it fills, and the level is the one multiplier of every minting, up to the limit of a second —
 * twice that while a track of the music plays.
 */
object PiLevels {
    const val DIGITS = "3141592653589793238"
    val all: List<Long> = (1..DIGITS.length).map { DIGITS.take(it).toLong() }
    const val SHOWN = 13
    fun place(balance: Long): Int = all.count { it <= balance }
    val musicPlays: Boolean get() = MusicPlayer.playing
    fun multiplier(balance: Long): Long = minOf(CoinBook.LIMIT, maxOf(1, place(balance)).toLong()) * (if (musicPlays) 2 else 1)
    val ceiling: Long get() = CoinBook.LIMIT * (if (musicPlays) 2 else 1)
    /** π as far as a level reveals it: 3, 3.1, 3.14 and on. */
    fun revealed(place: Int): String {
        val d = DIGITS.take(maxOf(0, place))
        return if (d.length < 2) d else d.take(1) + "." + d.drop(1)
    }
    /** Whole thousands, millions and billions, never rounded up (the author's word 03.10 21:19: 1k, 10k and on to 1kkk). */
    fun short(c: Context, n: Long): String {
        val k = c.getString(R.string.coin_k)
        if (1_000_000_000L <= n) return (n / 1_000_000_000L).toString() + k + k + k
        if (1_000_000L <= n) return (n / 1_000_000L).toString() + k + k
        if (1_000L <= n) return (n / 1_000L).toString() + k
        return maxOf(0L, n).toString()
    }
}

/**
 * THE ONE BOOK OF COINS (iOS MTLocalCoinLedger behind MTCoinLedger): LOCAL, kept on this phone, never a note of the core's wallet —
 * the core has no door that mints or transfers today. One line of JSON per move, appended; the balance and the counts are the
 * sum of the lines, read once. A move between people is on disk in the same turn it is taken; a game's coins gather in a
 * window of a minute and join the book as one move when it closes.
 */
object CoinBook {
    /** The limit of a second (the constitution of the chain, point 11): thirteen coins, all minting together. */
    const val LIMIT = 13L
    /** The ticker of the Montana time coin (point 12): one symbol in every language. */
    const val TICKER = "\$TCM"
    private const val WINDOW_MS = 60_000L
    private const val FILE = "coin-ledger.jsonl"

    private var read = false
    private val entries = ArrayList<CoinEntry>()
    private val taken = HashSet<String>()
    private val onTarget = HashMap<String, Long>()
    var balance = 0L; private set
    var earned = 0L; private set
    var tapped = 0L; private set
    /** The coins of chess (iOS MTCoinCounts.played): a move's coin and the Timer's, a won game's sum taken, a lost game's sum given. */
    var played = 0L; private set
    /** The coins the VPN wall minted by its seconds (iOS MTCoinCounts.walled). */
    var walled = 0L; private set
    var received = 0L; private set
    var sent = 0L; private set
    var spent = 0L; private set
    var burned = 0L; private set
    private var level = 0   // the last level of π the balance filled, joined to the chain «pi»

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { told(); val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }
    /** The chain spoke (CoinSplit): every page that shows the available reads it again; the book itself did not move. */
    fun listeners() { val ls = synchronized(listeners) { listeners.toList() }; ls.forEach { it() } }
    /**
     * THE BOOK'S BALANCE FOR A READER OFF THE SCREEN'S THREAD (iOS MTCoinBalance, MTWalletCore.swift:552-563): the presence words are
     * built on the lanes' own threads (Presence.coinTail); until the book has read its file this holds nothing, so a word never tells
     * a pair a balance of nothing it does not hold. A move of the balance says it again to the people in the app (CoinTell).
     */
    @Volatile var said: Long? = null; private set
    private fun told() { val was = said; said = balance; if (was != null && was != balance) CoinTell.moved() }

    private fun dir(): File = File(Book.ctx.filesDir, "Coins").apply { mkdirs() }
    private fun file(): File = File(dir(), FILE)
    private fun nowS(): Double = System.currentTimeMillis() / 1000.0

    /**
     * THE BOOK'S GENERATION (iOS MTCoinBook.generation, the coin audit's second point 05.10.2026): one more at every person's change, before
     * anything is read again. A gather of the vault begun under the person who left compares it after every wait and writes nothing once
     * it moved -- else it laid the next person's book over the old seed's pieces.
     */
    @Volatile var generation = 0; private set

    /** The book is read once, off the screen's thread, at the app's start (iOS warm). */
    @Synchronized fun warm() { ensure() }

    private var passed = 0
    private var passedCoins = 0L
    private fun ensure() {
        if (read) return
        read = true
        CoinVault.soon("read", 1)   // the seed's other devices are asked once the book is read (iOS adopt 2530)
        val bytes = runCatching { file().takeIf { it.exists() }?.readBytes() }.getOrNull() ?: run { said = balance; return }
        // ONE BAD BYTE COSTS ONE LINE, NEVER THE BOOK (iOS decode): every line is read alone
        var start = 0
        for (i in 0..bytes.size) {
            if (i == bytes.size || bytes[i] == 10.toByte()) {
                if (start < i) CoinEntry.of(String(bytes, start, i - start, Charsets.UTF_8))?.let { adopt(it) }
                start = i + 1
            }
        }
        if (0 < passed) Log.i("Montana", "coin_book passed restored names=$passed coins=$passedCoins")
        Log.i("Montana", "coin_book read moves=" + entries.size + " balance=" + balance)
        // THE CHAINS TAKE THE BOOK'S PAST (iOS adopt, MTWalletCore 2028-2031): every level of π the moves filled, then every move in
        // the book's order, each passed by its name where its chain holds it already, so a link a dying process left out joins again
        var sum = 0L
        for (e in entries) {
            sum += e.signed
            val place = PiLevels.place(sum)
            if (level < place) { for (n in level + 1..place) TimeChain.note("pi", "level", n.toLong(), "level:" + n, e.at); level = place }
        }
        TimeChain.appendPast(entries.toList())
        said = balance
    }

    private fun adopt(e: CoinEntry) {
        if (e.c <= 0 || e.id in taken) return
        if (e.restoredName) { passed++; passedCoins += e.c; return }
        val next = plus(balance, e.signed) ?: return
        balance = next
        entries.add(e); taken.add(e.id); count(e)
    }

    /** A sum the integer cannot hold is no sum (the coin audit's ninth point): null instead of a wrap. */
    private fun plus(a: Long, b: Long): Long? { val s = a + b; return if (((a xor s) and (b xor s)) < 0) null else s }
    private fun sat(a: Long, b: Long): Long = plus(a, b) ?: if (0 < b) Long.MAX_VALUE else Long.MIN_VALUE
    private fun times(a: Long, b: Long): Long? = runCatching { Math.multiplyExact(a, b) }.getOrNull()

    private fun count(e: CoinEntry) {
        e.on?.let { onTarget[it] = sat(onTarget[it] ?: 0L, e.c) }
        // ONE CLASSIFICATION BY SOURCE (iOS MTCoinCounts.add/earn, MTWalletCore.swift:2383-2398): the game an earning came from by its
        // name -- the Pantheon's taps, chess and its Timer, the VPN wall, the chats; a won or lost game's sum is chess, never people
        when (e.k) {
            CoinEntry.EARN -> when {
                e.ref.startsWith(Pantheon.PREFIX) -> tapped = sat(tapped, e.c)
                e.ref.startsWith("chess:") || e.ref.startsWith("timer:") -> played = sat(played, e.c)
                e.ref.startsWith("vpnwall:") -> walled = sat(walled, e.c)
                else -> earned = sat(earned, e.c)
            }
            CoinEntry.RECEIVE -> if (e.ref.startsWith("chess-won:")) played = sat(played, e.c) else received = sat(received, e.c)
            CoinEntry.SPEND -> if (e.ref.startsWith("chess-lost:")) played = sat(played, -e.c) else spent = sat(spent, e.c)
            CoinEntry.SEND -> sent = sat(sent, e.c)
            CoinEntry.BURN -> burned = sat(burned, e.c)
        }
    }

    /** The one door every move passes: refused under a restored name or when the balance cannot hold it, written in the same turn. */
    private fun take(e: CoinEntry): Boolean {
        if (e.restoredName) { Log.i("Montana", "coin_refused " + e.k + " coins=" + e.c + " under a restored name"); return false }
        val next = plus(balance, e.signed) ?: run { Log.i("Montana", "coin_refused " + e.k + " the balance cannot hold it"); return false }
        entries.add(e); taken.add(e.id)
        balance = next
        count(e)
        write(listOf(e))
        TimeChain.append(e, now = true)   // every move joins its source's chain in the same turn it is on disk (iOS keep)
        reached(e.at)
        changed()
        // a move between people reaches the seed's devices at once, the minting within a minute (iOS keep 2706)
        val between = e.k == CoinEntry.SEND || e.k == CoinEntry.RECEIVE || e.k == CoinEntry.SPEND
        CoinVault.soon(if (between) "move" else "moves", if (between) 1 else 60)
        CoinTx.mintSoon()   // and the chain takes what the book holds above it within one window of τ1 (iOS MTLocalCoinLedger 2707)
        return true
    }

    /**
     * THE MOVES OF THE SEED'S OTHER DEVICES (iOS join, MTWalletCore.swift:2534-2559): taken once by their names into this book and its file,
     * in one stroke -- a device restored by its words takes the whole book here; they are on the nodes already and ride no piece back. A
     * move under a restored name, of no coins, or that the balance cannot hold is passed.
     */
    @Synchronized fun join(moves: List<CoinEntry>): Int {
        ensure()
        val fresh = ArrayList<CoinEntry>()
        for (e in moves) {
            if (e.c <= 0 || e.restoredName || e.id in taken) continue
            val next = plus(balance, e.signed) ?: continue
            balance = next
            entries.add(e); taken.add(e.id); count(e); fresh.add(e)
        }
        if (fresh.isEmpty()) return 0
        write(fresh)
        TimeChain.appendPast(fresh)   // their chains take them in one turn
        reached(nowS())
        changed()
        Log.i("Montana", "coin_book joined moves=" + fresh.size + " balance=" + balance)
        return fresh.size
    }
    /** The book's moves in its order, for the vault to lay what a node lacks. */
    @Synchronized fun all(): List<CoinEntry> { ensure(); return entries.toList() }

    /**
     * THE BOOK SAYS WHICH PAIRS HOLD THESE WORDS (iOS MTLocalCoinLedger.own, MTWalletCore.swift:2589-2603; MTOwnWords): one move seen from
     * both its ends -- a coin letter sent and credited under its one name, a paid reaction given and credited under its one name -- lies
     * in one book only when both ends hold the same words, for the book is the union of one seed's devices.
     */
    private var ownAt = -1
    private var ownSet: Set<String> = emptySet()
    @Synchronized fun ownPeers(): Set<String> {
        ensure()
        if (ownAt == entries.size) return ownSet
        val out = HashSet<String>()
        for (e in entries) {
            val peer = e.peer?.takeIf { it.isNotEmpty() } ?: continue
            val twin = when (e.k) {
                CoinEntry.SEND -> "receive:" + e.ref
                CoinEntry.RECEIVE -> if (e.ref.startsWith("rc:")) "spend:" + e.ref.drop(3) else "send:" + e.ref
                CoinEntry.SPEND -> "receive:rc:" + e.ref
                else -> continue
            }
            if (twin in taken) out.add(peer)
        }
        ownAt = entries.size; ownSet = out
        return out
    }

    /** A LEVEL OF π REACHED IS A LINK (iOS reached): the first time the balance fills a level, the level joins its chain at the move's moment. */
    private fun reached(at: Double) {
        val place = PiLevels.place(balance)
        if (level < place) {
            for (n in level + 1..place) TimeChain.note("pi", "level", n.toLong(), "level:" + n, at)
            level = place
        }
    }

    /** Lines appended; a line cut short by an ended process is ended first, so the next move stands on a line of its own. */
    private fun write(lines: List<CoinEntry>) {
        if (lines.isEmpty()) return
        runCatching {
            RandomAccessFile(file(), "rw").use { r ->
                val end = r.length()
                if (0L < end) { r.seek(end - 1); if (r.read() != 10) { r.seek(end); r.write(10) } }
                r.seek(r.length())
                r.write(lines.joinToString("") { it.line() + "\n" }.toByteArray(Charsets.UTF_8))
                r.fd.sync()
            }
        }.onFailure { Log.w("Montana", "coin book: " + it.javaClass.simpleName) }
    }

    // the minting window (iOS mintInWindow): one move a minute, not one a tap
    private class Window(val ref: String, var coins: Long, val at: Double)
    private val windows = HashMap<String, Window>()
    private var secondAt = 0L
    private var secondMinted = 0L

    /** A game's coins at the level's rate, gathered in its open window and booked as one move when the window closes. */
    @Synchronized fun mintInWindow(coins: Long, prefix: String, seconds: Int, byLevel: Boolean = true): Long {
        ensure()
        val whole = times(coins, if (byLevel) PiLevels.multiplier(balance) else 1L) ?: return 0
        if (whole <= 0 || plus(balance, whole) == null) return 0
        val c = priced(whole, seconds)
        if (c <= 0) return 0
        val w = windows[prefix] ?: Window(prefix + "w" + System.currentTimeMillis() + "-" + UUID.randomUUID().toString().uppercase(), 0, nowS()).also { win ->
            windows[prefix] = win
            MainThread.later(WINDOW_MS, Runnable { closeIf(prefix, win.ref) })
        }
        w.coins += c
        balance += c
        // the game an earning came from, by its name (iOS MTCoinCounts.earn, MTWalletCore.swift:1900-1905): the pull's seconds are the Pantheon's too
        if (prefix.startsWith(Pantheon.PREFIX)) tapped = sat(tapped, c) else earned = sat(earned, c)
        reached(nowS())
        changed()
        return c
    }
    @Synchronized private fun closeIf(prefix: String, ref: String) { if (windows[prefix]?.ref == ref) close(prefix) }
    private fun close(prefix: String) {
        val w = windows.remove(prefix) ?: return
        if (w.coins <= 0) return
        val e = CoinEntry(CoinEntry.EARN, w.coins, w.ref, at = w.at)
        entries.add(e); taken.add(e.id)
        write(listOf(e))
        TimeChain.append(e)   // the window's one move, its one link
        CoinVault.soon("moves", 60)   // the window's move reaches the seed's devices within a minute (iOS close → keep)
        CoinTx.mintSoon()
    }
    /** Every open window into the book now, and every waiting link into its chain: the app leaves the screen, the person leaves. */
    @Synchronized fun closeWindows() { for (p in windows.keys.toList()) close(p); TimeChain.flush() }

    /** THE LIMIT OF A SECOND (iOS priced): all the minting of one second shares its thirteen coins; what it leaves out is not minted. */
    private fun priced(coins: Long, seconds: Int): Long {
        val now = System.currentTimeMillis() / 1000
        if (secondAt != now) { secondAt = now; secondMinted = 0 }
        val away = times(PiLevels.ceiling, maxOf(0, seconds - 1).toLong())
        val room = maxOf(0L, PiLevels.ceiling - secondMinted)
        val c = if (away == null) coins else minOf(coins, room + away)
        secondMinted += minOf(room, maxOf(0L, c - (away ?: c)))
        return c
    }

    // the moves between people (iOS send, receive, retake)
    /** A coin letter stands at its own birth in every book: its name carries the millisecond the sender's phone gave it. */
    private fun moment(ref: String): Double = (if (ref.startsWith("mid:t")) Marks.birthMs(ref)?.let { it / 1000.0 } else null) ?: nowS()

    /** Coins sent to a person in a coin letter; refused (false) when the balance is short or the name was taken. */
    @Synchronized fun send(coins: Long, peer: String, ref: String): Boolean {
        ensure()
        val e = CoinEntry(CoinEntry.SEND, coins, ref, peer, null, moment(ref))
        if (coins <= 0 || ref.isEmpty() || e.id in taken || balance < coins) {
            Log.i("Montana", "coin_refused send coins=" + coins + " balance=" + balance)
            return false
        }
        return take(e)
    }
    /** Coins that arrived, credited once by their name. */
    @Synchronized fun receive(coins: Long, peer: String, ref: String, on: String? = null): Boolean {
        ensure()
        if (coins <= 0 || ref.isEmpty() || ("receive:" + ref) in taken || plus(balance, coins) == null) return false
        val ok = take(CoinEntry(CoinEntry.RECEIVE, coins, ref, peer, on, moment(ref)))
        if (ok) Log.i("Montana", "coin_rx coins=" + coins + " balance=" + balance)
        return ok
    }
    /** A coin letter proven on its way again takes its coins again, whatever the balance (iOS retake). */
    @Synchronized fun retake(coins: Long, peer: String, ref: String): Boolean {
        ensure()
        val e = CoinEntry(CoinEntry.SEND, coins, ref, peer, null, nowS())
        if (coins <= 0 || ref.isEmpty() || e.id in taken) return false
        return take(e)
    }
    /** Coins given on a letter or into a game's pot; refused (false) when the balance is short or the name was taken (iOS spend). */
    @Synchronized fun spend(coins: Long, on: String, peer: String, ref: String): Boolean {
        ensure()
        val e = CoinEntry(CoinEntry.SPEND, coins, ref, peer, on, moment(ref))
        if (coins <= 0 || ref.isEmpty() || e.id in taken || balance < coins) return false
        return take(e)
    }
    /** Coins already counted elsewhere, minted once under their name: a game's pot at its end (iOS mint). */
    @Synchronized fun mint(coins: Long, ref: String, peer: String? = null): Long {
        ensure()
        if (coins <= 0 || ref.isEmpty() || ("earn:" + ref) in taken || plus(balance, coins) == null) return 0
        return if (take(CoinEntry(CoinEntry.EARN, coins, ref, peer, null, nowS()))) coins else 0
    }
    /** Coins burned under their name, as many as the balance holds and no more, once by the name (iOS burn, MTWalletCore.swift:2271-2279). */
    @Synchronized fun burn(coins: Long, ref: String): Long {
        ensure()
        val c = minOf(coins, balance)
        if (c <= 0 || ref.isEmpty() || ("burn:" + ref) in taken) return 0
        return if (take(CoinEntry(CoinEntry.BURN, c, ref, at = nowS()))) c else 0
    }
    /** How many coins stand on a letter or a pot, given and received alike (iOS coins(on:)). */
    @Synchronized fun coins(on: String): Long { ensure(); return onTarget[on] ?: 0L }
    @Synchronized fun holds(k: String, ref: String): Boolean { ensure(); return (k + ":" + ref) in taken }
    fun received(ref: String): Boolean = holds(CoinEntry.RECEIVE, ref)
    /** The coins of one move by its kind and name (a coin letter's transfer, read when its row is gone: CoinSend.arrived). */
    @Synchronized fun amount(k: String, ref: String): Long? { ensure(); return entries.lastOrNull { it.k == k && it.ref == ref }?.c }
    /** How many moves the book holds: the wallet reads its chains' heads again when it moves (iOS .task(id: book.entries.count)). */
    @Synchronized fun size(): Int { ensure(); return entries.size }
    /** The moves, newest first, for the history. */
    @Synchronized fun moves(): List<CoinEntry> { ensure(); return entries.asReversed().toList() }

    /** THE BOOK OF A PERSON FORGOTTEN LEAVES WITH THEM (iOS MTCoinPlace.setAside): set aside whole under the moment, read by nobody again. */
    @Synchronized fun setAside() {
        generation++
        CoinVault.forget()   // the person who left takes their vault's memory with them (iOS MTCoinBook.reread)
        CoinTx.mine = null; CoinSplit.forget()   // and what their chain's node said
        ownAt = -1
        windows.clear()
        val d = File(Book.ctx.filesDir, "Coins")
        val place = File(File(Book.ctx.filesDir, "CoinsForgotten").apply { mkdirs() }, System.currentTimeMillis().toString())
        if (d.exists()) d.renameTo(place)
        TimeChain.setAside(place)   // the person's chains leave with their book
        CoinBoard.forget()   // and the balances their correspondents told them (iOS SeedScope.seatKeys «coinBoard.told», MontanaChatStore.swift:6269)
        entries.clear(); taken.clear(); onTarget.clear()
        balance = 0; earned = 0; tapped = 0; played = 0; walled = 0; received = 0; sent = 0; spent = 0; burned = 0; level = 0
        changed()
    }
}

/**
 * PANTHEON ON FIRE (iOS MTPantheon, the author's words 03.10-04.10.2026): the first touch of the wallet's coin lights the game,
 * every tap mints the level's coins, thirteen taps a second at most — time bounds the coins, not a quicker finger. Three quiet
 * seconds put the fire out; a burn of sixty seconds rests sixty.
 */
object Pantheon {
    const val CEILING = 13
    const val PREFIX = "tap:"
    private const val STREAK_MS = 60_000L
    private const val QUIET_MS = 3_000L
    var lit = false; private set
    var speed = 0; private set
    private var litAt = 0L
    var restUntil = 0L; private set
    private val taps = ArrayList<Long>()
    private var holding = false
    private var quiet = 0
    private var settling = false
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { listeners.add(l) }
    fun unlisten(l: () -> Unit) { listeners.remove(l) }
    private fun changed() = listeners.toList().forEach { it() }
    val rests: Boolean get() = System.currentTimeMillis() < restUntil

    private fun light() {
        if (lit || rests) return
        lit = true
        val at = System.currentTimeMillis()
        litAt = at
        MainThread.later(STREAK_MS, Runnable { if (lit && litAt == at) rest() })
        changed()
    }
    private fun rest() {
        quiet++
        lit = false; litAt = 0; speed = 0; taps.clear()
        val until = System.currentTimeMillis() + STREAK_MS
        restUntil = until
        MainThread.later(STREAK_MS, Runnable { if (restUntil == until) { restUntil = 0; changed() } })
        changed()
    }
    /** A finger landed on the coin: the game lights at the touch itself, and burns while the finger holds. */
    fun touched() { holding = true; quiet++; light() }
    /** The last finger left the coin, or the page left under it. */
    fun released() { if (!holding) return; holding = false; goOutAfterQuiet() }
    /** One touch of the coin: the coins it minted, none past the thirteenth of a second. */
    fun tap(): Long {
        val now = System.currentTimeMillis()
        taps.removeAll { 1000 <= now - it }
        if (rests) return 0
        light()
        if (!holding) goOutAfterQuiet()
        if (CEILING <= taps.size) return 0
        taps.add(now)
        speed = taps.size
        val coins = CoinBook.mintInWindow(1, PREFIX, 1)
        settle()
        changed()
        return coins
    }
    private fun goOutAfterQuiet() {
        val q = ++quiet
        MainThread.later(QUIET_MS, Runnable { if (q == quiet && lit) { lit = false; litAt = 0; changed() } })
    }
    /** The speed reads the last second again ten times a second until no tap is left in it. */
    private fun settle() {
        if (settling) return
        settling = true
        MainThread.later(100, Runnable {
            settling = false
            val now = System.currentTimeMillis()
            taps.removeAll { 1000 <= now - it }
            if (speed != taps.size) { speed = taps.size; changed() }
            if (taps.isNotEmpty()) settle()
        })
    }
}

/**
 * THE PULL SWITCHES THE AUTO MINTING ON (iOS MTWalletPull, MTWalletCore.swift:1376-1418; the author's words 04.10.2026 03:52 and 04:18
 * MSK: «pulling the wallet's page, as the time panel does, calls the coin for a forced refresh of the tops and the activation of the
 * auto minting once a second»): a pull let go past the coin's trigger mints at once and goes on minting every second — the box's
 * number of coins, the book multiplies — on the one beat of the minting by the second (MintBeat). THE PERSON ENDS IT, NO CLOCK (13:33
 * MSK, and 05.10.2026 00:53 MSK: «only leaving the page or locking the screen, touches do not reset the auto minting»): the page
 * leaving and the app leaving the screen stop it (walletPage), nothing else does. The pull asks the nodes for the pairs' last words
 * at once, their balances ride them (Signal.sweep). Android minted one second a release, as the pull did at its birth (build 2093).
 */
object WalletPull {
    const val PREFIX = Pantheon.PREFIX + "pull-"
    var on = false; private set
    private var loggedAt = 0L
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { listeners.add(l) }
    fun unlisten(l: () -> Unit) { listeners.remove(l) }
    private fun changed() = listeners.toList().forEach { it() }

    fun fire() {
        Thread { runCatching { Signal.sweep(quiet = true) } }.start()   // the tops read again from the nodes at once (iOS 1396)
        if (on) return
        on = true
        Log.i("Montana", "wallet_pull auto on")
        changed()
        MintBeat.run()   // its seconds ride the one beat of the minting by the second (iOS 1401)
    }
    /** The page left or the app left the screen: the minting stops with it (iOS stop 1403-1408). */
    fun stop(why: String) {
        if (!on) return
        on = false
        Log.i("Montana", "wallet_pull auto off why=" + why)
        changed()
    }
    /** One second of the pull in the Pantheon's window of a minute (iOS mintSecond 1409-1412); the diary hears it once a minute. */
    fun mintSecond() {
        val coins = CoinBook.mintInWindow(1, PREFIX, 1)
        val now = System.currentTimeMillis()
        if (60_000L <= now - loggedAt) { loggedAt = now; Log.i("Montana", "wallet_pull coins=" + coins) }
    }
}

/**
 * ONE BEAT FOR THE MINTING BY THE SECOND (iOS MTMintBeat, MTWalletCore.swift:1664-1686; the author's word 04.10.2026 18:08 MSK): the
 * wallet's pull, the living VPN tunnel and a connected call each mint a second, asked at the same instant once a second on the screen's
 * thread; the beat runs while any of them wants it and stops by itself when none does. The one rise of the second's coins at the coin's
 * sides (MTCoinFlash.rise, iOS 1677-1678) is not here.
 */
object MintBeat {
    private const val BEAT_MS = 1000L
    private var beating = false
    fun run() = MainThread.post {
        if (beating) return@post
        beating = true
        beat()
    }
    private fun beat() {
        val vpn = VpnWallMint.wanted
        val call = CallMint.wanted
        if (!WalletPull.on && !vpn && !call) { beating = false; VpnWallMint.settle(); return }
        if (vpn) VpnWallMint.ask() else VpnWallMint.settle()
        if (WalletPull.on) WalletPull.mintSecond()
        if (call) CallMint.mintSecond()
        MainThread.later(BEAT_MS, Runnable { beat() })
    }
}

/**
 * A CALL'S SECOND FOLLOWS ITS CHAT (iOS MTCallMint, MTWalletCore.swift:1341-1374; the author's words 07.10.2026 18:5x, 21:3x and 21:4x
 * MSK: «from the money flow a call: +1 second +1 coin, and from an ordinary one -1 for a second of talk»; «7 coins a second of talk for
 * the 7th level»): every second a call stands connected, placed or answered, on the one beat (MintBeat), a call whose chat has the
 * Money Flow on mints the level's coins on this side in the calls' own window and TimeChain, and a call from an ordinary chat burns one
 * coin a second of talk on this side, once by its name — the call and the second. Each side counts its own phone's; Android minted
 * and burned nothing for a call.
 */
object CallMint {
    const val PREFIX = "callmint:"
    const val BURN = "callburn:"
    val wanted: Boolean get() = 0L < CallLine.connectedAt
    private var flowOf: Pair<String, Boolean>? = null   // a call's chat, asked once a call
    private var loggedAt = 0L
    fun mintSecond() {
        val talk = CallLine.talkSecond() ?: return
        val flow = flows(talk.peer, talk.call)
        // THE ORDINARY CHAT'S BURN WAITS FOR ITS PAIR (the conductor 09.10, coins a risk named to the author): iOS burns a second of an
        // ordinary chat's call and a bubble of it alike, and a person turns either into minting by the chat's Money Flow. Android has
        // neither the switch nor the bubble's burn yet (the chats module); a call alone burning would take coins no switch can save,
        // so the second burns nothing until the switch and the bubble's burn come with it.
        val coins = if (flow) CoinBook.mintInWindow(1, PREFIX, 1, byLevel = true) else 0L
        val now = System.currentTimeMillis()
        if (60_000L <= now - loggedAt) { loggedAt = now; Log.i("Montana", (if (flow) "call_mint" else "call_burn") + " coins=" + coins) }
    }
    /** The Money Flow is a chat's own switch; the call knows its peer, whose chat is asked once a call (iOS flows 1366-1373). */
    private fun flows(peer: String, call: String): Boolean {
        flowOf?.takeIf { it.first == call }?.let { return it.second }
        val on = MoneyFlow.isOn(peer)
        flowOf = call to on
        return on
    }
}

/**
 * THE MONEY FLOW IS A CHAT'S OWN (iOS MTMoneyFlow, MTWalletCore.swift:676-700): each conversation keeps its own switch under
 * «moneyFlow.» and its name -- its live words both ways (LiveDraft), its call's minting (CallMint); the chat's coin mark turns it.
 */
object MoneyFlow {
    /** [COMPAT-LOCAL] iOS MTMoneyFlowRow.mark: this phone's own row «the Money Flow began», never on the wire. */
    const val ROW = "​​MF:"
    fun isOn(conv: String): Boolean = conv.isNotEmpty() && Prefs.bool("moneyFlow." + conv, false)
    fun set(conv: String, on: Boolean) = Prefs.setBool("moneyFlow." + conv, on)
    fun isRow(text: String) = text.startsWith(ROW)
    /**
     * THE MONEY FLOW BEGAN IN THIS CHAT (iOS ChatStore.appendMoneyFlow, MontanaChatStore.swift:2963-2975): the one birth of its row,
     * this phone's own and read; the coin switched on again within a minute lays nothing more.
     */
    fun layRow(ref: String) {
        Book.edit(ref) { ch ->
            val last = ch.msgs.lastOrNull()
            if (last != null && isRow(last.text) && System.currentTimeMillis() - last.at < 60_000L) return@edit
            ch.msgs.add(Msg(Marks.mintMid(), ROW, true, System.currentTimeMillis(), state = 3))
        }
        android.util.Log.i("Montana", "money_flow begun peer=" + ref.take(10))
    }
}

/**
 * A COIN LETTER (iOS MTCoinLetter): coins sent to a person ride the chat's own letter road — the coin and the number on the first
 * line, the machine line under it, its JSON {c, id} in base64 with the URL's two letters. A build that does not know it reads the
 * words; the receiver's book credits it once by the letter's wire name, the same on both phones.
 */
object CoinLetter {
    const val LINK = "montana://coin/1/"
    const val MARK = "🪙 "
    class Coin(val c: Long, val id: String)
    fun text(c: Long, id: String): String {
        val code = Base64.encodeToString(JSONObject().put("c", c).put("id", id).toString().toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
            .replace('+', '-').replace('/', '_')
        return MARK + c + "\n" + LINK + code
    }
    fun parse(text: String): Coin? {
        if (!text.startsWith(MARK) || 512 < text.toByteArray(Charsets.UTF_8).size) return null
        val line = text.split("\n").last()
        if (!line.startsWith(LINK)) return null
        val code = line.removePrefix(LINK).replace('-', '+').replace('_', '/')
        val o = runCatching { JSONObject(String(Base64.decode(code, Base64.DEFAULT), Charsets.UTF_8)) }.getOrNull() ?: return null
        val c = o.optLong("c")
        val id = o.optString("id")
        if (c <= 0 || id.length != 36 || runCatching { UUID.fromString(id) }.isFailure) return null
        return Coin(c, id)
    }
    /** THE LETTER NAMES ITSELF (iOS bound): its id is the UUID of its own wire name, so a copy under another name names a letter that is not itself. */
    fun bound(coin: Coin, mid: String): Boolean {
        val core = mid.removePrefix("mid:")
        val dash = core.indexOf('-')
        return 0 <= dash && core.substring(dash + 1).equals(coin.id, ignoreCase = true)
    }
    /** The list's and the banner's words: the coin and the number (iOS MTRowLetter.coinCount). */
    fun preview(c: Context, text: String): String? = parse(text)?.let { MARK + CoinText.count(it.c) + " " + c.getString(R.string.coins_word) }
}

/**
 * THE COINS LEAVE BY THE CHAT'S OWN ROAD (iOS MTCoinSend): a transfer is a letter of the pair; the book is asked first, and a
 * short balance refuses here so nothing leaves. A coin letter of mine holds its coins while it is not red: red, they come back
 * by one move; on its way again, they are taken again by one move — each by its own name, so a door asked twice moves nothing twice.
 */
object CoinSend {
    private const val BACK = "back:"
    private const val AGAIN = "again:"
    /** The book's name of a letter: its wire name under «mid:», whichever form the row keeps (iOS arrived). */
    fun wire(mid: String): String = if (mid.startsWith("mid:")) mid else "mid:" + mid
    /** «mid:t» + birth millisecond + «-» + a uuid: the name a sender mints (iOS MTChatMint.wireName, MTWalletCore.swift:298-302). */
    fun wireName(s: String): Boolean {
        if (!s.startsWith("mid:t")) return false
        val ms = s.drop(5).takeWhile { it != '-' }
        return s.length == 5 + ms.length + 37 && UUID_FORM.matches(s.takeLast(36))
    }
    private val UUID_FORM = Regex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /** The coin letter a row is in its own right: a forward, a reply, an edited row or a file pays nothing. */
    fun coinOf(m: Msg): CoinLetter.Coin? = if (m.qt != null || m.edited || m.file != null) null else CoinLetter.parse(m.text)

    /** A pair's own conversation, open to letters, whose other end is a person and not my own words (OwnWords): where coins can go. */
    fun canPay(ref: String): Boolean = !Groups.isKey(ref) && Book.chat(ref) != null && Book.secret(ref) != null && !PeerSafety.isBlocked(ref) && !OwnWords.mine(ref)

    /** Coins given on the correspondent's letter (iOS MTCoinSend.react, MTWalletCore.swift:3010-3015; the menu's «Give a coin»): the book
     *  pays, the reaction word carries them, under a name of their own -- a second gift on one letter is a second gift. */
    fun react(coins: Long, m: Msg, conv: String): Boolean =
        !m.mine && canPay(conv) && give(coins, wire(m.mid), m.text, conv, java.util.UUID.randomUUID().toString().uppercase())
    /** An auto-reaction's coins on a chosen person's letter (iOS MTCoinSend.autoGive, MTWalletCore.swift:3017-3023, AutoReact): the paid
     *  reaction's own road under «auto:» and the letter's wire name, so a letter brought twice pays once. */
    const val AUTO_PREFIX = "auto:"   // NOT-UI: the book's own name
    fun autoGive(coins: Long, mid: String, words: String, conv: String): Boolean = give(coins, wire(mid), words, conv, AUTO_PREFIX + wire(mid))
    /**
     * THE ONE ROAD OF A PAID REACTION (iOS give, MTWalletCore.swift:3024-3031): the book pays on the letter's name, and the reaction word
     * carries the coins («op»: «coin», «c», «r» -- the name the reader's book credits them under, CoinSend.reacted there); a build that
     * does not know the op reads nothing at all. A short balance pays nothing and sends nothing.
     */
    fun give(coins: Long, sid: String, words: String, conv: String, ref: String): Boolean {
        if (!CoinBook.spend(coins, sid, conv, ref)) return false
        val word = Marks.REACTION + JSONObject().put("sid", sid).put("txt", words).put("e", "🪙").put("op", "coin").put("c", coins).put("r", ref)
        Post.send(conv, Marks.mintMid(), word)
        return true
    }

    /** A transfer's three honest outcomes (iOS MTCoinSend.TransferResult): the coins left (the record's name), the sum is above the
     *  available, or a record waits for a node's word -- never «not enough» for a road's or a chain's silence. */
    sealed class Transfer {
        class Sent(val id: String) : Transfer()
        object Short : Transfer()
        object Pending : Transfer()
    }
    /**
     * COINS TO A PERSON ARE A RECORD ON THE NODES, THE LETTER ONLY TELLS (iOS MTCoinSend.transferResult 2983-3010; MTCoinTx.sendResult):
     * the available the page shows weighs the sum (CoinSplit); the record's node's 200 is the moment the coins left and the book's debit;
     * then a letter in the chat says how many and carries the transfer's address in the Explorer. A refusal after the available held is
     * a state of the chain or the road, said as pending -- the shown available would lie as «not enough». Off the screen's thread.
     */
    private val sending = Any()
    /** ONE TRANSFER AT A TIME (the owner's word 17.10.2026: «no double debit»): two sends never weigh the same available and lay on the
     *  same head at once -- the second waits for the first one's word. */
    fun transferResult(ref: String, coins: Long): Transfer = synchronized(sending) { transferOnce(ref, coins) }
    private fun transferOnce(ref: String, coins: Long): Transfer {
        if (!canPay(ref) || coins <= 0) { Log.i("Montana", "coin_refused transfer invalid coins=$coins"); return Transfer.Pending }
        val available = CoinSplit.available
        if (available < coins) { Log.i("Montana", "coin_refused transfer coins=$coins available=$available"); return Transfer.Short }
        return when (val r = CoinTx.live.sendResult(coins, ref)) {
            is CoinClient.Sent.Left -> {
                val mid = Marks.mintMid()
                val text = CoinTx.telling(coins, r.id)
                Book.edit(ref) { it.msgs.add(Msg(mid, text, true, Marks.birthMs(mid) ?: System.currentTimeMillis())) }
                Post.send(ref, mid, text)
                Log.i("Montana", "coin_send coins=$coins id=" + r.id.take(12) + " balance=" + CoinBook.balance)
                Transfer.Sent(r.id)
            }
            CoinClient.Sent.Pending -> { Log.i("Montana", "coin_pending transfer coins=$coins"); Transfer.Pending }
            is CoinClient.Sent.NotLeft -> { Log.i("Montana", "coin_pending transfer unconfirmed coins=$coins why=" + r.why); Transfer.Pending }
        }
    }

    /** Coins to a person, as a coin letter in their chat (the road of a build that lays no record). False: refused, nothing sent. */
    fun transfer(ref: String, coins: Long): Boolean {
        if (!canPay(ref) || coins <= 0) return false
        val mid = Marks.mintMid()
        if (!CoinBook.send(coins, ref, wire(mid))) return false
        val text = CoinLetter.text(coins, mid.substringAfter('-'))
        Book.edit(ref) { it.msgs.add(Msg(mid, text, true, Marks.birthMs(mid) ?: System.currentTimeMillis())) }
        Post.send(ref, mid, text)
        Log.i("Montana", "coin_send coins=" + coins + " balance=" + CoinBook.balance)
        return true
    }

    /**
     * COINS GIVEN ON A LETTER (iOS MTCoinSend.reacted 2601-2605, applyReactionFromControl 5901-5908; the author's word 03.10): a
     * reaction word with the op «coin» carries coins the giver's book has paid; credited once, by the name it carries, never shown
     * as an emoji. Android read it as the coin's emoji and credited nothing — the coins were gone from the giver and never came here.
     */
    private const val RECEIVED = "rc:"
    fun reacted(c: Long, ref: String, sid: String, chat: String) {
        if (c <= 0 || ref.isEmpty() || sid.isEmpty()) return
        CoinBook.receive(c, chat, RECEIVED + ref, on = sid)
    }

    /** A letter of theirs landed (Post): a coin letter is credited once by its wire name. */
    fun landed(ref: String, mid: String, text: String, qt: String?) {
        if (qt != null || Groups.isKey(ref)) return
        val coin = CoinLetter.parse(text) ?: return
        if (credits(coin, mid, ref)) CoinBook.receive(coin.c, ref, wire(mid))
    }

    /**
     * A COIN LETTER IS CREDITED WHEN IT NAMES ITSELF (iOS credits): the first letter of a pair that names itself notes its birth; a
     * letter of that pair born later under another name is a copy and credits nothing.
     */
    private fun credits(coin: CoinLetter.Coin, mid: String, chat: String): Boolean {
        val born = Marks.birthMs(mid) ?: System.currentTimeMillis()
        val since = Prefs.str("coinBinds." + chat, "0").toLongOrNull() ?: 0L
        if (CoinLetter.bound(coin, mid)) {
            if (since == 0L || born < since) Prefs.setStr("coinBinds." + chat, born.toString())
            return true
        }
        if (since == 0L || born < since) return true
        Log.i("Montana", "coin_refused a copy under another name")
        return false
    }

    private fun moves(k: String, name: String): Int {
        var n = 0
        while (CoinBook.holds(k, name + ":" + (n + 1))) n++
        return n
    }

    /** A coin letter of mine holds its coins exactly while it is not red (iOS hold). */
    fun hold(m: Msg, ref: String) {
        if (!m.mine) return
        val coin = coinOf(m) ?: return
        val name = wire(m.mid)
        if (!CoinBook.holds(CoinEntry.SEND, name)) return
        val again = moves(CoinEntry.SEND, AGAIN + name)
        val back = moves(CoinEntry.RECEIVE, BACK + name)
        if (m.state == -1 && again == back) giveBack(coin.c, ref, BACK + name + ":" + (back + 1), "red")
        else if (m.state != -1 && again != back) CoinBook.retake(coin.c, ref, AGAIN + name + ":" + (again + 1))
    }
    /**
     * A COIN LETTER THAT DID NOT ARRIVE IN A DAY COMES HOME (the author's word 09.10.2026 11:3x MSK: «if the coins have
     * not arrived within 24 hours they must be returned»; measured 08.10: 727 639 coins rode a letter to an account that no longer
     * exists, never receipted, held for good). The node's box keeps a letter one day from the moment it took it, so a coin letter of
     * mine with no receipt a day after the box took it (after its birth, if no box ever did) can draw none: it leaves the queue, its
     * row turns red and hold gives its coins back. A receipt that still comes takes them again (hold, arrived): nothing is paid twice.
     */
    const val DAY_MS = 24 * 3600_000L
    fun expire() {
        val now = System.currentTimeMillis()
        for (chat in Book.all()) {
            if (Groups.isKey(chat.ref)) continue
            for (late in chat.msgs.filter { it.mine && (it.state == 0 || it.state == 1) && coinOf(it) != null && DAY_MS <= now - since(it) }) {
                Post.unqueue(late.mid)
                var red: Msg? = null
                Book.edit(chat.ref) { c -> c.msgs.find { it.mid == late.mid && it.mine }?.let { m -> if (m.advance(-1)) red = m } }
                red?.let {
                    hold(it, chat.ref)
                    Log.i("Montana", "coin_day coins=" + (coinOf(it)?.c ?: 0) + " state_was=" + late.state + " no receipt in a day")
                }
            }
        }
    }
    /** Where a coin letter's day starts: the box took it, or it was born and no box ever did. */
    private fun since(m: Msg): Long = if (m.state == 1 && 0 < m.statusAt) m.statusAt else Marks.birthMs(m.mid) ?: m.at

    /** Whether a coin letter of mine stands red with its coins back (the bubble says so). */
    fun returned(m: Msg): Boolean {
        val name = wire(m.mid)
        return m.mine && m.state == -1 && moves(CoinEntry.SEND, AGAIN + name) < moves(CoinEntry.RECEIVE, BACK + name)
    }

    /**
     * A COIN LETTER OF MINE ON ITS WAY IS NOT DELETED (iOS MTCoinSend.travels, MTWalletCore 2528-2539, the coin audit's first point
     * 05.10): a row deleted by the hand while it said «sending» or «sent» took its letter off the road and left its coins taken
     * — the receiver never had them and the sender never got them back. The letter keeps its row until its road ends: delivered
     * (the coins are the receiver's) or red (they come back by hold). Every door of the hand asks this first.
     */
    fun travels(m: Msg): Boolean {
        if (!m.mine || (m.state != 0 && m.state != 1) || m.mid.isEmpty()) return false
        coinOf(m) ?: return false
        val name = wire(m.mid)
        return CoinBook.holds(CoinEntry.SEND, name) && moves(CoinEntry.SEND, AGAIN + name) == moves(CoinEntry.RECEIVE, BACK + name)
    }
    /** Whether a conversation holds a coin letter of mine on its way: its deletion by the hand waits for the road to end (iOS coinsTravel). */
    fun travelsIn(ref: String): Boolean = Book.chat(ref)?.msgs?.any { travels(it) } == true

    /**
     * THE COINS OF A LETTER THAT CAN NO LONGER GO COME BACK FIRST (iOS MTCoinSend.release, removeConversationLocally 3484-3490): the
     * correspondent's erasure for both reaches here unasked — a coin letter of mine not proven delivered and still holding its coins
     * gives them back by the back move before its row goes.
     */
    fun release(m: Msg, ref: String) {
        if (!m.mine || m.state == 2 || m.state == 3 || m.mid.isEmpty()) return
        val coin = coinOf(m) ?: return
        val name = wire(m.mid)
        if (!CoinBook.holds(CoinEntry.SEND, name)) return
        val back = moves(CoinEntry.RECEIVE, BACK + name)
        if (moves(CoinEntry.SEND, AGAIN + name) != back) return
        giveBack(coin.c, ref, BACK + name + ":" + (back + 1), "gone")
    }
    /** The one back move of a coin letter (iOS giveBack): its coins come home under the letter's next back name, and the system chain says why. */
    private fun giveBack(c: Long, ref: String, back: String, why: String) {
        if (!CoinBook.receive(c, ref, back)) return
        TimeChain.note("system", "back", c, back)
        Log.i("Montana", "coin_back coins=" + c + " letter=" + why)
    }

    /**
     * A RECEIPT FOR A COIN LETTER OF MINE WHOSE ROW IS GONE (iOS MTCoinSend.arrived, MTWalletCore 2551-2562; markDelivered 4266): the
     * letter did arrive, so the coins that came back — released above, or red and then deleted — are taken again by one move, by the
     * amount the book's own transfer named. Without it the receiver held them and so did the sender.
     */
    fun arrived(mid: String, ref: String) {
        val name = wire(mid)
        if (!CoinBook.holds(CoinEntry.SEND, name)) return
        val c = CoinBook.amount(CoinEntry.SEND, name) ?: return
        val again = moves(CoinEntry.SEND, AGAIN + name)
        val back = moves(CoinEntry.RECEIVE, BACK + name)
        if (back <= again) return
        val took = CoinBook.retake(c, ref, AGAIN + name + ":" + (again + 1))
        Log.i("Montana", "coin_again coins=" + c + " took=" + (if (took) 1 else 0) + " row=gone")
    }

    /**
     * THE BOOK HOLDS EVERY COIN LETTER THE CHATS HOLD (iOS settle): once the history stands, a correspondent's coin letter the book
     * never credited is credited by its wire name, and every coin letter of mine is asked whether it holds its coins.
     */
    fun settle() {
        var letters = 0
        var coins = 0L
        for (chat in Book.all()) {
            if (Groups.isKey(chat.ref)) continue
            for (m in chat.msgs) {
                if (m.mine) { hold(m, chat.ref); continue }
                // ONE LETTER, ONE NAME, ONE CREDIT (iOS settle 3205-3212, 09.10.2026): a letter is credited under its wire name alone. A copy
                // a correspondent gave back carries that name inside its own, so the letter and its copy credit once; an archive's copy
                // names no wire name and credits nothing -- its coins moved under the wire name (Android credited it again as «mid:arc:»)
                val mid = m.mid.removePrefix(Keeping.RESTORED_GIVEN)
                val name = wire(mid)
                if (!wireName(name) || CoinBook.received(name)) continue
                val coin = coinOf(m) ?: continue
                if (!credits(coin, mid, chat.ref) || !CoinBook.receive(coin.c, chat.ref, name)) continue
                // THE SYSTEM'S OWN BRANCH OF THE TIMECHAIN (iOS settle, MTWalletCore 2602-2605): the credit stands in the received chain as
                // any other, and the system chain says why — a coin letter the book had lost, restored by its wire name, coins and moment
                TimeChain.note("system", "restore", coin.c, TimeChain.RESTORE + name)
                letters++; coins += coin.c
            }
        }
        if (0 < letters) TimeChain.flush()
        Log.i("Montana", "coin_settle letters=" + letters + " coins=" + coins + " balance=" + CoinBook.balance)
    }
}

/**
 * A PAIR OF MY OWN WORDS (iOS MTOwnWords, MTWalletCore.swift:2915-2944; the author's words 06.10.2026): a conversation whose other end
 * holds my 24 words -- my iPad, my second phone -- is no person to pay: no transfer and no paid reaction goes to it. The pair knows it by
 * the tag in the word about oneself (MyAbout «o», CoinVault.ownTag), or by the book, where one move stands from both its ends.
 */
object OwnWords {
    private fun key(conv: String) = "ownWords.$conv"   // NOT-UI: the mark's key (iOS «ownWords.»)
    private fun entropy(): ByteArray? = MontanaSeed.mnemonic?.let { MtBindings.nativeMnemonicToEntropy(it) }?.takeIf { it.size == 32 }
    /** The tag my word about myself carries to this pair; null while no words stand on the phone. */
    fun tag(conv: String): String? {
        if (conv.isEmpty()) return null
        val e = entropy() ?: return null
        return Base64.encodeToString(CoinVault.ownTag(e, conv), Base64.NO_WRAP).also { e.fill(0) }
    }
    /** The pair's word told its tag: the pair is mine when my words make the same one; a tag of other words lets the mark go. */
    fun heard(tag: String, conv: String) {
        val t = runCatching { Base64.decode(tag, Base64.DEFAULT) }.getOrNull()?.takeIf { it.size == 32 } ?: return
        if (conv.isEmpty()) return
        val e = entropy() ?: return
        val mine = CoinVault.ownTagHolds(t, e, conv).also { e.fill(0) }
        if (Prefs.bool(key(conv), false) == mine) return
        if (mine) Prefs.setBool(key(conv), true) else Prefs.remove(key(conv))
        Log.d("Montana", "own_words pair=" + conv.take(10) + " mine=" + (if (mine) 1 else 0) + " by=word")
    }
    /** Whether the other end of this pair holds my words: by the pair's word or by the book. */
    fun mine(conv: String): Boolean = conv.isNotEmpty() && (Prefs.bool(key(conv), false) || conv in CoinBook.ownPeers())
}

/**
 * THE OWNER SHOWS OR HIDES THEIR COINS (iOS MTCoinShow, MTWalletCore.swift:655-663): one switch, on unless its owner turned it off,
 * that the coins told to correspondents ask (Presence.coinTail); the privacy page turns it.
 */
object CoinShow {
    val on: Boolean get() = Prefs.bool("coins.shown", true)
    /** The owner turns it (iOS PrivacyView «Show my coins» → showChanged): the pairs in the app hear the coins said, or not, at once. */
    fun set(v: Boolean) { Prefs.setBool("coins.shown", v); CoinTell.moved() }
}

/**
 * THE PEOPLE IN THE APP HEAR MY BALANCE MOVE (iOS MTCoinTell, MTWalletCore.swift:565-581; the author's words 04.10.2026 03:03 and 04:19
 * MSK: «the update instant, as by a web socket»): a move of the book says the balance again to the correspondents in the app now, in
 * the app word itself (Presence.coinBeacon) — one round in two seconds however fast the coins come. The one table of the Montana top
 * on the nodes (MTTopNet.put, iOS 578) is not on Android.
 */
object CoinTell {
    private const val PACE_MS = 2000L
    private var due = false
    fun moved() = MainThread.post {
        if (due) return@post
        due = true
        MainThread.later(PACE_MS, Runnable {
            due = false
            val peers = Presence.appOnline()
            if (peers.isNotEmpty()) Thread { for (p in peers) Presence.coinBeacon(p) }.start()
        })
    }
}

/**
 * THE PEOPLE'S COINS (iOS MTCoinBoard, MTWalletCore.swift:583-631; balances are public, [I-2]): every pair's presence word tells its
 * balance after the ground's digits (iOS E2E.coinsSaid and heardCoins, MontanaE2E.swift:598-614), live or swept from the node, and this
 * book keeps what each pair last told — the newest word wins, a negative balance is «hidden» and its row leaves. Every word tells it,
 * so the moment always moves and the disk only when the coins did. The person's own, leaving with them (CoinBook.setAside). The top
 * thirteen that reads it (iOS MTCoinTop13) is not on Android yet.
 */
object CoinBoard {
    private const val KEY = "coinBoard.told"
    private class Told(val coins: Long, val at: Double)
    private var told: HashMap<String, Told>? = null
    private fun book(): HashMap<String, Told> = told ?: HashMap<String, Told>().also { t ->
        runCatching { val o = JSONObject(Prefs.str(KEY, "{}")); for (k in o.keys()) o.optJSONObject(k)?.let { x -> t[k] = Told(x.optLong("coins"), x.optDouble("at", 0.0)) } }
        told = t
    }
    private fun keep(t: Map<String, Told>) {
        val o = JSONObject()
        for ((k, v) in t) o.put(k, JSONObject().put("coins", v.coins).put("at", v.at))
        Prefs.setStr(KEY, o.toString())
    }
    @Synchronized fun note(conv: String, coins: Long, at: Double) {
        val t = book()
        if (at < (t[conv]?.at ?: 0.0)) return
        if (coins < 0) { if (t.remove(conv) != null) keep(t); return }
        val moved = t[conv]?.coins != coins
        t[conv] = Told(coins, at)
        if (moved) keep(t)
    }
    @Synchronized fun forget() { told = HashMap(); Prefs.remove(KEY); levels = HashMap(); levelHeardAt.clear(); Prefs.remove(LEVELS_KEY) }
    /** The balance a pair last told, none when it never told one or hides it (iOS told[conv]?.coins). */
    @Synchronized fun coins(conv: String): Long? = book()[conv]?.coins

    // THE PEOPLE'S LEVELS (iOS MTCoinBoard.levels, noteLevel, MTWalletCore.swift:614-648, the author's word 11.10.2026 21:2x MSK): the
    // Global Level each pair last told in its presence words; the newest word wins, a word that names none takes it away
    private const val LEVELS_KEY = "coinBoard.levels"
    private class Level(val level: Int, val at: Double)
    private var levels: HashMap<String, Level>? = null
    private val levelHeardAt = HashMap<String, Double>()
    private fun levelBook(): HashMap<String, Level> = levels ?: HashMap<String, Level>().also { t ->
        runCatching { val o = JSONObject(Prefs.str(LEVELS_KEY, "{}")); for (k in o.keys()) o.optJSONObject(k)?.let { x -> t[k] = Level(x.optInt("level"), x.optDouble("at", 0.0)) } }
        levels = t
    }
    @Synchronized fun noteLevel(conv: String, level: Int, at: Double) {
        val t = levelBook()
        if (at < maxOf(t[conv]?.at ?: 0.0, levelHeardAt[conv] ?: 0.0)) return
        levelHeardAt[conv] = at
        if (0 <= level) { if (t[conv]?.level == level) return; t[conv] = Level(level, at) }
        else if (t.remove(conv) == null) return
        Prefs.setStr(LEVELS_KEY, JSONObject().apply { for ((k, v) in t) put(k, JSONObject().put("level", v.level).put("at", v.at)) }.toString())
    }
    /** The Global Level a pair last told, none when it never told one or withdrew it (iOS levels[conv]). */
    @Synchronized fun level(conv: String): Int? = levelBook()[conv]?.level
    /**
     * A word of the peer told its Global Level or withdrew it (iOS levelSaid/heardLevel, MontanaE2E.swift:601-624): «L» after the balance's
     * digits, or after the ground's when the coins are hidden; a word naming the held tags and no level withdraws one told before.
     * «Q» closes the tags (iOS deletionQuietSaid): their build takes a deletion for everyone quietly.
     */
    fun heardLevel(peer: String, payload: String, atMs: Long) {
        var i = payload.indexOf('N')
        if (i < 0) return
        fun digits(from: Int): Int { var j = from; while (j < payload.length && payload[j].isDigit()) j++; return j }
        i = digits(i + 1)
        if (i < payload.length && payload[i] == 'A') i = digits(i + 1)
        if (i >= payload.length || payload[i] != 'W') return
        i = digits(i + 1)
        if (i >= payload.length || payload[i] != 'G') return
        i = digits(i + 1)
        if (i < payload.length && payload[i] == 'C') { i++; while (i < payload.length && (payload[i].isDigit() || payload[i] == '-')) i++ }
        val level = if (i < payload.length && payload[i] == 'L') payload.substring(i + 1).takeWhile { it.isDigit() }.toIntOrNull() ?: -1 else -1
        if (i < payload.length && payload[i] == 'L') i = digits(i + 1)
        if (i < payload.length && payload[i] == 'Q' && !Prefs.bool("dqcap_$peer", false)) Prefs.setBool("dqcap_$peer", true)
        noteLevel(peer, level, atMs / 1000.0)
    }
    /** A word of the peer, live or swept, told its balance: «C» and its digits after «N», «A», «W» and «G» and theirs (iOS coinsSaid 599-609). */
    fun heard(peer: String, payload: String, atMs: Long) {
        var i = payload.indexOf('N')
        if (i < 0) return
        fun digits(from: Int): Int { var j = from; while (j < payload.length && payload[j].isDigit()) j++; return j }
        i = digits(i + 1)
        if (i < payload.length && payload[i] == 'A') i = digits(i + 1)
        if (i >= payload.length || payload[i] != 'W') return
        i = digits(i + 1)
        if (i >= payload.length || payload[i] != 'G') return
        i = digits(i + 1)
        if (i >= payload.length || payload[i] != 'C') return
        val coins = payload.substring(i + 1).takeWhile { it.isDigit() }.toLongOrNull() ?: return
        note(peer, coins, atMs / 1000.0)
    }
}

/**
 * THE WINDOWS OF THE WALL'S COMMENTS (iOS MTWallWindow, MTBoard.wallWindows and window(of:), MontanaBoard.swift:1350-1358 and
 * 1418-1452; the author's word 01.10.2026 23:02 MSK, CouncilWall/COIN-PATH.md): a post opens a window of time while comments stand
 * under it; a minute of silence between two comments breaks it and its share is none. Unbroken, it is open while its last comment is
 * younger than a minute, and its share is the whole minutes from its first comment to its end — now, while it is open — one at
 * least. Every post this phone holds, my wall's first, then each wall of my people, once by its name. The wallet shows them beside
 * the book and never adds them into it: only the core turns a right into a note.
 */
object WallWindows {
    private const val SILENCE = 60.0
    class Row(val title: String, val share: Int, val open: Boolean, val span: String, val marks: List<String>)
    fun all(): List<Row> {
        val seen = HashSet<String>()
        val rows = ArrayList<Row>()
        fun take(p: JSONObject) { if (seen.add(p.optString("id"))) window(p)?.let { rows.add(it) } }
        for (p in MyWall.posts()) take(p)
        for (wall in Book.refs()) for (item in Board.posts(wall)) take(item.post)
        return rows
    }
    private fun window(p: JSONObject): Row? {
        val a = p.optJSONArray("comments") ?: return null
        val cs = (0 until a.length()).mapNotNull { a.optJSONObject(it)?.optDouble("at", 0.0) }.sorted()
        if (cs.isEmpty()) return null
        var broken = false
        for (i in 1 until cs.size) if (!(cs[i] - cs[i - 1] < SILENCE)) broken = true
        val now = System.currentTimeMillis() / 1000.0
        val live = now - cs.last() < SILENCE && !broken
        val length = maxOf(0.0, (if (live) now else cs.last()) - cs.first())
        val minutes = if (broken) 0 else maxOf(1, (length / SILENCE).toInt())
        val text = p.optString("text")
        val title = if (text.isEmpty()) p.optString("id") else if (text.codePointCount(0, text.length) <= 80) text else text.substring(0, text.offsetByCodePoints(0, 80))
        return Row(title, minutes, live, local(cs.first()) + " | " + local(cs.last()), cs.map { local(it) })
    }
    /** A moment on this phone's clock to the millisecond, as iOS MTBoard.local writes it (MontanaBoard.swift:1256-1265). */
    private fun local(at: Double): String {
        var sec = at.toLong()
        var ms = ((at - sec) * 1000 + 0.5).toInt()
        if (ms == 1000) { ms = 0; sec += 1 }
        if (ms < 0) ms = 0
        return java.text.SimpleDateFormat("dd.MM.yyyy HH:mm:ss", java.util.Locale.US).format(java.util.Date(sec * 1000)) + "." + ms.toString().padStart(3, '0')
    }
}
