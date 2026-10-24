package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

// ─────────────────────────── the book rides the seed (iOS MTCoinVault, MTWalletCore.swift:984-1206) ───────────────────────────

/** Where the vault's questions go: a door's /vault-get and /vault-put over HTTPS -- or a node on this phone (CoinLocalTest). */
fun interface VaultDoor { fun post(door: String, path: String, body: JSONObject, timeoutMs: Int): Pair<Int, JSONObject?> }

/** The book the vault gathers into and lays from: the phone's own (CoinBook), or a test's. */
interface VaultBook {
    /** One more at every person's change (iOS MTCoinBook.generation): a gather that waited across it writes nothing. */
    val generation: Int
    fun all(): List<CoinEntry>
    fun join(moves: List<CoinEntry>): Int
}

/**
 * THE BOOK RIDES THE SEED (iOS MTCoinVault; the author's words 04.10.2026 13:36-13:42 MSK: «I must log in by my seed on another device
 * and my balance must surely be kept -- the critical part»; «the book by the seed on the nodes»). Every move of the book is sealed under a
 * key only the words derive -- ChaCha20-Poly1305 over Apple's LZFSE of the moves' JSON, bound to «mt.coins.vault» -- and laid on every
 * node in pieces; any device with the same words gathers the union of all of them: a move is its name, so the union is the book, the
 * same on the iPhone and here. Every node holds two rows of the seed: its own (a token only that node's host makes, so no node can empty
 * the book on another) and the common one. Until a node has answered in this run (heard), the phone holds its own share alone: the
 * chain's GENESIS, laid once ever, waits for it (CoinClient.reconcile).
 */
object CoinVault {
    private val keyLabel = "mt-coins-vault-key-v1".toByteArray()      // NOT-UI: the seal's derivation label
    private val ownerLabel = "mt-coins-vault-owner-v1".toByteArray()  // NOT-UI: the row's derivation label
    private val tokenLabel = "mt-coins-vault-token".toByteArray()     // NOT-UI: the token's own label
    private val aad = "mt.coins.vault".toByteArray()                  // NOT-UI: the words the seal is bound to
    private val tipLabel = "mt-timechain-tip-token".toByteArray()     // NOT-UI: the tips' row label (iOS MTTimeChainTip)
    private val nodeLabel = "mt-coins-vault-node-v1".toByteArray()    // NOT-UI: a node's own row label (iOS nodeToken)
    /** How many pieces a node keeps for a seed before the whole book is laid there as one; a piece carries `SPAN` moves at most. */
    const val FOLD = 192
    const val SPAN = 8000

    class Keys(val seal: ByteArray, val token: ByteArray, val tip: ByteArray)
    /** iOS keys: the seal and the owner key by HKDF-SHA-256 of the entropy (salt empty), the tokens by HMAC-SHA-256 under the owner key. */
    fun keys(entropy: ByteArray): Keys {
        val owner = ownerKey(entropy)
        return Keys(Hkdf.sha256(entropy, ByteArray(0), keyLabel), Hkdf.hmac(owner, tokenLabel), Hkdf.hmac(owner, tipLabel)).also { owner.fill(0) }
    }
    private fun ownerKey(entropy: ByteArray) = Hkdf.sha256(entropy, ByteArray(0), ownerLabel)
    /** EVERY NODE HOLDS THE BOOK UNDER A ROW OF ITS OWN (iOS nodeToken, the author's words 06.10.2026: «close the double spends»): HMAC-SHA-256
     *  under the owner key over the label and the node's host -- a node learns its own row and no other. */
    fun nodeToken(entropy: ByteArray, host: String): ByteArray {
        val owner = ownerKey(entropy)
        return Hkdf.hmac(owner, nodeLabel + host.toByteArray()).also { owner.fill(0) }
    }

