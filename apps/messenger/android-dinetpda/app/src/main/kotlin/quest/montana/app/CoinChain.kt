package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

// THE COIN CHAINS OF VERSION 3 (iOS MTCoinChainRules, MTCoinTx, MTCoinReplica, MTWalletCore.swift 3280-4209; Audit/App/
// COIN-TX-V3.md; the author's words 11.10.2026 22:5x MSK, No.64: «balances must be proven ... the Explorer shows the proof of it
// locally and globally across the network»). Every move of a key's balance is a signed record of the key's chain: coins enter a
// key only by a record (MINT, RECV, REFUND) and leave only by one (SEND); the chain's node folds the chain and refuses what it does
// not prove. A record is 5443 bytes, signed by the seed's coin key (HKDF-Expand of the master seed under «mt-coin-tx» into
// ML-DSA-65), and lives on one node of the fixed table at the index of its key tag's first byte.
//
// NOTHING IS LAID ON THE LIVE LOG FROM THIS BUILD (the owner's decision 17.10.2026: built and checked locally; no irreversible test
// coin record goes to the live network without a separate permission): every road that writes -- a record, a claim, a
// holder's signature -- stands behind CoinTx.WRITES; what reads the network (a head, a chain, the logs, a checkpoint's root) runs.

/**
 * THE RULES OF A KEY'S CHAIN, ONE PLACE ON THE PHONE (iOS MTCoinChainRules 3280-3380; COIN-TX-V3 sections 1, 3 and 4): the fields a
 * kind uses, the time a key may mint, the blind and the commitment, and the one step of the fold the nodes, the replicas, the
 * phones and the Explorer all make. tools/coin_vectors.py makes the same values outside both apps.
 */
object CoinRules {
    const val V2_CUT = 1_792_443_600L       // NOT-UI: 20.10.2026 00:00 MSK, the node's TX_V2_CUT (section 8)
    const val COIN_EPOCH = 1_788_210_000L   // NOT-UI: 01.09.2026 00:00 MSK, the node's TX_COIN_EPOCH (section 3)
    /** τ1, the minting's window: the shortest interval a MINT covers and how often the phone asks its chain to take the book's surplus. */
    const val WINDOW = 60L
    val ZERO = "0".repeat(64)
    enum class Kind(val code: Int) {
        SEND(1), RECV(2), MINT(3), REFUND(4), GENESIS(5);
        companion object { fun of(c: Int) = values().firstOrNull { it.code == c } }
    }
    /** A record as the rules read it; a record of the layouts before kinds (version 2) is a send that names no receiver. */
    class Rec(val id: String, val version: Int, val kind: Int, val amount: Long, val from: String, val to: ByteArray, val ref: String, val a: Long, val b: Long)
    /** A key's state folded over its chain (section 3). */
    data class St(val head: String = ZERO, val height: Int = 0, val birth: Long = 0, val mintEnd: Long = 0, val proven: Long = 0,
                  val declared: Long = 0, val v3: Boolean = false, val lastAt: Long = 0, val minted: Long = 0)
    class SendInfo(val from: String, val amount: Long, val at: Long, val to: ByteArray, val dec: Long)

    /** A(x) of section 4: what the seconds 1..x of a key's life may mint -- 2 x min(13, max(1, bit_length(s) - 1)) a second. */
    fun timeA(x: Long): Long {
        var total = 0L; var lo = 1L; var k = 0L
        while (0 < x && lo <= x) {
            val hi = minOf(x, 2 * lo - 1)
            total += (hi - lo + 1) * minOf(13L, maxOf(1L, k))
            lo *= 2; k++
        }
        return 2 * total
    }
    val genesisCap: Long get() = timeA(V2_CUT - COIN_EPOCH)

    /** Section 1: a field its kind does not use is zero; a SEND names its commitment, a RECV and a REFUND the SEND they settle, and the
     *  announced part of a SEND or RECV (t0) is never above its amount. */
    fun fieldsHold(kind: Int, amount: Long, pair: ByteArray, to: ByteArray, ref: ByteArray, a: Long, b: Long): Boolean {
        val none = ByteArray(32)
        return when (Kind.of(kind)) {
            Kind.SEND -> ref.contentEquals(none) && b == 0L && !to.contentEquals(none) && a <= amount
            Kind.RECV -> pair.contentEquals(none) && b == 0L && !ref.contentEquals(none) && a <= amount
            Kind.MINT -> pair.contentEquals(none) && to.contentEquals(none) && ref.contentEquals(none)
            Kind.REFUND -> pair.contentEquals(none) && to.contentEquals(none) && !ref.contentEquals(none) && a == 0L && b == 0L
            Kind.GENESIS -> pair.contentEquals(none) && to.contentEquals(none) && ref.contentEquals(none) && a == 0L && b == 0L
            null -> false
        }
    }
    /** The blind of a SEND: HMAC-SHA-256 under the pair's secret over ASCII mt-coin-blind and the SEND's nonce (section 1). */
    fun blind(secret: ByteArray, nonce: ByteArray): ByteArray = Hkdf.hmac(secret, "mt-coin-blind".toByteArray() + nonce)
    /** The receiver's commitment: SHA-256 of ASCII mt-coin-to, the receiver's from (32 bytes) and the blind (section 1). */
    fun commitment(from: ByteArray, blind: ByteArray): ByteArray = Wire.sha("mt-coin-to".toByteArray(), from, blind)
    fun bytes(s: String): ByteArray? =
        if (s.length % 2 != 0 || s.any { it !in '0'..'9' && it !in 'a'..'f' && it !in 'A'..'F' }) null
        else ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    /**
     * One record folded onto its key's state by the nodes' rules (iOS step 3335-3379): the next state, or null for a record that breaks
     * a rule; `wait` for a RECV or REFUND whose SEND is not folded yet.
     */
    fun step(s: St, p: Rec, at: Long, sends: Map<String, SendInfo>, settled: Set<String>): Pair<St?, Boolean> {
        val first = s.height == 0
        var n = s.copy(head = p.id, height = s.height + 1, lastAt = maxOf(at, s.lastAt),
            birth = if (first) at else s.birth, mintEnd = if (first) at else s.mintEnd)
        val a = p.amount
        if (p.version == 2) {
            // EVERY TRANSFER MOVES ITS BALANCE (section 3, fold-2): after the chain opened, a send that names no receiver spends as a SEND
            if (!s.v3) return n to false
            if (s.proven + s.declared < a) return null to false
            val d = maxOf(0L, a - s.proven)
            return n.copy(proven = s.proven - (a - d), declared = s.declared - d) to false
        }
        n = n.copy(v3 = true)
        when (Kind.of(p.kind)) {
            Kind.GENESIS -> {
                if (s.v3 || (0 < a && V2_CUT <= at) || genesisCap < a) return null to false
                n = n.copy(declared = a)
            }
            Kind.MINT -> {
                val t0 = p.a; val t1 = p.b
                if (first || t0 < s.mintEnd || t1 < t0 + 60 || at < t1) return null to false
                // THE SUM OF TIME (section 4, fold-3): all the key's MINTs together stay under A(t1 - birth)
                if (timeA(t1 - s.birth) - s.minted < a) return null to false
                n = n.copy(proven = s.proven + a, mintEnd = t1, minted = s.minted + a)
            }
            Kind.SEND -> {
                val dec = p.a
                if (s.proven + s.declared < a || dec != maxOf(0L, a - s.proven)) return null to false
                n = n.copy(proven = s.proven - (a - dec), declared = s.declared - dec)
            }
            Kind.RECV, Kind.REFUND -> {
                val S = sends[p.ref] ?: return null to true
                if (S.amount != a || p.ref in settled) return null to false
                if (p.kind == Kind.RECV.code) {
                    val f = bytes(p.from) ?: return null to false
                    if (S.dec != p.a || !commitment(f, p.to).contentEquals(S.to)) return null to false
                } else if (S.from != p.from || at < S.at + 86_400) return null to false
                n = n.copy(proven = s.proven + a - S.dec, declared = s.declared + S.dec)
            }
            null -> return null to false
        }
        return n to false
    }

    /** The root of a checkpoint T (section 6): for every key in ascending from, its last record with at <= T and their count, u64 LE. */
    fun root(order: Map<String, List<String>>, atOf: Map<String, Long>, T: Long): Triple<String, Int, Int> {
        val h = MessageDigest.getInstance("SHA-256")
        h.update("mt-coin-root-v1".toByteArray())
        var keys = 0; var records = 0
        for (from in order.keys.sorted()) {
            val ids = order[from].orEmpty().filter { (atOf[it] ?: Long.MAX_VALUE) <= T }
            val last = ids.lastOrNull() ?: continue
            h.update(bytes(from) ?: continue); h.update(bytes(last) ?: continue); h.update(Wire.le8(ids.size.toLong()))
            keys++; records += ids.size
        }
        return Triple(Wire.hex(h.digest()), keys, records)
    }

