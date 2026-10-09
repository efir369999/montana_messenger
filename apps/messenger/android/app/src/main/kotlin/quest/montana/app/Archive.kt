package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * THE ARCHIVE OF LETTERS (iOS MontanaArchive, MontanaPQ 281-1082; the map is timechain/ARCHIVE-MAP.md). Every row of the feed is
 * sealed under the history key of the seed into its conversation's log, Montana/Chats/FOLDER/conversation.mtlog, the files of the
 * media under the media key beside it; the folder's name is a keyed hash that says nothing to whoever sees it. Each folder carries
 * its head — the pipe's secret, the correspondent's name, their face — so that the 24 words alone bring the history back and the
 * conversations stay answerable. The core does every seal (mt_archive_*); this side only names, orders and asks.
 */
object Archive {
    private const val HEAD_DIR = 2   // iOS headDir 844: letters use 0 (mine) and 1 (theirs)
    private const val FACE = "face"  // iOS faceBlob 916
    private const val FOLDERS = "mt.history.folders"     // conv → folder (iOS folderMapKey 820)
    private const val HEADS = "mt.history.heads.form"    // folder → the head's form (iOS headsKey 845)
    private const val NAMES = "mt.history.nameheads"     // folder → the name sealed last (iOS nameHeadsKey 925)
    private const val DEVICE = "mt.history.device"       // this install's sixteen bytes (iOS writerTag16, local)
    private const val PUSHED = "mt.history.pushed"       // folder → the next block number the twin has not been handed (iOS cursorKey 612)
    private val q = Executors.newSingleThreadExecutor { r -> Thread(r, "archive").apply { isDaemon = true } }
    @Volatile private var keys: Keys? = null

    private class Keys(val hk: ByteArray, val mk: ByteArray, val owner: ByteArray)

    private fun root(): File? = runCatching { MontanaPaths.archive(Book.ctx) }.getOrNull()

    /** THE FROZEN VECTOR OF THE HISTORY KEY (iOS MontanaVault.historyKeyKAT): HKDF over 0x55 × 32, computed outside this code. */
    fun historyKeyKAT(): Boolean =
        MtBindings.nativeHistoryKey(ByteArray(32) { 0x55 })?.let { Wire.hex(it) } == "e6a7dc51003770589d9f731c1231c1523be7348c7769383875dd34bd6c578def"

    /**
     * THE KEYS, ONCE, ON THE ARCHIVE'S OWN THREAD (iOS keys 390-420): history and media from the phrase's entropy, the owner branch from
     * its seed; and none of it before the frozen vectors of the Canon reproduce — a history sealed under a wrong key is a history lost.
     */
    @Synchronized private fun keys(): Keys? {
        keys?.let { return it }
        val words = MontanaSeed.mnemonic ?: return null
        if (!historyKeyKAT() || !Wire.pipeAgreesWithCanon()) {
            Log.w("Montana", "archive: the frozen vectors of the Canon do not reproduce — history is not written")
            return null
        }
        val ent = MtBindings.nativeMnemonicToEntropy(words) ?: return null
        val hk = MtBindings.nativeHistoryKey(ent) ?: return null
        val mk = MtBindings.nativeMediaKey(ent) ?: return null
        ent.fill(0)
        val master = MtBindings.nativeMnemonicToMasterSeed(words) ?: return null
        val owner = Wire.ownerSecret(master) ?: return null
        master.fill(0)
        return Keys(hk, mk, owner).also { keys = it }
    }

    /** The person left: the keys leave with them (iOS forgetKeys 348), and the next person's launch reads the archive afresh. */
    fun forgetKeys() { keys = null; launched = false }

    @Volatile private var launched = false

    /** The cold start's reading (iOS ChatStore 2361-2368, 2533): once a process, after the feed stands — rows go only where it has none. */
    fun atLaunch() { if (!launched) { launched = true; restoreSoon() } }