    /**
     * THE TAG OF A PAIR ONLY THE SAME WORDS MAKE (iOS ownTag, MTWalletCore.swift:1029-1037; MTOwnWords): HMAC-SHA-256 under the owner key
     * over «mt-own-words-v1» and the conversation's name. A pair of other words reads 32 bytes it can neither check nor tie to anything.
     */
    private val ownLabel = "mt-own-words-v1".toByteArray()   // NOT-UI: the own-words tag's label
    fun ownTag(entropy: ByteArray, conv: String): ByteArray {
        val owner = ownerKey(entropy)
        return Hkdf.hmac(owner, ownLabel + conv.toByteArray()).also { owner.fill(0) }
    }
    fun ownTagHolds(tag: ByteArray, entropy: ByteArray, conv: String): Boolean =
        java.security.MessageDigest.isEqual(tag, ownTag(entropy, conv))
    /**
     * THE PERSON'S ROW (iOS personRow, MTWalletCore.swift:1025-1028): the coin vault's own seal and one token for every door --
     * HMAC-SHA-256 under the owner key over «mt-person-chain-token» -- where each device of the words lays its seconds (PersonChain).
     */
    private val personLabel = "mt-person-chain-token".toByteArray()   // NOT-UI: the person row's label
    fun personRow(entropy: ByteArray): Pair<ByteArray, ByteArray> {
        val owner = ownerKey(entropy)
        return (Hkdf.sha256(entropy, ByteArray(0), keyLabel) to Hkdf.hmac(owner, personLabel)).also { owner.fill(0) }
    }
    /** The seed's entropy as the vault's live client reads it (iOS MontanaSeedKeys.entropyFrom): 32 bytes, or none. */
    fun entropy(): ByteArray? = MontanaSeed.mnemonic?.let { MtBindings.nativeMnemonicToEntropy(it) }?.takeIf { it.size == 32 }

    /** THE FROZEN VECTORS (iOS keyKAT: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting bytes 0x00..0x1f). */
    fun keyKAT(): Boolean {
        val counting = ByteArray(32) { it.toByte() }
        val k = keys(counting)
        // the own-words tags computed outside this code (Python hmac/hashlib, the same HKDF that reproduces iOS's frozen vectors)
        val own = Base64.encodeToString(ownTag(counting, "00112233445566778899aabbccddeeff"), Base64.NO_WRAP) == "Pnl5OKsb1OxRGCJeYypbI6AzOqFlpr6+kdJ+Zag5YE0="
            && Base64.encodeToString(ownTag(counting, "0123456789abcdef0123456789abcdef"), Base64.NO_WRAP) == "aqgIboGde1yGotSaWzsJJY5baUE+YmnLaW6LMLzfE/U="
        return Wire.hex(k.seal) == "e9720340e7dcb4b6c2befea9a657718560646f727614f732971bf9ea7d3795fb"
            && Wire.hex(k.token) == "4b7fc64e903945bee08b4fc45f7ca094d9b61ae2c96f4d97ebd1ccd8b4b9ab86"
            && Wire.hex(Wire.sha(k.token)) == "9e34605e5200c5f339f4a527f0654af5436a96b629f66835f91495b65e0ba245" && own
    }