    /**
     * SECTION 9's VECTORS THAT NEED NO SIGNATURE (V1, V2, V3, V4, V6), here on the phone: the commitment, the blind, the time a key may
     * mint, a checkpoint's root and the fold of a chain that holds a version 2 record. A drift lays nothing.
     */
    fun agreesWithCanon(): Boolean {
        val from = ByteArray(32) { it.toByte() }
        val bl = ByteArray(32) { (0x20 + it).toByte() }
        if (Wire.hex(commitment(from, bl)) != "b08fb9c67b693f0cfe394de25474d2b79ae990a87a2f6a24bb7727560a8d88a4") return false
        if (Wire.hex(blind(ByteArray(32) { (0x40 + it).toByte() }, ByteArray(16) { (0x60 + it).toByte() })) !=
            "530efcc186fe26cb48fb4023c7a7e884c94516d14e62feaa06e81c76f89d7be4") return false
        val a = mapOf(1L to 2L, 2L to 4L, 3L to 6L, 4L to 10L, 7L to 22L, 8L to 28L, 15L to 70L, 16L to 78L, 8191L to 180230L,
            8192L to 180256L, 8193L to 180282L, 86400L to 2213664L)
        if (a.any { (x, v) -> timeA(x) != v }) return false
        val keys = "abc".associateWith { Wire.hex(Wire.sha("root key $it".toByteArray())) }
        val counts = mapOf('a' to 3, 'c' to 2, 'b' to 1)
        val order = HashMap<String, List<String>>(); val atOf = HashMap<String, Long>()
        for (c in "acb") order[keys.getValue(c)] = (0 until counts.getValue(c)).map { i -> Wire.hex(Wire.sha("root head $c $i".toByteArray())).also { atOf[it] = 100L + i } }
        if (root(order, atOf, 1000).first != "4db30532f47a38696a81aa103cabea16ecf6034934cf26decbb9e78ad848b5e1") return false
        // V6: GENESIS 1000, MINT 500, SEND 1200 (dec 700), a v2 record of 50 -> proven 0, declared 250; a v2 of 251 next -> refused
        val t = 1_792_000_000L
        fun r(v: Int, k: Kind?, amount: Long, x: Long = 0, y: Long = 0) = Rec(Wire.hex(Wire.sha(t.toString().toByteArray(), amount.toString().toByteArray())), v, k?.code ?: 0, amount, "", ByteArray(32), ZERO, x, y)
        var s = step(St(), r(3, Kind.GENESIS, 1000), t, emptyMap(), emptySet()).first ?: return false
        s = step(s, r(3, Kind.MINT, 500, t, t + 300), t + 600, emptyMap(), emptySet()).first ?: return false
        s = step(s, r(3, Kind.SEND, 1200, 700), t + 601, emptyMap(), emptySet()).first ?: return false
        val s2 = step(s, r(2, null, 50), t + 602, emptyMap(), emptySet()).first ?: return false
        if (s2.proven != 0L || s2.declared != 250L) return false
        return step(s2, r(2, null, 251), t + 603, emptyMap(), emptySet()).first == null
    }
}

/**
 * THE COIN RECORD AND ITS NODES (iOS MTCoinTx 3421-3763 and its version 3, 3774-4066): the seed's coin key, the record's bytes and
 * their check by the core, the chain's node of a key, and the node's answers. What the chain is asked and what is laid on it is a
 * client's (CoinClient): the phone's own one, `live`, asks the network and moves the phone's book; a test makes its own.
 */
object CoinTx {
    /**
     * THE OWNER'S GATE (17.10.2026): the build's own flag (res coin_writes). False in the repository and on the test emulators -- no
     * record, claim or holder's signature leaves such a build for the live log; true only in the build made for the owner's own test
     * of the coins (tools/wsl-build.sh apk --coin-writes, Montana-…-coins-…), where the coins work as on iOS.
     */
    val WRITES: Boolean by lazy { runCatching { Book.ctx.resources.getBoolean(R.bool.coin_writes) }.getOrDefault(false) }
    const val SIZE1 = 5330   // version 1, read only (builds 2190 and older)
    const val SIZE2 = 5362   // version 2, read only here (taken by the nodes until the v2 cut)
    const val SIZE3 = 5443   // version 3
    const val REF_PREFIX = "tx:"        // NOT-UI: the book's name of a transfer's moves (iOS refPrefix)
    const val BACK_PREFIX = "txback:"   // NOT-UI: the book's name of a debit no node took (iOS backPrefix)
    const val LINK = "https://montana.xxx/explorer/#tx="   // NOT-UI: the transfer's confirmation link (the Explorer)
    const val EXPLORER = "https://montana.xxx/explorer/"   // NOT-UI: the Explorer's page (iOS MTCoinTx.explorer)
    /** THE CHAINS' NODES: the protocol's two nodes, each with its one door; a key's chain lives on the one at the index of its tag's first byte. */
    val chainNodes = listOf("montana.quest" to "api.montana.quest", "montana.xxx" to "montana.xxx")   // NOT-UI: the protocol's chain set
    private val MAGIC = "MTTX".toByteArray()
    private val SIGNED1 = "mt-coin-tx-v1".toByteArray()
    private val SIGNED2 = "mt-coin-tx-v2".toByteArray()
    private val SIGNED3 = "mt-coin-tx-v3".toByteArray()
    private val PAIR_INFO = "mt-coin-pair-v1".toByteArray()

    class Record(val id: String, val version: Int, val coins: Long, val birthMs: Long, val pair: ByteArray, val prev: String, val from: String,
                 val kind: Int = CoinRules.Kind.SEND.code, val to: ByteArray = ByteArray(32), val ref: String = CoinRules.ZERO,
                 val a: Long = 0, val b: Long = 0, val nonce: ByteArray = ByteArray(0)) {
        fun rule() = CoinRules.Rec(id, version, kind, coins, from, to, ref, a, b)
    }

    // ── the seed's coin key ──
    class Hands(val pk: ByteArray, val sk: ByteArray) { val from: String get() = keyTag(pk) }
    @Volatile private var held: Pair<String, Hands>? = null
    /** The seed's coin key: HKDF-Expand(master_seed, "mt-coin-tx", 32) into ML-DSA-65 -- one on every device of the words, and no
     *  relation to the identity's account key. Held for the run against the digest of the words it came from. */
    fun keys(): Hands? {
        val words = MontanaSeed.mnemonic ?: return null
        val of = Wire.hex(Wire.sha(words.toByteArray()))
        held?.let { if (it.first == of) return it.second }
        val h = derive(words) ?: return null
        held = of to h
        return h
    }
    fun derive(words: String): Hands? {
        val master = MtBindings.nativeMnemonicToMasterSeed(words)?.takeIf { it.size == 64 } ?: return null
        val seed = MtBindings.nativeRoleSeed(master, "mt-coin-tx").also { master.fill(0) } ?: return null
        return hands(seed).also { seed.fill(0) }
    }
    /** A key from its 32-byte ML-DSA seed (the vectors' and the local test's keys are made so). */
    fun hands(seed: ByteArray): Hands? {
        val kp = MtBindings.nativeMldsaKeypair(seed)?.takeIf { it.size == MtBindings.PUBKEY + MtBindings.SECKEY } ?: return null
        return Hands(kp.copyOfRange(0, MtBindings.PUBKEY), kp.copyOfRange(MtBindings.PUBKEY, kp.size)).also { kp.fill(0) }
    }
    /** The coin key's tag on the wire: SHA-256 of the coin key -- the sender's name in every record. */
    fun keyTag(pk: ByteArray) = Wire.hex(Wire.sha(pk))
    /** The key already derived in this run, never derived here (a caller on the screen's thread must not pay the seed's stretch). */
    val cachedKeyTag: String? get() = held?.second?.from
    /** The pair's tag: HMAC-SHA-256 under the pipe's secret -- its two ends know it, no one else does. */
    fun pairTag(secret: ByteArray): ByteArray = Hkdf.hmac(secret, PAIR_INFO)

