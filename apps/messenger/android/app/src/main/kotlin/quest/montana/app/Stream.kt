package quest.montana.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.ProxyFileDescriptorCallback
import android.os.storage.StorageManager
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile

/**
 * ONE FILE'S LOADER (iOS MTStreamLoader, MontanaStream.swift): the pieces a letter's manifest names are laid where they belong in
 * «name.part» as they come, in any order, and «name.have» keeps one byte per piece, 1 where the piece lies -- so a player that
 * reads from the first pieces and a download that goes through them in turn share every piece, and a file that stopped half-way
 * goes on from what it already laid. When the last piece lies, the part becomes the file under its name and the waiters are told.
 */
class StreamLoader(val dest: File, private val key: ByteArray, private val bids: List<String>, private val sizes: List<Int>) {
    val count = bids.size
    val size: Long = sizes.fold(0L) { a, n -> a + n }
    private val starts = LongArray(count).also { st -> var off = 0L; for (i in 0 until count) { st[i] = off; off += sizes[i] } }
    private val part = File(dest.path + PART)
    private val ledger = File(dest.path + LEDGER)
    private val have: ByteArray
    private val locks = Array(count) { Any() }
    @Volatile private var body: File = part
    @Volatile var whole = false; private set
    private val onWhole = ArrayList<() -> Unit>()

    init {
        val led = runCatching { ledger.readBytes() }.getOrNull()
        when {
            dest.exists() -> { have = ByteArray(count) { 1 }; body = dest; whole = true }
            // a play that stopped half-way: what it brought is still here
            led != null && led.size == count && part.exists() -> have = led
            else -> {
                have = ByteArray(count)
                runCatching { RandomAccessFile(part, "rw").use { it.setLength(size) }; ledger.writeBytes(have) }
            }
        }
        Log.d("Montana", "stream_open name=" + dest.name.take(20) + " bytes=" + size + " pieces=" + count + " laid=" + have.count { it == 1.toByte() })
    }

    /** Its bytes still lie where it reads them: the file when whole, the part while it is laid. */
    fun stands() = body.exists()

    /** Told once the file is whole (at once when it already is). */
    fun whenWhole(f: () -> Unit) {
        val now = synchronized(onWhole) { if (!whole) onWhole.add(f); whole }
        if (now) f()
    }

    /** Piece [i] of the file: from the part when it lies there, else brought now (one bring per piece, whoever asks). */
    fun piece(i: Int): ByteArray? {
        if (have[i] == 1.toByte()) read(i)?.let { return it }
        synchronized(locks[i]) {
            if (have[i] == 1.toByte()) read(i)?.let { return it }
            val t0 = System.currentTimeMillis()
            val plain = Media.bring(bids[i], key, sizes[i])
            if (plain == null) { Log.i("Montana", "stream_piece FAIL i=" + i + " of " + count + " name=" + dest.name.take(20)); return null }
            val all = synchronized(this) {
                runCatching { RandomAccessFile(part, "rw").use { it.seek(starts[i]); it.write(plain) } }.getOrElse { return plain }
                have[i] = 1
                runCatching { ledger.writeBytes(have) }
                have.all { it == 1.toByte() }
            }
            Log.d("Montana", "stream_piece i=" + i + " of " + count + " ms=" + (System.currentTimeMillis() - t0) + " name=" + dest.name.take(20))
            if (all) becomeWhole()
            return plain
        }
    }

    private fun read(i: Int): ByteArray? = runCatching {
        RandomAccessFile(body, "r").use { f -> ByteArray(sizes[i]).also { f.seek(starts[i]); f.readFully(it) } }
    }.getOrNull()

    private fun becomeWhole() {
        synchronized(this) {
            if (whole) return
            if (dest.exists()) part.delete() else if (!part.renameTo(dest)) return
            ledger.delete()
            body = dest
        }
        val told = synchronized(onWhole) { whole = true; ArrayList(onWhole).also { onWhole.clear() } }
        Log.d("Montana", "stream_whole name=" + dest.name.take(20) + " bytes=" + size + " pieces=" + count)
        for (f in told) runCatching { f() }
    }

    /** The bytes at [offset] for a reader, as many as lie in one piece and fit [size]; 0 at the end, -1 a piece that did not come. */
    fun read(offset: Long, size: Int, into: ByteArray): Int {
        if (offset >= this.size) return 0
        var lo = 0; var hi = count - 1
        while (lo < hi) { val mid = (lo + hi + 1) / 2; if (starts[mid] <= offset) lo = mid else hi = mid - 1 }
        // THE PLAYER IS A FEW SECONDS AHEAD (iOS: the player's own buffered requests on MTCargoLane, width 3): the next pieces
        // are asked for while this one is read
        for (n in lo + 1..minOf(count - 1, lo + AHEAD)) if (have[n] != 1.toByte()) Streams.ahead(this, n)
        val p = piece(lo) ?: return -1
        val from = (offset - starts[lo]).toInt()
        val take = minOf(size, p.size - from)
        if (take <= 0) return -1
        System.arraycopy(p, from, into, 0, take)
        return take
    }

