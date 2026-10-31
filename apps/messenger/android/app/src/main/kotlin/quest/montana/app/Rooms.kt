package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * A GROUP'S LIVE ROOM AS THIS PHONE KNOWS IT (iOS MTGroupRoom, MTGroupRoom.swift 1-700): a voice or video chat of up to 13, or a
 * stream, told to the group by the group's own word «room» -- opened, invited, came in, went out, closed. No server holds a room:
 * a room of N is N-1 calls of two (iOS MTRoomPair). STAGE A here: the room is heard and shown -- the book of rooms (MTRoomSeen),
 * its bar over the group's chat and its mark in the list (MTRoomBook, MTRoomBar, MTRoomRowMark), its rows in the feed («started»,
 * «ended»). Coming in (the pairs over WebRTC, the room's screen) is the next stage; until then this phone is in no room.
 */
object Rooms {
    /** [I-14] The most people in one room at once (iOS capacity). */
    const val CAPACITY = 13
    /** A room no word renewed for this long is gone from the bars (iOS staleAfter): a living room says so every ten minutes. */
    private const val STALE_MS = 30 * 60 * 1000L
    /** The book of rooms, sealed on this device alone (iOS bookKey, MontanaLocalVault). */
    private const val BOOK_KEY = "mt.rooms.seen"
    private const val PUB_SIZE = 1184   // ML-KEM-768 public key (iOS MTRoomSeal.pubSize)

    /** A group's room as the group's words told it (iOS MTRoomSeen); moments in node milliseconds. */
    private class Seen(
        val id: String, val kind: String, val key: String, var owner: String, var video: Boolean,
        val people: MutableMap<String, Long>, val since: Long, var at: Long, var askedBy: String? = null,
        val keys: MutableMap<String, String> = mutableMapOf(),
    )
    /** A group's live room as the bar over its chat shows it (iOS MTRoomBrief). */
    data class Brief(val kind: String, val video: Boolean, val count: Int, val askedBy: String?, val mine: Boolean)

    private val lock = Any()
    private var seen: MutableMap<String, Seen>? = null
    @Volatile private var briefs: Map<String, Brief> = emptyMap()
    private val listeners = mutableListOf<() -> Unit>()

    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }

    /** The room living in a group's chat, if one does (iOS MTRoomBook.rooms[gid]). */
    fun brief(chat: String): Brief? {
        if (!Groups.isKey(chat)) return null
        book()
        return briefs[chat.removePrefix(Groups.key(""))]
    }

    private fun isRoomId(s: String) = s.length == 32 && s.all { it in '0'..'9' || it in 'a'..'f' }
    private fun isSeat(s: String) = s.isNotEmpty() && s.length <= 128 && s.all { it.isLetterOrDigit() }
    private fun fresh(s: Seen) = NodeClock.now() - s.at < STALE_MS
    /** The later of two to come in: the moment first, the seat for a tie (iOS later). */
    private fun later(a: Pair<Long, String>, b: Pair<Long, String>) = if (a.first != b.first) a.first > b.first else a.second > b.second
    /** The first in the room: it holds the control when the owner goes (iOS firstIn). */
    private fun firstIn(people: Map<String, Long>): String =
        people.entries.minWithOrNull { x, y -> if (later(x.value to x.key, y.value to y.key)) 1 else -1 }?.key ?: ""

    /**
     * A ROOM'S WORD FROM THE GROUP (iOS heard): its seat is already proven by the group's road. The book learns who is in; the
     * feed lays «started» once, the first time the room is seen here, and «ended» when its owner closes it.
     */
    fun heard(text: String, gid: String, seat: String) {
        val e = runCatching { JSONObject(text) }.getOrNull()
        val r = e?.optString("r").orEmpty()
        val kind = e?.optString("m").orEmpty()
        if (e == null || !isRoomId(r) || (kind != "call" && kind != "live")) { Log.i("Montana", "room_refused unreadable seat=" + seat.take(8)); return }
        val ev = e.optString("e")
        val at = (e.optDouble("at", 0.0) * 1000).toLong()
        val now = NodeClock.now()
        if (now - at >= STALE_MS) return
        // the seat's own moment of coming in: s where the word names one (never later than the word itself), else the word's moment
        val came = if (e.has("s")) minOf((e.optDouble("s") * 1000).toLong(), at) else at
        val key = e.optString("k").takeIf { k -> runCatching { Base64.decode(k, Base64.DEFAULT).size == 32 }.getOrDefault(false) }
        val me = Groups.mySeat(Groups.key(gid))   // asked before the book's lock: the group's lock is never taken under it
        var laid: JSONObject? = null
        synchronized(lock) {
            val book = book()
            val cur = book[gid]
            val known = cur != null && cur.id == r
            var firstSight = false
            val s: Seen
            if (known) s = cur!! else {
                if (ev == "out" || ev == "end" || key == null) return   // nothing is known of the room and the word does not bring it
                val born = Seen(r, kind, key, e.optString("o").ifEmpty { seat }, e.optInt("v") == 1, mutableMapOf(), came, at)
                // TWO ROOMS OF ONE GROUP (opened at once): the earlier stands -- by its moment, by its id for a tie -- on every phone
                if (cur != null && cur.people.isNotEmpty() && fresh(cur) && (if (cur.since != born.since) cur.since < born.since else cur.id < born.id)) return
                s = born
                firstSight = true
            }
            val who = e.optString("w").ifEmpty { seat }
            // the speaker's room key, from its own word on the group's road (kept for the pairs of the next stage)
            if (ev != "out" && ev != "end") e.optString("q").takeIf { q -> runCatching { Base64.decode(q, Base64.DEFAULT).size == PUB_SIZE }.getOrDefault(false) }?.let { s.keys[seat] = it }
            var closed = false
            when (ev) {
                "open" -> {
                    // a room is opened once, by its owner: an open for a room known here from another seat takes nothing over
                    if (known && seat != s.owner) { Log.i("Montana", "room_refused a second open from another seat"); return }
                    s.people[seat] = at
                    s.owner = e.optString("o").ifEmpty { seat }
                    s.video = e.optInt("v") == 1
                }
                "ask" -> {
                    if (s.people[seat] == null) s.people[seat] = at
                    // an invitation for this phone: the bar names who asked (the banner and the way in come with the next stage)
                    val to = e.optJSONArray("to")
                    if (to != null && me in List(to.length()) { to.optString(it) } && now - at < 120_000) s.askedBy = seat
                }
                "in" -> s.people[who] = came
                "key" -> if (s.people[seat] == null) s.people[seat] = came
                "here" -> {
                    if (s.people[seat] == null) s.people[seat] = at
                    val p = e.optJSONArray("p") ?: JSONArray()
                    for (i in 0 until minOf(p.length(), CAPACITY)) p.optString(i).takeIf { isSeat(it) && s.people[it] == null }?.let { s.people[it] = at }
                }
                "out" -> s.people.remove(who)
                "end" -> {
                    if (seat != s.owner && !s.people.keys.all { it == seat }) return
                    s.people.clear()
                    closed = true
                }
                else -> return
            }
            if (s.people[s.owner] == null && s.people.isNotEmpty()) s.owner = firstIn(s.people)
            s.at = maxOf(s.at, at)
            if (s.people.isEmpty()) book.remove(gid) else book[gid] = s
            Log.i("Montana", "room_rx e=$ev people=${s.people.size}")
            // THE ROOM IN THE GROUP'S FEED (iOS stage R): begun, once; ended, with how long it lived
            if (firstSight && s.people.isNotEmpty())
                laid = JSONObject().put("e", "call").put("a", s.owner).put("k", s.kind).put("v", if (s.video) 1 else 0).put("r", s.id)
            if (closed && known)
                laid = JSONObject().put("e", "ended").put("a", seat).put("k", s.kind).put("v", if (s.video) 1 else 0).put("d", ((now - s.since) / 1000).toInt())
        }
        laid?.let { Groups.layRoom(gid, it) }
        publish()
    }

    /** A group gone from this phone takes its room with it (iOS groupGone). */
    fun groupGone(gid: String) {
        synchronized(lock) { if (book().remove(gid) == null) return }
        publish()
    }

    /** Every group's room as the bars over the chats show it (iOS publish); the book is kept sealed (iOS keep). */
    private fun publish() {
        val out = synchronized(lock) {
            val book = book()
            keep(book)
            book.filterValues { it.people.isNotEmpty() && fresh(it) }.mapValues { (_, s) -> Brief(s.kind, s.video, s.people.size, s.askedBy, false) }
        }
        if (out == briefs) return
        briefs = out
        val ls = synchronized(listeners) { listeners.toList() }
        MainThread.post { ls.forEach { it() } }
        Book.redraw()   // the list's rows wear the room's mark
    }

    /** The book lifted from the device vault once (iOS lift): a room older than its measure is not lifted. */
    private fun book(): MutableMap<String, Seen> = synchronized(lock) {
        seen ?: mutableMapOf<String, Seen>().also { m ->
            seen = m
            runCatching {
                val o = JSONObject(String(DeviceVault.get(BOOK_KEY) ?: return@runCatching))
                for (gid in o.keys()) {
                    val j = o.getJSONObject(gid)
                    val pp = j.getJSONObject("p"); val kk = j.optJSONObject("ks") ?: JSONObject()
                    val s = Seen(j.getString("id"), j.getString("m"), j.getString("k"), j.getString("o"), j.optBoolean("v"),
                        pp.keys().asSequence().associateWith { pp.getLong(it) }.toMutableMap(), j.getLong("si"), j.getLong("at"),
                        j.optString("ab").ifEmpty { null }, kk.keys().asSequence().associateWith { kk.getString(it) }.toMutableMap())
                    if (fresh(s) && s.people.isNotEmpty()) m[gid] = s
                }
            }
            briefs = m.mapValues { (_, s) -> Brief(s.kind, s.video, s.people.size, s.askedBy, false) }
        }
    }
    private fun keep(book: Map<String, Seen>) {
        val o = JSONObject()
        for ((gid, s) in book) o.put(gid, JSONObject().put("id", s.id).put("m", s.kind).put("k", s.key).put("o", s.owner).put("v", s.video)
            .put("p", JSONObject(s.people as Map<*, *>)).put("si", s.since).put("at", s.at).put("ab", s.askedBy ?: "").put("ks", JSONObject(s.keys as Map<*, *>)))
        DeviceVault.set(BOOK_KEY, o.toString().toByteArray())
    }

    /** The bar's first line (iOS MTRoomBar.headline). */
    fun headline(c: Context, b: Brief): String = c.getString(when {
        b.kind == "live" -> R.string.rm_live
        b.video -> R.string.rm_video
        else -> R.string.rm_voice
    })
    /** The bar's second line (iOS MTRoomBar.detail): who invited this phone, else how many are in. */
    fun detail(c: Context, gid: String, b: Brief): String = when {
        b.askedBy != null -> c.getString(R.string.rm_invites, Groups.seatName(c, gid, b.askedBy))
        b.kind == "live" -> c.getString(R.string.rm_watching, b.count)
        else -> c.getString(R.string.rm_of, b.count, CAPACITY)
    }
    /** The room's glyph: a phone, a camera, the waves of a stream (iOS phone.fill, video.fill, dot.radiowaves). */
    fun glyph(b: Brief): Int = when {
        b.kind == "live" -> R.drawable.ic_speaker_wave3
        b.video -> R.drawable.ic_peer_video
        else -> R.drawable.ic_peer_phone
    }
}

