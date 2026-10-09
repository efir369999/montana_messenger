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
    private const val LOOK_BUDGET = 1_000_000_000L   // iOS MTBoardLook.budget: a gigabyte (MontanaBoard.swift:2414 at 2155)
    private const val LOOK_KEEP = 300           // iOS MTBoardLook.keep

    private val lock = Any()
    private var loaded = false
    private val pages = HashMap<String, JSONObject>()     // a wall's owner -> {w, ps, at, v}, as the owner last sent it
    private val firstSeen = HashMap<String, Long>()       // a post -> the moment this phone first held it (iOS held)
    private val askedAt = HashMap<String, Long>()
    private val answeredAt = HashMap<String, Long>()
    private val kept = HashMap<String, JSONObject>()      // a post -> {post, wall, files, dl}: its files kept here (iOS MTBoardKept 224-229)
    private val keeping = HashSet<String>()               // a Save on its way, once per post
    private val countedDownload = HashSet<String>()       // a download counted in this run (iOS countedDownload 375)
    private val goneSaid = HashSet<String>()              // a post whose lost files were said once in this run (iOS goneSaid 374)
    private val fetching = HashSet<String>()              // a post whose file comes from the node now (iOS fetching 366)
    private val reposting = HashMap<String, JSONObject>() // a repost on its way: {wall, post, sizes, brought, failed} (iOS reposting 368)

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun store() = File(File(Book.ctx.filesDir, "board").apply { mkdirs() }, "pages.json")
    /** The person forgotten: the walls this phone held and the files brought for a look leave with them (Book.wipe). */
    fun wipe() = synchronized(lock) {
        MyWall.wipe()
        pages.clear(); firstSeen.clear(); askedAt.clear(); answeredAt.clear(); kept.clear(); keeping.clear(); countedDownload.clear(); goneSaid.clear(); fetching.clear(); reposting.clear(); loaded = false
        File(Book.ctx.filesDir, "board").deleteRecursively(); lookDir().deleteRecursively()
    }
    private fun ensure() {
        if (loaded) return
        loaded = true
        val o = runCatching { JSONObject(store().readText()) }.getOrNull() ?: return
        o.optJSONObject("pages")?.let { p -> p.keys().forEach { k -> p.optJSONObject(k)?.let { pages[k] = it } } }
        o.optJSONObject("first")?.let { f -> f.keys().forEach { k -> firstSeen[k] = f.optLong(k) } }
        o.optJSONObject("kept")?.let { k -> k.keys().forEach { id -> k.optJSONObject(id)?.let { kept[id] = it } } }
    }
    private fun save() {
        val p = JSONObject(); for ((k, v) in pages) p.put(k, v)
        val f = JSONObject(); firstSeen.entries.sortedByDescending { it.value }.take(FIRST_KEPT).forEach { f.put(it.key, it.value) }
        val k = JSONObject(); for ((id, v) in kept) k.put(id, v)
        val part = File(store().path + ".part")
        runCatching { part.writeText(JSONObject().put("pages", p).put("first", f).put("kept", k).toString()); part.renameTo(store()) }
    }

    /** iOS Announced.wireTag: the first four bytes of SHA-256 as a decimal number; nothing is «0». */
    fun wireTag(d: ByteArray?): String {
        if (d == null || d.isEmpty()) return "0"
        val h = Wire.sha(d)
        fun b(i: Int) = h[i].toLong() and 0xff
        return ((b(0) shl 24) or (b(1) shl 16) or (b(2) shl 8) or b(3)).toString()
    }
    private fun send(ref: String, w: JSONObject): Boolean = sendWord(ref, w) != null
    /** A word of the wall to a correspondent: the letter's name, by which its receipt is known (the page's «sent» is written by it). */
    fun sendWord(ref: String, w: JSONObject): String? {
        if (Groups.isKey(ref) || PeerSafety.isBlocked(ref) || Book.secret(ref) == null) return null
        val mid = Marks.mintMid()
        Post.send(ref, mid, MARK + w.toString())
        Log.d("Montana", "wall_tx t=" + w.optString("t") + " to=" + ref.take(10))
        return mid
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
    /**
     * EVERY WALL NEVER SEEN IS ASKED AT ONCE (iOS sweep, MontanaBoard.swift:591-602 at 2155; ContentView.swift:474): at every return of
     * the app, every correspondent whose build speaks the wall and whose page never came from its owner -- a page of one post of mine
     * stood for the wall for ever -- is asked, a third of a second apart.
     */
    fun sweep() {
        val speakers = MyWall.speakers()
        val unknown = synchronized(lock) { ensure(); speakers.filter { r -> pages[r]?.has("v") != true } }.filter { Book.secret(it) != null }
        unknown.forEachIndexed { n, r -> MainThread.later(300L * n, Runnable { Thread { ask(r) }.start() }) }
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
        MyWall.learnCap(ref)   // a word of the wall is the proof its build speaks it (iOS apply 812)
        val now = System.currentTimeMillis()
        when (t) {
            "page" -> {
                val src = w.optJSONArray("ps") ?: JSONArray()
                val fresh = (0 until minOf(src.length(), PAGE_SIZE)).mapNotNull { k -> src.optJSONObject(k)?.let { held(clean(it), now) } }
                // MY WORDS STAY ON MY SCREEN UNTIL THE OWNER'S PAGE CARRIES THEM (iOS keepMine, MontanaBoard.swift:984-999,
                // the author's word 25.09): a page fetched before the owner's own build echoes my latest act does not
                // take my own words off my own screen -- the owner's next page carries them for good.
                val oldPs = synchronized(lock) { ensure(); pages[ref]?.optJSONArray("ps") }
                val ps = JSONArray(); keepMine(oldPs, fresh, now).forEach { ps.put(it) }
                val pg = JSONObject().put("w", w.optBoolean("w", false)).put("ps", ps).put("at", now)
                if (w.has("v")) pg.put("v", w.optString("v"))
                synchronized(lock) { pages[ref] = pg; save() }
                Log.d("Montana", "wall_page posts=" + ps.length() + " from=" + ref.take(10))
                changed()
            }
            "no", "drop" -> w.optString("id").takeIf { it.isNotEmpty() }?.let { id ->
                drop(ref, id)
                if (t == "no") dropCardRow(ref, id)   // the owner said no: the post's row leaves the chat (iOS apply «no», MontanaBoard.swift:841)
            }
            "ask" -> MyWall.answer(ref)
            // THE OWNER ASKS THIS KEEPER TO LAY A POST'S FILES AGAIN (iOS apply «seed» 964-966): a post whose files this phone keeps
            "seed" -> w.optString("id").takeIf { it.isNotEmpty() }?.let { seedKept(it) }
            else -> MyWall.heard(ref, w)   // the owner's side: a post, a mark, a comment, a view on my wall
        }
    }

    private fun drop(ref: String, id: String) {
        forgetKept(id)   // iOS apply «no» 840, «drop» 891: a post off its wall is kept here no more
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
        // THE POST'S NUMBER ON ITS WALL STAYS WITH IT (iOS clean bounds the rest and keeps it, MontanaBoard.swift:1037-1054 at 2155): the
        // short link names a post by it (linkPost)
        if (p.has("n")) x.put("n", maxOf(0, p.optInt("n")))
        p.optString("face").takeIf { it.isNotEmpty() && it.length <= FACE_LIMIT }?.let { x.put("face", it) }
        // THE LINK CARD RIDES WITH A VISITOR'S OWN PAGE READ TOO (iOS clean carries every field of MTBoardSeen by decoding it, atom
        // 5a84afb1f68f): the same bound as a post's own arrival (MyWall.takePost 318).
        p.optString("lp").takeIf { 2 < it.length && it.toByteArray().size < 80_001 }?.let { x.put("lp", it) }
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

    /** MY WORDS STAY ON MY SCREEN UNTIL THE OWNER'S PAGE CARRIES THEM (iOS keepMine, MontanaBoard.swift:984-999, the
     * author's word 25.09): a page fetched before the owner's own build echoes my latest act does not take my own words
     * off my own screen. My comments not yet on the owner's page stay as I sent them for half an hour, in the order
     * written; my own post not yet on the owner's page stays too, before the first post that is not pinned. */
    private fun keepMine(oldPs: JSONArray?, fresh: List<JSONObject>, now: Long): List<JSONObject> {
        if (oldPs == null || oldPs.length() == 0) return fresh
        val since = now / 1000.0 - 1800.0
        val out = fresh.toMutableList()
        for (i in 0 until oldPs.length()) {
            val o = oldPs.optJSONObject(i) ?: continue
            val idx = out.indexOfFirst { it.optString("id") == o.optString("id") }
            if (idx >= 0) {
                val dst = out[idx]
                val haveComments = dst.optJSONArray("comments") ?: JSONArray()
                val have = (0 until haveComments.length()).mapNotNull { haveComments.optJSONObject(it)?.optString("id") }.toSet()
                val oldComments = o.optJSONArray("comments") ?: JSONArray()
                val mine = (0 until oldComments.length()).mapNotNull { oldComments.optJSONObject(it) }
                    .filter { it.optBoolean("m") && it.optString("id") !in have && since < it.optDouble("at") }
                if (mine.isNotEmpty()) {
                    val all = ((0 until haveComments.length()).mapNotNull { haveComments.optJSONObject(it) } + mine).sortedBy { it.optDouble("at") }
                    dst.put("comments", JSONArray(all)).put("commentCount", dst.optInt("commentCount") + mine.size)
                }
            } else if (o.optBoolean("mine") && since < o.optDouble("at")) {
                val before = out.indexOfFirst { !it.optBoolean("pinned") }
                out.add(if (before == -1) out.size else before, o)
            }
        }
        return out
    }

    class Item(val wall: String, val post: JSONObject)
    /** THE FEED (iOS feed, the author's word 06.10 15:0x): every post of every wall held, each once, strictly by time, the newest on top. */
    fun feed(): List<Item> {
        val held = Book.refs().toSet()
        val own = MyWall.posts().map { Item("", it) }   // my own wall stands in the feed as every other (iOS feed 732)
        val all = own + synchronized(lock) {
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
    private fun lookDir() = lookIn(Book.ctx).apply { mkdirs() }
    /** The look's folder, for the app's own door to a post's file (MediaProvider): a picture brought for a look goes out from here. */
    fun lookIn(c: Context) = File(c.filesDir, "walllook")
    private fun fileName(pid: String, i: Int, ext: String) = "wall_" + pid + "_" + i + (if (ext.isEmpty()) "" else "." + ext)
    /** A picture of a post, brought from the node's pieces into the look's folder; the latest three hundred stay. */
    fun bring(m: JSONObject, pid: String, i: Int, then: (File) -> Unit) {
        val name = fileName(pid, i, m.optString("ext"))
        MyWall.ownFile(name)?.let { then(it); return }   // a post of mine, or one kept here: this phone is its peer, nothing to bring
        val dest = File(lookDir(), name)
        if (dest.exists()) { then(dest); return }
        val chunks = m.optJSONArray("chunks")
        if (m.optString("kind") != "img" || chunks == null || chunks.length() == 0) return
        synchronized(going) { if (!going.add(name)) return }
        Thread {
            try {
                if (Media.download(JSONObject().put("bk", m.optString("key")).put("chunks", chunks), dest)) {
                    Log.d("Montana", "wall_look id=" + pid.take(10) + " i=" + i + " bytes=" + dest.length())
                    trimLook()
                    MainThread.post { then(dest) }
                }
            } catch (e: Exception) { Log.w("Montana", "wall_look: " + e.javaClass.simpleName) }
            finally { synchronized(going) { going.remove(name) } }
        }.start()
    }
    /** THE FOLDER KEEPS THE LATEST SEEN, BY COUNT AND BY THE DISK THEY TAKE (iOS MTBoardLook.trim, MontanaBoard.swift:2480-2494 at
     * 2155): a gigabyte and three hundred files at most; the oldest go first. */
    private fun trimLook() {
        val all = lookDir().listFiles()?.sortedBy { it.lastModified() } ?: return
        var total = all.sumOf { it.length() }
        var count = all.size
        for (f in all) {
            if (count <= LOOK_KEEP && total <= LOOK_BUDGET) break
            total -= f.length(); count--
            f.delete()
        }
    }

    // ── the keepers of a post (iOS keep, becomePeer, unkeep, file, noteDownloaded, reportGone, seedFiles, MontanaBoard 1585-1762) ──
    /**
     * SAVE (iOS keep 1585-1597, the author's word 24.09): the files come to this phone and stay -- from now on this phone is one of
     * the post's peers. True when every file of the post is here; one Save of a post at a time. progress hears, file by file, the
     * pieces this phone holds of it (iOS keep's progress, 1586-1593): the repost's bar reads it.
     */
    fun keep(wall: String, p: JSONObject, progress: ((Int, Int) -> Unit)? = null): Boolean {
        val id = p.optString("id")
        if (!plain(id)) return false
        synchronized(lock) { if (!keeping.add(id)) return false }
        try {
            val ms = p.optJSONArray("media") ?: JSONArray()
            for (i in 0 until ms.length()) {
                if (file(wall, p, i) == null) return false
                // this road brings a file whole, never piece by piece: its pieces are told once it lies here (iOS file 1689, 1696)
                progress?.invoke(i, ms.optJSONObject(i)?.optJSONArray("chunks")?.length() ?: 0)
            }
            becomePeer(wall, p)   // a post with no files, or its files already here
            return true
        } finally { synchronized(lock) { keeping.remove(id) } }
    }
    /**
     * THE FILE OF A POST ON THIS PHONE (iOS file 1685-1721): kept under its wall name in the one store of the wall's files. The copy
     * a look brought is taken in -- what was seen is not brought again -- else the node's pieces are fetched. A file come here makes
     * this phone the post's peer; pieces gone at every door (iOS fetchChunks .lost, MontanaWakePush 2532-2538) are said to the owner.
     */
    fun file(wall: String, p: JSONObject, i: Int): File? {
        val m = p.optJSONArray("media")?.optJSONObject(i) ?: return null
        val id = p.optString("id")
        if (!plain(id)) return null
        val dest = MyWall.storeFile(fileName(id, i, m.optString("ext")))
        if (dest.exists()) return dest
        val seen = File(lookDir(), dest.name)
        val part = File(dest.path + ".part")
        val taken = seen.exists() && runCatching { seen.copyTo(part, overwrite = true) }.isSuccess && part.renameTo(dest)
        if (!taken) {
            val chunks = m.optJSONArray("chunks") ?: JSONArray()
            if (chunks.length() == 0) return null
            // THE FILE ON ITS WAY HERE SAYS SO (iOS fetching, MontanaBoard.swift:1704-1705 at 2155): the post's rows wear the wheel
            synchronized(lock) { fetching.add(id) }
            changed()
            try {
                if (!Media.download(JSONObject().put("bk", m.optString("key")).put("chunks", chunks), dest)) {
                    if ((0 until chunks.length()).any { k -> Wire.isGone(chunks.optJSONObject(k)?.optString("bid") ?: "") }) reportGone(wall, id)
                    return null
                }
            } finally {
                synchronized(lock) { fetching.remove(id) }
                changed()
            }
        }
        becomePeer(wall, p)
        noteDownloaded(wall, p)
        return dest
    }
    /**
     * A FILE FETCHED MAKES THIS PHONE THE POST'S PEER (iOS becomePeer 1598-1623, the author's word 24.09): what it holds of the post
     * stays, and the wall's owner is told it keeps the post. The writer keeps theirs from the start.
     */
    private fun becomePeer(wall: String, p: JSONObject) {
        val id = p.optString("id")
        val ms = p.optJSONArray("media") ?: JSONArray()
        val here = (0 until ms.length()).map { fileName(id, it, ms.optJSONObject(it)?.optString("ext") ?: "") }.filter { MyWall.storeFile(it).exists() }
        if (wall.isEmpty()) { MyWall.ownMark(id, "keepers", true); return }
        val tell = synchronized(lock) {
            ensure()
            val k = kept[id]
            if (k != null) {
                val had = k.optJSONArray("files") ?: JSONArray()
                val was = (0 until had.length()).map { had.optString(it) }.sorted()
                val all = (was + here).toSortedSet().toList()
                if (all == was) return
                k.put("files", JSONArray(all)); save()
                false
            } else {
                kept[id] = JSONObject().put("post", JSONObject(p.toString()).put("kept", true)).put("wall", wall).put("files", JSONArray(here))
                save()
                !p.optBoolean("mine")
            }
        }
        if (!tell) return
        send(wall, JSONObject().put("t", "keep").put("id", id).put("on", true))
        patch(wall, id) { x -> if (!x.optBoolean("kept")) { x.put("kept", true); x.put("keepers", x.optInt("keepers") + 1) } }
    }
    /** REMOVE FROM SAVED (iOS unkeep 1624-1630): the writer keeps their post while it stands; only the wall's owner takes it down. */
    fun unkeep(wall: String, p: JSONObject) {
        val id = p.optString("id")
        if (wall.isEmpty()) { MyWall.ownMark(id, "keepers", false); return }
        if (p.optBoolean("mine")) return
        forgetKept(id)
        send(wall, JSONObject().put("t", "keep").put("id", id).put("on", false))
        patch(wall, id) { x -> if (x.optBoolean("kept")) { x.remove("kept"); x.put("keepers", maxOf(0, x.optInt("keepers") - 1)) } }
    }
    /**
     * A POST NO LONGER KEPT HERE (iOS forgetKept 1667-1671): its files stay while my own wall still shows the post; else they go at
     * once -- iOS leaves them to the sweep of the files no post names (allFiles 509-521), and this phone has no such sweep.
     */
    private fun forgetKept(id: String) {
        val k = synchronized(lock) { ensure(); kept.remove(id)?.also { save() } } ?: return
        if (MyWall.post(id) != null) return
        val fs = k.optJSONArray("files") ?: return
        for (i in 0 until fs.length()) fs.optString(i).takeIf { it.isNotEmpty() }?.let { MyWall.storeFile(it).delete() }
    }

    // ── a repost (iOS repost, brought, letRepostGo, MontanaBoard.swift:1631-1666, 1910-1917 at 2155) ──
    /**
     * REPOST (iOS repost 1631-1666, the author's word 25.09: «pressing repost shows the same progress bar as a post's publishing»): the
     * post is kept here -- its files come under the bar a post goes out under -- and stands on my own wall too, named by the wall it came
     * from, its writer by reference where it was that wall's owner's own; the wall's owner is told. Files that did not all come say so,
     * with a try again. The repost wears the face its post carried, else -- the owner's own post -- the face this phone holds for them.
     */
    fun repost(wall: String, p: JSONObject) {
        val id = p.optString("id")
        if (wall.isEmpty() || !plain(id)) return
        val ms = p.optJSONArray("media") ?: JSONArray()
        val sizes = JSONArray()
        val got = JSONArray()
        for (i in 0 until ms.length()) { sizes.put(maxOf(0L, ms.optJSONObject(i)?.optLong("size") ?: 0L)); got.put(0) }
        synchronized(lock) {
            val r = reposting[id]
            if (r != null && !r.optBoolean("failed")) return   // already on its way
            reposting[id] = JSONObject().put("wall", wall).put("post", p).put("sizes", sizes).put("brought", got).put("failed", false)
        }
        changed()
        val whole = keep(wall, p) { i, n -> brought(id, i, n) }
        val ownersOwn = p.optBoolean("own")
        val worn = p.optString("face").ifEmpty { null } ?: if (ownersOwn) small(Book.face(wall).takeIf { f -> f.exists() }?.readBytes(), 96) else null
        Log.d("Montana", "wall_repost id=" + id.take(10) + " files=" + ms.length() + " whole=" + (if (whole) 1 else 0))
        if (!whole) { synchronized(lock) { reposting[id]?.put("failed", true) }; changed(); return }
        synchronized(lock) { reposting.remove(id) }
        val post = JSONObject().put("id", id).put("author", "").put("byName", p.optString("byName")).put("byGlyph", p.optString("byGlyph"))
            .put("at", System.currentTimeMillis() / 1000.0).put("text", p.optString("text")).put("media", JSONArray(ms.toString()))
            .put("pinned", false).put("keepers", JSONArray().put("")).put("likes", JSONArray()).put("downloads", JSONArray())
            .put("reposts", JSONArray()).put("comments", JSONArray()).put("from", publicName(wall)).put("src", wall)
        worn?.let { post.put("face", it) }
        if (ownersOwn) post.put("srcBy", wall) else if (p.optBoolean("mine")) post.put("srcBy", "")   // "" -- I wrote it
        p.optString("lp").takeIf { it.isNotEmpty() }?.let { post.put("lp", it) }
        if (MyWall.repost(post)) {
            send(wall, JSONObject().put("t", "rp").put("id", id))
            patch(wall, id) { x -> if (!x.optBoolean("reposted")) { x.put("reposted", true); x.put("reposts", x.optInt("reposts") + 1) } }
        }
        changed()
    }
    /** A repost on its way as its bar reads it (iOS MTRepostBar 2808, MTBoardOutgoing.done): null -- none for this post on this wall. */
    fun repostGoing(wall: String, id: String): MyWall.Going? {
        return synchronized(lock) {
            val r = reposting[id]?.takeIf { it.optString("wall") == wall } ?: return null
            val sizes = r.optJSONArray("sizes") ?: JSONArray()
            val got = r.optJSONArray("brought") ?: JSONArray()
            var total = 0L
            var done = 0L
            for (i in 0 until sizes.length()) { val s = sizes.optLong(i); total += s; done += minOf(s, got.optLong(i) * Media.CHUNK) }
            MyWall.Going(id, r.optJSONObject("post") ?: JSONObject(), total, done, r.optBoolean("failed"), wall)
        }
    }
    /** A piece more of a repost's file came to this phone (iOS brought 1911-1915). */
    private fun brought(id: String, i: Int, n: Int) {
        synchronized(lock) {
            val b = reposting[id]?.optJSONArray("brought") ?: return
            if (b.length() <= i || n <= b.optInt(i)) return
            b.put(i, n)
        }
        changed()
    }
    /** A repost whose files did not all come, let go by its person (iOS letRepostGo 1917). */
    fun letRepostGo(id: String) {
        synchronized(lock) { reposting.remove(id) }
        changed()
    }
    /** The name a wall goes by where others read it (iOS publicName(of:), MontanaBoard.swift:711-715 at 2155): the name its owner gave
     * themselves -- never the one this phone set for them --, else «Someone». */
    private fun publicName(wall: String): String =
        Book.chat(wall)?.name?.trim()?.takeIf { it.isNotEmpty() }?.take(64) ?: Book.ctx.getString(R.string.wall_someone)

    /**
     * MY POST ON ANOTHER'S WALL LEAVES (iOS lay, MontanaBoard.swift:1873-1897 at 2155): this phone keeps its files -- the post's first
     * peer --, the word «post» goes to the wall's owner, the owner is asked for the page as it now stands (iOS askAfterAct 1144-1150),
     * and the post stands on their page here at once, before the first that is not pinned. The pair's chat row is born as the post leaves
     * (ChatStore.appendWallPost, 1890-1892): the post stands in the chat of the two whose wall and chat it is (cardRow).
     */
    fun wrote(wall: String, s: JSONObject, word: JSONObject) {
        val id = s.optString("id")
        val ms = s.optJSONArray("media") ?: JSONArray()
        val files = JSONArray()
        for (i in 0 until ms.length()) files.put(fileName(id, i, ms.optJSONObject(i)?.optString("ext") ?: ""))
        synchronized(lock) {
            ensure()
            kept[id] = JSONObject().put("post", JSONObject(s.toString())).put("wall", wall).put("files", files)
            save()
        }
        // THE POST STANDS IN THE PAIR'S CHAT (iOS lay 1889-1892): the writer's row is born as the post leaves for the wall's owner
        if (send(wall, word)) cardRow(wall, id, s.optString("text"), ms.optJSONObject(0)?.optString("kind"), mine = true)
        synchronized(lock) { askedAt[wall] = System.currentTimeMillis() }
        send(wall, JSONObject().put("t", "ask"))
        synchronized(lock) {
            ensure()
            val pg = pages[wall] ?: JSONObject().put("w", true).put("ps", JSONArray()).put("at", System.currentTimeMillis()).also { pages[wall] = it }
            val ps = pg.optJSONArray("ps") ?: JSONArray()
            val list = (0 until ps.length()).mapNotNull { ps.optJSONObject(it) }.filter { it.optString("id") != id }.toMutableList()
            val before = list.indexOfFirst { !it.optBoolean("pinned") }
            list.add(if (before == -1) list.size else before, s)
            pg.put("ps", JSONArray(list))
            save()
        }
        changed()
    }

    // ── the post's row in the pair's chat (iOS MTWallCard, ChatStore.appendWallPost and dropWallPost) ──
    /**
     * A POST ON A WALL OF THE PAIR, IN THEIR CHAT (iOS ChatStore.appendWallPost, MontanaChatStore.swift:2640-2658 at 2155; the author's
     * word 30.09): the one birth of its row -- the writer's as the post leaves for the wall's owner (wrote), the owner's as the post is
     * taken onto the wall (MyWall.takePost). On a folded pipe it stands in the conversation the pipe speaks for; once per post, by the
     * post's own name, so a word carried twice lays nothing the second time; mine says whose hand wrote it, theirs is unread until the
     * chat is opened, as a letter is. It rings nothing and never leaves this phone.
     */
    fun cardRow(pipe: String, id: String, text: String, kind: String?, mine: Boolean) {
        val peer = SamePair.root(pipe)
        var laid = false
        Book.edit(peer) { c ->
            if (c.msgs.any { WallCard.of(it.text)?.id == id }) return@edit
            c.msgs.add(Msg(Marks.mintMid(), WallCard.row(id, text, kind), mine, System.currentTimeMillis(), state = if (mine) 1 else 2))
            c.msgs.sortBy { it.at }
            if (!mine && Book.openChat != peer) c.unread++
            laid = true
        }
        Log.d("Montana", "wall_card " + if (laid) "laid mine=" + (if (mine) 1 else 0) + " peer=" + peer.take(10) else "row stands -- once")
    }
    /** The wall's owner refused the post (iOS dropWallPost, MontanaChatStore.swift:2682-2690 at 2155): its row leaves the writer's chat --
     * the chat does not say a post stands where its owner said it does not. */
    fun dropCardRow(pipe: String, id: String) {
        Book.edit(SamePair.root(pipe)) { c -> c.msgs.removeAll { WallCard.of(it.text)?.id == id } }
    }

    // ── a post's files on this phone (iOS fileName, MTBoardShown.local) and my small face (iOS small, myFace) ──
    /** A post's file by its wall name (iOS fileName 497-499); null for a post whose name no file may take. */
    fun fileOf(p: JSONObject, i: Int): String? {
        val m = p.optJSONArray("media")?.optJSONObject(i) ?: return null
        val id = p.optString("id")
        return if (plain(id)) fileName(id, i, m.optString("ext")) else null
    }
    /** A post's file on this phone (iOS MTBoardShown.local, MontanaBoardViews.swift:3006-3009 at 2155): the store's -- the writer's, a
     * keeper's, a touch's -- else the copy a look brought. */
    fun here(p: JSONObject, i: Int): File? {
        val name = fileOf(p, i) ?: return null
        return MyWall.storeFile(name).takeIf { it.exists() } ?: File(lookDir(), name).takeIf { it.exists() }
    }
    /** The post's file comes from the node now (iOS fetching 366): its rows wear the wheel. */
    fun isFetching(id: String) = synchronized(lock) { id in fetching }
    /** A face drawn square at the given side, cut to fill it, as a base64 JPEG (iOS small, MontanaBoard.swift:2124-2135 at 2155). */
    fun small(raw: ByteArray?, side: Int): String? {
        val b = raw?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } ?: return null
        if (b.width <= 0 || b.height <= 0) return null
        val s = maxOf(side.toFloat() / b.width, side.toFloat() / b.height)
        val w = b.width * s
        val h = b.height * s
        val drawn = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(drawn).drawBitmap(b, null, android.graphics.RectF((side - w) / 2, (side - h) / 2, (side + w) / 2, (side + h) / 2),
            android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
        val out = java.io.ByteArrayOutputStream()
        drawn.compress(Bitmap.CompressFormat.JPEG, 60, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP).takeIf { it.length <= FACE_LIMIT }
    }
    /** MY FACE, SMALL, OVER A POST I WRITE ON ANOTHER'S WALL (iOS myFace, MontanaBoard.swift:2058-2064 at 2155): the wall's owner keeps
     * it with the post, and a visitor who never met me sees it over my words. */
    fun myFace(): String? = small(SelfFace.bytes(Book.ctx), 96)
    /**
     * A DOWNLOAD IS COUNTED ONCE PER PERSON (iOS noteDownloaded 1722-1736, the author's word 24.09): when every file of the post has
     * come to this phone -- on the owner's wall, and on this page at once; one counted in a launch before this one is not counted again.
     */
    private fun noteDownloaded(wall: String, p: JSONObject) {
        val id = p.optString("id")
        val ms = p.optJSONArray("media") ?: return
        if (ms.length() == 0) return
        if (!(0 until ms.length()).all { MyWall.storeFile(fileName(id, it, ms.optJSONObject(it)?.optString("ext") ?: "")).exists() }) return
        synchronized(lock) { if (!countedDownload.add(id)) return }
        if (wall.isEmpty()) { MyWall.ownMark(id, "downloads", true); return }
        synchronized(lock) {
            ensure()
            val k = kept[id]
            if (k?.optBoolean("dl") == true) return   // counted in a launch before this one
            k?.put("dl", true); save()
        }
        send(wall, JSONObject().put("t", "dl").put("id", id))
        patch(wall, id) { x -> x.put("downloads", x.optInt("downloads") + 1) }
    }
    /** Pieces of a post gone at every door (iOS reportGone 1737-1743): said once to the wall's owner; on my own wall I lay them again. */
    private fun reportGone(wall: String, id: String) {
        synchronized(lock) { if (!goneSaid.add(id)) return }
        Log.d("Montana", "wall_gone id=" + id.take(10) + " wall=" + (if (wall.isEmpty()) "mine" else "theirs"))
        if (wall.isEmpty()) { MyWall.reseed(id); return }
        send(wall, JSONObject().put("t", "gone").put("id", id))
    }
    /** The wall's owner asks this keeper to lay a post's files on the node again (iOS apply «seed» 964-966): the post as it was kept. */
    private fun seedKept(id: String) {
        val media = synchronized(lock) { ensure(); kept[id]?.optJSONObject("post")?.optJSONArray("media") } ?: return
        Thread { seedFiles(id, media) }.start()
    }
    /**
     * A KEEPER LAYS THE FILES ON THE NODE AGAIN UNDER THE SAME KEY (iOS seedFiles 1752-1762): the same bytes sealed by the same key in
     * the same pieces give the same chunk names, so the manifest every page already carries finds them again.
     */
    fun seedFiles(id: String, media: JSONArray) {
        if (!plain(id)) return
        var n = 0
        for (i in 0 until media.length()) {
            val m = media.optJSONObject(i) ?: continue
            val f = MyWall.storeFile(fileName(id, i, m.optString("ext")))
            val key = runCatching { Base64.decode(m.optString("key"), Base64.DEFAULT) }.getOrNull()
            if (!f.exists() || key == null || key.isEmpty()) continue
            if (Media.layFile(f, "", key) {} != null) n++
        }
        Log.d("Montana", "wall_seed id=" + id.take(10) + " files=" + n + "/" + media.length())
    }
    /** A post's name as a file's name: letters, digits and the dash -- a hostile page names no path (iOS names a post «p» and 24 hex). */
    private fun plain(id: String) = id.isNotEmpty() && id.all { it.isLetterOrDigit() || it == '-' }

    // ── the visitor's marks (iOS like, view, comment) ──
    fun post(wall: String, id: String): JSONObject? = if (wall.isEmpty()) MyWall.post(id) else synchronized(lock) {
        ensure()
        val ps = pages[wall]?.optJSONArray("ps") ?: return null
        (0 until ps.length()).mapNotNull { ps.optJSONObject(it) }.firstOrNull { it.optString("id") == id }
    }
    fun canWrite(wall: String) = wall.isEmpty() || synchronized(lock) { ensure(); pages[wall]?.optBoolean("w") == true }

    /** WHICH WALL HOLDS A POST, FOR A WALL'S LINK (iOS MTBoard.place(of:), MontanaBoard.swift:1431-1435): "" for a post of mine,
     * a correspondent's ref for a post on their page, null for a post this phone does not hold. */
    fun place(id: String): String? {
        if (MyWall.post(id) != null) return ""
        return synchronized(lock) {
            ensure()
            pages.entries.firstOrNull { (_, pg) -> (pg.optJSONArray("ps") ?: JSONArray()).let { ps -> (0 until ps.length()).any { i -> ps.optJSONObject(i)?.optString("id") == id } } }?.key
        }
    }
    /** A long wall link, read before every other link (iOS MontanaFirstContact.handleLink:1855, MTBoardComments.target:2421-2433). */
    class LinkTarget(val wall: String, val post: String, val comment: String?)
    fun isWallLink(link: String): Boolean = Meeting.normalize(link).startsWith("montana://wall/")
    /** The post and the comment a wall link names among the posts this phone holds (iOS MTBoardComments.target,
     * MontanaBoardViews.swift:2421-2434 at 2155): the long link by the post's name, the short one by the wall's nick and the post's
     * number on that wall; null for a post not held here. */
    fun linkTarget(link: String): LinkTarget? {
        val parts = Meeting.normalize(link).removePrefix("montana://wall/").split("/").filter { it.isNotEmpty() }
        if (parts.size == 2 && parts[0] == "post") place(parts[1])?.let { return LinkTarget(it, parts[1], null) }
        if (parts.size == 3 && parts[0] == "comment") place(parts[1])?.let { return LinkTarget(it, parts[1], parts[2]) }
        // THE SHORT LINK READ BACK (2429-2432): «@nick», the post's number on that wall, and a comment's number in its chain
        val n = parts.getOrNull(1)?.toIntOrNull()
        if ((parts.size == 2 || parts.size == 3) && parts[0].startsWith("@") && n != null)
            return shortTarget(parts[0].drop(1), n, if (parts.size == 3) parts[2].toIntOrNull() else null)
        return null
    }
    /**
     * THE SHORT LINK (iOS MTBoard.linkPost(_:on:), MontanaBoard.swift:1457-1463 at 2155, the author's word 02.10): the wall's owner by the
     * nick after «@» in their name, and the post's number on that wall; a post with no number yet, or a wall with no nick, keeps the long
     * link. Written as a person reads it (iOS MTLinks.readable, MontanaPeerInfo.swift:206): the letters of a name, never a URL's bytes.
     */
    fun linkPost(p: JSONObject, wall: String): String {
        val long = "montana://wall/post/" + p.optString("id")
        if (!p.has("n")) return long
        val claimed = claimedName(wall) ?: return long
        return "montana://wall/@" + claimed + "/" + p.optInt("n")
    }
    /** The nick a wall goes by in a link (iOS claimedName(of:), 1468-1471): after «@» in the name its owner gave themselves -- my own
     * for my wall --, else the name this phone gave them. */
    private fun claimedName(wall: String): String? {
        val said = if (wall.isEmpty()) Prefs.userName else Book.chat(wall)?.name ?: ""
        return claimedIn(said) ?: if (wall.isEmpty()) null else Book.chat(wall)?.pin?.takeIf { it.isNotEmpty() }
    }
    /** iOS claimedName(in:) 1472-1476: the word after the last «@», up to a space. */
    private fun claimedIn(name: String): String? {
        val at = name.lastIndexOf('@')
        if (at < 0) return null
        return name.substring(at + 1).takeWhile { !it.isWhitespace() }.takeIf { it.isNotEmpty() }
    }
    /** The post a short link names among the walls this phone holds -- mine first, then the others by their reference -- and the
     * comment of that number in its chain (iOS find(name:number:comment:), 1477-1490). */
    private fun shortTarget(name: String, n: Int, k: Int?): LinkTarget? {
        val walls = listOf("") + synchronized(lock) { ensure(); pages.keys.sorted() }
        for (w in walls) {
            if (claimedName(w)?.equals(name, ignoreCase = true) != true) continue
            val p = (if (w.isEmpty()) MyWall.posts() else posts(w).map { it.post }).firstOrNull { it.has("n") && it.optInt("n") == n } ?: continue
            var cid: String? = null
            if (k != null) {
                val cs = p.optJSONArray("comments") ?: JSONArray()
                val i = k - (p.optInt("commentCount") - cs.length()) - 1
                if (i in 0 until cs.length()) cid = cs.optJSONObject(i)?.optString("id")
            }
            return LinkTarget(w, p.optString("id"), cid)
        }
        return null
    }
    /** A WALL READ AS ITS OWNER SENT IT (iOS posts(on:), MontanaBoard.swift:723): every post of one person's own page, the
     * pinned first, then by the newest record of its chain -- its birth or its latest comment (iOS lastAt 1306), so a comment
     * of mine lifts its post here at once. */
    fun posts(wall: String): List<Item> = synchronized(lock) {
        ensure()
        val ps = pages[wall]?.optJSONArray("ps") ?: return emptyList()
        (0 until ps.length()).mapNotNull { ps.optJSONObject(it)?.let { p -> Item(wall, p) } }
            .sortedWith(compareByDescending<Item> { it.post.optBoolean("pinned") }.thenByDescending { lastAt(it.post) })
    }
    private fun lastAt(p: JSONObject): Double {
        val cs = p.optJSONArray("comments") ?: return p.optDouble("at", 0.0)
        return (0 until cs.length()).maxOfOrNull { cs.optJSONObject(it)?.optDouble("at", 0.0) ?: 0.0 }?.let { maxOf(it, p.optDouble("at", 0.0)) } ?: p.optDouble("at", 0.0)
    }
    /** THE LOOK ASKS (iOS look, MontanaBoard.swift:609-613, the author's word 25.09): a person's page not held, or held
     * more than ten minutes ago, is asked for the moment their page opens; a page already fresh is drawn at once and
     * nothing is sent. */
    fun look(ref: String) {
        val stale = synchronized(lock) { ensure(); val pg = pages[ref]; pg == null || System.currentTimeMillis() - pg.optLong("at") >= LOOK_STALE }
        if (stale) ask(ref)
    }
    /**
     * WHOSE POST IT IS, AS FAR AS THIS PHONE KNOWS (iOS writer(of:on:), MontanaBoard.swift:2137-2154 at 2155): "" -- mine, a reference
     * -- a correspondent's, null -- a writer this phone is not told of. On my wall its writer's reference is mine to read; on another's
     * the post is mine, the owner's own, or -- a repost -- its first writer's, where this phone holds the post as itself.
     */
    fun writer(wall: String, p: JSONObject): String? {
        if (wall.isEmpty()) return MyWall.writerOf(p.optString("id")) ?: if (p.optBoolean("mine")) "" else null
        if (p.has("from")) return if (p.optBoolean("own")) wall else originalWriter(p.optString("id"), wall)
        if (p.optBoolean("mine")) return ""
        return if (p.optBoolean("own")) wall else null
    }
    /** The post where it stands as itself -- my wall, else the first wall by its reference this phone holds -- and its writer there
     * (iOS originalWriter 2190-2194, original(of:besides:) 2182-2188). */
    private fun originalWriter(id: String, besides: String): String? {
        MyWall.writerOf(id)?.let { return it }
        val o = synchronized(lock) {
            ensure()
            pages.keys.sorted().filter { it != besides }.firstNotNullOfOrNull { w ->
                val ps = pages[w]?.optJSONArray("ps") ?: JSONArray()
                (0 until ps.length()).mapNotNull { ps.optJSONObject(it) }.firstOrNull { q -> q.optString("id") == id && !q.has("from") }?.let { q -> w to q }
            }
        } ?: return null
        return writer(o.first, o.second)
    }
    /** WHO WROTE A COMMENT, AS FAR AS THIS PHONE KNOWS (iOS commenter, MontanaBoard.swift:2195-2207 at 2155): on my wall its writer's
     * reference is mine to read; on another's the owner says which are this visitor's own («m») and which the owner's («o»). */
    fun commenter(wall: String, postId: String, k: JSONObject): String? {
        if (wall.isEmpty()) return MyWall.commenterOf(postId, k.optString("id"))
        if (k.optBoolean("m")) return ""
        return if (k.optBoolean("o")) wall else null
    }
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
        if (wall.isEmpty()) { MyWall.like(p.optString("id")); return }   // my own wall: my own mark, the version moves
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
        if (wall.isEmpty() || p.optBoolean("mine") || !p.has("views")) return
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
        if (wall.isEmpty()) { MyWall.comment(p.optString("id"), text); return }
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

/**
 * A POST'S POSTER, DECODED OFF THE MAIN THREAD AND KEPT (iOS MTBoardPoster, MontanaBoard.swift:2253-2288 at 2155): a tile decoded the
 * poster its post carries -- a JPEG of up to sixty thousand characters -- on the main thread at every drawing of the feed, and read
 * it whole again for its shape. Decoded once, off it, and kept by its own words within 32 MB; its shape is read from its header alone.
 */
private object WallPoster {
    private val pictures = Caches.kept("wall_posters", object : android.util.LruCache<String, Bitmap>(32_000_000) { override fun sizeOf(key: String, value: Bitmap) = value.byteCount })
    private val shapes = android.util.LruCache<String, Float>(1024)
    private val work = java.util.concurrent.Executors.newFixedThreadPool(2)
    private fun key(b64: String) = b64.length.toString() + ":" + b64.hashCode()
    /** The poster when it is already decoded; null -- not yet, and nothing is decoded here. */
    fun kept(b64: String): Bitmap? = if (b64.isEmpty()) null else pictures.get(key(b64))
    fun decode(b64: String, then: (Bitmap) -> Unit) {
        if (b64.isEmpty()) return
        work.execute {
            val b = pictures.get(key(b64)) ?: poster(b64)?.also { pictures.put(key(b64), it) }
            if (b != null) MainThread.post { then(b) }
        }
    }
    /** A poster's shape, width over height, from its header: no pixel of it is decoded. */
    fun shape(b64: String): Float? {
        if (b64.isEmpty()) return null
        shapes.get(key(b64))?.let { return it }
        val d = runCatching { Base64.decode(b64, Base64.DEFAULT) }.getOrNull() ?: return null
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(d, 0, d.size, o)
        if (o.outWidth <= 0 || o.outHeight <= 0) return null
        return (o.outWidth.toFloat() / o.outHeight).also { shapes.put(key(b64), it) }
    }
}

/** WHAT WAS DRAWN SHARP STAYS DRAWN (iOS MTBoardPicture.cache, MontanaBoardViews.swift:944-948 at 2155): the pictures drawn for the
 * tiles within 48 MB, by their file, so a post drawn again is sharp on its first frame. */
private val wallSharp = Caches.kept("wall_sharp", object : android.util.LruCache<String, Bitmap>(48_000_000) { override fun sizeOf(key: String, value: Bitmap) = value.byteCount })

/** WHERE A WRITER'S NAME LEADS (iOS MTBoardRoute and MTBoardOpen.go, MontanaBoardViews.swift:75-111 at 2155): mine to My page -- the
 * one the drawer's face opens, face and all -- never to the room of my saved letters; a correspondent's to their page. */
fun openWriter(act: MainActivity, w: String) {
    if (w.isEmpty()) act.push { close -> myPage(act, close) } else act.push { close -> peerInfoPage(act, w, close) }
}

/** A LINK THE POST'S WRITER READ (iOS MTWallLink, MontanaBoardViews.swift:544-642 at 2155, atom 5a84afb1f68f): the picture the
 * writer's own read brought -- its shape held between three quarters and two, corners 10, a circled play or note mark on it for a
 * video or a track -- the site in caption grey on one line, the title semibold on two, six apart. A visitor never touches the site
 * before a tap (atom 2d3d5127f89b in the head's form, 6d7be772 of 09.10.2026): a media file itself plays in the picture at the first
 * tap, with its sound and the speaker mark; the second tap quiets it and opens it whole; a service's page opens in that service. */
private fun wallLinkView(act: MainActivity, card: LinkCard): View {
    val c: Context = act
    val kind = LinkPreview.playKind(card.u)
    val ratio = ((card.w ?: 16).toFloat() / maxOf(card.h ?: 9, 1).toFloat()).coerceIn(0.75f, 2f)
    val b64 = card.i.orEmpty()
    var stage: FrameLayout? = null
    var tile: ImageView? = null
    var glyph: View? = null
    var speaker: View? = null
    var clip: WallLinkClip? = null
    var sound = false
    val playable = card.u.takeIf { kind != null && LinkPreview.mediaFile(it) }
    fun open() { Log.d("Montana", "post_link open " + (kind ?: "page")); act.openLink(card.u) }
    // iOS press(): the first tap fetches the file and plays it here with its sound; the next quiets it and opens it whole
    fun press() {
        val st = stage
        val now = clip
        if (now == null) {
            if (playable == null || st == null) { open(); return }
            val v = WallLinkClip(c, playable) { tile?.visibility = View.INVISIBLE }
            st.addView(v, 0, FrameLayout.LayoutParams(MATCH, MATCH))
            clip = v; sound = true; v.sound(true)
            glyph?.visibility = View.GONE; speaker?.visibility = View.VISIBLE
            Log.d("Montana", "post_link play " + kind)
            return
        }
        if (!sound) { sound = true; now.sound(true); speaker?.visibility = View.VISIBLE }
        else { sound = false; now.sound(false); speaker?.visibility = View.GONE; FilmActivity.openRemote(c, playable ?: return) }
    }
    return c.vstack(Gravity.NO_GRAVITY) {
        var above = false
        if (b64.isNotEmpty()) {
            val pic = object : ImageView(c) {
                override fun onMeasure(w: Int, h: Int) { val wd = MeasureSpec.getSize(w); setMeasuredDimension(wd, (wd / ratio).toInt()) }
            }.apply { scaleType = ImageView.ScaleType.CENTER_CROP }
            tile = pic
            // the poster is decoded off the screen's thread and kept (iOS MTBoardPoster.decoded, 561)
            WallPoster.kept(b64)?.let { pic.setImageBitmap(it) } ?: WallPoster.decode(b64) { pic.setImageBitmap(it) }
            val box = FrameLayout(c).apply {
                outlineProvider = object : ViewOutlineProvider() {
                    override fun getOutline(v: View, o: android.graphics.Outline) { o.setRoundRect(0, 0, v.width, v.height, c.dp(10).toFloat()) }
                }
                clipToOutline = true
                addView(pic, FrameLayout.LayoutParams(MATCH, WRAP))
                if (kind != null) addView(c.icon(if (kind == "aud") R.drawable.ic_music_note_circle_fill else R.drawable.ic_play_circle_fill,
                    android.graphics.Color.WHITE).also { glyph = it }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER))
                // the speaker while the sound is on: body semibold on a black 0.45 round, 8 in from the corner (iOS 596-604)
                addView(FrameLayout(c).apply {
                    background = c.rounded(android.graphics.Color.argb(115, 0, 0, 0), 100)
                    addView(c.icon(R.drawable.ic_set_speaker, android.graphics.Color.WHITE, 17), FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER))
                    visibility = View.GONE
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                }.also { speaker = it }, FrameLayout.LayoutParams(dp(33), dp(33), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, dp(8), dp(8)) })
            }
            stage = box
            addView(box, lp())
            above = true
        }
        card.s?.takeIf { it.isNotEmpty() }?.let {
            addView(c.text(it, 12f, MT.gray).apply { singleLineEllipsis() }, lp().apply { if (above) topMargin = dp(6) })   // USER-DATA: the site the card carries
            above = true
        }
        card.t?.takeIf { it.isNotEmpty() }?.let {
            addView(c.text(it, 15f, android.graphics.Color.WHITE).apply {
                // semibold as the reference's weight (600) where the platform draws weights, bold before it (LinkPreview.kt bubble card)
                typeface = if (28 <= android.os.Build.VERSION.SDK_INT) android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, 600, false)
                    else android.graphics.Typeface.DEFAULT_BOLD
                maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
            }, lp().apply { if (above) topMargin = dp(6) })   // USER-DATA: the page title the card carries
        }
        minimumHeight = dp(44)
        // one element to the reader: Video, Music or Link, and the title its writer read (iOS 558-559)
        contentDescription = c.getString(if (kind == "aud") R.string.pi_music else if (kind == "vid") R.string.pi_video else R.string.pf_link) +
            ", " + (card.t ?: card.u)
        pressable { press() }
    }
}

