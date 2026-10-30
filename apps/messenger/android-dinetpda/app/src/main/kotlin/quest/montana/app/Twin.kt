package quest.montana.app

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * THE PERSON'S OTHER DEVICES IN STEP (iOS MontanaPQ 872-1155, MontanaDeliveryEngine.mirrors / landMirrored / landOwn, ChatStore.readByTwin,
 * giveTwinRows / takeTwinRow, MontanaCard.takeTwin; the port of Windows twin.rs: letters, groups, rows asked back, cards). Every device of the 24
 * words is one reference to the pipes of its correspondents, so the node's box hands a letter to whichever device takes it first, that
 * device's confirmation erases it for the rest, and a letter one device sent the box never gives the others. So what this phone sends,
 * takes from a correspondent or reads rides to the other devices as words of a mirror («lt») in the pipe only these words derive
 * (Archive.TWIN_PIPE), on the cargo road beside the archive's blocks («hist»); their words land here by the one landing road, quietly --
 * nobody answered, nothing paid twice -- and ride no further. What the blocks show this feed lacks is asked by the archive's key and given
 * back by name, and a card born on one device opens introductions on all. The wire is the original's: a word this phone writes is read by
 * an iPhone and by Windows as theirs is.
 */
object Twin {
    /** A read mark for the person's own devices alone, + the birth millisecond of the newest letter read; never on a pair's wire. */
    const val READ_MARK = "​​TR:"
    // the twin's past asked and given back, and a card born on another device (iOS twinAskMark, twinRowMark, twinCardMark 1083-1086)
    private const val ASK_MARK = "​​TA:"
    private const val ROW_MARK = "​​TW:"
    private const val CARD_MARK = "​​TC:"
    private const val CARD_PIPE = "twin:card"   // the mirror's name for the cards' words, never a conversation (iOS twinCardPipe)

    private const val QUEUE_FILE = "twin-mirror.sealed"   // the words not laid yet, in order (iOS twin-mirror.json), sealed by the device key
    private const val DUE = "mt.twin.due."                 // + «lt»: the millisecond the next lay is due, 0 when nothing waits
    private const val HELD = "mt.twin.held"                // words for a pipe this phone does not know yet: they land once its head comes
    private const val ASKED = "mt.twin.asked"              // chat/second/hash of the rows already asked of the other devices (iOS askedKey)
    private const val ASK_ROUND = 200                      // keys asked in one word, and read from one (iOS askTwin, giveTwinRows)
    private const val ASK_KEPT = 5000                      // keys remembered as asked (iOS askTwin suffix(5000))
    private const val KEPT = 4000         // [I-14]: a device away for long is given the newest; the history road keeps the rest
    private const val ROUND = 500
    private const val SOON_MS = 30_000L
    private const val AGAIN_MS = 120_000L // a lay that did not reach the nodes is tried again later
    private const val HOLD_MS = 2 * 86_400_000L

    private val qlock = Any()
    private val layLock = Any()   // one lay at a time; held across the road, so never taken by a sender's thread
    private val dueLock = Any()
    private val askLock = Any()
    /** A file given back or taken rides the cargo road off the pickup's thread, one at a time (iOS Task.detached in giveTwin, takeTwinRow). */
    private val roads = Executors.newSingleThreadExecutor { r -> Thread(r, "twin-rows").apply { isDaemon = true } }
    private val fetching = HashSet<String>()   // chat/name of a given-back file on its way here: one fetch of it at a time
    /** c/m/x[..24] -> the second it was queued: a name is given once within the hour (iOS keeps it in memory too). */
    private val given = HashMap<String, Long>()

    /** One word of the mirror (iOS TwinWord), as JSON with its empty fields left out -- c, m and x always written. */
    class Word(val c: String, val m: String, val x: String, val o: Int? = null, val at: Double? = null,
               val qt: String? = null, val qm: String? = null, val lp: String? = null, var q: Long? = null) {
        fun json(): JSONObject = JSONObject().put("c", c).put("m", m).put("x", x).apply {
            o?.let { put("o", it) }
            at?.let { put("at", it) }
            qt?.takeIf { it.isNotEmpty() }?.let { put("qt", it) }
            qm?.takeIf { it.isNotEmpty() }?.let { put("qm", it) }
            lp?.takeIf { it.isNotEmpty() }?.let { put("lp", it) }
            q?.let { put("q", it) }
        }
        companion object {
            /** A word as another device wrote it; one without c, m or x is skipped, unknown fields are passed over. */
            fun of(o: JSONObject): Word? {
                if (!o.has("c") || !o.has("m") || !o.has("x")) return null
                return Word(o.optString("c"), o.optString("m"), o.optString("x"),
                    if (o.has("o")) o.optInt("o") else null, if (o.has("at")) o.optDouble("at") else null,
                    o.optString("qt").ifEmpty { null }, o.optString("qm").ifEmpty { null }, o.optString("lp").ifEmpty { null },
                    if (o.has("q")) o.optLong("q") else null)
            }
        }
    }