    companion object {
        const val PART = ".part"
        const val LEDGER = ".have"
        private const val AHEAD = 2
    }
}

/**
 * THE FILES BEING READ FROM THEIR FIRST PIECES (iOS MTStreams): one loader per file for the app's life, shared by the download
 * and the player; the last 32 are kept. A film not yet whole opens at once on its loader through the app's own door
 * (MediaProvider, «stream/NAME»): the platform's proxy descriptor asks the loader for bytes as the player reads them.
 */
object Streams {
    private const val KEPT = 32
    private val loaders = object : LinkedHashMap<String, StreamLoader>(16, 0.75f, true) {
        override fun removeEldestEntry(e: MutableMap.MutableEntry<String, StreamLoader>) = KEPT < size
    }
    private val aheadPool = java.util.concurrent.Executors.newFixedThreadPool(3)
    private val asked = HashSet<String>()

    /** The loader of [dest] by its manifest {bk, chunks:[{bid, cs}]}, or null for a manifest without pieces. */
    fun loader(dest: File, man: JSONObject): StreamLoader? {
        // a loader whose bytes the cache took meanwhile is born again: the file is brought anew
        synchronized(loaders) { loaders[dest.path]?.let { if (it.stands()) return it else loaders.remove(dest.path) } }
        val bk = runCatching { Base64.decode(man.getString("bk"), Base64.DEFAULT) }.getOrNull() ?: return null
        val a = man.optJSONArray("chunks") ?: return null
        val bids = ArrayList<String>(); val sizes = ArrayList<Int>()
        for (i in 0 until a.length()) {
            val ch = a.optJSONObject(i) ?: return null
            bids.add(ch.optString("bid").ifEmpty { return null }); sizes.add(ch.optInt("cs").takeIf { it > 0 } ?: return null)
        }
        if (bids.isEmpty()) return null
        val born = StreamLoader(dest, bk, bids, sizes)
        synchronized(loaders) { return loaders.getOrPut(dest.path) { born } }
    }

    /** A piece asked ahead of the player, once at a time. */
    fun ahead(l: StreamLoader, i: Int) {
        val k = l.dest.path + "#" + i
        synchronized(asked) { if (!asked.add(k)) return }
        aheadPool.execute { try { l.piece(i) } finally { synchronized(asked) { asked.remove(k) } } }
    }

    /**
     * A FILM PLAYS FROM ITS FIRST PIECES (iOS onTapVideo → store.stream(forFile:) → VideoPresenter.present(stream:)): a letter's
     * film not yet on the phone, its manifest in hand, opens in the player at once; the file, whole, lands as the download's
     * would (Media.landed). False -- no manifest with pieces in hand, the tap takes the download's road.
     */
    fun play(act: MainActivity, m: Msg): Boolean {
        val man = Media.manifestOf(m) ?: return false
        if (man.optString("k") != "vid") return false
        val ref = Book.rooms().firstOrNull { ch -> ch.msgs.any { it.mid == m.mid } }?.ref ?: return false
        val dest = Media.file(act, m.mid, man.optString("e"))
        val l = loader(dest, man) ?: return false
        val app = act.applicationContext
        l.whenWhole { Media.landed(app, ref, m.mid, man, dest, own = m.mine) }
        Log.d("Montana", "film_stream mid=" + m.mid.take(8) + " pieces=" + l.count + " whole=" + l.whole)
        if (l.whole) { FilmActivity.open(act, dest); return true }
        FilmActivity.openStream(act, Uri.parse("content://${act.packageName}.media/stream/${dest.name}"), dest)
        return true
    }

    /** The descriptor the app's door hands the player for «stream/NAME»: reads ask the loader, piece by piece. */
    fun descriptor(c: Context, name: String): ParcelFileDescriptor? {
        val l = synchronized(loaders) { loaders.values.firstOrNull { it.dest.name == name } } ?: return null
        val t = HandlerThread("montana.stream").apply { start() }
        return runCatching {
            c.getSystemService(StorageManager::class.java).openProxyFileDescriptor(ParcelFileDescriptor.MODE_READ_ONLY, object : ProxyFileDescriptorCallback() {
                override fun onGetSize() = l.size
                override fun onRead(offset: Long, size: Int, data: ByteArray): Int {
                    var at = offset; var got = 0
                    val buf = ByteArray(size)
                    while (got < size) {
                        val n = l.read(at, size - got, buf)
                        if (n < 0) { if (got > 0) break; throw ErrnoException("onRead", OsConstants.EIO) }
                        if (n == 0) break
                        System.arraycopy(buf, 0, data, got, n)
                        got += n; at += n
                    }
                    return got
                }
                override fun onRelease() { t.quitSafely() }
            }, Handler(t.looper))
        }.onFailure { t.quitSafely(); Log.w("Montana", "stream descriptor: " + it.javaClass.simpleName) }.getOrNull()
    }
}
