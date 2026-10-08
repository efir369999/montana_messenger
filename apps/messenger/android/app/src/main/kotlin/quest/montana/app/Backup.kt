package quest.montana.app

import android.content.Context
import android.util.Log
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
 * THE ACCOUNT CARD a copy carries (iOS MontanaBackup.layCard): the person's settings and records, each tagged by the
 * store it lived in on iOS. This phone lays what it already has an owner for — the plain words its own settings read
 * (the name among them) — and never over a value already here; the whole card is kept sealed under the device key for
 * the owners still to come (the chats, their names and choices).
 */
object Card {
    /** The words this phone's own settings read, by the iOS names: they travel as the iOS card carries them. */
    private val ownWords = listOf("userName")

    class Built(val data: ByteArray, val count: Int)

    /**
     * The card a copy made HERE carries: every entry of the card last taken back (what this phone keeps for the owners
     * to come), with this phone's own values over it — the name, and the face as the iOS card carries it (avatarData).
     */
    fun build(c: Context): Built? {
        val out = kept(c, "card")?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() ?: return null } ?: JSONObject()
        val prefs = c.getSharedPreferences("mt.defaults", Context.MODE_PRIVATE)
        for (k in ownWords) prefs.getString(k, null)?.takeIf { it.isNotEmpty() }?.let { out.put("s:$k", it) }
        val face = File(c.filesDir, "avatar.jpg")
        if (face.isFile) out.put("b:avatarData", android.util.Base64.encodeToString(face.readBytes(), android.util.Base64.NO_WRAP))
        return Built(out.toString().toByteArray(), out.length())
    }

    fun lay(c: Context, raw: ByteArray): Boolean {
        val map = runCatching { JSONObject(String(raw, Charsets.UTF_8)) }.getOrNull() ?: return false
        val prefs = c.getSharedPreferences("mt.defaults", Context.MODE_PRIVATE)
        val edit = prefs.edit()
        var laid = 0
        for (tagged in map.keys()) {
            if (!tagged.startsWith("s:")) continue
            val k = tagged.substring(2)
            if (prefs.contains(k)) continue
            edit.putString(k, map.optString(tagged)); laid++
        }
        edit.commit()
        // The face as the iOS card carries it: laid only where this phone has none.
        val face = File(c.filesDir, "avatar.jpg")
        if (!face.exists()) map.optString("b:avatarData").takeIf { it.isNotEmpty() }?.let {
            runCatching { face.writeBytes(android.util.Base64.decode(it, android.util.Base64.NO_WRAP)); laid++ }
        }
        Log.i("Montana", "card laid words=$laid of ${map.length()}")
        return keep(c, "card", raw)
    }

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
