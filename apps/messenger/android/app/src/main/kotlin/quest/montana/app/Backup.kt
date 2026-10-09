package quest.montana.app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

// THE COPY IS THE ARCHIVE UNDER ONE MORE SEAL (iOS MontanaBackup, 23.09). This file is its way BACK: a copy made on
// any Montana (an iPhone, or this phone later) is opened with the 24 words and laid into this device. It merges, it
// never erases.
//
// THE CONTAINER, version 2, byte for byte:
//   0  32  salt. No mark of its own: without the words the file is noise.
//  32  ..  frames, every one exactly 1 MiB: ChaChaPoly combined (nonce 12, ciphertext, tag 16)
//   backup_key = HKDF-SHA-256(ikm = entropy 32, salt = salt 32, info = "mt-backup-key-v2", 32)
//   AAD of frame i = the salt, u64 LE i, and u8 1 on the final frame (0 on every other).
//   The frames' plaintexts, joined, are ONE stream of records -- u8 kind, u8 more, u16 LE nameLen, name, u32 LE
//   dataLen, data. Kind 1 a sealed history block, 2 a piece of an archive attachment (folder/blob), 3 the account
//   card, 4 a file of the correspondence store, 5 a file of one of the other places (place/file), 6 a piece of the
//   feed, 0 the tail: the count and the SHA-256 of every record before it.
// Version 1 -- magic "MTBAK" 0x00, version 1, kdf 1, salt 32, chunk size u64; then u32 LE lengths, each before one
// record sealed alone, AAD = that 48-byte header and u64 LE index, info "mt-backup-key-v1" -- is still read.

/** What a copy held — COUNTED here, never promised (iOS MontanaBackup.Tally). */
data class Tally(var chats: Int = 0, var records: Int = 0, var media: Int = 0, var bytes: Int = 0, var skipped: Int = 0)

/** Why a copy did not come back. Every one is spoken to the person (iOS MontanaBackup.Refusal). */
sealed class Refusal {
    object NoSeed : Refusal()
    object NoVault : Refusal()
    object Empty : Refusal()
    object NotOurs : Refusal()
    object Version : Refusal()
    object WrongWords : Refusal()
    object Unopened : Refusal()
    object Torn : Refusal()
    object NoSpace : Refusal()
    object Stopped : Refusal()
    class DiskRefused(val why: String) : Refusal()
    class CloudRefused(val why: String) : Refusal()

    /** One reading for every keeper (iOS Refusal.spoken(by: .node)). */
    fun spoken(c: Context): String = when (this) {
        Empty -> c.getString(R.string.node_empty)
        is CloudRefused -> c.getString(R.string.node_refused, why)
        Stopped -> c.getString(R.string.copy_stopped)
        NoSeed -> c.getString(R.string.copy_no_seed)
        NoVault -> c.getString(R.string.copy_no_vault)
        NoSpace -> c.getString(R.string.copy_no_space)
        is DiskRefused -> c.getString(R.string.copy_disk_refused, why)
        NotOurs -> c.getString(R.string.copy_not_ours)
        Version -> c.getString(R.string.copy_version)
        WrongWords -> c.getString(R.string.copy_wrong_words)
        Unopened -> c.getString(R.string.copy_unopened)
        Torn -> c.getString(R.string.copy_torn)
    }
}

sealed class CopyResult {
    class Taken(val tally: Tally) : CopyResult()
    /** A copy sealed on this phone's shelf, waiting to be handed on. */
    class Made(val file: File, val tally: Tally) : CopyResult()
    class Refused(val why: Refusal) : CopyResult()
}

/** The folders a copy lays into — the iOS names, under this app's own private storage (Documents / Application Support). */
object MontanaPaths {
    fun archive(c: Context) = File(c.filesDir, "Montana")                  // iOS Documents/Montana (archive.rs root)
    fun chats(c: Context) = File(archive(c), "Chats")                      // = archive.rs CHATS_DIR
    private fun support(c: Context) = File(c.filesDir, "Support")          // iOS Application Support
    fun store(c: Context) = File(support(c), "Montana/Media")              // iOS MontanaMediaStore.dir
    /** The person's other places (iOS MontanaBackup.places), each named once. */
    fun places(c: Context): Map<String, File> = mapOf(
        "avatars" to File(support(c), "Avatars"),
        "wallpapers" to File(support(c), "Wallpapers"),
        "stories" to File(c.filesDir, "stories"),
        "pictures" to File(support(c), "Montana/Pictures"))
    /** What came back and has no owner on this phone yet (the card, the feed), sealed under the device key. */
    fun taken(c: Context) = File(c.noBackupFilesDir, "MontanaTaken")
}

object MontanaBackup {
    private const val EXT = "mtbak"                       // NOT-UI: the container's own extension
    private const val CHUNK = 1 shl 20
    private const val FRAME = 1 shl 20
    private const val SALT = 32
    private const val HEADER = 48
    private val magic = byteArrayOf(0x4D, 0x54, 0x42, 0x41, 0x4B, 0x00)
    private val labelV1 = "mt-backup-key-v1".toByteArray()   // NOT-UI: the derivation's own label
    private val labelV2 = "mt-backup-key-v2".toByteArray()   // NOT-UI: the derivation's own label
    private const val KIND_TAIL = 0
    private const val KIND_BLOCK = 1
    private const val KIND_MEDIA = 2
    private const val KIND_CARD = 3
    private const val KIND_STORE = 4
    private const val KIND_PLACE = 5
    private const val KIND_FEED = 6

    /** «Forget this device»: every file of the person's history leaves with the seed (iOS clearData). */
    fun forget(c: Context) {
        // the sealed log of the chats stays (iOS sealForForget): only the words reopen it; the rest of the archive's root goes
        MontanaPaths.archive(c).listFiles()?.filter { it.name != MontanaPaths.chats(c).name }?.forEach { it.deleteRecursively() }
        (listOf(MontanaPaths.store(c), MontanaPaths.taken(c)) + MontanaPaths.places(c).values)
            .forEach { it.deleteRecursively() }
        shelf(c)?.deleteRecursively()
    }

    /** Where a copy waits while it is laid: outside every system backup. */
    fun shelf(c: Context): File? = File(c.noBackupFilesDir, "MontanaBackup").takeIf { it.isDirectory || it.mkdirs() }

    /** A name a copy may write: one plain file, never a path out of its place. */
    fun plainName(n: String) = n.isNotEmpty() && !n.contains('/') && !n.startsWith(".")