    private fun u64(b: ByteArray, at: Int): Long { var v = 0L; for (i in 0 until 8) v = v or ((b[at + i].toLong() and 0xff) shl (8 * i)); return v }
    fun name(rec: ByteArray) = Wire.hex(Wire.sha(rec))
    fun fresh(): ByteArray = MtBindings.nativeRandom(16) ?: ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }

    /** The record of version 3 (iOS build3 3785-3796), signed by the core; null: a field of the wrong size, or the core refused. */
    fun build3(kind: CoinRules.Kind, amount: Long, prev: String, nonce: ByteArray, pair: ByteArray = ByteArray(32), to: ByteArray = ByteArray(32),
               ref: String = CoinRules.ZERO, a: Long = 0, b: Long = 0, hands: Hands? = null, birthMs: Long = System.currentTimeMillis()): ByteArray? {
        val k = hands ?: keys() ?: return null
        val p = CoinRules.bytes(prev)?.takeIf { it.size == 32 } ?: return null
        val r = CoinRules.bytes(ref)?.takeIf { it.size == 32 } ?: return null
        if (nonce.size != 16 || pair.size != 32 || to.size != 32 || amount < 0) return null
        val body = MAGIC + byteArrayOf(3, kind.code.toByte()) + Wire.le8(amount) + Wire.le8(maxOf(0L, birthMs)) + nonce + p + pair + to + r +
            Wire.le8(a) + Wire.le8(b) + k.pk
        if (body.size != 2134) return null
        val sig = MtBindings.nativeSign(k.sk, SIGNED3 + body)?.takeIf { it.size == 3309 } ?: return null
        return body + sig
    }
    /** The record of version 2 (iOS build 3499-3514), signed by the core on top of the key's head: the road of a correspondent whose
     *  coin key is not known yet, until the v2 cut (COIN-TX-V3 section 8). Null: no key, a field of the wrong size, or the core refused. */
    fun build2(coins: Long, pair: ByteArray, prev: String, hands: Hands? = null): ByteArray? {
        val k = hands ?: keys() ?: return null
        val p = CoinRules.bytes(prev)?.takeIf { it.size == 32 } ?: return null
        if (coins <= 0 || pair.size != 32) return null
        val body = MAGIC + byteArrayOf(2) + Wire.le8(coins) + Wire.le8(System.currentTimeMillis()) + fresh() + pair + p + k.pk
        if (body.size != 2053) return null
        val sig = MtBindings.nativeSign(k.sk, SIGNED2 + body)?.takeIf { it.size == 3309 } ?: return null
        return body + sig
    }
    /** A record read back -- version 1, 2 or 3 -- believed only when its shape holds and the core verifies its signature. */
    fun read(rec: ByteArray): Record? {
        if (rec.size < 5 || !rec.copyOfRange(0, 4).contentEquals(MAGIC)) return null
        val v = rec[4].toInt()
        if (v == 3) return read3(rec)
        val end: Int; val keyAt: Int; val total: Int; val prefix: ByteArray
        when (v) {
            1 -> { end = 2021; keyAt = 69; total = SIZE1; prefix = SIGNED1 }
            2 -> { end = 2053; keyAt = 101; total = SIZE2; prefix = SIGNED2 }
            else -> return null
        }
        if (rec.size != total) return null
        val coins = u64(rec, 5)
        if (coins <= 0) return null
        val pk = rec.copyOfRange(keyAt, end)
        if (!MtBindings.nativeVerify(pk, prefix + rec.copyOfRange(0, end), rec.copyOfRange(end, total))) return null
        return Record(name(rec), v, coins, u64(rec, 13), rec.copyOfRange(37, 69), if (v == 2) Wire.hex(rec.copyOfRange(69, 101)) else "", keyTag(pk))
    }
    fun read3(rec: ByteArray): Record? {
        if (rec.size != SIZE3 || !rec.copyOfRange(0, 4).contentEquals(MAGIC) || rec[4].toInt() != 3) return null
        val kind = CoinRules.Kind.of(rec[5].toInt() and 0xff) ?: return null
        val amount = u64(rec, 6)
        if (amount < 0 || (amount == 0L && kind != CoinRules.Kind.GENESIS)) return null
        val pair = rec.copyOfRange(70, 102); val to = rec.copyOfRange(102, 134); val ref = rec.copyOfRange(134, 166)
        val a = u64(rec, 166); val b = u64(rec, 174)
        if (!CoinRules.fieldsHold(kind.code, amount, pair, to, ref, a, b)) return null
        val pk = rec.copyOfRange(182, 2134)
        if (!MtBindings.nativeVerify(pk, SIGNED3 + rec.copyOfRange(0, 2134), rec.copyOfRange(2134, SIZE3))) return null
        return Record(name(rec), 3, amount, u64(rec, 14), pair, Wire.hex(rec.copyOfRange(38, 70)), keyTag(pk), kind.code, to, Wire.hex(ref), a, b,
            rec.copyOfRange(22, 38))
    }

    // ── the nodes ──
    /** A key's chain node: the one at the index of the key tag's first byte. */
    fun chainNode(from: String): String? = from.take(2).toIntOrNull(16)?.let { chainNodes[it % chainNodes.size].first }
    fun chainDoor(from: String): String? = chainNode(from)?.let { nodeDoor(it) }
    fun nodeDoor(name: String): String? = chainNodes.firstOrNull { it.first == name }?.let { "https://" + it.second + "/pushwake" }
    /** A node's answer, and whether the request never reached it (no network, no name, no connection): only such a silence proves nothing was laid. */
    class Answer(val code: Int, val obj: JSONObject?, val unreached: Boolean)
    fun ask(url: String, body: JSONObject, timeoutMs: Int = 15_000): Answer {
        var conn: HttpURLConnection? = null
        return try {
            val raw = body.toString().toByteArray(Charsets.UTF_8)
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"; doOutput = true; connectTimeout = timeoutMs; readTimeout = timeoutMs * 4
                setRequestProperty("content-type", "application/json"); setFixedLengthStreamingMode(raw.size)
            }
            conn.outputStream.use { it.write(raw) }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.use { it.readBytes().toString(Charsets.UTF_8) }
            Answer(code, text?.let { runCatching { JSONObject(it) }.getOrNull() }, false)
        } catch (e: java.net.UnknownHostException) { Answer(-1, null, true) }
        catch (e: java.net.ConnectException) { Answer(-1, null, true) }
        catch (e: Exception) { Answer(-1, null, false) }
        finally { conn?.disconnect() }
    }
    /** The state of a key's chain as its node folds it (POST /tx-head), and the node's own second. */
    class Chain3(val head: String, val height: Int, val birth: Long, val mintEnd: Long, val proven: Long, val declared: Long, val v3: Boolean, val now: Long, val minted: Long?)

    // ── THE FIRST IRREVERSIBLE WRITE ASKS THE PERSON (the owner's word 17.10.2026: «a clear warning before the first irreversible GENESIS
    // record, if it is laid by itself»): iOS lays a key's GENESIS unasked at its first reconcile; here it waits for the person's yes,
    // once per coin key on this phone (askGenesis, the wallet). A chain another device of the words opened needs no GENESIS and asks
    // nothing. Without the yes nothing of the chain is written by itself: no GENESIS, so no MINT, no RECV, no holder's signature. ──
    private const val GENESIS_OK = "coin3.genesis.ok."   // NOT-UI: + the coin key's tag -- the person let this phone open the chain
    /** Off the screen's thread (the key may be derived here). */
    fun genesisAllowed(): Boolean = keys()?.from?.let { Prefs.bool(GENESIS_OK + it, false) } ?: false
    /** On the screen's thread: the key already derived in this run, else no. */
    fun genesisAllowedCached(): Boolean = cachedKeyTag?.let { Prefs.bool(GENESIS_OK + it, false) } ?: false
    /** The person said yes: the chain is opened at once, off the screen's thread. */
    fun allowGenesis() {
        cachedKeyTag?.let { Prefs.setBool(GENESIS_OK + it, true) }   // the page that asked redraws at once
        Thread {
            val k = keys() ?: return@Thread
            Prefs.setBool(GENESIS_OK + k.from, true)
            Log.i("Montana", "coin_v3 genesis allowed by the person")
            runCatching { if (agrees) live.reconcile(force = true) }
        }.start()
    }
    /** The person's own chain as its node last told it in this run -- the wallet's confirmed line; null until it answered. */
    @Volatile var mine: Chain3? = null
    /** The person's chain asked once, reads only (the wallet's opening). */
    fun readMine() { if (agrees) keys()?.let { live.chain3(it.from) } }
    private fun heardMine(c: Chain3) {
        val was = mine
        mine = c
        CoinSplit.heard(c.proven, c.declared, c.v3, false, c.height)
        if (was == null || was.v3 != c.v3) MainThread.post { CoinBook.listeners() }   // the wallet redraws its confirmed line
    }

    // ── the phone's own client: the network, the phone's book, the person's coin key, the pipes of the book ──
    /** Writes only where the build allows them and the canon's vectors hold on this phone; a GENESIS only once the vault answered and the
     *  person said yes. */
    val live = CoinClient(HttpDoor, PhoneLedger, FileMemo, { keys() }, { conv -> Book.secret(conv) }, { Book.refs() }, { WRITES && agrees },
        { System.currentTimeMillis() / 1000 }, told = { c -> heardMine(c) }, bookHeard = { CoinVault.heard }, genesisAllowed = { genesisAllowed() })
    fun peerFrom(conv: String) = FileMemo.peerFrom(conv)
    fun notePeerFrom(conv: String, from: String) = FileMemo.notePeerFrom(conv, from)
    @Volatile private var scannedAt = 0L
    @Volatile private var settled = false
    /** RECEIVES OF EVERY VERSION, AND THE COPY OF THE CHAINS AFTER THEM (iOS settle 3678-3696 and scan 3713-3762): the records an ended
     *  process left waiting are decided first, once a run. `force` -- a transfer's letter landed or the wallet opened; a return to the
     *  app asks once a minute at most. */
    fun scan(why: String, force: Boolean = false) {
        if (!agrees || (!force && System.currentTimeMillis() - scannedAt < 60_000L)) return
        scannedAt = System.currentTimeMillis()
        if (!settled) { settled = true; live.settle() }
        live.scanPairs(why)
        CoinReplica.run(why)
    }
    /**
     * THE BOOK'S MOVE ASKS ITS CHAIN WITHIN ONE WINDOW (iOS mintSoon 3844-3857, the author's words 12.10.2026 15:5x MSK: «the minting has its
     * own chain of time and as it is confirmed it releases the available»; «once in τ1»): one ask a window, however many coins it holds.
     */
    @Volatile private var mintDue = false
    fun mintSoon() {
        if (!WRITES || mintDue) return
        mintDue = true
        MainThread.later(CoinRules.WINDOW * 1000, Runnable { mintDue = false; Thread { runCatching { if (agrees) live.reconcile() } }.start() })
    }
    /** THE TRANSFER'S TELLING LETTER (iOS MTCoinSend.transferResult 2995-3000): the coin glyph, the number and the ticker, the same in
     *  every language, and the transfer's own address in the Explorer. The letter credits nothing; the record it names does. */
    fun telling(coins: Long, id: String) = "🪙 " + CoinText.count(coins) + " " + TICKER + "\n" + LINK + id   // USER-DATA: a sum
    const val TICKER = "\$TCM"   // NOT-UI: the Montana time coin's one symbol in every language (iOS MTCoinBook.ticker)

    /**
     * SECTION 9's V5 ON THE PHONE (iOS: the node's coin-node-check and the Explorer's run; here: Kotlin's layout over the core's own
     * deterministic ML-DSA-65): a SEND of the key of seed SHA-256(«seed v3 vector S») committing to the key of seed SHA-256(«seed v3
     * vector R»), its signed message's hash and its id, and the RECV that settles it. An id that differs is a field at another offset or
     * a signature over another prefix -- and nothing of this file lays a record then.
     */
    fun v5AgreesWithCanon(): Boolean {
        fun sha(s: String) = Wire.sha(s.toByteArray())
        val s = hands(sha("seed v3 vector S")) ?: return false
        val r = hands(sha("seed v3 vector R")) ?: return false
        val nonce = sha("nonce v3 S").copyOf(16)
        val blind = CoinRules.blind(sha("secret v3 S"), nonce)
        val to = CoinRules.commitment(Wire.sha(r.pk), blind)
        val send = build3(CoinRules.Kind.SEND, 1234, CoinRules.ZERO, nonce, sha("pair v3 S"), to, hands = s, birthMs = 1_760_300_000_000L) ?: return false
        val message = SIGNED3 + send.copyOfRange(0, 2134)
        if (Wire.hex(Wire.sha(message)) != "cf00d783cfb5364e6c00afdaaeb203b32635b31d6894650f3fb68d7b3c96e3e5") return false
        if (name(send) != "2dd4cf64695222b31d4cd0c799a1f21888aaacb83bab7febfce055f6b7da46fa") return false
        if (read(send)?.id != name(send)) return false
        val recv = build3(CoinRules.Kind.RECV, 1234, CoinRules.ZERO, sha("nonce v3 R").copyOf(16), to = blind, ref = name(send), hands = r,
            birthMs = 1_760_300_000_000L) ?: return false
        return name(recv) == "ce5a492c063c71435ccb9582e3662c1d876310fe04d2846d73f7d07bd0236646"
    }
    val agrees: Boolean by lazy {
        val rules = CoinRules.agreesWithCanon()
        val v5 = runCatching { v5AgreesWithCanon() }.getOrDefault(false)
        Log.d("Montana", "coin_canon rules=" + (if (rules) "ok" else "DISAGREE") + " v5=" + (if (v5) "ok" else "DISAGREES"))
        rules && v5
    }
}