    /** The words of the wire that are machinery between two phones, never a row (iOS isControlMarker, ContentView.swift 4104-4121). */
    private val CONTROL = listOf(Marks.READ, Marks.DELIVERED, CONVDEL_MARK, Marks.STICKER) +
        listOf("TY", "RC", "AV", "NM", "AB", "PG", "QC", "VC", "DL", "DF", "MD", "WH", "PA", "EX", "CG", "WA", "PL", "AP", "ED", "PN",
            "SP", "WL", "SM", "SY", "PX", "KP", "DK", "FT").map { "​​$it:" }
    private fun isControl(t: String) = CONTROL.any { t.startsWith(it) }

    /**
     * THE MIRROR'S CHOICE OF WORDS (iOS MontanaDeliveryEngine.mirrors 193-198): what stands in a conversation or moves a row -- a letter
     * of every kind, a receipt, a read mark, a deletion, a group's word -- rides to the other devices; what says only «here, now» (typing,
     * a group's too, presence, a name, a face) does not, nor, by the code, an edit, a reaction or a pin. A ring, a call's signal and a
     * live draft are stale before they would arrive: they stay here.
     */
    fun mirrors(t: String): Boolean {
        if (t.startsWith(Groups.MARK)) return Groups.mirrors(t)
        if (t.startsWith(Marks.RING) || t.startsWith("⁣mtcall:") || t.startsWith(LiveDraft.MARK)) return false
        if (t.startsWith(Marks.DELIVERED) || t.startsWith(Marks.READ) || t.startsWith(Marks.DELETE)) return true
        return !isControl(t) || t.startsWith(Marks.MEDIA) || t.startsWith(Marks.VOICE) || t.startsWith(Marks.STICKER)
    }

    /** THE WORD'S FORM AGREES WITH THE OTHER PLATFORMS (Windows twin.rs, a_word_of_the_mirror_reads_as_ios_writes_it; iOS JSONEncoder of
     *  [TwinWord]): a word written here reads back with its values, iOS's sample reads with its unknown field passed over; read at launch. */
    fun agreesWithCanon(): Boolean = runCatching {
        val w = Word.of(JSONObject(Word("ab", "t1-X", "привет", o = 1, at = 1760943600.5, q = 3).json().toString()))!!
        val back = w.c == "ab" && w.m == "t1-X" && w.x == "привет" && w.o == 1 && w.at == 1760943600.5 && w.q == 3L && w.qt == null && w.lp == null
        val a = JSONArray("""[{"c":"cd","m":"M","x":"\u200b\u200bTR:1760943600123","o":1,"zz":2},{"m":"n","c":"c","x":"y","lp":"https:\/\/a"}]""")
        val i0 = Word.of(a.getJSONObject(0))!!
        val i1 = Word.of(a.getJSONObject(1))!!
        back && i0.o == 1 && i0.at == null && i0.x == READ_MARK + "1760943600123" && i1.lp == "https://a" && i1.o == null &&
            mirrors("привет") && mirrors(Marks.DELIVERED + "t1-A") && mirrors(Marks.DELETE + "mid:t1-A") && mirrors(Marks.MEDIA + "{}") &&
            !mirrors(Marks.EDIT + "{}") && !mirrors(Marks.REACTION + "{}") && !mirrors(Marks.TYPING) && !mirrors(Marks.NAME + "x") &&
            // Windows the_mirror_carries_what_stands_in_a_conversation...: a group's word but its typing, and my missed call
            mirrors(Groups.MARK + """{"t":"say","g":"x"}""") && !mirrors(Groups.MARK + """{"t":"ty","g":"x"}""") && mirrors(Marks.MISSED + "{}") &&
            // the archive's key of a row's words: eight bytes of SHA-256 in hex (iOS rowHash; SHA-256("abc") = ba7816bf8f01cfea…)
            rowHash("abc") == "ba7816bf8f01cfea"
    }.getOrDefault(false)