/** THE LINK'S FILE PLAYING IN ITS PICTURE (iOS MontanaClipPlayer, MontanaFeeds.swift:1004-1048): the platform's player on a texture
 * that takes the picture's rounded corners, filling it as the aspect-fill layer does, from the start again after its last frame; it
 * is born only at the tap, and the picture scrolled away lets the player go. The poster stays over it until the first frame stands
 * (a track has none: its poster stays). */
private class WallLinkClip(c: Context, private val url: String, private val shown: () -> Unit) : android.view.TextureView(c), android.view.TextureView.SurfaceTextureListener {
    private var player: android.media.MediaPlayer? = null
    private var loud = false
    private var vw = 0
    private var vh = 0
    private var wantPlaying = false
    // THE HEALING BACKS OFF AND GIVES UP (iOS MontanaClipPlayer.heal, MontanaFeeds.swift:1128-1205 at 2155): a clip stalled or
    // errored is restarted a beat later, each heal in a row waiting twice as long as the last (0.4 s to 10 s), the eighth the
    // last until the clip plays again or the page asks anew (the author's word 29.09: 130 heals a minute, 36 MB in one).
    private var healStreak = 0
    private var healing = false
    private val healHandler = android.os.Handler(android.os.Looper.getMainLooper())
    init { surfaceTextureListener = this }
    fun sound(on: Boolean) { loud = on; val v = if (on) 1f else 0f; player?.runCatching { setVolume(v, v) } }
    private fun fill() {
        if (vw == 0 || vh == 0 || width == 0 || height == 0) return
        val sx = width.toFloat() / vw; val sy = height.toFloat() / vh; val k = maxOf(sx, sy)
        setTransform(android.graphics.Matrix().apply { setScale(k / sx, k / sy, width / 2f, height / 2f) })
    }
    private fun heal(why: String) {
        if (!wantPlaying || healing) return
        if (healStreak >= HEAL_CAP) { Log.d("Montana", "post_link heal given up after " + HEAL_CAP + " -- " + why); return }
        healing = true
        val delay = minOf(10_000L, 400L shl healStreak)
        healStreak++
        healHandler.postDelayed({
            healing = false
            if (wantPlaying) runCatching { player?.start() }
            Log.d("Montana", "post_link healed after " + why + " try=" + healStreak + " wait_ms=" + delay)
        }, delay)
    }
    override fun onSurfaceTextureAvailable(st: android.graphics.SurfaceTexture, w: Int, h: Int) {
        wantPlaying = true
        player = runCatching { android.media.MediaPlayer().apply {
            setDataSource(context, android.net.Uri.parse(url))
            setSurface(android.view.Surface(st))
            isLooping = true
            setOnVideoSizeChangedListener { _, x, y -> vw = x; vh = y; fill() }
            setOnInfoListener { _, what, _ ->
                when (what) {
                    android.media.MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START -> { healStreak = 0; shown() }
                    android.media.MediaPlayer.MEDIA_INFO_BUFFERING_END -> healStreak = 0
                    android.media.MediaPlayer.MEDIA_INFO_BUFFERING_START -> heal("stalled")
                }
                false
            }
            setOnPreparedListener { mp -> val v = if (loud) 1f else 0f; mp.setVolume(v, v); mp.start() }
            setOnErrorListener { _, what, extra -> Log.d("Montana", "post_link failed what=" + what + " extra=" + extra); heal("error"); true }
            prepareAsync()
        } }.getOrNull()
    }
    override fun onSurfaceTextureSizeChanged(st: android.graphics.SurfaceTexture, w: Int, h: Int) { fill() }
    override fun onSurfaceTextureDestroyed(st: android.graphics.SurfaceTexture): Boolean {
        wantPlaying = false; healStreak = 0; healHandler.removeCallbacksAndMessages(null)
        player?.runCatching { release() }; player = null; return true
    }
    override fun onSurfaceTextureUpdated(st: android.graphics.SurfaceTexture) {}
    private companion object { const val HEAL_CAP = 8 }
}