    /** The moment a copy was made, read back from its name ("montana-<moment>[-<proof>].mtbak"). */
    fun born(n: String): java.util.Date? {
        if (!n.startsWith("montana-") || !n.endsWith(".$EXT")) return null
        var body = n.removePrefix("montana-").removeSuffix(".$EXT")
        val dash = body.lastIndexOf('-')
        if (dash >= 0) {
            val tail = body.substring(dash + 1)
            if (tail.length == 16 && tail.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }) body = body.substring(0, dash)
        }
        for (f in listOf("yyyy-MM-dd-HHmmss", "yyyy-MM-dd-HHmm")) {
            val fmt = java.text.SimpleDateFormat(f, java.util.Locale.US).apply { isLenient = false }
            val p = java.text.ParsePosition(0)
            val d = fmt.parse(body, p)
            if (d != null && p.index == body.length) return d
        }
        return null
    }

    // ── the seal ──
    private fun key(entropy: ByteArray, salt: ByteArray, label: ByteArray) = Hkdf.sha256(entropy, salt, label)
    private fun le64(v: Long) = ByteArray(8) { (v ushr (8 * it)).toByte() }
    private fun num(b: ByteArray, o: Int, n: Int): Int { var v = 0; for (k in 0 until n) v = v or ((b[o + k].toInt() and 0xff) shl (8 * k)); return v }

    /** ChaChaPoly combined (nonce 12 ‖ ciphertext ‖ tag 16) opened on the platform's own cipher; null when it does not open. */
    private fun open(k: ByteArray, combined: ByteArray, aad: ByteArray): ByteArray? = try {
        Cipher.getInstance("ChaCha20/Poly1305/NoPadding").run {
            init(Cipher.DECRYPT_MODE, SecretKeySpec(k, "ChaCha20"), IvParameterSpec(combined, 0, 12))
            updateAAD(aad)
            doFinal(combined, 12, combined.size - 12)
        }
    } catch (e: javax.crypto.AEADBadTagException) { null } catch (e: java.security.GeneralSecurityException) { null }

    /** THE FROZEN VECTORS OF THE SEAL (iOS MontanaBackup.keyKAT, RFC 5869 computed outside this code). */
    fun keyKAT(): Boolean {
        val counting = ByteArray(32) { it.toByte() }
        val after = ByteArray(32) { (it + 32).toByte() }
        return hex(key(ByteArray(32) { 0x55 }, ByteArray(32), labelV1)) == "bdd50e3824fb05ed88e25d379fa70b2de845cc5de0d27f037d201b39a9fb6792"
            && hex(key(counting, after, labelV1)) == "cb836de01e5c7468cf1b7f8e4c604a1d8ff5af1a2f683e9d9ea091713d04e6dd"
            && hex(key(counting, after, labelV2)) == "ec63f219255c63640c9916705b59e10f71ec3f8a296bb048db4ed08ed4ad48e4"
    }

    // ── making one ──
    private const val PIECE = (1 shl 20) - 4096   // room for a record's own head inside one chunk
    private val ownerLabel = "mt-backup-owner-v1".toByteArray()   // NOT-UI: the derivation's own label

    /** WHOSE COPY IT IS, SAID BY ITS NAME TO ITS OWNER ALONE: sixteen hex of HMAC over its moment, keyed from the words. */
    fun ownerKey(entropy: ByteArray) = Hkdf.sha256(entropy, ByteArray(0), ownerLabel)
    private fun proof(moment: String, k: ByteArray) = hex(Hkdf.hmac(k, moment.toByteArray())).substring(0, 16)
    private fun nameNow(entropy: ByteArray): String {
        val moment = java.text.SimpleDateFormat("yyyy-MM-dd-HHmmss", java.util.Locale.US).format(java.util.Date())
        return "montana-$moment-${proof(moment, ownerKey(entropy))}.$EXT"
    }
    fun ownerKAT() = hex(ownerKey(ByteArray(32) { it.toByte() })) == "a07f0e82f8b0d5a375684f7b23a9e8a5d9015b4207620f869c9c6aa1e28750bc"
        && proof("2026-09-23-143542", ownerKey(ByteArray(32) { it.toByte() })) == "fc4380015be1598a"

    /** The stream of records, cut into frames of one length and sealed (iOS Framer). A full frame waits for the next byte. */
    private class Framer(private val out: java.io.OutputStream, private val k: ByteArray, private val salt: ByteArray) {
        private var index = 0L
        private val hash = MessageDigest.getInstance("SHA-256")
        private val frame = java.io.ByteArrayOutputStream(FRAME - 28)
        fun digestHex(): String = hex(hash.digest())
        fun put(kind: Int, name: String, data: ByteArray, off: Int = 0, len: Int = data.size, more: Boolean = false) {
            val n = name.toByteArray()
            val head = byteArrayOf(kind.toByte(), if (more) 1 else 0, n.size.toByte(), (n.size shr 8).toByte()) + n +
                byteArrayOf(len.toByte(), (len shr 8).toByte(), (len shr 16).toByte(), (len shr 24).toByte())
            if (kind != KIND_TAIL) { hash.update(head); hash.update(data, off, len) }
            feed(head, 0, head.size)
            feed(data, off, len)
        }
        private fun feed(b: ByteArray, off: Int, len: Int) {
            var at = off
            val end = off + len
            while (at < end) {
                if (frame.size() == FRAME - 28) seal(false)
                val take = minOf(FRAME - 28 - frame.size(), end - at)
                frame.write(b, at, take)
                at += take
            }
        }
        /** The final frame: what is left of the stream, then zeros to the frame's full length. */
        fun finish() {
            frame.write(ByteArray(FRAME - 28 - frame.size()))
            seal(true)
        }
        private fun seal(last: Boolean) {
            val nonce = MtBindings.nativeRandom(12) ?: throw java.io.IOException("nonce")
            val c = Cipher.getInstance("ChaCha20/Poly1305/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(k, "ChaCha20"), IvParameterSpec(nonce))
            c.updateAAD(salt + le64(index) + byteArrayOf(if (last) 1 else 0))
            out.write(nonce)
            out.write(c.doFinal(frame.toByteArray()))
            index++
            frame.reset()
        }
    }

    /**
     * A COPY OF EVERYTHING THIS PHONE HOLDS (iOS MontanaBackup.build), in the iOS order: the letters of every
     * conversation and their attachments, the correspondence store, the other places, the feed, the card, the tail.
     * A file that will not read stops the copy: a copy one attachment short that calls itself whole is the shape a
     * person leans on and loses. Runs on the caller's worker thread.
     */
    fun create(c: Context, progress: (Double) -> Unit): CopyResult {
        if (!keyKAT() || !ownerKAT()) return CopyResult.Refused(Refusal.NoVault)
        val mn = MontanaSeed.mnemonic ?: return CopyResult.Refused(Refusal.NoSeed)
        val ent = MtBindings.nativeMnemonicToEntropy(mn)?.takeIf { it.size == 32 } ?: return CopyResult.Refused(Refusal.NoSeed)
        val card = Card.build(c) ?: return CopyResult.Refused(Refusal.NoVault)
        val salt = MtBindings.nativeRandom(32) ?: return CopyResult.Refused(Refusal.DiskRefused("salt"))
        val dir = shelf(c) ?: return CopyResult.Refused(Refusal.DiskRefused("shelf"))
        dir.listFiles()?.forEach { it.delete() }   // a copy of the copy has no business waiting here
        val part = File(dir, java.util.UUID.randomUUID().toString() + ".part")   // NOT-UI: the unfinished name

        // What will be taken, counted from the disk: the bar measures bytes sealed against it.
        val chats = MontanaPaths.chats(c).listFiles { f -> f.isDirectory }?.sortedBy { it.name } ?: emptyList()
        val store = MontanaPaths.store(c).listFiles { f -> f.isFile && !f.name.startsWith(".") }?.sortedBy { it.name } ?: emptyList()
        val placed = MontanaPaths.places(c).flatMap { (place, d) ->
            (d.listFiles { f -> f.isFile && plainName(f.name) }?.sortedBy { it.name } ?: emptyList()).map { place to it }
        }
        val feed = Card.kept(c, "feed")
        var total = 0L
        for (d in chats) {
            total += File(d, "conversation.mtlog").length()
            File(d, "Media").listFiles()?.forEach { total += it.length() }
        }
        store.forEach { total += it.length() }
        placed.forEach { total += it.second.length() }
        total += feed?.size ?: 0
        var sealed = 0L
        var shown = -1
        fun advance(n: Int) {
            sealed += n
            val pct = if (total > 0) minOf(99L, sealed * 100 / total).toInt() else 0
            if (pct != shown) { shown = pct; progress(pct / 100.0) }
        }
        progress(0.0)
        val tally = Tally()
        fun pieces(f: File, kind: Int, name: String, w: Framer) {
            f.inputStream().use { inp ->
                val size = f.length()
                val count = maxOf(1L, (size + PIECE - 1) / PIECE)
                val buf = ByteArray(PIECE)
                for (i in 0 until count) {
                    var got = 0
                    while (got < PIECE) { val r = inp.read(buf, got, PIECE - got); if (r < 0) break; got += r }
                    w.put(kind, name, buf, 0, got, more = i + 1 < count)
                    advance(got)
                }
            }
        }
        try {
            java.io.BufferedOutputStream(FileOutputStream(part), 1 shl 16).use { out ->
                out.write(salt)
                val w = Framer(out, key(ent, salt, labelV2), salt)
                for (d in chats) {
                    var any = false
                    val log = File(d, "conversation.mtlog")
                    if (log.exists()) java.io.DataInputStream(java.io.BufferedInputStream(log.inputStream())).use { inp ->
                        // One sealed block of the log, in the layout the core writes: u32 LE length, then the block.
                        val lenB = ByteArray(4)
                        while (true) {
                            if (inp.read(lenB) != 4) break
                            val len = num(lenB, 0, 4)
                            if (len < 1 || len > 4 shl 20) break
                            val block = ByteArray(len).also { inp.readFully(it) }
                            w.put(KIND_BLOCK, "", block)
                            tally.records++; tally.bytes += len
                            advance(len + 4)
                            any = true
                        }
                    }
                    File(d, "Media").listFiles { f -> f.isFile && !f.name.startsWith(".") }?.sortedBy { it.name }?.forEach { f ->
                        pieces(f, KIND_MEDIA, d.name + "/" + f.name, w)
                        tally.media++; tally.bytes += f.length().toInt()
                        any = true
                    }
                    if (any) tally.chats++
                }
                // The attachments themselves go LAST after every letter: on the other side a file lands after its letter.
                for (f in store) { pieces(f, KIND_STORE, f.name, w); tally.media++; tally.bytes += f.length().toInt() }
                for ((place, f) in placed) { pieces(f, KIND_PLACE, "$place/${f.name}", w); tally.bytes += f.length().toInt() }
                feed?.let { fd ->
                    val count = maxOf(1, (fd.size + PIECE - 1) / PIECE)
                    for (i in 0 until count) {
                        val lo = i * PIECE; val hi = minOf(fd.size, lo + PIECE)
                        w.put(KIND_FEED, "", fd, lo, hi - lo, more = i + 1 < count)
                        advance(hi - lo)
                    }
                }
                if (tally.records + tally.media + card.count < 1) return CopyResult.Refused(Refusal.Empty)
                // THE CARD IS PIECED LIKE AN ATTACHMENT: a face alone makes it larger than one chunk.
                val cd = card.data
                val count = maxOf(1, (cd.size + PIECE - 1) / PIECE)
                for (i in 0 until count) {
                    val lo = i * PIECE; val hi = minOf(cd.size, lo + PIECE)
                    w.put(KIND_CARD, "", cd, lo, hi - lo, more = i + 1 < count)
                }
                val t = JSONObject().put("tally", JSONObject().put("chats", tally.chats).put("records", tally.records)
                    .put("media", tally.media).put("bytes", tally.bytes).put("skipped", tally.skipped)).put("digest", w.digestHex())
                w.put(KIND_TAIL, "", t.toString().toByteArray())
                w.finish()
            }
            val made = File(dir, nameNow(ent))
            if (!part.renameTo(made)) return CopyResult.Refused(Refusal.DiskRefused("move"))
            progress(1.0)
            Log.i("Montana", "backup_made chats=${tally.chats} rec=${tally.records} media=${tally.media} places=${placed.size} card=${card.count} bytes=${tally.bytes}")
            return CopyResult.Made(made, tally)
        } catch (e: Exception) {
            return CopyResult.Refused(if (e.message?.contains("ENOSPC") == true) Refusal.NoSpace else Refusal.DiskRefused("write " + e.javaClass.simpleName))
        } finally {
            part.delete()
            ent.fill(0)
        }
    }

    // ── taking one back ──
    /**
     * A copy is taken back BY THE ROAD A TWIN'S HISTORY TAKES: every block goes through the core's own ingest, which
     * drops a block it already holds. So a restore MERGES, and a second restore costs nothing. The share measures the
     * copy's own frames read and filed. Runs on the caller's worker thread.
     */
    fun restore(c: Context, file: File, progress: (Double) -> Unit): CopyResult {
        if (!keyKAT() || !MontanaHomeNode.keyKAT()) return CopyResult.Refused(Refusal.NoVault)
        val mn = MontanaSeed.mnemonic ?: return CopyResult.Refused(Refusal.NoSeed)
        val ent = MtBindings.nativeMnemonicToEntropy(mn)?.takeIf { it.size == 32 } ?: return CopyResult.Refused(Refusal.NoSeed)
        val taker = Taker.open(c, mn, ent) ?: return CopyResult.Refused(Refusal.NoVault)
        var shown = -1
        val share = { f: Double -> val p = (f.coerceIn(0.0, 1.0) * 100).toInt(); if (p != shown) { shown = p; progress(p / 100.0) } }
        share(0.0)
        return try {
            RandomAccessFile(file, "r").use { fh ->
                val size = fh.length()
                if (size < HEADER) return CopyResult.Refused(Refusal.NotOurs)
                val head = ByteArray(HEADER).also { fh.readFully(it) }
                val r = if (head.copyOfRange(0, 6).contentEquals(magic)) applyV1(fh, head, ent, size, taker, share)
                        else { fh.seek(0); applyV2(fh, size, ent, taker, share) }
                r ?: taker.finish()
            }
        } catch (e: java.io.IOException) {
            CopyResult.Refused(if (e.message?.contains("ENOSPC") == true) Refusal.NoSpace else Refusal.DiskRefused("read " + e.javaClass.simpleName))
        } finally {
            taker.close()
            ent.fill(0)
        }
    }

    /** Version 1, read and never written: one record per chunk, each behind its own length. */
    private fun applyV1(fh: RandomAccessFile, head: ByteArray, ent: ByteArray, size: Long, t: Taker, share: (Double) -> Unit): CopyResult? {
        if (head[6].toInt() != 1 || head[7].toInt() != 1) return CopyResult.Refused(Refusal.Version)
        val k = key(ent, head.copyOfRange(8, 40), labelV1)
        var index = 0L
        val lenB = ByteArray(4)
        while (t.tail == null) {
            if (fh.read(lenB) != 4) break
            val len = num(lenB, 0, 4)
            if (len < 17 || len > CHUNK + 4096) return CopyResult.Refused(Refusal.Torn)   // judged BEFORE a byte of it is read
            val sealed = ByteArray(len)
            if (fh.read(sealed) != len) return CopyResult.Refused(Refusal.Torn)
            // THE FIRST CHUNK IS THE QUESTION «DO THESE WORDS OPEN THIS COPY?»; a later refusal is damage.
            val opened = open(k, sealed, head + le64(index)) ?: return CopyResult.Refused(if (index == 0L) Refusal.WrongWords else Refusal.Torn)
            index++
            t.take(opened)?.let { return CopyResult.Refused(it) }
            if (size > 0) share(fh.filePointer.toDouble() / size)
        }
        return null
    }

    /** Version 2: frames of one length; inside them, one stream of records. */
    private fun applyV2(fh: RandomAccessFile, size: Long, ent: ByteArray, t: Taker, share: (Double) -> Unit): CopyResult? {
        val body = size - SALT
        if (body < FRAME) return CopyResult.Refused(Refusal.NotOurs)
        val salt = ByteArray(SALT).also { fh.readFully(it) }
        val n = (body / FRAME).toInt()
        val whole = body % FRAME == 0L
        fun last(i: Int) = whole && i == n - 1
        fun aad(i: Int, end: Boolean) = salt + le64(i.toLong()) + byteArrayOf(if (end) 1 else 0)
        val k = key(ent, salt, labelV2)
        var stream = ByteArray(0)
        var ended = false
        val f = ByteArray(FRAME)
        for (i in 0 until n) {
            if (ended) return CopyResult.Refused(Refusal.Torn)   // a frame after the tail's frame is not the writer's
            fh.readFully(f)
            val opened = open(k, f, aad(i, last(i))) ?: run {
                // THE FIRST FRAME IS THE QUESTION «DO THESE WORDS OPEN THIS FILE?». One that opens only under the other
                // end-mark belongs to a copy cut at a frame's edge: that is damage, and is named so.
                if (i != 0) return CopyResult.Refused(Refusal.Torn)
                return CopyResult.Refused(if (open(k, f, aad(0, !last(0))) != null) Refusal.Torn else Refusal.Unopened)
            }
            stream += opened
            share((i + 1).toDouble() / n)
            var at = 0
            while (t.tail == null && stream.size - at >= 8) {
                val nl = num(stream, at + 2, 2)
                if (stream.size - at < 8 + nl) break
                val dl = num(stream, at + 4 + nl, 4)
                if (dl < 0 || dl > CHUNK + 4096) return CopyResult.Refused(Refusal.Torn)
                val len = 8 + nl + dl
                if (stream.size - at < len) break
                t.take(stream.copyOfRange(at, at + len))?.let { return CopyResult.Refused(it) }
                at += len
            }
            if (t.tail != null) {
                // What follows the tail is the final frame's padding, and nothing else.
                ended = true
                for (j in at until stream.size) if (stream[j].toInt() != 0) return CopyResult.Refused(Refusal.Torn)
                stream = ByteArray(0)
            } else {
                stream = stream.copyOfRange(at, stream.size)
            }
        }
        if (!ended || !whole) return CopyResult.Refused(Refusal.Torn)
        return null
    }

    /** A COPY HANDED BACK, RECORD BY RECORD — one reading for both shapes of the container. */
    private class Taker(private val c: Context, private val hk: ByteArray, private val owner: ByteArray) {
        val hash: MessageDigest = MessageDigest.getInstance("SHA-256")
        val tally = Tally()
        var card: ByteArray? = null
        var feed: ByteArray? = null
        var tail: JSONObject? = null
        var placed = 0
        private var sink: FileOutputStream? = null
        private var dropping = false
        private val root = MontanaPaths.archive(c)

        companion object {
            /** The history key and the owner branch of the seed, both from the core (iOS MontanaArchive.keys). */
            fun open(c: Context, mn: String, ent: ByteArray): Taker? {
                val hk = MtBindings.nativeHistoryKey(ent) ?: return null
                val master = MtBindings.nativeMnemonicToMasterSeed(mn) ?: return null
                val owner = MtBindings.nativeRoleSeed(master, "mt-owner-key")
                master.fill(0)
                return owner?.let { Taker(c, hk, it) }
            }
        }

        fun close() { runCatching { sink?.close() }; sink = null; hk.fill(0); owner.fill(0) }

        /** One whole record: null once it is filed, or the refusal that stops the copy. */
        fun take(p: ByteArray): Refusal? {
            if (p.size < 8) return Refusal.Torn
            val kind = p[0].toInt() and 0xff
            val more = p[1].toInt() == 1
            val nl = num(p, 2, 2)
            if (p.size < 8 + nl) return Refusal.Torn
            val name = String(p, 4, nl, Charsets.UTF_8)
            val dl = num(p, 4 + nl, 4)
            if (p.size != 8 + nl + dl) return Refusal.Torn
            val data = p.copyOfRange(8 + nl, 8 + nl + dl)
            if (kind != KIND_TAIL) hash.update(p)
            when (kind) {
                KIND_BLOCK -> { absorb(data); tally.records++ }
                KIND_MEDIA, KIND_STORE, KIND_PLACE -> {
                    if (dropping) { if (!more) dropping = false; return null }
                    if (sink == null) {
                        val dst = destination(kind, name) ?: return null
                        // An attachment already here is never overwritten: a copy adds, it does not erase.
                        if (dst.exists()) { dropping = more; return null }
                        try {
                            dst.parentFile?.mkdirs()
                            sink = FileOutputStream(dst)
                        } catch (e: java.io.IOException) { return Refusal.DiskRefused("media " + e.javaClass.simpleName) }
                        if (kind == KIND_PLACE) placed++ else tally.media++
                    }
                    try { sink?.write(data) } catch (e: java.io.IOException) {
                        close()
                        return if (e.message?.contains("ENOSPC") == true) Refusal.NoSpace else Refusal.DiskRefused("write")
                    }
                    if (!more) { runCatching { sink?.close() }; sink = null }
                }
                KIND_CARD -> card = (card ?: ByteArray(0)) + data
                KIND_FEED -> feed = (feed ?: ByteArray(0)) + data
                KIND_TAIL -> tail = runCatching { JSONObject(String(data, Charsets.UTF_8)) }.getOrNull() ?: return Refusal.Torn
                else -> {}   // a kind this build does not know is buried in silence
            }
            return null
        }

        /** Where a file of the copy goes: the place a letter looks for it, one plain file, never a path out. */
        private fun destination(kind: Int, name: String): File? = when (kind) {
            KIND_STORE -> File(MontanaPaths.store(c), sanitize(name))
            KIND_PLACE -> {
                val parts = name.split('/', limit = 2)
                val dir = MontanaPaths.places(c)[parts[0]]
                if (parts.size == 2 && dir != null && plainName(parts[1])) File(dir, parts[1]) else null
            }
            else -> {
                val parts = name.split('/')
                if (parts.size == 2) File(File(File(MontanaPaths.chats(c), sanitize(parts[0])), "Media"), sanitize(parts[1])) else null
            }
        }

        /** A sealed block of history: filed by the core's own ingest if it opens under this person's history key. */
        private fun absorb(sealed: ByteArray) {
            val conv = MtBindings.nativeArchivePeekConv(hk, owner, sealed) ?: return
            // A folder's name comes with the card; before it, the conversation's own id names it, as on iOS.
            MtBindings.nativeArchiveIngest(root.path, hex(conv), hk, owner, sealed)
        }

        /** The copy has been read to its end: it is whole only if its tail meets the stream it closes. */
        fun finish(): CopyResult {
            val t = tail
            if (t == null || hex(hash.digest()) != t.optString("digest")) {
                Log.i("Montana", "backup_torn rec=${tally.records} media=${tally.media}")
                return CopyResult.Refused(Refusal.Torn)
            }
            // The card and the feed are laid only once the whole copy has proved itself.
            if (card != null && !Card.lay(c, card!!)) return CopyResult.Refused(Refusal.NoVault)
            feed?.let { if (!Card.keep(c, "feed", it)) return CopyResult.Refused(Refusal.NoVault) }
            tally.chats = MontanaPaths.chats(c).listFiles { f -> f.isDirectory }?.size ?: 0
            tally.skipped = t.optJSONObject("tally")?.optInt("skipped") ?: 0
            Log.i("Montana", "backup_taken rec=${tally.records} media=${tally.media} places=$placed chats=${tally.chats} card=${if (card != null) 1 else 0} feed=${feed?.size ?: 0}")
            return CopyResult.Taken(tally)
        }
    }

    /** iOS MontanaArchive.sanitizeName: no separators, no leading or trailing dots. */
    fun sanitize(n: String): String {
        val t = n.map { if (it in "/\\:\u0000") '_' else it }.joinToString("").trim().trim('.')
        return if (t.isEmpty()) "_" else t
    }
}

