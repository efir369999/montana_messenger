package quest.montana.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.text.BreakIterator
import java.util.UUID

/**
 * GROUPS AND CHANNELS, CARRIED BY THE PHONES THEMSELVES (iOS MTGroup, MontanaGroup.swift). No server holds a group: its owner's
 * phone holds a pipe with every member and carries every word to the others over those pipes — a star through the owner. This
 * phone takes the owner's words: the invitation that stands the group here, the letters of its people, their answers (a
 * reaction, an edit, a deletion) and the owner taking this phone out. The word on the wire is iOS's own: the mark, then JSON
 * with iOS's short keys; a key a reader does not know is skipped by it.
 */
object Groups {
    /** [P2P-COMPAT] iOS MTGroup.mark: a build that does not know it buries the word unread. */
    const val MARK = "​​GR:"
    // COMPAT-LOCAL: the feed's key and a speaker's reference name rows of this phone; neither rides the wire (iOS keyHead, speakerHead).
    private const val KEY_HEAD = "grp:"
    private const val SPEAKER_HEAD = "gm:"
    private const val OWNER_SEAT = "0"
    private const val GROUP = "g"
    private const val CHANNEL = "c"
    private const val STORE = "groups.held"
    private const val COPIES = "groups.copies"
    /** A copy outlives the queue's own term by a day and is let go with it (iOS copyLife). */
    private const val COPY_LIFE_MS = 8L * 24 * 3600 * 1000
    private const val TITLE_LIMIT = 64
    private const val ABOUT_LIMIT = 255
    private const val NAME_LIMIT = 64
    private const val FACE_LIMIT = 24_000
    private const val FACE_SIDE = 160   // iOS faceSide
    /** [I-14]: a group is bounded by the people its owner carries to (iOS peopleLimit). */
    private const val PEOPLE_LIMIT = 200
    private const val PIECE_CHARS = 4500   // iOS ChatStore.sendPieceChars
    private const val HEARD_LIMIT = 512
    private val CROWNS = setOf(0x1F451, 0x2654, 0x2655, 0x265A, 0x265B)   // iOS MTCrown: only the Montana room wears a crown

    enum class Verdict { HELD, REFUSED, WAIT }

    class Member(val seat: String, val pipe: String)

    /** A group as this phone holds it (iOS MTGroupState): `owner` — the pipe to the owner, empty on the owner's phone; `me` — this phone's seat. */
    class State(
        val id: String, val kind: String, var title: String, var about: String, val owner: String, var me: String,
        val members: MutableList<Member>, var count: Int, val names: MutableMap<String, String>, val at: Long,
        var left: Boolean = false, var faceTag: String? = null,
    ) {
        val mine: Boolean get() = owner.isEmpty()
        fun json(): JSONObject = JSONObject().put("id", id).put("k", kind).put("ti", title).put("ds", about).put("ow", owner).put("me", me)
            .put("mb", JSONArray().apply { members.forEach { put(JSONObject().put("s", it.seat).put("p", it.pipe)) } })
            .put("c", count).put("nm", JSONObject(names.toMap())).put("at", at).put("lf", left).put("ft", faceTag ?: "")
        companion object {
            fun of(o: JSONObject) = State(o.getString("id"), o.getString("k"), o.optString("ti"), o.optString("ds"), o.optString("ow"),
                o.getString("me"),
                o.optJSONArray("mb")?.let { a -> MutableList(a.length()) { i -> a.getJSONObject(i).let { Member(it.getString("s"), it.getString("p")) } } } ?: mutableListOf(),
                o.optInt("c", 2),
                o.optJSONObject("nm")?.let { n -> n.keys().asSequence().associateWith { n.getString(it) }.toMutableMap() } ?: mutableMapOf(),
                o.optLong("at"), o.optBoolean("lf"), o.optString("ft").ifEmpty { null })
        }
    }

    private val lock = Any()
    private var loaded = false
    /**
     * A STORE THAT WOULD NOT OPEN IS NOT AN EMPTY ONE (iOS MTGroup.unread): it is read again before it is used, nothing is written
     * over it, and a word that needs it waits unanswered — one group written over an unread store would write every other away.
     */
    private var unread = false
    private val groups = LinkedHashMap<String, State>()
    /** Letters taken away before they came (iOS deletedMids of a group's feed): their late copy lands nowhere. */
    private val gone = mutableListOf<String>()
    /** The names of the newest answers already applied: a repeat of a copy is applied once (iOS answersHeard). */
    private val heard = mutableListOf<String>()

    /**
     * A COPY OF A GROUP'S WORD ON ITS WAY TO ONE RECEIVER (iOS MTGroupCopy): the queue knows it by its own name, the group knows by
     * this record whose row its receipt moves. `letter` — the row it carries, empty for a word of no row; `own` — a copy of a
     * letter of mine, its receipt a witness of my row; `of` — how many copies the letter left in.
     */
    private class Copy(val group: String, val letter: String, val to: String, val own: Boolean, var of: Int,
                       var held: Boolean = false, var failed: Boolean = false, val at: Long = System.currentTimeMillis()) {
        fun json(): JSONObject = JSONObject().put("g", group).put("l", letter).put("to", to).put("o", own).put("of", of)
            .put("h", held).put("f", failed).put("at", at)
        companion object {
            fun of(o: JSONObject) = Copy(o.getString("g"), o.optString("l"), o.getString("to"), o.optBoolean("o"), o.optInt("of", 1),
                o.optBoolean("h"), o.optBoolean("f"), o.optLong("at"))
        }
    }
    private val copies = LinkedHashMap<String, Copy>()

