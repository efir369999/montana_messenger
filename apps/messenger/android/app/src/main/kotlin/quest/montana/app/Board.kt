package quest.montana.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ScrollView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

// ─────────────────────────── the walls of my people (iOS MontanaBoard.swift MTBoard, MontanaBoardViews.swift MTFeedTabView) ───────────────────────────

/**
 * THE WALL, AS ITS VISITOR READS IT (iOS MTBoard, the author's word 24.09): a person's posts travel as the service word «WL:» in the
 * one pipe between two people, their files as sealed pieces on the node's blind store under keys that ride only inside the pipes.
 * The owner carries the page; a visitor asks for it when the version in the owner's presence word moved, or when the feed is looked
 * at and the page held is older than ten minutes (iOS heard, lookFeed). Any word of the wall from here tells the owner's build that
 * this phone reads the wall, and from then on it carries its page here (iOS learnCap). This phone's own wall is still empty: an ask
 * is answered with the page of an empty wall nobody may write on, which reads as a refusal reads (iOS refusedVersion).
 */
object Board {
    const val MARK = "​​WL:"
    private const val PAGE_SIZE = 30
    private const val COMMENTS_SHOWN = 20
    private const val TEXT_LIMIT = 4000
    private const val COMMENT_LIMIT = 1000
    private const val MEDIA_LIMIT = 10          // iOS MTPostMeasure.files
    private const val THUMB_LIMIT = 60_000
    private const val FACE_LIMIT = 16_000
    private const val FEED_SIZE = 300
    private const val FIRST_KEPT = 2000
    private const val LOOK_STALE = 600_000L
    private const val LOOK_KEEP = 300           // iOS MTBoardLook.keep

    private val lock = Any()
    private var loaded = false
    private val pages = HashMap<String, JSONObject>()     // a wall's owner -> {w, ps, at, v}, as the owner last sent it
    private val firstSeen = HashMap<String, Long>()       // a post -> the moment this phone first held it (iOS held)
    private val askedAt = HashMap<String, Long>()
    private val answeredAt = HashMap<String, Long>()

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun store() = File(File(Book.ctx.filesDir, "board").apply { mkdirs() }, "pages.json")
    /** The person forgotten: the walls this phone held and the files brought for a look leave with them (Book.wipe). */
    fun wipe() = synchronized(lock) {
        pages.clear(); firstSeen.clear(); askedAt.clear(); answeredAt.clear(); loaded = false
        File(Book.ctx.filesDir, "board").deleteRecursively(); lookDir().deleteRecursively()
    }
    private fun ensure() {
        if (loaded) return
        loaded = true
        val o = runCatching { JSONObject(store().readText()) }.getOrNull() ?: return
        o.optJSONObject("pages")?.let { p -> p.keys().forEach { k -> p.optJSONObject(k)?.let { pages[k] = it } } }
        o.optJSONObject("first")?.let { f -> f.keys().forEach { k -> firstSeen[k] = f.optLong(k) } }
    }
    private fun save() {
        val p = JSONObject(); for ((k, v) in pages) p.put(k, v)
        val f = JSONObject(); firstSeen.entries.sortedByDescending { it.value }.take(FIRST_KEPT).forEach { f.put(it.key, it.value) }
        val part = File(store().path + ".part")
        runCatching { part.writeText(JSONObject().put("pages", p).put("first", f).toString()); part.renameTo(store()) }
    }

    /** iOS Announced.wireTag: the first four bytes of SHA-256 as a decimal number; nothing is «0». */
    fun wireTag(d: ByteArray?): String {
        if (d == null || d.isEmpty()) return "0"
        val h = Wire.sha(d)
        fun b(i: Int) = h[i].toLong() and 0xff
        return ((b(0) shl 24) or (b(1) shl 16) or (b(2) shl 8) or b(3)).toString()
    }
    private val emptyVersion by lazy { wireTag("0r".toByteArray()) }

    private fun send(ref: String, w: JSONObject): Boolean {
        if (Groups.isKey(ref) || PeerSafety.isBlocked(ref) || Book.secret(ref) == null) return false
        Post.send(ref, Marks.mintMid(), MARK + w.toString())
        Log.d("Montana", "wall_tx t=" + w.optString("t") + " to=" + ref.take(10))
        return true
    }

