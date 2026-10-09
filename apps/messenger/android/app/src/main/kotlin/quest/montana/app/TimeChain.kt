package quest.montana.app

import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

// ─────────────────────────── the wallet's TimeChains (iOS MTWalletCore: MTTimeChain, MTTimeChainPlace; MontanaBubble: MTLetterSeal) ───────────────────────────

/**
 * THE TIMECHAINS OF THE MINTING (iOS MTTimeChain, MTWalletCore 1450-1628; the author's words 04.10.2026 00:25 MSK): every source of
 * coins keeps its own chain on this phone — chess, the Pantheon, the chats' letters, the coins received, given and sent: one link
 * per move of coins, numbered, stamped in milliseconds and sealed by SHA-256 over the link and the seal of the one before, so a link
 * changed or moved breaks every seal after it. The book keeps the balance; the chains keep how every coin came. A move joins its
 * chain once, by its name, and the book's whole past joins again at its reading, so a link a dying process left out comes back.
 * The line is the iPhone's own JSON line (n, at in milliseconds, k, c, ref, prev, hash) and the seal is the iPhone's own: all 86
 * links of T1's sent chain hold under it (08.10.2026), so a chain reads the same on either phone.
 */
object TimeChain {
    class Link(val n: Int, val at: Long, val k: String, val c: Long, val ref: String, val prev: String, val hash: String) {
        fun line(): String = JSONObject().put("n", n).put("at", at).put("k", k).put("c", c).put("ref", ref).put("prev", prev).put("hash", hash).toString()
        companion object {
            fun of(line: String): Link? = runCatching {
                val o = JSONObject(line)
                Link(o.getInt("n"), o.getLong("at"), o.getString("k"), o.getLong("c"), o.getString("ref"), o.getString("prev"), o.getString("hash"))
            }.getOrNull()
        }
    }
    class Head(val n: Int, val hash: String, val whole: Boolean)
    val GENESIS = "0".repeat(64)
    /** The sources, each its own chain, in the wallet's order. */
    val SOURCES = listOf("pi", "chess", "pantheon", "vpnwall", "vpnpay", "timer", "chats", "groups", "channels", "comments", "wall", "received", "spent", "sent", "calls", "letters", "system")
    /** The system chain's name for a restored credit: this prefix and the coin letter's wire name (iOS MTCoinSend.restorePrefix). */
    const val RESTORE = "restore:"

    private val CHESS = listOf("chess:", "chess-won:", "chess-lost:", "chess-pot:", "chess-stake:", "chess-back:")   // iOS MTChessCoins.owns
    private val BOARD = listOf("cmt:", "cmt-burn:", "cmt-pay:")   // iOS MTBoardCoins.owns