    private fun ready(): Boolean {
        if (loaded && !unread) return true
        loaded = true
        groups.clear(); gone.clear(); copies.clear()
        val raw = DeviceVault.get(STORE)
        val kept = DeviceVault.get(COPIES)
        unread = (raw == null && DeviceVault.has(STORE)) || (kept == null && DeviceVault.has(COPIES))
        if (raw != null) runCatching {
            val o = JSONObject(String(raw, Charsets.UTF_8))
            o.optJSONObject("g")?.let { g -> g.keys().forEach { k -> groups[k] = State.of(g.getJSONObject(k)) } }
            o.optJSONArray("gone")?.let { a -> for (i in 0 until a.length()) gone.add(a.getString(i)) }
        }.onFailure { groups.clear(); gone.clear(); unread = true }
        if (kept != null) runCatching {
            val o = JSONObject(String(kept, Charsets.UTF_8))
            val edge = System.currentTimeMillis() - COPY_LIFE_MS
            o.keys().forEach { k -> Copy.of(o.getJSONObject(k)).takeIf { edge < it.at }?.let { copies[k] = it } }
        }.onFailure { copies.clear(); unread = true }
        if (unread) Log.i("Montana", "group_unread the groups' store did not open -- read again before use")
        return !unread
    }
    private fun save() {
        if (unread) return
        val g = JSONObject(); groups.forEach { (k, v) -> g.put(k, v.json()) }
        DeviceVault.set(STORE, JSONObject().put("g", g).put("gone", JSONArray(gone)).toString().toByteArray(Charsets.UTF_8))
    }
    private fun saveCopies() {
        if (unread) return
        val o = JSONObject(); copies.forEach { (k, v) -> o.put(k, v.json()) }
        DeviceVault.set(COPIES, o.toString().toByteArray(Charsets.UTF_8))
    }
    /** The person leaves: their groups leave with them (iOS montanaSeedForgotten). */
    fun wipe() = synchronized(lock) {
        groups.clear(); gone.clear(); heard.clear(); copies.clear(); loaded = false; unread = false
        DeviceVault.delete(STORE); DeviceVault.delete(COPIES)
    }

    // ── names ──

    fun isKey(chat: String) = chat.startsWith(KEY_HEAD)
    private fun key(id: String) = KEY_HEAD + id
    private fun state(key: String): State? = synchronized(lock) { if (isKey(key) && ready()) groups[key.removePrefix(KEY_HEAD)] else null }
    /** The people in the group, the owner included — the head of the group's chat says this number (iOS people). */
    fun peopleLine(c: Context, key: String): String? = state(key)?.count?.let { c.resources.getQuantityString(R.plurals.gr_members, it, it) }
    /** Out of the group — it left, or the owner took it out: the chat says so instead of a field (iOS isOut). */
    fun isOut(key: String) = state(key)?.left == true
    /** A channel, not a group: its page is the channels' (iOS kind == .channel). */
    fun isChannel(key: String) = state(key)?.kind == CHANNEL
    /** Everyone writes in a group, the owner alone in a channel (iOS canWrite). */
    fun canWrite(key: String): Boolean { val g = state(key) ?: return false; return !g.left && (g.kind == GROUP || g.mine) }
    /** The moment the group stood here: its row stands by it until its first letter (iOS stand puts the row at the top). */
    fun bornAt(key: String): Long = state(key)?.at ?: 0L

    private fun speaker(id: String, seat: String) = SPEAKER_HEAD + id + "/" + seat
    /**
     * The name a speaker's rows wear (iOS speakerName): the person as this phone knows them where it holds their pipe, else the
     * name they gave themselves in their last word.
     */
    fun speakerName(c: Context, ref: String?): String {
        val parts = ref?.takeIf { it.startsWith(SPEAKER_HEAD) }?.removePrefix(SPEAKER_HEAD)?.split("/", limit = 2)
        if (parts == null || parts.size != 2) return c.getString(R.string.gr_member)
        val g = state(key(parts[0])) ?: return c.getString(R.string.gr_member)
        val seat = parts[1]
        val pipe = if (!g.mine && seat == OWNER_SEAT) g.owner else g.members.firstOrNull { it.seat == seat }?.pipe
        val book = pipe?.takeIf { it.isNotEmpty() }?.let { Book.chat(SamePair.root(it))?.shown }
        return book?.ifBlank { null } ?: g.names[seat]?.ifEmpty { null } ?: c.getString(R.string.gr_member)
    }
    /** The line above a speaker's bubble (iOS speakerLine): in a group every letter of another says who wrote it; a channel speaks as itself. */
    fun speakerLine(c: Context, m: Msg, chat: String): String? =
        if (m.mine || m.from?.startsWith(SPEAKER_HEAD) != true || state(chat)?.kind != GROUP) null else speakerName(c, m.from)