    /** The page of a correspondent's wall, asked of its owner — once a minute per wall at most (iOS ask). */
    fun ask(ref: String) {
        val now = System.currentTimeMillis()
        synchronized(lock) { if (now - (askedAt[ref] ?: 0L) < 60_000L) return; askedAt[ref] = now }
        send(ref, JSONObject().put("t", "ask"))
    }
    private fun people() = Book.refs().filter { !Groups.isKey(it) && !PeerSafety.isBlocked(it) && SamePair.merged(it) == null }
    /** THE LOOK ASKS (iOS lookFeed, the author's word 25.09): every wall not held, or held from more than ten minutes ago. */
    fun lookFeed() {
        val now = System.currentTimeMillis()
        val due = synchronized(lock) { ensure(); people().filter { r -> now - (pages[r]?.optLong("at") ?: 0L) >= LOOK_STALE } }
        due.forEachIndexed { i, r -> MainThread.later(300L * i, Runnable { Thread { ask(r) }.start() }) }
    }

    /** iOS heardHeld's wallHeard: «W» and its digits after the name's tag and the bio's tag of a fresh presence word. */
    fun heardPresence(ref: String, payload: String) {
        val n = payload.indexOf('N'); if (n < 0) return
        var j = n + 1
        while (j < payload.length && payload[j].isDigit()) j++
        if (j < payload.length && payload[j] == 'A') { j++; while (j < payload.length && payload[j].isDigit()) j++ }
        if (j >= payload.length || payload[j] != 'W') return
        val v = payload.substring(j + 1).takeWhile { it.isDigit() }
        if (v.isEmpty()) return
        val pg = synchronized(lock) { ensure(); pages[ref] }
        if (v == "0") {   // a build of 1923–1925: an empty wall and a refusal alike; a wall never held is asked (iOS heard)
            if (pg == null) ask(ref)
            else if ((pg.optJSONArray("ps")?.length() ?: 0) > 0) { synchronized(lock) { pg.put("ps", JSONArray()); save() }; changed() }
            return
        }
        if (pg?.optString("v") != v) ask(ref)
    }

    /** A word of a wall (iOS MTBoard.handle): receipted as a letter, and never a row. */
    fun handle(ref: String, sid: String, text: String) {
        Post.receiptFor(ref, sid)
        if (PeerSafety.isBlocked(ref)) return
        val w = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull() ?: return
        val t = w.optString("t")
        Log.d("Montana", "wall_rx t=" + t + " from=" + ref.take(10))
        val now = System.currentTimeMillis()
        when (t) {
            "page" -> {
                val src = w.optJSONArray("ps") ?: JSONArray()
                val ps = JSONArray()
                for (k in 0 until minOf(src.length(), PAGE_SIZE)) src.optJSONObject(k)?.let { ps.put(held(clean(it), now)) }
                val pg = JSONObject().put("w", w.optBoolean("w", false)).put("ps", ps).put("at", now)
                if (w.has("v")) pg.put("v", w.optString("v"))
                synchronized(lock) { ensure(); pages[ref] = pg; save() }
                Log.d("Montana", "wall_page posts=" + ps.length() + " from=" + ref.take(10))
                changed()
            }
            "no", "drop" -> w.optString("id").takeIf { it.isNotEmpty() }?.let { drop(ref, it) }
            "ask" -> {
                synchronized(lock) { if (now - (answeredAt[ref] ?: 0L) < 30_000L) return; answeredAt[ref] = now }
                send(ref, JSONObject().put("t", "page").put("w", false).put("ps", JSONArray()).put("v", emptyVersion))
            }
            else -> {}   // the owner's side (post, like, cmt, view…) comes with this phone's own wall
        }
    }

    private fun drop(ref: String, id: String) {
        synchronized(lock) {
            ensure()
            val pg = pages[ref] ?: return
            val ps = pg.optJSONArray("ps") ?: return
            val out = JSONArray()
            for (i in 0 until ps.length()) ps.optJSONObject(i)?.takeIf { it.optString("id") != id }?.let { out.put(it) }
            pg.put("ps", out); save()
        }
        changed()
    }

