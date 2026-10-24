package quest.montana.app

import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

// THE COPY KEPT BY THE PEOPLE ONE WRITES TO (iOS MTKeeping.swift, the author's words 08.10.2026: «restore by the words fully,
// byte for byte», «restore over the network from the phones, as it should be»; Network «A copy kept by the people one speaks
// with», Canon «The keeping of a copy»). The copy MontanaBackup seals under the words is cut by the erasure code of a delivery;
// the keeper at slot k -- a correspondent whose person allows keeping -- holds cell p of every group for which p mod n = k,
// beside the head of its share, the seal of that head under a branch of the words it never sees, and the secret of its slot.
// A phone that opens the words derives the secret of every slot, calls in each pipe, checks every seal and builds the copy
// back. Every road here is one a letter already rides: the keeping words ride the correspondence (Post.send), the parts ride
// the cargo road (Media.layFile), and a call and its answer ride the box of a pipe (Post.knockWord, Post.pickup).

/**
 * THE ERASURE CODE OF A DELIVERY (iOS MTKeepCode 20-224): Reed-Solomon over the field of 256 elements with the modulus 0x11D, the
 * Cauchy matrix cauchy[i][j] = inverse((erasure_data + i) XOR j), the body blocks first and the parity after them. The vectors
 * are the Canon's own (tools/keep_vectors.py makes them again outside both apps); the keeping refuses to start where they fail.
 */
object KeepCode {
    const val CHUNK = 868   // Canon: chunk_bytes
    const val GROUP = 16    // Canon: erasure_group
    const val DATA = 12     // Canon: erasure_data
    const val PARITY = GROUP - DATA

    /** A product in the field without a branch on either operand, the core's own form (mt-wire, erasure.rs). */
    fun mul(a: Int, b: Int): Int {
        var product = 0
        var left = a and 0xff
        var right = b and 0xff
        repeat(8) {
            product = product xor (left and -(right and 1))
            val over = -(left ushr 7)
            left = ((left shl 1) xor (0x1D and over)) and 0xff
            right = right ushr 1
        }
        return product and 0xff
    }
    /** The whole table of the field, walked once: a product is then one read of 64 KiB. */
    private val table: ByteArray by lazy { ByteArray(65536) { mul(it ushr 8, it and 0xff).toByte() } }
    private fun t(a: Int, b: Int) = table[(a shl 8) or b].toInt() and 0xff
    fun inverse(a: Int): Int? {
        if (a == 0) return null
        for (b in 1..255) if (t(a, b) == 1) return b
        return null
    }
    private val cauchy: Array<IntArray> by lazy { Array(PARITY) { i -> IntArray(DATA) { j -> inverse((DATA + i) xor j) ?: 0 } } }

    /** Every block scaled by its coefficient and summed into `o`, byte by byte. */
    private fun addScaled(o: ByteArray, coef: Int, b: ByteArray) {
        val tb = table
        val row = coef shl 8
        for (x in o.indices) o[x] = (o[x].toInt() xor tb[row or (b[x].toInt() and 0xff)].toInt()).toByte()
    }

    /** The parity blocks of one group: every body block scaled by its coefficient and summed, byte by byte. */
    fun parity(blocks: List<ByteArray>): List<ByteArray>? {
        if (blocks.size != DATA) return null
        val width = blocks[0].size
        if (blocks.any { it.size != width }) return null
        return List(PARITY) { i -> ByteArray(width).also { o -> for (j in 0 until DATA) addScaled(o, cauchy[i][j], blocks[j]) } }
    }

    /**
     * Any twelve cells of a group give its twelve body blocks, and no fewer: the rows they stand for are inverted in the field and
     * applied to what they carry. Twelve body cells in hand are the body itself, and nothing is computed.
     */
    fun reconstruct(present: List<Pair<Int, ByteArray>>): List<ByteArray>? {
        val seen = HashSet<Int>()
        val taken = ArrayList<Pair<Int, ByteArray>>()
        for ((p, b) in present) if (p in 0 until GROUP && seen.add(p)) {
            taken.add(p to b)
            if (taken.size == DATA) break
        }
        if (taken.size != DATA) return null
        val width = taken[0].second.size
        if (taken.any { it.second.size != width }) return null
        if (taken.all { it.first < DATA }) {
            val out = arrayOfNulls<ByteArray>(DATA)
            for ((p, b) in taken) out[p] = b
            return out.map { it!! }
        }
        val m = Array(DATA) { r -> taken[r].first.let { p -> if (p < DATA) IntArray(DATA) { if (it == p) 1 else 0 } else cauchy[p - DATA].copyOf() } }
        val inv = Array(DATA) { r -> IntArray(DATA) { if (it == r) 1 else 0 } }
        for (col in 0 until DATA) {
            val piv = (col until DATA).firstOrNull { m[it][col] != 0 } ?: return null
            val iv = inverse(m[piv][col]) ?: return null
            val mr = m[col]; m[col] = m[piv]; m[piv] = mr
            val ir = inv[col]; inv[col] = inv[piv]; inv[piv] = ir
            for (x in 0 until DATA) { m[col][x] = t(iv, m[col][x]); inv[col][x] = t(iv, inv[col][x]) }
            for (r in 0 until DATA) if (r != col && m[r][col] != 0) {
                val f = m[r][col]
                for (x in 0 until DATA) { m[r][x] = m[r][x] xor t(f, m[col][x]); inv[r][x] = inv[r][x] xor t(f, inv[col][x]) }
            }
        }
        return List(DATA) { i -> ByteArray(width).also { o -> for (j in 0 until DATA) if (inv[i][j] != 0) addScaled(o, inv[i][j], taken[j].second) } }
    }

    /**
     * THE CANON'S VECTORS OF THE WIRE (iOS agreesWithCanon 113-130), and one walk the frozen bytes cannot make alone: the body of the
     * vector is twelve repeated bytes, so a second body of counting bytes is rebuilt across a loss that takes three parity cells and
     * one body cell -- a matrix written in another order, or rows taken for the wrong positions, rebuilds neither.
     */
    fun agreesWithCanon(): Boolean {
        val body = List(DATA) { j -> ByteArray(CHUNK) { (0xA0 + j).toByte() } }
        val par = parity(body) ?: return false
        if (par.map { Wire.hex(it.copyOf(4)) } != listOf("a5a5a5a5", "acacacac", "b7b7b7b7", "bebebebe")) return false
        if (Wire.hex(Wire.sha(*par.toTypedArray())) != "8963024273fc41fdf9afe063f3be77e7fbc312a7d8ede4f96a7fd99dd4fd0e69") return false
        val lost = setOf(0, 5, 7, 11)
        val whole = body + par
        val back = reconstruct(whole.indices.filter { it !in lost }.map { it to whole[it] }) ?: return false
        if (back.indices.any { !back[it].contentEquals(body[it]) }) return false
        val counting = List(DATA) { j -> ByteArray(64) { ((j * 64 + it) % 251).toByte() } }
        val all = counting + (parity(counting) ?: return false)
        val loss = setOf(3, 12, 13, 15)
        val again = reconstruct(all.indices.filter { it !in loss }.map { it to all[it] }) ?: return false
        return again.indices.all { again[it].contentEquals(counting[it]) }
    }

    /** As many bytes as the buffer holds, or fewer only at the end of the stream (a stream may hand fewer at a time). */
    private fun readUpTo(inp: InputStream, buf: ByteArray): Int {
        var got = 0
        while (got < buf.size) { val r = inp.read(buf, got, buf.size - got); if (r < 0) break; got += r }
        return got
    }

    /**
     * THE CUT (iOS cut 132-183, Canon «The keeping of a copy»): the container is cut into blocks of chunk_bytes, grouped twelve at a
     * time, every group coded into sixteen cells, and cell p of every group laid into the share of slot p mod n, ascending. Streamed
     * one group at a time: a copy of gigabytes never stands whole in memory.
     */
    class Cut(val length: Long, val digest: ByteArray, val shares: List<File>, val shareDigests: List<ByteArray>)
    fun cut(container: File, n: Int, dir: File): Cut? {
        if (n !in setOf(4, 8, 16) || !container.isFile) return null
        val shares = List(n) { File(dir, java.util.UUID.randomUUID().toString() + ".keep") }
        val outs = ArrayList<java.io.OutputStream>()
        try {
            for (f in shares) outs.add(java.io.BufferedOutputStream(java.io.FileOutputStream(f), 1 shl 16))
            val whole = MessageDigest.getInstance("SHA-256")
            val digests = List(n) { MessageDigest.getInstance("SHA-256") }
            var length = 0L
            FileInputStream(container).use { inp ->
                val buf = ByteArray(DATA * CHUNK)
                while (true) {
                    val got = readUpTo(inp, buf)
                    if (got <= 0) break
                    whole.update(buf, 0, got)
                    length += got
                    val blocks = List(DATA) { j -> ByteArray(CHUNK).also { b -> val lo = j * CHUNK; if (lo < got) System.arraycopy(buf, lo, b, 0, minOf(CHUNK, got - lo)) } }
                    val cells = blocks + (parity(blocks) ?: throw java.io.IOException("parity"))
                    for (p in 0 until GROUP) { outs[p % n].write(cells[p]); digests[p % n].update(cells[p]) }
                    if (got < buf.size) break
                }
            }
            outs.forEach { it.close() }
            if (length <= 0) { shares.forEach { it.delete() }; return null }
            return Cut(length, whole.digest(), shares, digests.map { it.digest() })
        } catch (e: Exception) {
            outs.forEach { runCatching { it.close() } }
            shares.forEach { it.delete() }
            Log.d("Montana", "keep_cut refused " + e.javaClass.simpleName)
            return null
        }
    }