/**
 * THE ACCOUNT CARD a copy carries (iOS MontanaBackup.seedCard 782-819, layCard 875-925 at 2155): one JSON map of word to word,
 * every value under the iPhone's own key and tag — «d:» a sealed value opened, «b:» bytes, «s:» a word, «n:» a number, «a:» a
 * list of words, «p:» a property list — so one card lays on both phones. Every fact this phone has an owner for travels both
 * ways in the iPhone's own
 * form (the names: SeedScope, MontanaChatStore.swift 6117-6229); a key it has no owner for travels as the card last taken back
 * holds it, and that card stays the base of every card made here. Laid by the iPhone's rule (SeedScope.unionKeys 6303-6312): a
 * collection keeps what stands here and takes what it lacks — a copy adds a block, a pin or a name and lifts none; every other
 * value is the copy's.
 */
object Card {
    class Built(val data: ByteArray, val count: Int)

    /**
     * How this phone keeps a setting, against the iPhone's tag for it (iOS seedCard 796-803): a number there is a switch here, a
     * whole number, a fraction or a number kept as a word; a word is a word; a list of words is one word per line.
     */
    private enum class Form(val tag: String) { SWITCH("n:"), WHOLE("n:"), FRACTION("n:"), WHOLE_WORD("n:"), FRACTION_WORD("n:"), WORD("s:"), LINES("a:") }