    /** A RECEIVED POST STANDS NO LATER THAN THE MOMENT THIS PHONE FIRST HELD IT (iOS held, 07.10): five minutes for the clocks. */
    private fun held(p: JSONObject, now: Long): JSONObject {
        val first = synchronized(lock) { firstSeen.getOrPut(p.optString("id")) { now } }
        p.put("at", minOf(p.optDouble("at", 0.0), first / 1000.0 + 300))
        return p
    }

    /** WHAT ARRIVES IS HELD TO ITS BOUNDS (iOS clean, the critic 24.09): a hostile page cannot fill the store. */
    private fun clean(p: JSONObject): JSONObject {
        val x = JSONObject().put("id", p.optString("id").take(64)).put("byName", p.optString("byName").take(64))
            .put("byGlyph", p.optString("byGlyph").take(8)).put("at", p.optDouble("at", 0.0))
            .put("text", p.optString("text").take(TEXT_LIMIT)).put("pinned", p.optBoolean("pinned"))
        for (k in listOf("keepers", "likes", "downloads", "reposts", "commentCount")) x.put(k, maxOf(0, p.optInt(k)))
        for (k in listOf("liked", "kept", "reposted", "mine", "own")) if (p.optBoolean(k)) x.put(k, true)
        if (p.has("views") && !p.isNull("views")) x.put("views", maxOf(0, p.optInt("views")))
        p.optString("from").takeIf { it.isNotEmpty() }?.let { x.put("from", it.take(64)) }
        p.optString("face").takeIf { it.isNotEmpty() && it.length <= FACE_LIMIT }?.let { x.put("face", it) }
        val md = JSONArray(); val ms = p.optJSONArray("media") ?: JSONArray()
        for (i in 0 until minOf(ms.length(), MEDIA_LIMIT)) ms.optJSONObject(i)?.let { m ->
            val y = JSONObject().put("kind", m.optString("kind")).put("name", m.optString("name").take(120))
                .put("ext", m.optString("ext").take(8).filter { it.isLetterOrDigit() }).put("size", m.optLong("size"))
                .put("key", m.optString("key")).put("chunks", m.optJSONArray("chunks") ?: JSONArray())
            m.optString("thumb").takeIf { i < 4 && it.isNotEmpty() && it.length <= THUMB_LIMIT }?.let { y.put("thumb", it) }
            if (m.has("dur")) y.put("dur", m.optDouble("dur"))
            m.optJSONObject("fr")?.let { y.put("fr", it) }
            md.put(y)
        }
        x.put("media", md)
        val cs = JSONArray(); val cm = p.optJSONArray("comments") ?: JSONArray()
        for (i in maxOf(0, cm.length() - COMMENTS_SHOWN) until cm.length()) cm.optJSONObject(i)?.let { c ->
            val y = JSONObject().put("id", c.optString("id")).put("by", c.optString("by").take(64)).put("glyph", c.optString("glyph").take(8))
                .put("text", c.optString("text").take(COMMENT_LIMIT)).put("at", c.optDouble("at", 0.0))
            c.optString("fc").takeIf { it.isNotEmpty() && it.length <= FACE_LIMIT }?.let { y.put("fc", it) }
            c.optString("h").takeIf { it.length == 64 }?.let { y.put("h", it) }
            c.optString("pv").takeIf { it.length == 64 }?.let { y.put("pv", it) }
            if (c.optBoolean("m")) y.put("m", true)
            if (c.optBoolean("o")) y.put("o", true)
            cs.put(y)
        }
        return x.put("comments", cs)
    }

    class Item(val wall: String, val post: JSONObject)
    /** THE FEED (iOS feed, the author's word 06.10 15:0x): every post of every wall held, each once, strictly by time, the newest on top. */
    fun feed(): List<Item> {
        val held = Book.refs().toSet()
        val all = synchronized(lock) {
            ensure()
            pages.entries.filter { it.key in held && !PeerSafety.isBlocked(it.key) }.flatMap { e ->
                val ps = e.value.optJSONArray("ps") ?: JSONArray()
                (0 until ps.length()).mapNotNull { ps.optJSONObject(it)?.let { p -> Item(e.key, p) } }
            }
        }
        val once = HashSet<String>()
        return all.filter { once.add(it.post.optString("id")) }
            .sortedWith(compareByDescending<Item> { it.post.optDouble("at") }.thenByDescending { it.post.optString("id") }).take(FEED_SIZE)
    }

