package quest.montana.app

import org.json.JSONArray
import org.json.JSONObject

/**
 * THE EYE UNDER A CHANNEL'S POST (iOS MTChannelViews, MontanaChannel 209-354, the reference's view counter): a post is born with one
 * view, its author's, and every person whose screen showed it adds one. No server counts. A subscriber's phone tells the owner which
 * posts its screen showed (Groups.tellSeen); the owner counts each subscriber's seat once per post and carries the numbers that moved
 * to every subscriber (Groups.tellCounts). The number is people, never openings: a seat is counted once, and a number only grows.
 */
object ChannelViews {
    private const val KEY = "channels.views"
    /** [I-14]: the newest posts a channel keeps numbers for, and the posts a subscriber remembers having told. */
    private const val POSTS_KEPT = 400
    private const val SAID_KEPT = 1_000
    private const val PEOPLE_LIMIT = 200   // iOS MTGroup.peopleLimit

    private val lock = Any()
    private var loaded = false
    /** The owner's: a channel's post and the seats that showed it. */
    private val seen = mutableMapOf<String, MutableMap<String, MutableList<String>>>()
    /** A subscriber's: a channel's post and the number its owner told. */
    private val told = mutableMapOf<String, MutableMap<String, Int>>()
    /** A subscriber's: the posts already told as shown. */
    private val said = mutableMapOf<String, MutableList<String>>()
    private val waiting = mutableMapOf<String, MutableSet<String>>()
    private val moved = mutableMapOf<String, MutableSet<String>>()
    private var telling = false
    private var counting = false
    private val listeners = mutableListOf<() -> Unit>()

    /** A number shown moved: the open channel's feed reads its rows again (iOS rev). */
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun ensure() {
        if (loaded) return
        loaded = true
        seen.clear(); told.clear(); said.clear()
        val raw = DeviceVault.get(KEY) ?: return
        runCatching {
            val o = JSONObject(String(raw, Charsets.UTF_8))
            o.optJSONObject("seen")?.let { s -> s.keys().forEach { k -> val page = s.getJSONObject(k); seen[k] = page.keys().asSequence().associateWith { l -> page.getJSONArray(l).let { a -> MutableList(a.length()) { a.getString(it) } } }.toMutableMap() } }
            o.optJSONObject("told")?.let { t -> t.keys().forEach { k -> val page = t.getJSONObject(k); told[k] = page.keys().asSequence().associateWith { page.optInt(it) }.toMutableMap() } }
            o.optJSONObject("said")?.let { s -> s.keys().forEach { k -> said[k] = s.getJSONArray(k).let { a -> MutableList(a.length()) { a.getString(it) } } } }
        }.onFailure { seen.clear(); told.clear(); said.clear() }
    }
    private fun save() {
        val o = JSONObject()
            .put("seen", JSONObject().apply { seen.forEach { (k, page) -> put(k, JSONObject().apply { page.forEach { (l, seats) -> put(l, JSONArray(seats)) } }) } })
            .put("told", JSONObject().apply { told.forEach { (k, page) -> put(k, JSONObject(page.toMap())) } })
            .put("said", JSONObject().apply { said.forEach { (k, list) -> put(k, JSONArray(list)) } })
        DeviceVault.set(KEY, o.toString().toByteArray(Charsets.UTF_8))
    }
    /** The person leaves: another person's channels are not this one's (iOS montanaSeedForgotten). */
    fun wipe() = synchronized(lock) { seen.clear(); told.clear(); said.clear(); waiting.clear(); moved.clear(); loaded = false; DeviceVault.delete(KEY) }

    /** A post's one name without its wire head: the same on the owner's phone and on every subscriber's (iOS letter). */
    private fun letter(m: Msg): String? = m.mid.removePrefix("mid:").takeIf { Groups.isLetterName(it) }
    /** The newest posts a page keeps: a name begins with its birth moment, so the oldest names go first (iOS trimmed). */
    private fun <V> trim(page: MutableMap<String, V>) {
        if (page.size <= POSTS_KEPT) return
        page.keys.sorted().take(page.size - POSTS_KEPT).forEach { page.remove(it) }
    }