    /**
     * THE SETTINGS KEPT HERE UNDER THE IPHONE'S OWN NAMES (iOS SeedScope.dataKeys 6122, settingKeys 6206-6218), each in the form
     * its owner keeps it on this phone.
     */
    private val settings: Map<String, Form> = linkedMapOf(
        // the notifications (MontanaSettings.swift 278-281), the downloads (1186-1187), privacy (1717-1720; MontanaConversation.swift
        // 310-313), the terms (MontanaSafety.swift 22-25)
        "notifSound" to Form.SWITCH, "notifPreview" to Form.SWITCH, "notifSender" to Form.SWITCH, "notifLockName" to Form.SWITCH,
        "autoDownloadCellular" to Form.SWITCH, "autoDownloadWiFi" to Form.SWITCH,
        "presenceSharing" to Form.SWITCH, "readReceiptsEnabled" to Form.SWITCH, "liveTypingEnabled" to Form.SWITCH,
        "linkPreviewsEnabled" to Form.SWITCH, "objectionableFilterOn" to Form.SWITCH, "termsAcceptedVersion" to Form.WHOLE,
        // the bubbles (MontanaSettings.swift 951-967, BT ContentView.swift 74-75): the colours words, the rest fractions; the classic
        // bubble's colour a whole number there (MontanaBubble.swift 277), a fraction in this phone's store
        "bubbleStyle" to Form.WORD,
        "cbMineFill1" to Form.WORD, "cbMineFill2" to Form.WORD, "cbMineOpacity" to Form.FRACTION, "cbMineText" to Form.WORD,
        "cbMineOutline" to Form.WORD, "cbMineOutlineOp" to Form.FRACTION, "cbMineOutlineW" to Form.FRACTION,
        "cbPeerFill1" to Form.WORD, "cbPeerFill2" to Form.WORD, "cbPeerOpacity" to Form.FRACTION, "cbPeerText" to Form.WORD,
        "cbPeerOutline" to Form.WORD, "cbPeerOutlineOp" to Form.FRACTION, "cbPeerOutlineW" to Form.FRACTION,
        "bubbleColorIndex" to Form.FRACTION,
        // the feed's motion (MontanaChatMotion.swift 6-9), the note (MontanaFeeds.swift 1718, 1783-1808), the voice (MontanaMedia.swift 324-326)
        "chatSpringBounce" to Form.FRACTION, "chatSpringDuration" to Form.FRACTION,
        "noteQuality" to Form.WORD, "vnoteCorner" to Form.WHOLE_WORD, "voiceRate" to Form.FRACTION_WORD,
        // the field (MontanaBubble.swift 2361-2362, MontanaConversation.swift 661), the panes (ContentView.swift 226-227, 4296;
        // MontanaChatsList.swift 454), the mesh switch (MontanaNetworkView.swift 123), the daily copies to one's own node
        // (MontanaHomeNode.swift 23, 39-40)
        "composeOpen" to Form.SWITCH, "composeMediaMode" to Form.WORD, "lastMediaPane" to Form.WORD, "cardKind" to Form.WORD,
        "timePanelOpen" to Form.SWITCH, Mesh.KEY to Form.SWITCH, "mt.home.node.on" to Form.SWITCH,
        // the wall's rules (MontanaBoard.swift 44-49, 64-77): the rule a word, the people a list
        "boardRule" to Form.WORD, "boardSight" to Form.WORD,
        "boardAllow" to Form.LINES, "boardDeny" to Form.LINES, "boardSightAllow" to Form.LINES, "boardSightDeny" to Form.LINES,
        // the posts already named to their walls as seen (MontanaBoard.swift 1186-1203: a list of «wall#post», the copy's word)
        "board.viewed" to Form.LINES,
        // the person's own words (MontanaProfile.swift 623-625)
        "userName" to Form.WORD, "profileBio" to Form.WORD, "profileLink" to Form.WORD)