    /** This install's sixteen bytes (iOS writerTag16 438-442): local by nature, they part the nonces of one seed's devices. */
    private fun device(): ByteArray = DeviceVault.get(DEVICE)?.takeIf { it.size == 16 }
        ?: (MtBindings.nativeRandom(16) ?: ByteArray(16)).also { DeviceVault.set(DEVICE, it) }

    /** A folder's name (iOS folderLabel 639-644): SHA-256("mt-archive-label" ‖ 0 ‖ hk ‖ 0 ‖ ref)[0..16], thirty-two hex letters. */
    private fun label(k: Keys, ref: String) = Wire.hex(Wire.sha("mt-archive-label".toByteArray(), byteArrayOf(0), k.hk, byteArrayOf(0), ref.toByteArray()).copyOf(16))

    private fun conv(ref: String) = Wire.sha(ref.toByteArray())   // iOS MontanaQueueKeys.sha256(convRef)

    private fun map(name: String): JSONObject = DeviceVault.get(name)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONObject()
    private fun keep(name: String, o: JSONObject) = DeviceVault.set(name, o.toString().toByteArray())

    /** Queue-only: the folder of a conversation, its head written the first time the folder is named (iOS resolveFolder, rememberFolder 497-504, 822-830). */
    private fun folder(k: Keys, ref: String): String {
        val f = label(k, ref)
        val m = map(FOLDERS)
        val c = Wire.hex(conv(ref))
        if (m.optString(c) != f) { keep(FOLDERS, m.put(c, f)); headIn(k, ref, f) }
        return f
    }

    private fun append(k: Keys, ref: String, folder: String, dir: Int, atSec: Long, content: ByteArray): Boolean {
        val base = root()?.path ?: return false
        return MtBindings.nativeArchiveAppend(base, folder, k.hk, k.owner, device(), conv(ref), dir, atSec, content) == 0
    }

    /**
     * WHAT A ROW IS IN THE ARCHIVE (iOS archivedText 3702-3709): a letter goes as its words; a media row as the media mark and a small
     * record — kind, the file's name, the document's name, the caption, the voice's length — keys in sorted order, as iOS encodes them.
     */
    fun archivedText(m: Msg): String? {
        if (!m.text.startsWith(Marks.MEDIA)) return m.text
        val f = m.file?.let { File(it).name } ?: return null
        val j = runCatching { JSONObject(m.text.removePrefix(Marks.MEDIA)) }.getOrNull() ?: return null
        val rec = JSONObject()
        j.optString("cap").takeIf { it.isNotEmpty() }?.let { rec.put("cap", it) }
        j.optDouble("du", 0.0).takeIf { it > 0 }?.let { rec.put("d", it) }
        rec.put("f", f).put("k", j.optString("k"))
        j.optString("n").takeIf { it.isNotEmpty() }?.let { rec.put("n", it) }
        return Marks.MEDIA + rec.toString()
    }

    /** THE ONE ROAD FROM A ROW TO THE ARCHIVE (iOS archiveRow 3715-3719, archive 570-592): sealed off the screen's thread, in order. */
    fun row(ref: String, m: Msg) {
        val text = archivedText(m)?.takeIf { it.isNotEmpty() } ?: return
        val at = (if (m.at > 0) m.at else System.currentTimeMillis()) / 1000
        val dir = if (m.mine) 0 else 1
        q.execute {
            val k = keys() ?: return@execute
            append(k, ref, folder(k, ref), dir, at, text.toByteArray())
        }
    }

    /**
     * THE HEAD OF A FOLDER (iOS writeHeadIn 861-880): the pipe's secret when this phone holds it — «s:» and base64, the conversation's name
     * being sixteen bytes of its hash — else the bare name «a:»; written again only when its form changes.
     */
    private fun headIn(k: Keys, ref: String, folder: String) {
        val sec = Book.secret(ref)?.takeIf { Wire.reference(it) == ref }
        val (content, form) = if (sec != null) ("s:" + Base64.encodeToString(sec, Base64.NO_WRAP)) to "s" else ("a:" + ref) to "a"
        val heads = map(HEADS)
        if (heads.optString(folder) == form) return
        keep(HEADS, heads.put(folder, form))
        append(k, ref, folder, HEAD_DIR, System.currentTimeMillis() / 1000, content.toByteArray())
        Log.d("Montana", "archive_head form=" + form)
    }

