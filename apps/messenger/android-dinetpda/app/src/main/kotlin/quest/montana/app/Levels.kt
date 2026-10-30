package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * THE CHAIN OF THE PERSON (iOS MTPersonChain, MTWalletCore.swift:1884-2108; Canon, «The level of the chain of the person»): the seconds
 * the person's words were on the network -- every second the app stood on the screen and a node answered it, by the node's own clock,
 * never the phone's -- joined across every device of the words through a sealed piece beside the coin book on every node. The level is
 * the whole doublings of the count (bit_length(seconds) − 1); its links, one a level, are sealed one on the other as every TimeChain.
 */
object PersonChain {
    class Span(var a: Long, var b: Long)   // node seconds, both ends counted
    /** Two answers this far apart or nearer vouch for every second between them (iOS reach). */
    private const val REACH = 10L
    /** The away minting's name in the book (iOS awayPrefix): the Pantheon's own, «away-». */
    private const val AWAY_PREFIX = "tap:away-"
    private val AAD = "mt.person.chain".toByteArray()   // NOT-UI: the words the piece's seal is bound to

    private val lock = Any()
    @Volatile var seconds = 0L; private set
    @Volatile var links: List<TimeChain.Link> = emptyList(); private set
    /** The level this life read, null until the seconds are read (iOS MTPersonLevel.now): an unknown level is never said as none. */
    @Volatile var known: Int? = null; private set
    val level: Int? get() = level(seconds)
    private val spans = ArrayList<Span>()
    private var lane = ByteArray(0)
    private var last: Long? = null   // the node second of the last answer in this stretch on the screen
    private var away: Pair<Long, Int>? = null   // the app left: the node second of its last answer and the Global Level then
    private var loaded = false; private var dirty = false; private var putting = false; private var keepDue = false; private var checked = false
    private var putAt = 0L; private var gotAt = 0L; private var fedAt = 0L
    private val opened = HashMap<String, ByteArray>()   // a piece's name: its lane, opened once
    private val mine = HashMap<String, String>()        // a node's door: the piece of this lane it holds now
    private val stale = HashSet<String>()

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    /** THE LEVEL (iOS level, Canon): the whole doublings of the count, none below one second. */
    fun level(s: Long): Int? = if (s < 1) null else 63 - java.lang.Long.numberOfLeadingZeros(s)
    /** THE FROZEN VECTORS (iOS levelKAT): level(1) = 0, level(3) = 1, level(1048576) = 20, none below one second, every power's edge. */
    fun levelKAT(): Boolean {
        if (level(1) != 0 || level(3) != 1 || level(1_048_576) != 20 || level(0) != null || level(-5) != null) return false
        for (k in 1..62) if (level(1L shl k) != k || level((1L shl k) - 1) != k - 1) return false
        return level(Long.MAX_VALUE) == 62
    }
    /** THE GLOBAL LEVEL OF THE PERSON (iOS global, the author's word 10.10.2026): the lower of the person's level and the wallet's of π. */
    fun global(person: Int?, balance: Long): Int = minOf(person ?: 0, PiLevels.place(balance))