/** The book a client moves: the phone's own (CoinBook), or a test's (CoinLocalTest). */
interface CoinLedger {
    val balance: Long
    fun send(coins: Long, peer: String, ref: String): Boolean
    fun receive(coins: Long, peer: String, ref: String): Boolean
    fun retake(coins: Long, peer: String, ref: String): Boolean
    fun holds(kind: String, ref: String): Boolean
}
object PhoneLedger : CoinLedger {
    override val balance: Long get() { CoinBook.warm(); return CoinBook.balance }
    override fun send(coins: Long, peer: String, ref: String) = CoinBook.send(coins, peer, ref)
    override fun receive(coins: Long, peer: String, ref: String) = CoinBook.receive(coins, peer, ref)
    override fun retake(coins: Long, peer: String, ref: String) = CoinBook.retake(coins, peer, ref)
    override fun holds(kind: String, ref: String) = CoinBook.holds(kind, ref)
}
/** Where a client's questions go: a chain node by its name, over HTTPS -- or a node on this phone (CoinLocalNode). */
fun interface CoinDoor { fun ask(node: String, path: String, body: JSONObject): CoinTx.Answer }
object HttpDoor : CoinDoor {
    override fun ask(node: String, path: String, body: JSONObject): CoinTx.Answer =
        CoinTx.nodeDoor(node)?.let { CoinTx.ask(it + path, body, if (path == "/tx-pair") 20_000 else 15_000) } ?: CoinTx.Answer(-1, null, true)
}
/** What a client remembers: the correspondents' coin keys (their about word's «k»), its own sends still open, and the records no node
 *  has given its word on yet (iOS tx-pending-<id>.rec: an ended process's records are decided at the next launch). */
interface CoinMemo {
    fun peerFrom(conv: String): String?
    fun notePeerFrom(conv: String, from: String)
    fun openSends(): JSONArray
    fun keepOpen(a: JSONArray)
    fun keepPending(id: String, rec: ByteArray)
    fun dropPending(id: String)
    fun pendings(): List<ByteArray>
}
/** The phone's memory of them: files of this device (iOS coin3-peers.json, coin3-open.json). */
object FileMemo : CoinMemo {
    private fun store(name: String) = File(Book.ctx.noBackupFilesDir, name)
    private fun load(name: String): JSONObject = runCatching { JSONObject(store(name).readText()) }.getOrNull() ?: JSONObject()
    private fun save(name: String, o: JSONObject) { runCatching { store(name).writeText(o.toString()) } }
    override fun peerFrom(conv: String): String? = load("coin3-peers.json").optJSONObject("k")?.optString(conv)?.takeIf { it.length == 64 }
    @Synchronized override fun notePeerFrom(conv: String, from: String) {
        if (from.length != 64 || CoinRules.bytes(from) == null) return
        val o = load("coin3-peers.json")
        val m = o.optJSONObject("k") ?: JSONObject()
        if (m.optString(conv) == from) return
        o.put("k", m.put(conv, from)); save("coin3-peers.json", o)
    }
    override fun openSends(): JSONArray = load("coin3-open.json").optJSONArray("open") ?: JSONArray()
    override fun keepOpen(a: JSONArray) = save("coin3-open.json", JSONObject().put("open", a))
    private fun pendingDir() = File(Book.ctx.noBackupFilesDir, "coin-pending").apply { mkdirs() }
    override fun keepPending(id: String, rec: ByteArray) { runCatching { File(pendingDir(), "tx-pending-$id.rec").writeBytes(rec) } }
    override fun dropPending(id: String) { File(pendingDir(), "tx-pending-$id.rec").delete() }
    override fun pendings(): List<ByteArray> = pendingDir().listFiles { f -> f.name.startsWith("tx-pending-") && f.name.endsWith(".rec") }
        ?.mapNotNull { runCatching { it.readBytes() }.getOrNull() }.orEmpty()
}

