package quest.montana.app

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/**
 * THE WALL OF THOUGHTS FOR EVERYONE (iOS MTBoardGlobal, MontanaBoard.swift:2602-2801 at 2316; the author's word 18.10.2026 17:1x UTC:
 * «the whole wall must be global for all users, as the top is, and everything right -- the avatars, the names, the order»). A wall shown
 * to everyone (the sight rule EVERYONE) lays its owner's own posts on the nodes' public table (/wall-put) under a row only the owner's
 * words derive, as the top lays its rows; every phone reads the table (/wall-get), and the feed stands the posts of all people by the
 * moment each was published. A post of the table is read here and answered nowhere: its writer is nobody this phone knows (Board.writer
 * gives null), it wears the name and the face it carried, and no word of a wall goes to it -- its wall's reference («g:» and the row) is
 * held by no conversation. Nothing of a person leaves whose wall is not shown to everyone; a rule moved from everyone withdraws every
 * post at once.
 */
object WallGlobal {
    const val PREFIX = "g:"                                        // NOT-UI: a wall of the table, held by no conversation
    private const val SENT_KEY = "wall.global.sent"                // NOT-UI: this device's own record of what it laid
    private const val HIDDEN_KEY = "wall.global.hidden"            // NOT-UI: the writers of the table the person hid
    private val keyLabel = "mt-wall-owner-v1".toByteArray()       // NOT-UI: the derivation's own label
    private val tokenLabel = "mt-wall-token".toByteArray()        // NOT-UI: the token's own label
    // THE WHOLE WALL (the author's word 19.10.2026 08:4x UTC: «everyone must see the global feed of everyone, totally»): every post of
    // mine, of any age, up to the node's row (WALL_PER_ROW); the table read page by page up to the node's whole (WALL_POSTS).
    const val PER_OWNER = 1000
    const val TABLE_WHOLE = 5000
    const val BUDGET = 90 * 1024
    private const val HAVE_WHOLE = 4096                           // the most names a node's /blob-have answers at once
    private const val PAGE = 300                                  // a node answers 300 posts at most

    private val lock = Any()
    @Volatile var posts: List<Pair<String, JSONObject>> = emptyList(); private set
    private var readAt = 0L
    private var reading = false
    private var laying = false
    private var keptAt = 0L
    private var layWork: Runnable? = null

    fun isRef(wall: String?) = wall?.startsWith(PREFIX) == true
    fun key(entropy: ByteArray): ByteArray = Hkdf.sha256(entropy, ByteArray(0), keyLabel)
    fun token(k: ByteArray): ByteArray = Hkdf.hmac(k, tokenLabel)
    fun row(token: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(token))
    private fun myToken(): ByteArray? = HomeShelf.entropy()?.let { token(key(it)) }

    /** THE FROZEN VECTORS (iOS keyKAT: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting bytes 0x00..0x1f): the top's
     *  label in place of this one, a reversed root or a row hashed as hex text all fail them. */
    fun keyKAT(): Boolean {
        val k = key(ByteArray(32) { it.toByte() })
        val t = token(k)
        return hex(k) == "e2cdd8ddc43893fd6761039367f5d55e8ac52d2427d346383b0d12fd64d13ec9"
            && hex(t) == "23fc0c606a9a9d8665c3fb328e12cf35376b6491c689d010a2528135e1d3eb7a"
            && row(t) == "4b600b4950935a76a7c63c815f7af404dc71dfa22e1400391f763e7bb8730c8f"
    }

    fun hidden(): Set<String> = Prefs.str(HIDDEN_KEY, "").split('\n').filter { it.isNotEmpty() }.toSet()
    /** THE PERSON HIDES A WRITER OF THE TABLE (Guideline 1.2: a way to stop seeing a person): their posts leave this feed for good. */
    fun hide(wall: String) {
        if (!isRef(wall)) return
        val r = wall.removePrefix(PREFIX)
        val h = hidden() + r
        Prefs.setStr(HIDDEN_KEY, h.sorted().joinToString("\n"))
        synchronized(lock) { posts = posts.filter { it.first != r } }
        Board.tableMoved()
        Log.d("Montana", "wall_global hid a writer hidden=" + h.size)
    }

    private fun sent(): MutableMap<String, String> {
        val o = runCatching { JSONObject(Prefs.str(SENT_KEY, "{}")) }.getOrNull() ?: JSONObject()
        return o.keys().asSequence().associateWith { o.optString(it) }.toMutableMap()
    }

    // ── the owner lays ──
    fun laySoon() = MainThread.post {
        layWork?.let { MainThread.cancel(it) }
        val w = Runnable { Thread { lay() }.start() }
        layWork = w
        MainThread.later(2000L, w)
    }
    private fun lay() {
        val tok = myToken() ?: return
        synchronized(lock) { if (laying) return; laying = true }
        try {
            val hx = hex(tok)
            val sent = sent()
            val work = mutableListOf<Triple<String, String?, JSONObject>>()
            if (WallRule.current(WallRule.Act.SEE) != WallRule.Rule.EVERYONE) {
                if (sent.isEmpty()) return
                work.add(Triple("*", null, JSONObject().put("token", hx).put("hide", "*")))
            } else {
                val shown = MyWall.publicPosts(PER_OWNER, BUDGET)
                for (id in sent.keys) if (id !in shown) work.add(Triple(id, null, JSONObject().put("token", hx).put("hide", id)))
                for ((id, x) in shown) if (sent[id] != x.first) work.add(Triple(id, x.first, JSONObject().put("token", hx).put("post", x.second)))
            }
            if (work.isEmpty()) return
            val now = sent()
            var laid = 0
            for ((id, digest, body) in work) {
                if (send("/wall-put", body) == null) continue
                laid++
                if (id == "*") now.clear() else if (digest == null) now.remove(id) else now[id] = digest
            }
            Prefs.setStr(SENT_KEY, JSONObject(now as Map<*, *>).toString())
            Log.d("Montana", "wall_global laid=" + laid + " of=" + work.size + " held=" + now.size)
        } finally { synchronized(lock) { laying = false } }
    }