    private fun file(): File = File(File(Book.ctx.filesDir, "TimeChain").apply { mkdirs() }, "person-seconds.json")
    private fun load() {
        if (loaded) return
        loaded = true
        val o = runCatching { JSONObject(file().readText()) }.getOrNull()
        val l = o?.optString("lane")?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() }
        if (o != null && l != null && l.size == 16) {
            lane = l
            spans.clear(); spans.addAll(joined(spansOf(o.optJSONArray("spans"))))
            away = o.optJSONObject("away")?.let { it.optLong("at") to it.optInt("level") }
        } else lane = ByteArray(16).also { SecureRandom().nextBytes(it) }
        recount(write = false)
    }
    private fun spansOf(a: JSONArray?): List<Span> = if (a == null) emptyList() else (0 until a.length()).mapNotNull { i ->
        a.optJSONObject(i)?.let { Span(it.optLong("a"), it.optLong("b")) }
    }
    private fun spansJson(): JSONArray = JSONArray().apply { for (s in spans) put(JSONObject().put("a", s.a).put("b", s.b)) }
    private fun keep() {
        val o = JSONObject().put("lane", Base64.encodeToString(lane, Base64.NO_WRAP)).put("spans", spansJson())
        away?.let { (at, lv) -> o.put("away", JSONObject().put("at", at).put("level", lv)) }
        runCatching { val f = file(); val tmp = File(f.path + ".tmp"); tmp.writeText(o.toString()); tmp.renameTo(f) }
    }
    private fun keepSoon() {
        if (keepDue) return
        keepDue = true
        MainThread.later(10_000, Runnable { synchronized(lock) { keepDue = false; keep() } })
    }
    /** The person left: their seconds go with their folder (iOS reread on a seat lifted). */
    fun forget() = synchronized(lock) {
        loaded = false; spans.clear(); links = emptyList(); seconds = 0; last = null; away = null
        opened.clear(); mine.clear(); stale.clear(); dirty = false; known = null
        runCatching { file().delete() }
    }
    /** The seconds read before a node's answer asks for them: a face that shows the level, and a word that says it, need them now. */
    fun prime() = synchronized(lock) { load() }

    /** Spans joined: sorted, any two that touch or overlap become one -- a second is counted once however many devices held it. */
    fun joined(all: List<Span>): List<Span> {
        val out = ArrayList<Span>()
        for (s in all.filter { it.a <= it.b }.sortedBy { it.a }) {
            val l = out.lastOrNull()
            if (l != null && s.a <= l.b + 1) l.b = maxOf(l.b, s.b) else out.add(Span(s.a, s.b))
        }
        return out
    }
    /** One link a level, at the node second the count reached 2^k, each sealed on the one before (iOS chain, TimeChain.seal). */
    fun chain(spans: List<Span>): List<TimeChain.Link> {
        val out = ArrayList<TimeChain.Link>()
        var count = 0L; var next = 1L; var prev = TimeChain.GENESIS
        for (s in spans) {
            val len = s.b - s.a + 1
            while (next <= count + len) {
                val at = (s.a + (next - count) - 1) * 1000
                val k = out.size
                val ref = "level:$k"
                val hash = TimeChain.seal(k + 1, at, "level", k.toLong(), ref, prev)
                out.add(TimeChain.Link(k + 1, at, "level", k.toLong(), ref, prev, hash))
                prev = hash
                if (next > Long.MAX_VALUE / 2) return out
                next *= 2
            }
            count += len
        }
        return out
    }
    /** The count and the links read again; the chain's file (TimeChain/wallet-person.jsonl) follows a new level. */
    private fun recount(write: Boolean = true) {
        seconds = spans.sumOf { it.b - it.a + 1 }
        known = level
        val fresh = chain(spans)
        if (fresh.lastOrNull()?.hash != links.lastOrNull()?.hash) {
            links = fresh
            if (write) TimeChain.lay("person", fresh)
        }
        changed()
    }

    /**
     * A NODE ANSWERED AN EXCHANGE OF THIS APP (iOS answered, fed by MontanaWakePush.personFeed and MTCoinVault.post, once a second at
     * most): while the app stands on the screen its second counts, and so does every second back to the answer before it when they
     * are no further apart than the reach. `serverMs` -- the answer's own Date.
     */
    fun answered(serverMs: Long) {
        if (!Presence.shown || serverMs <= 0) return
        val now = System.currentTimeMillis()
        val back: Pair<Long, Int>?
        val s = serverMs / 1000
        synchronized(lock) {
            if (now - fedAt < 1000) return
            fedAt = now
            load()
            back = away
            if (back != null) { away = null; keep() }
            val from = last?.takeIf { it <= s && s - it <= REACH } ?: s
            last = maxOf(last ?: s, s)
            val before = seconds
            val all = ArrayList(spans); all.add(Span(from, s))
            spans.clear(); spans.addAll(joined(all))
            recount()
            if (seconds != before) { dirty = true; keepSoon() }
        }
        if (back != null) came(s, back)
    }

    /**
     * THE MINTING GOES ON WHILE THE APP IS AWAY (iOS left/came, the author's word 10.10.2026 15:0x MSK): the app leaving the screen keeps
     * the node second of its last answer and the Global Level of that moment; the first answer after its return names the second it came
     * back, and every second between is minted at that level, the limit of a second at most. Both ends are the nodes' seconds, so a clock
     * turned on the phone moves nothing, and a stretch with no answer before the leave mints nothing.
     */
    fun left(global: Int) {
        synchronized(lock) {
            load()
            val from = last
            last = null
            if (from == null || global <= 0) return
            away = from to minOf(global, CoinBook.LIMIT.toInt())
            keep()
        }
        Thread { put() }.start()
    }
    private fun came(back: Long, w: Pair<Long, Int>) {
        val gone = back - w.first
        if (gone <= 0 || w.second <= 0) return
        val coins = runCatching { Math.multiplyExact(gone, w.second.toLong()) }.getOrNull() ?: return
        val minted = CoinBook.mintInWindow(coins, AWAY_PREFIX, gone.toInt(), byLevel = false)
        Log.i("Montana", "person_away seconds=$gone level=${w.second} minted=$minted")
        // the pay for the seconds away goes to the chain at once, not a window later (iOS 17.10.2026, P1)
        if (0 < minted) Thread { runCatching { CoinTx.mintSoon(); if (CoinTx.agrees) CoinTx.live.reconcile(force = true) } }.start()
    }

    // ── the devices of the words join their seconds: one sealed piece a device, beside the coin book on every node ──

    /** The beat asks this (iOS tick from the wallet's live loop): the other devices' pieces every half minute, this device's union when it moved, once a minute at most. */
    fun tick() {
        val (getDue, putDue) = synchronized(lock) {
            load()
            if (!checked) { checked = true; Log.i("Montana", "person_self ok=" + (if (levelKAT() && pieceKAT()) 1 else 0)) }
            val now = System.currentTimeMillis()
            val g = 30_000 <= now - gotAt
            if (g) gotAt = now
            g to (dirty && 60_000 <= now - putAt)
        }
        if (getDue) gather()
        if (putDue) put()
    }
    private fun cipher(mode: Int, key: ByteArray, nonce: ByteArray, at: Int = 0): Cipher =
        Cipher.getInstance("ChaCha20/Poly1305/NoPadding").apply { init(mode, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce, at, 12)); updateAAD(AAD) }
    /** The piece (iOS Piece): this device's lane and its spans, sealed by ChaChaPoly under the coin vault's seal -- no packing. */
    fun sealPiece(lane: ByteArray, spans: List<Span>, key: ByteArray, nonce: ByteArray = ByteArray(12).also { SecureRandom().nextBytes(it) }): ByteArray {
        val plain = JSONObject().put("lane", Base64.encodeToString(lane, Base64.NO_WRAP))
            .put("spans", JSONArray().apply { for (s in spans) put(JSONObject().put("a", s.a).put("b", s.b)) }).toString().toByteArray(Charsets.UTF_8)
        return nonce + cipher(Cipher.ENCRYPT_MODE, key, nonce).doFinal(plain)
    }
    private fun openPiece(sealed: ByteArray, key: ByteArray): Pair<ByteArray, List<Span>>? = runCatching {
        if (sealed.size < 28) return null
        val o = JSONObject(String(cipher(Cipher.DECRYPT_MODE, key, sealed).doFinal(sealed, 12, sealed.size - 12), Charsets.UTF_8))
        Base64.decode(o.getString("lane"), Base64.DEFAULT) to spansOf(o.optJSONArray("spans"))
    }.getOrNull()
    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b)
    /** THE PIECE'S FROZEN VECTOR (computed outside this code, the iOS piece of the counting entropy): the combined bytes and their name. */
    fun pieceKAT(): Boolean = runCatching {
        val e = ByteArray(32) { it.toByte() }
        val (seal, token) = CoinVault.personRow(e)
        val sealed = sealPiece(ByteArray(16) { it.toByte() }, listOf(Span(1_760_000_000, 1_760_000_009), Span(1_760_000_020, 1_760_000_040)), seal, ByteArray(12) { it.toByte() })
        hex(token) == "63d0546f8cf80b00e443732a517a18a47be99b8ce71ab3425e282c9b8809f51e" &&
            hex(sealed) == "000102030405060708090a0b97963768879d9889c902163a805d6bba7142cd5a2d11e5e6e3b9e25ebfa832a97ec6ad26e0b741183538134920b73d8e24fc5555ddb6eae749a5ba98813b5ecabbd3ee6bf9464e26676ed11428c4fc47e5322ebf25904a83bfcbf6931c94bccfeb07b7b67eab59f49eae4c5cc638b7e355bfbfac0defc940bc74125f30" &&
            hex(sha(sealed)) == "8a670179b7117071e13e266f25ff35112c0f934dd1b8648ce09f3d343ae4e81a"
    }.getOrDefault(false)

    /** THIS DEVICE'S UNION ON EVERY NODE (iOS put): the piece replaces the one this lane laid there before and the stale ones. */
    private fun put() {
        val e = CoinVault.entropy() ?: return
        val (seal, token) = CoinVault.personRow(e)
        val (sealed, gone0) = synchronized(lock) {
            if (putting) return
            putting = true
            putAt = System.currentTimeMillis()
            dirty = false
            sealPiece(lane, spans.map { Span(it.a, it.b) }, seal) to stale.toSet()
        }
        val id = hex(sha(sealed))
        var laid = 0
        try {
            for (door in Doors.onePerNode(Doors.ordered("vault"))) {
                val gone = (gone0 + listOfNotNull(synchronized(lock) { mine[door] })).filter { it != id }
                val body = JSONObject().put("token", hex(token)).put("blob", Base64.encodeToString(sealed, Base64.NO_WRAP)).put("replace", JSONArray(gone))
                val (code, o) = HttpVault.post(door, "/vault-put", body, 10_000)
                val piece = o?.optString("piece").orEmpty()
                if (code != 200 || piece.isEmpty()) continue
                synchronized(lock) { mine[door] = piece; opened[piece] = lane }
                laid++
            }
        } finally {
            synchronized(lock) { putting = false; if (0 < laid) stale.clear() else dirty = true }
        }
        Log.d("Montana", "person_put spans=${spans.size} seconds=$seconds doors=$laid")
    }
    /** THE OTHER DEVICES' SECONDS (iOS gather): the first door that answers; a piece is its own name; no second of the future is a second lived. */
    private fun gather() {
        val e = CoinVault.entropy() ?: return
        val (seal, token) = CoinVault.personRow(e)
        val gen = CoinBook.generation
        for (door in Doors.onePerNode(Doors.ordered("vault"))) {
            val have = synchronized(lock) { opened.keys.take(256) }
            val (code, o) = HttpVault.post(door, "/vault-get", JSONObject().put("token", hex(token)).put("have", JSONArray(have)), 6_000)
            val held = o?.optJSONArray("held")
            if (code != 200 || o == null || held == null) continue
            if (gen != CoinBook.generation) return   // the seat moved during the wait: nothing of the person who left joins
            val horizon = NodeClock.now() / 1000 + 60
            val got = ArrayList<Span>()
            val pieces = o.optJSONArray("pieces") ?: JSONArray()
            synchronized(lock) {
                for (i in 0 until pieces.length()) {
                    val x = pieces.optJSONObject(i) ?: continue
                    val id = x.optString("piece")
                    val b = runCatching { Base64.decode(x.optString("blob"), Base64.DEFAULT) }.getOrNull() ?: continue
                    if (hex(sha(b)) != id) continue
                    val (l, sp) = openPiece(b, seal) ?: continue
                    opened[id] = l
                    if (l.contentEquals(lane)) { if (mine[door] != id) stale.add(id); continue }
                    got.addAll(sp.filter { it.b <= horizon })
                }
                val standing = (0 until held.length()).map { held.optString(it) }.toSet()
                opened.keys.retainAll(standing)
                val before = seconds
                val all = ArrayList(spans); all.addAll(got)
                spans.clear(); spans.addAll(joined(all))
                recount()
                if (seconds != before) { dirty = true; keepSoon() }
                Log.d("Montana", "person_get seconds=$seconds level=${level ?: -1} joined=${seconds - before}")
            }
            return
        }
    }
}