/**
 * ONE KEY'S CLIENT OF THE CHAINS (iOS MTCoinTx: lay, sendResult, settle, scan; its version 3: chain3, headIsMine, layOnHead, reconcile,
 * send3, receive3, refundDue): the nodes it asks (`door`), the book it moves, what it remembers, the key it signs with, the pipes it
 * knows, whether it may write at all, the clock it measures a window by, and whom it tells what its chain holds. The phone's own client
 * is CoinTx.live; CoinLocalTest makes its own against nodes on the phone, so the very code the network would meet is the code the
 * test walks. A GENESIS waits for two words: `bookHeard` -- the seed's book was gathered from the vault in this run (CoinVault.heard) --
 * and `genesisAllowed` -- the person said yes to the chain's first record (CoinTx.allowGenesis).
 */
class CoinClient(private val door: CoinDoor, private val ledger: CoinLedger, private val memo: CoinMemo, private val hands: () -> CoinTx.Hands?,
                 private val secretOf: (String) -> ByteArray?, private val pipes: () -> List<String>, private val writes: () -> Boolean,
                 private val wall: () -> Long, private val told: ((CoinTx.Chain3) -> Unit)? = null, private val bookHeard: () -> Boolean = { true },
                 private val genesisAllowed: () -> Boolean = { true }) {
    private fun ask(from: String, path: String, body: JSONObject): CoinTx.Answer? = CoinTx.chainNode(from)?.let { door.ask(it, path, body) }
    private fun pairTag(conv: String): ByteArray? = secretOf(conv)?.takeIf { it.isNotEmpty() }?.let { CoinTx.pairTag(it) }
    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)

    /** The state of a key's chain as its node folds it (POST /tx-head), and the node's own second. Reads only; what the person's own chain
     *  holds is told to the wallet's one number (CoinSplit). */
    fun chain3(me: String): CoinTx.Chain3? {
        val h = ask(me, "/tx-head", JSONObject().put("from", me)) ?: return null
        val o = h.obj ?: return null
        val head = o.optString("head")
        if (h.code != 200 || head.length != 64) return null
        fun n(k: String): Long = o.opt(k)?.toString()?.toLongOrNull() ?: 0L
        val now = n("now")
        val c = CoinTx.Chain3(head, n("height").toInt(), n("birth"), n("mint_end"), n("proven"), n("declared"), n("v3") == 1L,
            if (now == 0L) wall() else now, if (o.has("minted")) n("minted") else null)
        if (me == hands()?.from) told?.invoke(c)
        return c
    }
    /**
     * THE HEAD IS BELIEVED ONLY AS MY OWN SIGNED RECORD (iOS headIsMine 3603-3613): the head's record is read from the same chain node,
     * its bytes must be its name, the core must verify it, and it must be of my own key; nothing is built on anything else.
     */
    private fun headIsMine(head: String, me: String): Boolean {
        if (head == CoinRules.ZERO) return true
        val g = ask(me, "/tx-get", JSONObject().put("id", head)) ?: return false
        val b = g.obj?.optString("rec")?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() } ?: return false
        val r = CoinTx.read(b) ?: return false
        return g.code == 200 && r.id == head && r.from == me && (r.version == 2 || r.version == 3)
    }

    /**
     * THE NODE'S WORD DECIDES (iOS lay 3573-3602): a record of version 2 or 3 goes to its key's chain node alone -- taken there, left;
     * standing on a head that moved, behind; refused, or the request never reached it, not left; anything else waits for that node's
     * word. ONE ASK MORE THAN iOS ON A 409: a record the node already holds is left whatever head it now names -- a record laid again
     * after an ended process found its own self on the chain, and «behind» would give its coins back while the receiver took them.
     */
    enum class Word { LEFT, NOT_LEFT, BEHIND, UNKNOWN }
    fun lay(rec: ByteArray): Word {
        val r = CoinTx.read(rec) ?: return Word.NOT_LEFT
        val id = r.id
        if (!writes()) return Word.NOT_LEFT
        val a = ask(r.from, "/tx-put", JSONObject().put("rec", b64(rec))) ?: return Word.NOT_LEFT
        if (a.code == 200 && a.obj?.optString("id") == id) return Word.LEFT
        if (a.code == 409) return if (ask(r.from, "/tx-get", JSONObject().put("id", id))?.code == 200) Word.LEFT else Word.BEHIND
        if (a.code == 400 || a.code == 403 || a.code == 429 || a.code == 507 || a.unreached) return Word.NOT_LEFT
        return if (ask(r.from, "/tx-get", JSONObject().put("id", id))?.code == 200) Word.LEFT else Word.UNKNOWN
    }
    /**
     * ONE RECORD OF MY KEY LAID ON MY CHAIN'S HEAD (iOS layOnHead 3829-3843), the head read back and verified as mine first; a head that
     * moved is asked again once. A client that may not write puts nothing, and the word says so.
     */
    private fun layOnHead(make: (CoinTx.Chain3) -> ByteArray?): Pair<Int, String> {
        val me = hands()?.from ?: return -1 to "no key"
        if (!writes()) return -1 to "writes off"
        repeat(2) {
            val st = chain3(me) ?: return -1 to "no head"
            if (!headIsMine(st.head, me)) return -1 to "head unverified"
            val rec = make(st) ?: return -1 to "no record"
            val a = ask(me, "/tx-put", JSONObject().put("rec", b64(rec))) ?: return -1 to "no door"
            val word = a.obj?.optString("error").orEmpty()
            if (a.code == 200) return 200 to ""
            if (a.code == 409 && word == "not on the head") return@repeat
            if (a.code == -1 && !a.unreached && ask(me, "/tx-get", JSONObject().put("id", CoinTx.name(rec)))?.code == 200) return 200 to ""
            return a.code to word
        }
        return 409 to "not on the head"
    }

    /**
     * THE CHAIN HOLDS WHAT THE BOOK HOLDS (iOS reconcile 3858-3894, sections 3-4): a key's first v3 record is its GENESIS -- the book as
     * it stands, at most the genesis cap, announced and never called proven (before the v2 cut; a GENESIS of 0 after it); after it, what
     * the book holds above the chain is laid as a MINT of the time since the last one, at most what the interval allows. The node's
     * clock decides the interval. A client that may not write only reads.
     */
    @Volatile private var mintedAt = 0L
    fun reconcile(force: Boolean = false): CoinTx.Chain3? {
        val k = hands() ?: return null
        val me = k.from
        var st = chain3(me) ?: return null
        if (!writes()) return st
        val book = ledger.balance
        if (!st.v3) {
            // THE GENESIS WAITS FOR THE SEED'S BOOK (beside iOS MTCoinVault.heard: «a device that has not gathered its seed's book never
            // tells the table a balance it does not hold»): a key's GENESIS is laid once, ever; laid from this phone's share alone before
            // the vault answered, the book the seed's other devices hold could never be announced on the key's chain
            if (!bookHeard()) { Log.d("Montana", "coin_v3 genesis waits: the seed's book is not gathered yet"); return st }
            if (!genesisAllowed()) { Log.d("Montana", "coin_v3 genesis waits: the person has not opened the chain"); return st }
            val amount = if (st.now < CoinRules.V2_CUT) minOf(maxOf(0L, book), CoinRules.genesisCap) else 0L
            // ONE GENESIS A KEY: a head another device of the words opened meanwhile takes none (the node refuses a second one too)
            val r = layOnHead { s -> if (s.v3) null else CoinTx.build3(CoinRules.Kind.GENESIS, amount, s.head, CoinTx.fresh(), hands = k) }
            Log.d("Montana", "coin_v3 genesis code=" + r.first + " word=" + r.second + " amount=" + amount)
            st = chain3(me) ?: return null
            if (!st.v3) return st
        }
        val now = wall()
        if (!force && now - mintedAt < CoinRules.WINDOW) return st
        mintedAt = now
        val gap = book - st.proven - st.declared
        if (gap <= 0 || st.now - 120 < st.mintEnd + 60) return st
        val r = layOnHead { s ->
            val t0 = s.mintEnd; val t1 = s.now - 120
            // the key's time less what it minted (section 4, fold-3); a node that names no minted still folds by the interval
            val room = CoinRules.timeA(t1 - s.birth) - (s.minted ?: CoinRules.timeA(t0 - s.birth))
            val amount = minOf(book - s.proven - s.declared, room)
            if (amount <= 0 || t1 < t0 + 60) null else CoinTx.build3(CoinRules.Kind.MINT, amount, s.head, CoinTx.fresh(), a = t0, b = t1, hands = k)
        }
        Log.d("Montana", "coin_v3 mint code=" + r.first + " word=" + r.second + " gap=" + gap)
        return if (r.first == 200) chain3(me) else st
    }

    /** A transfer's three honest outcomes (iOS SendResult): the coins left (the record's name), a record waits for a node's word, or
     *  nothing moved. */
    sealed class Sent {
        class Left(val id: String) : Sent()
        object Pending : Sent()
        class NotLeft(val why: String) : Sent()
    }
    /**
     * VERSION 3 FIRST (iOS sendResult 3624-3677): the chain proves the balance; version 2 only for a correspondent who cannot take v3 yet
     * (their coin key not known), until the cut; after it, nothing moves on that road. Every road holds the coins under the record's own
     * name before it is laid and gives them back under the same name when no node took it.
     */
    fun sendResult(coins: Long, conv: String): Sent {
        when (val r3 = send3(coins, conv)) {
            is Send3.Sent -> return Sent.Left(r3.id)
            Send3.Pending -> return Sent.Pending
            Send3.Failed -> return Sent.NotLeft("v3 failed")
            is Send3.NotApplicable -> {
                Log.d("Montana", "coin_v3 v2 road why=" + r3.why + " coins=" + coins)
                if (r3.why == "writes off" || r3.why == "no key" || r3.why == "no pipe") return Sent.NotLeft(r3.why)
            }
        }
        val k = hands() ?: return Sent.NotLeft("no key")
        val me = k.from
        val pair = pairTag(conv) ?: return Sent.NotLeft("no pipe")
        val first = reconcile(force = true) ?: return Sent.NotLeft("no head")
        if (CoinRules.V2_CUT <= first.now) return Sent.NotLeft("v2 retired")
        // A SEND THAT NAMES NO RECEIVER SPENDS THE CHAIN TOO (fold-2): the chain opened and holding the sum first, else the node refuses
        if (first.v3 && first.proven + first.declared < coins) return Sent.NotLeft("chain short")
        repeat(2) { attempt ->
            val st = chain3(me) ?: return Sent.NotLeft("no head")
            if (!headIsMine(st.head, me)) return Sent.NotLeft("head unverified")
            val rec = CoinTx.build2(coins, pair, st.head, k) ?: return Sent.NotLeft("no record")
            val id = CoinTx.name(rec)
            if (!ledger.send(coins, conv, CoinTx.REF_PREFIX + id)) return Sent.NotLeft("book short")
            memo.keepPending(id, rec)
            val word = lay(rec)
            Log.d("Montana", "coin_tx word=$word coins=$coins id=" + id.take(12) + " attempt=" + (attempt + 1))
            when (word) {
                Word.LEFT -> { memo.dropPending(id); return Sent.Left(id) }
                Word.UNKNOWN -> return Sent.Pending
                Word.NOT_LEFT, Word.BEHIND -> {
                    ledger.receive(coins, conv, CoinTx.BACK_PREFIX + id); memo.dropPending(id)
                    if (word == Word.NOT_LEFT) return Sent.NotLeft("not left")
                    scanPairs("behind")   // the other device's record joins the book before the balance is asked again
                }
            }
        }
        return Sent.NotLeft("behind")
    }

    /** What a version 3 SEND became (iOS Send3). */
    sealed class Send3 {
        class Sent(val id: String) : Send3()
        object Pending : Send3()
        class NotApplicable(val why: String) : Send3()
        object Failed : Send3()
    }
    /**
     * SENDS (version 3, iOS send3 3933-3972): the receiver's key known (their about word), my chain announced and holding the sum, the
     * record names the declared part of it (proven is spent first), commits to the receiver's key under the pair's blind, and is laid
     * on my chain's head. What makes v3 impossible now is said as NotApplicable.
     */
    fun send3(coins: Long, conv: String): Send3 {
        val k = hands()
        val secret = secretOf(conv)
        val pair = pairTag(conv)
        val peer = memo.peerFrom(conv)?.let { CoinRules.bytes(it) }?.takeIf { it.size == 32 }
        when {
            !writes() -> return Send3.NotApplicable("writes off")
            k == null -> return Send3.NotApplicable("no key")
            secret == null || pair == null -> return Send3.NotApplicable("no pipe")
            peer == null -> return Send3.NotApplicable("no receiver key")
            coins <= 0 -> return Send3.NotApplicable("no coins")
        }
        k!!; secret!!; pair!!; peer!!
        val me = k.from
        val first = reconcile(force = true)
        if (first == null || !first.v3 || first.proven + first.declared < coins) return Send3.NotApplicable("chain short")
        val nonce = CoinTx.fresh()
        // past the walk's anchor a SEND is blinded under the conversation's root, not the pipe's secret (iOS send3 -> itemKey)
        val blind = CoinRules.blind(Wire.itemKey(secret), nonce)
        val commit = CoinRules.commitment(peer, blind)
        repeat(2) { attempt ->
            val st = chain3(me) ?: return Send3.Failed
            if (!st.v3 || st.proven + st.declared < coins) return Send3.NotApplicable("chain short")
            if (!headIsMine(st.head, me)) return Send3.Failed
            val dec = maxOf(0L, coins - st.proven)
            val rec = CoinTx.build3(CoinRules.Kind.SEND, coins, st.head, nonce, pair, commit, a = dec, hands = k) ?: return Send3.Failed
            val id = CoinTx.name(rec)
            if (!ledger.send(coins, conv, CoinTx.REF_PREFIX + id)) return Send3.Failed
            memo.keepPending(id, rec)
            val word = lay(rec)
            Log.d("Montana", "coin_v3 send word=$word coins=$coins dec=$dec id=" + id.take(12) + " attempt=" + (attempt + 1))
            when (word) {
                Word.LEFT -> {
                    memo.dropPending(id)
                    memo.keepOpen(memo.openSends().put(JSONObject().put("id", id).put("conv", conv).put("coins", coins).put("at", st.now)))
                    return Send3.Sent(id)
                }
                Word.UNKNOWN -> {
                    memo.keepOpen(memo.openSends().put(JSONObject().put("id", id).put("conv", conv).put("coins", coins).put("at", st.now)))
                    return Send3.Pending
                }
                Word.NOT_LEFT, Word.BEHIND -> {
                    ledger.receive(coins, conv, CoinTx.BACK_PREFIX + id); memo.dropPending(id)   // not taken: the coins come back under its name
                    if (word == Word.NOT_LEFT) return Send3.Failed
                }
            }
        }
        return Send3.Failed
    }
    /**
     * THE RECORDS AN ENDED PROCESS LEFT WAITING (iOS settle 3678-3696), each decided by its node's word: taken -- it stays the book's debit;
     * refused or behind -- the coins come back under its name; still no word -- it waits on the disk.
     */
    fun settle() {
        if (!writes()) return
        val byTag = HashMap<String, String>()
        for (c in pipes()) pairTag(c)?.let { byTag[Wire.hex(it)] = c }
        for (rec in memo.pendings()) {
            val r = CoinTx.read(rec) ?: continue
            val conv = byTag[Wire.hex(r.pair)]
            when (lay(rec)) {
                Word.LEFT -> memo.dropPending(r.id)
                Word.NOT_LEFT, Word.BEHIND -> {
                    if (conv != null) ledger.receive(r.coins, conv, CoinTx.BACK_PREFIX + r.id)
                    memo.dropPending(r.id)
                }
                Word.UNKNOWN -> {}
            }
            Log.d("Montana", "coin_tx settle id=" + r.id.take(12) + " coins=" + r.coins)
        }
    }
    /**
     * RECEIVES (version 3, iOS receive3 3973-3991): a SEND of my pair that commits to my key is taken by a RECV on my chain -- the book
     * credits it only when my chain holds it. A client that may not write leaves it: the SEND comes back to its sender after a day.
     */
    fun receive3(s: CoinTx.Record, conv: String): Boolean {
        val k = hands() ?: return false
        val me = k.from
        val mine = CoinRules.bytes(me) ?: return false
        val secret = secretOf(conv) ?: return false
        // the sender's day is its own clock: the root first, then the established secret (iOS receive3 -> itemKeys)
        val blind = Wire.itemKeys(secret).map { k -> CoinRules.blind(k, s.nonce) }
            .firstOrNull { b -> CoinRules.commitment(mine, b).contentEquals(s.to) } ?: return false
        if (s.kind != CoinRules.Kind.SEND.code) return false
        if (ledger.holds(CoinEntry.RECEIVE, CoinTx.REF_PREFIX + s.id)) return false
        if (!writes()) { Log.d("Montana", "coin_v3 recv waits: writes off coins=" + s.coins + " id=" + s.id.take(12)); return false }
        val st = reconcile() ?: return false
        if (!st.v3) return false
        val r = layOnHead { c -> CoinTx.build3(CoinRules.Kind.RECV, s.coins, c.head, CoinTx.fresh(), to = blind, ref = s.id, a = s.a, hands = k) }
        var taken = r.first == 200
        if (!taken && (r.second == "settled" || r.second == "not yours")) {
            val f = ask(s.from, "/tx-settle", JSONObject().put("send", s.id))
            taken = f?.obj?.optString("state") == "recv" && f.obj.optString("by") == me
        }
        Log.d("Montana", "coin_v3 recv code=" + r.first + " word=" + r.second + " taken=" + (if (taken) 1 else 0) + " id=" + s.id.take(12))
        return taken && ledger.receive(s.coins, conv, CoinTx.REF_PREFIX + s.id)
    }
    /** An untaken SEND comes back after a day by a REFUND on my chain (iOS refundDue 4045-4065): its node's clock decides, one fate a SEND. */
    fun refundDue() {
        if (!writes()) return
        val k = hands() ?: return
        val me = k.from
        val rows = memo.openSends()
        if (rows.length() == 0) return
        val left = JSONArray()
        for (i in 0 until rows.length()) {
            val o = rows.optJSONObject(i) ?: continue
            val id = o.optString("id"); val conv = o.optString("conv"); val coins = o.optLong("coins"); val at = o.optLong("at")
            val state = ask(me, "/tx-settle", JSONObject().put("send", id))?.obj?.optString("state").orEmpty()
            if (state == "recv") continue
            if (state == "refund") { ledger.receive(coins, conv, CoinTx.BACK_PREFIX + id); continue }
            val st = chain3(me)
            if (state != "open" || st == null || st.now < at + 86_460) { left.put(o); continue }
            val r = layOnHead { c -> CoinTx.build3(CoinRules.Kind.REFUND, coins, c.head, CoinTx.fresh(), ref = id, hands = k) }
            Log.d("Montana", "coin_v3 refund code=" + r.first + " word=" + r.second + " id=" + id.take(12))
            if (r.first == 200) ledger.receive(coins, conv, CoinTx.BACK_PREFIX + id) else left.put(o)
        }
        memo.keepOpen(left)
    }

    /** What one scan found: the records read, credited, my own, refused by the core or by the chain-node rule, waiting for a RECV. */
    class Scanned(val got: Int, val credited: Int, val own: Int, val bad: Int, val foreign: Int, val waiting: Int)
    /**
     * RECEIVES OF EVERY VERSION (iOS scan 3710-3762): every pipe's tag asked on each chain node (/tx-pair); a verified record of another
     * key is a credit -- versions 1 and 2 by the pair's tag into the book, version 3 by its RECV -- a record of my own key my own send
     * from another device of the words, each once by its name; a version 2 or 3 record is believed only from its key's chain node.
     */
    @Volatile private var scanning = false
    @Volatile private var scanAgain = false
    fun scanPairs(why: String): Scanned? {
        synchronized(this) { if (scanning) { scanAgain = true; return null }; scanning = true }
        try {
            val me = hands()?.from ?: return null
            val conv = HashMap<String, String>()
            for (c in pipes()) pairTag(c)?.let { conv[Wire.hex(it)] = c }
            if (conv.isEmpty()) return Scanned(0, 0, 0, 0, 0, 0)
            var got = 0; var credited = 0; var own = 0; var bad = 0; var foreign = 0; var waiting = 0
            val seen = HashSet<String>()
            for ((node, _) in CoinTx.chainNodes) {
                for (part in conv.keys.toList().chunked(256)) {
                    var since = 0L
                    while (true) {
                        val a = door.ask(node, "/tx-pair", JSONObject().put("tags", JSONArray(part)).put("since", since))
                        val txs = a.obj?.optJSONArray("txs")
                        if (a.code != 200 || txs == null) break
                        for (i in 0 until txs.length()) {
                            val x = txs.optJSONObject(i) ?: continue
                            val id = x.optString("id")
                            if (id.isEmpty() || id in seen) continue
                            val b = runCatching { Base64.decode(x.optString("rec"), Base64.DEFAULT) }.getOrNull() ?: continue
                            got++
                            val r = CoinTx.read(b)
                            val c = r?.let { conv[Wire.hex(it.pair)] }
                            if (r == null || r.id != id || c == null) { bad++; continue }
                            if (r.version != 1 && CoinTx.chainNode(r.from) != node) { foreign++; continue }
                            seen.add(id)
                            when {
                                r.from == me -> if (!ledger.holds(CoinEntry.SEND, CoinTx.REF_PREFIX + r.id) && ledger.retake(r.coins, c, CoinTx.REF_PREFIX + r.id)) own++
                                r.version == 3 -> if (receive3(r, c)) credited++ else if (r.kind == CoinRules.Kind.SEND.code && !ledger.holds(CoinEntry.RECEIVE, CoinTx.REF_PREFIX + r.id)) waiting++
                                else -> if (ledger.receive(r.coins, c, CoinTx.REF_PREFIX + r.id)) credited++
                            }
                        }
                        val last = a.obj?.optLong("last", since) ?: since
                        if (txs.length() < 512 || last <= since) break
                        since = last
                    }
                }
            }
            Log.d("Montana", "coin_tx_scan why=$why pipes=${conv.size} got=$got credited=$credited own=$own bad=$bad foreign=$foreign waiting=$waiting")
            reconcile()
            refundDue()
            return Scanned(got, credited, own, bad, foreign, waiting)
        } catch (e: Exception) {
            Log.w("Montana", "coin_tx_scan " + e.javaClass.simpleName)
            return null
        } finally {
            val again = synchronized(this) { scanning = false; scanAgain.also { scanAgain = false } }
            if (again) Thread { scanPairs("again") }.start()
        }
    }
}