/** ONE POST OF THE FEED (iOS MTBoardCell in MTFeedTabView): whose wall, the writer, the words, the pictures, the counts. */
fun postCell(act: MainActivity, it: Board.Item, whole: Boolean = false, onItsWall: Boolean = false, sending: Boolean = false, field: View? = null): View = act.vstack(Gravity.NO_GRAVITY) {
    val c: Context = act
    val openComments = { act.push { close -> wallCommentsPage(act, it.wall, it.post.optString("id"), close) } }
    val p = it.post
    val own = p.optBoolean("own")
    // A REPOST ON ITS WAY, OVER THE POST IT TAKES (iOS MTRepostBar, MontanaBoardViews.swift:2800-2813 at 2155 -- over the cell in
    // MTBoardRows 178 and in the feed 2945): the bar a post goes out under, live, with its try again and its letting go
    if (!sending) Board.repostGoing(it.wall, p.optString("id"))?.let { r ->
        addView(goingBar(act, r, onRetry = { Thread { Board.repost(r.wall, r.post) }.start() }, onDiscard = { Board.letRepostGo(r.id) }), lp())
        gap(if (onItsWall) 12 else 4)
    }
    // WHOSE WALL A POST STANDS ON, when its writer is not the wall's owner and the row is not drawn on that very wall's
    // own page (iOS onItsWall, MontanaBoardViews.swift: "Drawn on its wall's own page... in the feed, off it")
    if (!own && !onItsWall) addView(c.text(c.getString(R.string.wall_on, Board.nameOf(c, it.wall)), 12f, MT.gray).apply { setPadding(dp(4), 0, 0, dp(6)) }, lp())
    addView(c.vstack(Gravity.NO_GRAVITY) {
        // THE POST'S PLATE (iOS MTBoardPostPlate, MontanaBoardViews.swift:2548-2560 at 2155; BubbleShape 18, MontanaBubble.swift:62-69):
        // one-tone glass in a correspondent's bubble's own shape, under the glass's thin light rim -- the clear glass is the buttons'
        background = c.rounded(GLASS_TONE, 18, android.graphics.Color.argb(46, 255, 255, 255))
        setPadding(dp(12), dp(12), dp(12), dp(12))
        val name = p.optString("byName").ifEmpty { c.getString(R.string.wall_someone) }
        val face = if (own && it.wall.isEmpty()) SelfFace.load(c)   // my own wall: my own face
            else if (own) Book.face(it.wall).takeIf { f -> f.exists() }?.let { f -> BitmapFactory.decodeFile(f.path) } else poster(p.optString("face"))
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            // THE BYLINE OPENS ITS WRITER'S ONE PAGE (iOS MTBoardCell.header, MontanaBoardViews.swift:375-386 at 2155; MTBoardOpen 94-111):
            // the face, the name and when -- one target over its whole room; my name leads to My page, a correspondent's to theirs; a
            // writer this phone is not told of opens nothing, nor the wall's owner on their own wall's page
            val w = Board.writer(it.wall, p)
            val opens = when {
                w == null -> false
                w.isEmpty() -> it.wall.isNotEmpty() || !onItsWall   // in the feed my own post opens my page
                else -> w != it.wall || !onItsWall
            }
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = dp(44)
                addView(c.avatar(face, name, 40), lp(dp(40), dp(40)))
                gap(10)
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.text(name, 15f, android.graphics.Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())
                    val at = (p.optDouble("at") * 1000).toLong()
                    addView(c.text(android.text.format.DateUtils.getRelativeTimeSpanString(at, System.currentTimeMillis(), 60_000L), 12f, MT.gray), lp())
                }, lp(0, WRAP, 1f))
                if (opens && w != null) pressable { openWriter(act, w) }
            }, lp(0, WRAP, 1f))
            // THE POST'S OWN MENU (iOS MTBoardCell menuItems, MontanaBoardViews.swift:404-441 at 2155): on every wall, while the post is
            // not on its way (postMenu)
            if (!sending) addView(c.icon(R.drawable.ic_more_horiz, MT.gray).apply {
                setPadding(dp(11), dp(11), dp(11), dp(11))
                contentDescription = c.getString(R.string.pi_more)
                pressable { postMenu(act, this, it.wall, p) }
            }, lp(dp(44), dp(44)))
        }, lp())
        p.optString("from").takeIf { f -> f.isNotEmpty() }?.let { f ->
            gap(8); addView(c.text(c.getString(R.string.wall_reposted, f), 12f, MT.gray), lp())
        }
        val words = p.optString("text")
        // EVERY MONTANA LINK OPENS AT A TOUCH (iOS MTPostTextView.lay, MontanaBoardViews.swift:2662-2666, atom 20c5cef6f490):
        // the web's own finder and a Montana link alike, in the platform's own blue (iOS words.tintColor, MontanaBoardViews.swift:2632).
        // THE EDITOR'S WORDS STAND WHERE THE POST'S WORDS STAND (iOS MTBoardEditor's cell with its draft, MontanaBoardViews.swift:2089-2090)
        if (field != null) { gap(10); addView(field, lp()) }
        else if (words.isNotEmpty()) {
            gap(10)
            addView(c.text(linkedWords(words) { u -> act.openLink(u.toString()) }, 16f).apply {
                setTextIsSelectable(false)
                movementMethod = android.text.method.LinkMovementMethod.getInstance()
                setLinkTextColor(MT.blue)
            }, lp())
        }
        // A LINK THE POST'S WRITER READ RIDES WITH THE POST (iOS MTWallLink, MontanaBoardViews.swift:544 at 2155, atom 5a84afb1f68f):
        // the picture its writer's own read brought, the site and the title under it.
        if (field == null) LinkCard.parse(p.optString("lp"))?.let { card -> gap(10); addView(wallLinkView(act, card), lp()) }
        val media = p.optJSONArray("media") ?: JSONArray()
        for (i in 0 until media.length()) {
            val m = media.optJSONObject(i) ?: continue
            val kind = m.optString("kind")
            if (kind != "img" && kind != "vid") continue
            val thumb = m.optString("thumb")
            val fr = m.optJSONObject("fr")
            // THE SHAPE FROM THE FRAME, ELSE FROM THE POSTER'S HEADER ALONE (iOS MTBoardPoster.shape, MontanaBoard.swift:2277-2287 at 2155)
            val shape = fr?.optDouble("a", 0.0)?.toFloat()?.takeIf { s -> s > 0f } ?: WallPoster.shape(thumb) ?: 1f
            gap(10)
            val posterHeld = WallPoster.kept(thumb)
            var sharp = false
            val tile = WallTile(c, shape).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                background = c.rounded(MT.hairline, 12)
                outlineProvider = ViewOutlineProvider.BACKGROUND
                clipToOutline = true
                posterHeld?.let { b -> setImageBitmap(b) }
            }
            addView(tile, lp())
            // A TILE'S TOUCH OPENS ITS FILE (iOS MTBoardMediaView.tile, MontanaBoardViews.swift:695-716 at 2155; openTile)
            if (field == null) tile.pressable { openTile(act, it.wall, p, i, !onItsWall, whole) }   // the editor's tiles answer nothing (iOS onTile: { _ in }, 2090)
            // THE SHARP PICTURE, ELSE THE POSTER DECODED OFF THE MAIN THREAD, ELSE THE TILE'S GREY (iOS MTBoardPicture, MontanaBoardViews.swift:
            // 926-941 at 2155); what was drawn sharp stands sharp on the first frame of the next drawing (iOS MTBoardPicture.cache 944-948)
            if (posterHeld == null) WallPoster.decode(thumb) { b -> if (!sharp) tile.setImageBitmap(b) }
            Board.bring(m, p.optString("id"), i) { f ->
                val held = wallSharp.get(f.path)
                if (held != null) { sharp = true; tile.setImageBitmap(held) }
                else Thread { Media.preview(c, f, kind, 1600)?.let { b -> wallSharp.put(f.path, b); MainThread.post { sharp = true; tile.setImageBitmap(b) } } }.start()
            }
        }
        // THE TRACKS AND THE FILES AS ROWS, UNDER THE PICTURES (iOS MTBoardMediaView, MontanaBoardViews.swift:657-667, 718-720 at 2155):
        // a track in the one player's face, any other file as its row
        for (i in 0 until media.length()) {
            val m = media.optJSONObject(i) ?: continue
            val kind = m.optString("kind")
            if (kind == "img" || kind == "vid") continue
            gap(8)
            addView(if (kind == "aud") trackRow(act, it.wall, p, i, m, !onItsWall) else fileRow(act, it.wall, p, i, m), lp())
        }
        // THE COUNTS (iOS counters 445-487): like, comments, keepers, reposts; in the corner the downloads and the eye with the views
        // where the wall's owner counts them.
        if (sending) return@vstack
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
            // THE POST'S PEERS ANSWER THE FINGER (iOS counters 452-454): a tap saves the post -- its files come here and stay -- or lets it go
            mark(if (p.optBoolean("kept")) R.drawable.ic_tray_full_fill else R.drawable.ic_tray_down, p.optInt("keepers"), if (p.optBoolean("kept")) android.graphics.Color.WHITE else MT.gray, R.string.wall_keepers) {
                Thread { if (p.optBoolean("kept")) Board.unkeep(it.wall, p) else Board.keep(it.wall, p) }.start()
            }
            // A REPOST FROM ITS MARK (iOS counters 455-457): on another's wall, of a post neither mine nor reposted yet
            val reposts = it.wall.isNotEmpty() && !p.optBoolean("reposted") && !p.optBoolean("mine")
            mark(R.drawable.ic_repost, p.optInt("reposts"), if (p.optBoolean("reposted")) android.graphics.Color.WHITE else MT.gray, R.string.wall_repost,
                if (reposts) ({ Thread { Board.repost(it.wall, p) }.start() }) else null)
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
    if (!sending) addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Board.view(it.wall, it.post) }
        override fun onViewDetachedFromWindow(v: View) {}
    })
}

