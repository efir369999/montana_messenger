package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * THE CARGO ROAD OF A FILE AND THE KNOCK IN A PIPE OF ITS OWN (iOS MTKeeping.lay / fetch / knock / word, MTKeeping.swift 417-841):
 * a file is sealed in pieces under a fresh key and put on the nodes, its list of pieces sealed as one more piece under a key of
 * its own; the word that names the file carries that piece's name and both keys, never the list (a list outgrows a letter). The
 * word rides the box of a pipe as a letter of the keeping vocabulary («KP:» and JSON). The keeping of a copy with correspondents
 * (the slots, the ring, the parts) has no road on this phone yet: only the road the seed's own pipe needs stands here.
 */
object Keeping {
    const val MARK = "​​KP:"   // iOS keepMark (ContentView.swift:4015): NOT-UI, a word of the keeping vocabulary

    fun word(text: String): JSONObject? =
        if (!text.startsWith(MARK)) null else runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull()

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)

    /** A FILE ON THE CARGO ROAD (iOS layPieces 676-686): its pieces under a fresh key, their list sealed as one more piece. */
    fun lay(f: File): JSONObject? {
        val size = f.length()
        if (size <= 0L) return null
        val bk = MtBindings.nativeRandom(32) ?: return null
        val (bk64, chunks) = Media.layFile(f, "", key = bk) {} ?: return null
        val mk = MtBindings.nativeRandom(32) ?: return null
        val sealed = Wire.seal(mk, chunks.toString().toByteArray()) ?: return null
        val mref = Wire.hex(Wire.sha(sealed))
        if (!Wire.putBlob(mref, sealed)) return null
        return JSONObject().put("z", size).put("bk", bk64).put("mref", mref).put("mk", b64(mk))
    }

    /** The file comes back piece by piece (iOS fetch 688-714): the list checked by its name, each piece by its own, the length whole. */
    fun fetch(o: JSONObject, dest: File): Boolean {
        val size = o.optLong("z", 0L)
        val bk = o.optString("bk"); val mref = o.optString("mref")
        val mk = runCatching { Base64.decode(o.optString("mk"), Base64.DEFAULT) }.getOrNull()
        if (size <= 0L || bk.isEmpty() || mref.isEmpty() || mk == null) return false
        val list = Wire.getBlob(mref)?.takeIf { Wire.hex(Wire.sha(it)) == mref } ?: return false
        val chunks = Wire.open(mk, list)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: return false
        dest.delete()
        if (!Media.download(JSONObject().put("bk", bk).put("chunks", chunks), dest)) return false
        return dest.length() == size
    }

    /**
     * ONE LETTER IN A PIPE OF ITS OWN (iOS knock 833-841, MTNodeWire.knockLetter): mid ‖ 0 ‖ «KP:» and the word ‖ 0 ‖ 0 ‖ 0, padded to
     * the envelope, sealed afresh at every door; the first door that boxes it ends the walk. `sender` -- the name the pipe hears it
     * from: the node never gives a letter back to the name that laid it.
     */
    fun knock(secret: ByteArray, o: JSONObject, sender: String, silent: Boolean = true): Boolean {
        val mid = UUID.randomUUID().toString().uppercase()
        val body = mid.toByteArray() + byteArrayOf(0) + (MARK + o.toString()).toByteArray() + byteArrayOf(0, 0, 0)
        if (body.size > Wire.ENVELOPE) return false
        val plain = body + ByteArray(Wire.ENVELOPE - body.size)
        val cw = Wire.convW(secret, Wire.day())
        for (door in Signal.writeOrder("box")) {
            val env = Wire.seal(Wire.bodyKey(secret, Wire.minute()), plain) ?: return false
            val (code, _) = Wire.post(door, "/wake", JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, sender)).put("mid", mid)
                .put("env", b64(env)).apply { if (silent) put("silent", true) })
            if (code == 200) { Signal.doorAnswered(door); return true }
            Signal.doorFailed(door, code)
        }
        return false
    }
}

/**
 * THE SEED'S OWN PIPE (iOS MontanaArchive twinSecret … takeMirror, MontanaPQ.swift 879-1153; 349cc053, f376b4ef; the author's words
 * 18.10.2026 10:2x-10:4x MSK: «on T1 the letters of 10:07 are not seen, on the Mac with the same person they are»; «what I posted
 * from the phone is not seen -- it does not sync as the chats do»; «read on the phone -- read on every device»). The node's box gives
 * a letter to whichever device of the seed takes it first, and that device's confirmation erases it for the rest; so every word a
 * device takes from a correspondent, sends, or reads rides to the seed's other devices in the pipe only they derive, on the cargo
 * road, under the name it was born with («lt»), and the history's blocks ride there too («hist»). There each word walks the one
 * landing road (Post.landMirrored): a name standing is a repeat, a buried name stays buried, a mirrored word rides no further.
 */