/**
 * THE BALANCE AS ITS CHAIN HOLDS IT (iOS MTCoinSplit 3383-3413; the chairman's task 12.10.2026, No.65; the author's word 16.10.2026 17:19
 * MSK: «it is enough to show how much is available with one owner, so that a transfer from the chat and from any place shows only the
 * available»): what the person's own chain holds -- proven and declared -- as its node or this phone's own copy folded it, the newest
 * height speaking; the available is that, never above the book, which has already paid the transfers still on their way; before the
 * chain has spoken in this run, the book.
 */
object CoinSplit {
    class Split(val proven: Long, val declared: Long, val fromCopy: Boolean, val height: Int)
    @Volatile var split: Split? = null
        private set
    fun heard(proven: Long, declared: Long, opened: Boolean, fromCopy: Boolean, height: Int) {
        if (!opened) return
        val s = split
        if (s != null && height < s.height) return
        if (s == null || s.proven != proven || s.declared != declared || s.height != height) {
            split = Split(proven, declared, fromCopy, height)
            Log.d("Montana", "coin_split proven=$proven declared=$declared copy=" + (if (fromCopy) 1 else 0))
            MainThread.post { CoinBook.listeners() }
        }
    }
    val available: Long get() {
        CoinBook.warm()
        val book = CoinBook.balance
        val s = split ?: return book
        return minOf(book, s.proven + s.declared)
    }
    fun forget() { split = null }
}