    /**
     * THE COPY BUILT BACK from the shares in hand (iOS rebuild 185-223): for every group the cells of each share are read where the
     * rule of positions laid them, any twelve rebuild the body, and the last group is cut at the container's own length. False when
     * a group cannot stand -- a container with a hole in it is never laid.
     */
    class Part(val slot: Int, val n: Int, val file: File)
    fun rebuild(parts: List<Part>, length: Long, dest: File): Boolean {
        val n = parts.firstOrNull()?.n ?: return false
        if (n !in setOf(4, 8, 16) || parts.any { it.n != n } || length <= 0) return false
        val per = GROUP / n
        val blocks = (length + CHUNK - 1) / CHUNK
        val groups = ((blocks + DATA - 1) / DATA).toInt()
        val ins = parts.mapNotNull { p -> runCatching { p.slot to RandomAccessFile(p.file, "r") }.getOrNull() }
        var fine = true
        var written = 0L
        try {
            java.io.BufferedOutputStream(java.io.FileOutputStream(dest), 1 shl 16).use { out ->
                for (g in 0 until groups) {
                    val present = ArrayList<Pair<Int, ByteArray>>()
                    for ((slot, fh) in ins) {
                        val at = g.toLong() * per * CHUNK
                        if (fh.length() < at + per * CHUNK) continue
                        val d = ByteArray(per * CHUNK)
                        fh.seek(at); fh.readFully(d)
                        for (c in 0 until per) present.add((slot + c * n) to d.copyOfRange(c * CHUNK, (c + 1) * CHUNK))
                    }
                    val body = reconstruct(present)
                    if (body == null) { fine = false; break }
                    for (b in body) {
                        if (written >= length) break
                        val take = minOf(CHUNK.toLong(), length - written).toInt()
                        out.write(b, 0, take)
                        written += take
                    }
                }
            }
        } catch (e: Exception) { fine = false } finally { ins.forEach { runCatching { it.second.close() } } }
        if (!fine || written != length) { dest.delete(); return false }
        return true
    }
}

/** THE THREE QUANTITIES OF KEEPING (iOS MTKeepDerive 226-297), as Canon fixes them: the secret of a slot, the keeping key, and the seal of a share's head. */
object KeepDerive {
    const val SLOTS = 16   // a group has sixteen cells: the slots of a copy (Canon: n is erasure_group)
    /** HKDF-Expand(master_seed, info, 32), the branches' one road: the core's own (mt_mldsa_seed_for_role). */
    private fun expand(master: ByteArray, info: String): ByteArray? =
        if (master.size == 64) MtBindings.nativeRoleSeed(master, info)?.takeIf { it.size == 32 } else null
    /** slot_secret(k) = HKDF-Expand(master_seed, "mt-keep-slot" || 0x00 || k_1B, 32) */
    fun slotSecret(master: ByteArray, k: Int): ByteArray? = if (k in 0 until SLOTS) expand(master, "mt-keep-slot" + Char(0) + Char(k)) else null
    /** keep_key = HKDF-Expand(master_seed, "mt-keep-key", 32): it seals every head and is handed to nobody. */
    fun keepKey(master: ByteArray) = expand(master, "mt-keep-key")
    /** light_secret = HKDF-Expand(master_seed, "mt-keep-light", 32): the pipe of light, the owner's alone, in which the road of the light copy is named. */
    fun lightSecret(master: ByteArray) = expand(master, "mt-keep-light")

    /** head = k_1B || n_1B || generation_8B_LE || length_8B_LE || SHA-256(container) || SHA-256(share): eighty-two bytes. */
    class Head(val slot: Int, val n: Int, val generation: Long, val length: Long, val copyDigest: ByteArray, val shareDigest: ByteArray) {
        val bytes: ByteArray get() = byteArrayOf(slot.toByte(), n.toByte()) + Wire.le8(generation) + Wire.le8(length) + copyDigest + shareDigest
        fun same(o: Head) = slot == o.slot && n == o.n && generation == o.generation && length == o.length &&
            copyDigest.contentEquals(o.copyDigest) && shareDigest.contentEquals(o.shareDigest)
        companion object {
            const val SIZE = 82
            fun of(d: ByteArray?): Head? {
                if (d == null || d.size != SIZE) return null
                fun u64(at: Int): Long { var v = 0L; for (b in 0 until 8) v = v or ((d[at + b].toLong() and 0xff) shl (8 * b)); return v }
                val slot = d[0].toInt() and 0xff; val n = d[1].toInt() and 0xff
                if (n !in setOf(4, 8, 16) || slot >= n) return null
                return Head(slot, n, u64(2), u64(10), d.copyOfRange(18, 50), d.copyOfRange(50, 82))
            }
        }
    }
    /** seal = SHA-256("mt-keep-seal" || 0x00 || keep_key || head), by the set's one composition. */
    fun seal(key: ByteArray, head: Head): ByteArray = Wire.domained("mt-keep-seal", key, head.bytes)

    /**
     * THE CANON'S VECTORS OF KEEPING (iOS 277-296), from the master seed of sixty-four distinct bytes. What they reject is named in the
     * set: a slot written as eight bytes, a missing NUL, a seed read backwards, integers written big-endian, the slot and n exchanged.
     */
    fun agreesWithCanon(): Boolean {
        val master = ByteArray(64) { it.toByte() }
        val s3 = slotSecret(master, 3) ?: return false
        val key = keepKey(master) ?: return false
        if (slotSecret(master, 0)?.let { Wire.hex(it) } != "f57057fdd34a297a072f161d54105f98ec23cbbaf6229662b36efb9ae4aaa9d7" ||
            slotSecret(master, 1)?.let { Wire.hex(it) } != "c534306aa283d19c8e83f392bda37a7e59b7ccd7868b8df455bb9b6716e1ab91" ||
            slotSecret(master, 15)?.let { Wire.hex(it) } != "4573fb5ad5dc3b579049f304cc95cf5f3765ceaf07caab730d986c034788edab" ||
            Wire.hex(Wire.pipeTag(s3, 1000)) != "ae67484d6abdb555a43159fc9386d753" ||
            Wire.hex(key) != "9945bec54d8f26ab7859b3e6eb886456ff529fd2637aa2650626b3595e88970c") return false
        // the light secret over the counting seed and over the same seed read backwards: a reader of the seed backwards swaps them
        val light = lightSecret(master) ?: return false
        if (Wire.hex(light) != "23d9bfa1a0151598ea710a15492cb9f8fcb46e5c86d39ba0e8824a69511a3776" ||
            lightSecret(master.reversedArray())?.let { Wire.hex(it) } != "8d14528b640e1d7b114c2d299cf85f4ba7813a2308255dfba6025f01e4f288b9" ||
            Wire.hex(Wire.pipeTag(light, 1000)) != "7b957934998d5c0ad69415e43616020c") return false
        val head = Head(2, 8, 0x1112131415161718L, 0x0102030405060708L, ByteArray(32) { (0x20 + it).toByte() }, ByteArray(32) { (0x40 + it).toByte() })
        return Head.of(head.bytes)?.same(head) == true &&
            Wire.hex(seal(key, head)) == "80b0b97f66a8ef64fce6d692935a82b37bf978c0e215cd8b190bb7a1100475ae"
    }
}

/**
 * THE RING OF KEEPERS (iOS MTKeepRing 1030-1051; the author's word 08.10.2026 23:5x MSK: «between contacts in a ring, so that if
 * someone is offline the restore is full»): every correspondent that allows keeping, two at each position at most, and every share at
 * two neighbouring positions.
 */
object KeepRing {
    const val MOST = 2 * KeepCode.GROUP
    /** The slots the keeper at place i of m keeps: those whose position, k mod q, is its own or the next one around the ring. */
    fun slots(place: Int, of: Int): List<Int> {
        val q = minOf(of, KeepCode.GROUP)
        if (q <= 0 || place < 0 || place >= of) return emptyList()
        val j = place % q
        return (0 until KeepCode.GROUP).filter { it % q == j || it % q == (j + 1) % q }
    }
    /** The rule as cases a wrong reading fails: a ring that does not close, the neighbour taken backwards, one or two keepers holding
     *  all sixteen, and the seventeenth keeper of twenty standing beside the first. */
    fun agrees(): Boolean =
        slots(0, 4) == listOf(0, 1, 4, 5, 8, 9, 12, 13) && slots(3, 4) == listOf(0, 3, 4, 7, 8, 11, 12, 15) &&
            slots(0, 1) == (0 until 16).toList() && slots(1, 2) == (0 until 16).toList() &&
            slots(16, 20) == listOf(0, 1) && slots(15, 16) == listOf(0, 15)
}

/**
 * THE KEEPING ON THIS PHONE (iOS MTKeeping 299-1028), its three sides in one owner: the owner's (my copy with the people I write to),
 * the keeper's (the parts this phone holds for them), and the side of a phone that opens the words (the copy taken back). One token
 * of the one vocabulary of service words, Marks.KEEP, JSON with «w»: «ask», «yes», «part», «held» and «release» ride the
 * correspondence of the owner and the keeper, «back» and «given» the correspondence of a person and anyone they write to; «call»
 * and «answer» ride the pipe of a slot; «light» the pipe of light.
 */