/**
 * THE POST'S MENU (iOS MTBoardCell.menuItems, MontanaBoardViews.swift:404-441 at 2155), the platform's own menu at the dots: Share -- the
 * post's link; on my own wall Pin or Unpin; Remove from saved while kept -- on another's wall never for my own post there, whose files I
 * keep while it stands -- else Save; Repost on another's wall, of a post neither mine nor reposted yet; Copy the words; Report another's
 * post; on my own wall Delete -- a wall's owner alone takes a post off it. Edit (416-419), after Pin: my own post on my own wall, never a repost.
 */
private fun postMenu(act: MainActivity, anchor: View, wall: String, p: JSONObject) {
    val c: Context = act
    val id = p.optString("id")
    val mine = p.optBoolean("mine")
    fun red(res: Int): CharSequence = android.text.SpannableString(c.getString(res)).apply {
        setSpan(android.text.style.ForegroundColorSpan(MT.red), 0, length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
    android.widget.PopupMenu(c, anchor).apply {
        menu.add(0, 0, 0, R.string.share)
        if (wall.isEmpty()) menu.add(0, 1, 1, if (p.optBoolean("pinned")) R.string.cl_unpin else R.string.cl_pin)
        if (wall.isEmpty() && mine && !p.has("from")) menu.add(0, 8, 1, R.string.edit)   // MY OWN WORDS ARE MINE TO CHANGE (iOS 416-419)
        if (!p.optBoolean("kept")) menu.add(0, 2, 2, R.string.wall_save)
        else if (!mine || wall.isEmpty()) menu.add(0, 3, 3, R.string.wall_unsave)
        if (wall.isNotEmpty() && !p.optBoolean("reposted") && !mine) menu.add(0, 4, 4, R.string.wall_repost)
        if (p.optString("text").isNotEmpty()) menu.add(0, 5, 5, R.string.copy)
        if (!mine) menu.add(0, 6, 6, red(R.string.pi_report))
        if (wall.isEmpty()) menu.add(0, 7, 7, red(R.string.delete))
        setOnMenuItemClickListener { item ->
            when (item.itemId) {
                0 -> sharePost(act, wall, p)
                1 -> Thread { MyWall.pin(id) }.start()
                2 -> Thread { Board.keep(wall, p) }.start()
                3 -> Thread { Board.unkeep(wall, p) }.start()
                4 -> Thread { Board.repost(wall, p) }.start()
                5 -> c.getSystemService(android.content.ClipboardManager::class.java)
                    .setPrimaryClip(android.content.ClipData.newPlainText("", p.optString("text")))   // USER-DATA: the post's words
                6 -> reportPost(act, wall, p)
                7 -> Thread { MyWall.remove(id) }.start()
                8 -> act.push { close -> postEditor(act, p, close) }
            }
            true
        }
    }.show()
}

/**
 * A POST GOES OUT AS ITS SHORT LINK (iOS MTPostLinkItem, MontanaBoardViews.swift:2205-2232 at 2155): the platform's own share with the
 * link that opens the post inside Montana -- the wall's nick and the post's number where they are (Board.linkPost) --, titled by its
 * writer and the first of its words. The link goes as a person reads it (MTLinks.readable, 2223-2230): the letters of a name, never the
 * bytes of a URL -- this phone's share hands every door the one text.
 */
private fun sharePost(act: MainActivity, wall: String, p: JSONObject) {
    val words = p.optString("text").trim()
    val title = if (words.isEmpty()) p.optString("byName") else p.optString("byName") + " · " + words.take(160)   // USER-DATA: the writer's name and words
    val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
        .putExtra(android.content.Intent.EXTRA_TEXT, Board.linkPost(p, wall)).putExtra(android.content.Intent.EXTRA_TITLE, title)
    runCatching { act.startActivity(android.content.Intent.createChooser(send, null)) }
}

/**
 * A POST REPORTED (iOS MTBoardSheet.reporting, MontanaBoardViews.swift:28-36 at 2155): its writer when this phone knows them, and then
 * they may be blocked with it; a writer the wall never named is reported through the wall that carried the post, and nobody is blocked
 * for another's words.
 */
private fun reportPost(act: MainActivity, wall: String, p: JSONObject) {
    val w = Board.writer(wall, p)
    val name = p.optString("byName")
    if (!w.isNullOrEmpty()) act.push { close -> reportPage(act, w, name, onClose = close) }
    else act.push { close -> reportPage(act, wall, name, offersBlock = false, onClose = close) }
}

/** THE PAGE A POST STANDS ON (iOS MTBoardPlaylist and MTBoardShown.all, MontanaBoardViews.swift:799-801, 3016-3020 at 2155): the feed's
 * posts in the feed, the wall's on its own page -- mine read from my own wall. */
private fun wallPage(wall: String, inFeed: Boolean): List<Board.Item> = when {
    inFeed -> Board.feed()
    wall.isEmpty() -> MyWall.posts().map { Board.Item("", it) }
    else -> Board.posts(wall)
}

/**
 * A TILE'S TOUCH OPENS ITS FILE (iOS MTBoardMediaView.tile, MontanaBoardViews.swift:695-716 at 2155): on a wall's page and in the feed the
 * picture or the film opens the page of the pictures and the films, one screen each, up and down (onShow 182 and 2950, MTBoardMediaPage
 * 3040-3105); the post whole on its comments' page keeps the post's own road (open 768-791): the file comes by the touch's own road
 * (Board.file -- this phone becomes the post's peer, the download counts), a picture opens among the pictures of the page held here,
 * a film in the one player (iOS VideoPresenter).
 */
private fun openTile(act: MainActivity, wall: String, p: JSONObject, i: Int, inFeed: Boolean, whole: Boolean = false) {
    val kind = p.optJSONArray("media")?.optJSONObject(i)?.optString("kind") ?: return
    if (!whole) { act.push { close -> wallMediaPage(act, wall, p, i, inFeed, close) }; return }
    Thread {
        val f = Board.file(wall, p, i) ?: return@Thread
        if (kind == "vid") { MainThread.post { FilmActivity.open(act, f) }; return@Thread }
        fun pictures(posts: List<Board.Item>): List<File> {
            val once = HashSet<String>()
            val out = ArrayList<File>()
            for (item in posts) {
                if (!once.add(item.post.optString("id"))) continue
                val ms = item.post.optJSONArray("media") ?: continue
                for (j in 0 until ms.length()) if (ms.optJSONObject(j)?.optString("kind") == "img") Board.here(item.post, j)?.let { out.add(it) }
            }
            return out
        }
        var among = pictures(wallPage(wall, inFeed))
        if (among.none { it.path == f.path }) among = pictures(listOf(Board.Item(wall, p)))
        val album = among
        MainThread.post { openPictures(act, f, album) }
    }.start()
}

/** One screen of the viewer (iOS MTBoardShown, MontanaBoardViews.swift:2997-3009 at 2155): a picture or a film of a post, and its wall. */
private class Shown(val wall: String, val post: JSONObject, val i: Int) {
    val id: String get() = post.optString("id") + "#" + i
    val media: JSONObject get() = post.optJSONArray("media")?.optJSONObject(i) ?: JSONObject()
}

/**
 * THE PAGE IS THE ALBUM (iOS MTBoardShown.all and visual, MontanaBoardViews.swift:3010-3037 at 2155): every picture and film of the page
 * the post stands on -- the feed's in the feed, the wall's on the wall --, in the page's order, each post once; a post the page no longer
 * holds as the finger came is an album of its own.
 */
private fun shownAll(wall: String, p: JSONObject, i: Int, inFeed: Boolean): List<Shown> {
    fun visual(page: List<Board.Item>): List<Shown> {
        val once = HashSet<String>()
        val out = ArrayList<Shown>()
        for (item in page) {
            if (!once.add(item.post.optString("id"))) continue
            val ms = item.post.optJSONArray("media") ?: continue
            for (j in 0 until ms.length()) {
                val k = ms.optJSONObject(j)?.optString("kind")
                if (k == "img" || k == "vid") out.add(Shown(item.wall, item.post, j))
            }
        }
        return out
    }
    val start = p.optString("id") + "#" + i
    val out = visual(wallPage(wall, inFeed))
    return if (out.any { it.id == start }) out else visual(listOf(Board.Item(wall, p)))
}

private const val ZOOM_TAG = "wall_zoom"
/** A few screens of pictures at their own pixels, kept by their cost (iOS MTBoardShownPicture.cache, MontanaBoardViews.swift:3141-3142). */
private val wallShown = Caches.kept("wall_shown", object : android.util.LruCache<String, Bitmap>(48_000_000) { override fun sizeOf(key: String, value: Bitmap) = value.byteCount })

/**
 * THE SCREENS, UP AND DOWN (iOS MTBoardMediaPage's paging scroll, MontanaBoardViews.swift:3061-3075 at 2155: .scrollTargetBehavior
 * (.paging), .scrollDisabled(zoomed)): three screens stand one over another -- the one looked at and its neighbours; a vertical stroke
 * carries them together and settles on the next past a third of the height or on a fling, as this phone's album settles its pages
 * sideways (PicturePager -- the platform's paging names no number in the Swift); while a picture stands enlarged the screens hold still
 * and the stroke pans it. A pinch and a double tap enlarge a picture (MTZoomImage, as the album's ZoomPicture).
 */
private class ShownPager(private val act: MainActivity, private val count: Int, start: Int,
                         private val make: (Int, Boolean) -> View, private val onPage: (Int) -> Unit) : FrameLayout(act) {
    var at = start
        private set
    private val slots = List(3) { FrameLayout(act) }   // the one above, the one looked at, the one below
    private val slop = android.view.ViewConfiguration.get(act).scaledTouchSlop
    private var axis = 0   // 0 undecided, 1 the screens, 2 the enlarged picture's pan, 3 a stroke across: nothing
    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var tracker: android.view.VelocityTracker? = null
    private var scaling = false
    private var turning = false
    private fun zoom(): ZoomPicture? = slots[1].findViewWithTag<ZoomPicture>(ZOOM_TAG)
    private val scaler = android.view.ScaleGestureDetector(act, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(d: android.view.ScaleGestureDetector): Boolean { scaling = true; return zoom() != null }
        override fun onScale(d: android.view.ScaleGestureDetector): Boolean { zoom()?.zoomBy(d.scaleFactor, d.focusX, d.focusY); return true }
    })
    private val taps = android.view.GestureDetector(act, object : android.view.GestureDetector.SimpleOnGestureListener() {
        override fun onDoubleTap(e: android.view.MotionEvent): Boolean { zoom()?.toggleAt(e.x, e.y); return true }
    })

    init {
        slots.forEach { addView(it, LayoutParams(MATCH, MATCH)) }
        load()
    }

    private fun load() {
        for (k in 0..2) {
            val i = at - 1 + k
            slots[k].removeAllViews()
            if (i in 0 until count) slots[k].addView(make(i, k == 1), LayoutParams(MATCH, MATCH))
        }
        place(0f)
        onPage(at)
    }

    private fun place(dy: Float) {
        slots[0].translationY = dy - height
        slots[1].translationY = dy
        slots[2].translationY = dy + height
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) { super.onLayout(changed, l, t, r, b); place(slots[1].translationY) }

    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        taps.onTouchEvent(e)
        if (tracker == null) tracker = android.view.VelocityTracker.obtain()
        tracker?.addMovement(e)
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> { downX = e.x; downY = e.y; lastX = e.x; lastY = e.y; axis = 0; scaling = false }
            android.view.MotionEvent.ACTION_MOVE -> {
                if (scaling || 1 < e.pointerCount) { lastX = e.x; lastY = e.y; return true }
                val dx = kotlin.math.abs(e.x - downX)
                val dy = kotlin.math.abs(e.y - downY)
                if (axis == 0 && (slop < dx || slop < dy)) axis = when {
                    zoom()?.zoomed == true -> 2
                    dx < dy && !turning -> 1
                    else -> 3
                }
                when (axis) {
                    1 -> place(slots[1].translationY + (e.y - lastY))
                    2 -> zoom()?.panBy(e.x - lastX, e.y - lastY)
                }
                lastX = e.x; lastY = e.y
            }
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                tracker?.computeCurrentVelocity(1000)
                val vy = tracker?.yVelocity ?: 0f
                tracker?.recycle(); tracker = null
                if (axis == 1) {
                    val y = slots[1].translationY
                    val go = when {
                        y < -height / 3f || vy < -act.dp(600) -> 1
                        height / 3f < y || act.dp(600) < vy -> -1
                        else -> 0
                    }.let { if (at + it in 0 until count) it else 0 }
                    settle(go)
                }
                axis = 0
            }
        }
        return true
    }

    private fun settle(go: Int) {
        turning = true
        android.animation.ValueAnimator.ofFloat(slots[1].translationY, -go * height.toFloat()).apply {
            duration = 220
            addUpdateListener { a -> place(a.animatedValue as Float) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { turning = false; if (go != 0) { at += go; load() } }
            })
            start()
        }
    }
}