/**
 * ACCESS BY LEVEL (iOS MTLevelAccess, MTWalletCore.swift:727-756, the author's words 16.10.2026 18:2x MSK: «the gamification of access to
 * Montana's functions»): every function a level opens is named here once, with its level. The person's level is the Global Level; before
 * this life has read it, the last one this phone knew stands, so a launch's first second never drops a choice the level opened.
 */
object LevelAccess {
    enum class Feature(val level: Int) {
        KEEP_DELETED(7),   // a letter the correspondent deletes for everyone stays on this phone, and the correspondent is told
        AUTO_RECORD(7),    // calls are recorded by themselves
        OWN_NODE(8),       // a machine the person owns joins Montana's network through this app
    }
    const val LAST_KEY = "levelAccess.last"            // NOT-UI: the last Global Level this phone knew of this person
    const val KEEP_KEY = "levelAccess.keepDeleted"      // NOT-UI: the person's choice, on once the level opens it
    val level: Int? get() {
        val last = Prefs.str(LAST_KEY, "").toIntOrNull()
        val p = PersonChain.known ?: return last
        val c = CoinBook.said ?: return last
        val g = PersonChain.global(p, c)
        if (last != g) Prefs.setStr(LAST_KEY, g.toString())
        return g
    }
    fun opens(f: Feature) = f.level <= (level ?: 0)
    /** The person keeps the letters their correspondents delete: the level opens it, and it stands until they untick it. */
    val keepsDeleted: Boolean get() = opens(Feature.KEEP_DELETED) && Prefs.bool(KEEP_KEY, true)
}