object Keeping {
    // ── the person's choices, settings of this device ──
    private const val MINE = "mt.keep.mine"           // NOT-UI: my copy is kept by the people I write to
    private const val OTHERS = "mt.keep.others"       // NOT-UI: this phone keeps parts for the people who write to me
    private const val BUDGET = "mt.keep.budget.mb"    // NOT-UI: what this phone keeps for others, in megabytes
    private const val TOLD = "mt.keep.mine.told"      // NOT-UI: the person was told and chose
    /**
     * ON BY DEFAULT, ASKED AT THE OPENING (iOS 311-319, the author's word 08.10.2026 23:2x MSK): nothing leaves before the person has
     * been told what each keeper learns -- the question at the opening, or the switch in Data and Storage under its own explanation.
     */
    val mine: Boolean get() = Prefs.bool(MINE, true)
    val told: Boolean get() = Prefs.bool(TOLD, false)
    /** The crossed glyph in the bar's first slot: the person chose to keep no copy with their contacts. */
    val offShown: Boolean get() = told && !mine
    val others: Boolean get() = Prefs.bool(OTHERS, true)
    private val budget: Long get() = (Prefs.str(BUDGET, "").toLongOrNull() ?: 1024L) * 1_048_576L
    /** The names a slot's pipe is heard under in the box: never a conversation of the feed. */
    const val PIPE_PREFIX = "keep:"   // NOT-UI: the pipe of a slot this phone holds
    private const val CALL_PREFIX = "kslot:"   // NOT-UI: the pipes a phone opening the words calls in
    /** The name the pipe of light is heard and sent under (iOS lightName): never the person's own reference. */
    private const val LIGHT_NAME = "light"   // NOT-UI
    /** The app on this phone as the network names it (iOS Bundle.main.bundleIdentifier): one person's Montana on an iPhone and on an
     *  Android phone is one app of the same words, whatever package this build installs under. */
    const val APP = "quest.montana.app"   // NOT-UI
    /** The keeping starts only where the Canon's vectors hold: a code or a derivation off by one byte would scatter parts nobody can rebuild. */
    val agrees: Boolean by lazy {
        val ok = KeepCode.agreesWithCanon() && KeepDerive.agreesWithCanon() && KeepRing.agrees()
        Log.d("Montana", "keep_canon " + if (ok) "ok" else "DISAGREES — nothing is kept")
        ok
    }

    // ── the owner's side ──
    /** A keeper of the ring holds the slots of its position and of the next (KeepRing); a keeper of an older build held one. */
    class Keeper(var slot: Int, var held: Boolean, var slots: List<Int>? = null, var heldSlots: List<Int>? = null) {
        fun json(): JSONObject = JSONObject().put("slot", slot).put("held", held).apply {
            slots?.let { put("slots", JSONArray(it)) }; heldSlots?.let { put("heldSlots", JSONArray(it)) }
        }
        companion object {
            fun of(o: JSONObject) = Keeper(o.optInt("slot"), o.optBoolean("held"), o.optJSONArray("slots")?.ints(), o.optJSONArray("heldSlots")?.ints())
        }
    }
    class Owner(var generation: Long = 0, var asking: Long? = null, var askedAt: Double = 0.0, val yes: MutableList<String> = mutableListOf(),
                var n: Int = 0, val keepers: MutableMap<String, Keeper> = LinkedHashMap(), var renewedAt: Double = 0.0, var short: Boolean = false,
                var lightGen: Long? = null, var lightAt: Double? = null) {
        fun json(): JSONObject = JSONObject().put("generation", generation).put("askedAt", askedAt).put("yes", JSONArray(yes)).put("n", n)
            .put("keepers", JSONObject().apply { keepers.forEach { (k, v) -> put(k, v.json()) } }).put("renewedAt", renewedAt).put("short", short)
            .apply { asking?.let { put("asking", it) }; lightGen?.let { put("lightGen", it) }; lightAt?.let { put("lightAt", it) } }
        companion object {
            fun of(o: JSONObject) = Owner(o.optLong("generation"), if (o.has("asking")) o.optLong("asking") else null, o.optDouble("askedAt", 0.0),
                o.optJSONArray("yes")?.strings()?.toMutableList() ?: mutableListOf(), o.optInt("n"),
                LinkedHashMap<String, Keeper>().apply { o.optJSONObject("keepers")?.let { k -> k.keys().forEach { put(it, Keeper.of(k.getJSONObject(it))) } } },
                o.optDouble("renewedAt", 0.0), o.optBoolean("short"),
                if (o.has("lightGen")) o.optLong("lightGen") else null, if (o.has("lightAt")) o.optDouble("lightAt") else null)
        }
    }
    private const val OWNER = "mt.keep.owner"   // NOT-UI: sealed under the device key; the person's own
    private var owner = Owner()

    // ── the keeper's side ──
    /** A part held: the owner's own road of it on the nodes and when it was laid ride an answer within the pieces' week whole. */
    class Held(val slot: Int, val n: Int, val secret: ByteArray, val head: ByteArray, val seal: ByteArray, val bytes: Long, val at: Double,
               var answeredAt: Double = 0.0, var road: Map<String, String>? = null, var roadAt: Double? = null) {
        fun json(): JSONObject = JSONObject().put("slot", slot).put("n", n).put("secret", b64(secret)).put("head", b64(head)).put("seal", b64(seal))
            .put("bytes", bytes).put("at", at).put("answeredAt", answeredAt)
            .apply { road?.let { r -> put("road", JSONObject(r)) }; roadAt?.let { put("roadAt", it) } }
        companion object {
            fun of(o: JSONObject): Held? {
                val secret = unb64(o.optString("secret")) ?: return null
                val head = unb64(o.optString("head")) ?: return null
                val seal = unb64(o.optString("seal")) ?: return null
                val road = o.optJSONObject("road")?.let { r -> r.keys().asSequence().associateWith { r.optString(it) } }
                return Held(o.optInt("slot"), o.optInt("n"), secret, head, seal, o.optLong("bytes"), o.optDouble("at", 0.0),
                    o.optDouble("answeredAt", 0.0), road, if (o.has("roadAt")) o.optDouble("roadAt") else null)
            }
        }
    }
    private const val HELD = "mt.keep.held"   // NOT-UI: this device's own
    private var held = LinkedHashMap<String, Held>()