    // ── the owner keeps the files ──
    /**
     * THE FILES OF THE TABLE ARE KEPT BY THEIR OWNER (iOS keepFiles, the author's word 22.10 18:19: «no music plays from the common wall
     * -- everything must work»): a reader of the table answers nobody, so the pieces a node let go never came back. The owner, who alone
     * holds the bytes and the key, asks every store at the app's return whether the pieces of the posts it shows to everyone lie there,
     * and lays again under the same key the ones they lack: the same bytes sealed by the same key give the same names.
     */
    fun keepFiles() {
        if (WallRule.current(WallRule.Act.SEE) != WallRule.Rule.EVERYONE) return
        synchronized(lock) { val now = System.currentTimeMillis(); if (now - keptAt < 600_000L) return; keptAt = now }
        Thread {
            val jobs = mutableListOf<Triple<String, JSONArray, List<String>>>()
            var asked = 0
            for ((id, media) in MyWall.ownMedia(PER_OWNER)) {
                val bids = (0 until media.length()).flatMap { i ->
                    val cs = media.optJSONObject(i)?.optJSONArray("chunks") ?: JSONArray()
                    (0 until cs.length()).mapNotNull { k -> cs.optJSONObject(k)?.optString("bid")?.takeIf { it.isNotEmpty() } }
                }
                if (asked + bids.size > HAVE_WHOLE) break
                asked += bids.size
                jobs.add(Triple(id, media, bids))
            }
            if (jobs.isEmpty()) return@Thread
            // a silent store is «don't know» and lays nothing: only the stores' own word that a piece is missing moves the owner
            val have = Wire.blobsHave(jobs.flatMap { it.third }, everyStore = true) ?: return@Thread
            val lost = jobs.filter { j -> !j.third.all { it in have } }
            for (j in lost) Board.seedFiles(j.first, j.second)
            Log.d("Montana", "wall_global kept posts=" + jobs.size + " relaid=" + lost.size)
        }.start()
    }

    // ── every phone reads ──
    fun read() {
        synchronized(lock) {
            val now = System.currentTimeMillis()
            if (reading || now - readAt < 60_000L) return
            reading = true
        }
        Thread {
            val got = fetch()
            synchronized(lock) { reading = false; readAt = System.currentTimeMillis() }
            if (got == null) { Log.d("Montana", "wall_global read: no node answered"); return@Thread }
            val h = hidden()
            synchronized(lock) { posts = got.filter { it.first !in h } }
            Board.tableMoved()
            Log.d("Montana", "wall_global read posts=" + got.size)
        }.start()
    }

    private fun send(path: String, body: JSONObject): JSONObject? {
        for (door in Signal.writeOrder("top")) {
            val (code, text) = Wire.post(door, path, body)   // SERVER-DEBT-ACK: the accelerator node (rung 4), the public table
            if (code == 200) return runCatching { JSONObject(text ?: "{}") }.getOrNull() ?: JSONObject()
        }
        return null
    }
    /** A post's name in the table: its row and its id. */
    private fun name(x: JSONObject): String? {
        val r = x.optString("row").takeIf { it.isNotEmpty() } ?: return null
        val id = x.optJSONObject("post")?.optString("id")?.takeIf { it.isNotEmpty() } ?: return null
        return "$r/$id"
    }
    private fun list(j: JSONObject?): List<JSONObject>? =
        j?.optJSONArray("posts")?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } }
    /** A post of another hand owes this screen nothing: it is read as a post, its marks of mine set to none, its name letters only. */
    private fun fetch(): List<Pair<String, JSONObject>>? {
        // THE TABLE PAGE BY PAGE (iOS fetch, 19.10.2026): the next page is asked below the oldest moment held, one second over it so a
        // moment shared across the edge is not lost -- the repeats fall to the name -- until a page brings nothing new or the whole is read.
        val all = list(send("/wall-get", JSONObject()))?.toMutableList() ?: return null
        val names = all.mapNotNull { name(it) }.toMutableSet()
        var page: List<JSONObject> = all.toList()
        while (all.size < TABLE_WHOLE && page.size == PAGE) {
            val oldest = page.mapNotNull { it.optJSONObject("post")?.takeIf { p -> p.has("at") }?.optDouble("at") }.minOrNull() ?: break
            val more = list(send("/wall-get", JSONObject().put("before", oldest.toLong() + 1))) ?: break
            val fresh = more.filter { x -> name(x)?.let { names.add(it) } ?: false }
            if (fresh.isEmpty()) break
            all += fresh
            page = more
        }
        val mine = myToken()?.let { row(it) }
        val out = mutableListOf<Pair<String, JSONObject>>()
        for (x in all) {
            val r = x.optString("row")
            val p = x.optJSONObject("post") ?: continue
            if (r.length != 64 || r == mine || p.optString("id").isEmpty()) continue
            val s = Board.clean(p)
            for (k in listOf("mine", "liked", "kept", "reposted", "pinned", "from")) s.remove(k)
            s.put("own", true).put("comments", JSONArray())
            s.put("byName", s.optString("byName").filter { !Character.isISOControl(it) && Character.getType(it) != Character.FORMAT.toInt() }.take(64))
            out.add(r to s)
        }
        return out
    }
}