    private val q = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "montana.TimeChains").apply { isDaemon = true } }
    private class Held(var n: Int, var hash: String, val refs: HashSet<String>)
    private class Pending(val chain: String, val kind: String, val coins: Long, val ref: String, val at: Long)
    private val held = HashMap<String, Held>()   // on q: each chain read once
    private val waiting = LinkedHashMap<String, StringBuilder>()   // on q: the links sealed and not yet in their files
    private var due = false

    /** The chain a move belongs to (iOS source(ref:kind:peer:)): the names of the games first, then the move's way. */
    fun source(e: CoinEntry): String = source(e.ref, e.k, e.peer)
    fun source(ref: String, kind: String, peer: String? = null): String {
        if (CHESS.any { ref.startsWith(it) }) return "chess"
        if (ref.startsWith(Pantheon.PREFIX)) return "pantheon"
        if (ref.startsWith("vpnwall:")) return "vpnwall"
        if (ref.startsWith("vpnpay:")) return "vpnpay"
        if (ref.startsWith("callmint:")) return "calls"
        if (ref.startsWith("timer:")) return "timer"
        if (BOARD.any { ref.startsWith(it) }) return "comments"
        return when (kind) {
            // a group's and a channel's coins stand in their own chains: the letter's conversation names its chain
            CoinEntry.EARN -> if (peer == null || !Groups.isKey(peer)) "chats" else if (Groups.isChannel(peer)) "channels" else "groups"
            CoinEntry.RECEIVE -> "received"
            CoinEntry.SPEND -> "spent"
            CoinEntry.SEND -> "sent"
            else -> if (ref.startsWith("call:")) "calls" else "letters"
        }
    }

    /** THE TIMECHAIN FOLDER (iOS MTTimeChainPlace): one file a source, wallet-SOURCE.jsonl, the person's own and leaving with them. */
    private fun dir(): File = File(Book.ctx.filesDir, "TimeChain").apply { mkdirs() }
    private fun file(chain: String): File = File(dir(), "wallet-" + chain + ".jsonl")

    /** The seal: SHA-256 over the link's fields, one per line, the previous seal last. */
    fun seal(n: Int, at: Long, k: String, c: Long, ref: String, prev: String): String =
        sha256(listOf(n.toString(), at.toString(), k, c.toString(), ref, prev).joinToString("\n"))
    fun sha256(s: String): String = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    /** One moment to the millisecond, the same on every device (iOS ms): rounded, never cut. */
    fun ms(seconds: Double): Long = Math.round(seconds * 1000)

    private fun links(chain: String): List<Link> {
        val f = file(chain)
        val bytes = if (f.exists()) runCatching { f.readBytes() }.getOrNull() else null
        if (bytes == null) return emptyList()
        return String(bytes, Charsets.UTF_8).split('\n').mapNotNull { if (it.isBlank()) null else Link.of(it) }
    }
    private fun state(chain: String): Held = held.getOrPut(chain) {
        val all = links(chain)
        Held(all.lastOrNull()?.n ?: 0, all.lastOrNull()?.hash ?: GENESIS, all.mapTo(HashSet()) { it.ref })
    }

    /** One move of coins joins its source's chain, once by its name; a move between people is in its file in the same turn. */
    fun append(e: CoinEntry, now: Boolean = false) = appendPast(listOf(e), now)
    /** The book's whole past in one turn of the queue, not a turn for every move (iOS appendPast). */
    fun appendPast(moves: List<CoinEntry>, now: Boolean = false) {
        if (moves.isEmpty()) return
        val links = moves.map { e -> Pending(source(e), e.k, e.c, e.ref, ms(e.at)) }
        q.execute { for (l in links) write(l); if (now) writeWaiting() }
    }
    /** One link that is not a move of coins (a level of π reached, the system's word): the same seal, the same once-by-name. */
    fun note(chain: String, kind: String, coins: Long, ref: String, at: Double = System.currentTimeMillis() / 1000.0) {
        val p = Pending(chain, kind, coins, ref, ms(at))
        q.execute { write(p) }
    }

    /** Queue-only: one link joins its chain, once by its name; its file takes it within a second, with the others of that second. */
    private fun write(p: Pending) {
        val h = state(p.chain)
        if (p.ref in h.refs) return
        val n = h.n + 1
        val hash = seal(n, p.at, p.kind, p.coins, p.ref, h.hash)
        waiting.getOrPut(p.chain) { StringBuilder() }.append(Link(n, p.at, p.kind, p.coins, p.ref, h.hash, hash).line()).append('\n')
        h.n = n; h.hash = hash; h.refs.add(p.ref)
        if (!due) { due = true; q.schedule(Runnable { writeWaiting() }, 1, TimeUnit.SECONDS) }
    }
    /** Queue-only: every waiting link into its chain's file; a line cut short by an ended process is ended first. */
    private fun writeWaiting() {
        due = false
        if (waiting.isEmpty()) return
        val all = LinkedHashMap(waiting)
        waiting.clear()
        for ((chain, text) in all) runCatching {
            RandomAccessFile(file(chain), "rw").use { r ->
                val end = r.length()
                if (0L < end) { r.seek(end - 1); if (r.read() != 10) { r.seek(end); r.write(10) } }
                r.seek(r.length())
                r.write(text.toString().toByteArray(Charsets.UTF_8))
                r.fd.sync()
            }
        }.onFailure { Log.w("Montana", "timechain " + chain + ": " + it.javaClass.simpleName) }
    }
    /** The app leaves the screen: the waiting links are written now. */
    fun flush() { q.execute { writeWaiting() } }

    /** Every link of a chain as its file holds it, the waiting ones written first (the chain's own page, a move's page). */
    fun read(chain: String, done: (List<Link>) -> Unit) {
        q.execute { writeWaiting(); val all = links(chain); MainThread.post { done(all) } }
    }
    /** Every chain read whole and every seal checked from the genesis: its length, its head, whether it is whole. */
    fun heads(done: (Map<String, Head>) -> Unit) {
        q.execute { writeWaiting(); val all = SOURCES.associateWith { check(links(it)) }; MainThread.post { done(all) } }
    }
    /** One chain's links and its head from one reading (the chain's own page). */
    fun chain(chain: String, done: (List<Link>, Head) -> Unit) {
        q.execute { writeWaiting(); val all = links(chain); val h = check(all); MainThread.post { done(all, h) } }
    }
    private fun check(all: List<Link>): Head {
        var prev = GENESIS
        var whole = true
        var n = 0
        for (l in all) {
            n++
            if (l.n != n || l.prev != prev || l.hash != seal(l.n, l.at, l.k, l.c, l.ref, l.prev)) { whole = false; break }
            prev = l.hash
        }
        return Head(n, prev, whole)
    }

    /** THE CHAINS OF A PERSON FORGOTTEN LEAVE WITH THEM (iOS: the folder is the seated person's): set aside whole beside their book. */
    fun setAside(place: File) {
        q.execute {
            writeWaiting()
            held.clear()
            val d = File(Book.ctx.filesDir, "TimeChain")
            if (d.exists()) { place.mkdirs(); d.renameTo(File(place, "TimeChain")) }
        }
    }
}

/**
 * THE SEAL OF A LETTER (iOS MTLetterSeal, MontanaBubble 149-170): SHA-256 over the domain and the letter's one wire name — «mid:t»,
 * the birth millisecond, «-» and the uuid, minted once by the sender — the one field both phones hold byte for byte, so every device
 * that holds a transfer reads the same seal (the Global TimeChain of a move's page). A row with no wire name has none.
 */
object LetterSeal {
    private const val DOMAIN = "montana-letter-seal"
    fun seal(mid: String): String? = if (mid.startsWith("mid:")) TimeChain.sha256(DOMAIN + "\n" + mid) else null
}