    /** A pipe was born (iOS MTPipe 432): its folder and its head are written now, before its first letter. */
    fun head(ref: String) = q.execute { keys()?.let { k -> folder(k, ref) } }

    /** THE PIPE CLOSED AT THE OTHER END (iOS closeHead 883-893): the folder says so, so no restore revives it from the secret it holds. */
    fun closeHead(ref: String) = q.execute {
        val k = keys() ?: return@execute
        val f = folder(k, ref)
        keep(HEADS, map(HEADS).put(f, "x"))
        append(k, ref, f, HEAD_DIR, System.currentTimeMillis() / 1000, "x:".toByteArray())
    }

    /** The correspondent's name, sealed beside their letters, written again when it changes (iOS writeNameHeadIn 936-960). */
    fun nameHead(ref: String, name: String) {
        val n = name.trim()
        if (n.isEmpty() || n.length > 64) return
        q.execute {
            val k = keys() ?: return@execute
            val f = folder(k, ref)
            val marks = map(NAMES)
            if (marks.optString(f) == n) return@execute
            keep(NAMES, marks.put(f, n))
            append(k, ref, f, HEAD_DIR, System.currentTimeMillis() / 1000, ("n:" + n).toByteArray())
        }
    }

    /** Their face, sealed under the media key into the folder as «face» (iOS sealFace 919-923). */
    private fun faceIn(k: Keys, ref: String) {
        val bytes = Book.face(ref).takeIf { it.isFile }?.readBytes()?.takeIf { it.isNotEmpty() } ?: return
        val base = root()?.path ?: return
        MtBindings.nativeArchivePutMedia(base, folder(k, ref), FACE, k.mk, k.owner, bytes)
    }

    // ── THE READING ROAD (iOS 832-1082; ChatStore restoreFromArchive 3006-3077, applyRestored 3084-3130) ──

    private class Rec(val dir: Int, val at: Long, val content: ByteArray)
    private class Item(val at: Long, val mine: Boolean, val text: String)

    private fun u32(d: ByteArray, o: Int) = (d[o].toInt() and 0xff) or ((d[o + 1].toInt() and 0xff) shl 8) or
        ((d[o + 2].toInt() and 0xff) shl 16) or ((d[o + 3].toInt() and 0xff) shl 24)

    /** The sealed blocks of one folder in file order: (u32 LE length ‖ sealed)×N, the layout the core writes (iOS readLog 964-976). */
    private fun readLog(f: File): List<ByteArray> {
        val d = runCatching { f.readBytes() }.getOrNull() ?: return emptyList()
        val out = ArrayList<ByteArray>()
        var i = 0
        while (i + 4 <= d.size) {
            val n = u32(d, i)
            i += 4
            if (n <= 0 || d.size < i + n) break
            out.add(d.copyOfRange(i, i + n))
            i += n
        }
        return out
    }

    /** One block's canon (iOS openBlock 979-1001): block_seq u64 ‖ count u32 at 8 ‖ (conv[32] ‖ dir ‖ at u64 ‖ len u32 ‖ content)×count, LE. */
    private fun opened(d: ByteArray): List<Rec> {
        if (d.size <= 12) return emptyList()
        val out = ArrayList<Rec>()
        var o = 12
        for (x in 0 until u32(d, 8)) {
            if (d.size < o + 45) break
            o += 32
            val dir = d[o].toInt() and 0xff
            o += 1
            var at = 0L
            for (b in 0 until 8) at = at or ((d[o + b].toLong() and 0xff) shl (8 * b))
            o += 8
            val n = u32(d, o)
            o += 4
            if (n < 0 || d.size < o + n) break
            out.add(Rec(dir, at, d.copyOfRange(o, o + n)))
            o += n
        }
        return out
    }