    // ── the files of a post, brought for a look (iOS MTBoardLook) ──
    private val going = HashSet<String>()
    private fun lookDir() = File(Book.ctx.filesDir, "walllook").apply { mkdirs() }
    private fun fileName(pid: String, i: Int, ext: String) = "wall_" + pid + "_" + i + (if (ext.isEmpty()) "" else "." + ext)
    /** A picture of a post, brought from the node's pieces into the look's folder; the latest three hundred stay. */
    fun bring(m: JSONObject, pid: String, i: Int, then: (File) -> Unit) {
        val name = fileName(pid, i, m.optString("ext"))
        val dest = File(lookDir(), name)
        if (dest.exists()) { then(dest); return }
        val chunks = m.optJSONArray("chunks")
        if (m.optString("kind") != "img" || chunks == null || chunks.length() == 0) return
        synchronized(going) { if (!going.add(name)) return }
        Thread {
            try {
                if (Media.download(JSONObject().put("bk", m.optString("key")).put("chunks", chunks), dest)) {
                    Log.d("Montana", "wall_look id=" + pid.take(10) + " i=" + i + " bytes=" + dest.length())
                    lookDir().listFiles()?.sortedByDescending { it.lastModified() }?.drop(LOOK_KEEP)?.forEach { it.delete() }
                    MainThread.post { then(dest) }
                }
            } catch (e: Exception) { Log.w("Montana", "wall_look: " + e.javaClass.simpleName) }
            finally { synchronized(going) { going.remove(name) } }
        }.start()
    }

    // ── the visitor's marks (iOS like, view, comment) ──
    fun post(wall: String, id: String): JSONObject? = synchronized(lock) {
        ensure()
        val ps = pages[wall]?.optJSONArray("ps") ?: return null
        (0 until ps.length()).mapNotNull { ps.optJSONObject(it) }.firstOrNull { it.optString("id") == id }
    }
    fun canWrite(wall: String) = synchronized(lock) { ensure(); pages[wall]?.optBoolean("w") == true }
    private fun patch(wall: String, id: String, change: (JSONObject) -> Unit) {
        synchronized(lock) {
            ensure()
            val ps = pages[wall]?.optJSONArray("ps") ?: return
            for (i in 0 until ps.length()) ps.optJSONObject(i)?.takeIf { it.optString("id") == id }?.let(change)
            save()
        }
        changed()
    }

    /** A like given or taken back (iOS like): the word to the wall's owner and the page here at once; the owner's next page says it exact. */
    fun like(wall: String, p: JSONObject) {
        val on = !p.optBoolean("liked")
        val id = p.optString("id")
        if (!send(wall, JSONObject().put("t", "like").put("id", id).put("on", on))) return
        patch(wall, id) { s -> if (on) s.put("liked", true) else s.remove("liked"); s.put("likes", maxOf(0, s.optInt("likes") + (if (on) 1 else -1))) }
    }

    /**
     * THE POSTS I SAW ARE NAMED TO THEIR WALL, EACH ONCE (iOS view and tellSeen, the author's words 06.10 00:4x): a post drawn on the
     * screen joins its wall's list of the moment, and two seconds later the list leaves as one word. A wall whose page counts no
     * views is told nothing; the number shown is the owner's alone.
     */
    private val seenDue = HashMap<String, MutableList<String>>()
    private val viewed: MutableList<String> by lazy { Prefs.str("board.viewed", "").split('\n').filter { it.isNotEmpty() }.toMutableList() }
    fun view(wall: String, p: JSONObject) {
        if (p.optBoolean("mine") || !p.has("views")) return
        val id = p.optString("id")
        val first = synchronized(lock) {
            if ((wall + "#" + id) in viewed || seenDue[wall]?.contains(id) == true) return
            val due = seenDue.getOrPut(wall) { mutableListOf() }
            due.add(id); due.size == 1
        }
        if (first) MainThread.later(2000, Runnable { Thread { tellSeen(wall) }.start() })
    }
    private fun tellSeen(wall: String) {
        val ids = synchronized(lock) { seenDue.remove(wall) } ?: return
        if (ids.isEmpty() || !send(wall, JSONObject().put("t", "view").put("vs", JSONArray(ids)))) return
        synchronized(lock) {
            viewed.addAll(ids.map { wall + "#" + it })
            while (viewed.size > 4000) viewed.removeAt(0)
            Prefs.setStr("board.viewed", viewed.joinToString("\n"))
        }
    }

