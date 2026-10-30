package quest.montana.app

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * WHO MAY WRITE ON MY WALL, AND WHO MAY SEE IT (iOS MTBoardRule, MontanaBoard.swift 25-95 at 2155; the author's words 24.09 and 25.09):
 * only me, everyone, my contacts, some — chosen — or everyone but some. One rule over two acts, each under its own keys; both start
 * at «Everyone». A blocked person never may.
 */
object WallRule {
    enum class Act { WRITE, SEE }
    enum class Rule(val raw: String) { ONLY_ME("onlyMe"), EVERYONE("everyone"), CONTACTS("contacts"), SOME("some"), EXCEPT("except") }
    private fun keys(a: Act) = if (a == Act.WRITE) Triple("boardRule", "boardAllow", "boardDeny") else Triple("boardSight", "boardSightAllow", "boardSightDeny")
    fun current(a: Act): Rule = Prefs.str(keys(a).first, "").let { s -> Rule.values().firstOrNull { it.raw == s } } ?: Rule.EVERYONE
    private fun set(key: String) = Prefs.str(key, "").split('\n').filter { it.isNotEmpty() }.toSet()
    fun allowed(a: Act) = set(keys(a).second)
    fun denied(a: Act) = set(keys(a).third)
    fun choose(r: Rule, a: Act) { Prefs.setStr(keys(a).first, r.raw); MyWall.renewVersion(own = true) }
    fun setAllowed(s: Set<String>, a: Act) { Prefs.setStr(keys(a).second, s.sorted().joinToString("\n")); MyWall.renewVersion(own = true) }
    fun setDenied(s: Set<String>, a: Act) { Prefs.setStr(keys(a).third, s.sorted().joinToString("\n")); MyWall.renewVersion(own = true) }
    /** May this correspondent write on my wall, or see it? A blocked person never may. */
    fun admits(ref: String, a: Act): Boolean = ref.isNotEmpty() && !PeerSafety.isBlocked(ref) && byRule(ref, a)
    /** The rule alone, without the block list — for the presence word, which never reaches a blocked person anyway. */
    fun byRule(ref: String, a: Act): Boolean {
        if (ref.isEmpty()) return false
        return when (current(a)) {
            Rule.ONLY_ME -> false
            Rule.EVERYONE -> true
            Rule.CONTACTS -> Book.chat(ref)?.shown?.isNotBlank() == true && !Groups.isKey(ref)   // a person of the contacts' page
            Rule.SOME -> ref in allowed(a)
            Rule.EXCEPT -> ref !in denied(a)
        }
    }
}

/**
 * MY OWN WALL, AS ITS OWNER KEEPS IT (iOS MTBoard's owner side, MontanaBoard.swift 331-1343 at 2155; the author's word 24.09): on my page
 * the people I allow write posts, and a post lives with those who keep it. The references are mine and never leave this phone: a visitor
 * gets the counts and their own marks. The owner carries the page to every correspondent whose build speaks the wall and whose version
 * of it moved; the version rides every presence word («W»), one per visitor. Sealed at rest under the device key.
 */
object MyWall {
    private const val PAGE_SIZE = 30
    private const val COMMENTS_SHOWN = 20
    private const val TEXT_LIMIT = 4000
    private const val COMMENT_LIMIT = 1000
    private const val POSTS_PER_WRITER = 100   // [I-14]: a writer let in cannot fill a wall
    private const val WALL_LIMIT = 500
    private const val FACE_LIMIT = 16_000
    private const val THUMB_LIMIT = 60_000
    private const val MEDIA_LIMIT = 10
    private const val PUSH_TO = 128            // the owner carries the wall to the latest correspondents this many at most
    private const val PAGE_SHAPE = "c4"        // the page's shape is part of its version: c4 carries the posts' views
    private const val ZERO_HASH = "0000000000000000000000000000000000000000000000000000000000000000"

    private val lock = Any()
    private var loaded = false
    private val mine = mutableListOf<JSONObject>()
    private val cap = HashSet<String>()                    // correspondents whose build speaks the wall — told by their own words
    private val sent = HashMap<String, String>()           // the version each was last carried, written by the receipt alone
    private val inFlight = HashMap<String, Triple<String, Long, String>>()   // the page handed to the queue: version, moment, letter
    private val answeredAt = HashMap<String, Long>()
    private val pushing = HashSet<String>()
    @Volatile private var versionKept = "0"

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) = synchronized(listeners) { listeners.add(l) }
    fun unlisten(l: () -> Unit) = synchronized(listeners) { listeners.remove(l) }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun file() = File(File(Book.ctx.filesDir, "board").apply { mkdirs() }, "mine.sealed")
    private fun ensure() {
        if (loaded) return
        loaded = true
        if (!following) { following = true; Book.listen(bookMoved) }   // a wall kept for contacts follows the book (bookMoved)
        val o = runCatching { DeviceVault.unseal(file().readBytes())?.let { JSONObject(String(it, Charsets.UTF_8)) } }.getOrNull()
        o?.optJSONArray("mine")?.let { a -> for (i in 0 until a.length()) a.optJSONObject(i)?.let { mine.add(it) } }
        o?.optJSONArray("cap")?.let { a -> for (i in 0 until a.length()) cap.add(a.optString(i)) }
        o?.optJSONObject("sent")?.let { s -> s.keys().forEach { k -> sent[k] = s.optString(k) } }
        // a post on its way outlives the run; one a run died under is due again (iOS saveGoing 455, roadBack 1922)
        runCatching { DeviceVault.unseal(goingFile().readBytes())?.let { JSONArray(String(it, Charsets.UTF_8)) } }.getOrNull()?.let { a ->
            for (i in 0 until a.length()) a.optJSONObject(i)?.let { g -> going[g.optString("id")] = g.put("failed", true) }
        }
        val sealed = sealMissing()
        if (numberMissing() || sealed) write()
        versionKept = postsTag()
    }
    private fun write() {
        val o = JSONObject().put("mine", JSONArray(mine)).put("cap", JSONArray(cap.toList())).put("sent", JSONObject(sent as Map<*, *>))
        val sealedBytes = DeviceVault.seal(o.toString().toByteArray(Charsets.UTF_8)) ?: return
        val part = File(file().path + ".part")
        runCatching { part.writeBytes(sealedBytes); part.renameTo(file()) }
    }
    /** The person forgotten: their wall leaves with them. */
    fun wipe() = synchronized(lock) {
        mine.clear(); cap.clear(); sent.clear(); inFlight.clear(); going.clear(); loaded = false
        file().delete(); goingFile().delete(); store().deleteRecursively()
    }

    // ── the shape of a post, owner and visitor ──
    private fun arr(p: JSONObject, k: String): JSONArray = p.optJSONArray(k) ?: JSONArray().also { p.put(k, it) }
    private fun has(a: JSONArray, v: String) = (0 until a.length()).any { a.optString(it) == v }
    private fun toggle(p: JSONObject, k: String, who: String, on: Boolean) {
        val a = arr(p, k)
        if (on) { if (!has(a, who)) a.put(who) }
        else { val keep = JSONArray(); for (i in 0 until a.length()) a.optString(i).takeIf { it != who }?.let { keep.put(it) }; p.put(k, keep) }
    }
    private fun lastAt(p: JSONObject): Double {
        val cs = p.optJSONArray("comments") ?: return p.optDouble("at", 0.0)
        return (0 until cs.length()).maxOfOrNull { cs.optJSONObject(it)?.optDouble("at", 0.0) ?: 0.0 }?.let { maxOf(it, p.optDouble("at", 0.0)) } ?: p.optDouble("at", 0.0)
    }
    /** THE WALL, NEWEST FIRST: the pinned on top, then each post at the moment of the newest record of its chain. */
    private fun ordered(): List<JSONObject> = mine.sortedWith(compareByDescending<JSONObject> { it.optBoolean("pinned") }.thenByDescending { lastAt(it) })
    /** The views move the version at every doubling (1, 2, 4, 8 …), so a hundred viewers carry the wall a handful of times. */
    private fun viewStep(n: Int): Int = if (n == 0) 0 else 64 - java.lang.Long.numberOfLeadingZeros(n.toLong())

    /** One version per visitor's right, the posts' part beside it (iOS postsTag 552-565): an edit moves only its own wall's version. */
    private fun postsTag(): String {
        val shown = ordered().take(PAGE_SIZE)
        if (shown.isEmpty()) return "0"
        val s = StringBuilder(PAGE_SHAPE + ";")
        for (p in shown) {
            val cs = arr(p, "comments")
            val faces = (0 until cs.length()).count { cs.optJSONObject(it)?.has("fc") == true } + (if (p.has("face")) 1 else 0)
            val hid = (0 until cs.length()).count { cs.optJSONObject(it)?.optBoolean("hid") == true }
            s.append(p.optString("id")).append(if (p.optBoolean("pinned")) "p" else "").append(arr(p, "keepers").length()).append('.')
                .append(arr(p, "likes").length()).append('.').append(arr(p, "downloads").length()).append('.').append(arr(p, "reposts").length())
                .append('.').append(cs.length()).append('.').append(faces).append('.').append(viewStep(arr(p, "views").length()))
            if (p.has("ed")) s.append("e").append((p.optDouble("ed") * 1000).toLong())
            s.append("z").append(hid).append(";")
        }
        return Presence.wireTag(s.toString().toByteArray(Charsets.UTF_8))
    }
    private val refused by lazy { Presence.wireTag("0r".toByteArray()) }
    /** MY WALL'S VERSION FOR ONE VISITOR (iOS spokenVersion 534-540): one the rule of sight leaves out hears what an empty wall says. */
    fun spokenVersion(peer: String): String {
        synchronized(lock) { ensure() }
        if (!WallRule.byRule(peer, WallRule.Act.SEE)) return refused
        val bit = if (WallRule.byRule(peer, WallRule.Act.WRITE)) "w" else "r"
        return Presence.wireTag((versionKept + bit).toByteArray(Charsets.UTF_8))
    }
    /** One who hides their presence carries the wall only right after an act of their own (the critic's N6). */
    fun renewVersion(own: Boolean = false) {
        synchronized(lock) { ensure(); versionKept = postsTag() }
        changed()
        if (own || Presence.sharing) schedulePush()
    }

    // ── a wall kept for contacts follows the book ──
    @Volatile private var following = false
    private var bookKept: Set<String>? = null
    private var bookReading = false
    /**
     * A WALL KEPT FOR CONTACTS FOLLOWS THE BOOK (iOS MTNameBook.invalidateContacts, MontanaNameBook.swift:336-345 at 2155, the critic
     * 25.09): one taken out of the book is carried the empty page, one put in it the page -- the push reads the rule anew at every
     * change of the book. The book is the contacts' page (WallRule.byRule CONTACTS), read off the main thread -- one reading on its
     * way at a time -- and only while a rule of my wall reads it.
     */
    private val bookMoved: () -> Unit = {
        if (WallRule.current(WallRule.Act.SEE) != WallRule.Rule.CONTACTS && WallRule.current(WallRule.Act.WRITE) != WallRule.Rule.CONTACTS) {
            synchronized(lock) { bookKept = null }
        } else if (synchronized(lock) { !bookReading.also { bookReading = true } }) Thread {
            synchronized(lock) { bookReading = false }
            val now = Book.all().filter { it.shown.isNotBlank() && !Groups.isKey(it.ref) }.map { it.ref }.toSet()
            val moved = synchronized(lock) { (bookKept != now).also { bookKept = now } }
            if (moved) renewVersion(own = true)
        }.start()
    }

    // ── the owner carries the wall ──
    /** A correspondent spoke the wall — a word of it: from now on the owner may carry the page to them. */
    fun learnCap(ref: String) {
        if (ref.isEmpty() || Groups.isKey(ref)) return
        val fresh = synchronized(lock) { ensure(); cap.add(ref).also { if (it) write() } }
        if (fresh && Presence.sharing) schedulePush()
    }
    @Volatile private var pushGen = 0
    /** Half a second folds a burst of edits into one page, then every correspondent a few frames apart (iOS schedulePush 640-648): only the last ask of a burst runs. */
    fun schedulePush() {
        val gen = synchronized(lock) { ++pushGen }
        MainThread.later(500, Runnable { if (gen == pushGen) Thread { pushDue() }.start() })
    }
    private fun pushDue() {
        val (latest, withdrawn) = synchronized(lock) {
            ensure()
            val l = Book.all().map { it.ref }.filter { it in cap }.take(PUSH_TO)
            // A WITHDRAWN SIGHT REACHES EVERYONE WHO SAW (the critic's N4): the empty page, so no old post stays with them
            val w = sent.filter { it.value != refused && !WallRule.byRule(it.key, WallRule.Act.SEE) }.keys
            l to w
        }
        val due = latest + withdrawn.filter { it !in latest }
        var n = 0
        for (conv in due) {
            if (Book.secret(conv) == null) continue
            val v = spokenVersion(conv)
            val go = synchronized(lock) { conv !in pushing && sent[conv] != v && !onItsWay(conv, v) && pushing.add(conv) }
            if (!go) continue
            MainThread.later(150L * n++, Runnable {
                Thread {
                    synchronized(lock) { pushing.remove(conv) }
                    val v2 = spokenVersion(conv)
                    if (synchronized(lock) { sent[conv] != v2 && !onItsWay(conv, v2) }) sendPage(conv, v2)
                }.start()
            })
        }
    }
    /** The same page already stands in the queue for them, handed less than half an hour ago. */
    private fun onItsWay(conv: String, v: String): Boolean = inFlight[conv]?.let { it.first == v && System.currentTimeMillis() - it.second < 1_800_000L } == true

    /**
     * THE ONE PAGE THIS OWNER SENDS (iOS sendPage 683-690): only one who may see may write; the page is «sent» at its receipt; a
     * visitor gets the counts and their own marks, the latest comments, and a hidden comment's words are not carried.
     */
    private fun sendPage(conv: String, v: String) {
        val sees = WallRule.admits(conv, WallRule.Act.SEE)
        val ps = JSONArray()
        if (sees) synchronized(lock) { ensure(); ordered().take(PAGE_SIZE).forEach { ps.put(seen(it, conv, conceal = true)) } }
        val word = JSONObject().put("t", "page").put("w", sees && WallRule.admits(conv, WallRule.Act.WRITE)).put("ps", ps).put("v", v)
        val mid = Board.sendWord(conv, word) ?: return
        synchronized(lock) { inFlight[conv] = Triple(v, System.currentTimeMillis(), mid); answeredAt[conv] = System.currentTimeMillis() }
        Log.d("Montana", "wall_page posts=" + ps.length())
    }
    /** The receipt of a page letter: the version it carried is the one that visitor now holds (iOS delivered 692-701). */
    fun delivered(ref: String, mid: String) {
        synchronized(lock) {
            val f = inFlight[ref] ?: return
            if (f.third != mid) return
            sent[ref] = f.first
            inFlight.remove(ref)
            write()
        }
    }
    /** An ask: one answer to one correspondent in thirty seconds (the critic's P6) — the page as it stands, or the empty one. */
    fun answer(ref: String) {
        val now = System.currentTimeMillis()
        synchronized(lock) { if (now - (answeredAt[ref] ?: 0L) < 30_000L) return; answeredAt[ref] = now }
        sendPage(ref, spokenVersion(ref))
    }

    /** A post as a visitor sees it: the counts and the visitor's own marks, no reference of anybody (iOS seen 758-769, shown 773-780). */
    private fun seen(p: JSONObject, by: String, conceal: Boolean): JSONObject {
        val cs = arr(p, "comments")
        val from = if (conceal) maxOf(0, cs.length() - COMMENTS_SHOWN) else 0
        val shown = JSONArray()
        for (i in from until cs.length()) {
            val c = cs.optJSONObject(i) ?: continue
            val x = JSONObject(c.toString())
            x.remove("ref")
            if (by.isNotEmpty() && c.optString("ref", "-") == by) x.put("m", true) else x.remove("m")
            if (c.has("ref") && c.optString("ref") == "") x.put("o", true) else x.remove("o")
            if (conceal && c.optBoolean("hid")) x.put("text", "")
            shown.put(x)
        }
        val author = p.optString("author")
        val x = JSONObject().put("id", p.optString("id")).put("byName", p.optString("byName")).put("byGlyph", p.optString("byGlyph"))
            .put("at", p.optDouble("at")).put("text", p.optString("text")).put("media", arr(p, "media")).put("pinned", p.optBoolean("pinned"))
            .put("keepers", arr(p, "keepers").length()).put("likes", arr(p, "likes").length()).put("downloads", arr(p, "downloads").length())
            .put("reposts", arr(p, "reposts").length()).put("comments", shown).put("commentCount", cs.length())
            .put("liked", has(arr(p, "likes"), by)).put("kept", has(arr(p, "keepers"), by)).put("reposted", has(arr(p, "reposts"), by))
            .put("mine", author == by).put("views", arr(p, "views").length())
        p.optString("from").takeIf { it.isNotEmpty() }?.let { x.put("from", it) }
        if (!(author.isEmpty() && !p.has("from"))) p.optString("face").takeIf { it.isNotEmpty() }?.let { x.put("face", it) }
        if (author.isEmpty() && (!p.has("from") || p.optString("srcBy", "-") == "")) x.put("own", true)
        p.optString("lp").takeIf { it.isNotEmpty() }?.let { x.put("lp", it) }
        if (p.has("n")) x.put("n", p.optInt("n"))
        return x
    }

    // ── the words of visitors (iOS apply 810-972, the owner's side) ──
    /** A word of my wall from a correspondent: their post, their marks, their comment, their view. */
    fun heard(ref: String, w: JSONObject) {
        val now = System.currentTimeMillis() / 1000.0
        when (w.optString("t")) {
            "post" -> takePost(ref, w, now)
            "like" -> if (WallRule.admits(ref, WallRule.Act.SEE)) mutate(w.optString("id")) { toggle(it, "likes", ref, w.optBoolean("on", true)) }
            "keep" -> if (WallRule.admits(ref, WallRule.Act.SEE)) mutate(w.optString("id")) { toggle(it, "keepers", ref, w.optBoolean("on", true)) }
            "dl" -> if (WallRule.admits(ref, WallRule.Act.SEE)) mutate(w.optString("id")) { toggle(it, "downloads", ref, true) }
            "rp" -> if (WallRule.admits(ref, WallRule.Act.SEE)) mutate(w.optString("id")) { toggle(it, "reposts", ref, true) }
            // A POST SEEN: a person counts once on a post, its writer never, and nobody is shown who (iOS 899-909)
            "view" -> if (WallRule.admits(ref, WallRule.Act.SEE)) {
                val vs = w.optJSONArray("vs") ?: JSONArray()
                var moved = false
                synchronized(lock) {
                    ensure()
                    for (i in 0 until minOf(vs.length(), PAGE_SIZE)) {
                        val p = mine.firstOrNull { it.optString("id") == vs.optString(i) } ?: continue
                        if (p.optString("author") == ref || has(arr(p, "views"), ref)) continue
                        arr(p, "views").put(ref); moved = true
                    }
                    if (moved) write()
                }
                if (moved) renewVersion()
            }
            "cmt" -> takeComment(ref, w, now)
            // ONLY THE WALL'S OWNER TAKES A POST OFF THEIR WALL: a writer's «del» says only that their phone no longer keeps its files
            "del" -> mutate(w.optString("id")) { p -> if (has(arr(p, "keepers"), ref)) toggle(p, "keepers", ref, false) }
            // A POST'S FILES GONE FROM THE NODE (iOS apply 961-963): a visitor found them gone -- I lay them again, and I ask its keepers
            "gone" -> w.optString("id").takeIf { it.isNotEmpty() }?.let { reseed(it) }
            else -> {}   // «hi» is the proof alone; a shape from a newer build is buried in silence
        }
    }
    private fun takePost(ref: String, w: JSONObject, now: Double) {
        val id = w.optString("id").take(64)
        if (id.isEmpty()) return
        if (!WallRule.admits(ref, WallRule.Act.WRITE) || !WallRule.admits(ref, WallRule.Act.SEE)) {
            Board.sendWord(ref, JSONObject().put("t", "no").put("id", id)); Log.d("Montana", "wall_refused rule=" + WallRule.current(WallRule.Act.WRITE).raw); return
        }
        val name = w.optString("bn").take(64).ifEmpty { Book.chat(ref)?.shown?.ifBlank { null } ?: Book.ctx.getString(R.string.wall_someone) }
        val glyph = w.optString("bg").take(8).ifEmpty { name.take(1).uppercase() }
        val post = JSONObject().put("id", id).put("author", ref).put("byName", name).put("byGlyph", glyph)
            .put("at", minOf(w.optDouble("at", now), now)).put("text", w.optString("tx").take(TEXT_LIMIT)).put("media", cleanMedia(w.optJSONArray("md")))
            .put("pinned", false).put("keepers", JSONArray().put(ref)).put("likes", JSONArray()).put("downloads", JSONArray())
            .put("reposts", JSONArray()).put("comments", JSONArray())
        w.optString("fc").takeIf { it.isNotEmpty() && it.length <= FACE_LIMIT }?.let { post.put("face", it) }
        w.optString("lp").takeIf { 2 < it.length && it.toByteArray().size < 80_001 }?.let { post.put("lp", it) }
        val refuse = synchronized(lock) {
            ensure()
            when {
                mine.any { it.optString("id") == id } -> return
                POSTS_PER_WRITER <= mine.count { it.optString("author") == ref } || WALL_LIMIT <= mine.size -> true
                else -> { mine.add(post); false }
            }
        }
        if (refuse) { Board.sendWord(ref, JSONObject().put("t", "no").put("id", id)); Log.d("Montana", "wall_refused full"); return }
        saveMine()
        // THE OWNER'S ROW IS BORN AS THE POST IS TAKEN ONTO THE WALL (iOS apply «post», MontanaBoard.swift:835-836 at 2155): once -- a post
        // the wall holds already returned above
        Board.cardRow(ref, id, w.optString("tx"), post.optJSONArray("media")?.optJSONObject(0)?.optString("kind"), mine = false)
    }
    private fun takeComment(ref: String, w: JSONObject, now: Double) {
        if (!WallRule.admits(ref, WallRule.Act.SEE) || !WallRule.admits(ref, WallRule.Act.WRITE)) return
        val text = w.optString("tx").trim()
        if (text.isEmpty()) return
        val name = w.optString("bn").take(64).ifEmpty { Book.chat(ref)?.shown?.ifBlank { null } ?: Book.ctx.getString(R.string.wall_someone) }
        val c = JSONObject().put("id", w.optString("cid").ifEmpty { java.util.UUID.randomUUID().toString().uppercase() }).put("by", name)
            .put("glyph", w.optString("bg").take(8).ifEmpty { name.take(1).uppercase() }).put("text", text.take(COMMENT_LIMIT))
            .put("at", minOf(w.optDouble("at", now), now)).put("ref", ref)
        w.optString("fc").takeIf { it.isNotEmpty() && it.length <= FACE_LIMIT }?.let { c.put("fc", it) }
        w.optString("hh").takeIf { it.isNotEmpty() }?.let { c.put("h", it) }
        w.optString("pv").takeIf { it.isNotEmpty() }?.let { c.put("pv", it) }
        mutate(w.optString("id")) { p -> chain(p, c) }
        // THE COMMENTER SEES EVERY COMMENT: a comment is answered as an ask is — with the page as it stands
        answer(ref)
    }
    /** A comment joins its post's chain once by its name; one that came unsealed is sealed after the last seal the post holds. */
    private fun chain(p: JSONObject, c: JSONObject) {
        val cs = arr(p, "comments")
        if ((0 until cs.length()).any { cs.optJSONObject(it)?.optString("id") == c.optString("id") }) return
        if (!c.has("h")) {
            val prev = cs.optJSONObject(cs.length() - 1)?.optString("h")?.ifEmpty { null } ?: ZERO_HASH
            c.put("pv", prev).put("h", Board.seal(c.optString("id"), c.optDouble("at"), prev, c.optString("text")))
        }
        cs.put(c)
    }
    private fun cleanMedia(ms: JSONArray?): JSONArray {
        val out = JSONArray()
        if (ms == null) return out
        for (i in 0 until minOf(ms.length(), MEDIA_LIMIT)) {
            val m = ms.optJSONObject(i) ?: continue
            val y = JSONObject().put("kind", m.optString("kind")).put("name", m.optString("name").take(120))
                .put("ext", m.optString("ext").take(8).filter { it.isLetterOrDigit() }).put("size", m.optLong("size"))
                .put("key", m.optString("key")).put("chunks", m.optJSONArray("chunks") ?: JSONArray())
            m.optString("thumb").takeIf { i < 4 && it.isNotEmpty() && it.length <= THUMB_LIMIT }?.let { y.put("thumb", it) }
            if (m.has("dur")) y.put("dur", m.optDouble("dur"))
            if (m.optString("kind") == "img" || m.optString("kind") == "vid") m.optJSONObject("fr")?.let { y.put("fr", it) }
            out.put(y)
        }
        return out
    }
    private fun mutate(id: String, own: Boolean = false, change: (JSONObject) -> Unit) {
        val hit = synchronized(lock) { ensure(); mine.firstOrNull { it.optString("id") == id }?.also(change) } ?: return
        saveMine(own)
    }
    /** One write a moment: the post numbers given, the record sealed, the version renewed (iOS saveMine 445-448). */
    private fun saveMine(own: Boolean = false) {
        synchronized(lock) { numberMissing(); write() }
        renewVersion(own)
    }
    /** THE POST'S NUMBER ON ITS WALL (the author's word 02.10): given once, the next after the highest, in the order of birth. */
    private fun numberMissing(): Boolean {
        var top = mine.maxOfOrNull { it.optInt("n", 0) } ?: 0
        var moved = false
        for (p in mine.sortedBy { it.optDouble("at") }) if (!p.has("n")) { top++; p.put("n", top); moved = true }
        return moved
    }
    private fun sealMissing(): Boolean {
        var moved = false
        for (p in mine) {
            val cs = arr(p, "comments")
            var prev = ZERO_HASH
            for (i in 0 until cs.length()) {
                val c = cs.optJSONObject(i) ?: continue
                if (!c.has("h")) { c.put("pv", prev).put("h", Board.seal(c.optString("id"), c.optDouble("at"), prev, c.optString("text"))); moved = true }
                prev = c.optString("h").ifEmpty { prev }
            }
        }
        return moved
    }

    // ── the owner's own hand ──
    /** My wall as I see it: every post, the pinned first, newest by its chain. */
    fun posts(): List<JSONObject> = synchronized(lock) { ensure(); ordered().map { seen(it, "", conceal = false) } }
    fun post(id: String): JSONObject? = synchronized(lock) { ensure(); mine.firstOrNull { it.optString("id") == id }?.let { seen(it, "", conceal = false) } }
    /** The correspondents whose build speaks the wall (iOS cap): the visitor's sweep asks for the walls among them never seen (Board.sweep). */
    fun speakers(): List<String> = synchronized(lock) { ensure(); cap.toList() }
    /** WHOSE POST ON MY WALL (iOS writer(of:on:), MontanaBoard.swift:2142-2149 at 2155): "" -- mine, a reference -- its writer's; null --
     * no post of that name, or a repost whose writer this phone was not told. */
    fun writerOf(id: String): String? = synchronized(lock) {
        ensure()
        mine.firstOrNull { it.optString("id") == id }?.let { p -> if (p.has("from")) p.optString("srcBy", "-").takeIf { it != "-" } else p.optString("author") }
    }
    /** WHO WROTE A COMMENT ON MY WALL (iOS commenter, MontanaBoard.swift:2199-2202 at 2155): "" -- I did, a reference -- its writer's. */
    fun commenterOf(postId: String, cid: String): String? = synchronized(lock) {
        ensure()
        val cs = mine.firstOrNull { it.optString("id") == postId }?.optJSONArray("comments")
        (0 until (cs?.length() ?: 0)).mapNotNull { cs?.optJSONObject(it) }.firstOrNull { it.optString("id") == cid && it.has("ref") }?.optString("ref")
    }
    // ── a post on its way: its files on the node, then the post (iOS begin, publish, lay 1764-1932) ──
    class Attachment(val file: File, val kind: String, val name: String, val ext: String)
    /** A post on its way as its bar reads it (iOS MTBoardOutgoing 282-298): the bytes the node confirmed of all its files, and the wall
     * it goes to -- "" my own. */
    class Going(val id: String, val post: JSONObject, val total: Long, val done: Long, val failed: Boolean, val wall: String = "") {
        val share: Double get() = if (total == 0L) 1.0 else minOf(1.0, done.toDouble() / total)
    }
    private val going = LinkedHashMap<String, JSONObject>()   // id -> the post as it will stand, its files' sizes, the pieces confirmed
    private val publishing = HashSet<String>()
    private fun goingFile() = File(File(Book.ctx.filesDir, "board").apply { mkdirs() }, "going.sealed")
    private fun writeGoing() {
        val sealedBytes = DeviceVault.seal(JSONArray(going.values.toList()).toString().toByteArray(Charsets.UTF_8)) ?: return
        val part = File(goingFile().path + ".part")
        runCatching { part.writeBytes(sealedBytes); part.renameTo(goingFile()) }
    }
    /** The files of my own posts: this phone is each post's first peer (iOS MontanaMediaStore under the post's names). */
    private fun store() = storeDir(Book.ctx).apply { mkdirs() }
    /** The folder of the wall's files, for the app's own door to them (MediaProvider): a post's document opens and goes out as a chat's does. */
    fun storeDir(c: android.content.Context) = File(File(c.filesDir, "board"), "files")
    private fun fileName(pid: String, i: Int, ext: String) = "wall_" + pid + "_" + i + (if (ext.isEmpty()) "" else "." + ext)   // iOS fileName 497-499
    fun ownFile(name: String): File? = File(store(), name).takeIf { it.exists() }
    /** The one store of a post's files on this phone -- my posts' and the posts I keep (iOS MontanaMediaStore under fileName 497-499). */
    fun storeFile(name: String): File = File(store(), name)

    /**
     * A NEW POST, AT ONCE AS IT WILL STAND (iOS begin 1768-1818): the files move into this phone's store under the post's own names,
     * a picture in its frame -- its own shape whole -- with its poster, a track's or a film's length; the post stands on its way with
     * my name and the words, and outlives the run; written on a person's page (wall, their reference) it goes to their wall, my small
     * face over it. null: nothing to post, or a file could not be taken.
     */
    fun begin(text: String, atts: List<Attachment>, wall: String = ""): String? {
        val t = text.trim().take(TEXT_LIMIT)
        if (t.isEmpty() && atts.isEmpty()) return null
        val pid = "p" + java.util.UUID.randomUUID().toString().replace("-", "").lowercase().take(24)
        val media = JSONArray()
        val sizes = JSONArray()
        val confirmed = JSONArray()
        for ((i, a) in atts.take(MEDIA_LIMIT).withIndex()) {
            val f = File(store(), fileName(pid, i, a.ext))
            if (!a.file.renameTo(f) && runCatching { a.file.copyTo(f, overwrite = true) }.isFailure) {
                Log.w("Montana", "wall_write FAIL file=" + i + " kind=" + a.kind + " taking")
                return null
            }
            val m = JSONObject().put("kind", a.kind).put("name", a.name.take(120)).put("ext", a.ext).put("size", f.length())
                .put("key", "").put("chunks", JSONArray())
            if (a.kind == "img" || a.kind == "vid") {
                val fr = Media.preview(Book.ctx, f, a.kind, 256)?.let { b -> WallFiles.ownFrame(b.width, b.height) }
                fr?.let { m.put("fr", it) }
                WallFiles.poster(Book.ctx, f, a.kind, fr)?.let { m.put("thumb", it) }
            }
            if (a.kind == "vid" || a.kind == "aud") WallFiles.duration(f)?.let { m.put("dur", it) }
            media.put(m); sizes.put(f.length()); confirmed.put(0)
        }
        val name = Prefs.userName.trim()
        // THE CARD RIDES WITH THE POST FROM THE START (iOS begin, MontanaBoard.swift:1772-1818 at 2155, atom 5a84afb1f68f): the
        // first link of the words, read before the post stands on its way, so a YouTube address shows its picture at once.
        val lp = LinkPreview.wallCard(t)?.json()
        val post = JSONObject().put("id", pid).put("author", "").put("byName", name).put("byGlyph", name.take(1).uppercase())
            .put("at", System.currentTimeMillis() / 1000.0).put("text", t).put("media", media).put("pinned", false)
            .put("keepers", JSONArray().put("")).put("likes", JSONArray()).put("downloads", JSONArray()).put("reposts", JSONArray())
            .put("comments", JSONArray())
        lp?.let { post.put("lp", it) }
        // MY FACE OVER A POST ON ANOTHER'S WALL (iOS fresh, MontanaBoard.swift:1821-1826 at 2155: face: wall == nil ? nil : myFace())
        if (wall.isNotEmpty()) Board.myFace()?.let { post.put("face", it) }
        synchronized(lock) {
            ensure()
            going[pid] = JSONObject().put("id", pid).put("wall", wall).put("post", post).put("sizes", sizes).put("confirmed", confirmed).put("failed", false)
            writeGoing()
        }
        changed()
        return pid
    }

    /**
     * THE FILES ON THE NODE, THEN THE POST (iOS publish and lay 1828-1901): one lay a post at a time; each file is sealed under its
     * letter «wall-POST-N» and laid on the node, its pieces counted as the node confirms them -- the post's bar reads that count -- and
     * when every file lies there the post joins my wall. A file the node did not take leaves the post on its way, said so.
     */
    fun publish(pid: String): Boolean {
        val o = synchronized(lock) {
            ensure()
            val g = going[pid] ?: return false
            if (!publishing.add(pid)) return false
            g.put("failed", false)
        }
        changed()
        try {
            val post = o.getJSONObject("post")
            val ms = post.optJSONArray("media") ?: JSONArray()
            val laid = JSONArray()
            for (i in 0 until ms.length()) {
                val m = ms.getJSONObject(i)
                val f = File(store(), fileName(pid, i, m.optString("ext")))
                val sealed = if (f.exists()) Media.layFile(f, "wall-" + pid + "-" + i) { n -> confirmed(pid, i, n) } else null
                if (sealed == null) {
                    Log.w("Montana", "wall_write FAIL file=" + i + " kind=" + m.optString("kind"))
                    synchronized(lock) { o.put("failed", true); if (going.containsKey(pid)) writeGoing() }
                    changed()
                    return false
                }
                confirmed(pid, i, sealed.second.length())
                laid.put(JSONObject(m.toString()).put("key", sealed.first).put("chunks", sealed.second))
            }
            synchronized(lock) {
                if (going.remove(pid) == null) return false   // let go by its writer meanwhile
                writeGoing()
                post.put("media", laid)
                if (o.optString("wall").isEmpty()) mine.add(post)
            }
            val wall = o.optString("wall")
            if (wall.isNotEmpty()) {
                // MY POST ON ANOTHER'S WALL (iOS lay, MontanaBoard.swift:1873-1897 at 2155): it stands there as a visitor's own post --
                // mine, kept here, my small face over it, no views counted by me -- and its word carries the words, the files and the
                // face (1889: MTBoardWord(t: "post", id, at, tx, md, bn, bg, fc, lp))
                val shown = seen(post, "", conceal = false).apply { remove("own"); remove("views") }
                post.optString("face").takeIf { it.isNotEmpty() }?.let { shown.put("face", it) }
                val word = JSONObject().put("t", "post").put("id", pid).put("at", post.optDouble("at")).put("tx", post.optString("text"))
                    .put("md", laid).put("bn", post.optString("byName")).put("bg", post.optString("byGlyph"))
                post.optString("face").takeIf { it.isNotEmpty() }?.let { word.put("fc", it) }
                post.optString("lp").takeIf { it.isNotEmpty() }?.let { word.put("lp", it) }   // the card rides to the wall's owner too
                Board.wrote(wall, shown, word)
                changed()
                Log.d("Montana", "wall_write id=" + pid.take(10) + " files=" + laid.length() + " wall=theirs")
                return true
            }
            saveMine(own = true)
            Log.d("Montana", "wall_write id=" + pid.take(10) + " files=" + laid.length() + " wall=mine")
            return true
        } finally {
            synchronized(lock) { publishing.remove(pid) }
        }
    }
    /** The node confirmed a piece more of a post's file. */
    private fun confirmed(pid: String, i: Int, n: Int) {
        synchronized(lock) {
            val c = going[pid]?.optJSONArray("confirmed") ?: return
            if (c.length() <= i || n <= c.optInt(i)) return
            c.put(i, n)
        }
        changed()
    }
    /** A post on its way let go by its writer (iOS discard 1909): its files go with it. */
    fun discard(pid: String) {
        val g = synchronized(lock) { ensure(); going.remove(pid)?.also { writeGoing() } } ?: return
        val ms = g.optJSONObject("post")?.optJSONArray("media") ?: JSONArray()
        for (i in 0 until ms.length()) File(store(), fileName(pid, i, ms.optJSONObject(i)?.optString("ext") ?: "")).delete()
        changed()
    }
    /** The posts on their way to a wall -- "" my own --, newest first, each as it will stand (iOS sending(on:) 1919-1921). */
    fun sending(wall: String = ""): List<Going> = synchronized(lock) {
        ensure()
        going.values.filter { it.optString("wall") == wall }.map { g ->
            val sizes = g.optJSONArray("sizes") ?: JSONArray()
            val conf = g.optJSONArray("confirmed") ?: JSONArray()
            var total = 0L
            var done = 0L
            for (i in 0 until sizes.length()) { val s = sizes.optLong(i); total += s; done += minOf(s, conf.optLong(i) * Media.CHUNK) }
            // on its way to another's wall it stands as it will there: a visitor's own post, my small face over it (iOS fresh 1821-1826)
            val shown = seen(g.getJSONObject("post"), "", conceal = false)
            if (wall.isNotEmpty()) {
                shown.remove("own"); shown.remove("views")
                g.getJSONObject("post").optString("face").takeIf { it.isNotEmpty() }?.let { shown.put("face", it) }
            }
            Going(g.optString("id"), shown, total, done, g.optBoolean("failed"), wall)
        }.sortedByDescending { it.post.optDouble("at") }
    }
    /** EVERY POST ON ITS WAY, TO ANY WALL, NEWEST FIRST (iOS MTFeedTabView's going, board.outgoing.values, MontanaBoardViews.swift:2875
     * at 2155): the feed stands them over its posts. */
    fun sendingAll(): List<Going> = synchronized(lock) { ensure(); going.values.map { it.optString("wall") }.toSet() }.flatMap { sending(it) }
        .sortedByDescending { it.post.optDouble("at") }
    /**
     * A POST ON ITS WAY GOES ON BY ITSELF (iOS roadBack 1922-1932): every post the node did not take whole, or one a run died under,
     * is laid again when the app comes to the screen; never twice at once. The person's own try again stands as it was.
     */
    fun roadBack(why: String) {
        val due = synchronized(lock) { ensure(); going.values.filter { it.optBoolean("failed") && it.optString("id") !in publishing }.map { it.optString("id") } }
        if (due.isEmpty()) return
        Log.d("Montana", "wall_retry why=" + why + " n=" + due.size)
        for (pid in due) Thread { publish(pid) }.start()
    }
    fun pin(id: String) = mutate(id, own = true) { it.put("pinned", !it.optBoolean("pinned")) }
    /**
     * THE WORDS OF MY OWN POST, CHANGED (iOS MTBoard.edit, MontanaBoard.swift:1535-1555 at 2155, the author's word 30.09): only on my own
     * wall and only the words -- a file keeps the name its place gave it at birth, a repost keeps its writer's words. The edit moves the
     * wall's version (postsTag «e»), so the next page carries the new words to everyone who holds it; no new word rides the wire. A link
     * card whose address the words no longer lead with goes with them (1545-1547). False: nothing to change.
     */
    fun edit(id: String, words: String): Boolean {
        val t = words.trim().take(TEXT_LIMIT)
        var next: String? = null
        var had: String? = null
        synchronized(lock) {
            ensure()
            val p = mine.firstOrNull { it.optString("id") == id } ?: return false
            if (p.optString("author").isNotEmpty() || p.has("from") || t == p.optString("text") || (t.isEmpty() && arr(p, "media").length() == 0)) return false
            p.put("text", t).put("ed", System.currentTimeMillis() / 1000.0)
            next = LinkPreview.webURLs(t).firstOrNull()
            had = LinkCard.parse(p.optString("lp"))?.u
            if (next != had) p.remove("lp")
        }
        saveMine(own = true)
        // THE WORDS CHANGED THE LINK: THE CARD IS READ AGAIN (iOS attachCard, MontanaBoard.swift:1560-1569 at 2155, atom
        // 5a84afb1f68f): the wall's version moves a second time once the new link's card comes, off this thread.
        if (next != null && next != had) { val pid = id; val url = next!!; Thread { attachCard(pid, url) }.start() }
        Log.d("Montana", "wall_edit id=" + id.take(10) + " chars=" + t.length)
        return true
    }
    /** The card of the link the words now carry, read again and laid on the post (iOS attachCard, MontanaBoard.swift:1560-1569 at
     * 2155, atom 5a84afb1f68f): the version moves with it, so the next page carries the new card to everyone who holds it; a post
     * edited again before this read lands keeps the newer words' own link. */
    private fun attachCard(id: String, url: String) {
        val card = LinkPreview.wallCard(url)?.json() ?: return
        synchronized(lock) {
            ensure()
            val p = mine.firstOrNull { it.optString("id") == id } ?: return
            if (LinkPreview.webURLs(p.optString("text")).firstOrNull() != url) return
            p.put("lp", card).put("ed", System.currentTimeMillis() / 1000.0)
        }
        saveMine(own = true)
    }
    fun like(id: String) = mutate(id, own = true) { toggle(it, "likes", "", !has(arr(it, "likes"), "")) }
    /** A REPOST STANDS ON MY WALL (iOS repost, MontanaBoard.swift:1656-1661 at 2155): once by its name; false -- it stands already. */
    fun repost(post: JSONObject): Boolean {
        val id = post.optString("id")
        synchronized(lock) {
            ensure()
            if (mine.any { it.optString("id") == id }) return false
            mine.add(post)
        }
        saveMine(own = true)
        return true
    }
    /** My own comment on my own post: sealed after the last seal the post holds. */
    fun comment(id: String, text: String) {
        val t = text.trim().take(COMMENT_LIMIT)
        if (t.isEmpty()) return
        val name = Prefs.userName.trim()
        val c = JSONObject().put("id", java.util.UUID.randomUUID().toString().uppercase()).put("by", name).put("glyph", name.take(1).uppercase())
            .put("text", t).put("at", System.currentTimeMillis() / 1000.0).put("ref", "")
        mutate(id, own = true) { chain(it, c) }
    }
    /** OFF MY WALL, BY ITS OWNER ALONE (iOS remove 1571-1584): its writer is told they need not keep it for me. */
    fun remove(id: String) {
        val author = synchronized(lock) {
            ensure()
            val p = mine.firstOrNull { it.optString("id") == id } ?: return
            mine.remove(p)
            p.optString("author")
        }
        if (author.isNotEmpty()) Board.sendWord(author, JSONObject().put("t", "drop").put("id", id))
        saveMine(own = true)
    }
    /**
     * MY OWN MARK ON A POST OF MY WALL, ONCE (iOS becomePeer 1603-1607, unkeep 1625, noteDownloaded 1730): «keepers» -- this phone
     * keeps the post's files -- or «downloads»; a mark already as asked moves nothing.
     */
    fun ownMark(id: String, k: String, on: Boolean) {
        val moves = synchronized(lock) { ensure(); mine.firstOrNull { it.optString("id") == id }?.let { has(arr(it, k), "") != on } } ?: return
        if (moves) mutate(id, own = true) { toggle(it, k, "", on) }
    }
    /**
     * THE FILES OF A POST ON MY WALL ARE GONE FROM THE NODE (iOS reseed 1744-1751): I lay them again under the post's own key if I
     * keep them, and I ask every keeper of the post to lay theirs.
     */
    fun reseed(id: String) {
        val p = synchronized(lock) { ensure(); mine.firstOrNull { it.optString("id") == id }?.let { JSONObject(it.toString()) } } ?: return
        val keepers = arr(p, "keepers")
        if (has(keepers, "") || p.optString("author").isEmpty()) { val ms = arr(p, "media"); Thread { Board.seedFiles(id, ms) }.start() }
        for (i in 0 until keepers.length()) keepers.optString(i).takeIf { it.isNotEmpty() }?.let { Board.sendWord(it, JSONObject().put("t", "seed").put("id", id)) }
    }
}