    /**
     * What a correspondent said of themselves, kept per conversation (iOS SeedScope.dataPrefixes 6170-6171): hiding the exact
     * moment (MontanaConversation.swift 318-327), reading the page's ground (MontanaE2E.swift 782-786), saying «played» (796-799).
     */
    private val flags = listOf("phide_", "pgcap_", "plcap_")
    /**
     * A moment kept per conversation (iOS SeedScope.dataPrefixes 6170, 6175): when a correspondent last said whether they hide the exact
     * moment (MontanaConversation.swift 322-325), and the birth of a pair's first coin letter that names itself (MTWalletCore.swift
     * 2575-2578) — a mark against a copied letter, it moves no coin. The iPhone keeps seconds, this phone milliseconds: the card says seconds.
     */
    private val moments = listOf("phideAt_", "coinBinds.")
    /** The tag of a correspondent's page ground I hold and the moment they said it, «tag@at» on both phones (iOS MontanaFeeds.swift 390-396). */
    private const val HELD = "pgHeld."
    private const val MIRRORED = "copy.mirrored"   // NOT-UI: the paths of the links the last copy laid, one a line
    private const val NODE = "mt.home.node"           // NOT-UI: iOS MontanaHomeNode.hostKey, sealed
    private const val NODE_PIN = "mt.home.node.pin"   // NOT-UI: iOS MontanaHomeNode.pinKey, sealed