    /** iOS seal: SHA-256 of the comment's name, its moment in UTC to the millisecond, the seal before it and its words. */
    private const val ZERO_HASH = "0000000000000000000000000000000000000000000000000000000000000000"
    fun seal(id: String, at: Double, prev: String, text: String): String =
        Wire.hex(Wire.sha((id + "\n" + stamp(at) + "\n" + prev + "\n" + text).toByteArray(Charsets.UTF_8)))
    private fun moment(at: Double, zone: java.util.TimeZone, pattern: String): String {
        var sec = at.toLong()
        var ms = ((at - sec) * 1000 + 0.5).toInt()
        if (ms == 1000) { ms = 0; sec += 1 }
        if (ms < 0) ms = 0
        val f = java.text.SimpleDateFormat(pattern, java.util.Locale.US).apply { timeZone = zone }
        return f.format(java.util.Date(sec * 1000)) + "." + ms.toString().padStart(3, '0')
    }
    fun stamp(at: Double) = moment(at, java.util.TimeZone.getTimeZone("UTC"), "yyyy-MM-dd'T'HH:mm:ss") + "Z"
    /** A comment's number in its chain, its moment on this phone's clock, then the prime sum of its own seal (iOS numberLine 1296-1302). */
    fun numberLine(n: Int, at: Double, h: String): String {
        val line = n.toString() + " · " + moment(at, java.util.TimeZone.getDefault(), "dd.MM.yyyy HH:mm:ss")
        return if (h.isEmpty()) line else line + " · gematria " + gematria(h)
    }
    private val PRIMES = intArrayOf(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109)
    /** iOS gematria (MontanaBoard 1266-1290): the seal read as one number, divided by 29 again and again, the prime of every remainder summed. */
    fun gematria(hex: String): Int {
        var chars = hex.lowercase().toList()
        if (chars.isEmpty()) return PRIMES[0]
        var total = 0
        while (true) {
            var rem = 0
            val next = ArrayList<Char>()
            var started = false
            for (ch in chars) {
                val v = Character.digit(ch, 16)
                if (v == -1) return total
                val cur = rem * 16 + v
                val q = cur / 29
                rem = cur % 29
                if (q != 0 || started) { next.add(Character.forDigit(q, 16)); started = true }
            }
            total += PRIMES[rem]
            if (next.isEmpty()) break
            chars = next
        }
        return total
    }

    /** My small face for a comment, as the commenter sends it (iOS commentFace): a JPEG under the bound every build keeps. */
    private fun commentFace(): String? {
        val raw = SelfFace.bytes(Book.ctx) ?: return null
        val b = BitmapFactory.decodeByteArray(raw, 0, raw.size) ?: return null
        val side = 96
        val small = Bitmap.createScaledBitmap(b, side, maxOf(1, b.height * side / maxOf(1, b.width)), true)
        val out = java.io.ByteArrayOutputStream()
        small.compress(Bitmap.CompressFormat.JPEG, 70, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP).takeIf { it.length <= FACE_LIMIT }
    }