    private fun cipher(mode: Int, key: ByteArray, nonce: ByteArray, at: Int = 0): Cipher =
        Cipher.getInstance("ChaCha20/Poly1305/NoPadding").apply { init(mode, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce, at, 12)); updateAAD(aad) }
    /** iOS seal: the moves' JSON array, packed by LZFSE, sealed by ChaChaPoly and laid combined -- nonce 12, ciphertext, tag 16. */
    fun seal(moves: List<CoinEntry>, key: ByteArray): ByteArray? = runCatching {
        val plain = JSONArray().apply { for (m in moves) put(m.json()) }.toString().toByteArray(Charsets.UTF_8)
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        nonce + cipher(Cipher.ENCRYPT_MODE, key, nonce).doFinal(Lzfse.encode(plain))
    }.getOrNull()
    /** iOS open: a piece that will not open, or holds one move this build cannot read, is no piece -- it is skipped whole. */
    fun open(sealed: ByteArray, key: ByteArray): List<CoinEntry>? = runCatching {
        if (sealed.size < 12 + 16) return null
        val packed = cipher(Cipher.DECRYPT_MODE, key, sealed).doFinal(sealed, 12, sealed.size - 12)
        val arr = JSONArray(String(Lzfse.decode(packed) ?: return null, Charsets.UTF_8))
        List(arr.length()) { i -> CoinEntry.of(arr.getJSONObject(i)) ?: return null }
    }.getOrNull()

    // THE PACKING'S FROZEN VECTORS (computed outside this code: the lzfse 1.0 reference CLI, Python's cryptography for RFC 8439): two
    // moves packed as one LZVN block, 4 096 bytes packed as a bvx2 block with its tables, and the AEAD of RFC 8439 section 2.8.2
    private const val SMALL = "[{\"k\":\"earn\",\"c\":13,\"ref\":\"tap:w1760000000000-3B1F2D4C-0A1B-4C2D-8E3F-405162738495\",\"at\":1760000000.5}," +
        "{\"k\":\"send\",\"c\":7,\"ref\":\"tx:2dd4cf64695222b31d4cd0c799a1f21888aaacb83bab7febfce055f6b7da46fa\",\"peer\":\"ab12\",\"at\":1760000001.25}]"
    private const val SMALL_LZVN = "6276786ee7000000ce000000e0085b7b226b223a226561726e222c2263223a31332c227265660014e97461703a77313736303001e0152d3342" +
        "3146324434432d304131422d344332442d384533462d3430353136323733383439350047e46174223a3839e42e357d2c1866e473656e64f6686537f1e003783a3264" +
        "643463663634363935323232623331000fe01c64306337393961316632313838386161616362383362616237666562666365303535663662376461343666610052e4" +
        "70656572004de461623132387ff6e6312e32357d5d060000000000000062767824"
    private const val ABC_LZFSE = "6276783200100000040010000003005000000830000c0070880000003790b00de7d75c030000005c03000000c04ff03e7c0f7c0f0000000000000000" +
        "000000000000000000000000000000000000000000000000000000000000003c7a8fcea3030000000000000000000000000000000000000000000000" +
        "00000000000000000000000000000000000000000000000000a8b1f97f62767824"
    private const val RFC_SEALED = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b" +
        "2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691"
    fun packKAT(): Boolean {
        val small = CoinRules.bytes(SMALL_LZVN)?.let { Lzfse.decode(it) } ?: return false
        val abc = ByteArray(4096) { "abc"[it % 3].code.toByte() }
        val big = CoinRules.bytes(ABC_LZFSE)?.let { Lzfse.decode(it) } ?: return false
        val rfcKey = ByteArray(32) { (0x80 + it).toByte() }
        val rfc = Cipher.getInstance("ChaCha20/Poly1305/NoPadding").run {
            init(Cipher.ENCRYPT_MODE, SecretKeySpec(rfcKey, "ChaCha20"), IvParameterSpec(CoinRules.bytes("070000004041424344454647")))
            updateAAD(CoinRules.bytes("50515253c0c1c2c3c4c5c6c7"))
            doFinal("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".toByteArray())
        }
        val moves = JSONArray(SMALL).let { a -> List(a.length()) { CoinEntry.of(a.getJSONObject(it)) ?: return false } }
        val key = Wire.sha("montana android coin vault pack check".toByteArray())
        val back = seal(moves, key)?.let { open(it, key) } ?: return false
        return String(small, Charsets.UTF_8) == SMALL && big.contentEquals(abc) && Wire.hex(rfc) == RFC_SEALED
            && back.map { it.line() } == moves.map { it.line() } && open(seal(moves, key)!!, Wire.sha(key)) == null
            && Lzfse.decode(Lzfse.encode(small))?.contentEquals(small) == true && Lzfse.decode(Lzfse.encode(big))?.contentEquals(big) == true
    }
    /** Nothing is gathered or laid unless the frozen vectors reproduce on this phone: a book sealed under another key is a book lost. */
    val agrees: Boolean by lazy {
        val k = runCatching { keyKAT() }.getOrDefault(false)
        val p = runCatching { packKAT() }.getOrDefault(false)
        Log.d("Montana", "coins_vault canon keys=" + (if (k) "ok" else "DISAGREE") + " pack=" + (if (p) "ok" else "DISAGREES"))
        k && p
    }

    // ── the phone's own vault: the network's doors that hold it, one per machine, the phone's book, the person's words ──
    val live = VaultClient(HttpVault, PhoneVaultBook, { Doors.onePerNode(Doors.ordered("vault")) },
        { MontanaSeed.mnemonic?.let { MtBindings.nativeMnemonicToEntropy(it) }?.takeIf { it.size == 32 } })
    /** A node answered this seed's book since the launch or the person's change. */
    val heard: Boolean get() = live.heard
    /** The person left: the vault's memory leaves with them (iOS forget). */
    fun forget() { retryS = 0; live.forget() }

    private var running = false
    private var again = false
    private var dueAt = Long.MAX_VALUE
    private var retryS = 0   // the wait before asking again while no node has answered: 15 s, doubled, five minutes at most
    /** A gathering soon (iOS soon): the moves of a minute ride one piece, never one each; the nearest ask wins. */
    fun soon(why: String, afterS: Int = 60) {
        val wait = afterS * 1000L
        val at = System.currentTimeMillis() + wait
        synchronized(this) { if (dueAt <= at) return; dueAt = at }
        MainThread.later(wait, Runnable {
            synchronized(this) { if (dueAt != at) return@Runnable; dueAt = Long.MAX_VALUE }
            Thread { gather(why) }.start()
        })
    }
    private fun gather(why: String) {
        synchronized(this) { if (running) { again = true; return }; running = true }
        val was = live.heard
        try { if (agrees) live.gather(why) }
        catch (e: Exception) { Log.w("Montana", "coins_vault why=$why " + e.javaClass.simpleName) }
        finally { if (synchronized(this) { running = false; again.also { again = false } }) soon("again", 1) }
        if (!was && live.heard) {
            MainThread.post { CoinBook.listeners() }   // the wallet says the book is the seed's now
            ChatMint.sweepPairs()   // the pairs' letters that landed before the book was heard mint now (iOS MTWalletCore.swift:1130-1136)
        }
        // WORDS RESTORED FIND THEIR BOOK (the owner's word 17.10.2026: «restoring my 24 words must first load the existing coin book»):
        // until a node has answered, the vault is asked again -- a quarter of a minute, then twice as long each time, five minutes at most
        if (agrees && !live.heard && MontanaSeed.mnemonic != null) {
            retryS = if (retryS == 0) 15 else minOf(300, retryS * 2)
            soon("retry", retryS)
        } else retryS = 0
    }
}