/**
 * THE ROOM'S BAR over a group's chat (iOS MTRoomBar): a green round with the room's glyph, what it is and who is in, shown while
 * the group's room lives. Coming in is the next stage: until then a tap says so.
 */
fun roomBar(act: MainActivity, ref: String): View {
    val c: Context = act
    val gid = ref.removePrefix(Groups.key(""))
    val round = android.widget.ImageView(c).apply {
        background = android.graphics.drawable.GradientDrawable().apply { shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(SysColor.green) }
        setPadding(dp(9), dp(9), dp(9), dp(9))
        setColorFilter(Color.WHITE)
    }
    val head = c.text("", 15f, Color.WHITE, bold = true).apply { singleLineEllipsis() }
    val detail = c.text("", 12f, MT.gray).apply { singleLineEllipsis() }
    lateinit var bar: View
    fun draw() {
        val b = Rooms.brief(ref)
        bar.visibility = if (b == null) View.GONE else View.VISIBLE
        if (b == null) return
        round.setImageResource(Rooms.glyph(b))
        head.text = Rooms.headline(c, b)
        detail.text = Rooms.detail(c, gid, b)   // USER-DATA: the asker's name
    }
    bar = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = c.glassPlate()
        minimumHeight = dp(52)
        setPadding(dp(12), dp(6), dp(12), dp(6))
        addView(round, lp(dp(36), dp(36)).apply { marginEnd = dp(12) })
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(head); addView(detail) }, lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_chevron_right, MT.gray, 14), lp(dp(14), dp(14)))
        pressable { android.widget.Toast.makeText(c, R.string.rm_later, android.widget.Toast.LENGTH_SHORT).show() }
    }
    draw()
    val again: () -> Unit = { act.onMain { draw() } }
    bar.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Rooms.listen(again); draw() }
        override fun onViewDetachedFromWindow(v: View) { Rooms.unlisten(again) }
    })
    return bar
}