/**
 * A SCREEN OF A PICTURE (iOS MTBoardShownPicture, MontanaBoardViews.swift:3121-3166 at 2155): the picture whole, fitted, enlarged as the
 * album's are; at once the poster its post carries -- decoded already where the feed drew it --, sharp from the file the moment the file
 * lies here, decoded off the main thread at 2400 px on its longest side (3140) and kept (3142). The screen looked at goes the touch's own
 * road (Board.file, bring 3160-3165): the file comes, this phone becomes the post's peer and the download counts; the platform's wheel
 * stands over it while the file comes and nothing sharp stands yet (3135).
 */
private fun shownPicture(act: MainActivity, s: Shown, active: Boolean): View {
    val c: Context = act
    val pic = ZoomPicture(c).apply { tag = ZOOM_TAG }
    val wheel = android.widget.ProgressBar(c).apply {
        indeterminateTintList = android.content.res.ColorStateList.valueOf(android.graphics.Color.WHITE)
        visibility = View.GONE
    }
    var sharp = false
    fun sharpen() {
        val f = Board.here(s.post, s.i) ?: return
        val held = wallShown.get(f.path)
        if (held != null) { sharp = true; wheel.visibility = View.GONE; pic.show(held); return }
        Thread {
            val b = Media.preview(c, f, "img", 2400) ?: return@Thread
            wallShown.put(f.path, b)
            MainThread.post { sharp = true; wheel.visibility = View.GONE; pic.show(b) }
        }.start()
    }
    sharpen()
    if (!sharp) {
        val thumb = s.media.optString("thumb")
        val kept = WallPoster.kept(thumb)
        if (kept != null) pic.show(kept) else WallPoster.decode(thumb) { b -> if (!sharp) pic.show(b) }
    }
    if (active) {
        if (!sharp && Board.fileOf(s.post, s.i)?.let { MyWall.storeFile(it).exists() } != true) wheel.visibility = View.VISIBLE
        Thread {
            Board.file(s.wall, s.post, s.i)
            MainThread.post { if (!sharp) { wheel.visibility = View.GONE; sharpen() } }
        }.start()
    }
    return FrameLayout(c).apply {
        addView(pic, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(wheel, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER))
    }
}

