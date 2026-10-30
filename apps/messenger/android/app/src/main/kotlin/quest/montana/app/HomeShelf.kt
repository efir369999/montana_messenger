package quest.montana.app

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.Future
import javax.net.ssl.HttpsURLConnection

// ── THE FILES ON YOUR NODE (iOS MTHomeShelf / MTHomeBook / MTHomeKeep, 6f24f091) ─────────────────────────────────────────
// The author's word 18.10.2026 20:1x MSK: «make my Lauterbourg node my personal storage for T1, so I clear the cache in the
// app and it weighs nothing, and even after deleting the app I come back and load everything from my own node».
//
// Every file of this phone's media store is sealed by this phone under a key of its own, cut into the pieces the doors
// already carry, and laid on the shelf of the words' token beside the copies (/home-put). Which file is which pieces is THE
// BOOK; it lies on the node as well, sealed under a key the words alone derive and named by a name the words alone derive --
// so the 24 words bring the book back, and the book every file. The node holds what it says it holds (/home-have): a file
// leaves this phone only when the node has just named every one of its pieces, and comes back at a look or a tap.

/** The node's rooms for the pieces, and the keys the words derive for them. */
object HomeShelf {
    private val bookKeyLabel = "mt-home-book-key".toByteArray()     // NOT-UI: the derivation's own label
    private val bookNameLabel = "mt-home-book-name".toByteArray()   // NOT-UI: the book's name on the shelf
    private val fileKeyLabel = "mt-home-file-key".toByteArray()     // NOT-UI: a file's own key
    const val CHUNK = Media.CHUNK

    /** Files go to the node while its copies do (the switch); taking one's own files back asks no switch. */
    fun keeping(c: Context) = MontanaHomeNode.on(c) && bringing
    val bringing: Boolean get() = MontanaHomeNode.host.isNotEmpty() && entropy() != null
    fun entropy(): ByteArray? {
        val m = MontanaSeed.mnemonic ?: return null
        return MtBindings.nativeMnemonicToEntropy(m)?.takeIf { it.size == 32 }
    }
    fun bookKey(e: ByteArray): ByteArray = Hkdf.sha256(e, ByteArray(0), bookKeyLabel)
    fun bookName(e: ByteArray): String = hex(Hkdf.hmac(bookKey(e), bookNameLabel))
    /** A file's key, from the words and the file's name: the same file sealed again gives the same pieces, so a pass cut short
     *  goes on from what the node already holds. */
    fun fileKey(e: ByteArray, name: String): ByteArray = Hkdf.hmac(bookKey(e), fileKeyLabel + name.toByteArray())

    /** THE FROZEN VECTORS (iOS MTHomeShelf.keyKAT: RFC 5869 HKDF-SHA-256 and HMAC-SHA-256 on the counting bytes 0x00..0x1f and
     *  the name img_a1.jpg). A drifted label loses the book of every phone before it. */
    fun keyKAT(): Boolean {
        val counting = ByteArray(32) { it.toByte() }
        return hex(bookKey(counting)) == "9bece1c15302a5154b382514015c9d888be32876f01e00963cecdaf7156bb992"
            && bookName(counting) == "5d536d3dc037f357cc0430d317072ac117cc72efaafcae76d4a9e923edbe28a1"
            && hex(fileKey(counting, "img_a1.jpg")) == "0362e58cd7c26c3fd0735391a2b64c012744647e42bacbe6745d1373d6775901"   // NOT-UI: a vector's name
    }