    /**
     * The rows of a restored conversation (iOS ChatStore 3041-3066): one per signature — the second, mine or theirs, the words, joined
     * by the bar — named «arc:» and twelve bytes of its hash, read history; a media row is its record again, the file found by its name
     * in this phone's media store, if it stayed.
     */
    private fun rows(items: List<Item>): List<Msg> {
        val seen = HashSet<String>()
        val out = ArrayList<Msg>()
        for (it in items.sortedBy { it.at }) {
            val sig = it.at.toString() + "|" + (if (it.mine) 1 else 0) + "|" + it.text
            if (!seen.add(sig)) continue
            val mid = "arc:" + Wire.hex(Wire.sha(sig.toByteArray()).copyOf(12))
            val state = if (it.mine) 1 else 3
            if (!it.text.startsWith(Marks.MEDIA)) { out.add(Msg(mid, it.text, it.mine, it.at * 1000, state = state)); continue }
            val rec = runCatching { JSONObject(it.text.removePrefix(Marks.MEDIA)) }.getOrNull() ?: continue
            val f = rec.optString("f").ifEmpty { null } ?: continue   // a record without a file's name is not a row (iOS 3056)
            val man = JSONObject().put("k", rec.optString("k")).put("e", f.substringAfterLast('.', ""))
            rec.optString("n").takeIf { n -> n.isNotEmpty() }?.let { n -> man.put("n", n) }
            rec.optString("cap").takeIf { c -> c.isNotEmpty() }?.let { c -> man.put("cap", c) }
            rec.optDouble("d", 0.0).takeIf { d -> d > 0 }?.let { d -> man.put("du", d) }
            val file = File(Media.dir(Book.ctx), f).takeIf { x -> x.isFile }?.path
            out.add(Msg(mid, Marks.MEDIA + man.toString(), it.mine, it.at * 1000, state = state, file = file))
        }
        return out
    }

    /** Read the archive into the feed, off the screen's thread; `only` — the folders a twin's block just reached. */
    fun restoreSoon(only: List<String>? = null) = q.execute { runCatching { restore(only) }.onFailure { Log.w("Montana", "archive_restore " + it.javaClass.simpleName) } }