/**
 * ONE SEED'S GATHERING (iOS MTCoinVault.gather): every door's two rows asked for the pieces this phone has not opened yet; the moves of
 * every piece that opens joined into the book by their names; then every row that answered is sent the moves its pieces lack -- or, past
 * FOLD pieces or after a refusal as full, the whole book anew, the old pieces it read going with the last new one. A piece that would not
 * open stays on its node. The phone's own client is CoinVault.live; CoinLocalTest walks this same code against nodes in memory.
 */
class VaultClient(private val door: VaultDoor, private val book: VaultBook, private val doors: () -> List<String>,
                  private val entropy: () -> ByteArray?) {
    @Volatile var heard = false
        private set
    @Volatile private var heardAt = 0L
    /** The seed's union was gathered within half a minute. */
    val fresh: Boolean get() = heard && System.currentTimeMillis() - heardAt < 30_000L
    private val pieces = ConcurrentHashMap<String, Set<String>>()   // a piece's name -> the names of the moves it carries, opened once
    private val held = ConcurrentHashMap<String, List<String>>()     // a row -> the pieces its node said it keeps
    private val full: MutableSet<String> = ConcurrentHashMap.newKeySet()   // the rows that refused a piece as full: laid whole next
    fun forget() { heard = false; heardAt = 0L; pieces.clear(); held.clear(); full.clear() }

    private class Row(val slot: String, val door: String, val token: String)
    class Gathered(val rows: Int, val answered: Int, val got: Int, val joined: Int, val laid: Int, val whole: Int, val moves: Int)

    /** The person changed while the gather waited (iOS moved): nothing of the person who left is written or kept. */
    private fun moved(gen: Int, why: String): Boolean {
        if (gen == book.generation) return false
        Log.d("Montana", "coins_vault why=$why the person changed -- the gather writes nothing")
        return true
    }

    fun gather(why: String): Gathered? {
        val e = entropy() ?: return null
        val ds = doors()
        if (e.size != 32 || ds.isEmpty()) { e.fill(0); return null }
        val k = CoinVault.keys(e)
        val gen = book.generation
        // every node's two rows (iOS rows): its own first, then the common one
        val rows = ds.flatMap { d ->
            listOf(Row("$d#own", d, Wire.hex(CoinVault.nodeToken(e, android.net.Uri.parse(d).host ?: d))), Row(d, d, Wire.hex(k.token)))
        }
        e.fill(0)
        try { return gatherRows(why, k.seal, gen, rows) } finally { k.seal.fill(0) }
    }

    private fun gatherRows(why: String, seal: ByteArray, gen: Int, rows: List<Row>): Gathered? {
        val answered = ArrayList<String>()
        val got = ArrayList<CoinEntry>()
        for (r in rows) {
            val have = JSONArray(pieces.keys.take(256))
            val (code, o) = door.post(r.door, "/vault-get", JSONObject().put("token", r.token).put("have", have), 20_000)
            val ids = o?.optJSONArray("held")
            if (code != 200 || ids == null) continue
            if (moved(gen, why)) return null
            val list = o.optJSONArray("pieces") ?: JSONArray()
            for (i in 0 until list.length()) {
                val x = list.optJSONObject(i) ?: continue
                val id = x.optString("piece")
                val b = runCatching { Base64.decode(x.optString("blob"), Base64.DEFAULT) }.getOrNull() ?: continue
                if (id.isEmpty() || Wire.hex(Wire.sha(b)) != id) continue   // a piece is its own name
                val moves = CoinVault.open(b, seal) ?: continue
                pieces[id] = moves.map { it.id }.toSet()
                got.addAll(moves)
            }
            held[r.slot] = (0 until ids.length()).map { ids.optString(it) }.filter { it.isNotEmpty() }
            answered.add(r.slot)
        }
        if (answered.isEmpty() || moved(gen, why)) return null
        heard = true
        heardAt = System.currentTimeMillis()
        val joined = book.join(got)
        val all = book.all()
        var laid = 0
        var whole = 0
        for (slot in answered) {
            val r = rows.firstOrNull { it.slot == slot } ?: continue
            val ids = held[slot].orEmpty()
            val carried = HashSet<String>()
            for (id in ids) pieces[id]?.let { carried.addAll(it) }
            val anew = CoinVault.FOLD <= ids.size || slot in full
            val lacking = if (anew) all else all.filter { it.id !in carried }
            if (lacking.isEmpty()) continue
            // ONLY A PIECE READ HERE IS REPLACED (iOS, the coin audit's third point, 05.10.2026): a piece that would not open -- a book of a
            // later build, a broken blob -- or whose moves the book did not take stays on the node, beside the whole
            val inBook = if (anew) all.map { it.id }.toHashSet() else emptySet()
            var replace = if (anew) ids.filter { id -> pieces[id]?.let { inBook.containsAll(it) } ?: false } else emptyList()
            var start = 0
            while (start < lacking.size) {
                val part = lacking.subList(start, minOf(start + CoinVault.SPAN, lacking.size))
                // THE OLD PIECES GO WITH THE LAST NEW ONE (iOS, the coin audit's sixth point): every part is laid first
                val last = lacking.size <= start + CoinVault.SPAN
                val sealed = CoinVault.seal(part, seal) ?: break
                if (moved(gen, why)) return null
                val (code, o) = door.post(r.door, "/vault-put", JSONObject().put("token", r.token).put("blob", Base64.encodeToString(sealed, Base64.NO_WRAP))
                    .put("replace", JSONArray(if (last) replace else emptyList())), 30_000)
                if (moved(gen, why)) return null   // the old seed's own book went to its own row; nothing more is kept here
                if (code == 413) { full.add(slot); break }
                val id = o?.optString("piece").orEmpty()
                if (code != 200 || id.isEmpty()) break
                pieces[id] = part.map { it.id }.toSet()
                val gone = if (last) replace.toSet() else emptySet()
                held[slot] = held[slot].orEmpty().filter { it !in gone } + id
                if (last) replace = emptyList()
                laid += part.size
                if (anew) whole++
                start += CoinVault.SPAN
            }
            if (anew && 0 < whole) full.remove(slot)
        }
        val keep = held.values.flatten().toHashSet()
        pieces.keys.retainAll(keep)   // a piece no node keeps is forgotten here too
        Log.d("Montana", "coins_vault why=$why rows=${answered.size}/${rows.size} got=${got.size} joined=$joined laid=$laid whole=$whole moves=${all.size}")
        return Gathered(rows.size, answered.size, got.size, joined, laid, whole, all.size)
    }
}