    // ── a phone that opened the words ──
    /** Fetching: the light copy coming down from the nodes, its share of bytes -- set the moment the words open, so the page shows a
     *  bar from its first frame (iOS Taking, the author's word 09.10.2026). */
    sealed class Taking {
        object Idle : Taking()
        class Fetching(val f: Double) : Taking()
        class Calling(val have: Int, val need: Int) : Taking()
        class Laying(val f: Double) : Taking()
        object Done : Taking()
        object Failed : Taking()
    }
    @Volatile var taking: Taking = Taking.Idle
        private set(v) { field = v; changed() }
    /** The first screen waits for the copy (Onboarding.takeFromKeepers) until the person walks on without it. */
    @Volatile var onboardingWaits = false
    /** The first screen lets the person in the moment the light copy is laid (App: «once the light copy is laid»). */
    @Volatile var onLight: (() -> Unit)? = null
    @Volatile private var renewing = false
    @Volatile private var lighting = false
    @Volatile private var takingThread: Thread? = null
    @Volatile private var stopped = false
    private val roads = HashMap<String, Pair<Double, JSONObject>>()
    private val lock = Any()
    @Volatile private var loaded = false

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun now() = System.currentTimeMillis() / 1000.0
    private fun b64(b: ByteArray): String = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String?): ByteArray? = s?.takeIf { it.isNotEmpty() }?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() }
    private fun unhex(h: String?): ByteArray? = h?.takeIf { it.length % 2 == 0 && it.all { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' } }
        ?.let { s -> ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() } }
    private fun JSONArray.ints(): List<Int> = (0 until length()).map { optInt(it) }
    private fun JSONArray.strings(): List<String> = (0 until length()).map { optString(it) }

    /** What the vault holds, read again: at launch, and after a copy laid this person's state of keeping. */
    fun reread() = synchronized(lock) {
        owner = DeviceVault.get(OWNER)?.let { runCatching { Owner.of(JSONObject(String(it, Charsets.UTF_8))) }.getOrNull() } ?: Owner()
        held = heldNow()
        loaded = true
    }
    private fun ensure() { if (!loaded) reread() }
    private fun saveOwner() { DeviceVault.set(OWNER, owner.json().toString().toByteArray()) }
    private fun saveHeld() { DeviceVault.set(HELD, JSONObject().apply { held.forEach { (k, v) -> put(k, v.json()) } }.toString().toByteArray()) }
    private fun heldNow(): LinkedHashMap<String, Held> {
        val o = DeviceVault.get(HELD)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: return LinkedHashMap()
        return LinkedHashMap<String, Held>().apply { o.keys().forEach { k -> o.optJSONObject(k)?.let { Held.of(it) }?.let { put(k, it) } } }
    }
    /** The owner's state as the page reads it: a copy taken under the lock. */
    fun ownerNow(): Owner = synchronized(lock) { ensure(); Owner.of(owner.json()) }

    /**
     * THE PARTS THIS PHONE KEEPS FOR OTHERS lie in a folder of their own (iOS folder 392-403), never in this person's copy and never
     * in the platform's backup: they are another person's, and they go back only to that person's words.
     */
    private fun folder(): File? = runCatching { File(Book.ctx.noBackupFilesDir, "MontanaKeeping").apply { mkdirs() } }.getOrNull()
    private fun partFile(key: String): File? {
        val name = key.map { ch -> if (ch.isLetterOrDigit() && ch.code < 128) ch.toString() else "%" + "%02X".format(ch.code and 0xff) }.joinToString("")
        return if (name.isEmpty()) null else folder()?.let { File(it, "$name.keep") }
    }
    /** Where the copies, shares and answers of this file are cut and built: apart from MontanaBackup's shelf, which a copy clears. */
    private fun work(): File? = runCatching { File(Book.ctx.noBackupFilesDir, "MontanaKeepWork").apply { mkdirs() } }.getOrNull()

    // ── the words ──
    fun word(text: String): JSONObject? =
        if (!text.startsWith(Marks.KEEP)) null else runCatching { JSONObject(text.removePrefix(Marks.KEEP)) }.getOrNull()
    private fun say(conv: String, o: JSONObject) = Post.send(conv, Marks.mintMid(), Marks.KEEP + o.toString(), quiet = true)
    /** A keeping word lives in the queue while it can still mean something (iOS expired 418-423): a question an hour (an older build
     *  buries it unread and never receipts it), every other word two days -- the pieces of a part live a week on the nodes. */
    fun expired(text: String, ageS: Double): Boolean {
        if (!text.startsWith(Marks.KEEP)) return false
        return ageS > (if (word(text)?.optString("w") == "ask") 3600.0 else 172_800.0)
    }
    /**
     * A KEEPING WORD IS HEARD ONCE (iOS ChatStore.controlSeen, MontanaDeliveryEngine 228-237: «a control letter that already spoke is not
     * heard twice»): the box repeats until a pickup confirms, and the live road and the box bring the same word twice -- a question
     * answered twice is two answers (17.10.2026: one «ask» on three phones came back as two dozen «yes»). The names are kept a while.
     */
    private const val HEARD = "mt.keep.heard"   // NOT-UI
    private val heardMids = LinkedHashSet<String>()
    @Volatile private var heardRead = false
    fun once(mid: String): Boolean = synchronized(heardMids) {
        if (!heardRead) { heardRead = true; Prefs.str(HEARD, "").split('\n').filterTo(heardMids) { it.isNotEmpty() } }
        if (mid.isEmpty() || !heardMids.add(mid)) return false
        while (heardMids.size > 1024) heardMids.remove(heardMids.first())
        Prefs.setStr(HEARD, heardMids.joinToString("\n"))
        true
    }
    /** A keeping word landed in a correspondence (Post.place): never a row, answered here, off the box's thread. */
    fun heard(text: String, conv: String) {
        if (!agrees) return
        val o = word(text) ?: return
        val w = o.optString("w")
        Log.d("Montana", "keep_word w=" + w + " conv=" + conv.take(10))
        Thread {
            runCatching {
                when (w) {
                    "ask" -> answerAsk(conv, o)
                    "yes" -> tookYes(conv, o)
                    "part" -> takePart(conv, o)
                    "held" -> tookHeld(conv, o)
                    "release" -> drop(conv)
                    "back" -> answerBack(conv, o)
                    "given" -> takeGiven(conv, o)
                }
            }.onFailure { Log.w("Montana", "keep_word " + w + " " + it.javaClass.simpleName) }
        }.start()
    }

    // ── the owner ──
    fun setMine(on: Boolean) {
        Prefs.setBool(MINE, on)
        Prefs.setBool(TOLD, true)   // the switch stands under its own explanation
        if (on) {
            synchronized(lock) { ensure(); owner.renewedAt = 0.0; saveOwner() }
            Thread { tick() }.start()
        } else {
            val gone = synchronized(lock) { ensure(); owner.keepers.keys.toList().also { owner = Owner(generation = owner.generation); saveOwner() } }
            for (conv in gone) say(conv, JSONObject().put("w", "release"))
        }
        changed()
    }
    /** The answer to the question at the opening. */
    fun answer(keep: Boolean) { Prefs.setBool(TOLD, true); setMine(keep) }

    /**
     * THE QUESTION AT THE OPENING (iOS ContentView 2369-2380): once the system's own question about notifications has been put, the
     * copy's question follows at the next return, until the person answers it.
     */
    @Volatile private var asking = false
    fun askAtOpening(act: MainActivity) {
        if (told || asking || !MontanaSeed.hasSeed) return
        asking = true
        AlertDialog.Builder(act)
            .setTitle(R.string.keep_ask_title)
            .setMessage(R.string.keep_explained)
            .setPositiveButton(R.string.keep_ask_yes) { _, _ -> asking = false; answer(true) }
            .setNegativeButton(R.string.keep_ask_not_now) { _, _ -> asking = false; answer(false) }
            .setOnCancelListener { asking = false }
            .show()
    }

    /**
     * THE OWNER'S RHYTHM (iOS tick 452-471): a renewal is due a day after the last; it asks the people I write to, waits ten minutes
     * for one yes at least (a full ring goes at once), and an hour without one leaves the copy where it stands until tomorrow.
     */
    fun tickSoon() = MainThread.later(30_000L, Runnable { Thread { tick() }.start() })
    fun tick() {
        if (!mine || !told || !agrees || !MontanaSeed.hasSeed) return
        val now = now()
        val (lightDue, asked) = synchronized(lock) { ensure(); (!lighting && now - (owner.lightAt ?: 0.0) >= 86_400) to owner.asking }
        if (lightDue) layLight()
        if (renewing) return
        if (asked != null) {
            val (yes, at) = synchronized(lock) { owner.yes.size to owner.askedAt }
            if (yes >= KeepRing.MOST || (yes > 0 && now - at >= 600)) return renew(asked)
            if (now - at >= 3600) {
                synchronized(lock) { owner.short = true; owner.asking = null; owner.yes.clear(); owner.renewedAt = now; saveOwner() }
                Log.d("Montana", "keep_ask nobody said yes in an hour")
                changed()
                return
            }
            MainThread.later(120_000L, Runnable { Thread { tick() }.start() })
            return
        }
        if (now - synchronized(lock) { owner.renewedAt } < 86_400) return
        ask()
    }
    private fun ask() {
        val people = candidates()
        val now = now()
        if (people.isEmpty()) {
            synchronized(lock) { owner.short = true; owner.renewedAt = now; saveOwner() }
            Log.d("Montana", "keep_ask people=0: nobody to ask")
            changed()
            return
        }
        val g = synchronized(lock) { (owner.generation + 1).also { owner.asking = it; owner.askedAt = now; owner.yes.clear(); saveOwner() } }
        for (conv in people) say(conv, JSONObject().put("w", "ask").put("g", g))
        Log.d("Montana", "keep_ask g=" + g + " people=" + people.size)
        changed()
        MainThread.later(120_000L, Runnable { Thread { tick() }.start() })
    }
    /** The people I write to, the latest first: a correspondence of a person -- never my own twin, a group, a folded pipe, a closed
     *  one, or someone I block (iOS people 485-492). */
    private fun people(): List<String> {
        val twin = MontanaSeed.twin ?: ""
        return Book.all().map { it.ref }.filter { ref ->
            ref != twin && !ref.startsWith("arc:") && !Groups.isKey(ref) && Book.secret(ref) != null && SamePair.merged(ref) == null &&
                !Post.closed(ref) && !PeerSafety.isBlocked(ref) && !PeerSafety.isBarred(ref)
        }
    }
    /** Those asked to keep: twice a full ring, so that the ring fills when some stay silent. */
    private fun candidates() = people().take(2 * KeepRing.MOST)
    private fun tookYes(conv: String, o: JSONObject) {
        val g = o.optLong("g", -1)
        val full = synchronized(lock) {
            ensure()
            val a = owner.asking ?: return
            if (g != a || owner.yes.contains(conv)) return
            owner.yes.add(conv); saveOwner()
            if (owner.yes.size >= KeepRing.MOST) a else null
        }
        changed()
        if (full != null) renew(full)
    }
    /** The keeper's own word: only this makes a part «held» on my screen (the rule of the external keeper); a keeper of the ring names
     *  the slot it holds, and is whole once it holds every slot of its place. */
    private fun tookHeld(conv: String, o: JSONObject) {
        val whole = synchronized(lock) {
            ensure()
            if (o.optLong("g", -1) != owner.generation) return
            val k = owner.keepers[conv] ?: return
            if (o.has("k")) {
                val have = ((k.heldSlots ?: emptyList()) + o.optInt("k")).toSortedSet()
                k.heldSlots = have.toList()
                k.held = have.containsAll(k.slots ?: listOf(k.slot))
            } else k.held = true   // a keeper of an older build holds one part and names no slot
            saveOwner()
            k.held
        }
        Log.d("Montana", "keep_held slot=" + o.optInt("k", -1) + " whole=" + whole)
        changed()
    }
    private fun renew(g: Long) {
        val yes = synchronized(lock) { owner.yes.toList() }
        if (yes.isEmpty() || renewing) return
        renewing = true
        synchronized(lock) { owner.asking = null; saveOwner() }
        // THE RING IN THE ORDER OF THE LATEST LETTER (Network): the people written to last stand first, a full ring at most
        val rank = people().withIndex().associate { it.value to it.index }
        val chosen = yes.sortedBy { rank[it] ?: Int.MAX_VALUE }.take(KeepRing.MOST)
        Thread {
            try {
                when (val r = MontanaBackup.create(Book.ctx) { }) {
                    is CopyResult.Made -> try { hand(r.file, g, chosen) } finally { r.file.delete() }
                    is CopyResult.Refused -> Log.d("Montana", "keep_copy refused " + r.why.javaClass.simpleName)
                    else -> {}
                }
            } finally { renewing = false; changed() }
        }.start()
    }
    /**
     * THE COPY HANDED AROUND THE RING (iOS hand 534-570): cut at the sixteen slots of a group (Canon: n is erasure_group), every share
     * laid on the nodes ONCE and its road handed to each keeper of its slot -- the ring costs the network a copy and a third, whatever
     * the number of keepers.
     */
    private fun hand(made: File, g: Long, keepers: List<String>) {
        val n = KeepCode.GROUP
        val m = MontanaSeed.mnemonic ?: return
        val master = MtBindings.nativeMnemonicToMasterSeed(m) ?: return
        try {
            val key = KeepDerive.keepKey(master) ?: return
            val dir = work() ?: return
            val cut = KeepCode.cut(made, n, dir) ?: return Unit.also { Log.d("Montana", "keep_cut refused n=" + n) }
            try {
                val laid = HashMap<Int, JSONObject>()
                for (k in 0 until n) lay(cut.shares[k])?.let { laid[k] = it }
                val ring = keepers.withIndex().associate { (i, conv) -> conv to KeepRing.slots(i, keepers.size).filter { laid[it] != null } }
                val sent = LinkedHashMap<String, Keeper>()
                for ((conv, slots) in ring) slots.firstOrNull()?.let { sent[conv] = Keeper(it, false, slots, emptyList()) }
                if (sent.isEmpty()) { Log.d("Montana", "keep_hand no part left the phone"); return }
                // THE RING STANDS BEFORE ITS FIRST PART LEAVES: a keeper's «held» can come back within the second, on another thread,
                // and is weighed against the generation and the ring written here (iOS does it on one actor, after the loop)
                val released = synchronized(lock) {
                    val gone = owner.keepers.keys.filter { sent[it] == null }
                    owner.keepers.clear(); owner.keepers.putAll(sent)
                    owner.n = n; owner.generation = g; owner.yes.clear(); owner.short = false; owner.renewedAt = now()
                    saveOwner()
                    gone
                }
                var parts = 0
                for ((conv, slots) in ring) for (k in slots) {
                    val secret = KeepDerive.slotSecret(master, k) ?: continue
                    val road = laid[k] ?: continue
                    val head = KeepDerive.Head(k, n, g, cut.length, cut.digest, cut.shareDigests[k])
                    val o = JSONObject().put("w", "part").put("k", k).put("n", n).put("s", b64(secret))
                        .put("h", Wire.hex(head.bytes)).put("e", Wire.hex(KeepDerive.seal(key, head)))
                    road.keys().forEach { o.put(it, road.get(it)) }
                    say(conv, o)
                    parts++
                }
                for (conv in released) say(conv, JSONObject().put("w", "release"))
                Log.d("Montana", "keep_hand g=" + g + " keepers=" + sent.size + " parts=" + parts + " laid=" + laid.size + " bytes=" + cut.length)
            } finally { cut.shares.forEach { it.delete() } }
        } finally { master.fill(0) }
    }

    // ── the light copy (Network «The light copy»; the author's word 08.10.2026 23:5x MSK: «the person, the face, the name and
    // everything else back by the words, down to the chess games») ──
    /**
     * THE COPY WITHOUT ITS ATTACHMENTS (iOS layLight 572-610) -- every letter, every room, the profile, the faces and the head of every
     * correspondence -- sealed as every copy is, laid on the nodes and named by one letter in the pipe of light, once a day while the
     * copy is kept. The pieces live a week there and the letter in the box as long, so a phone lost today is opened by the words
     * alone tomorrow.
     */
    private fun layLight() {
        if (lighting) return
        lighting = true
        val g = synchronized(lock) { (owner.lightGen ?: 0L) + 1 }
        Thread {
            try {
                when (val r = MontanaBackup.create(Book.ctx, light = true) { }) {
                    is CopyResult.Made -> try { nameLight(r.file, r.tally, g) } finally { r.file.delete() }
                    is CopyResult.Refused -> Log.d("Montana", "keep_light refused " + r.why.javaClass.simpleName)
                    else -> {}
                }
            } finally { lighting = false }
        }.start()
    }
    private fun nameLight(made: File, tally: Tally, g: Long) {
        val m = MontanaSeed.mnemonic ?: return
        val master = MtBindings.nativeMnemonicToMasterSeed(m) ?: return
        val secret = KeepDerive.lightSecret(master).also { master.fill(0) }
        val digest = digestOf(made)
        val road = if (secret != null && digest != null) lay(made) else null
        if (secret == null || digest == null || road == null) { Log.d("Montana", "keep_light the light copy did not reach the nodes"); return }
        road.put("w", "light").put("g", g).put("d", digest).put("v", Archive.writerTagHex())   // the device that laid it
            .put("a", APP)   // and the app on it: two apps of one phone are two writers of the same words
        // The sender of the pipe of light is named «light», never this person's own reference: a phone opening the same words reads
        // the box under that reference, and a letter of its own name the node would keep from it.
        if (!knock(secret, road, sender = LIGHT_NAME)) { Log.d("Montana", "keep_light no door boxed the road"); return }
        synchronized(lock) { owner.lightGen = g; owner.lightAt = now(); saveOwner() }
        Log.d("Montana", "keep_light named g=" + g + " bytes=" + tally.bytes + " chats=" + tally.chats)
    }
    /**
     * THE LIGHT COPY TAKEN BACK (iOS takeLight 612-656): the pipe of light read, and the newest road OF EVERY DEVICE that names one
     * there taken -- two devices of the same words count their generations each from one, so the highest number is no measure across
     * them. Each is checked by its digest and laid, the largest first; a copy laid merges and erases nothing. The person stands in
     * their correspondences from the first laid. The box keeps the letters: the next phone of the same words reads them too.
     */
    private fun takeLight(secret: ByteArray, dir: File): Boolean {
        val rows = ArrayList<Map<String, String>>()
        Post.pickup(mapOf(LIGHT_NAME to secret)) { row -> rows.add(row); false }
        val newest = HashMap<String, JSONObject>()
        for (o in rows.mapNotNull { word(it["t"] ?: "") }) if (o.optString("w") == "light") {
            // THE NEWEST ROAD OF EVERY WRITER, A DEVICE AND THE APP ON IT (09.10.2026)
            val v = o.optString("v") + "/" + o.optString("a")
            if (o.optLong("g", 0) >= (newest[v]?.optLong("g", -1) ?: -1)) newest[v] = o
        }
        val list = newest.values.sortedByDescending { it.optLong("z", 0) }
        if (list.isEmpty()) { Log.d("Montana", "keep_light the pipe of light holds no road"); return false }
        var laid = 0
        for (road in list) {
            val d = road.optString("d").ifEmpty { null } ?: continue
            val f = File(dir, java.util.UUID.randomUUID().toString() + ".mtbak")
            try {
                taking = Taking.Fetching(0.0)
                if (!fetch(road, f) { taking = Taking.Fetching(it) } || digestOf(f) != d) { Log.d("Montana", "keep_light a light copy did not come whole"); continue }
                taking = Taking.Laying(0.0)
                val r = MontanaBackup.restore(Book.ctx, f) { taking = Taking.Laying(it) }
                reread()
                Log.d("Montana", "keep_light laid=" + (if (r is CopyResult.Taken) "taken chats=" + r.tally.chats else r.javaClass.simpleName) + " devices=" + list.size)
                if (r !is CopyResult.Taken) continue
                Archive.restoreAndWait()   // the person stands in their correspondences from the first copy laid
                laid++
                if (laid == 1) { val letIn = onLight; onLight = null; letIn?.invoke() }
            } finally { f.delete() }
        }
        return laid > 0
    }

    // ── the cargo road of a part ──
    /**
     * A PART ON THE CARGO ROAD (iOS lay 658-671): sealed in pieces under a fresh key and put on the nodes, and its list of pieces sealed
     * as one more piece -- the word that names a part carries that piece's name and key, never the list (a list outgrows a letter).
     */
    fun lay(f: File): JSONObject? {
        val size = f.length()
        if (size <= 0) return null
        val bk = MtBindings.nativeRandom(32) ?: return null
        val (key, chunks) = Media.layFile(f, java.util.UUID.randomUUID().toString(), bk) { } ?: return null
        val mk = MtBindings.nativeRandom(32) ?: return null
        val sealed = Wire.seal(mk, chunks.toString().toByteArray(Charsets.UTF_8)) ?: return null
        val mref = Wire.hex(Wire.sha(sealed))
        if (!Wire.putBlob(mref, sealed, assumeAbsent = true)) return null
        return JSONObject().put("z", size).put("bk", key).put("mref", mref).put("mk", b64(mk))
    }
    /** The part comes back piece by piece from the nodes (iOS fetch 672-698), each opened under its key and checked by its name, written in order. */
    fun fetch(o: JSONObject, dest: File, progress: ((Double) -> Unit)? = null): Boolean {
        val size = o.optLong("z", 0)
        val bk = unb64(o.optString("bk"))
        val mref = o.optString("mref")
        val mk = unb64(o.optString("mk"))
        if (size <= 0 || bk == null || mk == null || mref.isEmpty()) return false
        val list = Wire.getBlob(mref)?.takeIf { Wire.hex(Wire.sha(it)) == mref } ?: return false
        val manifest = Wire.open(mk, list)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: return false
        dest.delete()
        var written = 0L
        try {
            java.io.BufferedOutputStream(java.io.FileOutputStream(dest), 1 shl 16).use { out ->
                for (i in 0 until manifest.length()) {
                    val m = manifest.optJSONObject(i) ?: return false
                    val bid = m.optString("bid"); val cs = m.optInt("cs", -1)
                    if (bid.isEmpty() || cs < 0) return false
                    var piece: ByteArray? = null
                    for (attempt in 0 until 3) {
                        val s = Wire.getBlob(bid)
                        if (s != null && Wire.hex(Wire.sha(s)) == bid) piece = Wire.open(bk, s)?.let { if (cs <= it.size) it.copyOf(cs) else it }
                        if (piece != null) break
                        if (attempt < 2) Thread.sleep(800)
                    }
                    val p = piece ?: return false
                    out.write(p)
                    written += p.size
                    progress?.invoke(minOf(written, size).toDouble() / size)
                }
            }
        } catch (e: Exception) { return false }
        return written == size
    }
    /** SHA-256 of a file, in hex, read a megabyte at a time (iOS MontanaHomeNode.digest(of:)). */
    fun digestOf(f: File): String? = runCatching {
        val h = MessageDigest.getInstance("SHA-256")
        FileInputStream(f).use { inp -> val buf = ByteArray(1 shl 20); while (true) { val r = inp.read(buf); if (r < 0) break; h.update(buf, 0, r) } }
        Wire.hex(h.digest())
    }.getOrNull()

    // ── the keeper ──
    /** A part is held under the name of its correspondence and its slot: a keeper of the ring holds several of one owner. A name
     *  without a slot is a part an older build handed. */
    private fun keyOf(conv: String, k: Int) = conv + "#" + k
    private fun convOf(key: String) = key.substringBefore('#')
    private fun generation(h: Held) = KeepDerive.Head.of(h.head)?.generation ?: 0L
    private fun heldBytes(except: String) = held.filter { convOf(it.key) != except }.values.sumOf { it.bytes }
    /** The people whose parts this phone holds, and how much of each. */
    fun keptFor(): List<String> = synchronized(lock) { ensure(); held.keys.map { convOf(it) }.toSortedSet().toList() }
    fun bytes(conv: String): Long = synchronized(lock) { held.filter { convOf(it.key) == conv }.values.sumOf { it.bytes } }
    /** A question is answered only by a phone whose person allows keeping and whose budget has room: anything else is silence. */
    private fun answerAsk(conv: String, o: JSONObject) {
        val g = o.optLong("g", -1)
        val room = synchronized(lock) { ensure(); heldBytes(conv) < budget }
        if (!others || g < 0 || !room) { Log.d("Montana", "keep_quiet conv=" + conv.take(10)); return }
        say(conv, JSONObject().put("w", "yes").put("g", g))
    }
    private fun takePart(conv: String, o: JSONObject) {
        val k = o.optInt("k", -1); val n = o.optInt("n", -1)
        val secret = unb64(o.optString("s"))?.takeIf { it.size == 32 }
        val hd = unhex(o.optString("h"))
        val head = KeepDerive.Head.of(hd)?.takeIf { it.slot == k && it.n == n }
        val seal = unhex(o.optString("e"))?.takeIf { it.size == 32 }
        val size = o.optLong("z", 0)
        if (!others || secret == null || hd == null || head == null || seal == null || size <= 0) { Log.d("Montana", "keep_part refused in silence"); return }
        val key = keyOf(conv, k)
        // The budget counts every other person's parts and this person's parts of the same copy: an older copy leaves below.
        val room = synchronized(lock) {
            ensure()
            val sameCopy = held.filter { convOf(it.key) == conv && it.key != key && generation(it.value) == head.generation }.values.sumOf { it.bytes }
            heldBytes(conv) + sameCopy + size <= budget
        }
        val dest = partFile(key)
        if (!room || dest == null) { Log.d("Montana", "keep_part refused in silence"); return }
        val landing = File(dest.path + "." + java.util.UUID.randomUUID().toString().take(8) + ".part")   // one landing per fetch: two never share a file
        if (!fetch(o, landing) || digestOf(landing) != Wire.hex(head.shareDigest)) {
            landing.delete()
            Log.d("Montana", "keep_part the part did not come whole")
            return
        }
        dest.delete()
        if (!landing.renameTo(dest)) { landing.delete(); return }
        val first = synchronized(lock) {
            val first = held.keys.none { convOf(it) == conv }
            // A RENEWAL REPLACES (Network): this person's parts of an older copy leave as the newer one arrives.
            for ((old, h) in held.toList()) if (convOf(old) == conv && old != key && generation(h) < head.generation) dropKey(old)
            val now = now()
            val road = mapOf("z" to size.toString(), "bk" to o.optString("bk"), "mref" to o.optString("mref"), "mk" to o.optString("mk"))
            held[key] = Held(k, n, secret, hd, seal, size, now, road = road, roadAt = now)
            roads.remove(key)
            saveHeld()
            first
        }
        say(conv, JSONObject().put("w", "held").put("g", head.generation).put("d", Wire.hex(head.shareDigest)).put("k", k))
        Log.d("Montana", "keep_part held slot=" + k + " of " + n + " bytes=" + size)
        if (first) tell(conv, size)
        changed()
    }
    private fun dropKey(key: String) {   // under the lock
        held.remove(key); roads.remove(key)
        partFile(key)?.delete()
    }
    fun drop(conv: String) {
        val c = convOf(conv)
        val n = synchronized(lock) {
            ensure()
            val keys = held.keys.filter { convOf(it) == c }
            keys.forEach { dropKey(it) }
            if (keys.isNotEmpty()) saveHeld()
            keys.size
        }
        if (n == 0) return
        Log.d("Montana", "keep_drop conv=" + c.take(10) + " parts=" + n)
        changed()
    }
    fun setOthers(on: Boolean) {
        Prefs.setBool(OTHERS, on)
        if (!on) keptFor().forEach { drop(it) }
        changed()
    }
    /** THE PERSON IS TOLD whose part this phone holds and how many bytes, the moment it first holds one (App, «What a client owes the person»). */
    private fun tell(conv: String, bytes: Long) {
        val c = Book.ctx
        val nm = c.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(NotificationChannel("keeping", c.getString(R.string.keep_note_title), NotificationManager.IMPORTANCE_DEFAULT))
        val name = Book.chat(conv)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
        val open = PendingIntent.getActivity(c, 0x6b65, c.packageManager.getLaunchIntentForPackage(c.packageName)?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP) ?: Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, "keeping")
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(c.getString(R.string.keep_note_title))
            .setContentText(c.getString(R.string.keep_note_body, name, android.text.format.Formatter.formatShortFileSize(c, bytes)))   // USER-DATA: a name, a size
            .setStyle(Notification.BigTextStyle().bigText(c.getString(R.string.keep_note_body, name, android.text.format.Formatter.formatShortFileSize(c, bytes))))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        runCatching { nm.notify("keep:" + conv, 1, n) }
    }
    /** The pipes of the slots this phone holds, heard in the box beside every correspondence (Post.fetchOnce). */
    fun listening(): Map<String, ByteArray> {
        if (!agrees) return emptyMap()
        return synchronized(lock) { ensure(); held.entries.associate { PIPE_PREFIX + it.key to it.value.secret } }
    }
    /** A row of the box under the pipe of a slot is this file's own: a call is answered, and the row is in hand either way. */
    fun takes(row: Map<String, String>): Boolean {
        val c = row["c"] ?: return false
        if (!c.startsWith(PIPE_PREFIX)) return false
        val key = c.removePrefix(PIPE_PREFIX)
        if (word(row["t"] ?: "")?.optString("w") == "call") Thread { runCatching { answerCall(key) } }.start()
        return true
    }
    private fun answerCall(key: String) {
        val now = now()
        val h = synchronized(lock) { ensure(); held[key] } ?: return
        val file = partFile(key)
        if (!others || file == null || !file.isFile) return
        if (now - h.answeredAt < 600) return   // a call repeats every two minutes; one answer serves ten
        val r = h.road
        val at = h.roadAt
        val road: JSONObject = if (r != null && at != null && now - at < 6 * 86_400 && r["z"]?.toLongOrNull() == h.bytes) {
            JSONObject().put("z", h.bytes).put("bk", r["bk"] ?: "").put("mref", r["mref"] ?: "").put("mk", r["mk"] ?: "")   // the owner's pieces, alive a week
        } else synchronized(lock) { roads[key]?.takeIf { now - it.first < 86_400 }?.second?.let { JSONObject(it.toString()) } }   // a day's answers share them
            ?: (lay(file) ?: return Unit.also { Log.d("Montana", "keep_answer the part did not reach the nodes") })
                .also { fresh -> synchronized(lock) { roads[key] = now to JSONObject(fresh.toString()) } }
        road.put("w", "answer").put("h", Wire.hex(h.head)).put("e", Wire.hex(h.seal))
        if (!knock(h.secret, road)) { Log.d("Montana", "keep_answer no door boxed it"); return }
        synchronized(lock) { held[key]?.answeredAt = now; saveHeld() }
        Log.d("Montana", "keep_answer slot=" + h.slot + " of " + h.n)
    }
    /** One letter in the pipe of a slot, boxed like every letter of a pipe (iOS knock 815-826): silent, or loud for a keeper whose app the
     *  system does not wake. The sender is the person, or the name a pipe asks for (the pipe of light, a device of the seed). */
    fun knock(secret: ByteArray, o: JSONObject, silent: Boolean = true, sender: String? = null): Boolean {
        val from = sender ?: MontanaSeed.twin ?: return false
        return Post.knockWord(secret, Marks.KEEP + o.toString(), from, silent)
    }

    // ── the correspondence given back (Network «The correspondence given back»; the author's word 08.10.2026 23:5x MSK: «by default
    // every correspondent keeps the conversation with their correspondent and, if it is saved, gives it to the one who restores») ──
    private const val ASKED_BACK = "mt.keep.back.asked"   // NOT-UI: the correspondences this phone asked to give back, and when
    private val answeredBack = HashMap<String, Double>()
    private fun askedBack(): MutableMap<String, Double> =
        runCatching { JSONObject(Prefs.str(ASKED_BACK, "{}")).let { o -> o.keys().asSequence().associateWith { o.optDouble(it, 0.0) }.toMutableMap() } }.getOrNull() ?: mutableMapOf()
    private fun lastLetter(conv: String): Double = (Book.chat(conv)?.msgs?.maxOfOrNull { it.at } ?: 0L) / 1000.0
    /** THE REQUEST (iOS askBack 835-847): once a copy is laid, every correspondence of a person it names is asked in its own pipe, with the
     *  moment of the last letter laid there; the answer is awaited a week, as long as the pieces it rides live. */
    private fun askBack() {
        val now = now()
        val asked = askedBack().filter { now - it.value < 7 * 86_400 }.toMutableMap()
        var n = 0
        for (conv in people()) if (now - (asked[conv] ?: 0.0) >= 600) {
            say(conv, JSONObject().put("w", "back").put("a", lastLetter(conv)))
            asked[conv] = now; n++
        }
        Prefs.setStr(ASKED_BACK, JSONObject(asked as Map<*, *>).toString())
        Log.d("Montana", "keep_back asked=" + n)
    }
    /**
     * THE ANSWER (iOS answerBack 848-878): the letters of this correspondence this phone holds, later than the asker's last, on the cargo
     * road and named in the same correspondence -- nothing kept for the purpose, nothing but this correspondence, and nothing while the
     * person keeps nothing for others. A letter of the asker rides with the author field it came with: their phone names it theirs by
     * their own key, never by this phone's word.
     */
    private fun answerBack(conv: String, o: JSONObject) {
        val now = now()
        if (!others || now - (synchronized(answeredBack) { answeredBack[conv] } ?: 0.0) < 600) { Log.d("Montana", "keep_back quiet conv=" + conv.take(10)); return }
        synchronized(answeredBack) { answeredBack[conv] = now }
        val since = o.optDouble("a", 0.0)
        val rows = Book.chat(conv)?.msgs.orEmpty().filter { it.at / 1000.0 > since && it.text.isNotEmpty() && !Marks.isService(it.text) && it.file == null }
        if (rows.isEmpty()) { say(conv, JSONObject().put("w", "given").put("c", 0)); return }
        val list = JSONArray()
        for (r in rows) {
            val e = JSONObject().put("i", if (r.mid.contains(':')) r.mid else "mid:" + r.mid).put("m", if (r.mine) 1 else 0).put("t", r.at / 1000.0).put("x", r.text)
            if (!r.mine) r.au?.takeIf { it.isNotEmpty() }?.let { e.put("a", it) }
            list.put(e)
        }
        val dir = work() ?: return
        val f = File(dir, java.util.UUID.randomUUID().toString() + ".given")
        try {
            val body = list.toString().toByteArray(Charsets.UTF_8)
            f.writeBytes(body)
            val digest = digestOf(f)
            val road = if (digest != null) lay(f) else null
            if (digest == null || road == null) { Log.d("Montana", "keep_back the letters did not reach the nodes"); return }
            road.put("w", "given").put("c", rows.size).put("d", digest)
            say(conv, road)
            Log.d("Montana", "keep_back gave=" + rows.size + " bytes=" + body.size + " conv=" + conv.take(10))
        } finally { f.delete() }
    }
    /**
     * THE CORRESPONDENCE TAKEN BACK (iOS takeGiven 879-914): only an answer to this phone's own request, only the letters later than the
     * last one in that correspondence here -- a letter erased before the copy stays erased -- each on the side of the one who wrote it.
     * WHICH LETTER IS MINE IS SAID BY MY OWN WORDS (the critic R-6): a letter they name as theirs is theirs; one they name as mine stands
     * as mine only when the author field it rode with is made again under this person's key -- else it is not laid at all.
     */
    private fun takeGiven(conv: String, o: JSONObject) {
        val at = askedBack()[conv] ?: return
        if (now() - at >= 7 * 86_400 || o.optInt("c", 0) <= 0) return
        val d = o.optString("d").ifEmpty { null } ?: return
        val dir = work() ?: return
        val f = File(dir, java.util.UUID.randomUUID().toString() + ".given")
        try {
            val list = if (fetch(o, f) && digestOf(f) == d) runCatching { JSONArray(String(f.readBytes(), Charsets.UTF_8)) }.getOrNull() else null
            if (list == null) { Log.d("Montana", "keep_back the given letters did not come whole"); return }
            val secret = Book.secret(conv)
            val key = MontanaSeed.authorKey?.takeIf { Wire.authorAgreesWithCanon }
            // The copies' last letter is the last one older than the request: a letter that came live after it is no measure.
            val since = (Book.chat(conv)?.msgs.orEmpty().filter { it.at / 1000.0 < at }.maxOfOrNull { it.at } ?: 0L) / 1000.0
            var unproven = 0
            val rows = ArrayList<Msg>()
            for (i in 0 until list.length()) {
                val e = list.optJSONObject(i) ?: continue
                val t = e.optDouble("t", 0.0); val x = e.optString("x")
                if (t <= since || x.isEmpty()) continue
                val wire = e.optString("i").ifEmpty { null }
                val claimedMine = e.optInt("m", 0) == 0   // the other side's own letter is the other side's here
                if (claimedMine) {
                    val bare = wire?.removePrefix("mid:") ?: ""
                    if (bare.isEmpty() || secret == null || !Wire.authorHolds(e.optString("a"), key, secret, bare, x)) { unproven++; continue }
                }
                val name = RESTORED_GIVEN + (wire?.removePrefix("mid:") ?: t.toString())
                rows.add(Msg(name, x, claimedMine, (t * 1000).toLong(), state = if (claimedMine) 1 else 3))
            }
            val laid = Book.layGivenBack(conv, rows)
            Log.d("Montana", "keep_back took=" + laid + " of " + list.length() + " unproven_mine=" + unproven + " conv=" + conv.take(10))
        } finally { f.delete() }
    }
    /** A given-back row's name on this phone, never on the wire (iOS MTRestoredMid.given). */
    const val RESTORED_GIVEN = "given:"

    // ── a phone that opened the words ──
    /**
     * THE COPY TAKEN BACK FROM THE PEOPLE ONE WRITES TO (iOS takeBack 916-1027): the pipe of every slot is called, every answer's seal is
     * checked against the words, and the copy of the highest generation whose every group stands is built, checked against its digest
     * and laid by the one road of a copy (MontanaBackup.restore). The calls repeat every two minutes; the walk ends with the copy laid,
     * or after six hours without one.
     */
    fun takeBack(done: (CopyResult) -> Unit = {}) {
        if (takingThread != null) return
        stopped = false
        takingThread = Thread {
            val r = runCatching { callAndBuild() }.getOrElse { Log.w("Montana", "keep_take " + it.javaClass.simpleName); taking = Taking.Failed; CopyResult.Refused(Refusal.Unopened) }
            takingThread = null
            changed()
            done(r)
        }.apply { isDaemon = true; start() }
        changed()
    }
    fun stopTaking() {
        stopped = true
        takingThread?.interrupt()
        if (taking is Taking.Calling) taking = Taking.Idle
    }
    val isTaking: Boolean get() = takingThread != null

    private class Answer(val head: KeepDerive.Head, val file: File)
    private fun callAndBuild(): CopyResult {
        val m = MontanaSeed.mnemonic
        val master = m?.let { MtBindings.nativeMnemonicToMasterSeed(it) }
        val dir = work()
        if (!agrees || master == null || dir == null) { taking = Taking.Failed; return CopyResult.Refused(Refusal.NoSeed) }
        val key = KeepDerive.keepKey(master)
        val secrets = (0 until KeepDerive.SLOTS).mapNotNull { KeepDerive.slotSecret(master, it) }
        val light = KeepDerive.lightSecret(master)
        master.fill(0)
        if (key == null || secrets.size != KeepDerive.SLOTS) { taking = Taking.Failed; return CopyResult.Refused(Refusal.NoSeed) }
        val pipes = secrets.withIndex().associate { CALL_PREFIX + it.index to it.value }
        val answers = HashMap<String, Answer>()
        var lastCall = 0.0
        var lastLoud = 0.0
        val began = now()
        taking = Taking.Fetching(0.0)
        // THE LIGHT COPY FIRST (Network «The light copy»): the pipe of light is read before any call, and the person is let in.
        if (light != null && takeLight(light, dir)) askBack()   // the pipes it named are asked to give back
        taking = Taking.Calling(0, 0)
        try {
            while (!stopped) {
                val now = now()
                if (now - lastCall >= 120) {
                    lastCall = now
                    var boxed = 0
                    for (s in secrets) if (knock(s, JSONObject().put("w", "call"))) boxed++
                    Log.d("Montana", "keep_call slots=" + secrets.size + " boxed=" + boxed)
                }
                // IF NEEDED, A LOUD CALL (the author's word 08.10.2026 22:4x MSK): six minutes of silence from a slot, and the call in its
                // pipe rings the keeper's screen with the owner's name, every ten minutes; the slots that answered the newest copy are rung no more.
                if (now - began >= 360 && now - lastLoud >= 600) {
                    lastLoud = now
                    val newest = answers.values.maxByOrNull { it.head.generation }?.head
                    val heard = answers.values.filter { newest != null && it.head.copyDigest.contentEquals(newest.copyDigest) }.map { it.head.slot }.toSet()
                    var rung = 0
                    for (k in 0 until (newest?.n ?: KeepDerive.SLOTS)) if (k !in heard && knock(secrets[k], JSONObject().put("w", "call").put("loud", 1), silent = false)) rung++
                    Log.d("Montana", "keep_call loud rung=" + rung + " heard=" + heard.size)
                }
                val rows = ArrayList<Map<String, String>>()
                Post.pickup(pipes) { row -> rows.add(row); true }
                for (row in rows) {
                    val c = row["c"] ?: continue
                    val k = c.removePrefix(CALL_PREFIX).toIntOrNull() ?: continue
                    val o = word(row["t"] ?: "")?.takeIf { it.optString("w") == "answer" } ?: continue
                    val head = KeepDerive.Head.of(unhex(o.optString("h")))?.takeIf { it.slot == k } ?: continue
                    val seal = unhex(o.optString("e")) ?: continue
                    if (!seal.contentEquals(KeepDerive.seal(key, head))) continue
                    val id = Wire.hex(head.copyDigest) + "." + k
                    if (answers[id] != null) continue
                    val f = File(dir, java.util.UUID.randomUUID().toString() + ".keep")
                    if (!fetch(o, f) || digestOf(f) != Wire.hex(head.shareDigest)) { f.delete(); continue }
                    answers[id] = Answer(head, f)
                    Log.d("Montana", "keep_took slot=" + k + " of " + head.n + " generation=" + head.generation)
                }
                // The copies in hand, the newest first; a copy stands when its parts hold twelve cells of every group.
                val ranked = answers.values.groupBy { Wire.hex(it.head.copyDigest) }.values.sortedByDescending { it.first().head.generation }
                ranked.firstOrNull()?.let { best -> taking = Taking.Calling(best.size, 3 * best.first().head.n / 4) }
                for (parts in ranked) {
                    val h0 = parts.first().head
                    val same = parts.filter { it.head.n == h0.n && it.head.length == h0.length }
                    if (same.size * (KeepCode.GROUP / h0.n) < KeepCode.DATA) continue
                    val out = File(dir, java.util.UUID.randomUUID().toString() + ".mtbak")
                    try {
                        val built = KeepCode.rebuild(same.map { KeepCode.Part(it.head.slot, it.head.n, it.file) }, h0.length, out)
                        if (!built || digestOf(out) != Wire.hex(h0.copyDigest)) { Log.d("Montana", "keep_build generation=" + h0.generation + " did not stand"); continue }
                        taking = Taking.Laying(0.0)
                        val r = MontanaBackup.restore(Book.ctx, out) { taking = Taking.Laying(it) }
                        reread()   // the copy laid this person's state of keeping too
                        if (r is CopyResult.Taken) {
                            Archive.restoreAndWait()
                            synchronized(lock) { owner.generation = maxOf(owner.generation, h0.generation); saveOwner() }
                            askBack()   // the pipes the full copy named, the ones the light copy did not already ask
                            taking = Taking.Done
                        } else taking = Taking.Failed
                        Log.d("Montana", "keep_build generation=" + h0.generation + " laid=" + r.javaClass.simpleName)
                        return r
                    } finally { out.delete() }
                }
                if (now() - began > 6 * 3600) { taking = Taking.Failed; return CopyResult.Refused(Refusal.Empty) }
                try { Thread.sleep(15_000) } catch (e: InterruptedException) { break }
            }
        } finally { answers.values.forEach { it.file.delete() } }
        taking = Taking.Idle
        return CopyResult.Refused(Refusal.Stopped)
    }

    /** The one share of the copy's road (iOS keepShare, MontanaSettings 2418-2427): the light copy coming down is the first half, its
     *  laying the second; the parts in hand count the first half while no light copy comes. */
    fun share(): Double? = when (val t = taking) {
        is Taking.Fetching -> t.f / 2
        is Taking.Calling -> if (0 < t.need) minOf(1.0, t.have.toDouble() / t.need) / 2 else null
        is Taking.Laying -> 0.5 + t.f / 2
        else -> null
    }
}

