package quest.montana.app

import org.json.JSONArray
import org.json.JSONObject

/**
 * THE EYE UNDER A CHANNEL'S POST (iOS MTChannelViews, MontanaChannel.swift:209-354): a post is born with one view, its author's, and
 * every person whose screen showed it adds one. No server counts. A subscriber's phone tells the owner which posts its screen showed
 * (Groups.tellSeen); the owner counts each subscriber's seat once per post and carries the numbers that moved to every subscriber
 * (Groups.tellCounts). The number is people, never openings: a seat is counted once, and a number only grows.
 */
object ChannelViews {
    /** The store's own name, iOS's (MontanaLocalVault «channels.views»): the owner's seats per post, the numbers told, the posts said. */
    private const val STORE = "channels.views"
    /** [I-14]: the newest posts a channel keeps numbers for, and the posts a subscriber remembers having told (iOS postsKept, saidKept). */
    private const val POSTS_KEPT = 400
    private const val SAID_KEPT = 1_000
    private const val PEOPLE_LIMIT = 200   // iOS MTGroup.peopleLimit

    private val lock = Any()
    private var loaded = false
    private val seen = HashMap<String, MutableMap<String, MutableList<String>>>()
    private val told = HashMap<String, MutableMap<String, Int>>()
    private val said = HashMap<String, MutableList<String>>()
    private val waiting = HashMap<String, MutableSet<String>>()
    private val moved = HashMap<String, MutableSet<String>>()
    private var telling = false
    private var counting = false

    private val listeners = mutableListOf<() -> Unit>()
    /** A number shown moved: the open channel's feed reads its rows again (iOS rev). */
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun load() {
        if (loaded) return
        loaded = true
        val o = DeviceVault.get(STORE)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: return
        o.optJSONObject("seen")?.let { s -> for (k in s.keys()) { val page = s.getJSONObject(k); seen[k] = page.keys().asSequence().associateWith { l -> page.getJSONArray(l).let { a -> MutableList(a.length()) { a.getString(it) } } }.toMutableMap() } }
        o.optJSONObject("told")?.let { t -> for (k in t.keys()) { val page = t.getJSONObject(k); told[k] = page.keys().asSequence().associateWith { page.optInt(it) }.toMutableMap() } }
        o.optJSONObject("said")?.let { s -> for (k in s.keys()) said[k] = s.getJSONArray(k).let { a -> MutableList(a.length()) { a.getString(it) } } }
    }
    private fun save() {
        val o = JSONObject()
            .put("seen", JSONObject().apply { for ((k, page) in seen) put(k, JSONObject().apply { for ((l, seats) in page) put(l, JSONArray(seats)) }) })
            .put("told", JSONObject().apply { for ((k, page) in told) put(k, JSONObject(page.toMap())) })
            .put("said", JSONObject().apply { for ((k, list) in said) put(k, JSONArray(list)) })
        DeviceVault.set(STORE, o.toString().toByteArray(Charsets.UTF_8))
    }
    /** The person leaves: their channels' numbers leave with them (iOS montanaSeedForgotten). */
    fun wipe() = synchronized(lock) { seen.clear(); told.clear(); said.clear(); waiting.clear(); moved.clear(); loaded = false; DeviceVault.delete(STORE) }

    /** A post's one name without its wire head: the same on the owner's phone and on every subscriber's (iOS letter). */
    private fun letter(m: Msg): String? = m.mid.removePrefix("mid:").takeIf { Groups.letterName(it) }
    /** The newest posts a page keeps: a name begins with its birth moment, so the oldest names go first (iOS trimmed). */
    private fun <V> trim(page: MutableMap<String, V>) {
        if (page.size <= POSTS_KEPT) return
        for (old in page.keys.sorted().take(page.size - POSTS_KEPT)) page.remove(old)
    }

    /**
     * The number under a post (iOS views): on the owner's phone its own count -- one, the author, and every seat that showed it; on a
     * subscriber's phone what the owner told, one until it is told.
     */
    fun views(m: Msg, key: String): Int {
        val l = letter(m) ?: return 1
        val owner = Groups.ownsChannel(key)   // asked before the store's lock: the groups' lock is never taken under it
        synchronized(lock) {
            load()
            return if (owner) 1 + (seen[key]?.get(l)?.size ?: 0) else maxOf(1, told[key]?.get(l) ?: 1)
        }
    }

    /**
     * A POST STOOD ON THIS SUBSCRIBER'S SCREEN (iOS shown): told to the owner once, a moment later together with the others that
     * appeared. «I saw your words» is a read receipt: with «Read receipts» off nothing is told and nothing is kept to tell later.
     */
    fun shown(m: Msg, key: String) {
        if (!Prefs.bool("readReceiptsEnabled", true) || m.mine || !Groups.isChannel(key) || Groups.ownsChannel(key) || Groups.isOut(key)) return
        val l = letter(m) ?: return
        synchronized(lock) {
            load()
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
        var told = false
        for ((key, list) in batch) {
            if (!Groups.tellSeen(list, key)) continue   // no pipe to the owner now: they wait for the next post shown
            synchronized(lock) {
                val s = said.getOrPut(key) { mutableListOf() }
                s.addAll(list)
                while (s.size > SAID_KEPT) s.removeAt(0)
                waiting.remove(key)
            }
            told = true
        }
        if (told) synchronized(lock) { save() }
    }

    /** A subscriber's seat showed these posts of mine (their «vw», iOS saw): each seat counted once; the numbers leave a few seconds later.
     *  `tell` false: a word the twin mirror brought -- counted here, the numbers told by the device that took it (Windows channel_saw). */
    fun saw(letters: List<String>, seat: String, key: String, tell: Boolean = true) {
        synchronized(lock) {
            load()
            val page = seen.getOrPut(key) { mutableMapOf() }
            var grew = false
            for (l in letters) {
                val seats = page.getOrPut(l) { mutableListOf() }
                if (seat in seats || seats.size >= PEOPLE_LIMIT) continue
                seats.add(seat)
                if (tell) moved.getOrPut(key) { mutableSetOf() }.add(l)
                grew = true
            }
            if (!grew) return
            trim(page)
            save()
            if (counting || !tell) { changed(); return }
            counting = true
        }
        changed()
        MainThread.later(3_000, Runnable { count() })
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
            load()
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