    /**
     * A COMMENT (iOS comment): sealed into the post's chain after the last seal this phone holds, sent to the wall's owner with
     * one coin when the book holds one (the author's words 04.10 02:50: four of five burn, the fifth to the post's writer), and
     * shown here at once as my own; the wall is asked again so the owner's page brings every comment.
     */
    fun comment(wall: String, p: JSONObject, text: String) {
        val t = text.trim().take(COMMENT_LIMIT)
        if (t.isEmpty()) return
        val id = p.optString("id")
        val name = Prefs.userName.trim()
        val glyph = name.take(1).uppercase()
        val at = System.currentTimeMillis() / 1000.0
        val cid = java.util.UUID.randomUUID().toString().uppercase()
        val prev = post(wall, id)?.optJSONArray("comments")?.let { cs -> cs.optJSONObject(cs.length() - 1)?.optString("h")?.takeIf { it.isNotEmpty() } } ?: ZERO_HASH
        val h = seal(cid, at, prev, t)
        val face = commentFace()
        val r = java.util.UUID.randomUUID().toString().uppercase()
        val paid = CoinBook.spend(1L, "post:" + id, wall, "cmt:" + r)
        val w = JSONObject().put("t", "cmt").put("id", id).put("at", at).put("tx", t).put("bn", name).put("bg", glyph)
            .put("cid", cid).put("hh", h).put("pv", prev)
        if (face != null) w.put("fc", face)
        if (paid) w.put("c", 1).put("r", r)
        if (!send(wall, w)) return
        synchronized(lock) { askedAt[wall] = System.currentTimeMillis() }
        send(wall, JSONObject().put("t", "ask"))   // iOS askAfterAct: the owner answers with the page as it stands
        val said = JSONObject().put("id", cid).put("by", name).put("glyph", glyph).put("text", t).put("at", at).put("m", true).put("h", h).put("pv", prev)
        if (face != null) said.put("fc", face)
        patch(wall, id) { s -> (s.optJSONArray("comments") ?: JSONArray().also { s.put("comments", it) }).put(said); s.put("commentCount", s.optInt("commentCount") + 1) }
    }

    fun nameOf(c: Context, ref: String) = Book.chat(ref)?.name?.takeIf { it.isNotBlank() } ?: c.getString(R.string.wall_someone)
}

/** A picture of a post: its width the post's, its height by the frame's shape (iOS MTBoardFrame.held: 9:16 up to 16:9). */
private class WallTile(c: Context, private val shape: Float) : ImageView(c) {
    override fun onMeasure(w: Int, h: Int) {
        val wd = MeasureSpec.getSize(w)
        setMeasuredDimension(wd, (wd / shape.coerceIn(9f / 16f, 16f / 9f)).toInt())
    }
}

private fun poster(b64: String?): Bitmap? = b64?.takeIf { it.isNotEmpty() }?.let {
    runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull()?.let { d -> BitmapFactory.decodeByteArray(d, 0, d.size) }
}