/**
 * THE PHONE'S COPY OF THE NETWORK'S COIN CHAINS (iOS MTCoinReplica 4069-4201, COIN-TX-V3 section 6): with the person's consent to keep
 * for others (Keeping.others) the phone pulls what each chain node took, verifies every signature with the core, folds every chain by
 * the nodes' own rules and computes the root of the nodes' newest checkpoint itself -- the whole network's chains, never only the
 * correspondents'. The holder's signature of that root is a write (CoinTx.WRITES): until the owner allows it, the copy is checked and
 * kept, the diary says whether its root is the nodes' own (same=1), and nothing is signed.
 */
object CoinReplica {
    private class Row(val id: String, val version: Int, val kind: Int, val amount: Long, val from: String, val prev: String, val to: ByteArray,
                      val ref: String, val a: Long, val b: Long, val at: Long, val node: String)
    private val rows = LinkedHashMap<String, Row>()
    private val seq = HashMap<String, Long>()
    @Volatile private var running = false
    @Volatile private var ranAt = 0L
    @Volatile var last: String = ""
        private set
    private fun file() = File(Book.ctx.noBackupFilesDir, "coin-replica.json")

    private fun loadOnce() {
        if (rows.isNotEmpty() || seq.isNotEmpty()) return
        val o = runCatching { JSONObject(file().readText()) }.getOrNull() ?: return
        o.optJSONObject("seq")?.let { s -> s.keys().forEach { seq[it] = s.optLong(it) } }
        val a = o.optJSONArray("rows") ?: return
        for (i in 0 until a.length()) a.optJSONObject(i)?.let { r ->
            val row = Row(r.optString("id"), r.optInt("v"), r.optInt("k"), r.optLong("z"), r.optString("f"), r.optString("p"),
                CoinRules.bytes(r.optString("t")) ?: ByteArray(32), r.optString("r"), r.optLong("a"), r.optLong("b"), r.optLong("at"), r.optString("n"))
            rows[row.id] = row
        }
    }
    private fun save() {
        val a = JSONArray()
        for (r in rows.values) a.put(JSONObject().put("id", r.id).put("v", r.version).put("k", r.kind).put("z", r.amount).put("f", r.from).put("p", r.prev)
            .put("t", Wire.hex(r.to)).put("r", r.ref).put("a", r.a).put("b", r.b).put("at", r.at).put("n", r.node))
        val s = JSONObject(); seq.forEach { (k, v) -> s.put(k, v) }
        runCatching { file().writeText(JSONObject().put("seq", s).put("rows", a).toString()) }
    }