/** The phone's book as the vault sees it. */
object PhoneVaultBook : VaultBook {
    override val generation: Int get() = CoinBook.generation
    override fun all(): List<CoinEntry> = CoinBook.all()
    override fun join(moves: List<CoinEntry>): Int = CoinBook.join(moves)
}

/** The vault's doors over HTTPS (iOS MTCoinVault.post): the code and the JSON the node answered, -1 when it did not. */
object HttpVault : VaultDoor {
    override fun post(door: String, path: String, body: JSONObject, timeoutMs: Int): Pair<Int, JSONObject?> {
        var conn: HttpURLConnection? = null
        return try {
            val raw = body.toString().toByteArray(Charsets.UTF_8)
            conn = (URL(door + path).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"; doOutput = true; connectTimeout = timeoutMs; readTimeout = timeoutMs
                setRequestProperty("content-type", "application/json"); setFixedLengthStreamingMode(raw.size)
            }
            conn.outputStream.use { it.write(raw) }
            val code = conn.responseCode
            // a node's answer is a second of the person on the network (iOS MTCoinVault.post → MTPersonChain.answered)
            runCatching { conn.getHeaderFieldDate("Date", 0L) }.getOrDefault(0L).takeIf { 0L < it }?.let { PersonChain.answered(it) }
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.use { it.readBytes().toString(Charsets.UTF_8) }
            code to text?.let { runCatching { JSONObject(it) }.getOrNull() }
        } catch (_: Exception) { -1 to null } finally { conn?.disconnect() }
    }
}