    // ── the wire ──

    /**
     * ONE COPY TO ONE RECEIVER, UNDER A NAME OF ITS OWN (iOS carry): it has no row of its own — the row it carries stands in the
     * group's feed under the letter's name, and the copy's receipt moves that row (follow).
     */
    private fun carry(w: JSONObject, pipe: String, letter: String, own: Boolean): String? {
        if (Book.secret(pipe) == null) return null
        val name = Marks.mintMid()
        copies[name] = Copy(w.getString("g"), letter, pipe, own, 1)
        saveCopies()
        Post.send(pipe, name, MARK + w.toString())
        Log.i("Montana", "group_tx mid=" + name.take(14) + " t=" + w.optString("t") + " to=" + pipe.take(10))
        return name
    }

    /** A word to everyone this phone carries to in the group (iOS spread): the owner to every member but the speaker, a member to the owner. */
    private fun spread(w: JSONObject, g: State, except: String?, own: Boolean): Int {
        val targets = if (g.mine) g.members.filter { it.seat != except }.map { it.pipe } else listOf(g.owner)
        val names = targets.mapNotNull { carry(w, it, w.optString("id"), own) }
        names.forEach { copies[it]?.of = names.size }
        if (names.isNotEmpty()) saveCopies()
        return names.size
    }

    /**
     * The word's head (iOS MTGroupWord): its kind and its group; a letter carries the group's kind and title too — the receiver's
     * notification holds no group and names it by these — and every word the name this phone gives itself.
     */
    private fun word(t: String, g: State): JSONObject {
        val w = JSONObject().put("t", t).put("g", g.id)
        if (t == "say") w.put("k", g.kind).put("ti", g.title)
        clean(Prefs.userName, NAME_LIMIT).takeIf { it.isNotEmpty() }?.let { w.put("n", it) }
        return w
    }

    /**
     * A LETTER OF MINE INTO A GROUP (iOS ChatStore.send → MTGroup.send): long words leave as pieces (breakOutgoingText), each a row
     * born in the group's feed under its one name and a copy to everyone this phone carries to — on a member's phone, the owner;
     * the receipts raise the row (follow). Nobody to carry to: honest red. False when the group takes no letter from this phone.
     */
    fun send(key: String, words: String, qt: String?, qm: String?): Boolean {
        synchronized(lock) {
            val g = state(key)
            if (g == null || g.left || (g.kind != GROUP && !g.mine) || words.isBlank()) {
                Log.i("Montana", "group_refused send -- group=" + (if (g == null) 0 else 1))
                return false
            }
            pieces(words).forEachIndexed { i, piece ->
                if (!carries(piece)) return@forEachIndexed
                val first = i == 0
                val mid = Marks.mintMid()
                Book.edit(key) { it.msgs.add(Msg(mid, piece, true, Marks.birthMs(mid) ?: System.currentTimeMillis(),
                    qt = qt.takeIf { first }, qm = qm.takeIf { first })) }
                val w = word("say", g).put("id", mid).put("s", g.me).put("tx", piece)
                if (first && !qt.isNullOrEmpty()) w.put("qt", qt)
                if (first && !qm.isNullOrEmpty()) w.put("qm", qm)
                if (spread(w, g, null, own = true) == 0) Book.edit(key) { c -> c.msgs.find { it.mid == mid }?.advance(-1) }
            }
            return true
        }
    }

    /**
     * A MEDIA LETTER OF MINE INTO A GROUP (iOS MTGroup.carryMedia): its row stands in the feed already under its one name, its
     * file's sealed pieces lie on the nodes for every receiver — the node's term keeps them, no single receipt takes them away —
     * and its manifest leaves to everyone this phone carries to, as a word does. False: nobody took it.
     */
    fun carryMedia(key: String, mid: String, letter: String): Boolean {
        synchronized(lock) {
            val g = state(key)
            if (g == null || g.left || (g.kind != GROUP && !g.mine) || !letter.startsWith(Marks.MEDIA) || !carries(letter) || !isLetterName(mid)) {
                Log.i("Montana", "group_refused media -- group=" + (if (g == null) 0 else 1))
                return false
            }
            return spread(word("say", g).put("id", mid).put("s", g.me).put("tx", letter), g, null, own = true) > 0
        }
    }

    /**
     * A REACTION, AN EDIT OR A DELETION OF MINE (iOS MTGroup.signal): carried to every phone of the group like a letter and applied
     * there by the same road, never a row. Everyone in a group or a channel may react; only a letter's own speaker changes it or
     * takes it away (answered checks the seat on every phone).
     */
    fun signal(key: String, text: String) {
        synchronized(lock) {
            val g = state(key)
            if (g == null || g.left || !answers(text)) { Log.i("Montana", "group_refused answer -- group=" + (if (g == null) 0 else 1)); return }
            spread(word("sig", g).put("id", Marks.mintMid()).put("s", g.me).put("tx", text), g, null, own = false)
        }
    }