    // ───────────────────────────── the queue ─────────────────────────────

    private fun qfile() = File(File(Book.ctx.noBackupFilesDir, "MontanaTwin").apply { mkdirs() }, QUEUE_FILE)
    /** «CANNOT READ» IS NOT «EMPTY» (as Post.outbox): a queue that does not open is never written over. */
    @Volatile private var unreadable = false
    private fun queue(): MutableList<Word> {
        val f = qfile()
        if (!f.exists()) { unreadable = false; return mutableListOf() }
        val a = runCatching { DeviceVault.unseal(f.readBytes()) }.getOrNull()?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() }
        unreadable = a == null
        if (a == null) { Log.d("Montana", "twin_queue unreadable -- not overwriting"); return mutableListOf() }
        return (0 until a.length()).mapNotNullTo(mutableListOf()) { i -> a.optJSONObject(i)?.let { Word.of(it) } }
    }
    private fun keepQueue(q: List<Word>) {
        if (unreadable) return
        val sealed = DeviceVault.seal(JSONArray(q.map { it.json() }).toString().toByteArray(Charsets.UTF_8)) ?: return
        val f = qfile()
        val tmp = File(f.path + ".tmp")
        tmp.writeBytes(sealed)
        if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
    }

    /**
     * A WORD FOR THE OTHER DEVICES (iOS mirrorNote 1026-1043): kept until it rode, laid within half a minute with whatever came beside
     * it. A name given within the hour is not queued twice; a newer read mark of a conversation stands for the older; the newest 4000
     * are kept.
     */
    private fun note(w: Word) {
        if (Archive.twinSecret() == null) return
        val reads = w.x.startsWith(READ_MARK)
        synchronized(qlock) {
            val now = System.currentTimeMillis() / 1000
            val name = w.c + "/" + w.m + "/" + w.x.take(24)
            if (!reads && given[name]?.let { now - it <= 3600 } == true) return
            given[name] = now
            if (given.size > 2000) given.entries.removeAll { now - it.value >= 3600 }
            val q = queue()
            if (reads) q.removeAll { it.c == w.c && it.x.startsWith(READ_MARK) }
            w.q = (q.mapNotNull { it.q }.maxOrNull() ?: 0L) + 1
            q.add(w)
            while (q.size > KEPT) q.removeAt(0)
            keepQueue(q)
        }
        soon("lt", SOON_MS)
    }

    /**
     * WHAT THIS PERSON SENT rides to the other devices under its name (iOS enqueue 963-972): a pair's letter or word the mirror carries
     * -- never a receipt or a read mark, which are this device's word to the correspondent, never a quiet word that is no control word,
     * never Saved Messages (its letters ride the archive's blocks alone) and never a group's feed. A group's copy on a member's pipe
     * (Groups.carry) is such a word under its own name (iOS MTGroup.carry → enqueue): a letter and an invitation ride, each copy once; a
     * silent copy -- an answer, a leaving, a taking out, a silent channel post -- stays here, as iOS leaves it.
     */
    fun sent(to: String, mid: String, text: String, qt: String?, qm: String?, lp: String?, quiet: Boolean) {
        if (Groups.isKey(to) || to == SavedMessages.KEY || to == Archive.TWIN_PIPE || !mirrors(text)) return
        if (text.startsWith(Marks.DELIVERED) || text.startsWith(Marks.READ)) return
        if (quiet && !isControl(text)) return
        note(Word(to, mid, text, o = 1, at = System.currentTimeMillis() / 1000.0, qt = qt, qm = qm, lp = lp))
    }

    /** A CORRESPONDENT'S WORD THIS PHONE TOOK rides to the other devices (iOS receive 246-250): the box gave it to this one, and this
     *  one's confirmation erases it there. Its moment is its birth. */
    fun heard(ref: String, mid: String, text: String, qt: String?, qm: String?, lp: String?) {
        if (Groups.isKey(ref) || !mirrors(text)) return
        val at = (Marks.birthMs(mid) ?: System.currentTimeMillis()) / 1000.0
        note(Word(ref, mid, text, at = at, qt = qt, qm = qm, lp = lp))
    }

    /** READ HERE (iOS ChatStore.markRead 3151-3157): the other devices read the conversation up to the same letter; the correspondent is
     *  told nothing by this word. */
    fun readHere(ref: String, upToMs: Long?) {
        if (Groups.isKey(ref) || upToMs == null || upToMs <= 0) return
        note(Word(ref, Marks.mintMid(), READ_MARK + upToMs, o = 1))
    }

    // ───────────────────────────── laying ─────────────────────────────

    /** A lay is due within `ms` (iOS mirrorSoon): a lay already due keeps its moment; a phone awake lays it then, any later walk too. */
    fun soon(what: String, ms: Long) {
        synchronized(dueLock) {
            if ((Prefs.str(DUE + what, "0").toLongOrNull() ?: 0L) != 0L) return
            Prefs.setStr(DUE + what, (System.currentTimeMillis() + ms).toString())
        }
        MainThread.later(ms + 1_000L, Runnable { Thread { runCatching { walk() } }.start() })
    }
    /** The next lay set `ms` from now, whatever was set before (a lay that failed, or a queue that still holds words). */
    private fun dueIn(what: String, ms: Long) {
        synchronized(dueLock) { Prefs.setStr(DUE + what, (System.currentTimeMillis() + ms).toString()) }
        MainThread.later(ms + 1_000L, Runnable { Thread { runCatching { walk() } }.start() })
    }
    private fun due(what: String): Boolean = synchronized(dueLock) {
        val at = Prefs.str(DUE + what, "0").toLongOrNull() ?: 0L
        if (at == 0L || at > System.currentTimeMillis()) false else { Prefs.setStr(DUE + what, "0"); true }
    }

    /** THE TWIN'S WALK (Post.fetch, and the half minute after a word): the words that are due are laid; words held for a pipe unknown
     *  here are tried again, and a group's words that came before their group stood here (Windows group_retry). */
    fun walk() {
        if (due("lt")) layMirror()
        landHeld()
        Groups.twinRetry()
    }

    /**
     * THE WORDS LAID (iOS layMirror 1052-1075): up to 500 as one JSON array on the cargo road, named by a silent letter in the twin's
     * pipe with «w» «lt», their count and this phone's writer tag; what rode leaves the queue, the rest waits for the next round.
     */
    fun layMirror(): Boolean { return synchronized(layLock) {
        val secret = Archive.twinSecret() ?: return false
        val tag = Archive.writerTagHex().ifEmpty { return false }
        val batch = synchronized(qlock) { queue().take(ROUND) }
        if (batch.isEmpty()) return true
        val f = File(File(Book.ctx.noBackupFilesDir, "MontanaKeepWork").apply { mkdirs() }, UUID.randomUUID().toString() + ".lt")
        try {
            f.writeBytes(JSONArray(batch.map { it.json() }).toString().toByteArray(Charsets.UTF_8))
            val road = Keeping.lay(f)
            val laid = road != null && Keeping.knock(secret, road.put("w", "lt").put("n", batch.size).put("f", tag), silent = true, sender = Archive.twinDeviceRef)
            if (!laid) {
                Log.d("Montana", "twin_lt the words did not reach the nodes n=" + batch.size)
                dueIn("lt", AGAIN_MS)
                return false
            }
            val top = batch.mapNotNull { it.q }.maxOrNull() ?: -1L
            val left = synchronized(qlock) { queue().also { q -> q.removeAll { (it.q ?: -1L) <= top }; keepQueue(q) }.size }
            Log.d("Montana", "twin_lt laid words=" + batch.size + " left=" + left)
            if (left > 0) dueIn("lt", SOON_MS)
            return true
        } finally { f.delete() }
    } }

    // ───────────────────────────── taking and landing ─────────────────────────────

    /** THE WORDS OF THE OTHER DEVICE (iOS takeMirror 1140-1154): each lands here, in the order that device heard them. False when the
     *  road did not come whole; a file that does not parse is lost, as on every device. */
    fun takeMirror(o: JSONObject): Boolean {
        val f = File(File(Book.ctx.noBackupFilesDir, "MontanaKeepWork").apply { mkdirs() }, UUID.randomUUID().toString() + ".lt")
        try {
            Log.d("Montana", "twin_lt fetching n=" + o.optInt("n"))
            if (!Keeping.fetch(o, f)) { Log.d("Montana", "twin_lt the words did not come whole"); return false }
            val a = runCatching { JSONArray(String(f.readBytes(), Charsets.UTF_8)) }.getOrNull()
                ?: return true.also { Log.d("Montana", "twin_lt the words do not read") }
            var n = 0
            for (i in 0 until a.length()) a.optJSONObject(i)?.let { Word.of(it) }?.let { w -> runCatching { land(w) }.onFailure { Log.w("Montana", "twin_lt land " + it.javaClass.simpleName) }; n++ }
            Log.d("Montana", "twin_lt taken words=" + n)
            return true
        } finally { f.delete() }
    }

    /**
     * A WORD THE OTHER DEVICE MIRRORED HERE (iOS landMirrored 174-189; Windows land_mirrored 665-703): a read mark reads the conversation
     * here too; the twin's past is asked and given back by name, and a card born there opens its introductions here; every other word walks
     * the one landing road under the name it was born with -- the person's own as mine (a group's word done as that device did it, my
     * missed call its row), a correspondent's as theirs, quietly -- and rides no further. A word for a pipe this phone does not know waits
     * for the head the blocks bring.
     */
    fun land(w: Word) {
        if (w.x.startsWith(READ_MARK)) { readByTwin(w.c, w.x.removePrefix(READ_MARK).trim().toLongOrNull()); return }
        if (w.x.startsWith(ASK_MARK)) { give(w.c, w.x.removePrefix(ASK_MARK)); return }
        if (w.x.startsWith(CARD_MARK)) { MontanaCard.takeTwin(w.x.removePrefix(CARD_MARK)); return }
        if (w.x.startsWith(ROW_MARK)) { takeRow(w, w.x.removePrefix(ROW_MARK)); return }
        if (w.m.isEmpty() || w.x.isEmpty() || w.m.length > 128 || w.c == CARD_PIPE || Groups.isKey(w.c)) return
        if (Book.secret(w.c) == null && Book.chat(w.c) == null) { hold(w); return }
        var text = w.x
        if (text.startsWith(Marks.LONG)) text = Post.fetchLong(text)?.ifEmpty { null } ?: run { hold(w); return }
        if (w.o == 1) Post.landOwnMirrored(w.c, w.m, text, w.qt, w.qm, w.lp)
        else Post.placeQuiet(w.c, w.m, text, w.qt, w.qm, w.lp)
    }

    /** THE OTHER DEVICE READ THIS CONVERSATION (iOS readByTwin 3188-3207): its letters up to the same one are read here too and the
     *  count follows what is left; at none the banner and the hand mark go. Nothing is said to the correspondent. */
    private fun readByTwin(ref: String, ms: Long?) {
        val upTo = ms?.takeIf { it > 0 } ?: return
        if (Book.chat(ref) == null) return
        var none = false
        Book.edit(ref) { c ->
            val left = c.msgs.count { !it.mine && it.at > upTo + 1 && (!Marks.isService(it.text) || it.text.startsWith(Marks.MEDIA) || it.text.startsWith(Marks.VOICE) || it.text.startsWith(Marks.STICKER)) }
            c.unread = minOf(c.unread, left)
            none = c.unread == 0
        }
        if (none) { ChatMarks.opened(ref); MainThread.post { Notify.clear(ref) } }
        Log.d("Montana", "twin_read chat=" + ref.take(10) + " upto=" + Diary.shortMs(upTo))
    }

    private fun held(): MutableList<Pair<Word, Long>> = DeviceVault.get(HELD)?.let { raw ->
        runCatching { JSONArray(String(raw, Charsets.UTF_8)).let { a -> (0 until a.length()).mapNotNullTo(mutableListOf()) { i ->
            a.optJSONObject(i)?.let { o -> o.optJSONObject("w")?.let { Word.of(it) }?.let { it to o.optLong("t") } } } } }.getOrNull()
    } ?: mutableListOf()
    private fun keepHeld(l: List<Pair<Word, Long>>) {
        if (l.isEmpty()) DeviceVault.delete(HELD)
        else DeviceVault.set(HELD, JSONArray(l.map { (w, t) -> JSONObject().put("w", w.json()).put("t", t) }).toString().toByteArray(Charsets.UTF_8))
    }
    private fun hold(w: Word) {
        synchronized(qlock) {
            val h = held()
            if (h.any { (x, _) -> x.c == w.c && x.m == w.m && x.x == w.x }) return
            h.add(w to System.currentTimeMillis())
            while (h.size > ROUND) h.removeAt(0)
            keepHeld(h)
        }
    }
    /** The words held for pipes unknown here land once their pipe stands; the rest wait two days. */
    private fun landHeld() {
        if (!DeviceVault.has(HELD)) return
        val ready = synchronized(qlock) {
            val now = System.currentTimeMillis()
            val (go, wait) = held().filter { now - it.second < HOLD_MS }.partition { (w, _) -> Book.secret(w.c) != null || Book.chat(w.c) != null }
            keepHeld(wait)
            go
        }
        for ((w, _) in ready) runCatching { land(w) }
    }

    // ───────────────────────────── the past the other device missed ─────────────────────────────

    /** The archive's key of a row's words, the same on every device of the seed (iOS rowHash 1089-1091; Windows row_hash 134-136): eight
     *  bytes of SHA-256 of the words exactly as the archive holds them, in hex. */
    fun rowHash(archived: String): String = Wire.hex(Wire.sha(archived.toByteArray(Charsets.UTF_8)).copyOf(8))

    /** A row's key as the asker spells it -- its second, its side, the hash of its archived words -- or null for a row the archive holds no
     *  words of (a file not here yet). */
    private fun rowKey(m: Msg): String? {
        if (m.at <= 0) return null
        val t = Archive.archivedText(m)?.takeIf { it.isNotEmpty() } ?: return null
        return (m.at / 1000).toString() + "|" + (if (m.mine) 1 else 0) + "|" + rowHash(t)
    }
    private fun archiveSig(m: Msg): String? =
        if (m.at <= 0) null else Archive.archivedText(m)?.takeIf { it.isNotEmpty() }?.let { (m.at / 1000).toString() + "|" + (if (m.mine) 1 else 0) + "|" + it }

    private fun asked(): LinkedHashSet<String> = DeviceVault.get(ASKED)?.let { raw ->
        runCatching { JSONArray(String(raw, Charsets.UTF_8)).let { a -> (0 until a.length()).mapTo(LinkedHashSet()) { a.optString(it) } } }.getOrNull()
    } ?: LinkedHashSet()
    private fun keepAsked(s: Collection<String>) {
        DeviceVault.set(ASKED, JSONArray(s.toList().takeLast(ASK_KEPT)).toString().toByteArray(Charsets.UTF_8))
    }

    /**
     * THE PAST THE OTHER DEVICE HOLDS AND THIS FEED DOES NOT (iOS MontanaArchive.askTwin 1093-1105, from restoreFromArchive's archive_gap
     * 3510-3521; Windows ask_twin 474-511): the mirror carries what lands from now on, and an archive row bears no letter's name, so the blocks
     * never lay rows into a conversation held here (Archive.restore). The rows they hold beyond the feed are asked of the other devices by the
     * archive's own key -- [second, side, hash] -- each key once, two hundred a round; the newest 5000 keys are remembered.
     */
    fun ask(chat: String, items: List<Triple<Long, Boolean, String>>) {
        if (items.isEmpty() || Archive.twinSecret() == null) return   // no pipe yet: no key is marked asked that never rode
        val fresh = JSONArray()
        synchronized(askLock) {
            val asked = asked()
            for ((s, mine, text) in items) {
                if (ASK_ROUND <= fresh.length()) break
                if (s <= 0 || text.isEmpty()) continue
                val h = rowHash(text)
                if (!asked.add("$chat/$s/$h")) continue
                fresh.put(JSONArray().put(s).put(if (mine) 1 else 0).put(h))
            }
            if (fresh.length() == 0) return
            keepAsked(asked)
        }
        note(Word(chat, Marks.mintMid(), ASK_MARK + JSONObject().put("i", fresh), o = 1))
        Log.d("Montana", "twin_ask chat=" + chat.take(10) + " rows=" + fresh.length())
    }

    /** A row whose file did not come whole is asked again the next time the gap is measured (iOS unaskTwin 1107-1111): its key goes by the
     *  conversation and the second, whatever form of the file's words the asker hashed (Windows unask_twin 549-553). */
    private fun unask(chat: String, s: Long) = synchronized(askLock) {
        val asked = asked()
        if (asked.removeAll { it.startsWith("$chat/$s/") }) keepAsked(asked)
    }

    private val KINDS = setOf("img", "vid", "aud", "doc")

    /**
     * THE OTHER DEVICE ASKS FOR ROWS ITS ARCHIVE HOLDS AND ITS FEED DOES NOT (iOS ChatStore.giveTwinRows 3212-3230, MontanaArchive.giveTwin
     * 1114-1137; Windows give_twin 558-599): each row held here under an asked key is given back by its name -- its words at once, its file by
     * the cargo road under a fresh key, inside the pipe only the seed's devices open; a row this phone does not hold is the truth too (deleted
     * here, or never here) and nothing is said of it.
     * WHICH ROWS: iOS passes over a row named «mid:…» -- its name for every letter the wire brought it -- so an iPhone gives back only what it
     * wrote. No row here is named so: every row is given, as Windows gives it, and a correspondent's letter this phone took (a file above all)
     * still reaches the device whose mirror's word was lost (past the box's day, past its 64 rows a day).
     * A FILE'S ROW is known by its second and its side as well: its record keeps the first form of my own letter (the manifest before the
     * pieces rode, the pick's name), which its row no longer spells, so a file is given when its second and side are asked and no row here
     * answers that key -- as Archive.restore measures the gap.
     */
    private fun give(chat: String, body: String) {
        val items = runCatching { JSONObject(body).optJSONArray("i") }.getOrNull() ?: return
        val want = HashSet<String>()
        for (i in 0 until minOf(items.length(), ASK_ROUND)) {
            val a = items.optJSONArray(i)?.takeIf { it.length() == 3 } ?: continue
            val h = a.optString(2).takeIf { it.isNotEmpty() } ?: continue
            want.add(a.optLong(0).toString() + "|" + a.optInt(1) + "|" + h)
        }
        if (want.isEmpty()) return
        val rows = Book.chat(SamePair.root(chat))?.msgs?.takeIf { it.isNotEmpty() } ?: return
        val keyed = rows.mapNotNull { m -> rowKey(m)?.let { m to it } }
        val answered = keyed.mapNotNullTo(HashSet()) { (_, k) -> k.takeIf { it in want } }
        val loose = want.filterNot { it in answered }.mapTo(HashSet()) { it.substringBeforeLast('|') }
        var given = 0
        for ((m, k) in keyed) {
            val media = m.text.startsWith(Marks.MEDIA)
            if (k !in want && !(media && k.substringBeforeLast('|') in loose)) continue
            val g = JSONObject()
            m.from?.takeIf { it.isNotEmpty() }?.let { g.put("sr", it) }
            val own = if (m.mine) 1 else null
            val at = m.at / 1000.0
            if (!media) {
                note(Word(chat, m.mid, ROW_MARK + g.put("t", m.text), o = own, at = at))
                given++
                continue
            }
            val file = m.file?.let { File(it) }?.takeIf { it.isFile } ?: continue
            val man = Media.manifestOf(m) ?: JSONObject()
            g.put("k", man.optString("k").takeIf { it in KINDS } ?: "doc").put("f", file.name)
            man.optString("n").takeIf { it.isNotEmpty() }?.let { g.put("n", it) }
            man.optString("cap").takeIf { it.isNotEmpty() }?.let { g.put("t", it) }
            man.optDouble("du", 0.0).takeIf { it > 0 }?.let { g.put("d", it) }
            val mid = m.mid
            roads.execute {
                val road = runCatching { Keeping.lay(file) }.getOrNull()
                if (road == null) { Log.d("Montana", "twin_answer a file did not reach the nodes sid=" + mid.take(16)); return@execute }
                note(Word(chat, mid, ROW_MARK + g.put("road", road), o = own, at = at))
            }
            given++
        }
        Log.d("Montana", "twin_answer chat=" + chat.take(10) + " asked=" + want.size + " given=" + given)
    }

    /**
     * A ROW THE OTHER DEVICE GAVE BACK (iOS ChatStore.takeTwinRow 3234-3266; Windows take_twin_row 604-658): laid by its own birth, once --
     * never over a row of the same name or the same archive key standing here, never over its grave; a file comes by the cargo road into the
     * media store under the name it bears on the device that gave it, and a file that did not come whole leaves its key to be asked again (a
     * file with no road is not laid: Windows; iOS would stand the row without its file). The archive already holds the row: it is not
     * written there twice. Nothing is counted unread, rung or receipted: it is history the person already lived.
     */
    private fun takeRow(w: Word, body: String) {
        val o = runCatching { JSONObject(body) }.getOrNull() ?: return
        val at = w.at ?: 0.0
        if (at <= 0.0 || w.m.isEmpty() || w.m.length > 128) return
        val ref = SamePair.root(w.c)
        val c = Book.chat(ref) ?: return
        if (c.msgs.any { it.mid == w.m } || Book.buried(ref, w.m)) return
        val own = w.o == 1
        val t = o.optString("t")
        val kind = o.optString("k").ifEmpty { null }
        var text = t
        var file: File? = null
        if (kind != null) {
            val name = o.optString("f")
            if (kind !in KINDS || name.isEmpty() || 128 < name.length || name.contains('/') || name.contains('\\') || name.startsWith(".")) return
            val ext = name.substringAfterLast('.', "").filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' }.take(8).ifEmpty { "bin" }
            val man = JSONObject().put("k", kind).put("e", ext)
            if ((kind == "img" || kind == "vid") && t.isNotEmpty()) man.put("cap", t)
            if (kind == "aud") o.optDouble("d", 0.0).takeIf { it > 0 }?.let { man.put("du", it) }
            if (kind == "img" || kind == "doc") (o.optString("n").ifEmpty { null } ?: name.takeIf { kind == "doc" })?.let { man.put("n", it.take(255)) }
            text = Marks.MEDIA + man
            file = File(Media.dir(Book.ctx), name)
        }
        if (text.isEmpty()) return
        val row = Msg(w.m, text, own, Math.round(at * 1000), state = if (own) 2 else 0, file = file?.path,
            from = o.optString("sr").takeIf { it.isNotEmpty() && it.length <= 128 })
        val sig = archiveSig(row) ?: return
        if (c.msgs.any { archiveSig(it) == sig }) return
        val f = file
        if (f == null || f.isFile) { layRow(ref, row); return }
        val road = o.optJSONObject("road") ?: return unask(w.c, at.toLong())
        val key = ref + "/" + w.m
        if (!synchronized(fetching) { fetching.add(key) }) return
        roads.execute {
            try {
                val tmp = File(f.path + ".twin")
                val came = runCatching { Keeping.fetch(road, tmp) }.getOrDefault(false) && (tmp.renameTo(f) || f.isFile)
                tmp.delete()
                if (!came) { unask(w.c, at.toLong()); Log.d("Montana", "twin_row a file did not come whole -- asked again at the next gap"); return@execute }
                row.text = Marks.MEDIA + JSONObject(row.text.removePrefix(Marks.MEDIA)).put("sz", f.length())
                layRow(ref, row)
            } finally { synchronized(fetching) { fetching.remove(key) } }
        }
    }
    private fun layRow(ref: String, row: Msg) {
        var n = 0
        var laid = false
        Book.edit(ref, archive = false) { c ->
            if (c.msgs.none { it.mid == row.mid } && !Book.buried(ref, row.mid)) { c.msgs.add(row); c.msgs.sortBy { it.at }; laid = true }
            n = c.msgs.size
        }
        if (laid) Log.d("Montana", "twin_row chat=" + ref.take(10) + " sid=" + row.mid.take(16) + " n=" + n)
    }

    /** THE LIVE CARDS GO TO THE OTHER DEVICES (iOS twinLiveCards 743-758; Windows twin_cards 236-240): the day's and the permanent one with
     *  their secrets, said at a birth and at every keeping-up; a repeat within the hour rides once (the queue's own rule). Off the caller's
     *  thread: a birth may be asked from the screen. */
    fun cards() {
        if (Archive.twinSecret() == null) return
        Thread { runCatching { for ((inv, body) in MontanaCard.liveCards()) note(Word(CARD_PIPE, inv, CARD_MARK + body, o = 1)) } }.start()
    }

    /** The person leaves: the mirror's queue, its moments, its held words and its asked keys go with them (iOS SeedScope). */
    fun wipe() {
        synchronized(qlock) { qfile().delete(); given.clear(); unreadable = false }
        DeviceVault.delete(HELD)
        synchronized(askLock) { DeviceVault.delete(ASKED) }
        Prefs.remove(DUE + "lt")
    }
}