object Twin {
    const val PIPE = "twin:history"                 // iOS twinPipe: the box name of the pipe of this seed's devices
    const val READ = "​​TR:"              // iOS twinReadMark: a read mark for this seed's devices alone
    const val ASK = "​​TA:"               // iOS twinAskMark: the asker's keys
    const val CARD = "​​TC:"              // iOS twinCardMark: a card the other device gave birth to
    const val CARD_PIPE = "twin:card"              // iOS twinCardPipe: the mirror's name for the cards' words, never a conversation
    const val ROW = "​​TW:"               // iOS twinRowMark: one row given back
    // THE PIPE IS THE APP'S, NOT THE PACKAGE'S (iOS twinSecret mixes Bundle.main.bundleIdentifier, quest.montana.app for Montana): two
    // apps of one seed keep two pipes; the iPhone's Montana and this one are one app, whatever this build's package is called
    private const val APP = "quest.montana.app"
    private const val MIRROR = "mt.twin.mirror"     // the queue (iOS twin-mirror.json), sealed in the vault: it holds letters
    private const val SEEN = "mt.history.twinSeen"  // iOS twinSeenKey: the letters of the other devices already taken
    private const val ASKED = "mt.twin.asked"       // iOS askedKey
    private const val KEPT = 4000                   // iOS mirrorKept
    private const val ROUND = 500                   // iOS mirrorRound
    private val ex = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "twin").apply { isDaemon = true } }
    private val lock = Any()

    fun forget() = synchronized(lock) { listOf(MIRROR, SEEN, ASKED).forEach { DeviceVault.delete(it) }; given.clear() }

    fun secret(): ByteArray? = Archive.historyKey()?.let { hk ->
        Wire.sha("mt-twin-box".toByteArray(), byteArrayOf(0), APP.toByteArray(), byteArrayOf(0), hk)
    }
    /** This device's name in the pipe (iOS twinDeviceRef): the node rings every device of the pipe but the one that spoke. */
    fun deviceRef(): String? = MontanaSeed.twin?.let { it + "#" + Archive.deviceTag() }
    /** The one place a label of the seed's own pipe is asked: under this device's name, never the person's (iOS twinSid). */
    fun sid(cw: String): String? = deviceRef()?.let { Wire.subId(cw, it) }

    private fun vault(key: String): JSONArray = DeviceVault.get(key)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONArray()
    private fun strings(key: String): MutableList<String> = vault(key).let { a -> MutableList(a.length()) { a.optString(it) } }
    private fun keepStrings(key: String, l: List<String>) = DeviceVault.set(key, JSONArray(l).toString().toByteArray())
    private fun scratch(): File = File(Book.ctx.cacheDir, UUID.randomUUID().toString() + ".twin")

    // ── the history's blocks (iOS twinSoon / layForTwins / takeFromTwin) ──
    @Volatile private var histDue = false
    /** A block was written: the other devices get it within half a minute, in one letter with whatever came beside it. */
    fun histSoon() {
        synchronized(lock) { if (histDue) return; histDue = true }
        ex.schedule({ synchronized(lock) { histDue = false }; runCatching { layHist() }.onFailure { Log.w("Montana", "twin_hist " + it.javaClass.simpleName) } }, 30, TimeUnit.SECONDS)
    }
    private fun layHist() {
        val g = Archive.twinBlocks() ?: return
        if (g.n == 0) return
        val secret = secret() ?: return
        val me = deviceRef() ?: return
        val f = scratch()
        try {
            f.writeBytes(g.blob)
            val road = Keeping.lay(f) ?: return Unit.also { Log.d("Montana", "twin_hist the blocks did not reach the nodes n=" + g.n) }
            road.put("w", "hist").put("n", g.n).put("f", Archive.writerHex() ?: "")
            if (!Keeping.knock(secret, road, me)) { Log.d("Montana", "twin_hist no door boxed the letter n=" + g.n); return }
            Archive.twinBoxed(g.tops)
            Log.d("Montana", "twin_hist laid blocks=" + g.n + " bytes=" + g.blob.size + " more=" + (if (g.more) 1 else 0))
            if (g.more) histSoon()
        } finally { f.delete() }
    }
    private fun takeHist(o: JSONObject, mid: String) {
        if (o.optString("f") == Archive.writerHex()) return   // this device's own letter, heard back from the box
        if (mid in strings(SEEN)) return
        val f = scratch()
        try {
            if (!Keeping.fetch(o, f)) { Log.d("Montana", "twin_hist the blocks did not come whole"); return }
            val b = f.readBytes()
            var i = 0; var filed = 0
            while (i + 4 <= b.size) {
                val len = (b[i].toInt() and 0xff) or ((b[i + 1].toInt() and 0xff) shl 8) or ((b[i + 2].toInt() and 0xff) shl 16) or ((b[i + 3].toInt() and 0xff) shl 24)
                i += 4
                if (len <= 0 || b.size < i + len) break
                if (Archive.absorb(b.copyOfRange(i, i + len))) filed++
                i += len
            }
            seen(mid)
            Log.d("Montana", "twin_hist taken blocks=" + filed)
        } finally { f.delete() }
    }
    private fun seen(mid: String) = synchronized(lock) { keepStrings(SEEN, (strings(SEEN) + mid).takeLast(512)) }

    // ── the pickup (iOS twinTakes) ──
    /** A row of the box in the pipe of this seed's devices is this file's own, never a letter of the feed. */
    fun takes(text: String, mid: String) {
        val o = Keeping.word(text) ?: return
        if (mid.isEmpty()) return
        when (o.optString("w")) {
            "hist" -> ex.execute { runCatching { takeHist(o, mid) }.onFailure { Log.w("Montana", "twin_hist " + it.javaClass.simpleName) } }
            "lt" -> ex.execute { runCatching { takeMirror(o, mid) }.onFailure { Log.w("Montana", "twin_mirror " + it.javaClass.simpleName) } }
        }
    }

    // ── the mirror (iOS TwinWord, mirrorNote, layMirror, takeMirror) ──
    /**
     * THE MIRROR'S CHOICE OF WORDS (iOS MontanaDeliveryEngine.mirrors): what stands in a conversation or moves a row -- a letter of
     * every kind, a reaction's row, an edit, a deletion, a receipt, a group's word -- rides; what says only «here, now» (typing,
     * presence, a call's signal, a draft, a name, a face) does not: it would be stale where it landed.
     */
    fun mirrors(text: String): Boolean {
        if (text.startsWith(Groups.MARK)) return runCatching { JSONObject(text.removePrefix(Groups.MARK)).optString("t") != "ty" }.getOrDefault(false)
        if (text.startsWith(Marks.DELIVERED) || text.startsWith(Marks.READ) || text.startsWith(Marks.DELETE)) return true
        if (!Marks.isService(text) || text.startsWith(Marks.MEDIA) || text.startsWith(Marks.VOICE) || text.startsWith(Marks.STICKER)) return true
        return changesRow(text)
    }
    /** iOS MTRowLetter.changesRow: a row's own words, never the machinery. */
    private fun changesRow(text: String): Boolean {
        if (text.isEmpty() || ChessLetter.isStep(text)) return false
        if (text.startsWith(Marks.STICKER)) return true
        if (text.startsWith("​​")) return text.drop(2).take(3) in setOf("VC:", "MD:", "MC:", "CL:", "GE:")
        if (text.startsWith(Marks.LONG)) return true
        return !(text.startsWith("⁣") || text.startsWith("⁤") || text.startsWith("​"))
    }

    private val given = HashMap<String, Long>()   // a name given within the hour: a later copy of it by another road stays
    @Volatile private var mirrorDue = false

    /**
     * A WORD FOR THE SEED'S OTHER DEVICES (iOS mirrorNote): kept in the vault until it rode, laid within half a minute with whatever
     * came beside it. A repeat within the hour is not queued twice; a newer read mark of a conversation stands for the older.
     * `at` -- seconds, as iOS writes it.
     */
    fun note(c: String, m: String, x: String, own: Boolean = false, at: Double? = null, qt: String? = null, qm: String? = null, lp: String? = null) {
        if (MontanaSeed.twin == null) return
        synchronized(lock) {
            val reads = x.startsWith(READ)
            val now = System.currentTimeMillis()
            val name = c + "/" + m + "/" + x.take(24)
            if (!reads && now - (given[name] ?: 0L) <= 3_600_000L) return
            given[name] = now
            if (2000 < given.size) given.entries.removeAll { now - it.value >= 3_600_000L }
            val a = vault(MIRROR)
            val keep = JSONArray()
            var top = 0L
            for (i in 0 until a.length()) a.getJSONObject(i).let { e ->
                top = maxOf(top, e.optLong("q"))
                if (!(reads && e.optString("c") == c && e.optString("x").startsWith(READ))) keep.put(e)
            }
            val w = JSONObject().put("c", c).put("m", m).put("x", x).put("q", top + 1)
            if (own) w.put("o", 1)
            at?.takeIf { it > 0 }?.let { w.put("at", it) }
            qt?.takeIf { it.isNotEmpty() }?.let { w.put("qt", it) }
            qm?.takeIf { it.isNotEmpty() }?.let { w.put("qm", it) }
            lp?.takeIf { it.isNotEmpty() }?.let { w.put("lp", it) }
            keep.put(w)
            val out = if (keep.length() <= KEPT) keep else JSONArray().also { t -> for (i in keep.length() - KEPT until keep.length()) t.put(keep.get(i)) }
            DeviceVault.set(MIRROR, out.toString().toByteArray())
        }
        mirrorSoon()
    }
    private fun mirrorSoon() {
        synchronized(lock) { if (mirrorDue) return; mirrorDue = true }
        ex.schedule({ synchronized(lock) { mirrorDue = false }; runCatching { layMirror() }.onFailure { Log.w("Montana", "twin_mirror " + it.javaClass.simpleName) } }, 30, TimeUnit.SECONDS)
    }
    private fun layMirror() {
        val batch = synchronized(lock) { vault(MIRROR).let { a -> JSONArray().also { b -> for (i in 0 until minOf(ROUND, a.length())) b.put(a.get(i)) } } }
        if (batch.length() == 0) return
        val secret = secret() ?: return
        val me = deviceRef() ?: return
        val f = scratch()
        try {
            f.writeBytes(batch.toString().toByteArray())
            val road = Keeping.lay(f) ?: return Unit.also { mirrorSoon(); Log.d("Montana", "twin_mirror the words did not reach the nodes n=" + batch.length()) }
            road.put("w", "lt").put("n", batch.length()).put("f", Archive.writerHex() ?: "")
            if (!Keeping.knock(secret, road, me)) { mirrorSoon(); Log.d("Montana", "twin_mirror no door boxed the letter n=" + batch.length()); return }
            var top = -1L
            for (i in 0 until batch.length()) top = maxOf(top, batch.getJSONObject(i).optLong("q", -1L))
            val left = synchronized(lock) {
                val a = vault(MIRROR)
                val keep = JSONArray()
                for (i in 0 until a.length()) a.getJSONObject(i).let { if (it.optLong("q", -1L) > top) keep.put(it) }
                DeviceVault.set(MIRROR, keep.toString().toByteArray())
                keep.length()
            }
            if (left > 0) mirrorSoon()
            Log.d("Montana", "twin_mirror laid words=" + batch.length() + " left=" + left)
        } finally { f.delete() }
    }
    /** The words of the seed's other device: each lands here by the one landing road, in the order that device heard them. */
    private fun takeMirror(o: JSONObject, mid: String) {
        if (o.optString("f") == Archive.writerHex()) return
        if (mid in strings(SEEN)) return
        val f = scratch()
        val words = try {
            if (!Keeping.fetch(o, f)) { Log.d("Montana", "twin_mirror the words did not come whole"); return }
            runCatching { JSONArray(f.readText()) }.getOrNull() ?: return
        } finally { f.delete() }
        seen(mid)
        for (i in 0 until words.length()) runCatching { land(words.getJSONObject(i)) }.onFailure { Log.w("Montana", "twin_land " + it.javaClass.simpleName) }
        Log.d("Montana", "twin_mirror taken words=" + words.length())
    }

    /**
     * A WORD THE SEED'S OTHER DEVICE MIRRORED HERE (iOS MontanaDeliveryEngine.landMirrored): a read mark reads the conversation here
     * too and takes its banners down; the twin's past is asked and given back by name; every other word walks the one landing road
     * under the name it was born with.
     */
    private fun land(w: JSONObject) {
        val c = w.optString("c"); val m = w.optString("m"); val x = w.optString("x")
        if (c.isEmpty() || m.isEmpty() || x.isEmpty()) return
        when {
            x.startsWith(READ) -> readByTwin(c, x.removePrefix(READ).toLongOrNull())
            x.startsWith(ASK) -> giveRows(c, x.removePrefix(ASK))
            // a card the other device gave birth to: this device opens the introductions it brings (iOS MontanaCard.takeTwin)
            x.startsWith(CARD) -> MontanaCard.takeTwin(x.removePrefix(CARD))
            x.startsWith(ROW) -> takeRow(c, m, w.optInt("o") == 1, w.optDouble("at", 0.0), x.removePrefix(ROW))
            else -> Post.landMirrored(c, m, x, w.optInt("o") == 1, w.optString("qt").ifEmpty { null }, w.optString("qm").ifEmpty { null },
                w.optString("lp").ifEmpty { null })
        }
    }

    /**
     * THE SEED'S OTHER DEVICE READ THIS CONVERSATION (iOS ChatStore.readByTwin): its letters up to the same one are read here too, the
     * count follows what is left, and the banners of the conversation leave -- nothing is said to the correspondent: the device that
     * read already said it, if the person tells it at all.
     */
    private fun readByTwin(ref: String, upTo: Long?) {
        if (upTo == null || upTo <= 0L) return
        val chat = Book.chat(ref) ?: return
        val left = chat.msgs.count { !it.mine && (Marks.birthMs(it.mid) ?: it.at) > upTo }
        if (left < chat.unread) Book.edit(ref) { it.unread = minOf(it.unread, left) }
        if (left == 0) MainThread.post { Notify.clear(ref) }
        Log.d("Montana", "twin_read chat=" + ref.take(10) + " left=" + left)
    }
    /** The read mark for the seed's other devices (iOS markRead's mirrorNote): what was unread here is read there up to this letter. */
    fun read(ref: String, newestMs: Long) = note(ref, UUID.randomUUID().toString().uppercase(), READ + newestMs, own = true)

    // ── the twin's past (iOS askTwin / giveTwinRows / takeTwinRow, f376b4ef) ──
    /** The rows of a conversation the archive holds and the feed does not: asked once, two hundred at most a round. */
    fun ask(chat: String, items: List<Triple<Long, Boolean, String>>) {
        if (MontanaSeed.twin == null) return
        val fresh = synchronized(lock) {
            val asked = strings(ASKED)
            val have = asked.toHashSet()
            val f = items.filter { (s, _, h) -> "$chat/$s/$h" !in have }.take(200)
            if (f.isEmpty()) return
            keepStrings(ASKED, (asked + f.map { (s, _, h) -> "$chat/$s/$h" }).takeLast(5000))
            f
        }
        val js = JSONObject().put("i", JSONArray(fresh.map { (s, mine, h) -> JSONArray().put(s).put(if (mine) 1 else 0).put(h) }))
        note(chat, UUID.randomUUID().toString().uppercase(), ASK + js.toString(), own = true)
        Log.d("Montana", "twin_ask chat=" + chat.take(10) + " rows=" + fresh.size)
    }
    /** A row whose file did not come whole is asked again the next time the gap is measured. */
    private fun unask(chat: String, s: Long, h: String) = synchronized(lock) { keepStrings(ASKED, strings(ASKED).filter { it != "$chat/$s/$h" }) }

    /**
     * THE OTHER DEVICE ASKS FOR ROWS ITS ARCHIVE HOLDS AND ITS FEED DOES NOT (iOS ChatStore.giveTwinRows): each row held here under the
     * archive's own key -- its second, its side, the hash of its words -- is given back by its name, a file by the cargo road; a row
     * this device does not hold is the truth too (deleted here, or never here) and nothing is said of it.
     */
    private fun giveRows(chat: String, body: String) {
        val items = runCatching { JSONObject(body).getJSONArray("i") }.getOrNull() ?: return
        val rows = Book.chat(chat)?.msgs ?: return
        val want = HashSet<String>()
        for (i in 0 until minOf(200, items.length())) items.optJSONArray(i)?.takeIf { it.length() == 3 }?.let { a ->
            want.add(a.optLong(0).toString() + "|" + a.optInt(1) + "|" + a.optString(2))
        }
        var n = 0
        for (m in rows) {
            if (m.mid.startsWith("arc:") || m.at <= 0) continue
            val t = Archive.archivedText(m) ?: continue
            if ((m.at / 1000).toString() + "|" + (if (m.mine) 1 else 0) + "|" + Archive.rowHash(t) !in want) continue
            give(chat, m)
            n++
        }
        Log.d("Montana", "twin_answer chat=" + chat.take(10) + " asked=" + want.size + " given=" + n)
    }
    private fun give(chat: String, m: Msg) {
        val o = JSONObject()
        m.from?.let { o.put("sr", it) }
        val at = m.at / 1000.0
        if (!m.text.startsWith(Marks.MEDIA)) {
            if (m.text.isEmpty()) return
            note(chat, m.mid, ROW + o.put("t", m.text).toString(), m.mine, at)
            return
        }
        // a media row: the words iOS keeps beside the file (a caption), the kind, the file's name, a document's name, a voice's length
        val man = Media.manifestOf(m) ?: return
        val f = m.file?.let { File(it) }?.takeIf { it.isFile } ?: return
        man.optString("cap").takeIf { it.isNotEmpty() }?.let { o.put("t", it) }
        o.put("k", man.optString("k").ifEmpty { "doc" }).put("f", f.name)
        man.optString("n").takeIf { it.isNotEmpty() }?.let { o.put("n", it) }
        man.optDouble("du", 0.0).takeIf { it > 0 }?.let { o.put("d", it) }
        ex.execute {
            val road = Keeping.lay(f) ?: return@execute Unit.also { Log.d("Montana", "twin_answer a file did not reach the nodes") }
            note(chat, m.mid, ROW + o.put("road", road).toString(), m.mine, at)
        }
    }

    /**
     * A ROW THE OTHER DEVICE GAVE BACK (iOS ChatStore.takeTwinRow): laid by its own birth, once -- never over a row of the same name or
     * the same archive key standing here, never over its tombstone; a file comes by the cargo road under the name it bears there.
     */
    private fun takeRow(chat: String, mid: String, own: Boolean, at: Double, body: String) {
        val o = runCatching { JSONObject(body) }.getOrNull() ?: return
        if (at <= 0 || mid.isEmpty()) return
        val rows = Book.chat(chat)?.msgs ?: return
        if (rows.any { it.mid == mid } || Book.isBuried(chat, mid) || Book.diedBefore(chat, mid)) return
        val text = o.optString("t"); val sr = o.optString("sr").ifEmpty { null }
        val kind = o.optString("k").ifEmpty { null }
        val ms = (at * 1000).toLong()
        if (kind == null) {
            if (text.isEmpty()) return
            if (rows.any { it.at / 1000 == ms / 1000 && it.mine == own && it.text == text }) return
            lay(chat, Msg(mid, text, own, ms, state = if (own) 2 else 3, from = sr))
            return
        }
        val name = o.optString("f")
        if (kind !in setOf("img", "vid", "aud", "doc") || name.isEmpty() || name.contains('/') || name.startsWith(".")) return
        val man = JSONObject().put("k", kind).put("e", name.substringAfterLast('.', ""))
        o.optString("n").takeIf { it.isNotEmpty() }?.let { man.put("n", it) }
        if (text.isNotEmpty() && (kind == "img" || kind == "vid")) man.put("cap", text)
        o.optDouble("d", 0.0).takeIf { it > 0 }?.let { man.put("du", it) }
        val dest = File(Media.dir(Book.ctx), name)
        val row = { file: String? -> Msg(mid, Marks.MEDIA + man.toString(), own, ms, state = if (own) 2 else 3, file = file, meta = man.toString(), from = sr) }
        if (dest.isFile) { lay(chat, row(dest.path)); return }
        val road = o.optJSONObject("road") ?: return
        val h = Archive.rowHash(Archive.archivedText(row(dest.path)) ?: "")
        ex.execute {
            val tmp = scratch()
            try {
                if (!Keeping.fetch(road, tmp) || !tmp.renameTo(dest)) {
                    unask(chat, ms / 1000, h)
                    Log.d("Montana", "twin_row a file did not come whole -- asked again at the next gap"); return@execute
                }
            } finally { tmp.delete() }
            lay(chat, row(dest.path))
        }
    }
    private fun lay(chat: String, m: Msg) {
        var n = 0
        Book.edit(chat) { c ->
            if (c.msgs.none { it.mid == m.mid } && !Book.isBuried(chat, m.mid)) { c.msgs.add(m); c.msgs.sortBy { it.at } }
            n = c.msgs.size
        }
        Log.d("Montana", "twin_row chat=" + chat.take(10) + " sid=" + m.mid.take(16) + " n=" + n)
    }
}