    // ── birth: this phone owns the group ──

    /**
     * A GROUP OR A CHANNEL IS BORN ON THIS PHONE (iOS MTGroup.create): its owner's phone. The people are the correspondents chosen,
     * each by the pipe this phone holds with them; each is told by an invitation of their own, with a seat of their own. The row
     * stands at once; the invitations ride the queue until each is receipted. The key of the group's feed, or null when nobody
     * chosen can be carried to.
     */
    fun create(channel: Boolean, title: String, about: String, face: ByteArray?, people: List<String>): String? {
        synchronized(lock) {
            val name = clean(title, TITLE_LIMIT)
            val pipes = people.map { SamePair.root(it) }.filter { !isKey(it) && Book.secret(it) != null }.distinct().take(PEOPLE_LIMIT)
            if (!ready() || name.isEmpty() || pipes.isEmpty()) {
                Log.i("Montana", "group_refused birth -- title=" + (if (name.isEmpty()) 0 else 1) + " people=" + pipes.size)
                return null
            }
            val id = mintId()
            val taken = mutableSetOf(OWNER_SEAT)
            val members = pipes.map { p ->
                var seat = mintSeat()
                while (seat in taken) seat = mintSeat()
                taken.add(seat)
                Member(seat, p)
            }.toMutableList()
            val g = State(id, if (channel) CHANNEL else GROUP, name, clean(about, ABOUT_LIMIT), "", OWNER_SEAT, members, members.size + 1,
                mutableMapOf(), System.currentTimeMillis())
            groups[id] = g
            save()
            stand(g, face)
            tellAll(g, face?.let { thumb(it) })
            Log.i("Montana", "group_born kind=" + g.kind + " people=" + g.count)
            return key(id)
        }
    }

    /**
     * The invitation's word to every member (iOS tellAll): the title, the words about the group, the count, the receiver's own
     * seat, and the face where it is given — `only`, the seats the face goes to (the people just added).
     */
    private fun tellAll(g: State, face: String?, only: Set<String>? = null) {
        for (m in g.members) {
            val w = word("inv", g).put("k", g.kind).put("ti", g.title).put("c", g.count).put("me", m.seat)
            if (g.about.isNotEmpty()) w.put("ds", g.about)
            if (face != null && (only == null || m.seat in only)) w.put("fc", face)
            carry(w, m.pipe, "", own = false)
        }
    }

    // ── the group's life: its name and face, its people, leaving ──

    /** One person of the group's page: the seat, the name it wears here, and the pipe this phone holds with them. */
    class Seat(val seat: String, val name: String, val pipe: String)
    /** The people of the group's page (iOS shownSeats): the owner's phone lists everyone it carries to, a member's the owner. */
    fun shownSeats(c: Context, key: String): List<Seat> {
        val g = state(key) ?: return emptyList()
        return if (g.mine) g.members.map { Seat(it.seat, speakerName(c, speaker(g.id, it.seat)), it.pipe) }
            else listOf(Seat(OWNER_SEAT, speakerName(c, speaker(g.id, OWNER_SEAT)), g.owner))
    }
    /** This phone owns the group: its page edits it (iOS state.mine). */
    fun owns(key: String) = state(key)?.mine == true
    /** Whether the owner's phone already carries the group to this person (iOS carries(to:in:)): the page's «add» lists the others only. */
    fun carriesTo(pipe: String, key: String): Boolean {
        val p = SamePair.root(pipe)
        return state(key)?.members?.any { SamePair.root(it.pipe) == p } == true
    }

    /**
     * THE OWNER RENAMES THE GROUP OR GIVES IT A NEW FACE (iOS renew): every member is told by the invitation's own word again —
     * the same group, the same seat, the new title and face — so every phone shows what the owner's shows.
     */
    fun renew(key: String, title: String, face: ByteArray?) {
        synchronized(lock) {
            val g = state(key) ?: return
            val name = clean(title, TITLE_LIMIT)
            if (!g.mine || name.isEmpty() || (name == g.title && face == null)) return
            g.title = name
            save()
            stand(g, face)
            tellAll(g, face?.let { thumb(it) })
            Log.i("Montana", "group_renewed face=" + (if (face == null) 0 else 1))
        }
    }