/** ONE POST OF THE FEED (iOS MTBoardCell in MTFeedTabView): whose wall, the writer, the words, the pictures, the counts. */
private fun postCell(act: MainActivity, it: Board.Item, whole: Boolean = false): View = act.vstack(Gravity.NO_GRAVITY) {
    val c: Context = act
    val openComments = { act.push { close -> wallCommentsPage(act, it.wall, it.post.optString("id"), close) } }
    val p = it.post
    val own = p.optBoolean("own")
    // WHOSE WALL A POST STANDS ON, when its writer is not the wall's owner (iOS wallLink)
    if (!own) addView(c.text(c.getString(R.string.wall_on, Board.nameOf(c, it.wall)), 12f, MT.gray).apply { setPadding(dp(4), 0, 0, dp(6)) }, lp())
    addView(c.vstack(Gravity.NO_GRAVITY) {
        background = c.rounded(MT.plate, 16)
        setPadding(dp(12), dp(12), dp(12), dp(12))
        val name = p.optString("byName").ifEmpty { c.getString(R.string.wall_someone) }
        val face = if (own) Book.face(it.wall).takeIf { f -> f.exists() }?.let { f -> BitmapFactory.decodeFile(f.path) } else poster(p.optString("face"))
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(c.avatar(face, name, 40), lp(dp(40), dp(40)))
            gap(10)
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(name, 15f, android.graphics.Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())
                val at = (p.optDouble("at") * 1000).toLong()
                addView(c.text(android.text.format.DateUtils.getRelativeTimeSpanString(at, System.currentTimeMillis(), 60_000L), 12f, MT.gray), lp())
            }, lp(0, WRAP, 1f))
        }, lp())
        p.optString("from").takeIf { f -> f.isNotEmpty() }?.let { f ->
            gap(8); addView(c.text(c.getString(R.string.wall_reposted, f), 12f, MT.gray), lp())
        }
        val words = p.optString("text")
        if (words.isNotEmpty()) { gap(10); addView(c.text(words, 16f).apply { setTextIsSelectable(false) }, lp()) }
        val media = p.optJSONArray("media") ?: JSONArray()
        for (i in 0 until media.length()) {
            val m = media.optJSONObject(i) ?: continue
            val kind = m.optString("kind")
            if (kind != "img" && kind != "vid") continue
            val small = poster(m.optString("thumb"))
            val fr = m.optJSONObject("fr")
            val shape = fr?.optDouble("a", 0.0)?.toFloat()?.takeIf { s -> s > 0f } ?: small?.let { b -> b.width.toFloat() / maxOf(1, b.height) } ?: 1f
            gap(10)
            val tile = WallTile(c, shape).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                background = c.rounded(MT.hairline, 12)
                outlineProvider = ViewOutlineProvider.BACKGROUND
                clipToOutline = true
                small?.let { b -> setImageBitmap(b) }
            }
            addView(tile, lp())
            Board.bring(m, p.optString("id"), i) { f -> Thread { Media.preview(c, f, "img", 1600)?.let { b -> MainThread.post { tile.setImageBitmap(b) } } }.start() }
        }
        // THE COUNTS (iOS counters 445-487): like, comments, keepers, reposts; in the corner the downloads and the eye with the views
        // where the wall's owner counts them. Keeping and reposting come with this phone's own wall (W3): their counts stand.
        gap(4)
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            fun mark(glyph: Int, n: Int, tint: Int, words: Int, onTap: (() -> Unit)?) = addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                contentDescription = c.getString(words)
                addView(c.icon(glyph, tint, 18)); gap(4)
                addView(c.text(n.toString(), 13f, MT.gray, bold = true))
                if (onTap != null) pressable(onTap)
            }, lp(WRAP, dp(44)).apply { marginEnd = dp(14) })
            val liked = p.optBoolean("liked")
            mark(if (liked) R.drawable.ic_heart_fill else R.drawable.ic_heart, p.optInt("likes"), if (liked) MT.red else MT.gray, R.string.wall_like) { Board.like(it.wall, p) }
            mark(R.drawable.ic_set_textbubble, p.optInt("commentCount"), MT.gray, R.string.wall_comments, if (whole) null else openComments)
            mark(R.drawable.ic_tray_down, p.optInt("keepers"), if (p.optBoolean("kept")) android.graphics.Color.WHITE else MT.gray, R.string.wall_keepers, null)
            mark(R.drawable.ic_repost, p.optInt("reposts"), if (p.optBoolean("reposted")) android.graphics.Color.WHITE else MT.gray, R.string.wall_repost, null)
            spacer()
            addView(c.icon(R.drawable.ic_arrow_circle_down, MT.gray, 16).apply { contentDescription = c.getString(R.string.wall_downloads) }); gap(4)
            addView(c.text(p.optInt("downloads").toString(), 13f, MT.gray, bold = true))
            if (p.has("views")) {
                gap(12)
                addView(c.icon(R.drawable.ic_set_eye, MT.gray, 16).apply { contentDescription = c.getString(R.string.wall_views) }); gap(4)
                addView(c.text(p.optInt("views").toString(), 13f, MT.gray, bold = true))
            }
        }, lp())
        if (!whole) pressable(openComments)
    }, lp())
    // A POST ON THE SCREEN IS A POST SEEN (iOS MTBoardCell.onAppear, 06.10): its wall is told once
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Board.view(it.wall, it.post) }
        override fun onViewDetachedFromWindow(v: View) {}
    })
}

/**
 * THE COMMENTS OF A POST (iOS MTBoardComments 2246-2440): the post whole on top, its chain newest first, each comment under its
 * writer's head with its number in the chain and its moment; the field below for one who may write on the wall, else the words
 * that say who may.
 */
