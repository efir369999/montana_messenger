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
    /** A copy was just taken back (iOS restore → montanaArchiveIngested for every folder): its folders are read into the feed now, not at
     *  the next launch; before the first launch reads them all, atLaunch does it. */
    fun afterCopy() { if (launched) restoreSoon() }

    /** This install's sixteen bytes (iOS writerTag16 438-442): local by nature, they part the nonces of one seed's devices. */
    private fun device(): ByteArray = DeviceVault.get(DEVICE)?.takeIf { it.size == 16 }
        ?: (MtBindings.nativeRandom(16) ?: ByteArray(16)).also { DeviceVault.set(DEVICE, it) }

    /** A folder's name (iOS folderLabel 639-644): SHA-256("mt-archive-label" ‖ 0 ‖ hk ‖ 0 ‖ ref)[0..16], thirty-two hex letters. */
    private fun label(k: Keys, ref: String) = Wire.hex(Wire.sha("mt-archive-label".toByteArray(), byteArrayOf(0), k.hk, byteArrayOf(0), ref.toByteArray()).copyOf(16))

    private fun conv(ref: String) = Wire.sha(ref.toByteArray())   // iOS MontanaQueueKeys.sha256(convRef)

    /** The folder a conversation is filed under (iOS labelOnQueue): the map's word for it, else its label; null without the keys. */
    fun folderOf(ref: String): String? = keys()?.let { k -> map(FOLDERS).optString(Wire.hex(conv(ref))).ifEmpty { label(k, ref) } }

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
            if (append(k, ref, folder(k, ref), dir, at, text.toByteArray())) Twin.histSoon()   // the block reaches this seed's other devices through the box (iOS twinSoon)
        }
    }

    /**
     * THE HEAD OF A FOLDER (iOS writeHeadIn 861-880): the pipe's secret when this phone holds it — «s:» and base64, the conversation's name
     * being sixteen bytes of its hash — else the bare name «a:»; written again only when its form changes.
     */
    private fun headIn(k: Keys, ref: String, folder: String) {
        val sec = Book.secret(ref)?.takeIf { Wire.reference(it) == ref }
        // from ERASE_DAY the head carries the floor, never the secret (iOS archiveHead): a form of its own, so it is written once
        // more; a restore walks forward from that floor, so it need not follow the floor's later days
        val form = if (sec == null) "a" else if (Wire.isFloor(sec)) "f" else "s"
        val content = if (sec != null) "s:" + Base64.encodeToString(sec, Base64.NO_WRAP) else "a:" + ref
        val heads = map(HEADS)
        if (heads.optString(folder) == form) return
        keep(HEADS, heads.put(folder, form))
        append(k, ref, folder, HEAD_DIR, System.currentTimeMillis() / 1000, content.toByteArray())
        Log.d("Montana", "archive_head form=" + form)
    }

    /**
     * A pipe was born (iOS MTPipe 432): its folder and its head are written now, before its first letter. And the head again whenever
     * the pipe's form changes (iOS writeHead): the floor's head follows the secret's once, from the day the walk erased it -- the
     * folder already named, headIn alone hears the change (before 551 a floored pipe's folder kept the secret's head).
     */
    fun head(ref: String) = q.execute { keys()?.let { k -> headIn(k, ref, folder(k, ref)) } }

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

    private class Rec(val conv: ByteArray, val dir: Int, val at: Long, val content: ByteArray)
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
            val conv = d.copyOfRange(o, o + 32)
            o += 32
            val dir = d[o].toInt() and 0xff
            o += 1
            var at = 0L
            for (b in 0 until 8) at = at or ((d[o + b].toLong() and 0xff) shl (8 * b))
            o += 8
            val n = u32(d, o)
            o += 4
            if (n < 0 || d.size < o + n) break
            out.add(Rec(conv, dir, at, d.copyOfRange(o, o + n)))
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

    /**
     * THE FOLDERS A COPY LAID TWICE (the builds before 512 filed a copy's blocks under the conversation's hash, not by the map
     * absorb walks): a folder named by a hash the map files under another folder gives its blocks to that folder — the core drops
     * every block it already holds — and leaves only once each block is filed there. A folder holding anything beside its log stays.
     */
    private fun twins(k: Keys, chatsDir: File) {
        val m = map(FOLDERS)
        var healed = 0
        for (d in chatsDir.listFiles()?.filter { it.isDirectory && it.name.length == 64 } ?: return) {
            val to = m.optString(d.name).takeIf { it.isNotEmpty() && it != d.name } ?: continue
            if (!File(chatsDir, to).isDirectory || d.list()?.all { it == "conversation.mtlog" } != true) continue
            val base = root()?.path ?: return
            if (readLog(File(d, "conversation.mtlog")).all { MtBindings.nativeArchiveIngest(base, to, k.hk, k.owner, it) >= 0 }) {
                d.deleteRecursively(); healed++
            }
        }
        if (healed > 0) Log.i("Montana", "archive_twins healed=$healed")
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
        if (only == null) twins(k, chatsDir)
        val folders = only ?: chatsDir.listFiles()?.filter { it.isDirectory && !it.name.startsWith(".") }?.map { it.name } ?: return
        val book = HashMap<String, String>()
        for (r in Book.refs()) book[label(k, r)] = r
        book[label(k, Book.SAVED)] = Book.SAVED   // the room without an address has a folder and no secret (iOS: the book holds it)
        var chats = 0; var added = 0; var headed = 0; var hs = 0; var ha = 0; var hn = 0; var faces = 0; var gapChats = 0; var gapRows = 0
        // THE ROAD BACK FLOORS BY THE LATER DAY (iOS MTPipeBook.recoveryDay, 67332869, decision 188, E): the device's day or the trusted
        // mark M, whichever is later, so a clock behind keeps no secret a node's Date says is past its floor
        val backDay = FloorGuard.recoveryDay()
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
                            s.startsWith("s:") -> runCatching { Base64.decode(s.drop(2), Base64.DEFAULT) }.getOrNull()?.takeIf { Wire.isWhole(it) }?.let { secret = Wire.floored(it, backDay); hs++ }
                            s.startsWith("x:") -> closedThere = true
                            s.startsWith("a:") -> { ha++; val n = s.drop(2); if (ref == null && (Book.secret(n) != null || Book.isLocal(n) || Groups.isKey(n))) ref = n }
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
            // THE LOCAL ROOM'S FOLDER IS NOT A STRANGER'S (build 427 read it as «Recovered history» while its head named a room with no
            // secret): a row of it born so leaves the list -- the folder stays, it is the room's own
            if (ref != null && Book.isLocal(ref!!) && Book.chat("arc:$folder") != null) { Book.discard("arc:$folder"); Log.d("Montana", "archive_heal folder named again") }
            // A GROUP'S FOLDER IS THE GROUP'S (its head is «a:» and the group's key, no pipe's secret): the builds before 470 read it as «Recovered
            // history» at every first launch and laid the group's rows as a second chat -- that one leaves; a group gone from this
            // phone is the group store's word, its archive never brings the chat back
            if (ref != null && Groups.isKey(ref!!)) {
                if (Book.chat("arc:$folder") != null) { Book.discard("arc:$folder"); Log.d("Montana", "archive_heal group folder") }
                if (Book.chat(ref!!) == null) continue
            }
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
                    // THE SEED'S OTHER DEVICE IS ASKED FOR THESE ROWS BY THEIR NAMES (iOS MontanaArchive.askTwin, f376b4ef): it gives back
                    // what it holds, and each lands by its own birth (Twin.takeRow)
                    if (ref != null) Twin.ask(key, missing.map { Triple(it.at, it.mine, rowHash(it.text)) })
                }
                continue
            }
            // AN EMPTIED CONVERSATION STAYS EMPTY (iOS 95294cf8 at 2240): a feed whose letters were deleted here -- by me or by the
            // correspondent's word -- holds graves, and the append-only archive gave every erased letter back at the next launch; an
            // empty feed never deleted from (a chat just named by its head, a twin's history landing) still takes its transcript
            if (Book.chat(key) != null && Book.hasGraves(key)) { Log.d("Montana", "archive_skip chat=" + key.take(10) + " emptied here"); continue }
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
                if (base != null) MtBindings.nativeArchiveGetMedia(base, folder, FACE, k.mk, k.owner)?.takeIf { it.isNotEmpty() }?.let { if (Book.setFace(r0, it)) faces++ }
            }
            chats++; added += built.size
        }
        if (0 < gapRows) Log.d("Montana", "archive_gap total chats=" + gapChats + " rows=" + gapRows)
        Log.d("Montana", "archive_restore chats=" + chats + " rows=" + added + " headed=" + headed + " heads=s" + hs + "/a" + ha + "/n" + hn + " faces=" + faces)
    }

    // ── HISTORY ACROSS A PERSON'S OWN DEVICES (iOS 595-769) ──

    /** The history key, for the pipe only this seed's devices derive (Twin.secret, iOS twinSecret). */
    fun historyKey(): ByteArray? = keys()?.hk
    /** This install's writer tag in hex: a letter of the seed's pipe names the device that laid it (iOS writerTag().montanaHexString). */
    fun writerHex(): String? = MtBindings.nativeWriterTag(device())?.let { Wire.hex(it) }
    /** This device's own name among the seed's devices (iOS E2E.deviceTag): local, never a quantity of the protocol. */
    fun deviceTag(): String = "and-" + Wire.hex(Wire.sha("mt-device-tag".toByteArray(), byteArrayOf(0), device())).take(12)
    /** The archive's key of a row's words, the same on every device of the seed (iOS MontanaArchive.rowHash). */
    fun rowHash(archived: String): String = Wire.hex(Wire.sha(archived.toByteArray()).copyOf(8))

    private const val BOXED = "mt.history.boxed"   // folder → the first block not yet laid for the other devices (iOS boxedKey)
    private const val TWIN_CAP = 8 shl 20           // one letter's file stays small; what is left rides the next round (iOS twinCap)
    /** What the box road gathers for the seed's other devices (iOS layForTwins): length-framed blocks, each folder's top, more left. */
    class Gathered(val blob: ByteArray, val tops: Map<String, Long>, val n: Int, val more: Boolean)
    fun twinBlocks(): Gathered? = q.submit<Gathered?> {
        keys() ?: return@submit null
        val wt = MtBindings.nativeWriterTag(device()) ?: return@submit null
        val base = root()?.path ?: return@submit null
        val cursor = map(BOXED)
        val blob = java.io.ByteArrayOutputStream()
        val tops = HashMap<String, Long>()
        var n = 0; var more = false
        for (chat in File(base, "Chats").listFiles()?.filter { it.isDirectory }?.map { it.name }.orEmpty()) {
            if (TWIN_CAP < blob.size()) { more = true; break }
            val from = cursor.optLong(chat, 0L)
            val stream = MtBindings.nativeArchiveExport(base, chat, wt, from) ?: continue
            var top = from
            var i = 0
            while (i + 4 <= stream.size) {
                val len = u32(stream, i)
                if (len <= 0 || stream.size < i + 4 + len) break
                val sealed = stream.copyOfRange(i + 4, i + 4 + len)
                val id = MtBindings.nativeArchiveBlockId(sealed)?.takeIf { it.size == 12 }
                i += 4 + len
                id ?: continue
                var seq = 0L
                for (b in 0 until 8) seq = seq or ((id[4 + b].toLong() and 0xff) shl (8 * b))
                blob.write(stream, i - 4 - len, 4 + len)
                top = maxOf(top, seq + 1); n++
            }
            if (top != from) tops[chat] = top
        }
        Gathered(blob.toByteArray(), tops, n, more)
    }.get()
    /** The blocks rode: the cursor moves past them (iOS layForTwins, after the knock). */
    fun twinBoxed(tops: Map<String, Long>) = q.execute {
        val cursor = map(BOXED)
        for ((k, v) in tops) cursor.put(k, maxOf(cursor.optLong(k, 0L), v))
        keep(BOXED, cursor)
    }

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
    @Volatile private var refusedAt = 0L
    fun absorb(sealed: ByteArray): Boolean {
        val k = keys() ?: return false
        val conv = MtBindings.nativeArchivePeekConv(k.hk, k.owner, sealed) ?: return false
        val c = Wire.hex(conv)
        // A BLOCK OF A CONVERSATION ERASED HERE IS TAKEN AND NOT FILED (iOS absorb deletedHere, 44f44060; the critic B-4): my other
        // device's blocks, laid before it heard of the deletion, came back by the twin's road and stood the conversation again
        if (Book.erasedHere(c)) {
            val now = System.currentTimeMillis()
            if (now - refusedAt >= 60_000) { refusedAt = now; Log.d("Montana", "archive_refused a block of a deleted conversation is not filed") }
            return true
        }
        // A HEAD WITH THE ESTABLISHED SECRET IS NOT FILED FROM THE FLOOR DAY (iOS absorb, bf55cd1a, decision 191): the twin's copy of an
        // old head would lay the secret under the seed again after this phone's pass took it out (dropSecretHeads)
        if (Book.floorDay() >= Wire.ERASE_DAY && onlySecretHeads(MtBindings.nativeArchiveOpenBlock(k.hk, k.owner, sealed)?.let(::opened) ?: emptyList())) {
            val now = System.currentTimeMillis()
            if (now - refusedAt >= 60_000) { refusedAt = now; Log.d("Montana", "archive_refused a head with the established secret is not filed from the floor day") }
            return true
        }
        val folder = map(FOLDERS).optString(c).ifEmpty { c }
        val base = root()?.path ?: return false
        val rc = synchronized(logLock) { MtBindings.nativeArchiveIngest(base, folder, k.hk, k.owner, sealed) }
        if (rc == 1) { Log.d("Montana", "history_rx block filed"); restoreSoon(listOf(folder)) }
        return rc >= 0
    }

    // ── THE SECRET LEAVES THE ARCHIVE ON THE FLOOR DAY (iOS MontanaArchive.dropSecretHeads, bf55cd1a and 67332869, decision 191) ──
    // Every head written before ERASE_DAY carries the established secret («s:» and its thirty-two bytes), and a folder's log is only
    // ever appended to. From the floor day the archive holds the floor, never the secret: every folder's log is rewritten once without
    // those blocks. A folder whose last secret head has no floor head after it gets the floor of that very head in its place, so the
    // last head still decides at a restore as before; nothing else in the log moves. The twin's copy is cleaned by its own pass, and a
    // secret head it still sends is not filed here (absorb).
    private const val PURGED = "archiveSecretHeadsPurged"   // this seat's archive is through the pass (iOS purgedKey; never a copy's)
    private val logLock = Any()                             // the rewrite against absorb, the one writer off the queue
    @Volatile private var purgeAsked = 0L                   // the floor day this run last asked the pass on: once a day at most

    private fun headPipe(head: String): ByteArray? =
        if (!head.startsWith("s:")) null else runCatching { Base64.decode(head.drop(2), Base64.DEFAULT) }.getOrNull()?.takeIf { Wire.isWhole(it) }
    /** Whether a block is nothing but heads carrying the established secret (iOS MTPipeKey.onlySecretHeads, headHoldsSecret). */
    private fun onlySecretHeads(rs: List<Rec>) =
        rs.isNotEmpty() && rs.all { it.dir == HEAD_DIR && headPipe(String(it.content, Charsets.UTF_8))?.let(Wire::holdsOrigin) == true }

    /** `day`: the day the book floored by (Book.floorDay), from ERASE_DAY. */
    fun dropSecretHeads(day: Long) {
        if (day < Wire.ERASE_DAY || purgeAsked == day) return
        purgeAsked = day
        q.execute { runCatching { dropSecretHeadsIn(day) }.onFailure { Log.w("Montana", "archive_secret_heads " + it.javaClass.simpleName) } }
    }
    /** The seat leaves: the next person's archive is passed again (iOS SeedScope.seatKeys). */
    fun forgetPurge() { purgeAsked = 0L; DeviceVault.delete(PURGED) }

    /** Queue-only: the pass, once per archive from the floor day (again after a seat change brings an older archive). */
    private fun dropSecretHeadsIn(day: Long) {
        if (DeviceVault.has(PURGED)) return
        val k = keys() ?: run { purgeAsked = 0L; return }   // no seed at hand yet: the next read asks again
        val chatsDir = File(root() ?: run { purgeAsked = 0L; return }, "Chats")
        var cut = 0; var floored = 0; var folders = 0; var failed = 0
        for (dir in chatsDir.listFiles()?.filter { it.isDirectory && !it.name.startsWith(".") } ?: emptyList()) {
            val r = synchronized(logLock) { purgeFolder(k, File(dir, "conversation.mtlog"), day) }
            if (r == null) { failed++; continue }
            if (r[0] > 0) { folders++; cut += r[0]; floored += r[1] }
        }
        if (failed == 0) DeviceVault.set(PURGED, day.toString().toByteArray())
        Log.d("Montana", "archive_secret_heads folders=$folders cut=$cut floored=$floored failed=$failed")
    }

    /** One folder's log (queue and logLock): [blocks cut, floor heads laid], or null when it must be passed again at the next start. */
    private fun purgeFolder(k: Keys, log: File, day: Long): IntArray? {
        val data = runCatching { log.readBytes() }.getOrNull() ?: return intArrayOf(0, 0)
        // the frames in file order: (u32 LE length ‖ sealed), as readLog reads them; a torn tail is kept as it lay
        val frames = ArrayList<Pair<ByteArray, List<Rec>>>()
        var i = 0
        while (i + 4 <= data.size) {
            val n = u32(data, i)
            if (n <= 0 || data.size < i + 4 + n) break
            val rs = MtBindings.nativeArchiveOpenBlock(k.hk, k.owner, data.copyOfRange(i + 4, i + 4 + n))?.let(::opened) ?: emptyList()
            frames.add(data.copyOfRange(i, i + 4 + n) to rs)
            i += 4 + n
        }
        val tail = data.copyOfRange(i, data.size)
        // 1 a block of secret heads, 2 one with a floor head, 0 anything else (iOS MTPipeKey.LogFrame, purge)
        val kinds = frames.map { (_, rs) ->
            when {
                onlySecretHeads(rs) -> 1
                rs.any { it.dir == HEAD_DIR && headPipe(String(it.content, Charsets.UTF_8))?.let(Wire::isFloor) == true } -> 2
                else -> 0
            }
        }
        val last = kinds.lastIndexOf(1)
        if (last < 0) return intArrayOf(0, 0)
        var put: ByteArray? = null
        if (2 !in kinds.subList(last + 1, kinds.size)) {
            // the floor head could not be made or laid: the old head stays rather than leave the folder with no head, and the pass
            // is not marked done -- the next start tries again
            val head = frames[last].second.first()
            val floor = headPipe(String(head.content, Charsets.UTF_8))?.let { Wire.floored(it, day) }?.takeIf { Wire.isFloor(it) } ?: return null
            val base = root()?.path ?: return null
            val content = ("s:" + Base64.encodeToString(floor, Base64.NO_WRAP)).toByteArray()
            if (MtBindings.nativeArchiveAppend(base, log.parentFile!!.name, k.hk, k.owner, device(), head.conv, HEAD_DIR, System.currentTimeMillis() / 1000, content) != 0) return null
            // the block just appended is the log's last frame: the queue and the lock let no other writer in between
            val after = runCatching { log.readBytes() }.getOrNull() ?: return null
            if (after.size <= data.size || !after.copyOf(data.size).contentEquals(data)) return null
            put = after.copyOfRange(data.size, after.size)
        }
        val out = java.io.ByteArrayOutputStream(data.size)
        var cut = 0
        frames.forEachIndexed { x, (frame, _) ->
            if (kinds[x] == 1) { cut++; if (x == last) put?.let(out::write) } else out.write(frame)
        }
        out.write(tail)
        val tmp = File(log.parentFile, log.name + ".purge")
        val ok = runCatching { tmp.writeBytes(out.toByteArray()); tmp.renameTo(log) }.getOrDefault(false)
        if (!ok) { tmp.delete(); return null }
        return intArrayOf(cut, if (put != null) 1 else 0)
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