/**
 * A SCREEN OF A FILM (iOS MTBoardShownVideo, MontanaBoardViews.swift:3168-3213 at 2155): the platform's own player view with its controls
 * and its scrub (VideoView with the platform's MediaController), playing with sound while its screen is the one looked at and let go when
 * the screen is scrolled away; the poster the post carries stands in it until the first frame (3182-3186). The film comes whole by the
 * touch's own road first (Board.file): a film played from its first pieces is the chats' one lane of pieces (atom ec7b4762586f).
 */
private fun shownFilm(act: MainActivity, s: Shown, active: Boolean): View {
    val c: Context = act
    val box = FrameLayout(c)
    val poster = ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
    val thumb = s.media.optString("thumb")
    val kept = WallPoster.kept(thumb)
    if (kept != null) poster.setImageBitmap(kept) else WallPoster.decode(thumb) { b -> poster.setImageBitmap(b) }
    box.addView(poster, FrameLayout.LayoutParams(MATCH, MATCH))
    if (!active) return box
    val wheel = android.widget.ProgressBar(c).apply { indeterminateTintList = android.content.res.ColorStateList.valueOf(android.graphics.Color.WHITE) }
    box.addView(wheel, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER))
    var player: android.widget.VideoView? = null
    var gone = false
    box.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {}
        override fun onViewDetachedFromWindow(v: View) { gone = true; player?.stopPlayback(); player = null }   // the screen scrolled away rests (rest 3208-3213)
    })
    Thread {
        val f = Board.file(s.wall, s.post, s.i)
        MainThread.post {
            wheel.visibility = View.GONE
            if (f == null || gone) return@post
            val v = android.widget.VideoView(c)
            v.setMediaController(android.widget.MediaController(c))
            v.setOnInfoListener { _, what, _ -> if (what == android.media.MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) poster.visibility = View.GONE; false }
            box.addView(v, 0, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
            player = v
            v.setVideoPath(f.path)
            v.start()
        }
    }.start()
    return box
}

