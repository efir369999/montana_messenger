package quest.montana.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
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
    /** The other device's copies of words whose group has not stood here yet (Windows groups.rs TWIN_WAITING): tried again by the twin's walk. */
    private const val TWIN_WAIT = "groups.twinWait"
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
    /** [COMPAT-LOCAL] iOS MTGroupEvent.mark: a group's event, a row of this phone's own in the middle of its feed, never on the wire. */
    const val EVENT_MARK = "​​GE:"
    /** [I-14]: the deeds a channel's owner keeps for its Recent Actions (iOS actsKept). */
    private const val ACTS_KEPT = 100
    /** [I-14]: the posts one word of a channel's views names, at most (iOS viewsBatch). */
    const val VIEWS_BATCH = 200
    /** The invite link's own query name (iOS joinParam): «?jg=<group>.<mark>». */
    private const val JOIN_PARAM = "jg"

    /** INSTANT (iOS 2235, a typing word): neither held nor refused -- nothing answers it, no receipt, it lives seconds. */
    enum class Verdict { HELD, REFUSED, WAIT, INSTANT }

    class Member(val seat: String, val pipe: String)

    /** One deed of a channel, as its owner's phone wrote it (iOS MTChannelAct): what, about whom by the names known then, when. */
    class Act(val e: String, val p: List<String>?, val t: String?, val at: Long) {
        fun json(): JSONObject = JSONObject().put("e", e).put("at", at).apply { p?.let { put("p", JSONArray(it)) }; t?.let { put("t", it) } }
        companion object {
            fun of(o: JSONObject) = Act(o.getString("e"), o.optJSONArray("p")?.let { a -> List(a.length()) { a.getString(it) } },
                o.optString("t").ifEmpty { null }, o.optLong("at"))
        }
    }

    /** A group as this phone holds it (iOS MTGroupState): `owner` — the pipe to the owner, empty on the owner's phone; `me` — this phone's seat. */
    class State(
        val id: String, val kind: String, var title: String, var about: String, val owner: String, var me: String,
        val members: MutableList<Member>, var count: Int, val names: MutableMap<String, String>, val at: Long,
        var left: Boolean = false, var faceTag: String? = null,
        // iOS 2235 MTGroupState: the administrators' seats (inv «ad»), a channel signing its posts («sg»), reactions off («rx»: 0),
        // and taken out by the owner rather than gone by one's own word
        val admins: MutableList<String> = mutableListOf(), var signs: Boolean = false, var reacts: Boolean? = null, var removed: Boolean = false,
        // the owner's own: the standing mark of the invite link, the people taken out of a channel (kept out of its link), what was
        // done in a channel (its Recent Actions), its posts going without sound; and who read this phone's letters, how far
        var invite: String? = null, val banned: MutableList<Member> = mutableListOf(), val acts: MutableList<Act> = mutableListOf(),
        var silent: Boolean = false, val readBy: MutableMap<String, Long> = mutableMapOf(),
    ) {
        val mine: Boolean get() = owner.isEmpty()
        /** A group's every person writes; a channel's owner and the administrators it named post (iOS canWrite). */
        val canWrite: Boolean get() = !left && (kind == GROUP || mine || me in admins)
        fun json(): JSONObject = JSONObject().put("id", id).put("k", kind).put("ti", title).put("ds", about).put("ow", owner).put("me", me)
            .put("mb", JSONArray().apply { members.forEach { put(JSONObject().put("s", it.seat).put("p", it.pipe)) } })
            .put("c", count).put("nm", JSONObject(names.toMap())).put("at", at).put("lf", left).put("ft", faceTag ?: "")
            .put("ad", JSONArray(admins)).put("sg", signs).put("rm", removed).apply { reacts?.let { put("rx", it) } }
            .apply {
                invite?.let { put("iv", it) }
                if (banned.isNotEmpty()) put("bn", JSONArray().apply { banned.forEach { put(JSONObject().put("s", it.seat).put("p", it.pipe)) } })
                if (acts.isNotEmpty()) put("ac", JSONArray().apply { acts.forEach { put(it.json()) } })
                if (silent) put("sl", true)
                if (readBy.isNotEmpty()) put("rb", JSONObject(readBy.toMap()))
            }
        companion object {
            fun of(o: JSONObject) = State(o.getString("id"), o.getString("k"), o.optString("ti"), o.optString("ds"), o.optString("ow"),
                o.getString("me"),
                o.optJSONArray("mb")?.let { a -> MutableList(a.length()) { i -> a.getJSONObject(i).let { Member(it.getString("s"), it.getString("p")) } } } ?: mutableListOf(),
                o.optInt("c", 2),
                o.optJSONObject("nm")?.let { n -> n.keys().asSequence().associateWith { n.getString(it) }.toMutableMap() } ?: mutableMapOf(),
                o.optLong("at"), o.optBoolean("lf"), o.optString("ft").ifEmpty { null },
                o.optJSONArray("ad")?.let { a -> MutableList(a.length()) { a.getString(it) } } ?: mutableListOf(),
                o.optBoolean("sg"), if (o.has("rx")) o.optBoolean("rx") else null, o.optBoolean("rm"),
                o.optString("iv").ifEmpty { null },
                o.optJSONArray("bn")?.let { a -> MutableList(a.length()) { i -> a.getJSONObject(i).let { Member(it.getString("s"), it.getString("p")) } } } ?: mutableListOf(),
                o.optJSONArray("ac")?.let { a -> MutableList(a.length()) { i -> Act.of(a.getJSONObject(i)) } } ?: mutableListOf(),
                o.optBoolean("sl"),
                o.optJSONObject("rb")?.let { r -> r.keys().asSequence().associateWith { r.optLong(it) }.toMutableMap() } ?: mutableMapOf())
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
    /** Each group's face as this phone keeps it (the row's own, Book.face): a copy lays it in its avatars (iOS MTGroupState.face). */
    fun facesHeld(): Map<String, File> = synchronized(lock) {
        if (!ready()) emptyMap() else groups.keys.associateWith { Book.face(key(it)) }.filterValues { it.isFile }
    }
    /**
     * THE GROUPS IN A COPY, AS THE IPHONE CARRIES THEM (iOS MTGroup.stateKey among SeedScope.dataKeys, MontanaChatStore.swift:6634-6635;
     * the Codable MTGroupState, MontanaGroup.swift:29-84): every group this person owns or was invited to, with the pipes of its people,
     * in the iPhone's field names and seconds; `faces` names each group's face as the copy's avatars hold it. None while there is none.
     */
    fun carried(faces: Map<String, String>): ByteArray? = synchronized(lock) {
        if (!ready() || groups.isEmpty()) return null
        fun seats(l: List<Member>) = JSONArray().apply { l.forEach { put(JSONObject().put("seat", it.seat).put("pipe", it.pipe)) } }
        val o = JSONObject()
        for ((id, g) in groups) o.put(id, JSONObject()
            .put("id", g.id).put("kind", g.kind).put("title", g.title).put("about", g.about).put("owner", g.owner).put("me", g.me)
            .put("members", seats(g.members)).put("count", g.count).put("names", JSONObject(g.names.toMap())).put("at", g.at / 1000.0)
            .apply {
                if (g.left) put("left", true)
                if (g.removed) put("removed", true)
                if (g.admins.isNotEmpty()) put("admins", JSONArray(g.admins))
                g.invite?.let { put("invite", it) }
                g.faceTag?.let { put("faceTag", it) }
                faces[id]?.let { put("face", it) }
                if (g.readBy.isNotEmpty()) put("readBy", JSONObject(g.readBy.toMap()))
                if (g.silent) put("silent", true)
                if (g.signs) put("signs", true)
                g.reacts?.let { put("reacts", it) }
                if (g.banned.isNotEmpty()) put("banned", seats(g.banned))
                if (g.acts.isNotEmpty()) put("acts", JSONArray().apply {
                    g.acts.forEach { a -> put(JSONObject().put("e", a.e).put("at", a.at / 1000.0).apply { a.p?.let { put("p", JSONArray(it)) }; a.t?.let { put("t", it) } }) }
                })
            })
        o.toString().toByteArray(Charsets.UTF_8)
    }
    /**
     * A COPY LAID (iOS layCard «d:groups.held», then MTGroup.reread): the copy's groups take their places here by their ids, their faces
     * out of the copy's avatars, and a group this phone is still in stands in the list. [COMPAT-LOCAL] a group this phone holds and the
     * copy does not stays: the iPhone lays the copy's store whole, which would leave a group born here after the copy without a state.
     */
    fun lay(raw: ByteArray, avatars: File?) {
        val taken = parse(raw, avatars)
        synchronized(lock) {
            if (!ready() || taken.isEmpty()) return
            for ((g, _) in taken) groups[g.id] = g
            save()
        }
        for ((g, face) in taken) if (!g.left) stand(g, face?.let { runCatching { it.readBytes() }.getOrNull() })
        Log.i("Montana", "groups_laid count=" + taken.size + " standing=" + taken.count { !it.first.left })
    }
    /**
     * A TEST BUILD'S CHECK OF THE COPY'S GROUPS (`am start … --ez groupsCopyTest true`): the groups in the iPhone's form written to
     * files/test/groups-held.json for a reader outside, read back by the copy's own reader, and each compared with what it was.
     */
    fun copyCheck(c: Context) {
        val raw = carried(emptyMap()) ?: run { Log.i("Montana", "groups_copy none"); return }
        runCatching { File(c.filesDir, "test").apply { mkdirs() }.resolve("groups-held.json").writeBytes(raw) }
        val back = parse(raw, null).associate { it.first.id to it.first.json().toString() }
        val held = synchronized(lock) { groups.mapValues { it.value.json().toString() } }
        val same = held.count { (id, j) -> back[id] == j }
        Log.i("Montana", "groups_copy bytes=" + raw.size + " groups=" + held.size + " back=" + back.size + " same=" + same + " ok=" + (if (same == held.size && back.size == held.size) 1 else 0))
    }
    private fun parse(raw: ByteArray, avatars: File?): List<Pair<State, File?>> {
        val o = runCatching { JSONObject(String(raw, Charsets.UTF_8)) }.getOrNull() ?: return emptyList()
        fun seats(a: JSONArray?) = a?.let { MutableList(it.length()) { i -> it.getJSONObject(i).let { m -> Member(m.getString("seat"), m.getString("pipe")) } } } ?: mutableListOf()
        fun ms(sec: Double) = Math.round(sec * 1000)
        val taken = ArrayList<Pair<State, File?>>()
        for (id in o.keys()) runCatching {
            val s = o.getJSONObject(id)
            if (id.isEmpty() || 64 < id.length || !id.all { it.isLetterOrDigit() || it == '-' || it == '_' } || s.optString("id", id) != id) return@runCatching
            val kind = s.optString("kind").takeIf { it == GROUP || it == CHANNEL } ?: return@runCatching
            val members = seats(s.optJSONArray("members"))
            val g = State(id, kind, s.optString("title"), s.optString("about"), s.optString("owner"), s.getString("me"), members,
                s.optInt("count", members.size + 1),
                s.optJSONObject("names")?.let { n -> n.keys().asSequence().associateWith { n.getString(it) }.toMutableMap() } ?: mutableMapOf(),
                ms(s.optDouble("at", 0.0)), s.optBoolean("left"), s.optString("faceTag").ifEmpty { null },
                s.optJSONArray("admins")?.let { a -> MutableList(a.length()) { a.getString(it) } } ?: mutableListOf(),
                s.optBoolean("signs"), if (s.has("reacts")) s.optBoolean("reacts") else null, s.optBoolean("removed"),
                s.optString("invite").ifEmpty { null }, seats(s.optJSONArray("banned")),
                s.optJSONArray("acts")?.let { a -> MutableList(a.length()) { i -> a.getJSONObject(i).let { x ->
                    Act(x.getString("e"), x.optJSONArray("p")?.let { p -> List(p.length()) { p.getString(it) } }, x.optString("t").ifEmpty { null }, ms(x.optDouble("at", 0.0)))
                } } } ?: mutableListOf(),
                s.optBoolean("silent"),
                s.optJSONObject("readBy")?.let { r -> r.keys().asSequence().associateWith { r.optLong(it) }.toMutableMap() } ?: mutableMapOf())
            val face = s.optString("face").takeIf { it.isNotEmpty() && MontanaBackup.plainName(it) }?.let { f -> avatars?.let { File(it, f) } }?.takeIf { it.isFile }
            taken.add(g to face)
        }
        return taken
    }
    /** The person leaves: their groups leave with them (iOS montanaSeedForgotten). */
    fun wipe() = synchronized(lock) {
        groups.clear(); gone.clear(); heard.clear(); copies.clear(); loaded = false; unread = false
        DeviceVault.delete(STORE); DeviceVault.delete(COPIES); DeviceVault.delete(TWIN_WAIT)
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
    /** Everyone writes in a group; in a channel the owner and the administrators it named (iOS 2235 canWrite). */
    fun canWrite(key: String): Boolean { val g = state(key) ?: return false; return !g.left && (g.kind == GROUP || g.mine || g.me in g.admins) }
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
    /** The role a speaker wears in the group (iOS 2235 role chip, MontanaConversation 4686-4690): the owner, an administrator, or none. */
    fun roleOf(ref: String?): Int? {
        val parts = ref?.takeIf { it.startsWith(SPEAKER_HEAD) }?.removePrefix(SPEAKER_HEAD)?.split("/", limit = 2) ?: return null
        if (parts.size != 2) return null
        val g = state(key(parts[0])) ?: return null
        return when { parts[1] == OWNER_SEAT -> R.string.gr_role_owner; parts[1] in g.admins -> R.string.gr_role_admin; else -> null }
    }
    /** The line above a speaker's bubble (iOS speakerLine): in a group every letter of another says who wrote it; a channel speaks as itself. */
    fun speakerLine(c: Context, m: Msg, chat: String): String? =
        if (m.mine || m.from?.startsWith(SPEAKER_HEAD) != true || state(chat)?.kind != GROUP) null else speakerName(c, m.from)
    /**
     * The pipe this phone holds to a speaker (iOS speakerPipe, MontanaGroup.swift:327-330): the owner's phone holds every member's, a
     * member's phone the owner's -- the others are known by their own words alone.
     */
    fun speakerPipe(ref: String?): String? {
        val parts = ref?.takeIf { it.startsWith(SPEAKER_HEAD) }?.removePrefix(SPEAKER_HEAD)?.split("/", limit = 2) ?: return null
        if (parts.size != 2) return null
        val g = state(key(parts[0])) ?: return null
        return if (!g.mine && parts[1] == OWNER_SEAT) g.owner else g.members.firstOrNull { it.seat == parts[1] }?.pipe
    }
    /** Taken out by the owner, not gone by one's own hand (iOS state.removed): a channel's chat then says «Join», answering nothing. */
    fun isRemoved(key: String) = state(key)?.removed == true

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
        // ONLY A LETTER AND AN INVITATION RING (iOS carry): every other word of a group rides silent -- a silent channel post too. A
        // ringing copy rides to the person's other devices too, as the word it is (Post.send → Twin.sent, iOS enqueue 963-972)
        val t = w.optString("t")
        Post.send(pipe, name, MARK + w.toString(), quiet = !(t == "say" || t == "inv") || w.optInt("sl") == 1)
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
            if (g == null || !g.canWrite || words.isBlank()) {
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
                if (g.kind == CHANNEL && g.silent) w.put("sl", 1)   // the bell in the owner's field (iOS Silent Broadcast)
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
            if (g == null || !g.canWrite || !letter.startsWith(Marks.MEDIA) || !carries(letter) || !isLetterName(mid)) {
                Log.i("Montana", "group_refused media -- group=" + (if (g == null) 0 else 1))
                return false
            }
            val w = word("say", g).put("id", mid).put("s", g.me).put("tx", letter)
            if (g.kind == CHANNEL && g.silent) w.put("sl", 1)   // the bell in the owner's field (iOS Silent Broadcast)
            return spread(w, g, null, own = true) > 0
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
            if (text.startsWith(PIN_MARK) && g.kind != GROUP) return   // a channel has no pin for everyone (iOS pins)
            spread(word("sig", g).put("id", Marks.mintMid()).put("s", g.me).put("tx", text), g, null, own = false)
            // A PIN LAYS THE REFERENCE'S SERVICE ROW (iOS MTGroup.pin): «You pinned "..."», by the pinned letter's own words
            if (text.startsWith(PIN_MARK)) runCatching {
                val o = JSONObject(text.removePrefix(PIN_MARK))
                val t = o.getString("sid").removePrefix("mid:")
                val row = Book.chat(key)?.msgs?.firstOrNull { it.mid == t }
                if (o.optString("op") == "pin" && row != null) lay(event("pinned", g.id, g.me, t = pinWords(row)))
            }
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
            // a channel may start before it has subscribers (iOS create)
            if (!ready() || name.isEmpty() || (!channel && pipes.isEmpty())) {
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
            lay(event("made", id, OWNER_SEAT, t = name))   // «You created the group»
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
            if (g.admins.isNotEmpty()) w.put("ad", JSONArray(g.admins))   // the administrators the owner named (stage R.6)
            if (g.kind == CHANNEL && g.signs) w.put("sg", 1)   // a channel signs its posts (Sign Messages)
            if (g.kind == CHANNEL && g.reacts == false) w.put("rx", 0)   // a channel takes no reactions (Allow Reactions off)
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
    fun renew(key: String, title: String, face: ByteArray?, about: String? = null) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left) return
            val name = clean(title, TITLE_LIMIT)
            // the description, the owner's words about the group (stage R): carried in the invitation's «ds», as at the group's birth
            val words = about?.let { clean(it, ABOUT_LIMIT) }
            val described = words != null && words != g.about
            if (name.isEmpty() || (name == g.title && face == null && !described)) return
            val renamed = name != g.title
            if (renamed) act(g, "title", t = name)
            if (described) act(g, "about")
            if (face != null) act(g, "photo")
            g.title = name
            if (words != null) g.about = words
            save()
            stand(g, face)
            tellAll(g, face?.let { thumb(it) })
            if (renamed) lay(event("named", g.id, OWNER_SEAT, t = name))
            if (face != null) lay(event("face", g.id, OWNER_SEAT))
            Log.i("Montana", "group_renewed face=" + (if (face == null) 0 else 1))
        }
    }

    /**
     * THE OWNER ADDS PEOPLE (iOS add): each new one is invited with a seat of their own and the group's face; everyone learns the
     * count, the group reads who came, and a subscriber added to a channel later reads its newest posts. `viaLink` — one who opened
     * the group's link joined by their own hand (iOS «%@ joined the group via invite link»). `quiet` — one the other device of these
     * words let in by the link stands here too, and nobody is told from here: that device told them (Windows admit).
     */
    fun add(key: String, people: List<String>, viaLink: Boolean = false, quiet: Boolean = false) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left) return
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
            // one taken out and added again by the owner's own hand is let back (iOS «Add To Channel»)
            g.banned.removeAll { b -> fresh.any { it.pipe == SamePair.root(b.pipe) } }
            act(g, if (viaLink) "joined" else "invited", p = fresh.map { seatName(g, it.seat) })
            save()
            if (!quiet) tellAll(g, Book.face(key).takeIf { it.exists() }?.readBytes()?.let { thumb(it) }, fresh.map { it.seat }.toSet())
            val came = if (viaLink) event("joined", g.id, fresh[0].seat) else event("added", g.id, OWNER_SEAT, fresh.map { it.seat })
            lay(came)
            if (!quiet) tellEvent(came, g)
            // A SUBSCRIBER ADDED LATER READS THE CHANNEL'S NEWEST POSTS (iOS add, the author's words 17.10.2026 18:4x MSK): the newest
            // ten posts of words, each under its own one name and so at its own moment; a post with a file stays -- its sealed pieces
            // were laid for the receivers of its day
            if (g.kind == CHANNEL && !quiet) {
                val posts = Book.chat(key)?.msgs.orEmpty().filter { it.mine && it.file == null && !it.text.startsWith(Marks.MEDIA) && !isEvent(it.text) && carries(it.text) }
                for (p in posts.takeLast(10)) {
                    if (!isLetterName(p.mid)) continue
                    val w = word("say", g).put("id", p.mid).put("s", g.me).put("tx", p.text)
                    if (!p.qt.isNullOrEmpty()) w.put("qt", p.qt)
                    for (m in fresh) carry(w, m.pipe, "", own = false)
                }
            }
            Log.i("Montana", "group_added people=" + fresh.size + " count=" + g.count)
        }
    }

    /**
     * THE OWNER TAKES A PERSON OUT (iOS remove): told by their own word, carried to no more; everyone left learns the count and reads
     * who did it -- `by`, an administrator's deed says its own name. One taken out of a channel does not come back by its link.
     */
    fun remove(key: String, seat: String, by: String = OWNER_SEAT) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left) return
            val m = g.members.firstOrNull { it.seat == seat } ?: return
            if (g.kind == CHANNEL) {
                g.banned.removeAll { it.seat == seat }; g.banned.add(m)
                while (g.banned.size > PEOPLE_LIMIT) g.banned.removeAt(0)
            }
            act(g, "removed", p = listOf(seatName(g, seat)))
            g.members.removeAll { it.seat == seat }
            g.admins.remove(seat)   // a person taken out is nobody's administrator
            g.count = g.members.size + 1
            save()
            carry(JSONObject().put("t", "out").put("g", g.id), m.pipe, "", own = false)
            tellAll(g, null)
            val out = event("removed", g.id, by, listOf(seat))
            lay(out)
            tellEvent(out, g)
            Log.i("Montana", "group_removed count=" + g.count)
        }
    }

    /**
     * DELETE FOR ALL (iOS dissolve, the owner's «Delete Group»): every member is told by the owner's own «out» marked as the group's
     * end -- a build that reads the mark erases the chat, an older one stands it read-only -- and the chat leaves this phone, the
     * group known as ended here.
     */
    fun dissolve(key: String) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left) return
            val w = JSONObject().put("t", "out").put("g", g.id).put("dl", 1)
            for (m in g.members) carry(w, m.pipe, "", own = false)
            g.left = true
            g.members.clear()
            save()
            Log.i("Montana", "group_dissolved by its owner")
        }
        erase(key)
    }
    /**
     * DELETE AND EXIT (iOS erase): the chat and its rows leave this phone; the group stays known as one this phone is out of, so a
     * word still on its way finds its road over -- only the owner adding this phone again stands it anew.
     */
    fun erase(key: String) {
        if (state(key)?.left != true) return
        Thread { Book.forget(key) }.start()
        Log.i("Montana", "group_erased")
    }
    /** LEAVE GROUP (iOS leaveAndErase): the owner is told, and the chat goes. */
    fun leaveAndErase(key: String) { leave(key); erase(key) }
    /** What the head of a group's chat says once this phone is out of it (iOS outWords). */
    fun outWords(c: Context, key: String): String? {
        val g = state(key) ?: return null
        if (!g.left) return null
        val channel = g.kind == CHANNEL
        return c.getString(if (g.removed) (if (channel) R.string.gr_out_removed_channel else R.string.gr_out_removed_group)
            else (if (channel) R.string.gr_out_left_channel else R.string.gr_out_left_group))
    }

    // ── administrators and a channel's own settings (iOS stage R.6, the reference folder: «Promote», «Dismiss Admin») ──

    /** A DEED OF A CHANNEL, WRITTEN ON ITS OWNER'S PHONE (iOS act): a group keeps its events in its feed instead. */
    private fun act(g: State, e: String, p: List<String>? = null, t: String? = null) {
        if (g.kind != CHANNEL || !g.mine) return
        g.acts.add(Act(e, p, t, System.currentTimeMillis()))
        while (g.acts.size > ACTS_KEPT) g.acts.removeAt(0)
    }
    /** The name a seat of a group is known by on this phone, as the page lists it (iOS seatName): a member's, a removed one's, a speaker's. */
    private fun seatName(g: State, seat: String): String {
        val pipe = g.members.firstOrNull { it.seat == seat }?.pipe ?: g.banned.firstOrNull { it.seat == seat }?.pipe
            ?: (if (!g.mine && seat == OWNER_SEAT) g.owner else null)
        val book = pipe?.let { Book.chat(SamePair.root(it))?.shown }?.ifBlank { null }
        return book ?: g.names[seat]?.ifEmpty { null } ?: Book.ctx.getString(R.string.gr_member)
    }
    /** Whether a seat is an administrator the owner named. */
    fun isAdmin(key: String, seat: String) = state(key)?.admins?.contains(seat) == true
    /** Whether this phone moderates the group: its owner, or an administrator it named -- they take another's letter away for everyone. */
    fun moderates(key: String): Boolean { val g = state(key) ?: return false; return !g.left && (g.mine || g.me in g.admins) }
    /** THE OWNER NAMES OR DISMISSES AN ADMINISTRATOR (iOS setAdmin): every member hears the list by the invitation's word again. */
    fun setAdmin(key: String, seat: String, on: Boolean) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left || g.members.none { it.seat == seat }) return
            if (on) { if (seat !in g.admins) g.admins.add(seat) } else g.admins.remove(seat)
            g.admins.sort()
            act(g, if (on) "promoted" else "demoted", p = listOf(seatName(g, seat)))
            save()
            tellAll(g, null)
            Log.i("Montana", "group_admin " + if (on) "named" else "dismissed")
        }
    }
    /**
     * AN ADMINISTRATOR TAKES A PERSON OUT (iOS kick): the owner's phone carries the group, so the word goes to the owner, who takes the
     * person out as by its own hand -- never the owner, never another administrator.
     */
    fun kick(key: String, seat: String) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (g.left) return
            if (g.mine) { remove(key, seat); return }
            if (g.me !in g.admins || seat == OWNER_SEAT || seat == g.me || seat in g.admins) return
            carry(JSONObject().put("t", "kk").put("g", g.id).put("id", Marks.mintMid()).put("s", seat), g.owner, "", own = false)
            Log.i("Montana", "group_admin asked the owner to take a person out")
        }
    }
    /** WHETHER THE OWNER'S NEXT POSTS GO WITHOUT SOUND (iOS silent, the bell in a channel's field): its owner's choice, kept on its state. */
    fun silent(key: String) = state(key)?.silent == true
    fun setSilent(key: String, on: Boolean) {
        synchronized(lock) { val g = state(key) ?: return; if (!g.mine || g.left || g.kind != CHANNEL) return; g.silent = on; save() }
    }
    /** Whether a channel's posts take reactions (iOS reactionsOn, Allow Reactions): on unless its owner turned them off. */
    fun reactionsOn(key: String) = state(key)?.reacts != false
    /** THE OWNER ALLOWS REACTIONS OR TURNS THEM OFF (iOS setReactions): every subscriber hears it by the invitation's word again. */
    fun setReactions(key: String, on: Boolean) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left || g.kind != CHANNEL) return
            g.reacts = if (on) null else false
            act(g, if (on) "reactOn" else "reactOff")
            save()
            tellAll(g, null)
        }
    }
    /** Whether a channel signs its posts (iOS Sign Messages). */
    fun signsOn(key: String) = state(key)?.signs == true
    /** THE OWNER SIGNS THE CHANNEL'S POSTS OR STOPS (iOS setSigns): every subscriber hears it by the invitation's word again. */
    fun setSigns(key: String, on: Boolean) {
        synchronized(lock) {
            val g = state(key) ?: return
            if (!g.mine || g.left || g.kind != CHANNEL) return
            g.signs = on
            act(g, if (on) "signOn" else "signOff")
            save()
            tellAll(g, null)
        }
    }
    /** The name a signed channel's post wears in its stamp (iOS signature): its writer's; null where the channel does not sign. */
    fun signature(c: Context, m: Msg, key: String): String? {
        val g = state(key) ?: return null
        if (g.kind != CHANNEL || !g.signs) return null
        if (m.mine) return clean(Prefs.userName, NAME_LIMIT).ifEmpty { null }
        val ref = m.from?.takeIf { it.startsWith(SPEAKER_HEAD) } ?: return null
        val name = speakerName(c, ref)
        return if (name == c.getString(R.string.gr_member)) null else name
    }
    /** THE OWNER LETS A REMOVED PERSON BACK BY THE LINK (iOS unban, the reference's «Removed Users»). */
    fun unban(key: String, seat: String) {
        synchronized(lock) { val g = state(key) ?: return; if (!g.mine || g.left) return; if (g.banned.removeAll { it.seat == seat }) save() }
    }
    /** The people its owner took out of a channel, by the names they were known by (iOS bannedPeople). */
    fun bannedPeople(key: String): List<Seat> { val g = state(key) ?: return emptyList(); return g.banned.map { Seat(it.seat, seatName(g, it.seat), it.pipe) } }
    /** What was done in a channel, the newest last (iOS acts, its Recent Actions). */
    fun acts(key: String): List<Act> = state(key)?.acts?.toList().orEmpty()
    /** The owner's administrators (iOS admins). */
    fun admins(key: String): List<String> = state(key)?.admins?.toList().orEmpty()

    // ── the group's invite link (iOS stage R.6, the reference folder: «Invite Link», «joined the group via invite link») ──

    /**
     * The link the owner hands out (iOS inviteLink): its own card -- whoever opens it meets the owner, the one road of a link -- and the
     * group's mark after it. Null: no card stands yet, or this phone is no owner of the group.
     */
    fun inviteLink(c: Context, key: String): String? {
        if (state(key)?.mine != true) return null
        // iOS MontanaCard.offerStanding: the name's web link while a name is held, else the permanent card
        val card = Names.heldName?.takeIf { it.isNotEmpty() }?.let { "https://montana.quest/n/$it" } ?: MontanaCard.offerPermanent(c) ?: return null
        synchronized(lock) {
            val g = state(key) ?: return null
            if (!g.mine || g.left) return null
            if (g.invite == null) { g.invite = mintId(); save() }
            return card + (if ('?' in card) "&" else "?") + JOIN_PARAM + "=" + g.id + "." + g.invite
        }
    }
    /** A new mark: every link given before opens nothing more (iOS resetInvite, the reference's «Reset Link»). */
    fun resetInvite(key: String) {
        synchronized(lock) { val g = state(key) ?: return; if (!g.mine || g.left) return; g.invite = mintId(); save(); Log.i("Montana", "group_link reset") }
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

    // ── the group's events: rows in the middle of its feed (iOS MTGroupEvent, lay, tellEvent, evented, eventWords) ──

    /** A group's event row: its kind, the group, the seat that did it, the seats it was about, a title (iOS MTGroupEvent). */
    private fun event(e: String, g: String, a: String, p: List<String>? = null, t: String? = null): JSONObject =
        JSONObject().put("e", e).put("g", g).put("a", a).apply { if (!p.isNullOrEmpty()) put("p", JSONArray(p)); if (t != null) put("t", t) }
    /** Whether a row is a group's event, no letter: no bubble, no menu, no rung (iOS MTRowLetter.ownRow). */
    fun isEvent(text: String) = text.startsWith(EVENT_MARK)
    /**
     * AN EVENT OF THE GROUP STANDS IN ITS FEED (iOS lay, ChatStore.appendGroupEvent): laid on this phone, in the middle of the feed as
     * the day is -- this phone's own row, read and done, never on the wire. A channel keeps its deeds in its Recent Actions instead.
     */
    private fun lay(e: JSONObject) {
        val g = groups[e.optString("g")] ?: return
        if (g.kind != GROUP) return
        val key = key(g.id)
        val at = System.currentTimeMillis()
        Book.edit(key) { c -> c.msgs.add(Msg(Marks.mintMid(), EVENT_MARK + e.toString(), true, at, state = 3)) }
        Log.i("Montana", "group_event laid e=" + e.optString("e"))
    }
    /** The owner tells everyone else who came, who was taken out, who left -- by seat, never by a name of the owner's (iOS tellEvent). */
    private fun tellEvent(e: JSONObject, g: State) {
        if (!g.mine || g.kind != GROUP) return
        val w = JSONObject().put("t", "ev").put("g", g.id).put("id", Marks.mintMid()).put("s", OWNER_SEAT).put("tx", e.toString())
        val about = e.optJSONArray("p")?.let { a -> (0 until a.length()).map { a.optString(it) }.toSet() }.orEmpty()
        for (m in g.members) if (m.seat !in about) carry(w, m.pipe, "", own = false)
    }
    /** AN EVENT FROM THE OWNER (its «ev», iOS evented): taken from the owner's pipe alone, about seats alone, once by its name. */
    private fun evented(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.WAIT
        if (g.left || g.mine || SamePair.root(g.owner) != SamePair.root(pipe)) return Verdict.REFUSED
        val id = w.optString("id"); val tx = w.optString("tx")
        if (!isLetterName(id) || tx.isEmpty() || tx.toByteArray().size > 4096) return Verdict.REFUSED
        val e = runCatching { JSONObject(tx) }.getOrNull() ?: return Verdict.REFUSED
        val kind = e.optString("e")
        if (kind !in setOf("added", "removed", "left", "joined") || !isSeat(e.optString("a"))) return Verdict.REFUSED
        if (id in heard) return Verdict.HELD
        remember(id)
        val about = e.optJSONArray("p")?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { isSeat(it) }.take(PEOPLE_LIMIT) }.orEmpty()
        lay(event(kind, g.id, e.optString("a"), about.ifEmpty { null }))
        return Verdict.HELD
    }
    /** The sentence an event's row says on this phone (iOS eventWords): the people by the names this group knows them by, «you» for this phone. */
    fun eventWords(c: Context, text: String): String? {
        val e = runCatching { JSONObject(text.removePrefix(EVENT_MARK)) }.getOrNull() ?: return null
        val gid = e.optString("g")
        val me = state(key(gid))?.me
        val a = e.optString("a")
        val mine = a == me
        val who = if (mine) "" else speakerName(c, speaker(gid, a))
        val about = e.optJSONArray("p")?.let { arr -> (0 until arr.length()).map { arr.optString(it) } }.orEmpty()
        val you = me != null && me in about
        val names = about.filter { it != me }.joinToString(", ") { speakerName(c, speaker(gid, it)) }
        val title = e.optString("t")
        return when (e.optString("e")) {
            "made" -> if (mine) c.getString(R.string.ge_made_you, title) else c.getString(R.string.ge_made, who, title)
            "added" -> if (mine) c.getString(R.string.ge_added_you_did, names) else if (you) c.getString(R.string.ge_added_you, who) else c.getString(R.string.ge_added, who, names)
            "removed" -> if (mine) c.getString(R.string.ge_removed_you_did, names) else if (you) c.getString(R.string.ge_removed_you, who) else c.getString(R.string.ge_removed, who, names)
            "left" -> if (mine) c.getString(R.string.ge_left_you) else c.getString(R.string.ge_left, who)
            "joined" -> if (mine) c.getString(R.string.ge_joined_you) else c.getString(R.string.ge_joined, who)
            "named" -> if (mine) c.getString(R.string.ge_named_you, title) else c.getString(R.string.ge_named, who, title)
            "face" -> if (mine) c.getString(R.string.ge_face_you) else c.getString(R.string.ge_face, who)
            "pinned" -> if (mine) c.getString(R.string.ge_pinned_you, title) else c.getString(R.string.ge_pinned, who, title)
            "call" -> when {
                e.optString("k") == "live" -> if (mine) c.getString(R.string.ge_live_you) else c.getString(R.string.ge_live, who)
                e.optInt("v") == 1 -> if (mine) c.getString(R.string.ge_video_you) else c.getString(R.string.ge_video, who)
                else -> if (mine) c.getString(R.string.ge_voice_you) else c.getString(R.string.ge_voice, who)
            }
            "ended" -> {
                val span = span(e.optInt("d"))
                c.getString(if (e.optString("k") == "live") R.string.ge_live_ended else if (e.optInt("v") == 1) R.string.ge_video_ended else R.string.ge_voice_ended, span)
            }
            else -> null
        }
    }
    /** A room's length as the reference's row says it (iOS span): minutes and seconds, hours when it ran past one. */
    fun span(seconds: Int): String {
        val s = maxOf(0, seconds)
        return if (3600 <= s) "%d:%02d:%02d".format(s / 3600, s % 3600 / 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
    }
    /** The pinned letter's words as its service row quotes them (iOS pinWords): the list's own words, cut at forty letters. */
    private fun pinWords(m: Msg): String {
        val w = letterWords(Book.ctx, m)
        return if (w.length <= 40) w else w.take(40) + "…"
    }

    // ── typing (iOS the checklist's B.12, the reference's «X is typing» in a group's head) ──

    /** The moment the owner last threw a member's typing on: once in two seconds a member, whatever it sends (iOS typingThrown, I-15). */
    private val typingThrown = HashMap<String, Long>()
    /**
     * A GROUP'S TYPING WORD LIVES AN INSTANT (iOS MTGroup.typing): thrown at the pipes this phone holds for the group on the live lane
     * -- the owner's phone at every member, a member's at the owner -- never queued, never receipted, never written. Typing is presence:
     * a phone that hides its presence says none, and none to a person it blocked.
     */
    fun typing(key: String) {
        if (!Presence.sharing) return
        val (w, pipes) = synchronized(lock) {
            val g = state(key) ?: return
            if (!g.canWrite || g.kind != GROUP) return
            val w = JSONObject().put("t", "ty").put("g", g.id)
            clean(Prefs.userName, NAME_LIMIT).takeIf { it.isNotEmpty() }?.let { w.put("n", it) }
            w.put("s", g.me) to (if (g.mine) g.members.map { it.pipe } else listOf(g.owner))
        }
        throwTyping(w, pipes)
    }
    private fun throwTyping(w: JSONObject, pipes: List<String>) {
        val text = MARK + w.toString()
        for (p in pipes) if (Book.secret(p) != null && !PeerSafety.isBlocked(p)) Signal.post(p, text)
    }
    /** A group's word heard on the live lane (Presence.hear): only a typing word rides there; it is answered by nothing. */
    fun hearLive(pipe: String, text: String) {
        val w = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull() ?: return
        if (w.optString("t") == "ty" && isLabel(w.optString("g"))) typed(w, pipe)
    }
    /** The head's line while someone types, null when nobody does (iOS MTGroupTyping.line): one name, two names, a name and how many others. */
    fun typingLine(c: Context, key: String): String? {
        val names = typingNames(c, key)
        return when (names.size) {
            0 -> null
            1 -> c.getString(R.string.gr_typing_one, names[0])
            2 -> c.getString(R.string.gr_typing_two, names[0], names[1])
            else -> c.getString(R.string.gr_typing_many, names[0], (names.size - 1).toString())
        }
    }

    // ── read (iOS the checklist's B.13, the reference's small group: a letter read, and who saw it) ──

    /** How far this phone told each group it read (iOS readTold): one word a moment, and only when the mark moved. */
    private val readTold = HashMap<String, Long>()
    /** How far the owner told the speakers each reader read, by group and reader (iOS readSpread). */
    private val readSpread = HashMap<String, Long>()
    /**
     * THIS PHONE READ THE GROUP (iOS tellRead, from ChatStore.sendReadMark on the chat's own terms: on screen, the app active): the
     * birth millisecond of the newest letter of another before its eyes, told as its own word «rd» to the owner, who tells each
     * speaker it covers; the owner's own reading goes to them straight. Never with «Read receipts» off.
     */
    fun tellRead(key: String) {
        if (!Prefs.bool("readReceiptsEnabled", true)) return
        synchronized(lock) {
            val g = state(key) ?: return
            if (g.kind != GROUP || g.left) return
            val ms = Book.chat(key)?.msgs.orEmpty().filter { !it.mine && !isEvent(it.text) }.mapNotNull { Marks.birthMs(it.mid) }.maxOrNull() ?: return
            if ((readTold[g.id] ?: 0L) >= ms) return
            readTold[g.id] = ms
            if (g.mine) spreadRead(g, g.me, ms)
            else carry(JSONObject().put("t", "rd").put("g", g.id).put("id", Marks.mintMid()).put("s", g.me).put("tx", ms.toString()), g.owner, "", own = false)
            Log.i("Montana", "read_tx group upto=" + Diary.shortMs(ms))
        }
    }
    /** THE OWNER TELLS EACH SPEAKER A READER REACHED (iOS spreadRead): the seats of the letters born after the reader's last mark. */
    private fun spreadRead(g: State, reader: String, ms: Long) {
        val key = key(g.id)
        val head = speaker(g.id, "")
        val k = g.id + "/" + reader
        val since = readSpread[k] ?: 0L
        if (since >= ms) return
        readSpread[k] = ms
        val speakers = HashSet<String>()
        for (r in Book.chat(key)?.msgs.orEmpty()) {
            if (isEvent(r.text)) continue
            val born = Marks.birthMs(r.mid) ?: continue
            if (born <= since || born > ms) continue
            val seat = if (r.mine) g.me else r.from?.takeIf { it.startsWith(head) }?.removePrefix(head).orEmpty()
            if (seat.isNotEmpty() && seat != reader) speakers.add(seat)
        }
        if (g.me in speakers) readMine(g.id, reader, ms)
        for (m in g.members) if (m.seat in speakers) {
            val w = JSONObject().put("t", "rd").put("g", g.id).put("id", Marks.mintMid()).put("s", reader).put("tx", ms.toString()).put("ts", JSONArray(listOf(m.seat)))
            carry(w, m.pipe, "", own = false)
        }
    }
    /** A READER REACHED MY LETTERS (iOS readMine): their mark kept, every letter of mine born up to it raised to read -- delivered first. */
    private fun readMine(gid: String, reader: String, ms: Long) {
        val g = groups[gid] ?: return
        if (reader == g.me || (g.readBy[reader] ?: 0L) >= ms) return
        g.readBy[reader] = ms
        save()
        var raised = 0
        Book.edit(key(gid)) { c ->
            for (r in c.msgs) if (r.mine && !isEvent(r.text)) {
                val born = Marks.birthMs(r.mid) ?: continue
                if (born <= ms) { r.advance(2); if (r.advance(3)) raised++ }
            }
        }
        Log.i("Montana", "read_rx group upto=" + Diary.shortMs(ms) + " raised=" + raised)
    }
    /** A READER'S WORD (iOS readWord): at the owner the reader's seat is the pipe's own; at a member, the owner's word for a reader of mine.
     *  `quiet` (Windows group_handle «rd»): the copy reads my letters here; the carrying was the other device's. */
    private fun readWord(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.WAIT
        val ms = w.optString("tx").toLongOrNull()
        if (g.left || g.kind != GROUP || ms == null || ms <= 0) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        if (g.mine) {
            val m = g.members.firstOrNull { SamePair.root(it.pipe) == from } ?: return Verdict.REFUSED
            if (quiet) readMine(g.id, m.seat, ms) else spreadRead(g, m.seat, ms)
        } else {
            val s = w.optString("s")
            val ts = w.optJSONArray("ts")
            val forMe = ts == null || (0 until ts.length()).any { ts.optString(it) == g.me }
            if (SamePair.root(g.owner) != from || !isSeat(s) || s == g.me || !forMe) return Verdict.REFUSED
            readMine(g.id, s, ms)
        }
        return Verdict.HELD
    }
    /** THE READERS OF A LETTER OF MINE, BY NAME (iOS seenBy, the reference's «N Seen»): the seats whose mark covers its birth. */
    fun seenBy(c: Context, m: Msg, key: String): List<String>? {
        val g = state(key) ?: return null
        if (g.kind != GROUP || !m.mine || isEvent(m.text)) return null
        val ms = Marks.birthMs(m.mid) ?: return null
        return g.readBy.filter { ms <= it.value }.keys.map { speakerName(c, speaker(g.id, it)) }.sortedWith(String.CASE_INSENSITIVE_ORDER)
    }

    // ── a channel's views (iOS the reference's eye under a post; MTChannelViews) ──

    /**
     * A SUBSCRIBER'S SCREEN SHOWED POSTS (iOS tellSeen): their names go to the owner alone, silent, for its count. False -- no pipe to
     * the owner now, and the posts wait. A read receipt: with «Read receipts» off the word never leaves.
     */
    fun tellSeen(letters: List<String>, key: String): Boolean {
        if (!Prefs.bool("readReceiptsEnabled", true) || letters.isEmpty()) return false
        synchronized(lock) {
            val g = state(key) ?: return false
            if (g.kind != CHANNEL || g.mine || g.left) return false
            val w = JSONObject().put("t", "vw").put("g", g.id).put("id", Marks.mintMid()).put("s", g.me).put("tx", letters.take(VIEWS_BATCH).joinToString(","))
            return carry(w, g.owner, "", own = false) != null
        }
    }
    /** THE OWNER TELLS THE NUMBERS THAT MOVED (iOS tellCounts): one silent word to every subscriber. */
    fun tellCounts(numbers: Map<String, Int>, key: String) {
        if (numbers.isEmpty()) return
        synchronized(lock) {
            val g = state(key) ?: return
            if (g.kind != CHANNEL || !g.mine || g.left) return
            val w = JSONObject().put("t", "vc").put("g", g.id).put("id", Marks.mintMid()).put("s", OWNER_SEAT).put("tx", JSONObject(numbers).toString())
            for (m in g.members) carry(w, m.pipe, "", own = false)
        }
    }
    /** A subscriber's posts shown, at the owner's phone (iOS seen): the seat is the pipe's, and only posts of this channel's feed count. */
    private fun seen(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.WAIT
        val tx = w.optString("tx")
        val from = SamePair.root(pipe)
        val m = g.members.firstOrNull { SamePair.root(it.pipe) == from }
        if (!g.mine || g.kind != CHANNEL || g.left || tx.isEmpty() || tx.toByteArray().size > 16_384 || m == null) return Verdict.REFUSED
        val key = key(g.id)
        val posts = Book.chat(key)?.msgs.orEmpty().filter { !isEvent(it.text) }.map { it.mid }.toSet()
        val letters = tx.split(",").take(VIEWS_BATCH).filter { isLetterName(it) && it in posts }
        ChannelViews.saw(letters, m.seat, key, tell = !quiet)
        return Verdict.HELD
    }
    /** The owner's numbers, at a subscriber's phone (iOS counted): from the owner's pipe alone. */
    private fun counted(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.WAIT
        val tx = w.optString("tx")
        if (g.mine || g.kind != CHANNEL || g.left || SamePair.root(g.owner) != SamePair.root(pipe) || tx.isEmpty() || tx.toByteArray().size > 16_384) return Verdict.REFUSED
        val o = runCatching { JSONObject(tx) }.getOrNull() ?: return Verdict.REFUSED
        val numbers = HashMap<String, Int>()
        for (k in o.keys()) if (isLetterName(k)) numbers[k] = o.optInt(k)
        ChannelViews.told(numbers, key(g.id))
        return Verdict.HELD
    }
    /** Whether this phone owns the channel a views' question is about (ChannelViews.views). */
    fun ownsChannel(key: String): Boolean = state(key)?.let { it.mine && it.kind == CHANNEL } == true

    // ── the owner's side of the other words: an administrator's «take out», a join by the link, a keeper's word ──

    /** An administrator's «take out» at the owner's phone (iOS kicked): the asker must be an administrator, the person a member who is none. */
    private fun kicked(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.REFUSED
        if (!g.mine || g.left) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        val asker = g.members.firstOrNull { SamePair.root(it.pipe) == from } ?: return Verdict.REFUSED
        val target = w.optString("s")
        if (asker.seat !in g.admins || target.isEmpty() || target == asker.seat || target in g.admins || g.members.none { it.seat == target }) return Verdict.REFUSED
        // the device that took the word takes the person out and tells everyone (Windows group_handle «kk»: quiet holds it)
        if (!quiet) remove(key(g.id), target, by = asker.seat)
        return Verdict.HELD
    }
    /**
     * ONE WHO OPENED THE GROUP'S LINK ASKS AT THE OWNER'S PHONE (iOS joined): the mark must be the group's standing one; one the owner
     * took out does not come back by it; then the person is added by the owner's own road, and everyone reads that they joined.
     */
    private fun joined(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.REFUSED
        val held = g.invite
        if (!g.mine || g.left || held == null || w.optString("tx") != held) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        if (g.members.any { SamePair.root(it.pipe) == from }) return Verdict.HELD   // already in: nothing more
        if (g.banned.any { SamePair.root(it.pipe) == from }) { Log.i("Montana", "group_link a removed person asked by the link -- refused"); return Verdict.REFUSED }
        add(key(g.id), listOf(from), viaLink = true, quiet = quiet)
        Log.i("Montana", "group_link joined by the link")
        return Verdict.HELD
    }
    /**
     * A LETTER TAKEN AWAY FOR EVERYONE STAYS ON THIS PHONE (iOS tellKept, MTLevelAccess.keepDeleted): the one who took it away alone is
     * told, by the keeper's own word «kp» -- the owner carries it to that seat; in a channel the speaker is its owner. An older build
     * refuses the word and receipts it: its speaker is not told there.
     */
    private fun tellKept(sid: String, seat: String, key: String) {
        val g = state(key) ?: return
        if (g.left || seat == g.me) return
        val w = JSONObject().put("t", "kp").put("g", g.id).put("id", Marks.mintMid()).put("s", g.me).put("tx", Marks.DELETE_KEPT + sid).put("ts", JSONArray(listOf(seat)))
        if (g.mine) g.members.firstOrNull { it.seat == seat }?.let { carry(w, it.pipe, "", own = false) }
        else carry(w, g.owner, "", own = false)
        Log.i("Montana", "delete_kept group word to seat=$seat")
    }
    /**
     * A KEEPER'S WORD (iOS keptHeard, «kp»): a letter taken away for everyone stays on the keeper's phone; the owner carries the word on
     * to the speaker's seat, and the speaker is told.
     */
    private fun keptHeard(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.optString("g")] ?: return Verdict.REFUSED
        val to = w.optJSONArray("ts")?.optString(0).orEmpty()
        if (g.left || to.isEmpty() || !w.optString("tx").startsWith(Marks.DELETE_KEPT)) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        if (g.mine) {
            if (g.members.none { SamePair.root(it.pipe) == from }) return Verdict.REFUSED   // a member's word alone
            if (to != g.me) { if (!quiet) g.members.firstOrNull { it.seat == to }?.let { carry(w, it.pipe, "", own = false) }; return Verdict.HELD }
        } else if (SamePair.root(g.owner) != from || to != g.me) return Verdict.REFUSED
        Notify.kept(key(g.id))
        return Verdict.HELD
    }

    // ── the people a page and a «@» name ──

    /**
     * THE PEOPLE OF A GROUP'S PAGE (iOS pagePeople): the owner's phone everyone it carries to; a member's phone the owner first, then
     * everyone who spoke -- the owner names nobody, the others come by their own words.
     */
    fun pagePeople(c: Context, key: String): List<Seat> {
        val g = state(key) ?: return emptyList()
        val out = shownSeats(c, key).toMutableList()
        if (!g.mine) {
            g.names.filter { (s, _) -> s != OWNER_SEAT && s != g.me && out.none { it.seat == s } }
                .entries.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.value })
                .forEach { (s, n) -> out.add(Seat(s, n, "")) }
        }
        return out
    }
    /** This phone's own seat in the group (iOS state.me). */
    fun mySeat(key: String): String? = state(key)?.me
    /** The people in the group, the owner included (iOS people): the head of its chat and its page say this number. */
    fun people(key: String): Int? = state(key)?.count
    /** The owner's words about the group (iOS state.about): its page's description. */
    fun about(key: String): String = state(key)?.about.orEmpty()
    /**
     * The conversations this phone holds with people of the group, by their roots (iOS heldConversations): the owner's phone everyone it
     * carries to, a member's phone the owner -- whom it may see online at all.
     */
    fun heldConversations(key: String): List<String> {
        val g = state(key) ?: return emptyList()
        return if (g.mine) g.members.map { SamePair.root(it.pipe) } else listOf(SamePair.root(g.owner))
    }
    /** The pipe this phone holds to a speaker of the group, when it holds one (iOS speakerPipe). */
    fun seatPipe(key: String, seat: String): String? {
        val g = state(key) ?: return null
        return if (!g.mine && seat == OWNER_SEAT) g.owner else g.members.firstOrNull { it.seat == seat }?.pipe
    }
    /** A seat's name as this phone knows it (iOS speakerName of the seat's reference). */
    fun seatWord(c: Context, key: String, seat: String): String = speakerName(c, speaker(key.removePrefix(KEY_HEAD), seat))
    /**
     * A LETTER THAT NAMES ME (iOS mentionsMe, the reference folder's mention): «@» and the name I go by -- my own name or my nick; the
     * name ends where a word ends. It rings even in a chat whose sound is off.
     */
    /**
     * The people a «@» may name in a group (iOS mentionable, MontanaGroup.swift:1062-1071): everyone this phone knows by name in it -- the
     * owner's phone everyone it carries to, a member's phone the owner and whoever spoke -- this phone aside, and nobody known only as
     * «Member».
     */
    fun mentionable(c: Context, key: String): List<Seat> {
        val g = state(key) ?: return emptyList()
        if (g.kind != GROUP) return emptyList()
        val member = c.getString(R.string.gr_member)
        return pagePeople(c, key).filter { it.seat != g.me && it.name != member }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }
    fun mentionsMe(words: String): Boolean {
        val low = words.lowercase()
        val names = listOf(Prefs.userName, Names.heldName ?: "").map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        return names.any { name ->
            var from = 0
            var hit = false
            while (!hit) {
                val at = low.indexOf("@$name", from)
                if (at < 0) break
                val end = at + name.length + 1
                if (end >= low.length || !low[end].isLetterOrDigit()) hit = true else from = end
            }
            hit
        }
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
        if (verdict != Verdict.WAIT && verdict != Verdict.INSTANT) Post.receiptFor(pipe, sid)
    }

    /** `quiet`: a copy the twin mirror brought (Windows group_handle's quiet) -- applied, never carried on, never answered. */
    private fun take(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        if (w.optString("t") == "ty") return if (quiet) Verdict.INSTANT else typed(w, pipe)   // a live word: no store needed, never a receipt
        if (!ready()) return Verdict.WAIT   // the copy knocks again once the store opens
        return when (val t = w.optString("t")) {
            "inv" -> invited(w, pipe)
            "say" -> said(w, pipe, quiet)
            "sig" -> answered(w, pipe, quiet)
            "out" -> dropped(w, pipe)
            "bye" -> parted(w, pipe, quiet)
            "ev" -> evented(w, pipe)
            "kk" -> kicked(w, pipe, quiet)   // an administrator's «take out», to the owner
            "jn" -> joined(w, pipe, quiet)   // a person who opened the group's invite link
            "kp" -> keptHeard(w, pipe, quiet)   // a keeper's word to a deleted letter's speaker
            "rd" -> readWord(w, pipe, quiet)   // a reader's mark (iOS B.13)
            "vw" -> seen(w, pipe, quiet)   // a subscriber's posts shown, to a channel's owner
            "vc" -> counted(w, pipe)   // a channel owner's view counts, to its subscribers
            else -> Verdict.REFUSED.also { Log.i("Montana", "group_refused kind=${t.take(8)}") }   // a newer build's word (a room's, a wall's): its road ends here
        }
    }

    // ── the person's other devices (the twin mirror: iOS MTGroup.mirrors, handleOwn, replay; Windows groups.rs mirrors, group_own,
    //    group_heard_by_twin) ──

    /** A group's word rides to the person's other devices unless it lived an instant (iOS MTGroup.mirrors 2098-2102): a typing word
     *  would be stale where it landed; a word that does not read as a group's word does not ride. */
    fun mirrors(text: String): Boolean {
        val w = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull() ?: return false
        return w.opt("t") is String && w.opt("g") is String && w.getString("t") != "ty"
    }

    /**
     * A CORRESPONDENT'S GROUP WORD ANOTHER DEVICE OF THESE WORDS TOOK (Windows groups.rs group_heard_by_twin): done here as there, but
     * carried on to nobody and answered to nobody -- the device that took it did both. No copy of it knocks here again, so a word
     * whose group has not stood here yet is kept and tried again by the twin's walk (twinRetry).
     */
    fun heardByTwin(pipe: String, mid: String, text: String) {
        val w = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull()
        if (w == null || !isLabel(w.optString("g"))) { Log.i("Montana", "group_refused unreadable twin word from=${pipe.take(10)}"); return }
        synchronized(lock) {
            if (take(w, pipe, quiet = true) != Verdict.WAIT) return
            val a = twinWaiting()
            if ((0 until a.length()).any { a.optJSONObject(it)?.optString("m") == mid }) return
            a.put(JSONObject().put("p", pipe).put("m", mid).put("x", text))
            keepTwinWaiting(a)
            Log.i("Montana", "group_twin_wait mid=" + mid.take(14) + " the group has not stood here yet")
        }
    }
    /** The other device's words whose group had not stood here are tried again (Windows group_retry): what still waits stays. */
    fun twinRetry() {
        if (!DeviceVault.has(TWIN_WAIT)) return
        synchronized(lock) {
            val a = twinWaiting()
            val left = JSONArray()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val w = runCatching { JSONObject(o.optString("x").removePrefix(MARK)) }.getOrNull() ?: continue
                if (runCatching { take(w, o.optString("p"), quiet = true) }.getOrDefault(Verdict.REFUSED) == Verdict.WAIT) left.put(o)
            }
            if (left.length() != a.length()) Log.i("Montana", "group_twin_retry landed=" + (a.length() - left.length()) + " waiting=" + left.length())
            keepTwinWaiting(left)
        }
    }
    private fun twinWaiting(): JSONArray =
        DeviceVault.get(TWIN_WAIT)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONArray()
    /** The newest 512 are kept (Windows: the oldest drained past 512). */
    private fun keepTwinWaiting(a: JSONArray) {
        if (a.length() == 0) { DeviceVault.delete(TWIN_WAIT); return }
        val kept = JSONArray()
        for (i in maxOf(0, a.length() - HEARD_LIMIT) until a.length()) kept.put(a.get(i))
        DeviceVault.set(TWIN_WAIT, kept.toString().toByteArray(Charsets.UTF_8))
    }

    /**
     * THE PERSON'S OWN GROUP WORD FROM ANOTHER OF THEIR DEVICES (iOS MTGroup.handleOwn 2112-2116 and replay 2135-2161; Windows groups.rs
     * group_own): the group stands on every device of these words, so what that device said is what this person said, done here as
     * the hand did it there -- an invitation stands the group as mine with that person at the seat the word gave, a letter its row
     * (mine when the seat is mine, a member's when that device carried it on), a taking out and a leaving their state -- and nothing
     * is said to anyone again: the device that spoke already carried it. Never a row of the pipe it rode.
     */
    fun handleOwn(pipe: String, text: String) {
        val w = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull() ?: return
        val id = w.optString("g")
        if (!isLabel(id) || w.opt("t") !is String) return
        synchronized(lock) {
            if (!ready()) return
            when (val t = w.getString("t")) {
                "inv" -> replayInvitation(w, pipe)
                "say" -> replayLetter(w)
                "out" -> {
                    // the other device took a person out of a group of mine: by the pipe the word rode (iOS replay «out»)
                    val who = SamePair.root(pipe)
                    val g = groups[id]?.takeIf { it.mine } ?: return
                    val m = g.members.firstOrNull { SamePair.root(it.pipe) == who } ?: return
                    g.banned.removeAll { it.seat == m.seat }; g.banned.add(m)
                    while (g.banned.size > PEOPLE_LIMIT) g.banned.removeAt(0)
                    g.members.removeAll { it.seat == m.seat }
                    g.admins.remove(m.seat)
                    g.count = g.members.size + 1
                    save()
                    lay(event("removed", g.id, OWNER_SEAT, listOf(m.seat)))
                }
                "bye" -> {
                    // the other device left a group this person was invited to (iOS replay «bye»): out here too, the rows readable
                    val g = groups[id]?.takeIf { !it.mine && !it.left } ?: return
                    g.left = true
                    save()
                    Book.edit(key(g.id)) {}   // the open chat trades its field for the note at once
                }
                else -> { Log.i("Montana", "group_own kind=${t.take(8)} -- the other device's word, applied to nobody"); return }
            }
            Log.i("Montana", "group_own kind=" + w.getString("t") + " group=" + id.take(6))
        }
    }

    /**
     * THE OTHER DEVICE INVITED A PERSON INTO A GROUP OF MINE -- its birth, an addition, a renewal (iOS replayInvitation 2166-2198): the group
     * stands here as its owner's, with that person at the seat the word gave, by the pipe the word rode (the pipes of one person are one
     * book). A group this phone holds as a member is not taken over.
     */
    private fun replayInvitation(w: JSONObject, pipe: String) {
        val kind = w.optString("k")
        val title = clean(w.optString("ti"), TITLE_LIMIT)
        val seat = w.optString("me")
        if ((kind != GROUP && kind != CHANNEL) || title.isEmpty() || !isSeat(seat) || seat == OWNER_SEAT) return
        val member = SamePair.root(pipe)
        val id = w.getString("g")
        val had = groups[id]
        if (had != null && !had.mine) { Log.i("Montana", "group_refused an own invitation of a group this phone holds as a member"); return }
        val g = had ?: State(id, kind, title, "", "", OWNER_SEAT, mutableListOf(), 2, mutableMapOf(), System.currentTimeMillis())
        val renamed = had != null && had.title != title
        g.title = title
        g.about = clean(w.optString("ds"), ABOUT_LIMIT)
        g.members.removeAll { it.seat == seat || SamePair.root(it.pipe) == member }
        g.members.add(Member(seat, member))
        g.banned.removeAll { SamePair.root(it.pipe) == member }
        g.count = maxOf(g.members.size + 1, minOf(w.optInt("c", 2), PEOPLE_LIMIT + 1))
        g.admins.clear()
        w.optJSONArray("ad")?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { isSeat(it) }.take(PEOPLE_LIMIT).forEach { g.admins.add(it) } }
        g.signs = w.optInt("sg") == 1
        g.reacts = if (w.has("rx") && w.optInt("rx", 1) == 0) false else null
        val fc = w.optString("fc").ifEmpty { null }
        val tag = fc?.let { it.length.toString() + "-" + it.takeLast(16) }
        val newFace = tag != null && tag != g.faceTag
        if (newFace) g.faceTag = tag
        groups[id] = g
        save()
        stand(g, if (newFace) face(fc) else null)
        if (had == null) lay(event("made", id, OWNER_SEAT, t = title))   // «You created the group»
        if (renamed) lay(event("named", id, OWNER_SEAT, t = title))
    }

    /**
     * A LETTER THE OTHER DEVICE WROTE INTO A GROUP OF THESE WORDS, OR CARRIED THERE FOR A MEMBER (iOS replayLetter 2203-2218): its row
     * stands here under its one name, the person's own when its seat is this person's, never a second time and never over its tombstone.
     */
    private fun replayLetter(w: JSONObject) {
        val g = groups[w.optString("g")] ?: return
        if (g.left) return
        val id = w.optString("id")
        val words = w.optString("tx")
        val seat = w.optString("s")
        if (!isLetterName(id) || !carries(words) || !isSeat(seat)) return
        val key = key(g.id)
        if (id in gone || Book.buried(key, id) || Book.chat(key)?.msgs?.any { it.mid == id } == true) return
        val mine = seat == g.me
        stand(g, null)
        // the speaker's name rides the carried letter (Windows group_own «say»)
        val name = clean(w.optString("n"), NAME_LIMIT)
        if (!mine && name.isNotEmpty() && g.names[seat] != name) { g.names[seat] = name; save() }
        val at = Marks.birthMs(id) ?: System.currentTimeMillis()
        val quote = w.optString("qt").ifEmpty { null }
        val quoted = w.optString("qm").removePrefix("mid:").ifEmpty { null }
        var landed = false
        Book.edit(key) { c ->
            if (c.msgs.none { it.mid == id }) {
                c.msgs.add(Msg(id, words, mine, at, state = if (mine) 1 else 0, qt = quote, qm = quoted, from = if (mine) null else speaker(g.id, seat)))
                c.msgs.sortBy { it.at }
                if (!mine && Book.openChat != key) c.unread++
                landed = true
            }
        }
        Log.i("Montana", "group_own mid=$id letter landed=${if (landed) 1 else 0} mine=${if (mine) 1 else 0}")
        // a media letter's file is gathered from the pieces every member reads, quietly: nobody here is answered for it
        if (landed && words.startsWith(Marks.MEDIA)) Media.fetch(Book.ctx, key, id, words, quiet = true)
    }

    /**
     * SOMEONE TYPES IN THE GROUP (iOS 2235 «ty», a live frame): who, seen for five seconds; answered by nothing. Android receipted it as a
     * refused word, and every burst of typing queued a receipt the iPhone filed among its orphans.
     */
    private val typing = HashMap<String, MutableMap<String, Long>>()   // group key -> seat -> until
    private fun typed(w: JSONObject, pipe: String): Verdict {
        val (g, seat) = synchronized(lock) {
            val g = (if (ready()) groups[w.optString("g")] else null) ?: return Verdict.INSTANT
            if (g.left || g.kind != GROUP) return Verdict.INSTANT
            val from = SamePair.root(pipe)
            val seat: String
            if (g.mine) {
                // its seat proven by the pipe it came by, as every word's is; the owner throws it on to everyone else, once in two
                // seconds a member, and takes none from a person it blocked (iOS typed)
                val m = g.members.firstOrNull { SamePair.root(it.pipe) == from } ?: return Verdict.INSTANT
                if (PeerSafety.isBlocked(m.pipe)) return Verdict.INSTANT
                seat = m.seat
                val k = g.id + "/" + seat
                val now = System.currentTimeMillis()
                if (now - (typingThrown[k] ?: 0L) >= 2000) {
                    typingThrown[k] = now
                    val on = JSONObject(w.toString()).put("s", seat)
                    throwTyping(on, g.members.filter { it.seat != seat }.map { it.pipe })
                }
            } else {
                val s = w.optString("s")
                if (SamePair.root(g.owner) != from || !isSeat(s) || s == g.me) return Verdict.INSTANT
                seat = s
            }
            // a person's name reaches the group from that person, as their letters bring it
            val name = clean(w.optString("n"), NAME_LIMIT)
            if (name.isNotEmpty() && g.names[seat] != name) { g.names[seat] = name; save() }
            g to seat
        }
        synchronized(typing) { typing.getOrPut(key(g.id)) { HashMap() }[seat] = System.currentTimeMillis() + 5_000L }
        Presence.poke()   // the open chat's head says it at once
        MainThread.later(5_100, Runnable { Presence.poke() })   // and lets it go with its life
        return Verdict.INSTANT
    }
    /** The group and its standing mark in an invitation link (iOS 2235 «?jg=<32 hex>.<32 hex>»), or null. */
    fun joinMark(link: String): Pair<String, String>? {
        val q = link.substringAfter('?', "").substringBefore('#')
        val v = q.split('&').firstOrNull { it.startsWith("jg=") }?.removePrefix("jg=") ?: return null
        val g = v.substringBefore('.').lowercase(); val mark = v.substringAfter('.', "").lowercase()
        return if (isLabel(g) && isLabel(mark)) g to mark else null
    }
    /**
     * ASKING TO JOIN BY THE OWNER'S LINK (iOS 2235 «jn»): once the pipe to the owner stands, the mark goes to it; an owner whose standing
     * mark it is, and who never took this person out, adds them -- the invitation comes back by its usual road.
     */
    fun askJoin(pipe: String, g: String, mark: String) {
        val w = JSONObject().put("t", "jn").put("g", g).put("id", Marks.mintMid()).put("tx", mark)
        clean(Prefs.userName, NAME_LIMIT).takeIf { it.isNotEmpty() }?.let { w.put("n", it) }
        synchronized(lock) { carry(w, pipe, "", own = false) }
        Log.i("Montana", "group_link asked to join group=" + g.take(8) + " owner=" + pipe.take(10))
    }
    /** The names typing in a group now (the chat's head). */
    fun typingNames(c: Context, key: String): List<String> {
        val now = System.currentTimeMillis()
        val seats = synchronized(typing) { typing[key]?.filterValues { now < it }?.keys?.toList().orEmpty() }
        return seats.map { speakerName(c, speaker(key.removePrefix(KEY_HEAD), it)) }
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
        // the administrators the owner named, a channel's signing and its reactions (iOS 2235 inv «ad», «sg», «rx»)
        val admins = w.optJSONArray("ad")?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { isSeat(it) && it != OWNER_SEAT }.take(PEOPLE_LIMIT) }.orEmpty()
        val signs = w.optInt("sg") == 1
        val reacts = if (w.has("rx") && w.optInt("rx", 1) == 0) false else null
        if (had != null) {
            if (had.mine || SamePair.root(had.owner) != owner) {
                Log.i("Montana", "group_refused invitation of a group held by another owner")
                return Verdict.REFUSED
            }
            // out of the group, a word of the old seat is one that was on its way; the owner adding this phone again gives a new seat
            val back = had.left
            if (back) { if (seat == had.me) return Verdict.REFUSED; had.left = false; had.removed = false }
            val renamed = !back && had.title != title
            val hadFace = had.faceTag != null
            had.title = title; had.about = clean(w.optString("ds"), ABOUT_LIMIT); had.count = count; had.me = seat
            had.admins.clear(); had.admins.addAll(admins); had.signs = signs; had.reacts = reacts
            if (ownerName.isNotEmpty()) had.names[OWNER_SEAT] = ownerName
            val newFace = tag != null && tag != had.faceTag
            if (newFace) had.faceTag = tag
            save()
            stand(had, if (newFace) face(fc) else null)
            // the reference folder's rows: added again, a new name, a new face -- each the owner's deed (iOS invited)
            if (back) lay(event("added", id, OWNER_SEAT, listOf(seat)))
            if (renamed) lay(event("named", id, OWNER_SEAT, t = title))
            if (newFace && hadFace && !back) lay(event("face", id, OWNER_SEAT))
            return Verdict.HELD
        }
        val g = State(id, kind, title, clean(w.optString("ds"), ABOUT_LIMIT), owner, seat, mutableListOf(), count,
            if (ownerName.isEmpty()) mutableMapOf() else mutableMapOf(OWNER_SEAT to ownerName), System.currentTimeMillis(), faceTag = tag,
            admins = admins.toMutableList(), signs = signs, reacts = reacts)
        groups[id] = g
        save()
        stand(g, face(fc))
        lay(event("added", id, OWNER_SEAT, listOf(seat)))   // «X added you»
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
     * letters from the owner's pipe alone. `quiet`: a copy the twin mirror brought -- the row, the count and the banner, carried on to
     * nobody (Windows group_handle «say»).
     */
    private fun said(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.WAIT
        if (g.left) return Verdict.REFUSED   // out of the group: the word's road ends here
        val id = w.optString("id")
        val words = w.optString("tx")
        if (!isLetterName(id) || !carries(words)) return Verdict.REFUSED
        val from = SamePair.root(pipe)
        val seat: String
        if (g.mine) {
            val m = g.members.firstOrNull { SamePair.root(it.pipe) == from } ?: return Verdict.REFUSED
            // in a channel the owner carries its administrators' posts alone (iOS 2235 heard)
            if (g.kind != GROUP && m.seat !in g.admins) { Log.i("Montana", "group_refused a member's letter in a channel is not carried"); return Verdict.REFUSED }
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
        // a letter that lands ends its speaker's typing (iOS 2235)
        if (synchronized(typing) { typing[key]?.remove(seat) } != null) Presence.poke()
        // the banner a running app owes its person: the group's title over who wrote and what (a channel speaks as itself); a silent
        // channel post (iOS 2235 «sl»: 1) rings nobody; a mention rings through the mute (iOS mentionsMe)
        val silent = w.optInt("sl") == 1
        if (landed && Book.openChat != key && !silent) Notify.letter(key, words, if (g.kind == GROUP) speakerName(Book.ctx, sp) else null,
            mentioned = g.kind == GROUP && mentionsMe(words))
        // a letter that lands in the open chat is read there (iOS sendReadMark on every letter that lands while the chat is open)
        if (landed && Book.openChat == key && g.kind == GROUP) Post.markRead(key)
        // THE OWNER CARRIES IT ON (iOS heard, g.mine): to every other member, under the speaker's seat and the name they gave -- the
        // device that took the word did, when it came by the mirror
        if (landed && g.mine && !quiet) {
            val on = JSONObject().put("t", "say").put("g", g.id).put("k", g.kind).put("ti", g.title).put("id", id).put("s", seat).put("tx", words)
            if (silent) on.put("sl", 1)
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
     * buries it before it comes. `quiet`: a copy the twin mirror brought, applied and carried on to nobody (Windows group_handle «sig»).
     */
    private fun answered(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
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
        val boss = seat == OWNER_SEAT || seat in g.admins
        // a pin for everyone is a group's alone; a channel whose reactions are off takes none but its owner's and its administrators'
        if (words.startsWith(PIN_MARK) && g.kind != GROUP) return Verdict.REFUSED
        if (words.startsWith(Marks.REACTION) && g.kind == CHANNEL && g.reacts == false && !boss) return Verdict.REFUSED
        val key = key(g.id)
        target(words)?.let { t ->
            val row = Book.chat(key)?.msgs?.firstOrNull { it.mid == t }
            if (row != null) {
                // only the speaker changes a letter; the owner and its administrators take anyone's away (iOS «boss», stage R.6)
                if (!words.startsWith(PIN_MARK) && author(row, g) != seat && !(words.startsWith(Marks.DELETE) && boss)) {
                    Log.i("Montana", "group_refused an answer to another's letter seat=$seat")
                    return Verdict.REFUSED
                }
            } else if (t in gone) return Verdict.HELD
            else if (g.mine) return Verdict.WAIT   // the letter has not landed at the owner yet: the copy knocks again
            else if (words.startsWith(Marks.DELETE)) { bury(t); remember(id); return Verdict.HELD }
        }
        remember(id)
        apply(key, words, seat, quiet)
        // the reference's service row of a pin (iOS answered): «X pinned "..."», laid under the pinned letter's own words
        if (words.startsWith(PIN_MARK)) runCatching {
            val o = JSONObject(words.removePrefix(PIN_MARK))
            val t = o.getString("sid").removePrefix("mid:")
            val row = Book.chat(key)?.msgs?.firstOrNull { it.mid == t }
            if (o.optString("op") == "pin" && row != null) lay(event("pinned", g.id, seat, t = pinWords(row)))
        }
        // the owner carries the answer on to every other member (iOS answered, g.mine)
        if (g.mine && !quiet) spread(JSONObject().put("t", "sig").put("g", g.id).put("id", id).put("s", seat).put("tx", words)
            .apply { w.optString("n").ifEmpty { null }?.let { put("n", it) } }, g, seat, own = false)
        return Verdict.HELD
    }

    /** A MEMBER LEFT (iOS parted, their «bye»): the owner carries nothing more to them, and everyone left learns the new count -- from
     *  the device that took the word, when it came by the mirror (Windows group_handle «bye», quiet). */
    private fun parted(w: JSONObject, pipe: String, quiet: Boolean = false): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.REFUSED
        val from = SamePair.root(pipe)
        val m = (if (g.mine) g.members.firstOrNull { SamePair.root(it.pipe) == from } else null) ?: return Verdict.REFUSED
        act(g, "left", p = listOf(seatName(g, m.seat)))
        g.members.removeAll { it.seat == m.seat }
        g.admins.remove(m.seat)
        g.count = g.members.size + 1
        save()
        if (!quiet) tellAll(g, null)
        val gone = event("left", g.id, m.seat)
        lay(gone)
        if (!quiet) tellEvent(gone, g)
        Log.i("Montana", "group_rx a member left count=" + g.count)
        return Verdict.HELD
    }

    private fun apply(key: String, words: String, seat: String, quiet: Boolean = false) {
        when {
            words.startsWith(Marks.DELETE) -> {
                val t = target(words) ?: return
                // THE PERSON KEEPS WHAT OTHERS DELETE (iOS ChatStore 4523-4547 for a group's feed): the letter stays, and the one who took it
                // away alone is told by the group's own word (tellKept) -- the deletion's own speaker, an administrator too; by the device
                // that took the deletion, when it came by the mirror
                PersonChain.prime(); CoinBook.warm()
                val kept = LevelAccess.keepsDeleted && Book.chat(key)?.msgs?.any { it.mid == t } == true
                if (kept && !quiet) tellKept("mid:$t", seat, key)
                if (!kept) Book.edit(key) { c -> c.msgs.removeAll { it.mid == t } }
            }
            words.startsWith(Marks.EDIT) -> {
                val tx = runCatching { JSONObject(words.removePrefix(Marks.EDIT)).getString("tx") }.getOrNull()
                val t = target(words)
                if (tx != null && t != null) Book.edit(key) { c -> c.msgs.find { it.mid == t && !it.mine }?.let { it.text = tx; it.edited = true } }
            }
            words.startsWith(Marks.REACTION) -> runCatching {
                val o = JSONObject(words.removePrefix(Marks.REACTION)); val t = o.getString("sid").removePrefix("mid:"); val e = o.getString("e")
                Book.edit(key) { c -> c.msgs.find { it.mid == t }?.let { m -> if (o.optString("op") == "del") m.reactions.remove(e) else m.reactions.add(e) } }
            }
            // A PIN FOR EVERYONE (iOS 2235 «sig» with «PN:»): the plate follows; «n»: 0 pins without a banner
            words.startsWith(PIN_MARK) -> runCatching {
                val o = JSONObject(words.removePrefix(PIN_MARK)); val t = o.getString("sid").removePrefix("mid:")
                val row = Book.chat(key)?.msgs?.firstOrNull { it.mid == t } ?: return@runCatching
                if (o.optString("op") == "pin") { MsgPins.pin(key, t); if (o.optInt("n", 1) != 0 && Book.openChat != key) Notify.pinned(key, t, row) }
                else MsgPins.unpin(key, t)
            }
        }
    }

    /**
     * THE OWNER TOOK THIS PHONE OUT (iOS dropped): the rows stay readable, and the chat says so instead of a field. THE OWNER DELETED THE
     * GROUP FOR EVERYONE (iOS 2235 «out» with «dl»: 1): the chat is erased here, the group stays known as left.
     */
    private fun dropped(w: JSONObject, pipe: String): Verdict {
        val g = groups[w.getString("g")] ?: return Verdict.REFUSED
        if (g.mine || SamePair.root(g.owner) != SamePair.root(pipe)) return Verdict.REFUSED
        val erase = w.optInt("dl") == 1
        if (!g.left || erase) {
            val was = g.left
            g.left = true; g.removed = true
            save()
            if (erase) { val key = key(g.id); Thread { Book.forget(key) }.start(); Log.i("Montana", "group_rx deleted for everyone by the owner -- erased here") }
            else {
                if (!was) lay(event("removed", g.id, OWNER_SEAT, listOf(g.me)))   // «X removed you» (iOS dropped)
                Book.edit(key(g.id)) {}; Log.i("Montana", "group_rx taken out by the owner")   // the open chat trades its field for the note at once
            }
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
        // a pin or an unpin (iOS 2235, at most 1 024 bytes)
        text.startsWith(PIN_MARK) -> text.toByteArray().size <= 1024 && target(text) != null &&
            runCatching { JSONObject(text.removePrefix(PIN_MARK)).optString("op") }.getOrNull().let { it == "pin" || it == "unpin" }
        else -> text.startsWith(Marks.DELETE) && target(text) != null
    }
    /** The bare name of the letter an edit, a deletion or a pin speaks of; null for a reaction (iOS target). */
    private fun target(text: String): String? {
        val sid = when {
            text.startsWith(Marks.EDIT) -> runCatching { JSONObject(text.removePrefix(Marks.EDIT)).optString("sid") }.getOrDefault("")
            text.startsWith(PIN_MARK) -> runCatching { JSONObject(text.removePrefix(PIN_MARK)).optString("sid") }.getOrDefault("")
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
    /** A letter's one name, bare (iOS isLetterName): read by the channel's views (ChannelViews). */
    fun letterName(s: String) = isLetterName(s)
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