    /**
     * The number under a post (iOS views): on the owner's phone its own count -- one, the author, and every seat that showed it; on a
     * subscriber's phone what the owner told, one until it is told.
     */
    fun views(m: Msg, key: String): Int {
        val l = letter(m) ?: return 1
        val owner = Groups.owns(key)   // asked before this book's lock: the groups' lock is never taken under it
        synchronized(lock) {
            ensure()
            return if (owner) 1 + (seen[key]?.get(l)?.size ?: 0) else maxOf(1, told[key]?.get(l) ?: 1)
        }
    }

    /**
     * A POST STOOD ON THIS SUBSCRIBER'S SCREEN (iOS shown, its row appeared in the feed): told to the owner once, a moment later
     * together with the others that appeared. «I saw your words» is a read receipt: with «Read receipts» off nothing is told and
     * nothing is kept to tell later (the critic's K-1).
     */
    fun shown(m: Msg, key: String) {
        if (!Prefs.bool("readReceiptsEnabled", true) || m.mine || !Groups.isChannel(key) || Groups.owns(key) || Groups.isOut(key)) return
        val l = letter(m) ?: return
        synchronized(lock) {
            ensure()
            if (said[key]?.contains(l) == true) return
            waiting.getOrPut(key) { mutableSetOf() }.add(l)
            if (telling) return
            telling = true
        }
        MainThread.later(1_500, Runnable { tell() })
    }
    private fun tell() {
        val batch = synchronized(lock) {
            telling = false
            if (!Prefs.bool("readReceiptsEnabled", true)) { waiting.clear(); return }   // turned off while they waited: let go untold
            waiting.mapValues { it.value.sorted() }
        }
        var any = false
        for ((key, list) in batch) {
            if (!Groups.tellSeen(list, key)) continue   // no pipe to the owner now: they wait for the next post shown
            synchronized(lock) {
                val s = said.getOrPut(key) { mutableListOf() }
                s.addAll(list)
                if (SAID_KEPT < s.size) repeat(s.size - SAID_KEPT) { s.removeAt(0) }
                waiting[key]?.removeAll(list.toSet())
                if (waiting[key]?.isEmpty() == true) waiting.remove(key)
            }
            any = true
        }
        if (any) synchronized(lock) { save() }
    }

    /** A subscriber's seat showed these posts of mine (their «vw», iOS saw): each seat counted once; the numbers that moved leave to
     *  every subscriber a few seconds later, in one word. */
    fun saw(letters: List<String>, seat: String, key: String) {
        synchronized(lock) {
            ensure()
            val page = seen.getOrPut(key) { mutableMapOf() }
            var grew = false
            for (l in letters) {
                val seats = page.getOrPut(l) { mutableListOf() }
                if (seat in seats || PEOPLE_LIMIT <= seats.size) continue
                seats.add(seat)
                moved.getOrPut(key) { mutableSetOf() }.add(l)
                grew = true
            }
            if (!grew) return
            trim(page)
            save()
            if (!counting) {
                counting = true
                MainThread.later(3_000, Runnable { count() })
            }
        }
        changed()
    }
    private fun count() {
        val batch = synchronized(lock) {
            counting = false
            val out = moved.mapValues { (key, ls) -> ls.sorted().takeLast(Groups.VIEWS_BATCH).associateWith { 1 + (seen[key]?.get(it)?.size ?: 0) } }
            moved.clear()
            out
        }
        for ((key, numbers) in batch) Groups.tellCounts(numbers, key)
    }
    /** The owner told the numbers (their «vc», iOS told): a number only grows, so a word that came late changes nothing. */
    fun told(numbers: Map<String, Int>, key: String) {
        synchronized(lock) {
            ensure()
            val page = told.getOrPut(key) { mutableMapOf() }
            var grew = false
            for ((l, n) in numbers) if ((page[l] ?: 0) < n) { page[l] = minOf(n, PEOPLE_LIMIT + 1); grew = true }
            if (!grew) return
            trim(page)
            save()
        }
        changed()
    }

    /** The reference's short count (iOS MTChannelPostLook.count): «999», «1.2K», «3M» -- the tenth shown only where it is not a zero. */
    fun short(n: Int): String {
        val dot = java.text.DecimalFormatSymbols.getInstance().decimalSeparator
        fun cut(unit: Int, mark: String): String { val tenth = (n % unit) / (unit / 10); return (n / unit).toString() + (if (tenth == 0) "" else "$dot$tenth") + mark }
        return when { 1_000_000 <= n -> cut(1_000_000, "M"); 1_000 <= n -> cut(1_000, "K"); else -> n.toString() }
    }
}