/**
 * THE VIEWER OF A POST'S PICTURES AND FILMS (iOS MTBoardMediaPage, MontanaBoardViews.swift:3040-3105 at 2155): a page pushed on the
 * stack the feed or the wall stands in, so the way out is the platform's own back -- its chevron and its edge swipe; every picture and
 * film of the page stands one screen each (MTBoardShown.all), up to the one before, down to the next, and it opens on the one touched.
 * The share (3090-3092, 3100-3104) hands the file of the screen looked at through the app's own door; a film not yet here shares nothing.
 */
private fun wallMediaPage(act: MainActivity, wall: String, p: JSONObject, i: Int, inFeed: Boolean, onClose: () -> Unit): View {
    val c: Context = act
    val items = shownAll(wall, p, i, inFeed)
    val start = maxOf(0, items.indexOfFirst { it.post.optString("id") == p.optString("id") && it.i == i })
    val pager = ShownPager(act, items.size, start, { k, active ->
        val s = items[k]
        if (s.media.optString("kind") == "vid") shownFilm(act, s, active) else shownPicture(act, s, active)
    }) { k -> Log.d("Montana", "wall_show page at=" + (k + 1) + " of=" + items.size) }
    Log.d("Montana", "wall_show open pages=" + items.size + " at=" + (start + 1) + " in=" + (if (inFeed) "feed" else "wall"))
    fun mark(glyph: Int, words: Int, deed: () -> Unit) = FrameLayout(c).apply {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(words)
        addView(c.icon(glyph, android.graphics.Color.WHITE, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        pressable(deed)
    }
    return FrameLayout(c).apply {
        setBackgroundColor(android.graphics.Color.BLACK)
        addView(pager, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(mark(R.drawable.ic_arrow_back_ios_new, R.string.back) { onClose() },
            FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply { setMargins(dp(14), dp(6), 0, 0) })
        addView(mark(R.drawable.ic_share, R.string.share) {
            val s = items.getOrNull(pager.at) ?: return@mark
            val f = Board.here(s.post, s.i) ?: return@mark
            val uri = Media.uri(c, f)
            val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType(c.contentResolver.getType(uri) ?: "*/*")
                .putExtra(android.content.Intent.EXTRA_STREAM, uri).addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            runCatching { act.startActivity(android.content.Intent.createChooser(send, null)) }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(6), dp(14), 0) })
    }
}

/**
 * A POST ON A WALL OF THE PAIR, A ROW OF THEIR CHAT (iOS MTWallCard, MTRowLetter.swift:214-262 at 2155; the author's word 30.09: «if I
 * publish on a friend's wall, let this post appear in his chat»): this phone's own row, never on the wire -- a copy arriving from
 * outside is a service word buried unread. It names the post by the name the post was born with, so a post stands in the chat once.
 */
object WallCard {
    const val MARK = "​​WP:"   // COMPAT-LOCAL: this phone's own row, never on the wire (iOS MTWallCard.mark 232)
    private const val WORDS_KEPT = 300   // iOS wordsKept 233: the card shows the post's first lines; the post itself lives on the wall
    class Card(val id: String, val tx: String, val k: String?)
    fun of(text: String): Card? {
        if (!text.startsWith(MARK)) return null
        val o = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull() ?: return null
        val id = o.optString("id").takeIf { it.isNotEmpty() } ?: return null
        return Card(id, o.optString("tx"), o.optString("k").takeIf { it.isNotEmpty() })
    }
    /** The row's words, written in this one place (iOS row 246-250). */
    fun row(id: String, text: String, kind: String?): String {
        val o = JSONObject().put("id", id).put("tx", text.trim().take(WORDS_KEPT))
        if (kind != null) o.put("k", kind)
        return MARK + o.toString()
    }
    /** What the card says: the post's own words, or the kind of its first file (iOS words 251-261). */
    fun words(c: Context, card: Card): String = card.tx.ifEmpty {
        when (card.k) {
            "img" -> c.getString(R.string.lw_photo)
            "vid" -> c.getString(R.string.lw_video)
            "aud" -> c.getString(R.string.pi_music)
            "doc" -> c.getString(R.string.file)
            else -> ""
        }
    }
}

/**
 * A POST ON A WALL OF THE PAIR, ITS BUBBLE (iOS MessageBubble.wallCardBubble, MontanaBubble.swift:903-920 at 2155): the wall's glyph
 * (text.below.photo, 22 in a 40 frame), «Wall post» as the headline and the post's first lines, three at most, in the chess
 * invitation's shape; the touch opens the wall the post stands on (primaryTap 454; MontanaConversation.swift:2177-2184, 2732) -- mine
 * stands on their wall, so their page; theirs on mine, so My page.
 */
fun wallCardPlate(c: Context, act: MainActivity?, ref: String, card: WallCard.Card, mine: Boolean): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    val ink = BubbleStyle.text(mine)
    addView(FrameLayout(c).apply {
        addView(c.icon(R.drawable.ic_text_below_photo, ink, 22), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
    }, lp(dp(40), dp(40)))
    gap(10)
    addView(c.vstack(Gravity.NO_GRAVITY) {
        addView(c.text(c.getString(R.string.wall_post), 17f, ink, bold = true), lp(WRAP, WRAP))
        // USER-DATA: the post's own words, as its writer wrote them
        addView(c.text(WallCard.words(c, card), 15f, ink).apply { maxLines = 3; ellipsize = android.text.TextUtils.TruncateAt.END; maxWidth = dp(220) },
            lp(WRAP, WRAP).apply { topMargin = dp(3) })
    }, lp(WRAP, WRAP))
    if (act != null) pressable { if (mine) act.push { close -> peerInfoPage(act, ref, close) } else act.push { close -> myPage(act, close) } }
}

/**
 * A POST OF MINE, ITS WORDS CHANGED (iOS MTBoardEditor, MontanaBoardViews.swift:2061-2131 at 2155; the author's word 30.09: «make
 * publications editable»): the post as it stands on its wall -- its own cell -- with its words a field where they stand; the check gives
 * the words to the wall (MyWall.edit) and stands dimmed until they changed (changed 2076-2079, 2103), the cross leaves them as they were,
 * and the field takes the keys at once (2105). Only the words: a file keeps the name its place gave it at birth.
 */
private fun postEditor(act: MainActivity, p: JSONObject, onClose: () -> Unit): View {
    val c: Context = act
    val was = p.optString("text")
    val files = p.optJSONArray("media")?.length() ?: 0
    val field = android.widget.EditText(c).apply {
        setText(was)   // USER-DATA: the post's own words
        hint = c.getString(R.string.write_something)
        setTextColor(android.graphics.Color.WHITE); setHintTextColor(MT.gray); background = null
        textSize = 16f
        setPadding(0, 0, 0, 0)
    }
    fun changed(): Boolean { val t = field.text.toString().trim(); return t != was && (t.isNotEmpty() || 0 < files) }
    val done = c.icon(R.drawable.ic_check, android.graphics.Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        contentDescription = c.getString(R.string.pe_done)
        pressable {
            if (!changed()) return@pressable
            val words = field.text.toString()
            Thread { MyWall.edit(p.optString("id"), words) }.start()
            onClose()
        }
        isEnabled = false
        alpha = 0.4f
    }
    field.addTextChangedListener(object : android.text.TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: android.text.Editable?) { done.isEnabled = changed(); done.alpha = if (done.isEnabled) 1f else 0.4f }
    })
    val page = settingsPage(act, c.getString(R.string.wall_edit_post), onClose, cross = true, trailing = done) {
        addView(postCell(act, Board.Item("", p), whole = true, onItsWall = true, sending = true, field = field), lp().apply { topMargin = dp(12) })
    }
    field.post {
        field.requestFocus()
        field.setSelection(field.text.length)
        c.getSystemService(android.view.inputmethod.InputMethodManager::class.java).showSoftInput(field, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
    }
    return page
}

/**
 * THE PAGE IS THE PLAYLIST (iOS MTBoardMediaView.open «aud» and MTBoardPlaylist, MontanaBoardViews.swift:797-809, 844-864 at 2155): the
 * one player plays the touched track, its queue every track of the page the post stands on, each once by its file; a post the page no
 * longer holds plays its own. This phone's player reads a whole file and no loader plays from the first pieces: the touched track comes
 * here first by the touch's own road (Board.file), and a track of the page not yet here stands out of the queue.
 */
private fun playTrack(act: MainActivity, wall: String, p: JSONObject, i: Int, inFeed: Boolean) {
    Thread {
        val f = Board.file(wall, p, i) ?: return@Thread
        fun tracks(posts: List<Board.Item>): List<Track> {
            val once = HashSet<String>()
            val out = ArrayList<Track>()
            for (item in posts) {
                val ms = item.post.optJSONArray("media") ?: continue
                for (j in 0 until ms.length()) {
                    val mj = ms.optJSONObject(j) ?: continue
                    if (mj.optString("kind") != "aud") continue
                    val here = Board.here(item.post, j) ?: continue
                    if (!once.add(here.name)) continue
                    out.add(Track(android.net.Uri.fromFile(here), mj.optString("name").ifEmpty { here.name }).apply { length = mj.optDouble("dur", 0.0) })
                }
            }
            return out
        }
        var list = tracks(wallPage(wall, inFeed))
        if (list.none { t -> t.uri.lastPathSegment == f.name }) list = tracks(listOf(Board.Item(wall, p)))
        val k = list.indexOfFirst { t -> t.uri.lastPathSegment == f.name }
        val queue = list
        Log.d("Montana", "music board queue n=" + queue.size + " at=" + (k + 1) + " in=" + (if (inFeed) "feed" else "wall"))
        if (k != -1) MainThread.post { MusicPlayer.play(act, queue, k) }
    }.start()
}

/**
 * A TRACK OF A POST IS A TRACK OF THE ONE PLAYER (iOS MTBoardMediaView.track, MontanaBoardViews.swift:722-743 at 2155): the playing track
 * wears the one bar itself (MontanaPlayerBar(row: true)) and every other stands still in the mini's face -- its play, its name without
 * its extension in the plate, its length; the face runs to the post's own edges (.padding(.horizontal, -16)), the whole row is one
 * target, and the platform's wheel stands on the play while the post's file comes (busy).
 */
private fun trackRow(act: MainActivity, wall: String, p: JSONObject, i: Int, m: JSONObject, inFeed: Boolean): View = FrameLayout(act).apply {
    val name = Board.fileOf(p, i)
    val busy = Board.isFetching(p.optString("id"))
    var shown: Boolean? = null
    fun draw() {
        val now = name != null && MusicPlayer.current?.uri?.lastPathSegment == name
        if (shown == now) return
        shown = now
        removeAllViews()
        val face: MiniFace = if (now) liveBar(act) else MiniFace(act, bar = false).apply {
            still(Track(android.net.Uri.EMPTY, m.optString("name")).apply { length = m.optDouble("dur", 0.0) }, false, false)
        }
        face.setPadding(0, dp(4), 0, dp(4))
        addView(face, FrameLayout.LayoutParams(MATCH, WRAP))
        if (!now && busy) addView(android.widget.ProgressBar(act).apply {
            indeterminateTintList = android.content.res.ColorStateList.valueOf(android.graphics.Color.WHITE)
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.START or Gravity.CENTER_VERTICAL))
    }
    draw()
    pressable { if (shown != true) playTrack(act, wall, p, i, inFeed) }
    val heard: () -> Unit = { draw() }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { MusicPlayer.listeners.add(heard); draw() }
        override fun onViewDetachedFromWindow(v: View) { MusicPlayer.listeners.remove(heard) }
    })
}