    /** THE OWNER ADDS PEOPLE (iOS add): each new one is invited with a seat of their own and the group's face; everyone learns the count. */
    fun add(key: String, people: List<String>) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine) return
            val held = g.members.map { SamePair.root(it.pipe) }.toSet()
            val taken = (g.members.map { it.seat } + OWNER_SEAT).toMutableSet()
            val fresh = mutableListOf<Member>()
            for (p in people.map { SamePair.root(it) }.distinct()) {
                if (isKey(p) || Book.secret(p) == null || p in held || g.members.size + fresh.size >= PEOPLE_LIMIT) continue
                var seat = mintSeat()
                while (seat in taken) seat = mintSeat()
                taken.add(seat)
                fresh.add(Member(seat, p))
            }
            if (fresh.isEmpty()) return
            g.members.addAll(fresh)
            g.count = g.members.size + 1
            save()
            val face = Book.face(key).takeIf { it.exists() }?.readBytes()?.let { thumb(it) }
            tellAll(g, face, fresh.map { it.seat }.toSet())
            Log.i("Montana", "group_added people=" + fresh.size + " count=" + g.count)
        }
    }

    /** THE OWNER TAKES A PERSON OUT (iOS remove): told by their own word, carried to no more; everyone left learns the count. */
    fun remove(key: String, seat: String) {
        synchronized(lock) {
            val g = state(key) ?: return
            val m = (if (g.mine) g.members.firstOrNull { it.seat == seat } else null) ?: return
            g.members.removeAll { it.seat == seat }
            g.count = g.members.size + 1
            save()
            carry(JSONObject().put("t", "out").put("g", g.id), m.pipe, "", own = false)
            tellAll(g, null)
            Log.i("Montana", "group_removed count=" + g.count)
        }
    }

    /** A MEMBER LEAVES (iOS leave): the owner is told and carries nothing more to this phone; the group's rows stay readable here. */
    fun leave(key: String) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (g.mine || g.left) return
            g.left = true
            save()
            carry(JSONObject().put("t", "bye").put("g", g.id), g.owner, "", own = false)
            Log.i("Montana", "group_left by this phone")
        }
        Book.edit(key) {}   // the open chat trades its field for the note at once
    }

    private fun mintId() = UUID.randomUUID().toString().replace("-", "").lowercase()
    private fun mintSeat() = mintId().take(8)
    /** The face an invitation carries (iOS thumb): small, so the word stays a letter and not a file. */
    private fun thumb(face: ByteArray): String? {
        val b = BitmapFactory.decodeByteArray(face, 0, face.size) ?: return null
        val side = minOf(b.width, b.height)
        val square = Bitmap.createBitmap(b, (b.width - side) / 2, (b.height - side) / 2, side, side)
        val small = Bitmap.createScaledBitmap(square, FACE_SIDE, FACE_SIDE, true)
        val out = ByteArrayOutputStream()
        small.compress(Bitmap.CompressFormat.JPEG, 70, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP).takeIf { it.length <= FACE_LIMIT }
    }

    // ── the receipts of the copies ──

    /** The node holds a copy (Post.flush): my row has left this phone. True when the name was a group's copy. */
    fun copyHeld(name: String): Boolean {
        synchronized(lock) {
            val c = (if (ready()) copies[name] else null) ?: return false
            if (!c.held) { c.held = true; saveCopies() }
            if (c.own) follow(c)
            return true
        }
    }
    /** A copy was receipted (Post.place, «delivered» on its receiver's pipe): it witnesses the group's row, never a row of the pipe. */
    fun copyDelivered(name: String): Boolean {
        synchronized(lock) {
            val c = (if (ready()) copies.remove(name) else null) ?: return false
            saveCopies()
            Log.i("Montana", "group_rcpt mid=" + name.take(14) + " own=" + (if (c.own) 1 else 0))
            if (c.own) follow(c)
            return true
        }
    }
    /** The copy's pipe was gone before it left (Post.flush): my row says so (iOS copySettled, red with no pipe). */
    fun copyLost(name: String): Boolean {
        synchronized(lock) {
            val c = (if (ready()) copies[name] else null) ?: return false
            if (!c.failed) { c.failed = true; saveCopies() }
            if (c.own) follow(c)
            return true
        }
    }
    /**
     * MY ROW STANDS WHERE ITS RECEIVERS SAY (iOS follow): delivered when every copy is receipted, red while a copy has failed, sent
     * once the node holds one or one is receipted — through the rung's one door (Msg.advance: forward only, red only from below).
     */
    private fun follow(c: Copy) {
        if (c.letter.isEmpty()) return
        val left = copies.values.filter { it.own && it.group == c.group && it.letter == c.letter }
        val next = when {
            left.isEmpty() -> 2
            left.any { it.failed } -> -1
            left.size < c.of || left.any { it.held } -> 1
            else -> return
        }
        Book.edit(key(c.group)) { ch -> ch.msgs.find { it.mine && it.mid == c.letter }?.advance(next) }
    }

    // ── arrival ──

    /**
     * A GROUP'S WORD ARRIVED ON A PIPE (iOS MTGroup.handle, Post.place before any row): never a row of the pipe. Held or refused,
     * the copy is receipted by its own name on the pipe it came by; a word that must wait is not, and its copy knocks again.
     */
    fun handle(pipe: String, sid: String, text: String) {
        val w = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull()
        val verdict = if (w != null && isLabel(w.optString("g"))) synchronized(lock) { take(w, pipe) }
            else Verdict.REFUSED.also { Log.i("Montana", "group_refused unreadable from=${pipe.take(10)}") }
        if (verdict != Verdict.WAIT) Post.receiptFor(pipe, sid)
    }

    private fun take(w: JSONObject, pipe: String): Verdict {
        if (!ready()) return Verdict.WAIT   // the copy knocks again once the store opens
        return when (val t = w.optString("t")) {
            "inv" -> invited(w, pipe)
            "say" -> said(w, pipe)
            "sig" -> answered(w, pipe)
            "out" -> dropped(w, pipe)
            "bye" -> parted(w, pipe)
            else -> Verdict.REFUSED.also { Log.i("Montana", "group_refused kind=${t.take(8)}") }   // a newer build's word: its road ends here
        }
    }

    /**
     * AN INVITATION (iOS invited): the group stands on this phone, owned by the pipe the word came by. A second invitation of the
     * same owner renews the title, the words, the count and the face; another pipe naming a group held here is refused.
     */
    private fun invited(w: JSONObject, pipe: String): Verdict {
        val owner = SamePair.root(pipe)
        val kind = w.optString("k")
        val title = clean(w.optString("ti"), TITLE_LIMIT)
        val seat = w.optString("me")
        if ((kind != GROUP && kind != CHANNEL) || title.isEmpty() || !isSeat(seat) || seat == OWNER_SEAT) return Verdict.REFUSED
        val count = w.optInt("c", 2).coerceIn(2, PEOPLE_LIMIT + 1)
        val ownerName = clean(w.optString("n"), NAME_LIMIT)
        val fc = w.optString("fc").ifEmpty { null }
        val tag = fc?.let { it.length.toString() + "-" + it.takeLast(16) }
        val id = w.getString("g")
        val had = groups[id]
        if (had != null) {
            if (had.mine || SamePair.root(had.owner) != owner) {
                Log.i("Montana", "group_refused invitation of a group held by another owner")
                return Verdict.REFUSED
            }
            // out of the group, a word of the old seat is one that was on its way; the owner adding this phone again gives a new seat
            if (had.left) { if (seat == had.me) return Verdict.REFUSED; had.left = false }
            had.title = title; had.about = clean(w.optString("ds"), ABOUT_LIMIT); had.count = count; had.me = seat
            if (ownerName.isNotEmpty()) had.names[OWNER_SEAT] = ownerName
            val newFace = tag != null && tag != had.faceTag
            if (newFace) had.faceTag = tag
            save()
            stand(had, if (newFace) face(fc) else null)
            return Verdict.HELD
        }
        val g = State(id, kind, title, clean(w.optString("ds"), ABOUT_LIMIT), owner, seat, mutableListOf(), count,
            if (ownerName.isEmpty()) mutableMapOf() else mutableMapOf(OWNER_SEAT to ownerName), System.currentTimeMillis(), faceTag = tag)
        groups[id] = g
        save()
        stand(g, face(fc))
        Log.i("Montana", "group_rx invitation kind=$kind people=$count from=${pipe.take(10)}")
        return Verdict.HELD
    }

    /** The group's row on the list (iOS stand): the one standing or archived, or a new one; a deleted group's row comes back with its next word. */
    private fun stand(g: State, face: ByteArray?) {
        val key = key(g.id)
        if (face != null) runCatching { Book.face(key).writeBytes(face) }
        Book.open(key, g.title, false)
        Book.edit(key) { it.name = g.title }
    }

    /**
     * A LETTER (iOS heard): it lands in the group's feed under its one name, worn by its speaker's seat. The owner takes a letter
     * only from a member it carries to — in a group, never in a channel — and carries it on to every other member; a member takes
     * letters from the owner's pipe alone.
     */
    private fun said(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.WAIT
        if (g.left) return Verdict.REFUSED   // out of the group: the word's road ends here
        val id = w.optString("id")
        val words = w.optString("tx")
        if (!isLetterName(id) || !carries(words)) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        val seat: String
        if (g.mine) {
            val m = g.members.firstOrNull { SamePair.root(it.pipe) == from } ?: return Verdict.REFUSED
            if (g.kind != GROUP) { Log.i("Montana", "group_refused a member's letter in a channel is not carried"); return Verdict.REFUSED }
            seat = m.seat
        } else {
            val s0 = w.optString("s")
            if (SamePair.root(g.owner) != from || !isSeat(s0) || s0 == g.me) return Verdict.REFUSED
            seat = s0
        }
        val name = clean(w.optString("n"), NAME_LIMIT)
        if (name.isNotEmpty() && g.names[seat] != name) { g.names[seat] = name; save() }
        if (id in gone) return Verdict.HELD
        val key = key(g.id)
        if (Book.chat(key)?.msgs?.any { it.mid == id } == true) return Verdict.HELD   // a repeat: the row stands
        stand(g, null)
        val sp = speaker(g.id, seat)
        val at = Marks.birthMs(id) ?: System.currentTimeMillis()
        val quote = w.optString("qt").ifEmpty { null }
        val quoted = w.optString("qm").removePrefix("mid:").ifEmpty { null }
        var landed = false
        Book.edit(key) { c ->
            if (c.msgs.none { it.mid == id }) {
                c.msgs.add(Msg(id, words, false, at, qt = quote, qm = quoted, from = sp)); c.msgs.sortBy { it.at }
                if (Book.openChat != key) c.unread++
                landed = true
            }
        }
        Log.i("Montana", "group_rx mid=$id letter landed=${if (landed) 1 else 0} owner=${if (g.mine) 1 else 0}")
        // a media letter's file is gathered from the pieces every member reads; its copy was receipted already (handle)
        if (landed && words.startsWith(Marks.MEDIA)) Media.fetch(Book.ctx, key, id, words)
        // the banner a running app owes its person: the group's title over who wrote and what (a channel speaks as itself)
        if (landed && Book.openChat != key) Notify.letter(key, words, if (g.kind == GROUP) speakerName(Book.ctx, sp) else null)
        // THE OWNER CARRIES IT ON (iOS heard, g.mine): to every other member, under the speaker's seat and the name they gave
        if (landed && g.mine) {
            val on = JSONObject().put("t", "say").put("g", g.id).put("k", g.kind).put("ti", g.title).put("id", id).put("s", seat).put("tx", words)
            if (name.isNotEmpty()) on.put("n", name)
            if (quote != null) on.put("qt", quote)
            w.optString("qm").ifEmpty { null }?.let { on.put("qm", it) }
            spread(on, g, seat, own = false)
        }
        return Verdict.HELD
    }

    /**
     * AN ANSWER (iOS answered): a reaction, an edit of one's own words, a deletion of one's own letter — applied in the group's
     * feed once by its name. Only a letter's own speaker changes it or takes it away; a deletion of a letter not landed yet
     * buries it before it comes.
     */
    private fun answered(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.WAIT
        if (g.left) return Verdict.REFUSED
        val id = w.optString("id")
        val words = w.optString("tx")
        if (!isLetterName(id) || !answers(words)) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        // the owner answers for every member by the pipe the word came by; a member takes the owner's word alone
        val seat = if (g.mine) g.members.firstOrNull { SamePair.root(it.pipe) == from }?.seat ?: return Verdict.REFUSED
            else w.optString("s").takeIf { SamePair.root(g.owner) == from && isSeat(it) && it != g.me } ?: return Verdict.REFUSED
        if (id in heard) return Verdict.HELD
        val key = key(g.id)
        target(words)?.let { t ->
            val row = Book.chat(key)?.msgs?.firstOrNull { it.mid == t }
            if (row != null) {
                if (author(row, g) != seat) {
                    Log.i("Montana", "group_refused an answer to another's letter seat=$seat")
                    return Verdict.REFUSED
                }
            } else if (t in gone) return Verdict.HELD
            else if (g.mine) return Verdict.WAIT   // the letter has not landed at the owner yet: the copy knocks again
            else if (words.startsWith(Marks.DELETE)) { bury(t); remember(id); return Verdict.HELD }
        }
        remember(id)
        apply(key, words)
        // the owner carries the answer on to every other member (iOS answered, g.mine)
        if (g.mine) spread(JSONObject().put("t", "sig").put("g", g.id).put("id", id).put("s", seat).put("tx", words)
            .apply { w.optString("n").ifEmpty { null }?.let { put("n", it) } }, g, seat, own = false)
        return Verdict.HELD
    }

    /** A MEMBER LEFT (iOS parted, their «bye»): the owner carries nothing more to them, and everyone left learns the new count. */
    private fun parted(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.REFUSED
        val from = SamePair.root(pipe)
        val m = (if (g.mine) g.members.firstOrNull { SamePair.root(it.pipe) == from } else null) ?: return Verdict.REFUSED
        g.members.removeAll { it.seat == m.seat }
        g.count = g.members.size + 1
        save()
        tellAll(g, null)
        Log.i("Montana", "group_rx a member left count=" + g.count)
        return Verdict.HELD
    }

    private fun apply(key: String, words: String) {
        when {
            words.startsWith(Marks.DELETE) -> target(words)?.let { t -> Book.edit(key) { c -> c.msgs.removeAll { it.mid == t } } }
            words.startsWith(Marks.EDIT) -> {
                val tx = runCatching { JSONObject(words.removePrefix(Marks.EDIT)).getString("tx") }.getOrNull()
                val t = target(words)
                if (tx != null && t != null) Book.edit(key) { c -> c.msgs.find { it.mid == t && !it.mine }?.let { it.text = tx; it.edited = true } }
            }
            words.startsWith(Marks.REACTION) -> runCatching {
                val o = JSONObject(words.removePrefix(Marks.REACTION)); val t = o.getString("sid").removePrefix("mid:"); val e = o.getString("e")
                Book.edit(key) { c -> c.msgs.find { it.mid == t }?.let { m -> if (o.optString("op") == "del") m.reactions.remove(e) else m.reactions.add(e) } }
            }
        }
    }

    /** THE OWNER TOOK THIS PHONE OUT (iOS dropped): the rows stay readable, and the chat says so instead of a field. */
    private fun dropped(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.REFUSED
        if (g.mine || SamePair.root(g.owner) != SamePair.root(pipe)) return Verdict.REFUSED
        if (!g.left) {
            g.left = true
            save()
            Book.edit(key(g.id)) {}   // the open chat trades its field for the note at once
            Log.i("Montana", "group_rx taken out by the owner")
        }
        return Verdict.HELD
    }

    private fun bury(mid: String) {
        gone.add(mid)
        if (gone.size > HEARD_LIMIT) gone.subList(0, gone.size - HEARD_LIMIT).clear()
        save()
    }
    private fun remember(id: String) {
        heard.add(id)
        if (heard.size > HEARD_LIMIT) heard.subList(0, heard.size - HEARD_LIMIT).clear()
    }

    // ── measures ──

    /** The seat whose letter a row is: mine is this phone's seat, another's is named by its speaker's reference (iOS author). */
    private fun author(row: Msg, g: State): String? =
        if (row.mine) g.me else row.from?.takeIf { it.startsWith(speaker(g.id, "")) }?.removePrefix(speaker(g.id, ""))

    /** WHAT AN ANSWER MAY BE IN A GROUP (iOS answers): an emoji put on or taken off, a letter's new words, a letter taken away. */
    private fun answers(text: String): Boolean = when {
        text.startsWith(Marks.REACTION) -> text.length <= 2048 &&
            runCatching { JSONObject(text.removePrefix(Marks.REACTION)).optString("op") }.getOrNull().let { it == "add" || it == "del" }
        text.startsWith(Marks.EDIT) -> target(text) != null &&
            runCatching { JSONObject(text.removePrefix(Marks.EDIT)).getString("tx") }.getOrNull()?.let { carries(it) } == true
        else -> text.startsWith(Marks.DELETE) && target(text) != null
    }
    /** The bare name of the letter an edit or a deletion speaks of; null for a reaction (iOS target). */
    private fun target(text: String): String? {
        val sid = when {
            text.startsWith(Marks.EDIT) -> runCatching { JSONObject(text.removePrefix(Marks.EDIT)).optString("sid") }.getOrDefault("")
            text.startsWith(Marks.DELETE) -> text.removePrefix(Marks.DELETE)
            else -> ""
        }
        return sid.removePrefix("mid:").takeIf { isLetterName(it) }
    }
    /**
     * WHAT A GROUP CARRIES (iOS carries): a person's words, a sticker, and a media letter — the manifest of a picture, a film, a
     * round note, a voice or a file, whose sealed pieces lie on the nodes for every receiver; never another service word. iOS also
     * refuses a coin's, a game's and a phone's own letter at the sender's door; this build reads none of them.
     */
    private fun carries(text: String): Boolean = text.isNotEmpty() && graphemes(text) <= PIECE_CHARS &&
        (!Marks.isService(text) || text.startsWith(Marks.STICKER) || text.startsWith(Marks.MEDIA))

    private fun isLabel(s: String) = s.length == 32 && s.all { it in '0'..'9' || it in 'a'..'f' }
    private fun isSeat(s: String) = s.isNotEmpty() && s.length <= 16 && s.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
    private fun isLetterName(s: String) = s.isNotEmpty() && s.length <= 80 && !s.startsWith("mid:") &&
        s.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' }

    /** A name or a title as the group shows it (iOS clean): trimmed, without a crown, at most `limit` characters as a person counts them. */
    private fun clean(s: String, limit: Int): String {
        val plain = StringBuilder()
        var afterMark = false
        val t = s.trim()
        var i = 0
        while (i < t.length) {
            val point = t.codePointAt(i); i += Character.charCount(point)
            if (point in CROWNS) { afterMark = true; continue }
            if (afterMark && (point == 0xFE0F || point == 0xFE0E)) continue
            afterMark = false
            plain.appendCodePoint(point)
        }
        val p = plain.toString()
        if (p.length <= limit) return p
        val cut = BreakIterator.getCharacterInstance().apply { setText(p) }
        var end = 0
        repeat(limit) { val next = cut.next(); if (next == BreakIterator.DONE) return p.substring(0, end); end = next }
        return p.substring(0, end)
    }
    /** Long words are cut into letters of up to the piece's characters, backing off to the last line break or period (iOS breakOutgoingText). */
    fun pieces(text: String): List<String> {
        if (graphemes(text) <= PIECE_CHARS) return listOf(text)
        val out = mutableListOf<String>()
        val cut = BreakIterator.getCharacterInstance().apply { setText(text) }
        var start = 0
        while (start < text.length) {
            var end = start; var n = 0; var mark = -1
            while (end < text.length && n < PIECE_CHARS) {
                val next = cut.following(end)
                val ch = text.substring(end, next)
                n++; end = next
                if (ch == "\n" || ch == ".") mark = end
            }
            val stop = if (end >= text.length || mark < 0) end else mark
            out.add(text.substring(start, stop).trim())
            start = stop
        }
        return out.filter { it.isNotEmpty() }
    }
    private fun graphemes(s: String): Int {
        if (s.length <= PIECE_CHARS) return s.length
        val cut = BreakIterator.getCharacterInstance().apply { setText(s) }
        var n = 0
        while (cut.next() != BreakIterator.DONE) n++
        return n
    }
    /** The face an invitation carries (iOS face): small, a picture, laid beside the group's row. */
    private fun face(b64: String?): ByteArray? {
        if (b64 == null || b64.length > FACE_LIMIT) return null
        val d = runCatching { Base64.decode(b64, Base64.DEFAULT) }.getOrNull() ?: return null
        return d.takeIf { BitmapFactory.decodeByteArray(it, 0, it.size) != null }
    }
}