    // ── the wire ──
    private fun post(path: String, body: JSONObject): Pair<Int, JSONObject>? {
        val tok = MontanaHomeNode.tokenHex() ?: return null
        val b = MontanaHomeNode.base(MontanaHomeNode.host) ?: return null
        return try {
            val c = URL(b + path).openConnection() as HttpURLConnection
            if (c is HttpsURLConnection) NodeTrust.apply(c)
            c.connectTimeout = 15_000; c.readTimeout = 30_000
            c.requestMethod = "POST"; c.doOutput = true
            c.setRequestProperty("content-type", "application/json")
            c.setRequestProperty(MontanaHomeNode.TOKEN_HEADER, tok)
            c.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = c.responseCode
            val j = runCatching { JSONObject((if (code < 400) c.inputStream else c.errorStream).bufferedReader().readText()) }.getOrNull() ?: JSONObject()
            c.disconnect()
            code to j
        } catch (e: Exception) { null }
    }
    fun get(bid: String): ByteArray? {
        val (code, j) = post("/home-get", JSONObject().put("bid", bid)) ?: return null
        if (code != 200) return null
        return j.optString("data").takeIf { it.isNotEmpty() }?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() }
    }
    /** The node's own word on which of these pieces it holds; null when it did not answer. */
    fun have(bids: List<String>): Set<String>? {
        val out = HashSet<String>()
        var at = 0
        while (at < bids.size) {
            val part = bids.subList(at, minOf(at + 4096, bids.size))
            val (code, j) = post("/home-have", JSONObject().put("bids", JSONArray(part))) ?: return null
            val h = j.optJSONArray("have")
            if (code != 200 || h == null) return null
            for (i in 0 until h.length()) out.add(h.optString(i))
            at += part.size
        }
        return out
    }
    /** True only on the node's «held». */
    fun put(bid: String, sealed: ByteArray, over: Boolean = false): Boolean {
        val (code, j) = post("/home-put", JSONObject().put("bid", bid).put("data", Base64.encodeToString(sealed, Base64.NO_WRAP)).put("over", over)) ?: return false
        if (code != 200) Log.i("Montana", "home_put refused code=$code ${j.optString("error")}")
        return code == 200 && j.optBoolean("held")
    }

    // ── the book on the node ──
    fun putBook(e: ByteArray) {
        val plain = HomeBook.json().toByteArray()
        val sealed = Wire.seal(bookKey(e), plain) ?: return
        val ok = put(bookName(e), sealed, over = true)
        Log.i("Montana", "home_book put files=${HomeBook.count} bytes=${sealed.size} held=${if (ok) 1 else 0}")
    }
    fun takeBook(e: ByteArray) {
        val plain = get(bookName(e))?.let { Wire.open(bookKey(e), it) }
        if (plain == null) { Log.i("Montana", "home_book none on your node"); return }
        val n = HomeBook.merge(String(plain, Charsets.UTF_8))
        Log.i("Montana", "home_book taken files=$n")
    }

    // ── a file to the node ──
    /** One piece sealed as a letter seals it (Media.sealPiece): the same bytes under the same key give the same name. */
    private fun piece(raf: RandomAccessFile, i: Int, size: Long, key: ByteArray): Pair<String, ByteArray>? = runCatching {
        val off = i.toLong() * CHUNK
        val len = minOf(CHUNK.toLong(), size - off).toInt()
        val d = ByteArray(len)
        raf.seek(off); raf.readFully(d)
        val padded = d.copyOf(Media.padLen(len))
        val nonce = Wire.sha(key, Wire.le8(i.toLong()), padded).copyOf(12)
        MtBindings.nativeSealBlob(key, nonce, padded)?.let { Wire.hex(Wire.sha(it)) to it }
    }.getOrNull()

    private val lanes = Executors.newFixedThreadPool(3)
    /** Every piece's name first (each sealed once to learn it), the node's word on them, then what it lacks, three at a time. */
    fun keepFile(f: File, e: ByteArray): HomeBook.Entry? {
        val size = f.length()
        if (size <= 0L || Int.MAX_VALUE.toLong() < size) return null
        val key = fileKey(e, f.name)
        val count = ((size + CHUNK - 1) / CHUNK).toInt()
        val bids = ArrayList<String>(count)
        RandomAccessFile(f, "r").use { raf -> for (i in 0 until count) bids.add(piece(raf, i, size, key)?.first ?: return null) }
        val held = have(bids) ?: return null
        val missing = (0 until count).filter { bids[it] !in held }
        val jobs: List<Future<Boolean>> = missing.map { i ->
            lanes.submit<Boolean> {
                val sc = RandomAccessFile(f, "r").use { raf -> piece(raf, i, size, key) }
                sc != null && sc.first == bids[i] && put(sc.first, sc.second)   // a changed name: the file changed under us
            }
        }
        var ok = true
        for (j in jobs) { if (!ok) { j.cancel(false); continue }; if (runCatching { j.get() }.getOrDefault(false) != true) ok = false }
        return if (ok) HomeBook.Entry(size, bids, System.currentTimeMillis() / 1000.0) else null
    }

    /** A file just born may be a pick being laid this moment (iOS MontanaMediaStore.newbornGrace 60 s). */
    private fun newborn(f: File) = System.currentTimeMillis() - f.lastModified() < 60_000
    /** The store's files a pass may take: whole ones, not the unfinished «.part». */
    private fun storeFiles(c: Context): List<File> =
        Media.dir(c).listFiles { f -> f.isFile && !f.name.startsWith(".") && !f.name.endsWith(".part") && !f.name.endsWith(StreamLoader.LEDGER) }?.sortedBy { it.name } ?: emptyList()

    /** THE PASS: every file of the store the book does not name at its size goes to the node; the book follows every
     *  twenty-five files and at the end. The answer is the node's word on the whole book. */
    fun keepPass(c: Context, progress: (Double) -> Unit): HomeKeep.Word {
        val e = entropy() ?: return HomeKeep.Word.Silent("seed")
        HomeBook.ensure()
        if (HomeBook.count == 0) takeBook(e)
        val todo = storeFiles(c).filter { !newborn(it) && 0L < it.length() && HomeBook.entry(it.name)?.z != it.length() }
        val total = maxOf(1L, todo.sumOf { it.length() })
        var done = 0L; var laid = 0; var since = 0; var refused = 0
        Log.i("Montana", "home_keep begin files=${todo.size} bytes=$total kept=${HomeBook.count}")
        for (f in todo) {
            val entry = keepFile(f, e)
            if (entry != null) { HomeBook.set(f.name, entry); laid++; since++ }
            else {
                refused++
                if (3 <= refused && laid == 0) break   // the node does not take anything now: the next pass goes on
            }
            done += f.length()
            progress(done.toDouble() / total)
            if (25 <= since) { HomeBook.save(); putBook(e); since = 0 }
        }
        if (0 < since) { HomeBook.save(); putBook(e) }
        Log.i("Montana", "home_keep end laid=$laid refused=$refused kept=${HomeBook.count}")
        return word()
    }
    /** What the node holds of the book, in its own word, asked now. */
    fun word(): HomeKeep.Word {
        val all = HomeBook.all()
        val held = have(all.values.flatMap { it.p }) ?: return HomeKeep.Word.Silent("no answer")
        val whole = all.filter { it.value.p.all(held::contains) }
        return HomeKeep.Word.Held(whole.size, whole.values.sumOf { it.z }, System.currentTimeMillis())
    }

    /** THE CACHE CLEARED: a file leaves this phone only when the node has just named every one of its pieces. */
    fun clearPass(c: Context): Pair<Int, Long>? = removeHeld(c, null)?.let { it.first.size to it.second }

    /** A FILE LEAVES THIS PHONE ONLY ON THE NODE'S WORD ASKED NOW, whoever asks (iOS MTHomeShelf.removeHeld): the hand's clearing,
     *  and the files the person chose on a kind's page of the copy -- `only` names them, null takes every file. A file the node
     *  does not hold whole stays; no letter is touched. */
    fun removeHeld(c: Context, only: Set<String>?): Pair<Set<String>, Long>? {
        HomeBook.ensure()
        val all = HomeBook.all()
        val inHand = Media.inHand()
        val candidates = storeFiles(c).filter { f ->
            val e = all[f.name]
            e != null && (only?.contains(f.name) ?: true) && f.path !in inHand && !newborn(f) && f.length() == e.z
        }
        val held = have(candidates.flatMap { all.getValue(it.name).p }) ?: return null
        val gone = candidates.filter { f -> all.getValue(f.name).p.all(held::contains) }
        var bytes = 0L
        for (f in gone) { bytes += f.length(); f.delete() }
        Log.i("Montana", "home_clear files=${gone.size} bytes=$bytes of=${candidates.size} kept=${all.size} chosen=${only?.size ?: -1}")
        return gone.map { it.name }.toSet() to bytes
    }

    /**
     * THE CACHE KEEPS ITSELF (iOS MTHomeShelf.trimPass, f5803d8c; the reference's «keep media» and «maximum cache size»): a file the
     * node holds and nobody opened within the person's term leaves this phone, and past the person's ceiling the files opened
     * longest ago leave first -- each only on the node's word asked now, as the hand's clearing. The disk keeps no reading moment
     * here, so a file's moment is its last change (iOS falls back to it too).
     */
    fun trimPass(c: Context, days: Int, limitGB: Int): Pair<Int, Long>? {
        if (days + limitGB <= 0) return 0 to 0L
        HomeBook.ensure()
        val all = HomeBook.all()
        val inHand = Media.inHand()
        class F(val f: File, val at: Long, val size: Long, val kept: Boolean)
        val files = storeFiles(c).filter { it.path !in inHand && !newborn(it) }.map { F(it, it.lastModified(), it.length(), all[it.name]?.z == it.length()) }
        val edge = System.currentTimeMillis() - days * 86_400_000L
        val going = files.filter { it.kept && 0 < days && it.at < edge }.toMutableSet()
        if (0 < limitGB) {
            var total = files.sumOf { it.size } - going.sumOf { it.size }
            val ceiling = limitGB * 1_073_741_824L
            for (f in files.sortedBy { it.at }) {
                if (total <= ceiling) break
                if (!f.kept || f in going) continue
                going.add(f); total -= f.size
            }
        }
        if (going.isEmpty()) return 0 to 0L
        val held = have(going.flatMap { all.getValue(it.f.name).p }) ?: return null
        val gone = going.filter { all.getValue(it.f.name).p.all(held::contains) }
        var bytes = 0L
        for (g in gone) { bytes += g.size; g.f.delete() }
        Log.i("Montana", "home_trim files=${gone.size} bytes=$bytes days=$days limit_gb=$limitGB")
        return gone.size to bytes
    }

    /** A file back from the node into the store: every piece asked of the node alone (Media.download → HomeBook.holds). */
    fun bring(c: Context, name: String, e: HomeBook.Entry): Boolean {
        val en = entropy() ?: return false
        val man = JSONObject().put("bk", Base64.encodeToString(fileKey(en, name), Base64.NO_WRAP)).put("chunks", manifest(e))
        val dest = File(Media.dir(c), name)
        if (!Media.download(man, dest)) {
            Log.i("Montana", "home_bring FAIL name=${name.take(20)} -- your node did not give every piece")
            return false
        }
        Media.Blobs.drop(e.p)
        Log.i("Montana", "home_bring name=${name.take(20)} bytes=${e.z}")
        return true
    }
    fun manifest(e: HomeBook.Entry): JSONArray = JSONArray().apply {
        e.p.forEachIndexed { i, bid -> put(JSONObject().put("bid", bid).put("cs", minOf(CHUNK.toLong(), e.z - i.toLong() * CHUNK).toInt())) }
    }
}