/**
 * THE KEEPING IN DATA AND STORAGE (iOS MTKeepingSection 1086-1151): two switches, what a keeper learns said beneath them, the state in
 * the keepers' own words (a part is «held» only on its keeper's «held»), the parts this phone holds by name and size, and the road back.
 */
fun LinearLayout.keepingSection(act: MainActivity) {
    val c: Context = act
    val state = c.text("", 15f, MT.gray).apply { setPadding(dp(16), dp(10), dp(16), dp(12)) }
    var draw: () -> Unit = {}
    val mineLine = c.switchLine(R.drawable.ic_app_groups, SysColor.teal, c.getString(R.string.keep_mine), Keeping.mine) { Thread { Keeping.setMine(it) }.start() }
    section(c.getString(R.string.keep_header), c.getString(R.string.keep_explained), mineLine, state)
    val people = c.vstack(Gravity.NO_GRAVITY) {}
    val backWord = c.text("", 15f, MT.gray).apply { setPadding(dp(16), dp(10), dp(16), dp(12)) }
    val bar = ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 100; progressTintList = ColorStateList.valueOf(Color.WHITE); setPadding(dp(16), dp(10), dp(16), dp(12))
    }
    val take = c.settingsRow(R.drawable.ic_arrow_circle_down, SysColor.blue, c.getString(R.string.keep_take_back), chevron = false) { if (!Keeping.isTaking) Keeping.takeBack() }
    section(null, c.getString(R.string.keep_others_footer),
        c.switchLine(R.drawable.ic_tray_full_fill, SysColor.gray, c.getString(R.string.keep_others), Keeping.others) { Thread { Keeping.setOthers(it) }.start() },
        people, take, backWord, bar)
    draw = {
        val o = Keeping.ownerNow()
        state.visibility = if (Keeping.mine) View.VISIBLE else View.GONE
        state.text = when {
            o.asking != null -> c.getString(R.string.keep_asking)
            o.keepers.isEmpty() -> c.getString(if (o.short) R.string.keep_nobody_yet else R.string.keep_not_yet)
            else -> c.getString(R.string.keep_kept_by, o.keepers.values.count { it.held }, o.keepers.size)
        }
        people.removeAllViews()
        for (conv in Keeping.keptFor()) {   // one row a person, their parts summed
            people.addView(c.hstack {
                setPadding(dp(16), dp(12), dp(16), dp(12))
                addView(c.text(Book.chat(conv)?.shown ?: "", 16f, Color.WHITE), lp(0, WRAP, 1f))   // USER-DATA: a correspondent's name
                addView(c.text(android.text.format.Formatter.formatShortFileSize(c, Keeping.bytes(conv)), 15f, MT.gray))   // USER-DATA: a size
                setOnLongClickListener {
                    AlertDialog.Builder(act).setMessage(R.string.keep_stop_part)
                        .setPositiveButton(R.string.keep_stop_part) { _, _ -> Thread { Keeping.drop(conv) }.start() }
                        .setNegativeButton(R.string.cancel, null).show()
                    true
                }
            }, lp())
        }
        take.alpha = if (Keeping.isTaking) 0.4f else 1f
        val t = Keeping.taking
        backWord.visibility = View.VISIBLE
        bar.visibility = View.GONE
        when (t) {
            is Keeping.Taking.Calling -> backWord.text = if (t.need > 0) c.getString(R.string.keep_parts_in_hand, t.have, t.need) else c.getString(R.string.keep_restoring_chain)
            is Keeping.Taking.Fetching -> { backWord.visibility = View.GONE; bar.visibility = View.VISIBLE; bar.progress = (t.f * 100).toInt() }
            is Keeping.Taking.Laying -> { backWord.visibility = View.GONE; bar.visibility = View.VISIBLE; bar.progress = (t.f * 100).toInt() }
            Keeping.Taking.Done -> backWord.text = c.getString(R.string.keep_came_back)
            Keeping.Taking.Failed -> backWord.text = c.getString(R.string.keep_none_came_back)
            Keeping.Taking.Idle -> backWord.visibility = View.GONE
        }
    }
    draw()
    val heard: () -> Unit = { if (isAttachedToWindow) draw() }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Keeping.listen(heard); draw() }
        override fun onViewDetachedFromWindow(v: View) { Keeping.unlisten(heard) }
    })
}