/**
 * THE LEVELS' DISTRIBUTION (iOS MTLevelDistribution, MTWalletCore.swift:756-835): how many people stand at each Global Level, read from
 * the nodes that hold «levels» (POST /level-get), at most once a minute and on every return to the app, and kept for the next launch;
 * a level's rank among them colours its badge on a face, red at the bottom to green at the top. Nodes that do not hold «levels» are
 * not asked. [COMPAT-LOCAL] reads only: the iPhone also lays its own level in it (/level-put, a public write) -- not on Android
 * without the owner's word.
 */
object LevelDistribution {
    private const val KEY = "level.distribution"   // NOT-UI: iOS cacheKey, the bins as JSON
    class Bin(val level: Int, val count: Int)
    @Volatile private var bins: List<Bin> = runCatching {
        JSONArray(Prefs.str(KEY, "[]")).let { a -> valid((0 until a.length()).map { a.getJSONObject(it).let { o -> Bin(o.getInt("level"), o.getInt("count")) } }) }
    }.getOrDefault(emptyList())
    private var asking = false
    private var readAt = 0L
    private var attemptedAt = 0L

    /** Levels 0…62 at most once each, every count 1…1 000 000, 63 bins at most -- else none (iOS valid). */
    private fun valid(input: List<Bin>): List<Bin> {
        val clean = input.filter { it.level in 0..62 && it.count in 1..1_000_000 }
        if (clean.map { it.level }.toSet().size != clean.size || 63 < clean.size) return emptyList()
        return clean.sortedBy { it.level }
    }
    /** A level's place among the people, 0 at the bottom to 1 at the top, each level at the middle of its own people (iOS rank). */
    fun rank(level: Int): Double? {
        val b = bins
        val first = b.firstOrNull() ?: return null
        val last = b.last()
        if (first.level == last.level) return if (level < first.level) 0.0 else 1.0
        if (level <= first.level) return 0.0
        if (level >= last.level) return 1.0
        val total = b.sumOf { it.count.toDouble() }
        val before = b.filter { it.level < level }.sumOf { it.count.toDouble() }
        val same = (b.firstOrNull { it.level == level }?.count ?: 0).toDouble()
        val low = first.count / 2.0
        val high = total - last.count / 2.0
        return ((before + same / 2 - low) / (high - low)).coerceIn(0.0, 1.0)
    }
    /** The badge's colour of a level (iOS levelColor: hue rank / 3, saturation 0.82, brightness 0.58), the grey of 0.35 while unknown. */
    fun color(level: Int): Int = rank(level)?.let { android.graphics.Color.HSVToColor(floatArrayOf((it / 3 * 360).toFloat(), 0.82f, 0.58f)) }
        ?: android.graphics.Color.rgb(89, 89, 89)
    /** Reads the distribution again: five seconds after a try, a minute after a read (iOS refresh, its reading half). */
    fun refresh() {
        val now = System.currentTimeMillis()
        synchronized(this) {
            if (asking || now - attemptedAt < 5_000 || now - readAt < 60_000) return
            asking = true; attemptedAt = now
        }
        try {
            for (base in Doors.ordered("levels").take(3)) {
                val (code, o) = HttpVault.post(base, "/level-get", JSONObject(), 6_000)
                val rows = o?.optJSONArray("levels") ?: continue
                if (code != 200) continue
                val next = valid((0 until rows.length()).mapNotNull { i -> rows.optJSONObject(i)?.let { r ->
                    if (r.has("level") && r.has("count")) Bin(r.optInt("level"), r.optInt("count")) else null } })
                bins = next
                Prefs.setStr(KEY, JSONArray().apply { next.forEach { put(JSONObject().put("level", it.level).put("count", it.count)) } }.toString())
                synchronized(this) { readAt = System.currentTimeMillis() }
                Log.d("Montana", "level_distribution bins=" + next.size)
                return
            }
        } finally { synchronized(this) { asking = false } }
    }
}