fun wallCommentsPage(act: MainActivity, wall: String, id: String, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(12), 0, dp(12), dp(16)) }
    fun draw() {
        body.removeAllViews()
        val p = Board.post(wall, id) ?: return
        body.addView(postCell(act, Board.Item(wall, p), whole = true), lp().apply { setMargins(0, c.dp(6), 0, c.dp(10)) })
        val cs = p.optJSONArray("comments") ?: JSONArray()
        if (cs.length() == 0) { body.addView(c.text(c.getString(R.string.wall_no_comments), 15f, MT.gray), lp()); return }
        val base = p.optInt("commentCount") - cs.length()
        for (i in cs.length() - 1 downTo 0) {
            val k = cs.optJSONObject(i) ?: continue
            val name = k.optString("by").ifEmpty { c.getString(R.string.wall_someone) }
            val face = when {
                k.optBoolean("m") -> SelfFace.bytes(c)?.let { b -> BitmapFactory.decodeByteArray(b, 0, b.size) }
                k.optBoolean("o") -> Book.face(wall).takeIf { f -> f.exists() }?.let { f -> BitmapFactory.decodeFile(f.path) }
                else -> null
            } ?: poster(k.optString("fc"))
            body.addView(c.vstack(Gravity.NO_GRAVITY) {
                setPadding(0, dp(10), 0, dp(6))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.avatar(face, name, 36), lp(dp(36), dp(36))); gap(10)
                    addView(c.text(name, 15f, android.graphics.Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
                }, lp())
                val words = k.optString("text")
                if (words.isNotEmpty()) addView(c.text(words, 16f).apply { setPadding(dp(46), dp(2), 0, 0) }, lp())
                addView(c.text(Board.numberLine(base + i + 1, k.optDouble("at"), k.optString("h")), 11f, MT.gray).apply { setPadding(dp(46), dp(2), 0, 0) }, lp())
            }, lp())
        }
    }
    val field = android.widget.EditText(c).apply {
        hint = c.getString(R.string.wall_write_comment); setTextColor(android.graphics.Color.WHITE); setHintTextColor(MT.gray)
        background = c.rounded(android.graphics.Color.rgb(38, 38, 38), 18); setPadding(dp(12), dp(10), dp(12), dp(10)); maxLines = 5
    }
    val foot: View = if (Board.canWrite(wall)) c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(8))
        addView(field, lp(0, WRAP, 1f)); gap(8)
        addView(c.icon(R.drawable.ic_arrow_circle_up, android.graphics.Color.WHITE, 30).apply {
            contentDescription = c.getString(R.string.wall_send)
            pressable {
                val p = Board.post(wall, id) ?: return@pressable
                Thread { Board.comment(wall, p, field.text.toString()) }.start()
                field.setText("")
            }
        }, lp(dp(44), dp(44)))
    } else c.text(c.getString(R.string.wall_only_writers), 13f, MT.gray, center = true).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) }
    val bar = FrameLayout(c).apply {
        addView(c.icon(R.drawable.ic_close, android.graphics.Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onClose) },
            FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.START).apply { marginStart = c.dp(8) })
        addView(c.text(c.getString(R.string.wall_comments), 17f, android.graphics.Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
    }
    val again: () -> Unit = { draw() }
    return FrameLayout(c).apply {
        setBackgroundColor(android.graphics.Color.BLACK)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f))
            addView(foot, lp())
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { Board.listen(again); draw() }
            override fun onViewDetachedFromWindow(v: View) { Board.unlisten(again) }
        })
    }
}

/**
 * THE FEED under the logo (iOS MTFeedTabView): every post on my people's walls this phone holds, the newest on top; «Posts on your
 * people's walls will appear here» while there is none. The moment the page is looked at, every wall it draws is asked for (iOS
 * mtPaneLive, lookFeed).
 */
class FeedPane(private val act: MainActivity) : FrameLayout(act) {
    private val c: Context = act
    private val column = c.vstack(Gravity.NO_GRAVITY)
    private val empty = c.text(c.getString(R.string.no_posts), 17f, MT.gray, center = true)
    private val again: () -> Unit = { if (isShown) draw() }
    init {
        addView(ScrollView(c).apply {
            isVerticalScrollBarEnabled = false
            addView(c.vstack(Gravity.NO_GRAVITY) { addView(column, lp()); gap(120) })
        }, LayoutParams(MATCH, MATCH))
        addView(empty, LayoutParams(WRAP, WRAP, Gravity.CENTER))
    }
    private fun draw() {
        val items = Board.feed()
        column.removeAllViews()
        for (it in items) column.addView(postCell(act, it), lp().apply { setMargins(dp(12), dp(6), dp(12), dp(6)) })
        empty.visibility = if (items.isEmpty()) View.VISIBLE else View.GONE
    }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); Board.listen(again); draw() }
    override fun onDetachedFromWindow() { Board.unlisten(again); super.onDetachedFromWindow() }
    override fun onVisibilityChanged(v: View, visibility: Int) {
        super.onVisibilityChanged(v, visibility)
        if (visibility == View.VISIBLE && isAttachedToWindow) { Board.lookFeed(); draw() }
    }
}