    class Folded(var keys: Int = 0, var records: Int = 0, var root: String = "", var bad: Int = 0, var waiting: Int = 0, var mine: CoinRules.St? = null)
    /** Every chain folded from its first record in its own order (prev), a RECV after the SEND it settles; then the root of T as the node computes it. */
    private fun fold(all: Collection<Row>, T: Long, me: String?): Folded {
        val out = Folded()
        val byPrev = HashMap<String, HashMap<String, Row>>()
        val atOf = HashMap<String, Long>()
        for (r in all) {
            if (r.version == 1) continue   // a version 1 row stands on no chain
            if (CoinTx.chainNode(r.from) != r.node) { out.bad++; continue }   // a node serves only its own chains
            byPrev.getOrPut(r.from) { HashMap() }[r.prev] = r
            atOf[r.id] = r.at
        }
        val st = HashMap<String, CoinRules.St>(); val sends = HashMap<String, CoinRules.SendInfo>(); val settled = HashSet<String>(); val broken = HashSet<String>()
        val order = HashMap<String, MutableList<String>>()
        var moved = true
        while (moved) {
            moved = false
            for ((from, chain) in byPrev) {
                if (from in broken) continue
                var s = st[from] ?: CoinRules.St()
                while (true) {
                    val r = chain[s.head] ?: break
                    val (next, wait) = CoinRules.step(s, CoinRules.Rec(r.id, r.version, r.kind, r.amount, r.from, r.to, r.ref, r.a, r.b), atOf[r.id] ?: 0, sends, settled)
                    if (wait) break
                    if (next == null) { broken.add(from); out.bad++; break }
                    if (r.version == 3 && r.kind == CoinRules.Kind.SEND.code) sends[r.id] = CoinRules.SendInfo(from, r.amount, atOf[r.id] ?: 0, r.to, r.a)
                    if (r.version == 3 && (r.kind == CoinRules.Kind.RECV.code || r.kind == CoinRules.Kind.REFUND.code)) settled.add(r.ref)
                    order.getOrPut(from) { ArrayList() }.add(r.id)
                    s = next; moved = true
                }
                st[from] = s
            }
        }
        for ((from, chain) in byPrev) if (from !in broken && chain[st[from]?.head ?: CoinRules.ZERO] != null) out.waiting++
        if (me != null && me !in broken) out.mine = st[me]
        val (root, keys, records) = CoinRules.root(order, atOf, T)
        out.root = root; out.keys = keys; out.records = records
        return out
    }

    /** One round: what each chain node took since the last round, every record checked by the core, the whole fold and the root of the
     *  nodes' newest checkpoint computed here; once in ten minutes at most, only with the consent to keep for others. */
    fun run(why: String, force: Boolean = false) {
        if (!Keeping.others || running || (!force && System.currentTimeMillis() - ranAt < 600_000L) || !CoinTx.agrees) return
        running = true
        ranAt = System.currentTimeMillis()
        try {
            loadOnce()
            var pulled = 0; var refused = 0
            for ((name, _) in CoinTx.chainNodes) {
                val door = CoinTx.nodeDoor(name) ?: continue
                var since = seq[name] ?: 0L
                for (page in 0 until 64) {
                    val a = CoinTx.ask("$door/tx-since", JSONObject().put("since", since), 30_000)
                    val txs = a.obj?.optJSONArray("txs")
                    if (a.code != 200 || txs == null) break
                    for (i in 0 until txs.length()) {
                        val x = txs.optJSONObject(i) ?: continue
                        val id = x.optString("id"); val s = x.optLong("seq", -1)
                        val rec = runCatching { Base64.decode(x.optString("rec"), Base64.DEFAULT) }.getOrNull()
                        if (s > since) since = s
                        if (id.isEmpty() || rec == null || rows.containsKey(id)) continue
                        val r = CoinTx.read(rec)
                        if (r == null || r.id != id) { refused++; continue }
                        rows[id] = Row(id, r.version, r.kind, r.coins, r.from, r.prev, r.to, r.ref, r.a, r.b, x.optLong("at"), name)
                        pulled++
                    }
                    seq[name] = since
                    if (txs.length() < 512) break
                }
            }
            save()
            val me = CoinTx.cachedKeyTag ?: CoinTx.keys()?.from
            val door = me?.let { CoinTx.chainDoor(it) } ?: CoinTx.nodeDoor(CoinTx.chainNodes[0].first) ?: return
            val r = CoinTx.ask("$door/tx-root", JSONObject())
            val T = r.obj?.optLong("at", 0) ?: 0
            val nodeRoot = r.obj?.optString("root").orEmpty()
            if (r.code != 200 || T <= 0) { last = "no checkpoint code=" + r.code; Log.d("Montana", "coin_replica why=$why pulled=$pulled rows=${rows.size} $last"); return }
            val f = fold(rows.values, T, me)
            val same = f.root == nodeRoot
            // the person's own chain as this copy folded it: the wallet's one number hears it before the node's word (iOS MTCoinSplit)
            f.mine?.takeIf { f.bad == 0 }?.let { m -> CoinSplit.heard(m.proven, m.declared, m.v3, true, m.height) }
            // THE HOLDER SIGNS THE ROOT IT COMPUTED ITSELF (section 6): T as u64 LE and the root, under the seed's coin key, at both nodes;
            // a node keeps only a key that has a chain, the last signature of each -- so a key whose chain is not open signs nothing
            var signed = 0
            val k = if (CoinTx.WRITES && f.bad == 0 && 0 < f.keys && f.mine?.v3 == true) CoinTx.keys() else null
            val rootBytes = CoinRules.bytes(f.root)
            if (k != null && rootBytes != null) {
                val sig = MtBindings.nativeSign(k.sk, "mt-coin-root-sig-v1".toByteArray() + Wire.le8(T) + rootBytes)
                if (sig != null) for ((name, _) in CoinTx.chainNodes) {
                    val d = CoinTx.nodeDoor(name) ?: continue
                    val a = CoinTx.ask("$d/tx-root-sign", JSONObject().put("pk", Base64.encodeToString(k.pk, Base64.NO_WRAP)).put("at", T)
                        .put("root", f.root).put("sig", Base64.encodeToString(sig, Base64.NO_WRAP)))
                    if (a.code == 200) signed++
                }
            }
            last = "keys=${f.keys} records=${f.records} pulled=$pulled refused=$refused bad=${f.bad} waiting=${f.waiting} T=$T root=${f.root.take(12)} " +
                "same=${if (same) 1 else 0} node_keys=${r.obj?.optInt("keys")} node_records=${r.obj?.optInt("records")} signed=$signed" + if (CoinTx.WRITES) "" else " (writes off)"
            Log.d("Montana", "coin_replica why=$why $last")
            f.mine?.let { m -> Log.d("Montana", "coin_replica mine proven=${m.proven} declared=${m.declared} height=${m.height} v3=${m.v3}") }
        } catch (e: Exception) {
            Log.w("Montana", "coin_replica " + e.javaClass.simpleName)
        } finally { running = false }
    }
}