    /**
     * EVERY FOLDER OPENED UNDER THE SEED (iOS restore 1015-1077): the head gives the conversation back — «s:» re-establishes the pipe,
     * «x:» names it without reviving it, «a:» and a bare name of an older build name it when the book holds it, «n:» is its name; a
     * folder without a head is named by the book's own labels. Rows go only into conversations the feed holds no row of — the feed is
     * the truth, its edits and deletions are never resurrected (iOS 3036-3043); a folder nobody can answer is «Recovered history».
     */
    private fun restore(only: List<String>?) {
        val k = keys() ?: return
        val chatsDir = File(root() ?: return, "Chats")
        val folders = only ?: chatsDir.listFiles()?.filter { it.isDirectory && !it.name.startsWith(".") }?.map { it.name } ?: return
        val book = HashMap<String, String>()
        for (r in Book.refs()) book[label(k, r)] = r
        var chats = 0; var added = 0; var headed = 0; var hs = 0; var ha = 0; var hn = 0; var faces = 0; var gapChats = 0; var gapRows = 0
        for (folder in folders) {
            var ref: String? = null
            var name: String? = null
            var secret: ByteArray? = null
            var closedThere = false
            val items = ArrayList<Item>()
            for (sealed in readLog(File(File(chatsDir, folder), "conversation.mtlog"))) {
                val plain = MtBindings.nativeArchiveOpenBlock(k.hk, k.owner, sealed) ?: continue
                for (r in opened(plain)) {
                    val s = String(r.content, Charsets.UTF_8)
                    if (r.dir == HEAD_DIR) {
                        when {
                            s.startsWith("s:") -> runCatching { Base64.decode(s.drop(2), Base64.DEFAULT) }.getOrNull()?.takeIf { it.size == 32 }?.let { secret = it; hs++ }
                            s.startsWith("x:") -> closedThere = true
                            s.startsWith("a:") -> { ha++; if (ref == null && Book.secret(s.drop(2)) != null) ref = s.drop(2) }
                            s.startsWith("n:") -> { hn++; name = s.drop(2) }
                            ref == null && Book.secret(s) != null -> ref = s   // the head of build 1345: the bare name
                        }
                        continue
                    }
                    if (s.isNotEmpty()) items.add(Item(r.at, r.dir == 0, s))
                }
            }
            secret?.let { sec ->
                ref = if (closedThere) Wire.reference(sec).also { Prefs.setBool("pipeClosed." + it, true) } else Book.establish(sec)
            }
            if (ref == null) ref = book[folder]
            if (items.isEmpty() && ref == null) continue
            if (ref != null) headed++
            val key = ref ?: ("arc:" + folder)
            val feed = Book.chat(key)?.msgs?.toList().orEmpty()
            if (feed.isNotEmpty()) {
                // THE ARCHIVE IS MEASURED AGAINST THE FEED (iOS restoreFromArchive 3008-3035, atom 2b8069c63096): a letter the archive
                // holds and the feed does not is named with its count and its newest moment -- measured here, never inserted (the
                // feed is the truth); a media letter is matched by its second and its side, its record and its row differing in form
                fun sig(at: Long, mine: Boolean, text: String) = at.toString() + "|" + (if (mine) 1 else 0) + "|" + (if (text.startsWith(Marks.MEDIA)) "media" else text)
                val have = feed.mapTo(HashSet()) { sig(it.at / 1000, it.mine, it.text) }
                val seen = HashSet<String>()
                val missing = items.filter { seen.add(sig(it.at, it.mine, it.text)) && sig(it.at, it.mine, it.text) !in have }
                if (missing.isNotEmpty()) {
                    gapChats++; gapRows += missing.size
                    val newest = java.text.SimpleDateFormat("HH:mm", java.util.Locale.ROOT).format(java.util.Date(missing.maxOf { it.at } * 1000))
                    Log.d("Montana", "archive_gap chat=" + key.take(10) + " feed=" + feed.size + " archive=" + items.size + " missing=" + missing.size +
                        " media=" + missing.count { it.text.startsWith(Marks.MEDIA) } + " theirs=" + missing.count { !it.mine } + " newest=" + newest)
                }
                continue
            }
            val built = rows(items)
            if (built.isEmpty()) continue
            val shown = name?.trim()?.takeIf { it.isNotEmpty() } ?: if (ref == null) Book.ctx.getString(R.string.recovered_history) else ""
            Book.open(key, shown, false)
            Book.edit(key) { c ->
                if (c.name.isEmpty() && shown.isNotEmpty()) c.name = shown
                if (c.msgs.isEmpty()) { c.msgs.addAll(built); c.msgs.sortBy { it.at }; c.unread = 0 }
            }
            val r0 = ref
            if (r0 != null && !Book.face(r0).isFile) {
                val base = root()?.path
                if (base != null) MtBindings.nativeArchiveGetMedia(base, folder, FACE, k.mk, k.owner)?.takeIf { it.isNotEmpty() }?.let { Book.face(r0).writeBytes(it); faces++ }
            }
            chats++; added += built.size
        }
        if (0 < gapRows) Log.d("Montana", "archive_gap total chats=" + gapChats + " rows=" + gapRows)
        Log.d("Montana", "archive_restore chats=" + chats + " rows=" + added + " headed=" + headed + " heads=s" + hs + "/a" + ha + "/n" + hn + " faces=" + faces)
    }

    // ── HISTORY ACROSS A PERSON'S OWN DEVICES (iOS 595-769) ──