/**
 * THE BOOK (iOS MTHomeBook): each file this phone gave its node, by name -- its size, its pieces in order, and when the node
 * named them all. Its copy on this phone is a cache of the one on the node (HomeShelf.putBook): the words bring it back. ONE
 * BOOK PER PERSON: its file is named by the words, so a second person seated on this phone never reads the first one's book.
 */
object HomeBook {
    class Entry(val z: Long, val p: List<String>, val at: Double) {
        fun json(): JSONObject = JSONObject().put("z", z).put("p", JSONArray(p)).put("at", at)
        companion object {
            fun of(o: JSONObject?): Entry? {
                val a = o?.optJSONArray("p") ?: return null
                return Entry(o.optLong("z"), (0 until a.length()).map { a.optString(it) }, o.optDouble("at", 0.0))
            }
        }
    }
    private val lock = Any()
    private var files: Map<String, Entry> = emptyMap()
    private var bids: Set<String> = emptySet()
    private var tag: String? = null   // the person whose book is in hand
    private fun dir(): File = File(Book.ctx.filesDir, "Montana/HomeBook").apply { mkdirs() }
    private fun file(t: String) = File(dir(), "book-$t.json")   // NOT-UI: the file's own name
    private fun person(): String = HomeShelf.entropy()?.let { HomeShelf.bookName(it).take(16) } ?: ""