/**
 * A FILE OF A POST AS A ROW (iOS MTBoardMediaView.fileRow, MontanaBoardViews.swift:745-766 at 2155): the document's glyph on its dark
 * square, its name without its extension and its size, the platform's wheel while the post's file comes; the whole row one target --
 * the file comes by the touch's own road (Board.file) and opens in the document's page (iOS MTBoardDocPresenter).
 */
private fun fileRow(act: MainActivity, wall: String, p: JSONObject, i: Int, m: JSONObject): View {
    val c: Context = act
    val name = m.optString("name")
    val shown = name.substringBeforeLast('.').ifEmpty { name }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(44)
        addView(FrameLayout(c).apply {
            background = c.rounded(android.graphics.Color.rgb(41, 41, 41), 8)
            addView(c.icon(R.drawable.ic_compose_doc, MT.gray, 17), FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER))
        }, lp(dp(36), dp(36)))
        gap(12)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(shown, 17f).apply { singleLineEllipsis() }, lp())   // USER-DATA: the file's own name
            addView(c.text(android.text.format.Formatter.formatShortFileSize(c, m.optLong("size")), 12f, MT.gray), lp())
        }, lp(0, WRAP, 1f))
        if (Board.isFetching(p.optString("id"))) addView(android.widget.ProgressBar(c).apply {
            indeterminateTintList = android.content.res.ColorStateList.valueOf(android.graphics.Color.WHITE)
        }, lp(dp(24), dp(24)))
        pressable { Thread { Board.file(wall, p, i)?.let { f -> MainThread.post { openDocument(act, f) } } }.start() }
    }
}

/**
 * THE COMMENTS OF A POST (iOS MTBoardComments 2246-2440): the post whole on top, its chain newest first, each comment under its
 * writer's head with its number in the chain and its moment; the field below for one who may write on the wall, else the words
 * that say who may.
 */
fun wallCommentsPage(act: MainActivity, wall: String, id: String, onClose: () -> Unit, focus: String? = null): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(12), 0, dp(12), dp(16)) }
    val scroll = ScrollView(c)
    // A COMMENT'S OWN LINK SCROLLS TO IT, ONCE (iOS MTBoardComments's ScrollViewReader.onAppear, MontanaBoardViews.swift:1591, 2155
    // build): montana://wall/comment opens this same page already drawn to its one comment.
    var scrolled = focus == null
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
                tag = k.optString("id")
                setPadding(0, dp(10), 0, dp(6))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.avatar(face, name, 36), lp(dp(36), dp(36))); gap(10)
                    addView(c.text(name, 15f, android.graphics.Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
                    // A COMMENTER'S HEAD OPENS THEIR PAGE (iOS MTBoardComments.row, MontanaBoardViews.swift:2338-2349 at 2155): me, the wall's
                    // owner, and on my own wall every commenter -- the face and the name one target
                    Board.commenter(wall, id, k)?.let { w -> minimumHeight = dp(44); pressable { openWriter(act, w) } }
                }, lp())
                val words = k.optString("text")
                // EVERY MONTANA LINK OPENS AT A TOUCH (iOS MTBoard.linked, MontanaBoard.swift:1491-1493, atom 20c5cef6f490):
                // the web's own finder and a Montana link alike, in the system's blue.
                if (words.isNotEmpty()) addView(c.text(linkedWords(words) { u -> act.openLink(u.toString()) }, 16f).apply {
                    setPadding(dp(46), dp(2), 0, 0)
                    movementMethod = android.text.method.LinkMovementMethod.getInstance()
                    setLinkTextColor(MT.blue)
                }, lp())
                addView(c.text(Board.numberLine(base + i + 1, k.optDouble("at"), k.optString("h")), 11f, MT.gray).apply { setPadding(dp(46), dp(2), 0, 0) }, lp())
            }, lp())
        }
        if (!scrolled) {
            scrolled = true
            scroll.post {
                val target = (0 until body.childCount).map { body.getChildAt(it) }.firstOrNull { it.tag == focus }
                if (target != null) scroll.scrollTo(0, maxOf(0, target.top - (scroll.height - target.height) / 2))
            }
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
            addView(scroll.apply { addView(body) }, lp(MATCH, 0, 1f))
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
    private val goingColumn = c.vstack(Gravity.NO_GRAVITY)
    private val column = c.vstack(Gravity.NO_GRAVITY)
    private val empty = c.text(c.getString(R.string.no_posts), 17f, MT.gray, center = true)
    private val again: () -> Unit = { if (isShown) draw() }
    private var goingIds = emptyList<String>()
    // A POST OF MINE ON ITS WAY READ LIVE (iOS MTBoardSendingLive, MontanaBoardViews.swift:2824-2834 at 2155): its bar moves with every
    // piece the node confirms; a post that left its way, or a new one, moves the feed
    private val moved: () -> Unit = { if (isShown) { if (MyWall.sendingAll().map { it.id } != goingIds) draw() else drawGoing() } }
    // ROOM KEPT AT THE BOTTOM FOR THE FLOATING PLAYER (iOS MTFeedTabView.reserve, MontanaBoardViews.swift:2864 at 2155,
    // atom f056cf90ad09): the posts scroll clear of the bar while it stands -- 60 more than the tab bar's own room, as
    // the music page's plus moves for it (MusicPage.reserve).
    private val foot = View(c)
    // THE WRITE BUTTON, THE PAGE'S OWN CORNER (iOS MTFeedTabView.mtPageAction, MontanaBoardViews.swift:2889-2897 at 2155): the
    // one glyph that opens the composer on my own wall, above the floating player's room when it stands (reserve, as the
    // music's plus, Music.kt MusicPage.reserve).
    private val write = FrameLayout(c).apply {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(R.string.pi_write_wall)
        addView(c.icon(R.drawable.ic_compose, android.graphics.Color.rgb(204, 204, 204)), LayoutParams(dp(30), dp(30), Gravity.CENTER))
        pressable { act.push { close -> newPostPage(act, close) } }
    }
    init {
        addView(ScrollView(c).apply {
            isVerticalScrollBarEnabled = false
            addView(c.vstack(Gravity.NO_GRAVITY) { addView(goingColumn, lp()); addView(column, lp()); addView(foot, lp(MATCH, dp(120))) })
        }, LayoutParams(MATCH, MATCH))
        addView(empty, LayoutParams(WRAP, WRAP, Gravity.CENTER))
        addView(write, PageCorner.params(c))
    }
    /** The bar stands: the posts keep room under it and the write button steps above it, as the music's plus. */
    fun reserve(on: Boolean) {
        foot.layoutParams = lp(MATCH, dp(if (on) 180 else 120)); foot.requestLayout()
        write.layoutParams = PageCorner.params(c, reserve = on)
    }
    private fun draw() {
        val items = Board.feed()
        column.removeAllViews()
        for (it in items) column.addView(postCell(act, it), lp().apply { setMargins(dp(12), dp(6), dp(12), dp(6)) })
        drawGoing()
    }
    /** THE POSTS ON THEIR WAY STAND FIRST (iOS MTFeedTabView's rows, MontanaBoardViews.swift:2875-2879 and 2940-2942 at 2155): every post
     * of mine on its way to any wall, under the bar of its files, newest first, over the posts of the walls. */
    private fun drawGoing() {
        val going = MyWall.sendingAll()
        goingIds = going.map { it.id }
        goingColumn.removeAllViews()
        for (o in going) goingColumn.addView(goingCell(act, o), lp().apply { setMargins(dp(12), dp(6), dp(12), dp(6)) })
        empty.visibility = if (column.childCount == 0 && going.isEmpty()) View.VISIBLE else View.GONE
    }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); Board.listen(again); MyWall.listen(moved); draw() }
    override fun onDetachedFromWindow() { Board.unlisten(again); MyWall.unlisten(moved); super.onDetachedFromWindow() }
    override fun onVisibilityChanged(v: View, visibility: Int) {
        super.onVisibilityChanged(v, visibility)
        if (visibility == View.VISIBLE && isAttachedToWindow) { Board.lookFeed(); draw() }
    }
}