    /**
     * The card a copy made HERE carries: the card last taken back, every value this phone owns written over it in the iPhone's
     * form. An entry this phone owns and no longer holds leaves the card: a copy never brings back what was undone here.
     */
    fun build(c: Context): Built? {
        // THE LINKS THIS COPY LAYS ARE NAMED, SO THE NEXT COPY TAKES BACK WHAT IS NO LONGER WORN (the conductor 09.10, absolute
        // privacy): a ground changed or a sticker taken away never rides a later copy; a file an iPhone's copy brought is not ours to take
        val laid = HashSet<String>()
        fun keepMirror(src: File, dir: File): Boolean = mirror(src, dir).also { if (it) laid.add(File(dir, src.name).path) }
        val out = kept(c, "card")?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() ?: return null } ?: JSONObject()
        val prefs = c.getSharedPreferences("mt.defaults", Context.MODE_PRIVATE)
        for ((k, form) in settings) {
            out.remove(form.tag + k)
            if (prefs.contains(k)) runCatching { said(prefs, k, form) }.getOrNull()?.let { out.put(form.tag + k, it) }
        }
        for (t in tagged(out, "n:") { k -> flags.any { k.startsWith(it) } }) out.remove(t)
        for (p in flags) for (k in Prefs.keys(p)) runCatching { prefs.getBoolean(k, false) }.getOrNull()?.let { out.put("n:$k", if (it) "1" else "0") }
        // The moments said per conversation, in the iPhone's seconds (iOS notePeerHides, MontanaConversation.swift 322-325; MTCoinSend.credits,
        // MTWalletCore.swift 2575-2578), and the page ground of theirs I hold, «tag@at» on both phones (iOS MTPageGround.held 390-396)
        for (t in tagged(out, "n:") { k -> moments.any { k.startsWith(it) } }) out.remove(t)
        for (p in moments) for (k in Prefs.keys(p)) Prefs.str(k, "").toLongOrNull()?.takeIf { it > 0 }?.let { out.put("n:$k", secs(it)) }
        for (t in tagged(out, "s:") { it.startsWith(HELD) }) out.remove(t)
        for (k in Prefs.keys(HELD)) Prefs.str(k, "").takeIf { it.isNotEmpty() }?.let { out.put("s:$k", it) }
        // Every ground — a chat's, my page's, a correspondent's page's — under the iPhone's key (iOS MTWallpaper, MontanaFeeds.swift 156-194);
        // a ground on a picture with its file in the copy's place of grounds, where the iPhone keeps its pictures (MontanaBackup.places).
        // A card's ground this phone could not wear stays as the card holds it.
        val walls = MontanaPaths.places(c).getValue("wallpapers")
        val grounds = Prefs.keys("chatWall.")
        val held = grounds.map { groundKey(it) }.toSet()
        for (t in tagged(out, "s:") { k -> k.startsWith("chatWall.") && (k in held || wearable(groundRef(k), out.optString("s:$k"), walls) != null) }) out.remove(t)
        for (k in grounds) {
            val v = Prefs.str(k, "")
            val w = wearable(k.removePrefix("chatWall."), v, ChatWall.folder()) ?: continue
            if (w !is ChatWall.Choice.Photo || keepMirror(File(ChatWall.folder(), w.file), walls)) out.put("s:" + groundKey(k), v)
        }
        // The list's marks, the blocked, the verified and the barred (iOS 6120-6121, 6131-6132, 6209): sealed lists, lists of words
        for ((k, list) in ChatMarks.carried()) out.put("d:$k", b64(JSONArray(list).toString()))
        out.put("d:blockedChats", b64(JSONArray(PeerSafety.blocked()).toString()))
        out.put("a:mtVerifiedConversations", b64(JSONArray(PeerSafety.verified()).toString()))
        out.remove("a:barredPeers")
        PeerSafety.barred().takeIf { it.isNotEmpty() }?.let { out.put("a:barredPeers", b64(JSONArray(it).toString())) }
        // The words left unsent in every chat (iOS ChatStore.draftsAll 740-744: one sealed map by conversation)
        val drafts = JSONObject()
        for (k in Prefs.keys("draft.")) {
            val ref = k.removePrefix("draft.")
            if (ref != "savedMessages") Prefs.str(k, "").takeIf { it.isNotEmpty() }?.let { drafts.put(ref, it) }
        }
        out.put("d:draftsMap", b64(drafts.toString()))
        // The names my hand set (iOS MTNameBook 26-55): a person with a row here has this phone's word, one without keeps the card's
        val names = (strings(out.optString("d:manualNames")) ?: emptyMap()).toMutableMap()
        for ((ref, pin) in Book.pins()) if (pin == null) names.remove(ref) else names.put(ref, pin)
        if (names.isEmpty()) out.remove("d:manualNames") else out.put("d:manualNames", b64(JSONObject(names).toString()))
        // The faces my hand set (iOS MTNameBook 133-157): the card's, while the picture still stands here
        strings(out.optString("d:manualPhotos"))?.let { m ->
            val held = m.filterKeys { MontanaBackup.plainName(it) && Book.myFace(it).exists() }
            if (held.isEmpty()) out.remove("d:manualPhotos") else out.put("d:manualPhotos", b64(JSONObject(held).toString()))
        }
        // One's own node and its certificate's digest (iOS MontanaHomeNode.swift 22-48), the business card (MontanaProfile.swift
        // 113-136), the face as the iPhone carries it (avatarData: the bytes as they are)
        for ((k, v) in listOf(NODE to MontanaHomeNode.host, NODE_PIN to MontanaHomeNode.pin)) if (v.isEmpty()) out.remove("d:$k") else out.put("d:$k", b64(v))
        BusinessCard.stored()?.let { out.put("d:businessCard", b64(it.json().toString())) } ?: out.remove("d:businessCard")
        SelfFace.bytes(c)?.let { out.put("b:avatarData", android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP)) } ?: out.remove("b:avatarData")
        // The records sealed in the same JSON on both phones (iOS SeedScope.dataKeys 6132-6133): the peers' read marks (ChatStore
        // notePeerRead 2872-2879), the name held in the network (MontanaNames.swift 113-132), the permanent link, its keys and the
        // day's cards (MontanaFirstContact.swift 626-868)
        val records = listOf("peerReadMap" to Post.PeerRead.carried(), "mt.name" to Names.record()) +
            MontanaCard.RECORDS.map { it to MontanaCard.record(it) }
        for ((k, v) in records) if (v == null) out.remove("d:$k") else out.put("d:$k", b64(v))
        // What each correspondent said of themselves (iOS MTPeerAbout, MontanaE2E.swift 74-125: one sealed map of conversation to bio,
        // link and moment) and the daily links they handed us with their births (MTPeerLinks 45-68: two sealed maps by conversation)
        PeerAbout.all().takeIf { it.isNotEmpty() }?.let { m ->
            out.put("d:peerAbout", b64(JSONObject().apply { for ((r, a) in m) put(r, JSONObject().put("bio", a.bio).put("link", a.link).put("at", a.at)) }.toString()))
        } ?: out.remove("d:peerAbout")
        val (links, born) = PeerLinks.carried()
        if (links.isEmpty()) { out.remove("d:peerRdvLinks"); out.remove("d:peerRdvLinks.b") }
        else { out.put("d:peerRdvLinks", b64(JSONObject(links).toString())); out.put("d:peerRdvLinks.b", b64(JSONObject(born).toString())) }
        // The people kept as contacts (iOS ContactsTabView.MTContact, ContentView.swift 2430-2436; addToContacts, MontanaPeerInfo.swift
        // 414-431: one sealed JSON list): the card's record of a person still kept here, and one for every other person kept here, named
        // by my hand's name as the iPhone's book mirrors it (MTNameBook.syncContact 320-331), the moment of the adding unknown here
        val people = PeerContact.all().toSet()
        val contacts = JSONArray()
        val listed = HashSet<String>()
        array(out.optString("d:mtContacts"))?.let { a ->
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                if (o.optString("address") in people && listed.add(o.optString("address"))) contacts.put(o)
            }
        }
        val hand = Book.pins()
        for (r in people) if (listed.add(r)) {
            val n = hand[r].orEmpty().trim()
            contacts.put(JSONObject().put("firstName", n.substringBefore(' ')).put("lastName", n.substringAfter(' ', "").trim())
                .put("address", r).put("username", "").put("addedAt", 0.0))
        }
        if (contacts.length() == 0) out.remove("d:mtContacts") else out.put("d:mtContacts", b64(contacts.toString()))
        // The letters waiting for their moment (iOS ScheduledMsg 31-37, saveScheduled 3237-3241) and the card's notes to oneself still to
        // come — a note to oneself has no room here (Scheduled waits for a chat), so it travels as the card holds it
        val waiting = Scheduled.carried()
        array(out.optString("d:scheduledMsgs"))?.let { a ->
            val now = System.currentTimeMillis() / 1000.0
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                if ((o.isNull("convRef") || o.optString("convRef").isEmpty()) && now < o.optDouble("fireAt", 0.0)) waiting.put(o)
            }
        }
        if (waiting.length() == 0) out.remove("d:scheduledMsgs") else out.put("d:scheduledMsgs", b64(waiting.toString()))
        // The letters pinned in every chat (iOS ChatStore.savePinned 3232-3236: one sealed map of chat to letters)
        MsgPins.carried().takeIf { it.isNotEmpty() }?.let { m ->
            out.put("d:pinnedMessages", b64(JSONObject().apply { for ((r, l) in m) put(r, JSONArray(l)) }.toString()))
        } ?: out.remove("d:pinnedMessages")
        // My own stickers (iOS MontanaStickerBook, MontanaSticker.swift 128, 171-173: names over the media store), each picture laid in
        // the copy's store, where the iPhone looks for it
        val store = MontanaPaths.store(c)
        val stickers = Stickers.names(c).filter { keepMirror(Stickers.file(c, it), store) }
        if (stickers.isEmpty()) out.remove("a:montana.stickers.mine") else out.put("a:montana.stickers.mine", b64(JSONArray(stickers).toString()))
        // The answers counted (iOS MTReactions, MontanaMessageMenu.swift 94-100: a map of answer to count, a property list on the card)
        QuickReactions.counts().takeIf { it.isNotEmpty() }?.let { out.put("p:reactionUse", b64(plist(it))) } ?: out.remove("p:reactionUse")
        // The moment the calls page was last seen (iOS ChatStore.loadCallsSeenAt 593-603: a sealed word of seconds)
        CallsSeen.kept()?.let { out.put("d:callsSeenAt", b64(secs(it))) } ?: out.remove("d:callsSeenAt")
        val before = Prefs.str(MIRRORED, "").split('\n').filter { it.isNotEmpty() }
        for (path in before) if (path !in laid) runCatching { File(path).delete() }
        Prefs.setStr(MIRRORED, laid.joinToString("\n"))
        return Built(out.toString().toByteArray(), out.length())
    }

    /**
     * A card taken back (iOS layCard 875-925): every value this phone owns goes to its owner in this phone's form — a setting as
     * the copy says it, a collection as a union — and the whole card is kept for the owners still to come.
     */
    fun lay(c: Context, raw: ByteArray): Boolean {
        val map = runCatching { JSONObject(String(raw, Charsets.UTF_8)) }.getOrNull() ?: return false
        val prefs = c.getSharedPreferences("mt.defaults", Context.MODE_PRIVATE)
        val edit = prefs.edit()
        val marks = HashMap<String, List<String>>()
        val grounds = ArrayList<Pair<String, String>>()
        var blocked: List<String>? = null
        var verified: List<String>? = null
        var barred: List<String>? = null
        var names: Map<String, String>? = null
        var faces: Map<String, String>? = null
        var node: String? = null
        var nodePin: String? = null
        var card: JSONObject? = null
        var face: ByteArray? = null
        var mesh: Boolean? = null
        var readMarks: Map<String, Long>? = null
        var nameRecord: ByteArray? = null
        val cards = HashMap<String, ByteArray>()
        var about: Map<String, PeerAbout.About>? = null
        var links: Map<String, String>? = null
        var born: Map<String, Double>? = null
        var contacts: List<String>? = null
        var waiting: JSONArray? = null
        var pins: Map<String, List<String>>? = null
        var stickers: List<String>? = null
        var reactions: Map<String, Int>? = null
        var callsSeen: Long? = null
        var laid = 0
        fun one(tagged: String) {
            val tag = tagged.take(2)
            val k = tagged.drop(2)
            val v = map.optString(tagged)
            val form = settings[k]
            when {
                // the switch acts the moment it is set, by its owner's own road (iOS SeedScope.reread 6359-6363)
                k == Mesh.KEY -> if (tag == "n:") mesh = (v.toDoubleOrNull() ?: 0.0) != 0.0
                form != null -> if (tag == form.tag && put(edit, k, form, v)) laid++
                tag == "n:" && flags.any { k.startsWith(it) } -> { edit.putBoolean(k, (v.toDoubleOrNull() ?: 0.0) != 0.0); laid++ }
                tag == "n:" && moments.any { k.startsWith(it) } -> ms(v)?.let { edit.putString(k, it.toString()); laid++ }
                tag == "s:" && k.startsWith(HELD) -> { edit.putString(k, v); laid++ }
                tag == "s:" && k.startsWith("chatWall.") -> grounds.add(groundRef(k) to v)
                tag == "d:" && k in ChatMarks.NAMES -> words(v)?.let { marks[k] = it }
                tag == "d:" && k == "blockedChats" -> blocked = words(v)
                tag == "a:" && k == "mtVerifiedConversations" -> verified = words(v)
                tag == "a:" && k == "barredPeers" -> barred = words(v)
                // a union (iOS SeedScope.unionKeys 6304): the words this phone already holds for a chat stay
                tag == "d:" && k == "draftsMap" -> strings(v)?.forEach { (ref, text) ->
                    if (text.isNotEmpty() && prefs.getString("draft.$ref", null).isNullOrEmpty()) { edit.putString("draft.$ref", text); laid++ }
                }
                tag == "d:" && k == "manualNames" -> names = strings(v)
                tag == "d:" && k == "manualPhotos" -> faces = strings(v)
                tag == "d:" && k == NODE -> node = unb64(v)?.toString(Charsets.UTF_8)
                tag == "d:" && k == NODE_PIN -> nodePin = unb64(v)?.toString(Charsets.UTF_8)
                tag == "d:" && k == "businessCard" -> card = unb64(v)?.let { JSONObject(it.toString(Charsets.UTF_8)) }
                tag == "b:" && k == "avatarData" -> face = unb64(v)
                tag == "d:" && k == "peerReadMap" -> readMarks = json(v)?.let { o -> o.keys().asSequence().associateWith { o.getLong(it) } }
                tag == "d:" && k == "mt.name" -> nameRecord = unb64(v)
                tag == "d:" && k in MontanaCard.RECORDS -> unb64(v)?.let { cards[k] = it }
                tag == "d:" && k == "peerAbout" -> about = json(v)?.let { o ->
                    o.keys().asSequence().associateWith { r -> o.getJSONObject(r).let { a -> PeerAbout.About(a.getString("bio"), a.getString("link"), a.getDouble("at")) } }
                }
                tag == "d:" && k == "peerRdvLinks" -> links = strings(v)
                tag == "d:" && k == "peerRdvLinks.b" -> born = json(v)?.let { o -> o.keys().asSequence().associateWith { o.getDouble(it) } }
                tag == "d:" && k == "mtContacts" -> contacts = array(v)?.let { a -> List(a.length()) { a.optJSONObject(it)?.optString("address").orEmpty() } }
                tag == "d:" && k == "scheduledMsgs" -> waiting = array(v)
                tag == "d:" && k == "pinnedMessages" -> pins = json(v)?.let { o ->
                    o.keys().asSequence().associateWith { r -> o.getJSONArray(r).let { a -> List(a.length()) { a.getString(it) } } }
                }
                tag == "a:" && k == "montana.stickers.mine" -> stickers = words(v)
                tag == "p:" && k == "reactionUse" -> reactions = unb64(v)?.let { counts(it) }
                tag == "d:" && k == "callsSeenAt" -> callsSeen = unb64(v)?.let { ms(String(it, Charsets.UTF_8)) }
            }
        }
        for (tagged in map.keys()) runCatching { one(tagged) }
        edit.commit()
        // The owners take theirs by their own doors, each on its own: one refusing leaves the others laid.
        val avatars = MontanaPaths.places(c)["avatars"]
        val walls = MontanaPaths.places(c).getValue("wallpapers")
        listOf<() -> Unit>(
            { if (marks.isNotEmpty()) ChatMarks.lay(marks) },
            { blocked?.let { PeerSafety.layBlocked(it) } },
            { verified?.let { PeerSafety.layVerified(it) } },
            { barred?.let { b -> val have = PeerSafety.barred(); PeerSafety.setBarred(have + b.filter { it !in have }) } },
            { names?.let { Book.layPins(it) } },
            { faces?.forEach { (ref, file) -> if (avatars != null && MontanaBackup.plainName(ref) && MontanaBackup.plainName(file)) Book.layMyFace(ref, File(avatars, file)) } },
            { for ((ref, v) in grounds) wearable(ref, v, walls)?.let { w -> if (w !is ChatWall.Choice.Photo || mirror(File(walls, w.file), ChatWall.folder())) ChatWall.set(ref, w) } },
            { node?.let { MontanaHomeNode.setHost(it) } },
            { nodePin?.let { MontanaHomeNode.setPin(it) } },
            { card?.let { BusinessCard(it.optString("name"), it.optString("phone"), it.optString("email"), it.optString("other")).keep() } },
            { face?.let { SelfFace.set(c, it) } },
            { mesh?.let { if (it != Mesh.discoverable) Mesh.setDiscoverable(it) } },
            { readMarks?.let { Post.PeerRead.lay(it) } },
            { nameRecord?.let { Names.lay(it) } },
            { for ((k, d) in cards) MontanaCard.lay(k, d) },
            { about?.let { PeerAbout.lay(it) } },
            { links?.let { PeerLinks.lay(it, born ?: emptyMap()) } },
            { contacts?.forEach { if (it.isNotEmpty()) PeerContact.keep(it) } },
            { waiting?.let { Scheduled.lay(it) } },
            { pins?.let { MsgPins.lay(it) } },
            { stickers?.let { Stickers.lay(c, it, MontanaPaths.store(c)) } },
            { reactions?.let { QuickReactions.lay(it) } },
            { callsSeen?.let { CallsSeen.lay(it) } }
        ).forEach { runCatching(it) }
        Log.i("Montana", "card laid values=$laid marks=${marks.size} grounds=${grounds.size} of ${map.length()}")
        return keep(c, "card", raw)
    }

    /** This phone's value in the iPhone's form (iOS seedCard 796-803): a number by its digits, a list as JSON in base64. */
    private fun said(p: SharedPreferences, k: String, f: Form): String? = when (f) {
        Form.SWITCH -> if (p.getBoolean(k, false)) "1" else "0"
        Form.WHOLE -> p.getInt(k, 0).toString()
        Form.FRACTION -> p.getFloat(k, 0f).takeIf { it.isFinite() }?.toString()
        Form.WHOLE_WORD -> p.getString(k, null)?.toDoubleOrNull()?.toInt()?.toString()
        Form.FRACTION_WORD -> p.getString(k, null)?.toFloatOrNull()?.takeIf { it.isFinite() }?.toString()
        Form.WORD -> p.getString(k, null)
        Form.LINES -> p.getString(k, null)?.let { s -> b64(JSONArray(s.split('\n').filter { it.isNotEmpty() }).toString()) }
    }

    /** The copy's value in this phone's form (iOS layCard 896-902: a number read as a double, an unreadable one as zero). */
    private fun put(e: SharedPreferences.Editor, k: String, f: Form, v: String): Boolean {
        val n = v.toDoubleOrNull() ?: 0.0
        when (f) {
            Form.SWITCH -> e.putBoolean(k, n != 0.0)
            Form.WHOLE -> e.putInt(k, n.toInt())
            Form.FRACTION -> e.putFloat(k, n.toFloat().takeIf { it.isFinite() } ?: return false)
            Form.WHOLE_WORD -> e.putString(k, n.toInt().toString())
            Form.FRACTION_WORD -> e.putString(k, (n.toFloat().takeIf { it.isFinite() } ?: return false).toString())
            Form.WORD -> e.putString(k, v)
            Form.LINES -> e.putString(k, (words(v) ?: return false).filter { it.isNotEmpty() }.joinToString("\n"))
        }
        return true
    }

    /** The card's entries under one tag whose key passes, taken out before any of them is removed. */
    private fun tagged(o: JSONObject, tag: String, take: (String) -> Boolean): List<String> =
        o.keys().asSequence().filter { it.startsWith(tag) && take(it.substring(2)) }.toList()
    /** A ground's key on the card (iOS MTWallpaper.page, pageKey — MontanaFeeds.swift 160-170): mine «page», a correspondent's page «page.» and them; this phone keeps them under ChatWall.PAGE and PageGround.keyOf. */
    private fun groundKey(mine: String): String {
        val r = mine.removePrefix("chatWall.")
        val peer = PageGround.keyOf("")
        return "chatWall." + when {
            r == ChatWall.PAGE -> "page"
            r.startsWith(peer) -> "page." + r.removePrefix(peer)
            else -> r
        }
    }
    /** The ref this phone keeps a card's ground under: the way back. */
    private fun groundRef(k: String): String {
        val r = k.removePrefix("chatWall.")
        return when {
            r == "page" -> ChatWall.PAGE
            r.startsWith("page.") -> PageGround.keyOf(r.removePrefix("page."))
            else -> r
        }
    }
    /** A ground's word this phone wears (iOS MTWallpaper.parse 173-178, set 190-194): a drawn name it draws, a picture standing in [dir], my page's «general». */
    private fun wearable(ref: String, v: String, dir: File): ChatWall.Choice? = when {
        v.startsWith("photo:") -> v.removePrefix("photo:").takeIf { MontanaBackup.plainName(it) && File(dir, it).isFile }?.let { ChatWall.Choice.Photo(it) }
        v == "general" && ref == ChatWall.PAGE -> ChatWall.Choice.General
        else -> drawn(v)?.let { ChatWall.Choice.Named(it) }
    }
    /** A ground by a drawn name this phone draws too (iOS MTWallpaper.parse 173-178); null for a picture or a name unknown here. */
    private fun drawn(v: String): String? = v.removePrefix("named:").takeIf { v.startsWith("named:") && ChatWall.names.any { n -> n.first == it } }
    private fun b64(s: String) = b64(s.toByteArray(Charsets.UTF_8))
    private fun b64(b: ByteArray): String = android.util.Base64.encodeToString(b, android.util.Base64.NO_WRAP)
    private fun unb64(s: String): ByteArray? = runCatching { android.util.Base64.decode(s, android.util.Base64.DEFAULT) }.getOrNull()
    /** A list of words as the iPhone writes it: JSON in base64 (iOS seedCard 790-801). */
    private fun words(s: String): List<String>? = unb64(s)?.let { b ->
        runCatching { JSONArray(String(b, Charsets.UTF_8)).let { a -> List(a.length()) { a.getString(it) } } }.getOrNull()
    }
    /** A map of words to words, the same way (iOS seedCard 802-803; draftsMap, manualNames, manualPhotos). */
    private fun strings(s: String): Map<String, String>? = unb64(s)?.let { b ->
        runCatching { JSONObject(String(b, Charsets.UTF_8)).let { o -> o.keys().asSequence().associateWith { o.getString(it) } } }.getOrNull()
    }

    /** A sealed value the iPhone writes as JSON (iOS seedCard 790-792): an object, or a list. */
    private fun json(s: String): JSONObject? = unb64(s)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() }
    private fun array(s: String): JSONArray? = unb64(s)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() }
    /** A moment of this phone, milliseconds, as the iPhone keeps it: seconds, written out whole (read there as a Double, layCard 897). */
    private fun secs(ms: Long): String = java.math.BigDecimal.valueOf(ms, 3).stripTrailingZeros().toPlainString()
    /** The iPhone's seconds, in whatever form a number is written, as this phone's milliseconds. */
    private fun ms(v: String): Long? = v.trim().toBigDecimalOrNull()?.movePointRight(3)?.toLong()
    /** A file laid into another place under its own name — linked, or copied where a link is refused — never over one standing there. */
    private fun mirror(src: File, dir: File): Boolean {
        val dst = File(dir, src.name)
        if (dst.isFile) return true
        if (!src.isFile || !(dir.isDirectory || dir.mkdirs())) return false
        return runCatching { android.system.Os.link(src.path, dst.path) }.recoverCatching { src.copyTo(dst); Unit }.isSuccess
    }
    /**
     * A map of answers to counts out of a property list (iOS seedCard 804-805 «p:», layCard 908-913): the binary form an iPhone writes,
     * or the XML this phone writes. Only what the card needs is read — one dictionary of words to whole numbers.
     */
    private fun counts(b: ByteArray): Map<String, Int>? = runCatching {
        if (b.size < 40 || String(b, 0, 8, Charsets.US_ASCII) != "bplist00")
            return@runCatching Regex("""<key>(.*?)</key>\s*<integer>(-?\d+)</integer>""").findAll(String(b, Charsets.UTF_8))
                .associate { unxml(it.groupValues[1]) to it.groupValues[2].toInt() }
        fun be(o: Int, n: Int): Long { var v = 0L; for (k in 0 until n) v = (v shl 8) or (b[o + k].toLong() and 0xff); return v }
        // the trailer: the offsets' width, the references' width, the top object, where the offsets stand
        val t = b.size - 32
        val width = b[t + 6].toInt() and 0xff
        val refWidth = b[t + 7].toInt() and 0xff
        val table = be(t + 24, 8).toInt()
        fun at(i: Long) = be(table + i.toInt() * width, width).toInt()
        fun head(o: Int): Pair<Int, Int> {   // an object's count and where its body begins
            val low = b[o].toInt() and 0x0f
            if (low != 0x0f) return low to o + 1
            val n = 1 shl (b[o + 1].toInt() and 0x0f)
            return be(o + 2, n).toInt() to o + 2 + n
        }
        val dict = at(be(t + 16, 8))
        require((b[dict].toInt() and 0xf0) == 0xd0)
        val (n, body) = head(dict)
        (0 until n).associate { i ->
            val ko = at(be(body + i * refWidth, refWidth))
            val vo = at(be(body + (n + i) * refWidth, refWidth))
            val (kl, ks) = head(ko)
            val key = when (b[ko].toInt() and 0xf0) {
                0x50 -> String(b, ks, kl, Charsets.US_ASCII)
                0x60 -> String(b, ks, kl * 2, Charsets.UTF_16BE)
                else -> error("a key that is not a word")
            }
            require((b[vo].toInt() and 0xf0) == 0x10)
            key to be(vo + 1, 1 shl (b[vo].toInt() and 0x0f)).toInt()
        }
    }.getOrNull()
    /** The same map as the XML property list (iOS layCard 908-913: PropertyListSerialization reads either form). */
    private fun plist(m: Map<String, Int>): String = buildString {
        append("""<?xml version="1.0" encoding="UTF-8"?>""").append('\n')
        append("""<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">""").append('\n')
        append("""<plist version="1.0"><dict>""")
        for ((k, v) in m) append("<key>").append(xml(k)).append("</key><integer>").append(v).append("</integer>")
        append("</dict></plist>")
    }
    private fun xml(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    private fun unxml(s: String) = s.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")

    /** What a copy handed back and this phone keeps sealed; null when nothing is kept or the device key refuses. */
    fun kept(c: Context, name: String): ByteArray? =
        File(MontanaPaths.taken(c), name).takeIf { it.isFile }?.let { DeviceVault.unseal(it.readBytes()) }

    /** A part of the copy with no owner here yet, sealed under the device key (iOS: the vault's own seal). */
    fun keep(c: Context, name: String, raw: ByteArray): Boolean {
        val dir = MontanaPaths.taken(c).apply { mkdirs() }
        val sealed = DeviceVault.seal(raw) ?: return false
        return runCatching { File(dir, name).writeBytes(sealed) }.isSuccess
    }
}