    /** The book of the person seated now: read again when the seat changed. */
    fun ensure() {
        val t = person()
        if (synchronized(lock) { t == tag }) return
        val f = if (t.isEmpty()) emptyMap() else runCatching { parse(file(t).readText()) }.getOrDefault(emptyMap())
        synchronized(lock) { tag = t }
        lay(f)
    }
    private fun parse(s: String): Map<String, Entry> {
        val o = JSONObject(s)
        return o.keys().asSequence().mapNotNull { k -> Entry.of(o.optJSONObject(k))?.let { k to it } }.toMap()
    }
    private fun lay(f: Map<String, Entry>) = synchronized(lock) { files = f; bids = f.values.flatMap { it.p }.toHashSet() }
    val count: Int get() { ensure(); return synchronized(lock) { files.size } }
    fun holds(bid: String): Boolean { if (tag == null) ensure(); return synchronized(lock) { bid in bids } }
    fun entry(name: String): Entry? { if (tag == null) ensure(); return synchronized(lock) { files[name] } }
    fun all(): Map<String, Entry> = synchronized(lock) { files }
    /** The names whose every piece the node named: a copy for the node leaves them out (iOS kept, HomeNodeWatch.send). */
    fun kept(): Set<String> { if (tag == null) ensure(); return synchronized(lock) { files.filter { 0 < it.value.at }.keys } }
    fun set(name: String, e: Entry) = synchronized(lock) { files = files + (name to e); bids = bids + e.p }
    fun json(): String = JSONObject().apply { all().forEach { (n, e) -> put(n, e.json()) } }.toString()
    /** The node's book joins this phone's: what either names stays named. */
    fun merge(plain: String): Int {
        val f = runCatching { parse(plain) }.getOrNull() ?: return 0
        val mine = all().toMutableMap()
        for ((n, e) in f) if (n !in mine) mine[n] = e
        lay(mine)
        save()
        return f.size
    }
    fun save() {
        val t = synchronized(lock) { tag } ?: return
        if (t.isEmpty()) return
        runCatching { val tmp = File(dir(), "book-$t.part"); tmp.writeText(json()); tmp.renameTo(file(t)) }
    }
}