    /**
     * Every block this device wrote and the twin has not been handed (iOS replicate 721-745): each folder's blocks of this writer from the
     * cursor on, each by its own wire name — the digest a media piece is named by, so the shape of what travels says nothing of what it
     * is — down the channel that stands with the person's own reference; the cursor moves past what the channel took.
     */
    fun replicate() = q.execute {
        val twin = MontanaSeed.twin ?: return@execute
        keys() ?: return@execute
        val wt = MtBindings.nativeWriterTag(device()) ?: return@execute
        val base = root()?.path ?: return@execute
        val cursor = map(PUSHED)
        var sent = 0
        for (chat in File(base, "Chats").listFiles()?.filter { it.isDirectory }?.map { it.name }.orEmpty()) {
            val from = cursor.optLong(chat, 0L)
            val stream = MtBindings.nativeArchiveExport(base, chat, wt, from) ?: continue
            var top = from
            var i = 0
            while (i + 4 <= stream.size) {
                val n = u32(stream, i)
                i += 4
                if (n <= 0 || stream.size < i + n) break
                val sealed = stream.copyOfRange(i, i + n)
                i += n
                val id = MtBindings.nativeArchiveBlockId(sealed)?.takeIf { it.size == 12 } ?: continue
                var seq = 0L
                for (b in 0 until 8) seq = seq or ((id[4 + b].toLong() and 0xff) shl (8 * b))
                if (Channels.sendBlob(twin, Wire.hex(Wire.sha(sealed)), sealed)) { sent++; top = maxOf(top, seq + 1) }
            }
            if (top != from) cursor.put(chat, top)
        }
        keep(PUSHED, cursor)
        if (sent > 0) Log.d("Montana", "history_push blocks=" + sent)
    }

    /**
     * A sealed piece arrived (iOS absorb 750-769): if it opens under this person's history key it is a block of their own history — filed
     * by the core, which drops a block it already holds, into the folder its conversation is filed under, and that folder is read
     * into the feed again. False: the piece belongs to another road and is left untouched.
     */
    fun absorb(sealed: ByteArray): Boolean {
        val k = keys() ?: return false
        val conv = MtBindings.nativeArchivePeekConv(k.hk, k.owner, sealed) ?: return false
        val c = Wire.hex(conv)
        val folder = map(FOLDERS).optString(c).ifEmpty { c }
        val base = root()?.path ?: return false
        val rc = MtBindings.nativeArchiveIngest(base, folder, k.hk, k.owner, sealed)
        if (rc == 1) { Log.d("Montana", "history_rx block filed"); restoreSoon(listOf(folder)) }
        return rc >= 0
    }

    /** No conversation, no trace of it on disk (iOS deleteChatFolder 706-712). */
    fun drop(ref: String) = q.execute {
        val k = keys() ?: return@execute
        val dir = File(File(root() ?: return@execute, "Chats"), label(k, ref))
        dir.deleteRecursively()
    }

    /**
     * THE DOOR OUT SEALS EVERYTHING THE SEED CAN REOPEN (iOS sealForForget 3721-3745; the author's word 07.09: «everything stored locally
     * and restored exactly on leaving without deleting the app»): every conversation's head, name and face into its folder, on disk
     * before the seed leaves; `then` follows on the main thread once the queue is through.
     */
    fun sealForForget(then: () -> Unit) {
        if (MontanaSeed.mnemonic == null) { Log.d("Montana", "forget_seal sealed=0 — no seed at hand"); then(); return }
        val chats = Book.all().filter { Book.secret(it.ref) != null }.map { it.ref to it.name }
        q.execute {
            val k = keys()
            if (k != null) for ((ref, name) in chats) {
                folder(k, ref)
                if (name.isNotBlank()) nameHead(ref, name)
                faceIn(k, ref)
            }
            q.execute { Log.d("Montana", "forget_seal sealed=" + (if (k != null) 1 else 0) + " held=" + chats.size); MainThread.post(then) }
        }
    }
}
