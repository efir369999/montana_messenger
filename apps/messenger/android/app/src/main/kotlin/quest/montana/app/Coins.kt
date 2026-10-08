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
    fun line(): String = JSONObject().put("k", k).put("c", c).put("ref", ref).apply {
        if (peer != null) put("peer", peer)
        if (on != null) put("on", on)
    }.put("at", at).toString()

    companion object {
        const val EARN = "earn"
        const val RECEIVE = "receive"
        const val SPEND = "spend"
        const val SEND = "send"
        const val BURN = "burn"
        private val KINDS = setOf(EARN, RECEIVE, SPEND, SEND, BURN)
        fun of(line: String): CoinEntry? = runCatching {
            val o = JSONObject(line)
            val k = o.getString("k")
            if (k !in KINDS) return null
            CoinEntry(k, o.getLong("c"), o.getString("ref"), o.optString("peer").ifEmpty { null }, o.optString("on").ifEmpty { null }, o.getDouble("at"))
        }.getOrNull()
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
    var received = 0L; private set
    var sent = 0L; private set
    var spent = 0L; private set
    var burned = 0L; private set

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun dir(): File = File(Book.ctx.filesDir, "Coins").apply { mkdirs() }
    private fun file(): File = File(dir(), FILE)
    private fun nowS(): Double = System.currentTimeMillis() / 1000.0

    /** The book is read once, off the screen's thread, at the app's start (iOS warm). */
    @Synchronized fun warm() { ensure() }

    private fun ensure() {
        if (read) return
        read = true
        val bytes = runCatching { file().takeIf { it.exists() }?.readBytes() }.getOrNull() ?: return
        // ONE BAD BYTE COSTS ONE LINE, NEVER THE BOOK (iOS decode): every line is read alone
        var start = 0
        for (i in 0..bytes.size) {
            if (i == bytes.size || bytes[i] == 10.toByte()) {
                if (start < i) CoinEntry.of(String(bytes, start, i - start, Charsets.UTF_8))?.let { adopt(it) }
                start = i + 1
            }
        }
        Log.i("Montana", "coin_book read moves=" + entries.size + " balance=" + balance)
    }

    private fun adopt(e: CoinEntry) {
        if (e.c <= 0 || e.id in taken) return
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
        when (e.k) {
            CoinEntry.EARN -> if (e.ref.startsWith(Pantheon.PREFIX)) tapped = sat(tapped, e.c) else earned = sat(earned, e.c)
            CoinEntry.RECEIVE -> received = sat(received, e.c)
            CoinEntry.SPEND -> spent = sat(spent, e.c)
            CoinEntry.SEND -> sent = sat(sent, e.c)
            CoinEntry.BURN -> burned = sat(burned, e.c)
        }
    }

    /** The one door every move passes: refused when the balance cannot hold it, written in the same turn. */
    private fun take(e: CoinEntry): Boolean {
        val next = plus(balance, e.signed) ?: run { Log.i("Montana", "coin_refused " + e.k + " the balance cannot hold it"); return false }
        entries.add(e); taken.add(e.id)
        balance = next
        count(e)
        write(listOf(e))
        changed()
        return true
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
        if (prefix == Pantheon.PREFIX) tapped = sat(tapped, c) else earned = sat(earned, c)
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
    }
    /** Every open window into the book now: the app leaves the screen, the person leaves. */
    @Synchronized fun closeWindows() { for (p in windows.keys.toList()) close(p) }

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
    /** How many coins stand on a letter or a pot, given and received alike (iOS coins(on:)). */
    @Synchronized fun coins(on: String): Long { ensure(); return onTarget[on] ?: 0L }
    @Synchronized fun holds(k: String, ref: String): Boolean { ensure(); return (k + ":" + ref) in taken }
    fun received(ref: String): Boolean = holds(CoinEntry.RECEIVE, ref)
    /** The coins of one move by its kind and name (a coin letter's transfer, read when its row is gone: CoinSend.arrived). */
    @Synchronized fun amount(k: String, ref: String): Long? { ensure(); return entries.lastOrNull { it.k == k && it.ref == ref }?.c }
    /** The moves, newest first, for the history. */
    @Synchronized fun moves(): List<CoinEntry> { ensure(); return entries.asReversed().toList() }

    /** THE BOOK OF A PERSON FORGOTTEN LEAVES WITH THEM (iOS MTCoinPlace.setAside): set aside whole under the moment, read by nobody again. */
    @Synchronized fun setAside() {
        windows.clear()
        val d = File(Book.ctx.filesDir, "Coins")
        if (d.exists()) d.renameTo(File(File(Book.ctx.filesDir, "CoinsForgotten").apply { mkdirs() }, System.currentTimeMillis().toString()))
        entries.clear(); taken.clear(); onTarget.clear()
        balance = 0; earned = 0; tapped = 0; received = 0; sent = 0; spent = 0; burned = 0
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

    /** The coin letter a row is in its own right: a forward, a reply, an edited row or a file pays nothing. */
    fun coinOf(m: Msg): CoinLetter.Coin? = if (m.qt != null || m.edited || m.file != null) null else CoinLetter.parse(m.text)

    /** A pair's own conversation, open to letters: where coins can go. */
    fun canPay(ref: String): Boolean = !Groups.isKey(ref) && Book.chat(ref) != null && Book.secret(ref) != null && !PeerSafety.isBlocked(ref)

    /** Coins to a person, as a coin letter in their chat. False: refused, nothing sent. */
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
        if (m.state == -1 && again == back) CoinBook.receive(coin.c, ref, BACK + name + ":" + (back + 1))
        else if (m.state != -1 && again != back) CoinBook.retake(coin.c, ref, AGAIN + name + ":" + (again + 1))
    }
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
        CoinBook.receive(coin.c, ref, BACK + name + ":" + (back + 1))
        Log.i("Montana", "coin_back coins=" + coin.c + " letter=gone")
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
                val coin = coinOf(m) ?: continue
                if (CoinBook.received(wire(m.mid))) continue
                if (credits(coin, m.mid, chat.ref) && CoinBook.receive(coin.c, chat.ref, wire(m.mid))) { letters++; coins += coin.c }
            }
        }
        Log.i("Montana", "coin_settle letters=" + letters + " coins=" + coins + " balance=" + CoinBook.balance)
    }
}