/** THE KEEPER ON THIS PHONE (iOS MTHomeKeep): the pass to the node, the cache cleared, a file brought back. Pages listen to it. */
object HomeKeep {
    sealed class Word {
        object Unknown : Word()
        class Held(val files: Int, val bytes: Long, val at: Long) : Word()   // the node's own word on the book
        class Silent(val why: String) : Word()
    }
    @Volatile var sending: Double? = null; private set   // this phone's own count of the pass
    @Volatile var word: Word = Word.Unknown; private set
    @Volatile var clearing = false; private set
    @Volatile private var running = false
    private val bringing = HashSet<String>()
    /** Told on every move; the page that shows the files sets it. */
    @Volatile var onChange: (() -> Unit)? = null
    private fun said() { onChange?.invoke() }
    private fun cellular(c: Context): Boolean {
        val cm = c.getSystemService(android.net.ConnectivityManager::class.java)
        return cm?.getNetworkCapabilities(cm.activeNetwork)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) == true
    }

    /** At launch: the node's book first on a phone that has none, then a pass over Wi-Fi when the copies ride. */
    @Volatile private var launched = false
    fun tickSoon(act: Context) {
        if (launched) return
        launched = true
        val c = act.applicationContext
        Log.i("Montana", "home_shelf kat=${if (HomeShelf.keyKAT()) "ok" else "FAIL"} bringing=${if (HomeShelf.bringing) 1 else 0}")
        if (!HomeShelf.bringing) return
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            Thread {
                HomeBook.ensure()
                if (HomeShelf.keeping(c)) keep(c, cellular = false)
                else if (HomeBook.count == 0) HomeShelf.entropy()?.let { HomeShelf.takeBook(it) }
            }.start()
        }, 20_000)
    }
    fun keep(c: Context, cellular: Boolean) {
        if (!HomeShelf.keeping(c) || running) return
        if (!cellular && cellular(c)) { Log.i("Montana", "home_keep waits for Wi-Fi"); return }
        running = true
        sending = 0.0; said()
        Thread {
            val w = runCatching { HomeShelf.keepPass(c) { f -> sending = f; said() } }.getOrElse { Word.Silent(it.javaClass.simpleName) }
            runCatching { HomeShelf.trimPass(c, keepDays, limitGB) }   // the cache keeps itself after the pass (iOS f5803d8c)
            running = false; sending = null; word = w; said()
        }.start()
    }
    const val KEEP_DAYS = "home.keep.days"     // NOT-UI: the person's term for a file nobody opened; 0 -- for ever
    const val LIMIT = "home.cache.limit"       // NOT-UI: the person's ceiling of the cache in gigabytes; 0 -- none
    val keepDays: Int get() = Prefs.str(KEEP_DAYS, "0").toIntOrNull() ?: 0
    val limitGB: Int get() = Prefs.str(LIMIT, "0").toIntOrNull() ?: 0
    /** The person moved the term or the ceiling: the cache keeps itself now, not at the next pass. */
    fun trim(c: Context) {
        if (!HomeShelf.bringing) return
        Thread { runCatching { HomeShelf.trimPass(c.applicationContext, keepDays, limitGB) } }.start()
    }
    fun ask() {
        if (!HomeShelf.bringing || HomeBook.count == 0) return
        Thread { word = HomeShelf.word(); said() }.start()
    }
    fun clear(c: Context, done: (Pair<Int, Long>?) -> Unit) {
        if (!HomeShelf.bringing || clearing) return done(null)
        clearing = true; said()
        Thread {
            val r = runCatching { HomeShelf.clearPass(c) }.getOrNull()
            clearing = false; said()
            done(r)
        }.start()
    }
    /** A file the book names and this phone no longer holds. */
    fun kept(f: String?): Boolean = f != null && !File(f).exists() && MontanaHomeNode.host.isNotEmpty() && HomeBook.entry(File(f).name) != null
    /** A LOOK BRINGS IT BACK (as the reference does): a file the book names comes from the node when its bubble stands on the
     *  screen and the attachments of this network download by themselves; a tap always. */
    fun want(c: Context, m: Msg) { if (kept(m.file)) bring(c, m, force = false) }
    fun bring(c: Context, m: Msg, force: Boolean) {
        val path = m.file ?: return
        val name = File(path).name
        if (File(path).exists() || !HomeShelf.bringing) return
        val e = HomeBook.entry(name) ?: return
        if (!force && !Media.autoAllowed(c)) return
        if (!synchronized(bringing) { bringing.add(name) }) return
        Thread {
            val ok = runCatching { HomeShelf.bring(c, name, e) }.getOrDefault(false)
            synchronized(bringing) { bringing.remove(name) }
            if (!ok) return@Thread
            // the file stands again where the row names it: the row is told, as a landing tells it (iOS fillMedia)
            val placed = File(Media.dir(c), name)
            if (placed.path != path) placed.renameTo(File(path))
            Book.rooms().firstOrNull { ch -> ch.msgs.any { it.mid == m.mid } }?.ref?.let { ref -> Book.edit(ref) { ch -> ch.msgs.find { it.mid == m.mid }?.file = path } }
        }.start()
    }
}
