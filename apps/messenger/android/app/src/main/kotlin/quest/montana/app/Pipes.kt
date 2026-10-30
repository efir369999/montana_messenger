package quest.montana.app

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

// ─────────────────────────── the wire (iOS MTNodeWire, MTPipe) ───────────────────────────

/**
 * THE FROZEN FORMULAS OF THE NODE WIRE, byte for byte as iOS writes them (MTNodeWire): every label and key is
 * SHA-256(domain ‖ 0x00 ‖ parts…), a window laid little-endian in eight bytes. The seal itself is the core's
 * (mt_e2e_seal_blob); nothing here is a cipher. `agreesWithCanon` holds the iOS vectors: a drift of one byte
 * and no letter leaves.
 */
object Wire {
    fun sha(vararg parts: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").run { parts.forEach { update(it) }; digest() }
    private fun d(domain: String) = domain.toByteArray() + byteArrayOf(0)
    fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    fun le8(w: Long) = ByteArray(8) { i -> (w ushr (8 * i)).toByte() }
    fun minute() = System.currentTimeMillis() / 60_000
    fun day() = System.currentTimeMillis() / 86_400_000

    /** The raw seal key of the set: SHA-256("mt-pipe-key" ‖ 0 ‖ step_secret ‖ W_LE) — held by the canon vectors (iOS MTNodeWire.sealKey). */
    fun sealKey(stepSecret: ByteArray, w: Long) = sha(d("mt-pipe-key"), stepSecret, le8(w))
    /** The letter body key of a minute: the seal key under the pipe secret of that minute's day (iOS MTNodeWire.bodyKey). */
    fun bodyKey(secret: ByteArray, w: Long) = sealKey(pipeSecret(secret, w / MINUTES_PER_DAY), w)
    /** The conversation's daily label at the node, over the pipe secret of that day. */
    fun convW(secret: ByteArray, day: Long) = convTag(pipeSecret(secret, day), day)
    /** The canon's daily label over the day's secret: SHA-256("mt-wake-conv" ‖ 0 ‖ day_secret ‖ W_LE) — held by the wake vectors apart from the walk (iOS MTNodeWire.convTag). */
    fun convTag(daySecret: ByteArray, day: Long) = hex(sha(d("mt-wake-conv"), daySecret, le8(day)))

    /**
     * THE PIPE SECRET WALKS WITH THE CLIENT'S DAY (iOS MTNodeWire.pipeSecret, 1d8aa430): pipe_secret(D + 1) =
     * SHA-256("mt-pipe-ratchet" ‖ 0 ‖ pipe_secret(D)), one step a day, standing still through WALK_ANCHOR_DAY so every key up
     * to that day is the one the earlier builds derive; a day read off a node's time is clamped to MAX_WALK steps, so a forged
     * time costs a bounded walk and opens nothing. The last value of each secret is kept: the box walks back minute by minute.
     */
    const val WALK_ANCHOR_DAY = 20754L   // 28.10.2026 UTC
    const val MINUTES_PER_DAY = 1440L
    const val MAX_WALK = 36_600L
    /**
     * THE ROOT OF A CONVERSATION (iOS MTNodeWire.convRoot, 43369c12, 21d43fae; the author's word 21.10.2026 15:2x MSK): SHA-256(
     * «mt-conv-root» ‖ 0 ‖ the established secret). The author field of a letter stands on the root from the day after
     * WALK_ANCHOR_DAY, never on the established secret, so the walk can erase that secret; the root opens no letter. (The coin
     * SEND's blind stands on it too on iOS: Android lays no v3 SEND yet.)
     */
    fun convRoot(secret: ByteArray): ByteArray = if (isFloor(secret)) part(secret, 1) else sha(d("mt-conv-root"), secret)
    /** The key an item laid today stands on: the root past the anchor, the established secret up to it (iOS itemKey); a floor has only the root. */
    fun itemKey(secret: ByteArray, day: Long = Wire.day()): ByteArray = if (day > WALK_ANCHOR_DAY || !holdsOrigin(secret)) convRoot(secret) else secret
    /** The keys a received item may stand on, the root first: the sender's day is its own clock (iOS itemKeys). */
    fun itemKeys(secret: ByteArray): List<ByteArray> = if (holdsOrigin(secret)) listOf(convRoot(secret), secret) else listOf(convRoot(secret))
    private val walked = HashMap<String, Pair<Long, ByteArray>>()
    private fun steps(day: Long) = (day - WALK_ANCHOR_DAY).coerceIn(0L, MAX_WALK)
    /** The value of the walk on a day: from the established secret, or from the floor forward; a day before the floor gets the
     *  floor's own value -- the walk never goes back (iOS MTPipeKey.walked). */
    fun pipeSecret(secret: ByteArray, day: Long): ByteArray {
        val floor = isFloor(secret)
        val base = if (floor) steps(floorDay(secret)) else 0L
        val start = if (floor) part(secret, 0) else secret
        val target = steps(day)
        if (target <= base) return start
        val id = hex(start)
        synchronized(walked) {
            var at = base
            var value = start
            walked[id]?.let { (s, v) -> if (s in at..target) { at = s; value = v } }
            while (at < target) { value = sha(d("mt-pipe-ratchet"), value); at++ }
            if (walked.size >= 256) walked.clear()
            walked[id] = target to value
            return value
        }
    }
    /** The daily label of a handed-out invitation (the first letter's box). */
    fun rdvConvW(inv: ByteArray, day: Long) = hex(sha(d("mt-rdv-wake"), inv, le8(day)))
    /** The subscription tag standing in for the device at the node. */
    fun subId(conv: String, ref: String) = hex(sha(d("mt-wake-sub"), conv.toByteArray(), byteArrayOf(0), ref.toByteArray()))
    /** The first-meeting letter's key, derived from the invitation (iOS rdvLetterSecret). */
    fun rdvLetterSecret(inv: ByteArray) = sha(d("mt-rdv-letter"), inv)
    /** The local name of a correspondence: SHA-256(secret)[0..16] in hex (iOS MTPipeBook.reference). */
    fun reference(secret: ByteArray) = hex(if (isFloor(secret)) secret.copyOfRange(FLOOR_SIZE - 16, FLOOR_SIZE) else sha(secret).copyOf(16))

    // ── the pipe's quantities and the overlay's (iOS MTPipe 15-112, MontanaOverlayKey.tag, MontanaWindowPos) ──
    /** The one composition of the set (iOS MTPipe.domained): SHA-256(domain ‖ 0 ‖ parts…). */
    fun domained(domain: String, vararg parts: ByteArray): ByteArray = sha(d(domain), *parts)
    /** The tag of a pipe: where a letter is laid in this window, and nowhere else (iOS MTPipe.tag). */
    fun pipeTag(secret: ByteArray, w: Long) = domained("mt-tag", secret, le8(w)).copyOf(16)
    /**
     * THE TAG WALKS FROM 01.11 (iOS MTPipeKey.tag/tags, a8173d52, OZ1 decision 126): from TAG_WALK_DAY (Y = 20758) the tag of a
     * window stands on the walked secret of the window's day, before it on the established secret as every build laid it; on Y
     * and Y + 1 a receiver still hears the tag laid over the established secret, so an earlier build's letter is not lost.
     */
    const val TAG_WALK_DAY = WALK_ANCHOR_DAY + 4   // 20758, 01.11.2026 UTC
    const val ERASE_DAY = TAG_WALK_DAY + 2         // 20760, 03.11.2026 UTC
    fun windowTag(secret: ByteArray, w: Long): ByteArray {
        val day = w / MINUTES_PER_DAY
        return pipeTag(if (day >= TAG_WALK_DAY || !holdsOrigin(secret)) pipeSecret(secret, day) else secret, w)
    }
    fun windowTags(secret: ByteArray, w: Long): List<ByteArray> {
        val day = w / MINUTES_PER_DAY
        val now = windowTag(secret, w)
        return if (holdsOrigin(secret) && day >= TAG_WALK_DAY && day < ERASE_DAY) listOf(now, pipeTag(secret, w)) else listOf(now)
    }

    /**
     * THE FLOOR (iOS MTPipeKey.floored/sealedForm, a8173d52, OZ1 decision 126): from ERASE_DAY the established secret is erased and a
     * pipe holds the walk's value at F = D - 2 (the earliest day a box read listens at) and the quantities it keeps for good, in the
     * form iOS seals: 0x01 ‖ F (8 LE) ‖ ps(F) ‖ root ‖ rank ‖ fingerprint material ‖ face name ‖ face key ‖ pair tag (32 each) ‖
     * reference (16) -- 249 bytes. A pipe's bytes are its thirty-two established bytes or this floor, and every derivation of this
     * object reads either; nothing outside it looks inside.
     */
    const val FLOOR_FORM: Byte = 0x01
    const val FLOOR_SIZE = 1 + 8 + 32 * 7 + 16
    const val FLOOR_LAG = 2L
    fun isFloor(p: ByteArray) = p.size == FLOOR_SIZE && p[0] == FLOOR_FORM
    /** Whether this device still holds the established secret: up to ERASE_DAY, never again once the walk erased it. */
    fun holdsOrigin(p: ByteArray) = p.size == 32
    /** A pipe: thirty-two bytes or the floor the walk left of them; a record of another size is no pipe. */
    fun isWhole(p: ByteArray) = p.size == 32 || isFloor(p)
    private fun part(p: ByteArray, n: Int) = p.copyOfRange(9 + 32 * n, 41 + 32 * n)
    private fun floorDay(p: ByteArray) = (0 until 8).fold(0L) { a, i -> a or ((p[1 + i].toLong() and 0xff) shl (8 * i)) }
    /** This pipe's place in the one order both ends compute alike, the same bytes before the erasure and after (iOS sameRank). */
    fun sameRank(p: ByteArray): ByteArray = if (isFloor(p)) part(p, 2) else sha(d("mt-same-rank"), p)
    /** The safety number's material: 5200 rounds of SHA-256("mt-safety" ‖ 0 ‖ h) (iOS MTNodeWire.fingerprintMaterial). */
    fun fingerprintMaterial(p: ByteArray): ByteArray {
        if (isFloor(p)) return part(p, 3)
        var h = p
        repeat(5200) { h = sha(d("mt-safety"), h) }
        return h
    }
    /** The name of the pipe face's blob and its key (iOS MTPipeKept.faceBid/faceKey). */
    fun faceBid(p: ByteArray): String = hex(if (isFloor(p)) part(p, 4) else sha(d("mt-pipe-f"), p))
    fun faceKey(p: ByteArray): ByteArray = if (isFloor(p)) part(p, 5) else sha(d("mt-pipe-fk"), p)
    /** The coin pair's tag: HMAC-SHA-256(secret, «mt-coin-pair-v1») (iOS MTCoinTx.pairTag), kept in the floor. */
    fun pairTag(p: ByteArray): ByteArray = if (isFloor(p)) part(p, 6)
        else Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(p, "HmacSHA256")) }.doFinal("mt-coin-pair-v1".toByteArray())
    /** The pipe as this device may hold it on a day: up to ERASE_DAY as it is; from it the floor at F = D - 2, walked forward from
     *  the floor already held, never back. The established secret leaves the value here (iOS MTPipeKey.floored). */
    fun floored(p: ByteArray, day: Long = day()): ByteArray {
        if (day < ERASE_DAY || !isWhole(p)) return p
        val f = day - FLOOR_LAG
        if (isFloor(p) && floorDay(p) >= f) return p
        val ref = if (isFloor(p)) p.copyOfRange(FLOOR_SIZE - 16, FLOOR_SIZE) else sha(p).copyOf(16)
        return byteArrayOf(FLOOR_FORM) + le8(f) + pipeSecret(p, f) + convRoot(p) + sameRank(p) + fingerprintMaterial(p) +
            (if (isFloor(p)) part(p, 4) else sha(d("mt-pipe-f"), p)) + faceKey(p) + pairTag(p) + ref
    }
    /** The day F a floor holds the walk at; null while the pipe holds the established secret. */
    fun floorDayOf(p: ByteArray): Long? = if (isFloor(p)) floorDay(p) else null
    /**
     * ONE PIPE MET AGAIN (iOS MTPipeKey.samePipe, 67332869, decision 188, #37): two pipes are one when equal, or when both, walked to the
     * later floor day of the two, give the same whole floor -- the walk's value, root, rank, fingerprint, face name and key, pair and
     * reference. Never the reference alone: a pipe that differs in any one kept quantity is another. Two whole secrets are one only equal.
     */
    fun samePipe(a: ByteArray, b: ByteArray): Boolean {
        if (a.contentEquals(b)) return true
        val f = listOfNotNull(floorDayOf(a), floorDayOf(b)).maxOrNull() ?: return false
        val x = floored(a, f + FLOOR_LAG); val y = floored(b, f + FLOOR_LAG)
        return isFloor(x) && isFloor(y) && x.contentEquals(y)
    }
    /** Of two pipes that are one, the one a book keeps: the further floor; a whole secret met again is never written over a floor. */
    fun further(a: ByteArray, b: ByteArray): ByteArray {
        val o = floorDayOf(b) ?: return a
        val s = floorDayOf(a) ?: return b
        return if (o > s) b else a
    }
    /** The label of one step, from the secret two neighbouring machines share (iOS MTPipe.stepLabel). */
    fun stepLabel(secret: ByteArray, w: Long) = domained("mt-step", secret, le8(w)).copyOf(16)
    /** The seal a hop lays so the owners inside one delivery are counted distinct (iOS MTPipe.relaySeal). */
    fun relaySeal(owner: ByteArray, label: ByteArray) = domained("mt-relay-seal", owner, label).copyOf(16)
    /** How one sender tells two owners apart among its entries; two senders get references that do not join (iOS MTPipe.ownerRef). */
    fun ownerRef(owner: ByteArray, secret: ByteArray) = domained("mt-owner-ref", owner, secret).copyOf(16)
    /** The owner branch of a seed, one value on every machine of one person (iOS MTPipe.ownerSecret: the role seed «mt-owner-key»). */
    fun ownerSecret(master: ByteArray): ByteArray? = MtBindings.nativeRoleSeed(master, "mt-owner-key")
    /** A machine's address on the overlay, from its answering key (iOS MontanaOverlayKey.tag). */
    fun overlayTag(authPub: ByteArray) = domained("mt-overlay", authPub)
    /** A machine's position in a window: whoever is acquainted with it recognises it, an outsider joins nothing (iOS MontanaWindowPos.of). */
    fun windowPos(overlay: ByteArray, w: Long) = domained("mt-pos", overlay, le8(w))
    /** My positions in the accepted windows — the neighbouring ones too, because clocks drift (iOS MontanaWindowPos.mine). */
    fun myPositions(overlay: ByteArray): List<ByteArray> = minute().let { w -> listOf(w - 1, w, w + 1).map { windowPos(overlay, it) } }
    /**
     * THE HOLDER OF A TAG (iOS MTPipe.holder 103-112): the machine whose commitment is the least one standing above the tag, the
     * lowest of all when none stands above it — the ring closes rather than ending.
     */
    fun holder(tag: ByteArray, commitments: List<ByteArray>): ByteArray? {
        val sorted = commitments.sortedWith { a, b -> order16(a, b) }
        return sorted.firstOrNull { order16(tag, it) < 0 } ?: sorted.firstOrNull()
    }
    /** The order of Swift's lexicographicallyPrecedes over the first sixteen bytes: unsigned, a shorter prefix first. */
    private fun order16(a: ByteArray, b: ByteArray): Int {
        val n = minOf(16, a.size, b.size)
        for (i in 0 until n) { val x = a[i].toInt() and 0xff; val y = b[i].toInt() and 0xff; if (x != y) return x - y }
        return minOf(16, a.size) - minOf(16, b.size)
    }
    private fun unhex(h: String) = ByteArray(h.length / 2) { h.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    fun seal(key: ByteArray, plain: ByteArray): ByteArray? {
        val nonce = MtBindings.nativeRandom(12) ?: return null
        return MtBindings.nativeSealBlob(key, nonce, plain)
    }
    fun open(key: ByteArray, sealed: ByteArray): ByteArray? = MtBindings.nativeOpenBlob(key, sealed)

    /** A boxed letter wears the SENDER's minute, the node names the minute it took it: the walk goes back a day. */
    fun openBoxed(sealed: ByteArray, secret: ByteArray, atS: Long): ByteArray? {
        val w0 = atS / 60
        for (w in longArrayOf(w0, w0 - 1, w0 + 1)) open(bodyKey(secret, w), sealed)?.let { return it }
        var w = w0 - 2
        repeat(1439) { open(bodyKey(secret, w), sealed)?.let { return it }; w-- }
        return null
    }

    /** mid‖0‖text‖0‖name‖0‖glyph‖0‖quote‖0‖quoted mid‖0‖card‖0‖author — eight fields, an absent one empty (iOS MTNodeWire.letterFields). */
    fun fields(plain: ByteArray, from: Int = 0): List<String> {
        val out = ArrayList<String>(AUTHOR_FIELDS + 1)
        var i = from
        while (out.size <= AUTHOR_FIELDS) {
            var z = i
            while (z < plain.size && plain[z] != 0.toByte()) z++
            out.add(String(plain, i, z - i, Charsets.UTF_8))
            if (z >= plain.size) break
            i = z + 1
        }
        while (out.size <= AUTHOR_FIELDS) out.add("")
        return out
    }

    /** One size for every envelope — the node cannot tell letter lengths apart (iOS envelopeSize). */
    const val ENVELOPE = 2048

    /**
     * THE LETTER'S AUTHOR IS THE PERSON, NOT THE DEVICE (iOS MTNodeWire.authorTag, withAuthor, authorHolds; cd109c31): a pipe's
     * secret is held by every device of one person and by the correspondent, and a letter named no author -- the words of my
     * other device reached me on the same pipe as the correspondent's and stood as theirs. The eighth field is HMAC-SHA-256 under
     * the person's author key (LetterAuthor) over «mt-letter-author» 0 ‖ the pipe's raw secret ‖ mid ‖ 0 ‖ the words as they ride,
     * cut to sixteen bytes in base64. The correspondent holds sixteen bytes it can neither open nor make; an older build reads seven.
     */
    const val AUTHOR_FIELDS = 7   // the fields before the author: mid, text, name, glyph, quote, quoted mid, card
    fun authorTag(key: ByteArray, secret: ByteArray, mid: String, text: String): String {
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }
        val m = d("mt-letter-author") + secret + mid.toByteArray() + byteArrayOf(0) + text.toByteArray()
        return Base64.encodeToString(mac.doFinal(m).copyOf(16), Base64.NO_WRAP)
    }
    /** Whether a letter's author field is this person's: the tag made again under this person's key, compared in constant time,
     *  over the conversation's root first, then the established secret (iOS authorHolds over itemKeys, 21d43fae). */
    fun authorHolds(tag: String, key: ByteArray?, secret: ByteArray, mid: String, text: String): Boolean {
        if (key == null || key.size != 32 || tag.isEmpty()) return false
        val got = runCatching { Base64.decode(tag, Base64.NO_WRAP) }.getOrNull()?.takeIf { it.size == 16 } ?: return false
        return itemKeys(secret).any { k ->
            val want = Base64.decode(authorTag(key, k, mid, text), Base64.NO_WRAP)
            var diff = 0
            for (i in 0 until 16) diff = diff or (got[i].toInt() xor want[i].toInt())
            diff == 0
        }
    }
    /** The body with the author's field: every field before it closed and the empty ones written, so the tag stands eighth
     *  whatever the letter carries; a body that would outgrow the envelope rides without it. */
    fun withAuthor(body: ByteArray, key: ByteArray?, secret: ByteArray, mid: String, text: String, day: Long = Wire.day()): ByteArray {
        if (key == null || key.size != 32) return body
        var b = body
        if (b.isNotEmpty() && b.last() != 0.toByte()) b += byteArrayOf(0)
        val closed = b.count { it == 0.toByte() }
        if (closed > AUTHOR_FIELDS) return body
        b += ByteArray(AUTHOR_FIELDS - closed)
        b += authorTag(key, itemKey(secret, day), mid, text).toByteArray() + byteArrayOf(0)
        return if (b.size <= ENVELOPE) b else body
    }
    /**
     * The author's vectors, derived apart from this code (python hmac): key = bytes 0..31, secret = bytes 32..63. They reject a tag
     * without its domain (N7afF/Hi…), plain SHA-256 in place of the HMAC (87X47Wdd…), mid and words swapped, no zero between mid
     * and words («ab», «c» and «a», «bc» would both be y6GqbLv5…), the URL alphabet (the first vector carries «/»), words read other
     * than UTF-8 (the Cyrillic one); the body's vectors reject a tag that is not the eighth field or rides past the envelope.
     */
    fun authorAgreesWithCanon(): Boolean {
        val k = ByteArray(32) { it.toByte() }
        val s = ByteArray(32) { (32 + it).toByte() }
        val a = "t1760000000000-A"
        val tag = authorTag(k, s, a, "hello")
        val head = (a + "\u0000hello\u0000\u0000\u0000").toByteArray()
        val signed = withAuthor(head, k, s, a, "hello", WALK_ANCHOR_DAY)
        val carded = withAuthor((a + "\u0000hello\u0000\u0000\u0000\u0000\u0000{\"u\":1}").toByteArray(), k, s, a, "hello", WALK_ANCHOR_DAY)
        val big = head + ByteArray(ENVELOPE - head.size - 10) { 0x41.toByte() }
        // past the anchor the tag stands on the conversation's root (python hmac over SHA-256(«mt-conv-root» 0 ‖ s), apart from
        // this code): a signer keeping the secret past the anchor fails it, and a reader trying the root alone fails the anchor day
        val rootTag = "j6XVy+w+ZQ6QHFKBfIY30g=="
        val past = withAuthor(head, k, s, a, "hello", WALK_ANCHOR_DAY + 1)
        val anchor = withAuthor(head, k, s, a, "hello", WALK_ANCHOR_DAY)
        return tag == "BlkjB/780CuSnoy9yO1MCg=="
            && authorTag(k, convRoot(s), a, "hello") == rootTag
            && fields(past)[7] == rootTag && fields(anchor)[7] == tag
            && authorHolds(rootTag, k, s, a, "hello") && !authorHolds(rootTag, k, s, a, "hello!")
            && authorTag(k, s, "hello", a) == "ccFvBbdQCRxil2lLe0NGfw=="
            && authorTag(k, s, "ab", "c") == "AmHB/IBs8lxFI/6uUuKpRg=="
            && authorTag(k, s, "a", "bc") == "gLG9utiVXFsSGWjgeQwT6A=="
            && authorTag(k, s, a, "Привет") == "zueZYAzrw98jjZrbBUVPdw=="
            && authorHolds(tag, k, s, a, "hello") && !authorHolds(tag, k, s, a, "hello!") && !authorHolds("", k, s, a, "hello")
            && fields(signed)[1] == "hello" && fields(signed)[7] == tag && signed.size == head.size + 3 + tag.length + 1
            && fields(carded)[6] == "{\"u\":1}" && fields(carded)[7] == tag
            && withAuthor(big, k, s, a, "hello").contentEquals(big)
            && withAuthor(head, null, s, a, "hello").contentEquals(head)
    }

    /**
     * The iOS vectors (MontanaWakePush.agreesWithCanon, MTPipe body key and walk). The wake and seal vectors stand on the raw
     * formulas: their windows lie past the anchor, so read through convW and bodyKey they would walk (8983 steps: 86d838dd…;
     * 36600 steps: 53a282b6…). The walk's vectors reject one that never steps (a656c407…), one stepping once whatever the
     * distance (1110b376…), one stepping by the day's number rather than its distance from the anchor, one without the domain
     * (630dcd29…).
     */
    fun agreesWithCanon(): Boolean {
        val s32 = ByteArray(32) { it.toByte() }
        val a = WALK_ANCHOR_DAY
        return subId("mt-conv-Q7", "mtAddrZ93kLmNoPq") == "e5438bfedc8b1fdcdadfb9f4d3995fac7722c0074f3a20ccd3e911ce5beb35de"
            && subId("ab", "c") == "a279974b24ff1b84299330076b5f5858684d56733458de21b152aa8521c7a230"
            && subId("a", "bc") == "c04b7d58e4c7aaca35800d119fd6fde021f95f7d3c9438e3ca46cd855afe6a8a"
            && convTag(s32, 29737) == "43eaf2811da7947166d4e851e52c4ab89e09c8c92247370d3c734ef08ca1e6ea"
            && convTag(s32, 29738) == "f5f2941435d76c0a80dd229722ef42382695e88fdd1fabf89d71f317bef05430"
            && hex(sealKey(s32, 0x0102030405060708)) == "e55fbc1e0f95c4fe012b476c4dd1a51c9455e24641248f4f1557ed57f8c14f35"
            && hex(bodyKey(s32, 1000)) == "e25542e65a84d1a5b5c72a13172ecb62319c18f21a59978a53e7dac2c22a966a"
            && pipeSecret(s32, a).contentEquals(s32)
            && hex(pipeSecret(s32, a + 1)) == "5dcfd87692fcd444a4344d756dfa37abe670d2eb252aa9b402646be97cf3c50a"
            && hex(pipeSecret(s32, a + 2)) == "0c31775e80ae463de61fecee68bee8bb4ebbcee8e6b2045f8714e93ef18cb1b0"
            && hex(bodyKey(s32, (a + 2) * MINUTES_PER_DAY)) == "925378a4bb83e7137cbb1f8cdaba8b79fc37e30d3159e4158da6e0fee8518bb5"
            && convW(s32, a) == "d29425fcf807a325b74d8bb017420cfe2250cc47e8bdc6351f6006cd4a6bdc9b"
            && convW(s32, a + 2) == "c665fdca8978b9c6e54b9a4f16a06ccac657ba7da259df0a8f3e2550d7c2d518"
            // the root of a conversation (iOS MTPipe.agreesWithCanon, 43369c12): without the zero separator (3be77415…) or in the
            // walk's domain (5dcfd876…) it fails; the anchor day still stands on the established secret
            && hex(convRoot(s32)) == "d9c3e7f533da2d0ed10b6729601c478ab29d1b0cafed60443113ee6a63824e11"
            && itemKey(s32, a).contentEquals(s32) && itemKey(s32, a + 1).contentEquals(convRoot(s32))
            && itemKeys(s32).let { it.size == 2 && it[0].contentEquals(convRoot(s32)) && it[1].contentEquals(s32) }
    }

    /**
     * The iOS vectors of the pipe (MTPipe.agreesWithCanon 160-194), and our own for the window position and the overlay address:
     * they stand on thirty-two distinct bytes and a window with bits at both ends, so a window laid most-significant first
     * (c9b2d923…) or a hash without its domain (274f6dfc…, 95b95398…) fails them. Derived from the set's formula apart from this code.
     * The channel stands on this check; the box keeps its own (agreesWithCanon), so a drift here can never silence the letters.
     */
    fun pipeAgreesWithCanon(): Boolean {
        fun r(b: Int, n: Int) = ByteArray(n) { b.toByte() }
        val s32 = ByteArray(32) { it.toByte() }
        val owner = r(0x99, 32)
        val ring = listOf(r(0x10, 32), r(0x90, 32))
        return hex(pipeTag(r(0x44, 32), 1000)) == "1d99467017fe1d0cc7c7ba29df6fd1b6"
            && hex(pipeTag(r(0x44, 32), 1001)) == "c146445f67c990e25256dd88dfb39a49"
            && hex(pipeTag(r(0x55, 32), 1000)) == "783b2b17dffaab016d1aca852f60ea3e"
            // the passage by the day (iOS mt-pipe-owner-check.py oracle, chain 969-972): s = bytes 0..31, window D*1440+5
            && hex(windowTag(s32, (TAG_WALK_DAY - 1) * MINUTES_PER_DAY + 5)) == "ec0c1a23e2450dd465356cd0b8175c4f"
            && windowTags(s32, TAG_WALK_DAY * MINUTES_PER_DAY + 5).map { hex(it) } == listOf("96d8937ada4908bcba9fd12c78b9c11c", "cc6997487bfa3ed9c4a7542be4fc2bbb")
            && windowTags(s32, (ERASE_DAY + 1) * MINUTES_PER_DAY + 5).map { hex(it) } == listOf("9e0c92b8f91b94880bf15eee1ca672c7")
            && hex(domained("mt-same-ask", convRoot(r(0x41, 32)), convRoot(r(0x42, 32))).copyOf(16)) == "652cacf2b156b3a11e0b19fa4e15752d"
            // the floor (iOS MTPipeKey.agreesWithCanon, chain 973-974): F = 20759 on the day after ERASE_DAY, its form byte for byte, and a
            // floored pipe deriving what the pipe derived
            && floored(s32, ERASE_DAY - 1).contentEquals(s32)
            && floored(s32, ERASE_DAY + 1).let { f ->
                isFloor(f) && !holdsOrigin(f) && isWhole(f) && floored(f, ERASE_DAY + 1).contentEquals(f)
                    && hex(pipeSecret(f, 20759)) == "047f100cb7db75364efcefe4b58cf0038b1e1bc441884b06b5674eaf7b857523"
                    && pipeSecret(f, 0).contentEquals(pipeSecret(f, 20759))
                    && hex(sha(f)) == "da6e42f21c5935263ba7339fdc38adfd36db060a69d335f97e21f0dfbf1ae119"
                    && hex(windowTag(f, (ERASE_DAY + 1) * MINUTES_PER_DAY + 5)) == "9e0c92b8f91b94880bf15eee1ca672c7"
                    && bodyKey(f, (ERASE_DAY + 3) * MINUTES_PER_DAY).contentEquals(bodyKey(s32, (ERASE_DAY + 3) * MINUTES_PER_DAY))
                    && convW(f, ERASE_DAY + 1) == convW(s32, ERASE_DAY + 1) && reference(f) == reference(s32)
                    && convRoot(f).contentEquals(convRoot(s32)) && sameRank(f).contentEquals(sameRank(s32))
                    && faceBid(f) == faceBid(s32) && faceKey(f).contentEquals(faceKey(s32)) && itemKeys(f).size == 1
                    // one pipe met again (iOS floor-188-tests, #37): the secret and its floors of any two days are one pipe, the book keeps
                    // the further floor; another secret is another pipe, whatever the day
                    && floored(s32, ERASE_DAY + 3).let { g ->
                        samePipe(f, s32) && samePipe(s32, g) && samePipe(f, g) && further(f, g) === g && further(g, f) === g
                            && further(f, s32) === f && further(s32, f) === f && !samePipe(f, floored(r(0x56, 32), ERASE_DAY + 1))
                            && !samePipe(s32, r(0x56, 32))
                    }
            }
            && hex(stepLabel(r(0x51, 32), 1000)) == "4b8cb5c6442a52d0750bfb4fac0ba39d"
            && hex(stepLabel(r(0x52, 32), 1000)) == "401d8ab71a2e2554ab30c11aab1ae97d"
            && hex(stepLabel(r(0x51, 32), 1001)) == "1cc3ac539a8b1d2701e489455a8b04d5"
            && hex(relaySeal(owner, r(0xAA, 16))) == "2c2231f087682d4daef313938a2da5e0"
            && hex(relaySeal(owner, r(0xBB, 16))) == "3e83b1e1610e48bfc13929a602617d79"
            && hex(ownerRef(owner, r(0x44, 32))) == "f4f72dafb742470e49defbd3c2326c27"
            && hex(ownerRef(owner, r(0x45, 32))) == "d24f63a8c1220ea9c176ec706b8a256f"
            && holder(unhex("45468cdd9bcdebe6f622c46257c27fe3"), ring).contentEquals(ring[1])
            && holder(r(0xFF, 16), ring).contentEquals(ring[0])
            && hex(windowPos(s32, 0x0102030405060708)) == "6f241143b5736f8ee9af63cd2db6fbf59b5bbc22069cc045307e8862e3ed6f8f"
            && hex(windowPos(s32, 1000)) == "db09ddb4cd56d677bd1f9fdc00a6894bc088b2cb8a382eaeb1f76644f2f95eec"
            && hex(overlayTag(ByteArray(1952) { ((it * 7 + 3) % 256).toByte() })) == "f2c55658958eee8b961a4d63c2ec60a793cf9f22c373d115f3021523e3f0eabe"
    }

    /**
     * One POST of JSON to a door: the code and the body (a door that does not answer is -1). `lane` — the signal lane's book of
     * requests in flight: a path change or the lane door's death cuts every one of them at once (Signal.cut). `whole` — the body of
     * a refusal too: where the code alone does not say it (the plane of names: a 404 is «nobody holds it» only in the keeper's words).
     */
    fun post(door: String, path: String, body: JSONObject, timeout: Int = 8000, lane: MutableSet<HttpURLConnection>? = null,
             whole: Boolean = false): Pair<Int, String?> {
        var held: HttpURLConnection? = null
        return try {
            val raw = body.toString().toByteArray(Charsets.UTF_8)
            val conn = URL(door + path).openConnection() as HttpURLConnection
            held = conn
            lane?.let { synchronized(it) { it.add(conn) } }
            conn.requestMethod = "POST"; conn.doOutput = true
            conn.connectTimeout = timeout; conn.readTimeout = timeout
            conn.setRequestProperty("content-type", "application/json")
            conn.setFixedLengthStreamingMode(raw.size)
            conn.outputStream.use { it.write(raw) }
            val code = conn.responseCode
            // the node's clock, in passing: the lane's answer and the diary's ship, one owner (iOS learnSkew 3304, 3789)
            if (path == "/signal-fetch" || path == "/diag-put") NodeClock.learn(conn)
            val text = if (code == 200) conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
                else if (whole) conn.errorStream?.use { it.readBytes().toString(Charsets.UTF_8) } else null
            conn.disconnect()
            code to text
        } catch (_: Exception) { -1 to null } finally { held?.let { c -> lane?.let { synchronized(it) { it.remove(c) } } } }
    }

    /** A blob onto the node (iOS putBlob): POST /blob-put {bid, data}; true once a door holds it. */
    /**
     * A CHUNK ALREADY ON THE NODE IS NOT SENT AGAIN (iOS putBlob 1000-1012, 08.09): the name is the content — one small question first,
     * the bytes only when the node lacks them. A walk that knows its chunks are new (their key was drawn this moment) says so and
     * skips the question; a retry after a road that broke mid-answer asks, so a chunk the node took is not carried twice.
     */
    fun putBlob(bid: String, data: ByteArray, cargo: String? = null, last: Boolean = false, assumeAbsent: Boolean = false): Boolean {
        if (!assumeAbsent && blobsHave(listOf(bid))?.contains(bid) == true) { Log.d("Montana", "blob_put already on the node id=" + bid.take(8)); return true }
        // A CHUNK GOES TO THE NEXT LIVE DOOR THE MOMENT THE FIRST ONE DIES (iOS build 1894): the doors that answered on this path
        // first, a resting one last, and every answer taught to the door book — a dead door held a piece its whole minute
        return Signal.writeOrder("blob").any { door -> putBlobAt(door, bid, data, cargo, last) }   // the elected store first (iOS 2007)
    }
    /**
     * What the node already holds of these chunks (iOS blobsPresent, askHave 1941-1981): only the chunks asked about count — a store
     * naming others is a stale index and is not believed, and the diary names it; null is «don't know».
     * THE QUESTION COSTS ONE ROUND TRIP, NEVER A WALK (iOS 18.09): the stores are asked AT ONCE under the one post deadline of five
     * seconds — one after another with ten seconds each, a fresh cargo walked the list until a dead door hung it. An upload's savings
     * ask only the store the bytes are going to; `everyStore` is for a verdict of loss: one silent store makes it «don't know».
     */
    fun blobsHave(bids: List<String>, everyStore: Boolean = false): Set<String>? {
        if (bids.isEmpty()) return null
        val doors = Signal.writeOrder("blob").let { if (everyStore) it else it.take(1) }
        if (doors.isEmpty()) return null
        val t0 = System.currentTimeMillis()
        val asked = bids.toSet()
        val answers = arrayOfNulls<Set<String>>(doors.size)
        doors.mapIndexed { i, door -> Thread { answers[i] = askHave(door, bids, asked) }.apply { start() } }
            .forEach { it.join(POST_DEADLINE_MS + 1_000L) }
        val have = HashSet<String>(); var silent = 0
        for (a in answers) if (a != null) have.addAll(a) else silent++
        val now = System.currentTimeMillis()
        if (now - haveSaidAt >= 30_000L) {   // folded to a line per half minute (iOS markFolded window 30)
            haveSaidAt = now
            Log.d("Montana", "blob_have doors=${doors.size} silent=$silent have=${have.size}/${bids.size} ms=${now - t0}")
        }
        if (have.size == bids.size) return have
        return if (silent > 0) null else have
    }
    @Volatile private var haveSaidAt = 0L
    private fun askHave(door: String, bids: List<String>, asked: Set<String>): Set<String>? {
        val (code, text) = post(door, "/blob-have", JSONObject().put("bids", JSONArray(bids)), POST_DEADLINE_MS)
        if (code != 200 || text == null) return null
        val h = runCatching { JSONObject(text).getJSONArray("have") }.getOrNull() ?: return null
        val named = (0 until h.length()).map { h.optString(it) }
        val foreign = named.count { it !in asked }
        if (foreign > 0) Log.d("Montana", "blob_have_foreign door=${android.net.Uri.parse(door).host ?: door} named=$foreign asked=${bids.size} — ignored")
        return named.filter { it in asked }.toSet()
    }
    // the one deadline of a post to a node (iOS MTNodeWire.postTimeoutS 299)
    private const val POST_DEADLINE_MS = 5_000
    /**
     * THE CARGO'S OWN DEADLINE (iOS MTNodeWire.cargoTimeoutS 301-306, 17.09): the knock's five seconds plus a second per sixteen
     * kilobytes — 64 KB waits 9 s, 512 KB waits 37 s; one rule for every road. A fixed minute held a dead door's piece a minute.
     */
    fun cargoTimeoutMs(bytes: Int): Int = 5_000 + (maxOf(0, bytes).toLong() * 1000 / 16_384).toInt()
    private fun putBlobAt(door: String, bid: String, data: ByteArray, cargo: String?, last: Boolean): Boolean {
        val body = JSONObject().put("bid", bid).put("data", Base64.encodeToString(data, Base64.NO_WRAP))
        if (cargo != null) { body.put("cg", cargo); if (last) body.put("last", true) }
        val code = post(door, "/blob-put", body, cargoTimeoutMs(data.size)).first
        if (code == 200) Signal.doorAnswered(door) else Signal.doorFailed(door, code)
        return code == 200
    }

    /**
     * CHUNKS EVERY DOOR HAS ALREADY CALLED GONE (iOS MontanaWakePush 2438-2453, 22.09; fork atoms 1829, 1884): the cargo of a letter
     * does not come back by being asked twice — a chunk every door answered 404 for is not asked again in this process, and the
     * memory is forgotten the moment a resting door answers again (a store that was silent may hold what the others did not).
     * Only a chunk of a letter's cargo is judged so; a silent door is not a gone chunk.
     */
    private val goneChunks = HashSet<String>()
    fun forgetGone() = synchronized(goneChunks) { goneChunks.clear() }
    fun isGone(bid: String) = synchronized(goneChunks) { bid in goneChunks }
    /** `busy` is raised when a door refused this moment (429 or 5xx: iOS BlobAnswer.busy, 1636-1691) -- a third answer, never «gone». */
    fun getChunk(bid: String, busy: BooleanArray? = null): ByteArray? {
        if (isGone(bid)) return null
        val stores = Doors.ordered("blob")   // another phone's chunk: every store of the network's list (iOS 1638)
        var gone = stores.isNotEmpty()
        for (door in stores) {
            val (code, text) = post(door, "/blob-get", JSONObject().put("bid", bid))
            if (code == 200 && text != null) runCatching { JSONObject(text).optString("data").takeIf { it.isNotEmpty() }?.let { return Base64.decode(it, Base64.DEFAULT) } }
            if (code != 404) gone = false
            if (code == 429 || code in 500..599) busy?.set(0, true)
        }
        if (gone) { synchronized(goneChunks) { goneChunks.add(bid) }; Log.d("Montana", "blob_dl gone at every door id=" + bid.take(8) + " — not asked again until a door revives") }
        return null
    }

    /** A long letter's blob and the stores' verdict (iOS askBlob): the bytes, or null with «gone» when every door answered 404. */
    fun getBlobVerdict(bid: String): Pair<ByteArray?, Boolean> {
        val stores = Doors.ordered("blob")
        var gone = stores.isNotEmpty()
        for (door in stores) {
            val (code, text) = post(door, "/blob-get", JSONObject().put("bid", bid))
            if (code == 200 && text != null) runCatching { JSONObject(text).optString("data").takeIf { it.isNotEmpty() }?.let { return Base64.decode(it, Base64.DEFAULT) to false } }
            if (code != 404) gone = false
        }
        return null to gone
    }

    /** A blob of the node (iOS getBlob): POST /blob-get {bid} → {data}. */
    fun getBlob(bid: String): ByteArray? {
        for (door in Doors.ordered("blob")) {
            val (code, text) = post(door, "/blob-get", JSONObject().put("bid", bid))
            if (code == 200 && text != null) runCatching { JSONObject(text).optString("data").takeIf { it.isNotEmpty() }?.let { return Base64.decode(it, Base64.DEFAULT) } }
        }
        return null
    }
}

// ─────────────────────────── the words a letter can carry (iOS ContentView marks) ───────────────────────────

object Marks {
    const val READ = "​⁣"          // «read», + the birth millisecond of the newest letter covered
    const val DELIVERED = "​⁤"     // «delivered», + the letter's mid
    const val REACTION = "​​RC:"   // {sid, txt, e, op}
    const val DELETE = "​​DL:"     // + "mid:" + the letter's mid
    const val DELETE_KEPT = "\u200B\u200BDK:"   // + the letter's wire name: the correspondent kept my deletion (iOS deleteKeptMark) -- never a row
    const val EDIT = "​​ED:"       // {sid, tx}
    const val NAME = "​​NM:"       // + the display name
    const val PIPE_CLOSED = "\u200B\u200BPX:"   // the pipe closed at the other end (iOS pipeClosedMark): never a row
    const val AVATAR = "\u200B\u200BAV:"     // + the face as base64 JPEG; empty — «no face»
    const val TYPING = "​​TY:"
    const val VOICE = "​​VC:"
    const val MEDIA = "​​MD:"
    const val STICKER = "⁣⁣"
    const val LONG = "⁣LB:"
    const val ABOUT = "\u200B\u200BAB:"   // + {b, l, at}: their bio and link (iOS aboutMark)
    const val PLAYED = "\u200B\u200BPL:"   // + the mid of a voice of theirs that was played here (iOS playedMark)
    const val SAME_ASK = "\u200B\u200BSM:"   // + base64 {t: [32 tags]}: \u00ABdo we already share a pipe?\u00BB (iOS sameAskMark)
    const val SAME_YES = "\u200B\u200BSY:"   // + base64 {p: proof or noise}: the answer (iOS sameYesMark)
    const val RING = "\u200B\u200BRG:"   // + {v, s, n, t}: a call as a letter (iOS ringMark) — it rings, never a row
    const val MISSED = "\u200B\u200BMC:"   // + {v, s}: the caller's «missed call» (iOS missedCallMark) — it lands as a call row
    const val CALL = "\u200B\u200BCL:"   // + {v, inc, dur, miss}: a call's row, laid by each phone for itself (iOS callMark), never sent
    const val RELEASE = "\u200B\u200BRL:"   // + {b, v, n, u, l}: a new build's word in the Montana room (iOS releaseMark), local, never sent
    /** A word of the wire, not a row of the feed. */
    fun isService(t: String) = t.startsWith("​") || t.startsWith("⁣")
    /**
     * A WORD OF THE WIRE NEVER RINGS (iOS isSilentLetter, isControlMarker): receipts, typing, drafts, the profile (name, face,
     * words, card, ground), deletions, edits, pins, presence, the set's and the wall's words ride a silent push — no banner on
     * their phone. Media, voice and stickers are letters and ring; a call's ring letter rings by its own road.
     */
    private val SILENT = listOf(READ, DELIVERED, TYPING, REACTION, AVATAR, NAME, ABOUT, "​​PG:", "​​QC:", DELETE,
        CONVDEL_MARK, "​​DF:", "​​WH:", "​​PA:", "​​EX:", "​​CG:", Presence.WATCH, PLAYED,
        Presence.APP, EDIT, PIN_MARK, "​​SP:", "​​WL:", SAME_ASK, SAME_YES, "​​PX:", LiveDraft.MARK)
    fun isSilent(t: String) = SILENT.any { t.startsWith(it) } || ChessLetter.silent(t)

    /** A letter's name: t<birth ms>-<UUID> (iOS ChatStore.mintMid). */
    private var lastMs = 0L
    @Synchronized fun mintMid(): String {
        var ms = System.currentTimeMillis()
        if (ms <= lastMs) ms = lastMs + 1
        lastMs = ms
        return "t$ms-" + UUID.randomUUID().toString().uppercase()
    }
    fun birthMs(mid: String): Long? {
        val core = mid.removePrefix("mid:")
        if (!core.startsWith("t")) return null
        val dash = core.indexOf('-').takeIf { it > 1 } ?: return null
        return core.substring(1, dash).toLongOrNull()
    }
}

// ─────────────────────────── the book of correspondences (iOS MTPipeBook + ChatStore) ───────────────────────────

/**
 * One letter of the feed. `state` is the rung of the ladder (iOS DeliveryStatus.rung): 0 sending, 1 sent, 2 delivered, 3 read;
 * -1 not sent. `statusAt` — the moment the rung was reached; `heard` — a voice played (theirs here, or mine there).
 */
class Msg(
    val mid: String, var text: String, val mine: Boolean, val at: Long,
    var state: Int = 0, var edited: Boolean = false,
    val qt: String? = null, val qm: String? = null,
    val reactions: MutableList<String> = mutableListOf(), var myReact: String? = null,
    var file: String? = null, var meta: String? = null,   // a media letter: the assembled file, and its manifest once known
    var statusAt: Long = 0, var heard: Boolean = false,
    var lp: String? = null,   // the link's card (iOS linkPreview, LinkPreview.kt): the body's seventh field
    val from: String? = null,   // a group's speaker (iOS Message.senderRef, Groups.speakerName); null in a pipe's own feed
    var peerReact: String? = null,   // the correspondent's one answer on this letter (iOS Message.peerReact): a new one replaces it
) {
    fun json(): JSONObject = JSONObject().put("m", mid).put("t", text).put("o", mine).put("at", at).put("s", state).put("e", edited)
        .put("qt", qt ?: "").put("qm", qm ?: "").put("r", JSONArray(reactions)).put("mr", myReact ?: "")
        .put("f", file ?: "").put("mm", meta ?: "").put("sa", statusAt).put("h", heard).put("lp", lp ?: "").put("sr", from ?: "").put("pr", peerReact ?: "")

    /** The moment the letter's rung was reached, or its birth (iOS Message.statusMoment). */
    val statusMoment: Long get() = if (statusAt > 0) statusAt else at

    /**
     * THE ONE DOOR TO THE RUNG (iOS ChatStore.advance): only forward; «read» only from «delivered» — reading what was never
     * received is impossible, and so is showing it; «not sent» only from «sending» or «sent» — the proven does not turn red.
     */
    fun advance(next: Int): Boolean {
        val ok = when (next) {
            -1 -> state == 0 || state == 1
            3 -> state == 2
            else -> next > state
        }
        if (ok) { state = next; statusAt = System.currentTimeMillis() }
        return ok
    }

    companion object {
        fun of(o: JSONObject) = Msg(o.getString("m"), o.getString("t"), o.getBoolean("o"), o.getLong("at"), o.optInt("s"), o.optBoolean("e"),
            o.optString("qt").ifEmpty { null }, o.optString("qm").ifEmpty { null },
            o.optJSONArray("r")?.let { a -> MutableList(a.length()) { a.getString(it) } } ?: mutableListOf(),
            o.optString("mr").ifEmpty { null }, o.optString("f").ifEmpty { null }, o.optString("mm").ifEmpty { null },
            o.optLong("sa"), o.optBoolean("h"), o.optString("lp").ifEmpty { null }, o.optString("sr").ifEmpty { null }, o.optString("pr").ifEmpty { null })
    }
}

private val CROWN_MARKS = setOf(0x1F451, 0x2654, 0x2655, 0x265A, 0x265B)
/**
 * A CROWN IS GIVEN, NEVER TYPED (iOS MTCrown.plain, MontanaNameBook.swift:7-21, atom d4142dd38143; the author's word
 * 03.10: «a system ban on crowns before a name -- only a Royal hands them out, as a verification»): no name a person
 * types or a correspondent sends wears a crown or one of its look-alikes.
 */
fun stripCrown(s: String): String {
    if (s.codePoints().noneMatch { it in CROWN_MARKS }) return s   // a name with no crown stands as typed, its spaces too (iOS plain 10)
    val plain = StringBuilder()
    var afterMark = false
    var i = 0
    while (i < s.length) {
        val point = s.codePointAt(i); i += Character.charCount(point)
        if (point in CROWN_MARKS) { afterMark = true; continue }
        if (afterMark && (point == 0xFE0F || point == 0xFE0E)) continue
        afterMark = false
        plain.appendCodePoint(point)
    }
    return plain.toString().split(' ').filter { it.isNotEmpty() }.joinToString(" ")
}

/**
 * `name` — the word the person gave themselves (their NM:, the card); `pin` — the name my hand set over it (iOS
 * MTNameBook.manual), and `note` — what I keep on them (iOS the card's note). What the screens show is `shown`.
 */
class Chat(val ref: String, var name: String, var perm: Boolean = false, var unread: Int = 0, val msgs: MutableList<Msg> = mutableListOf(),
           var pin: String? = null, var note: String = "") {
    /**
     * THE ANSWER IN THE ROW (iOS ChatStore.noteReaction / rowReaction, the author's word 20.09, atom dc65e5022221): the newest event of a
     * conversation may be an answer to a letter -- its sign, whose it is, the letter answered by its one name, and the answer's birth.
     */
    var ans: String? = null; var ansMine = false; var ansMid: String? = null; var ansAt = 0L
    fun json(): JSONObject = JSONObject().put("ref", ref).put("n", name).put("p", perm).put("u", unread)
        .put("pn", pin ?: "").put("nt", note)
        .put("ae", ans ?: "").put("am", ansMine).put("ar", ansMid ?: "").put("aat", ansAt)
        .put("msgs", JSONArray().apply { msgs.forEach { put(it.json()) } })
    val last: Msg? get() = msgs.lastOrNull { !ChessLetter.isStep(it.text) }   // a game's step is the board's, never the list's record
    /** Written by the two doors a reaction has, mine and theirs; an answer taken back leaves the row to the feed. */
    fun noteAnswer(e: String?, mine: Boolean, m: Msg, at: Long = System.currentTimeMillis()) {
        if (e.isNullOrEmpty()) { if (ansMid == m.mid) { ans = null; ansMid = null; ansAt = 0 }; return }
        ans = e; ansMine = mine; ansMid = m.mid; ansAt = at
    }
    /**
     * The letter the row's answer stands over, PROVEN (iOS answerStands): the answered letter is still in the feed, was born before the
     * answer, and no letter was born after the answer -- a newer letter takes the row back.
     */
    val answered: Msg? get() {
        if (ans.isNullOrEmpty()) return null
        val m = msgs.lastOrNull { it.mid == ansMid } ?: return null
        val tail = last ?: return null
        return m.takeIf { it.at <= ansAt && tail.at <= ansAt }
    }
    /** My word stands over theirs (iOS MTNameBook.display: mine, then declared). */
    val shown: String get() = pin?.ifBlank { null } ?: name
    companion object {
        fun of(o: JSONObject) = Chat(o.getString("ref"), o.optString("n"), o.optBoolean("p"), o.optInt("u"),
            o.optJSONArray("msgs")?.let { a -> MutableList(a.length()) { Msg.of(a.getJSONObject(it)) } } ?: mutableListOf(),
            o.optString("pn").ifEmpty { null }, o.optString("nt")).apply {
            ans = o.optString("ae").ifEmpty { null }; ansMine = o.optBoolean("am"); ansMid = o.optString("ar").ifEmpty { null }; ansAt = o.optLong("aat")
        }
    }
}

/**
 * THE BOOK (iOS MTPipeBook + ChatStore): the secret of each correspondence, filed under its local name, and the feed of it.
 * Everything is sealed in the device vault; the secrets never leave this phone. Listeners are the open screens.
 */
object Book {
    private const val SECRETS = "pipeSecrets"
    private const val INDEX = "chatIndex"
    private val lock = Any()
    private var secrets: MutableMap<String, ByteArray>? = null
    private val chats = LinkedHashMap<String, Chat>()
    private var loaded = false
    private val listeners = mutableListOf<() -> Unit>()
    var openChat: String? = null   // the chat on the screen: its letters are read as they land
    lateinit var ctx: Context

    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    private fun sec(): MutableMap<String, ByteArray> {
        secrets?.let { return it }
        val m = DeviceVault.get(SECRETS)?.let { raw ->
            runCatching { JSONObject(String(raw, Charsets.UTF_8)).let { o -> o.keys().asSequence().associateWith { Base64.decode(o.getString(it), Base64.NO_WRAP) } } }.getOrNull()
        }?.toMutableMap() ?: mutableMapOf()
        secrets = m; return m
    }
    private fun ensure() {
        if (loaded) return
        loaded = true
        val idx = DeviceVault.get(INDEX)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONArray()
        for (i in 0 until idx.length()) {
            val ref = idx.getString(i)
            DeviceVault.get("chat:$ref")?.let { raw -> runCatching { Chat.of(JSONObject(String(raw, Charsets.UTF_8))) }.getOrNull() }?.let { chats[ref] = it }
        }
    }
    private fun saveIndex() { DeviceVault.set(INDEX, JSONArray(chats.keys.toList()).toString().toByteArray()) }
    private fun save(c: Chat) { DeviceVault.set("chat:${c.ref}", c.json().toString().toByteArray()) }

    private var secretsDay = 0L        // the UTC day the book in memory stands floored for (iOS cacheDay)
    private var secretsHeld = false    // the clock guard withheld the first floor at the last walk: the next read asks again (iOS cacheHeld)
    private var refusedAt = 0L         // when the vault last refused the floored book; 0 while the disk holds what memory holds

    /**
     * THE BOOK WALKS WITH THE DAY (iOS MTPipeBook.load, bf55cd1a and 67332869, decisions 126, 188 and 191): memory holds the book as
     * floored for the day it is read on, by the day the clock guard gives (FloorGuard, asked again at every read while it withholds the
     * first floor); every pipe the walk moved is sealed again with the archive's head of its correspondence in the floor's form, and from
     * ERASE_DAY the archive's old heads with the secret leave the folders' logs. A refused write leaves memory floored and is sealed again
     * by a later read, at most once a minute. Under the lock.
     */
    private fun walked(): MutableMap<String, ByteArray> {
        val m = sec()
        val day = Wire.day()
        val retry = refusedAt != 0L && System.currentTimeMillis() - refusedAt >= 60_000
        if (secretsDay == day && !secretsHeld && !retry) return m
        val fd = FloorGuard.floorDay(m.isNotEmpty()) { m.values.any(Wire::isFloor) }
        secretsDay = day; secretsHeld = fd < day
        val moved = m.filter { (_, p) -> Wire.floored(p, fd) !== p }.keys.toList()
        moved.forEach { r -> m[r] = Wire.floored(m.getValue(r), fd) }
        if (moved.isNotEmpty() || retry) {
            if (saveSecrets(m)) {
                refusedAt = 0L
                if (moved.isNotEmpty()) Log.d("Montana", "pipes_floored n=" + moved.size + " day=" + fd)
                moved.forEach { Archive.head(it) }
            } else { refusedAt = System.currentTimeMillis(); Log.d("Montana", "pipes_write_refused n=" + m.size) }
        }
        if (fd >= Wire.ERASE_DAY) Archive.dropSecretHeads(fd)   // after the floor heads, on the archive's one queue
        return m
    }
    /** A pipe's bytes as the day allows them: from ERASE_DAY the floor (iOS MTPipeKey.held/lags; the book walks, walked). */
    fun secret(ref: String): ByteArray? = synchronized(lock) { walked()[ref] }
    /** The day the book floors by now (iOS MTPipeBook.floorDay): the device day, or the day before ERASE_DAY while the guard withholds. */
    fun floorDay(): Long = synchronized(lock) { walked(); FloorGuard.lastFloorDay() }
    private fun saveSecrets(m: Map<String, ByteArray>): Boolean {
        val o = JSONObject(); m.forEach { (k, v) -> o.put(k, Base64.encodeToString(v, Base64.NO_WRAP)) }
        return DeviceVault.set(SECRETS, o.toString().toByteArray())
    }
    fun refs(): List<String> = synchronized(lock) { sec().keys.toList() }

    /** A correspondence is born from the secret its first letter produced (iOS MTPipeBook.establish). */
    fun establish(secret: ByteArray): String? = synchronized(lock) {
        val ref = Wire.reference(secret)
        val m = walked()
        // ONE PIPE MET AGAIN (iOS MTPipeBook.remember, 67332869, decision 188, #37): from ERASE_DAY the book holds the floor, and a card's
        // letter brings the whole secret again, an archive head a floor of another day. They are one pipe only when both, walked to the
        // later floor day, give the same whole floor -- never the name alone; the book keeps the further floor, never the secret again.
        m[ref]?.let { held ->
            if (!Wire.samePipe(held, secret)) return null
            val keep = Wire.further(held, secret)
            if (keep !== held) { m[ref] = keep; if (saveSecrets(m)) Archive.head(ref) else m[ref] = held }
            return ref
        }
        m[ref] = Wire.floored(secret, FloorGuard.lastFloorDay())
        if (!saveSecrets(m)) { m.remove(ref); return null }
        markErased(listOf(ref), false)   // the pipe born again (iOS: a scan clears the deletion)
        Archive.head(ref)   // the pipe is born: its folder and its secret's head are sealed now (iOS MTPipe 432)
        ref
    }

    /**
     * A READER'S COPY (the screens, the searches, the counts): its own list of the feed's letters, taken under the lock. The
     * live list is changed by the receiving threads inside edit; a screen iterating it on the main thread died of it (07.10,
     * Pixel 19:23 MSK: ConcurrentModificationException in the conversation's redraw while a letter landed). Every change
     * still goes by edit.
     */
    private fun Chat.shot() = Chat(ref, name, perm, unread, ArrayList(msgs), pin, note).also { it.ans = ans; it.ansMine = ansMine; it.ansMid = ansMid; it.ansAt = ansAt }
    /** The correspondences: the local room stands apart, above them (iOS: its row is inserted first, never sorted with them). */
    fun all(): List<Chat> = synchronized(lock) { ensure(); chats.values.filter { !isLocal(it.ref) }.sortedByDescending { it.last?.at ?: 0 }.map { it.shot() } }
    /** Every feed this phone holds, the local room with them -- for the searches that find a file or a letter wherever it lies. */
    fun rooms(): List<Chat> = all() + listOfNotNull(chat(SAVED), chat(MONTANA))
    /** The chat list's feeds: the correspondences and, among them by its moment, the Montana room (iOS: an ordinary row of the list). */
    fun listed(): List<Chat> = synchronized(lock) { ensure(); chats.values.filter { !isLocal(it.ref) || isMontana(it.ref) }.sortedByDescending { it.last?.at ?: 0 }.map { it.shot() } }

    // ── THE ROOM WITHOUT AN ADDRESS (iOS savedMessagesKey, MontanaAvatarKit.swift:6; ChatStore.isLocalRoom, MontanaChatStore.swift:433-437
    // at 2155): Saved Messages is this device writing to itself, a feed like any other opened by the one conversation page; nothing
    // there is sent, waits or fails -- every road that would reach the wire asks isLocal and stops (the author's word 11.09) ──
    const val SAVED = "Saved Messages"   // the storage key is English and never translated, as iOS keeps it
    fun isLocal(ref: String) = ref == SAVED || ref == MONTANA
    // ── THE MONTANA ROOM (iOS montanaRoomKey, ContentView.swift:3228-3246; the author's word 29.09): the room without an address where
    // Montana itself speaks -- a new build, what changed, the button to update. Nobody writes into it; it stands among the chats by
    // its moment, «👑 Montana» under the app's glass icon, and an erased room is born again by the next build's word ──
    const val MONTANA = "Montana"   // the key is English and never translated
    const val MONTANA_TITLE = "\uD83D\uDC51 Montana"   // a name, not a word: the crown before it by right (iOS montanaRoomTitle)
    fun isMontana(ref: String) = ref == MONTANA
    /**
     * A NEW BUILD'S WORD IN THE MONTANA ROOM (iOS ChatStore.appendRelease, MontanaChatStore.swift:2958-2984): one row per build,
     * theirs and unread until the room is opened; a row already standing takes the languages the word brings now, never a second row.
     */
    fun appendRelease(build: Long, version: String, notes: JSONArray, l10n: JSONObject?, url: String): Boolean {
        val o = JSONObject().put("b", build).put("v", version).put("n", notes).put("u", url)
        if (l10n != null && l10n.length() > 0) o.put("l", l10n)
        val text = Marks.RELEASE + o
        chat(MONTANA)?.msgs?.firstOrNull { Release.of(it.text)?.build == build }?.let { row ->
            if (l10n != null && l10n.length() > 0 && Release.languages(row.text)?.toString() != l10n.toString()) edit(MONTANA) { c -> c.msgs.find { it.mid == row.mid }?.text = text }
            return false
        }
        open(MONTANA, MONTANA_TITLE, true)
        edit(MONTANA) { c ->
            c.msgs.add(Msg(Marks.mintMid(), text, false, System.currentTimeMillis(), state = 2))
            if (openChat != MONTANA || !Presence.shown) c.unread++
        }
        return true
    }
    /**
     * The local room, born at the first ask. THE LETTERS OF THE OLD PAGE COME WITH IT ONCE: Android kept Saved Messages as words in a
     * file of their own (SavedMessages) -- they become the room's letters, in their order and with their moments, and the file goes.
     */
    fun saved(c: Context): Chat {
        val had = chat(SAVED)
        if (had != null) return had
        open(SAVED, "", true)
        val old = SavedMessages.all(c)
        if (old.isNotEmpty()) edit(SAVED) { ch ->
            for (l in old) ch.msgs.add(Msg("t${l.at}-" + l.id.uppercase(), l.text, true, l.at).also { it.state = 2; it.statusAt = l.at })   // the name carries its own birth, as every letter's
            ch.msgs.sortBy { it.at }
        }
        SavedMessages.forget(c)
        Prefs.str("draft.savedMessages", "").takeIf { it.isNotEmpty() }?.let { Prefs.setStr("draft.$SAVED", it); Prefs.setStr("draft.savedMessages", "") }
        return chat(SAVED) ?: Chat(SAVED, "", true)
    }
    fun chat(ref: String): Chat? = synchronized(lock) { ensure(); chats[ref]?.shot() }

    fun open(ref: String, name: String, perm: Boolean): Chat = synchronized(lock) {
        ensure()
        chats[ref] ?: Chat(ref, name, perm).also { chats[ref] = it; save(it); saveIndex(); markErased(listOf(ref), false) }   // born again: no longer erased
    }.also { changed() }

    /**
     * A STATE WORD IS APPLIED IN THE ORDER IT WAS SPOKEN, NOT RECEIVED (iOS ChatStore.stateIsCurrent 965-971, MTNameBook.admitDeclared
     * 458-473; fork atom 1822): the box hands letters over in its own order and more than once, and seven writers of a name in any
     * order let a card minted a year ago overwrite yesterday's rename. A word older than the one held is refused out loud; an undated
     * one (a card, a call) never beats a dated word; the moment is kept per person and per kind.
     */
    fun admitState(ref: String, kind: String, at: Long): Boolean {
        val key = "stateAt." + kind + "." + ref
        val held = Prefs.str(key, "").toLongOrNull()
        if (held != null && at < held) { Log.d("Montana", "state_stale " + kind + " older than the held one by " + (held - at) / 1000 + "s"); return false }
        if (held == null || held < at) Prefs.setStr(key, at.toString())
        return true
    }

    /** Any change to a chat: written, and the screens told. */
    fun edit(ref: String, work: (Chat) -> Unit) {
        val born = ArrayList<Msg>()
        var renamed: String? = null
        synchronized(lock) {
            ensure(); val c = chats[ref] ?: return
            // THE ONE ROAD FROM A ROW TO THE ARCHIVE (iOS archiveRow): rows are born in many places here, so the archive reads them where
            // every one passes — a row new to the feed, or a media row whose file has just landed; the name the chat wears, when it changes
            val before = HashMap<String, Boolean>(c.msgs.size * 2)
            for (m in c.msgs) before[m.mid] = m.file != null
            val name0 = c.name
            work(c); save(c)
            for (m in c.msgs) {
                if (m.mid.startsWith("arc:")) continue   // a row the archive gave back is the archive's already (iOS applyRestored)
                val had = before[m.mid]
                val media = m.text.startsWith(Marks.MEDIA)
                if ((had == null && (!media || m.file != null)) || (had == false && media && m.file != null)) born.add(m)
            }
            if (c.name != name0) renamed = c.name
        }
        for (m in born) Archive.row(ref, m)
        renamed?.let { Archive.nameHead(ref, it) }
        changed()
    }

    /**
     * THE ONE TOMBSTONE DOOR (iOS bury(_:in:), buried(_:in:); 092e4fcb, f33985eb, a5047d15 at 2240): a letter deleted here -- by me,
     * by its sender's word, with its whole chat -- leaves its name behind IN ITS CONVERSATION, written BEFORE the row goes, so a copy
     * that comes again by the second road or the node's next pass is not laid in the feed once more. A grave stands in its own
     * conversation alone: a correspondent's word buries nothing of another chat. Only names not buried yet touch the store. The 4000
     * kept are shared: past them the conversation holding the most graves gives up its oldest (the order is the moment this phone
     * buried the name, never the birth a sender claims), so a flood costs its own conversation first.
     */
    private const val GRAVES = "graves"
    private const val GRAVES_CAP = 4000
    private var graves: LinkedHashMap<String, LinkedHashSet<String>>? = null
    private fun graveSets(): LinkedHashMap<String, LinkedHashSet<String>> = graves ?: LinkedHashMap<String, LinkedHashSet<String>>().also { g ->
        DeviceVault.get(GRAVES)?.let { b -> runCatching {
            val o = JSONObject(String(b, Charsets.UTF_8))
            for (k in o.keys()) { val a = o.getJSONArray(k); g[k] = LinkedHashSet<String>().apply { for (i in 0 until a.length()) add(a.getString(i)) } }
        } }
        graves = g
    }
    fun bury(ref: String, mids: Collection<String>) = synchronized(lock) {
        val g = graveSets()
        val set = g.getOrPut(ref) { LinkedHashSet() }
        var fresh = 0
        for (m in mids) if (m.isNotEmpty() && set.add(m)) fresh++
        if (set.isEmpty()) g.remove(ref)
        if (fresh > 0) {
            var total = g.values.sumOf { it.size }
            while (total > GRAVES_CAP) {
                val (k, most) = g.entries.maxByOrNull { it.value.size }!!
                most.remove(most.first()); total--
                if (most.isEmpty()) g.remove(k)
            }
            val o = JSONObject(); g.forEach { (k, v) -> o.put(k, JSONArray(v.toList())) }
            DeviceVault.set(GRAVES, o.toString().toByteArray())
        }
    }
    fun isBuried(ref: String, mid: String) = synchronized(lock) { graveSets()[ref]?.contains(mid) == true }
    /** The conversation holds graves: its letters were deleted here, and an empty feed of it is emptied, not unborn (iOS 95294cf8). */
    fun hasGraves(ref: String) = synchronized(lock) { graveSets()[ref]?.isNotEmpty() == true }

    /**
     * THE FUNERAL HAS A BIRTH (iOS funerals, noteFuneral, diedBefore; 876ab288 at 2240): each side keeps the newest funeral's moment
     * of a conversation -- mine before the chat goes, theirs by the funeral's name. A letter of it born at or before that moment is
     * the dead conversation's and stands nothing again; a funeral no newer than the one kept is a repeat. A record lives a carriage
     * and a day (a letter rides its sender's queue thirty days), at most 512 stand; the funerals outlive the chat, as the graves.
     */
    private const val FUNERALS = "funerals"
    private const val FUNERALS_CAP = 512
    private const val FUNERAL_LIFE = 31L * 86_400_000L
    private var funerals: HashMap<String, Long>? = null
    private fun funeralBook(): HashMap<String, Long> = funerals ?: HashMap<String, Long>().also { f ->
        DeviceVault.get(FUNERALS)?.let { b -> runCatching {
            val o = JSONObject(String(b, Charsets.UTF_8))
            for (k in o.keys()) f[k] = o.getLong(k)
        } }
        funerals = f
    }
    /** A funeral's moment is kept when it is newer than the one kept; the answer says whether it was. */
    fun noteFuneral(ref: String, at: Long): Boolean = synchronized(lock) {
        val f = funeralBook()
        if (at <= (f[ref] ?: 0L)) return false
        f[ref] = at
        val now = System.currentTimeMillis()
        f.entries.removeAll { now - it.value >= FUNERAL_LIFE }
        if (f.size > FUNERALS_CAP) f.entries.sortedBy { it.value }.take(f.size - FUNERALS_CAP).map { it.key }.forEach { f.remove(it) }
        val o = JSONObject(); f.forEach { (k, v) -> o.put(k, v) }
        DeviceVault.set(FUNERALS, o.toString().toByteArray())
        true
    }
    /** A letter whose name says it was born at or before its conversation's funeral belongs to the dead conversation. */
    fun diedBefore(ref: String, mid: String): Boolean {
        val born = Marks.birthMs(mid) ?: return false
        val funeral = synchronized(lock) { funeralBook()[ref] } ?: return false
        return born <= funeral
    }
    /** Letters leave a chat by the one road (iOS deleteLocally([(chat, msg)])): their names buried once, their rows by one write. */
    fun drop(ref: String, mids: Collection<String>) {
        if (mids.isEmpty()) return
        bury(ref, mids)
        edit(ref) { c -> c.msgs.removeAll { it.mid in mids } }
        mids.forEach { Notify.withdraw(ref, it) }   // a letter deleted for me is a letter gone too: its banner leaves (iOS 5a82f7cb)
    }

    /**
     * THE CONVERSATIONS ERASED HERE (iOS ChatStore.deletedChats, its keychain mirror deletedCold; 44f44060, the critic B-4): a chat
     * forgotten on this phone stays named here until a chat of that reference is born again, so a block of its history my other
     * device laid before it heard of the deletion is not filed back (Archive.absorb). The newest 4096 stand.
     */
    private const val ERASED = "erasedChats"
    private const val ERASED_CAP = 4096
    private var erased: LinkedHashSet<String>? = null
    private var erasedHashes: Set<String>? = null
    private fun erasedSet(): LinkedHashSet<String> = erased ?: LinkedHashSet<String>().also { s ->
        DeviceVault.get(ERASED)?.let { b -> runCatching { val a = JSONArray(String(b, Charsets.UTF_8)); for (i in 0 until a.length()) s.add(a.getString(i)) } }
        erased = s
    }
    private fun markErased(refs: Collection<String>, on: Boolean) {
        val s = erasedSet()
        val changed = if (on) { refs.forEach { s.remove(it); s.add(it) }; refs.isNotEmpty() } else s.removeAll(refs.toSet())
        if (!changed) return
        while (s.size > ERASED_CAP) s.remove(s.first())
        DeviceVault.set(ERASED, JSONArray(s.toList()).toString().toByteArray())
        erasedHashes = null
    }
    /** Whether the person deleted this conversation here (iOS deletedChats): a row stood back by its owner stays deleted. */
    fun erased(ref: String): Boolean = synchronized(lock) { ref in erasedSet() }
    /** A block names its conversation by the hash of the reference (Archive.conv): the erased set is asked by that hash. */
    fun erasedHere(convHex: String): Boolean = synchronized(lock) {
        val h = erasedHashes ?: erasedSet().mapTo(HashSet()) { Wire.hex(Wire.sha(it.toByteArray())) }.also { erasedHashes = it }
        convHex in h
    }

    /** A chat deleted here (and its pipe with it — iOS MTPipeBook.forget), with every pipe folded into it. */
    fun forget(ref: String) {
        val dead = listOf(ref) + SamePair.folded(ref)
        synchronized(lock) {
            ensure(); chats.remove(ref); DeviceVault.delete("chat:$ref"); saveIndex()
            markErased(dead, true)
            val m = sec(); dead.forEach { m.remove(it); Meeting.forget(it) }
            val o = JSONObject(); m.forEach { (k, v) -> o.put(k, Base64.encodeToString(v, Base64.NO_WRAP)) }
            DeviceVault.set(SECRETS, o.toString().toByteArray())
        }
        SamePair.drop(dead)
        dead.forEach { Archive.drop(it) }   // no conversation, no trace of it on disk (iOS deleteChatFolder)
        face(ref).delete(); myFace(ref).delete()
        ChatWall.forget(ref)
        changed()
    }

    /** A row the book holds by mistake leaves the list alone: no pipe, no archive folder, no face goes with it. */
    fun discard(ref: String) {
        synchronized(lock) { ensure(); if (chats.remove(ref) == null) return; DeviceVault.delete("chat:$ref"); saveIndex() }
        changed()
    }

    /** Two pipes proven to be one person: whichever conversations they speak for become one (iOS joinSamePerson). */
    fun join(pipe: String, proven: String) {
        val a = SamePair.root(pipe); val b = SamePair.root(proven)
        if (a != b) fold(a, b)
    }

    /**
     * THE FOLD (iOS foldConversation): the newer conversation's letters join the older one's feed, the newer row leaves,
     * the meeting books open the older one, and the newer pipe forwards into it until it dies.
     */
    private fun fold(newer: String, older: String) {
        if (newer == older || SamePair.merged(older) != null || SamePair.merged(newer) != null) return
        synchronized(lock) {
            ensure()
            val n = chats.remove(newer)
            val o = chats[older] ?: Chat(older, n?.name ?: "", n?.perm ?: false).also { chats[older] = it }
            if (n != null) {
                val had = o.msgs.map { it.mid }.toSet()
                o.msgs.addAll(n.msgs.filter { it.mid !in had }); o.msgs.sortBy { it.at }
                o.unread += n.unread
                if (o.name.isEmpty()) o.name = n.name
                if (o.pin == null) o.pin = n.pin
                if (o.note.isEmpty()) o.note = n.note
                o.perm = o.perm || n.perm
            }
            save(o); DeviceVault.delete("chat:$newer"); saveIndex()
        }
        val nf = face(newer); val of = face(older)
        if (nf.exists()) { if (!of.exists()) nf.renameTo(of) else nf.delete() }
        val nm = myFace(newer); val om = myFace(older)
        if (nm.exists()) { if (!om.exists()) nm.renameTo(om) else nm.delete() }
        SamePair.noteMerged(newer, older)
        Meeting.repoint(newer, older)
        if (openChat == newer) openChat = older
        changed()
    }

    /** The face the person published (their AV:, the card's face, the pipe's face). */
    fun face(ref: String) = File(File(ctx.filesDir, "faces").apply { mkdirs() }, "$ref.jpg")
    /** The picture my hand set on their card (iOS MTNameBook.setManualPhoto): it wins over theirs while it stands. */
    fun myFace(ref: String) = File(File(ctx.filesDir, "faces").apply { mkdirs() }, "$ref.mine.jpg")
    /** The one face of a person, resolved in one place: mine, then theirs (iOS MTNameBook avatar resolution). */
    fun shownFace(ref: String): File = myFace(ref).takeIf { it.exists() } ?: face(ref)
    /**
     * THE ONE WRITER OF A CORRESPONDENT'S FACE REFUSES MY OWN (iOS setPeerAvatar, 80a9490f at 2242; No.61 dfd4c5dc): the pipe of a
     * correspondence is shared by every device of my seed, so the face my other device announced or laid beside its card reached
     * this one as the correspondent's. Whatever door brought it -- letter, card, pipe face, archive -- it is refused here.
     * false: nothing was written.
     */
    fun setFace(ref: String, bytes: ByteArray): Boolean {
        if (SelfFace.isMine(bytes)) { Log.d("Montana", "face_echo own face offered for " + ref.take(10) + " -- not theirs"); return false }
        if (runCatching { face(ref).writeBytes(bytes) }.isFailure) return false
        edit(ref) {}
        return true
    }
    /** MY FACE LEAVES EVERY CORRESPONDENT THAT WEARS IT (iOS dropOwnFaceEchoes, dfd4c5dc): stored before the writer refused it, it
     * goes, and each owner is asked for their own face from their card (healFacesFromCards). A group's picture is the group's. */
    fun dropOwnFaceEchoes() {
        val mine = SelfFace.bytes(ctx) ?: return
        val echoes = refs().filter { r -> !Groups.isKey(r) && face(r).length() == mine.size.toLong() && runCatching { face(r).readBytes().contentEquals(mine) }.getOrDefault(false) }
        if (echoes.isEmpty()) return
        echoes.forEach { face(it).delete(); edit(it) {} }
        Log.d("Montana", "face_echo dropped=" + echoes.size + " own faces worn by correspondents")
    }

    /** My hand's name on every row here, null where it set none (iOS MTNameBook.manual — a copy carries it as «manualNames»). */
    fun pins(): Map<String, String?> = synchronized(lock) {
        ensure(); chats.values.filter { !it.ref.startsWith("arc:") }.associate { it.ref to it.pin?.ifBlank { null } }
    }

    /**
     * A COPY LAID (iOS layCard under SeedScope.unionKeys, MontanaChatStore.swift 6306; MTNameBook.setManual 44-54): a name my hand
     * set here stands, a row with none takes the copy's — unless it is the person's own word, which is no pin. A person with no row
     * here yet keeps it in the card this phone keeps (Card).
     */
    fun layPins(m: Map<String, String>) {
        var any = false
        synchronized(lock) {
            ensure()
            for ((ref, name) in m) {
                val c = chats[ref] ?: continue
                val n = name.trim()
                if (n.isEmpty() || !c.pin.isNullOrBlank() || n == c.name) continue
                c.pin = n; save(c); any = true
            }
        }
        if (any) changed()
    }

    /** A COPY LAID (iOS layCard «manualPhotos», a union): the picture my hand set on a person, where this phone holds none. */
    fun layMyFace(ref: String, src: File): Boolean {
        val dst = myFace(ref)
        if (dst.exists() || !src.isFile) return false
        return runCatching { src.copyTo(dst) }.isSuccess.also { if (it) changed() }
    }

    private val faceHealed = mutableSetOf<String>()
    /**
     * A FACE IS FETCHED FROM THE NODE, NOT WAITED FOR (iOS healFacesFromCards, MontanaChatStore.swift:1916, atom
     * 796a76a34ae0; the author's words 04.10.2026 03:54-03:57 MSK: «no avatars anywhere on T1 -- fix it at last»; «the
     * ask reaches only the one whose chat is open -- an architectural hole»): a correspondent already met but still
     * faceless is read at once from their card's face by their last daily link (PeerLinks.any), rather than wait for
     * their phone to wake and announce it again -- once a life per pipe, not on every redraw.
     */
    fun healFacesFromCards() {
        dropOwnFaceEchoes()   // iOS loadFromDisk: dropOwnFaceEchoes, then healFacesFromCards
        var asked = 0
        for (ref in refs()) {
            if (Groups.isKey(ref) || face(ref).exists() || myFace(ref).exists()) continue
            val link = PeerLinks.any(ref) ?: continue
            if (!synchronized(faceHealed) { faceHealed.add(ref) }) continue   // every return asks from its own thread: once a life, by one of them
            asked++
            Meeting.healFace(ref, link)
        }
        if (0 < asked) Log.d("Montana", "face_heal from_cards=" + asked)   // iOS MontanaChatStore 1926
    }

    /**
     * THE EDIT PAGE'S «DONE» (iOS mtHandProfileEdit → MTNameBook.setManual/setManualPhoto): a name equal to their own word
     * clears the pin instead of setting it, an empty field restores their name; the photo — bytes set by hand, or null to
     * give theirs back.
     */
    fun saveCard(ref: String, first: String, last: String, note: String, photo: ByteArray?, photoCleared: Boolean) {
        edit(ref) { c ->
            // A TYPED NAME LOSES ITS CROWN TOO (iOS MTCrown.plain, atom d4142dd38143): the rename book's own field.
            val full = stripCrown((first.trim() + " " + last.trim()).trim())
            c.pin = if (full.isEmpty() || full == c.name.trim()) null else full
            c.note = note.trim()
        }
        if (photo != null) myFace(ref).writeBytes(photo) else if (photoCleared) myFace(ref).delete()
        changed()
    }

    /** The person leaves: every correspondence leaves with them. */
    fun wipe() {
        synchronized(lock) {
            ensure(); chats.keys.forEach { DeviceVault.delete("chat:$it") }; chats.clear()
            DeviceVault.delete(INDEX); DeviceVault.delete(SECRETS); secrets = null
            secretsDay = 0L; secretsHeld = false; refusedAt = 0L
        }
        FloorGuard.wipe(); Archive.forgetPurge()   // the clock guard and the purge's mark are this seat's, as the book (iOS SeedScope.seatKeys)
        File(ctx.filesDir, "faces").deleteRecursively()
        DeviceVault.delete(Post.OUTBOX)
        Meeting.wipe(); SamePair.wipe(); Groups.wipe(); PeerLinks.wipe(); PasswordVault.wipe()
        CoinBook.setAside()   // the book of a person forgotten leaves with them (iOS MTCoinPlace.setAside)
        // NOTHING OF THE PERSON OUTLIVES THEM ON THIS PHONE BUT WHAT THE WORDS ALONE REOPEN (iOS SeedScope.forget; the absolute privacy,
        // 29.07): the history was sealed under the words before they left (Archive.sealForForget, iOS sealForForget) and stays in
        // Montana/Chats; everything else goes — the chats' files, the letters set for later, the words still waiting to leave, the
        // pins and marks of the chats, the card, the read marks, the walls held, the stickers and the grounds.
        Media.wipe(ctx); Scheduled.wipe(); ChatMarks.wipe(); MsgPins.wipe(); BusinessCard.forget(); Post.PeerRead.wipe()
        Board.wipe(); Stickers.wipe(ctx); GifBook.wipe(ctx); ChatWall.wipe()
        changed()
    }
}

object MainThread {
    private val h = android.os.Handler(android.os.Looper.getMainLooper())
    fun post(r: () -> Unit) { h.post(r) }
    fun later(ms: Long, r: Runnable) { h.postDelayed(r, ms) }
}

// ─────────────────────────── the post: the node box both ways (iOS MontanaWakePush box + delivery engine) ───────────────────────────

/**
 * THE POST. A letter goes to the node's box under the conversation's daily label, sealed under the pipe key of the minute it
 * was sealed in (iOS knockLetter); the receiver reads the box by its labels (iOS fetchBox), opens what is its own, and tells
 * the node to bury what it took (box-del). The first letter of a meeting lies under the invitation's label, sealed under the
 * invitation's letter key, and carries the encapsulation that begets the pipe (iOS wakeRdv / drainInbox «rdv»).
 * The node reads zero bytes: it sees labels that change every day and envelopes of one size.
 */
object Post {
    const val OUTBOX = "outbox"
    private val outLock = Any()
    private val fetchLock = Any()
    private var fetchAgain = false   // a hint that came while a pickup ran: one more round when it ends
    private var fetching = false
    private const val CARRY_MS = 30L * 86_400_000L   // iOS MontanaDeliveryEngine.carryDays: at least thirty days (the author's word 07.10)

    // ── sending ──
    /**
     * A STATE LETTER'S KIND AND WHAT TWO OF ITS KIND ARE COMPARED BY (iOS MTOutbox.Kind.isState, MTNodeWire 341-348: the name, the
     * face, «about», the page's ground; aboutTag(ofWord:) and groundTag(ofWord:), MontanaDeliveryEngine 370-390, compare «about» and
     * the ground by their content, the moment they carry aside); null -- a person's word, which is never folded.
     */
    private fun stateOf(t: String): Pair<Int, String>? = when {
        t.startsWith(Marks.NAME) -> 1 to t
        t.startsWith(Marks.AVATAR) -> 2 to t
        t.startsWith(Marks.ABOUT) -> 3 to (runCatching { JSONObject(t.removePrefix(Marks.ABOUT)).let { o -> o.optString("b") + "\n" + o.optString("l") } }.getOrNull() ?: t)
        t.startsWith(PageGround.MARK) -> 4 to (runCatching { JSONObject(t.removePrefix(PageGround.MARK)).optString("g") }.getOrNull() ?: t)
        else -> null
    }
    /** Queue a letter and knock at once; a letter that no door took waits in the outbox and rides the next round. */
    /** `quiet` — a letter of the person's that asks no banner this once (iOS enqueue silent: a missed call the far phone already rang for). */
    fun send(to0: String, mid: String, text: String, qt: String? = null, qm: String? = null, lp: String? = null, quiet: Boolean = false) {
        if (Groups.isKey(to0)) return   // a group's feed has no pipe: nothing is ever queued to it (iOS: a group's key has no doors)
        // THE ROOM WITHOUT AN ADDRESS HAS NO WIRE (iOS isLocalRoom): its own letter is settled where it was written, never queued
        if (Book.isLocal(to0)) { Book.edit(to0) { c -> c.msgs.find { it.mid == mid && it.mine }?.advance(2) }; return }
        val to = if (SamePair.speaksOfPipe(text)) to0 else SamePair.root(to0)   // a folded pipe's words go by its conversation's pipe
        var refused = false
        synchronized(outLock) {
            val a = outbox()
            for (i in 0 until a.length()) if (a.getJSONObject(i).optString("m") == mid) {
                // one letter, one place in the queue; its card, come later, joins the place it already holds (iOS attachPreview)
                if (lp != null) { a.getJSONObject(i).put("lp", lp); keepOutbox(a) }
                return
            }
            // ONE STATE, ONE LETTER (iOS DeliveryEngine 799-802, 08.09: forty-three read marks waiting their turn burnt the pair's ring
            // budget, T3 to T1): a read mark says «read up to here», so a newer one makes the queued one meaningless — the last word stands
            // and ONE PAGE OF MY WALL per person (iOS enqueue, the critic's N1): a newer page takes the queued one's place
            fun kind(t: String) = if (t.startsWith(Marks.READ)) 1 else if (t.startsWith(Board.MARK) && t.contains("\"t\":\"page\"")) 2 else 0
            val k = kind(text)
            var q = if (k == 0) a else JSONArray().also { keep ->
                for (i in 0 until a.length()) a.getJSONObject(i).let { o -> if (!(o.optString("to") == to && kind(o.optString("t")) == k)) keep.put(o) }
            }
            // THE SAME STATE ALREADY ON ITS WAY IS NOT QUEUED AGAIN, A NEWER ONE TAKES THE QUEUED ONE'S PLACE (iOS enqueue 807-821,
            // sameStateWaits 559-570, foldingState 553-556; atom a441e549ec21): at one proof of a peer's build four «about» letters and
            // three 1.6 MB ground letters left within 60 ms (T1, 25.09) -- the answer is given here, where the record is written
            val st = stateOf(text)
            if (st != null) {
                val twin = (q.length() - 1 downTo 0).map { q.getJSONObject(it) }.firstOrNull { o -> o.optString("to") == to && stateOf(o.optString("t"))?.first == st.first }
                if (twin != null && stateOf(twin.optString("t"))?.second == st.second) {
                    Log.d("Montana", "state_twin kind=" + st.first + " — the same state already waits for this peer")
                    return
                }
                if (twin != null) q = JSONArray().also { keep ->
                    for (i in 0 until q.length()) q.getJSONObject(i).let { o -> if (!(o.optString("to") == to && stateOf(o.optString("t"))?.first == st.first)) keep.put(o) }
                }
            }
            q.put(JSONObject().put("to", to).put("m", mid).put("t", text).put("qt", qt ?: "").put("qm", qm ?: "").put("lp", lp ?: "").apply { if (quiet) put("q", true) })
            if (!keepOutbox(q)) refused = true
        }
        // THE REFUSAL IS SHOWN, NOT SWALLOWED (iOS enqueue 822-829): with the store unreadable the letter did not land in the queue and
        // will not ride; its row goes red with a retry, as on any break
        if (refused) {
            Log.d("Montana", "enqueue_drop m=" + mid.take(8) + " store unreadable")
            var red: Msg? = null
            val chat = SamePair.root(to)
            Book.edit(chat) { c -> c.msgs.find { it.mid == mid && it.mine }?.let { m -> if (m.advance(-1)) red = m } }
            red?.let { CoinSend.hold(it, chat) }
            return
        }
        // THE TWIN MIRROR (iOS enqueue, MontanaDeliveryEngine.swift:963-972): what the person sends rides to the seed's other devices
        // under its name; a receipt and a read mark are this device's word to the correspondent
        if (Twin.mirrors(text) && !text.startsWith(Marks.DELIVERED) && !text.startsWith(Marks.READ))
            Twin.note(to, mid, text, own = true, at = System.currentTimeMillis() / 1000.0, qt = qt, qm = qm, lp = lp)
        Thread { flush() }.start()
    }
    /**
     * AN INSTANT WORD (iOS E2E.signalNow): one throw at the pipe's doors and no promises -- never queued, never receipted, never
     * written; only what lives an instant goes here (a group's «typing»), for which a word not delivered is no loss.
     */
    fun now(to0: String, text: String) {
        val to = SamePair.root(to0)
        val secret = Book.secret(to) ?: return
        if (Meeting.first(to) != null || PeerSafety.isBlocked(to)) return   // an unanswered introduction carries the person's letters alone
        Thread { knock(secret, Marks.mintMid(), text, null, null, quiet = true) }.start()
    }
    /** A letter taken off the road unsent: it leaves the queue (a coin letter whose day is over, CoinSend.expire). */
    fun unqueue(mid: String) {
        synchronized(outLock) {
            val a = outbox()
            val keep = JSONArray()
            for (i in 0 until a.length()) a.getJSONObject(i).let { if (it.optString("m") != mid) keep.put(it) }
            if (keep.length() != a.length()) keepOutbox(keep)
        }
    }
    /**
     * «CANNOT READ» IS NOT «EMPTY» (iOS storeUnreadable, MontanaDeliveryEngine 602-609, 662-700; atom e6cb9251482f): a stored queue
     * that does not open -- a foreign seal after a device-key change, bytes a later build cannot decode -- read as an empty queue, and
     * the next write saved that emptiness over it: every unsent letter gone, no red, no line in the diary. The store is judged on every
     * read: bytes that exist and do not open raise the flag, the diary names it, and while it stands no write lands -- the bytes stay
     * for a build that can open them. A read that opens lowers it.
     */
    @Volatile private var unreadable = false
    @Volatile private var unreadableSaidAt = 0L
    private fun outbox(): JSONArray {
        val raw = DeviceVault.get(OUTBOX)
        val a = raw?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() }
        unreadable = a == null && DeviceVault.has(OUTBOX)
        val now = System.currentTimeMillis()
        if (unreadable && 300_000L <= now - unreadableSaidAt) {
            unreadableSaidAt = now
            Log.d("Montana", "queue_unreadable the stored queue does not open bytes=" + (raw?.size ?: 0) + " — not overwriting")
        }
        return a ?: JSONArray()
    }
    private fun keepOutbox(a: JSONArray): Boolean {
        if (unreadable) { Log.d("Montana", "queue_save_refused the stored queue is unreadable — " + a.length() + " items not written over it"); return false }
        return DeviceVault.set(OUTBOX, a.toString().toByteArray())
    }

    /** Every waiting letter knocks once more; the ones a door boxed leave the queue. */
    fun flush() {
        val items = synchronized(outLock) { outbox() }
        val done = mutableSetOf<String>()
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            val to = o.getString("to"); val mid = o.getString("m")
            val secret = Book.secret(to)
            if (secret == null) {
                // THE LETTER HAS NO ROAD (iOS MTRefusal.noRoad, the one door into red, ContentView 3083-3111): the pipe is gone — nobody to
                // deliver to. Its row turns red instead of standing at the clock for ever, and a coin letter's coins come back with the red
                // (iOS hold): a coin letter on its way may not be deleted, so a row with no road would have held its coins for good.
                done.add(mid); Groups.copyLost(mid)
                var red: Msg? = null
                val chat = SamePair.root(to)
                Book.edit(chat) { c -> c.msgs.find { it.mid == mid && it.mine }?.let { m -> if (m.advance(-1)) red = m } }
                red?.let { CoinSend.hold(it, chat) }
                continue
            }
            // WHILE THE INTRODUCTION IS UNANSWERED every letter a person wrote rides the invitation's box with the ciphertext;
            // the words of the wire (receipts, reads, name, face) wait for the pipe to stand (iOS first_hold).
            val intro = Meeting.first(to)
            val text = o.getString("t")
            val sent = if (intro != null) {
                // the question «do we already share a pipe?» is itself the silent first letter that carries the ciphertext (iOS MTSamePair.ask)
                if (Marks.isService(text) && !text.startsWith(Marks.MEDIA) && !text.startsWith(Marks.VOICE) && !text.startsWith(Marks.SAME_ASK)) false
                else {
                    val words = if (text.toByteArray().size > 300) sealLong(mid, text) else text
                    // the live road beside the invitation's box: at the point the card names, under the new pipe's seal (iOS sendP2P 935-958)
                    val laid = words != null && Meeting.root(to)?.let { root -> Channels.layFirst(secret, root, intro.first, mid, letterHead(mid, words)) } == true
                    // a name has no invitation's box: its first letters ride the point of the name's root alone (iOS outgoingTag 502-510)
                    if (intro.second.isEmpty()) laid
                    else words != null && Meeting.knockFirst(secret, intro.first, intro.second, mid, words, Marks.isSilent(text) || o.optBoolean("q"))
                }
            } else knock(secret, mid, text, o.optString("qt").ifEmpty { null }, o.optString("qm").ifEmpty { null }, o.optString("lp").ifEmpty { null }, o.optBoolean("q"))
            if (sent) {
                done.add(mid)
                Book.edit(SamePair.root(to)) { c -> c.msgs.find { it.mid == mid }?.advance(1) }   // a letter queued on a pipe since folded settles in the conversation
                Groups.copyHeld(mid)   // a group's copy has no row of the pipe: the node holds it, and the group's row moves (iOS copyHeld)
            } else if (Marks.birthMs(mid)?.let { CARRY_MS <= System.currentTimeMillis() - it } == true) {
                // THE CARRIAGE IS THE ONE END, AND NEVER A CLOCK'S RED FOR A LETTER A NODE TOOK (iOS carryDays and neverLeft,
                // MontanaDeliveryEngine 315-316, 1354-1366; atom 4d96053c1090): a letter a door boxed left this queue at once, still
                // sent; one no node ever took in thirty days turns red by that word -- it never left this phone -- and leaves the queue.
                // A coin letter never reaches here: its day ends first (CoinSend.expire, the author's word 09.10 11:3x).
                done.add(mid); Groups.copyLost(mid)
                Log.d("Montana", "send_failed m=" + mid.take(8) + " — no node ever took it in the carriage's thirty days")
                var red: Msg? = null
                val chat = SamePair.root(to)
                Book.edit(chat) { c -> c.msgs.find { it.mid == mid && it.mine }?.let { m -> if (m.advance(-1)) red = m } }
                red?.let { CoinSend.hold(it, chat) }
            }
        }
        if (done.isEmpty()) return
        synchronized(outLock) {
            val a = outbox(); val keep = JSONArray()
            for (i in 0 until a.length()) a.getJSONObject(i).let { if (it.getString("m") !in done) keep.put(it) }
            keepOutbox(keep)
        }
    }

    /** A letter's body up to its glyph (iOS sendP2P 902-908): mid ‖ 0 ‖ words ‖ 0 ‖ my name ‖ 0 ‖ glyph — one shape for the box and the channels. */
    private fun letterHead(mid: String, text: String): ByteArray =
        mid.toByteArray() + 0 + text.toByteArray() + 0 + Prefs.userName.trim().toByteArray() + 0 + byteArrayOf(0)

    /** ONE KNOCK (iOS MTNodeWire.knockLetter): the body is sealed afresh at every door, the first door that boxes it ends the walk. */
    private fun knock(secret: ByteArray, mid: String, text0: String, qt: String?, qm: String?, lp: String? = null, quiet: Boolean = false): Boolean {
        val twin = MontanaSeed.twin ?: return false
        // A LETTER TOO LONG FOR ONE ENVELOPE rides as a blob under a key of its own, the envelope carries the reference (iOS sealLongLetter).
        val text = if (text0.toByteArray().size > Wire.ENVELOPE - 400) sealLong(mid, text0) ?: return false else text0
        var body = letterHead(mid, text)
        val quoted = !qt.isNullOrEmpty()
        if (quoted) {
            val tail = qt!!.take(200).toByteArray() + 0 + (qm ?: "").toByteArray() + 0
            if (body.size + tail.size <= Wire.ENVELOPE) body += tail
        }
        // THE LINK'S CARD IS THE SEVENTH FIELD (iOS wireTail / wireTailAfterQuote): after the quote pair, or after two empty
        // fields where the quote would stand; the envelope carries it without its picture, and only when it fits — decoration
        val head = body
        lp?.let { LinkCard.parse(it)?.json(withPicture = false) }?.takeIf { it.toByteArray().size > 64 }?.let { card ->
            val tail = (if (quoted) ByteArray(0) else byteArrayOf(0, 0)) + card.toByteArray()
            if (body.size + tail.size <= Wire.ENVELOPE) body += tail
        }
        if (body.size > Wire.ENVELOPE) return false
        // THE LIVE ROAD CARRIES THE CARD AS IT IS SEEN, ITS PICTURE CUT TO THE LEG (iOS MontanaPhoneNode.sendLetter 893-930 with
        // wireTail(lp:), fitting 16384): a channel's frame is not the node's envelope of 2048, so the picture rides there and fills
        // the receiver's card (enrich); Android laid the envelope's bare card on both roads, and an iPhone never saw a picture
        val live = LinkPreview.fitting(lp)?.let { card ->
            head + (if (quoted) ByteArray(0) else byteArrayOf(0, 0)) + card.toByteArray()
        } ?: body
        // the live road beside the box: laid before the nodes under the pipe's tag (iOS sendP2P) -- WORDS, NEVER A LONG LETTER'S
        // REFERENCE: iOS lays the letter's own text there (sendP2P(text:), MontanaDeliveryEngine.swift:1478, 1502) and seals the
        // reference into the envelope alone (sealLetterEnvelope, 1574). An iPhone files what the live road brings as a row: a
        // reference filed so stood as a loading row and was healed into the face's base64 as text (MontanaChatStore.swift:3295-3307;
        // A1 to an iPhone 10.10.2026 22:03-22:28, the author's word: make it never repeat). A long letter rides the box alone.
        if (!text.startsWith(Marks.LONG)) Channels.lay(secret, mid, live)
        // THE PERSON SIGNS THE LETTER AS ITS AUTHOR (iOS sealLetterEnvelope, MontanaWakePush.swift:1555): after the card, before the
        // padding, over the words as they ride (a long letter's reference); the live road above rides unsigned, as iOS lays it.
        body = Wire.withAuthor(body, LetterAuthor.key, secret, mid, text)
        val plain = body + ByteArray(Wire.ENVELOPE - body.size)
        val cw = Wire.convW(secret, Wire.day())
        // a service word asks the node for a silent push (iOS wake: body["silent"]), judged by its words, not by a long letter's reference
        val silent = Marks.isSilent(text0) || quiet
        // the elected door first, the next only past its death (iOS 1638)
        for (door in Signal.writeOrder("box")) {
            val env = Wire.seal(Wire.bodyKey(secret, Wire.minute()), plain) ?: return false
            val (code, _) = Wire.post(door, "/wake", JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, twin)).put("mid", mid)
                .put("env", Base64.encodeToString(env, Base64.NO_WRAP)).apply { if (silent) put("silent", true) })
            if (code == 200) { Signal.doorAnswered(door); return true }
            Signal.doorFailed(door, code)
        }
        return false
    }
    private operator fun ByteArray.plus(b: Int) = this + byteArrayOf(b.toByte())

    /** mid‖0‖text sealed under a fresh key, laid on the node under SHA-256 of the seal (iOS blobIdHex); the reference once per letter. */
    private fun sealLong(mid: String, text: String): String? {
        Prefs.str("longRef.$mid", "").takeIf { it.isNotEmpty() }?.let { return it }
        val mk = MtBindings.nativeRandom(32) ?: return null
        val sealed = Wire.seal(mk, mid.toByteArray() + 0 + text.toByteArray()) ?: return null
        val bid = Wire.hex(Wire.sha(sealed))
        if (!Wire.putBlob(bid, sealed, assumeAbsent = true)) return null   // a key drawn this moment: new by construction
        val link = Marks.LONG + JSONObject().put("r", bid).put("k", Base64.encodeToString(mk, Base64.NO_WRAP))
        Prefs.setStr("longRef.$mid", link)
        return link
    }

    /** The words behind a long letter's reference: the words, null — later (no door answered), "" — gone for good. */
    private fun fetchLong(text: String): String? = fetchLongV(text).first

    /** The words, and whether every store said the cargo is gone (iOS askBlob's verdict) when there are none yet. */
    private fun fetchLongV(text: String): Pair<String?, Boolean> {
        val o = runCatching { JSONObject(text.removePrefix(Marks.LONG)) }.getOrNull() ?: return "" to false
        val mk = runCatching { Base64.decode(o.getString("k"), Base64.DEFAULT) }.getOrNull() ?: return "" to false
        val (sealed, gone) = Wire.getBlobVerdict(o.optString("r"))
        if (sealed == null) return null to gone
        val plain = Wire.open(mk, sealed) ?: return "" to false
        val sep = plain.indexOf(0).takeIf { it >= 0 } ?: return "" to false
        return String(plain, sep + 1, plain.size - sep - 1, Charsets.UTF_8) to false
    }

    // A DEAD CARGO IS NOT ASKED FOR EVERY ROUND, AND THE LETTER'S AGE IS THE LETTER'S (iOS MontanaWakePush 2644-2737, atoms
    // 85a73a5b7ca0, 3d14a47ac6c3): a long letter whose cargo no store answered for was asked at every pickup for ever. The record
    // lies beside the box (the device's vault) so the burial arrives on the wall clock, whatever happens to the process: the retry
    // doubles from fifteen seconds to an hour and the letter keeps its own hour; «no such cargo» from every door three times over
    // ten minutes buries the reference, as does the box's own term, a day; the sender is told once, by the cargo-lost word.
    private const val LB = "mt.longblob.wait"
    private const val CARGO_LOST = "​​CG:"
    private fun lbLoad(): JSONObject = DeviceVault.get(LB)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONObject()
    private fun lbSave(o: JSONObject) { DeviceVault.set(LB, o.toString().toByteArray(Charsets.UTF_8)) }
    @Synchronized private fun lbForget(mid: String) { val o = lbLoad(); if (o.has(mid)) { o.remove(mid); lbSave(o) } }
    @Synchronized private fun lbDueNow(mid: String): Boolean = lbLoad().optJSONObject(mid)?.optDouble("next", 0.0)?.let { it <= System.currentTimeMillis() / 1000.0 } ?: true
    /** True when the reference is buried: the box lets it go. */
    @Synchronized private fun lbFailed(mid: String, conv: String, gone: Boolean, bornAt: Double?): Boolean {
        val now = System.currentTimeMillis() / 1000.0
        val all = lbLoad()
        val rec = all.optJSONObject(mid) ?: JSONObject()
        val born = minOf(rec.optDouble("born", now), bornAt ?: now)
        val n = rec.optInt("tries", 0)
        rec.put("born", born).put("tries", n + 1)
        if (gone) { if (!rec.has("goneAt")) rec.put("goneAt", now); rec.put("goneN", rec.optInt("goneN", 0) + 1) }
        val goneN = rec.optInt("goneN", 0)
        val goneFor = now - rec.optDouble("goneAt", now)
        if (3 <= goneN && 600 <= goneFor) {
            all.remove(mid); lbSave(all)
            Log.d("Montana", "lb_dead mid=" + mid.take(8) + " every door answered «no such cargo» " + goneN + " times over " + (goneFor / 60).toInt() + " min — the reference is buried")
            return true
        }
        if (86_400 < now - born) {
            all.remove(mid); lbSave(all)
            Log.d("Montana", "lb_dead mid=" + mid.take(8) + " asked " + (n + 1) + " rounds over " + ((now - born) / 3600).toInt() + "h — the reference is buried")
            return true
        }
        if (gone && !rec.has("told") && conv.isNotEmpty()) {
            rec.put("told", now)
            send(conv, Marks.mintMid(), CARGO_LOST + mid, quiet = true)   // the sender is told once, never on a mere «later»
        }
        val delay = minOf(15.0 * Math.pow(2.0, n.toDouble()), 3600.0)
        rec.put("next", now + delay)
        all.put(mid, rec); lbSave(all)
        Log.d("Montana", "lb_wait mid=" + mid.take(8) + " retry in " + delay.toInt() + "s try=" + (n + 1) + " verdict=" + (if (gone) "gone" else "later"))
        return false
    }
    /** A file whose cargo every store called gone: the row stands, and the sender is told once (iOS 4635-4649). */
    fun cargoLost(conv: String, mid: String) {
        if (Prefs.bool("cgTold.$mid", false)) return
        Prefs.setBool("cgTold.$mid", true)
        Log.d("Montana", "cargo_lost mid=" + mid.take(8) + " — the row stands, the sender is told")
        send(conv, Marks.mintMid(), CARGO_LOST + mid, quiet = true)
    }

    /**
     * MY NAME AND MY FACE GO TO EVERY CORRESPONDENT (iOS sendNameIfNeeded, sendFace): once, and again whenever they change.
     * The face rides as AV:+base64 JPEG — a long letter by construction; an empty AV: says «no face».
     */
    fun announce(ref: String) {
        if (PeerSafety.isBlocked(ref)) return   // a blocked person keeps no face, no name, no words of mine (iOS silenced)
        val name = stripCrown(Prefs.userName.trim())   // my own name never carries a crown either (iOS MTCrown.plain, atom d4142dd38143)
        if (name.isNotEmpty() && Prefs.str("annName2." + ref, "") != name && !inFlight("N", ref, name)) {
            val mid = Marks.mintMid(); flight("N", ref, name, mid); send(ref, mid, Marks.NAME + name)
        }
        MyAbout.sendIfNeeded(ref)
        if (!SelfFace.held(Book.ctx)) return   // an unread face is silence, not «no face» (iOS MontanaSelf.holds("avatarData"))
        val face = SelfFace.bytes(Book.ctx) ?: ByteArray(0)
        val tag = Wire.hex(Wire.sha(face)).take(16)
        if (Prefs.str("annFace2." + ref, "") != tag) {
            // THE FACE'S ROAD IS NAMED (18.10.2026: a held_differs answered by nothing the diary could show): sent, or still on its way
            if (inFlight("F", ref, tag)) Log.d("Montana", "face_tx to=" + ref.take(10) + " tag=" + tag.take(8) + " in-flight")
            else {
                val mid = Marks.mintMid(); flight("F", ref, tag, mid)
                send(ref, mid, Marks.AVATAR + if (face.isEmpty()) "" else Base64.encodeToString(face, Base64.NO_WRAP))
                Log.d("Montana", "face_tx to=" + ref.take(10) + " tag=" + tag.take(8) + " bytes=" + face.size + " mid=" + mid.take(8))
            }
        }
    }

    /**
     * «ANNOUNCED» MEANS «RECEIPTED» (iOS Announced.recordDelivered 424-453; the mark's meaning changed, so it lives under a
     * new name, 351-358): the only writer of the mark is the receipt of the very letter that carried the value. A promise
     * written at the send outlived a lost letter, and the face was never announced again until it changed. Until the
     * receipt the value is on its way — an hour, as the iPhone's queue holds an unanswered letter — and is not said twice.
     */
    fun flight(kind: String, ref: String, value: String, mid: String) =
        Prefs.setStr("annFly" + kind + "." + ref, value + "\n" + mid + "\n" + System.currentTimeMillis())
    fun inFlight(kind: String, ref: String, value: String): Boolean {
        val f = Prefs.str("annFly" + kind + "." + ref, "").split("\n")
        return f.size == 3 && f[0] == value && System.currentTimeMillis() - (f[2].toLongOrNull() ?: 0L) < 3_600_000L
    }
    /**
     * BLOCKED (iOS E2E.announceBlocked 1441-1465): what the blocked person's phone is told — my face taken back (an empty AV:) and
     * one presence word «0B», seen long ago, no face; both ride the durable road, as the iPhone's queue carries them.
     */
    fun blocked(ref: String) {
        if (Book.secret(ref) == null) return
        for (k in listOf("annFace2.", "annFlyF.")) Prefs.remove(k + ref)
        send(ref, Marks.mintMid(), Marks.AVATAR)
        send(ref, Marks.mintMid(), Presence.APP + "0B" + Presence.saidTail())
    }
    /**
     * THEIR SCREEN HOLDS A STALE FACE OR NAME OF MINE (iOS heardHeld 663-664: forgetFace / forgetName, then send again): the receipted
     * mark is forgotten and announced anew; the letter still on its way is not doubled (iOS forgetFace keeps the queue's pendingStateTag,
     * MontanaDeliveryEngine.swift:393-396, 539-547). ONE ANSWER TO ONE STATE (the author's word 10.10.2026 22:1x: make it never repeat):
     * a value they receipted, while they still name the same stale tag, is not sent again -- the same bytes meet the same screen. A1 sent
     * a correspondent its face every minute from 22:00, and the iPhone, healing the long letter into a row, showed it as text. It goes again when my
     * value or the tag they name changes, and a letter lost on its way goes again past its hour (inFlight).
     */
    fun announceAgain(ref: String, face: Boolean, name: Boolean, theirFace: String, theirName: String) {
        // THE ANSWERS GIVEN WHILE THE CARD'S FACE STOOD OLD ARE GIVEN ONCE MORE (18.10.2026): T1 wore my face, then the card's stale one
        // over it, and named that stale tag again -- the same state, answered, so nothing went for ever. Once, as the card's face is fresh.
        if (!Prefs.bool("annHeldCardFace2", false)) { Prefs.remove(*Prefs.keys("annHeldF.").toTypedArray()); Prefs.setBool("annHeldCardFace2", true) }
        val f = face && SelfFace.held(Book.ctx) && again("F", ref, "annFace2.", Wire.hex(Wire.sha(SelfFace.bytes(Book.ctx) ?: ByteArray(0))).take(16), theirFace)
        val n = name && again("N", ref, "annName2.", stripCrown(Prefs.userName.trim()), theirName)
        if (f) Prefs.remove("annFace2." + ref)
        if (n) Prefs.remove("annName2." + ref)
        if (f || n) announce(ref) else Log.d("Montana", "held_answered -- this stale state was answered and receipted, nothing goes again")
    }
    private fun again(kind: String, ref: String, mark: String, mine: String, theirs: String): Boolean {
        val said = mine + "\n" + theirs
        if (Prefs.str(mark + ref, "") == mine && Prefs.str("annHeld" + kind + "." + ref, "") == said) return false
        Prefs.setStr("annHeld" + kind + "." + ref, said)
        return true
    }
    /**
     * THEY ASK FOR MY PROFILE AGAIN (iOS resendProfileOnReconnect, answering «f» — «I hold no face of you»): the receipted marks of
     * my name, face, words and ground are forgotten and all go again, at most once in five minutes a person.
     */
    private val profilePushedAt = HashMap<String, Long>()
    fun resendProfile(ref: String) {
        if (Book.secret(ref) == null || PeerSafety.isBlocked(ref)) return
        val now = System.currentTimeMillis()
        synchronized(profilePushedAt) {
            if (now - (profilePushedAt[ref] ?: 0L) < 300_000L) return
            profilePushedAt[ref] = now
        }
        for (k in listOf("annName2.", "annFace2.", "annAbout2.", "annGround.")) Prefs.remove(k + ref)
        announce(ref)
        PageGround.sendIfNeeded(ref)
    }
    /** UNBLOCKED (iOS announceUnblocked 1458-1466): the person is told I am here again — my name, my face, my presence. */
    fun unblocked(ref: String) {
        if (Book.secret(ref) == null) return
        for (k in listOf("annName2.", "annFace2.", "annFlyN.", "annFlyF.", "annAbout2.", "annFlyA.")) Prefs.remove(k + ref)
        announce(ref)
        if (Presence.sharing) Thread { Signal.post(ref, Presence.APP + "1" + Presence.saidTail()) }.start()
    }
    private fun announcedDelivered(ref: String, mid: String) {
        MyWall.delivered(ref, mid)   // a page of my wall is «sent» at its receipt (iOS MTBoard.delivered)
        for ((kind, mark) in listOf("N" to "annName2.", "F" to "annFace2.", "G" to "annGround.", "A" to "annAbout2.")) {
            val f = Prefs.str("annFly" + kind + "." + ref, "").split("\n")
            if (f.size == 3 && f[1] == mid) { Prefs.setStr(mark + ref, f[0]); Prefs.remove("annFly" + kind + "." + ref) }
        }
    }

    // ── receiving ──
    /** ONE PICKUP AT A TIME (iOS fetchBox): the labels of every live invitation and every pipe, across the box's term. */
    fun fetch() {
        MainThread.post { Presence.watchApp(Book.ctx) }
        // A «YOU HAVE A LETTER» IS NEVER THROWN AWAY, ONLY DEFERRED (iOS build 1910): a hint that lands while a pickup runs asked a
        // box the running pickup may already have passed — it is kept, and the pickup goes round once more when it ends
        synchronized(fetchLock) { if (fetching) { fetchAgain = true; return }; fetching = true }
        try {
            do {
                synchronized(fetchLock) { fetchAgain = false }
                fetchOnce()
            } while (synchronized(fetchLock) { fetchAgain })
        } catch (e: Exception) { Log.w("Montana", "box fetch: ${e.javaClass.simpleName}") }
        finally { synchronized(fetchLock) { fetching = false } }
        CoinSend.expire()   // after the pickup: a receipt it brought counts before a coin letter's day is judged
        SamePair.askUnasked()
        Book.refs().filter { SamePair.merged(it) == null }.forEach { announce(it) }   // a folded pipe only forwards
        Media.fetchPending(Book.ctx)
        Thread { Media.drainIntents(Book.ctx) }.start()   // a file whose pieces did not land goes out again (iOS 1675), never ahead of the letters
        flush()
    }

    private fun fetchOnce() {
        if (!Wire.agreesWithCanon()) { Log.e("Montana", "box: the wire disagrees with the canon — nothing is read"); return }
        val twin = MontanaSeed.twin ?: return
        LetterAuthor.await()   // the author's key stands before a letter is told mine or theirs (iOS MontanaWakePush.swift:861)
        val secretOf = HashMap<String, ByteArray>()
        val invOf = HashMap<String, String>()
        val chatOf = HashMap<String, String>()
        val w0 = Wire.day()
        for (inv in MontanaCard.outstandingInvites()) {
            val s = Wire.rdvLetterSecret(inv)
            for (w in (w0 - 8)..(w0 + 1)) { val cw = Wire.rdvConvW(inv, w); secretOf[cw] = s; invOf[cw] = MontanaCard.b64url(inv) }
        }
        for (ref in Book.refs()) {
            val s = Book.secret(ref) ?: continue
            for (w in (w0 - 8)..(w0 + 1)) { val cw = Wire.convW(s, w); secretOf[cw] = s; chatOf[cw] = ref }
        }
        // THE SEED'S OWN PIPE NAMES EACH DEVICE APART (iOS BoxEar, MontanaWakePush.swift:2641-2649): the store yields no letter to the sid
        // that laid it, so this device asks under its own name there -- its own letters stay for the others
        val twinSid = HashMap<String, String>()
        Twin.secret()?.let { s ->
            for (w in (w0 - 2)..(w0 + 1)) { val cw = Wire.convW(s, w); Twin.sid(cw)?.let { sid -> secretOf[cw] = s; twinSid[cw] = sid } }
        }
        val subs = secretOf.keys.toList()
        if (subs.isEmpty()) return
        // ONE PERSON, MANY DEVICES (iOS 49bb3a95 OZ1, the author's word 24.10: the Mac took the photos, T1 got none): a letter is
        // marked taken by THIS device under its own name for the label (iOS deviceSid = twinSid, one per label, so the node links
        // no two labels), and stays in the box for the person's other devices until the box's term
        val me = Twin.deviceRef() ?: return
        val dev = { cw: String -> twinSid[cw] ?: Wire.subId(cw, me) }
        val taken = mutableListOf<JSONArray>()
        for (chunk in subs.chunked(128)) {
            val page = JSONObject().put("subs", JSONArray(chunk)).put("sids", JSONArray(chunk.map { twinSid[it] ?: Wire.subId(it, twin) }))
                .put("devs", JSONArray(chunk.map(dev)))
            val seen = HashSet<String>()
            val rows = mutableListOf<JSONObject>()
            // THE READ SWEEPS EVERY STORE of the network's list: a letter lies on the one node the writer elected (iOS 1638)
            for (door in Doors.ordered("box")) {
                val (code, text) = Wire.post(door, "/fetch", page, 6000)
                if (code != 200 || text == null) continue
                val ls = runCatching { JSONObject(text).optJSONArray("letters") }.getOrNull() ?: continue
                for (i in 0 until ls.length()) ls.getJSONObject(i).let { if (seen.add(it.optString("m"))) rows.add(it) }
            }
            for (l in rows) {
                val cw = l.optString("c"); val e = l.optString("e"); val m = l.optString("m")
                val secret = secretOf[cw] ?: continue
                val sealed = runCatching { Base64.decode(e, Base64.DEFAULT) }.getOrNull() ?: continue
                val plain = Wire.openBoxed(sealed, secret, l.optLong("at")) ?: continue
                // the history of this seed's other devices: filed there, never a letter of the feed (iOS restash → twinTakes)
                if (cw in twinSid) { val f = Wire.fields(plain); Twin.takes(f[1], f[0]); if (m.isNotEmpty()) taken.add(JSONArray(listOf(m, dev(cw)))); continue }
                val ok = invOf[cw]?.let { inv -> first(plain, inv) } ?: chatOf[cw]?.let { ref -> letter(ref, plain) } ?: false
                if (ok && m.isNotEmpty()) taken.add(JSONArray(listOf(m, dev(cw))))
            }
        }
        if (taken.isNotEmpty()) {
            // «taken», not «mids»: the node stops yielding these to this device and stops their ring; «mids» stays the funeral
            // (the node refuses more than 256 at once: the marks go by the page)
            val bodies = taken.chunked(128).map { JSONObject().put("taken", JSONArray(it)) }
            // THE STORES ARE ASKED AT ONCE, AND ONLY THE LIVING ONES (iOS MontanaWakePush.swift:2381-2399, 2155, atom fea4e68ea0da,
            // 21.09 measured 13:50:13→13:50:23 on the tablet: a walk door by door cost every burial ten seconds to two doors dead
            // on that network, and the drain stood behind it). One deadline for all; a burial is a cleanup, never delivery, so it
            // never waits in line behind a door that rests.
            val doors = Doors.ordered("box")
            val awake = doors.filter { Signal.doorAlive(it) }   // the one door book (Presence.kt, object Signal)
            for (door in (awake.ifEmpty { doors })) Thread { bodies.forEach { Wire.post(door, "/box-del", it, 5000) } }.start()
            Log.i("Montana", "box_taken n=${taken.size} doors=${awake.ifEmpty { doors }.size}")
        }
    }

    /**
     * THE FIRST LETTER OF A MEETING (iOS drainInbox «rdv» + MontanaCard.accept): ct[1088] ‖ mid‖0 text‖0 name‖0 glyph‖0 conf‖0.
     * The pipe is born from it, the chat stands with the scanner's name, the face laid beside the pipe is read, and the letter
     * is answered «delivered» — the scanner's proof that the pipe stands at both ends.
     */
    private fun first(plain: ByteArray, inv64: String): Boolean {
        if (plain.size <= 1092) return false
        val ct = plain.copyOf(1088)
        val f = Wire.fields(plain, 1088)
        val mid = f[0]; var text = f[1]
        if (mid.isEmpty() || text.isEmpty()) return false
        // a long first letter (the question of MTSamePair always is one) rides as a blob; unfolded before the pipe is born
        if (text.startsWith(Marks.LONG)) text = fetchLong(text)?.ifEmpty { text } ?: return false
        val (secret, root) = MontanaCard.acceptFirst(ct, inv64, f[4]) ?: return true   // not ours to open: buried, never retried
        return land(secret, root, mid, text, f[2])
    }

    /**
     * A FIRST LETTER OFF A CHANNEL (iOS MontanaP2P 1483-1535, openFirst 1198-1218): 0x02 ‖ the ciphertext ‖ the body sealed with the
     * new pipe's key, at the point of one of my cards — that card alone is tried, the body's seal is the proof (the box's letter
     * carries a key confirmation instead), and the letter lands as the box's first letter lands. One nobody here can open is said aloud.
     */
    fun firstOffChannel(point: ByteArray?, ct: ByteArray, sealed: ByteArray): String? {
        val w = Wire.minute()
        var plain: ByteArray? = null
        var root: ByteArray? = null
        // a letter that named no point (a frame at my window's position) walks every card, each one presenting the seal (iOS 1212-1217)
        val opens: (ByteArray) -> Boolean = { s ->
            plain = listOf(w, w - 1, w + 1).firstNotNullOfOrNull { Wire.open(Wire.bodyKey(s, it), sealed) }
            plain != null
        }
        val secret = (point?.let { listOf(it) } ?: MontanaCard.outstandingRoots()).firstNotNullOfOrNull { r ->
            MontanaCard.acceptAt(ct, r, opens)?.also { root = r }
        } ?: Names.heldRoot()?.takeIf { mine -> point == null || point.contentEquals(mine) }?.let { mine ->
            // a stranger who knocked at the name I hold (iOS openFirst 1206-1217): the name's own key, the same seal as the proof
            Names.acceptFirst(ct, opens)?.also { root = mine }
        }
        val body = plain
        val card = root
        if (secret == null || body == null || card == null) {
            Log.d("Montana", "first_refused bytes=" + sealed.size + " — there is no card here for this introduction")
            return null
        }
        val f = Wire.fields(body)
        var text = f[1]
        if (f[0].isEmpty() || text.isEmpty()) return null
        if (text.startsWith(Marks.LONG)) text = fetchLong(text)?.ifEmpty { text } ?: return null
        return if (land(secret, card, f[0], text, f[2])) Wire.reference(secret) else null
    }

    /** The pipe a first letter gives birth to: the chat with the writer's name, the face beside the pipe read, the letter placed and answered. */
    /**
     * THE RECEIVER SAYS MY LETTER'S CARGO IS GONE (iOS cargoLostMark, MontanaChatStore 4083-4098; verifyCargoNow and checkCargo,
     * MontanaDeliveryEngine 1198-1232; atom 7787c49622e5). The report may be stale -- about an old incarnation of the letter while a
     * resend rides under the same name -- so it never retracts the letter: the stores pass the sentence, every proven store asked, one
     * silent store is «don't know». Only a cargo truly absent turns a letter still riding red; a delivered letter keeps its row.
     */
    private fun cargoReported(ref: String, lost: String) {
        val m = Book.chat(ref)?.msgs?.find { it.mid == lost && it.mine } ?: return
        val o = runCatching { JSONObject(m.text.removePrefix(Marks.MEDIA)) }.getOrNull()?.takeIf { m.text.startsWith(Marks.MEDIA) } ?: return
        val bids = if (o.has("mref")) listOf(o.optString("mref"))
            else o.optJSONArray("chunks")?.let { a -> (0 until a.length()).map { a.getJSONObject(it).optString("bid") } }.orEmpty()
        if (bids.none { it.isNotEmpty() }) return
        Log.d("Montana", "cargo_lost m=" + lost.take(8) + " receiver reported: cargo gone — verifying against the node now")
        Thread {
            val have = Wire.blobsHave(bids.filter { it.isNotEmpty() }, everyStore = true) ?: return@Thread
            val gone = bids.count { it.isNotEmpty() && it !in have }
            if (gone == 0) return@Thread
            Log.d("Montana", "cargo_lost m=" + lost.take(8) + " sender check: " + gone + "/" + bids.size + " chunks gone from the node — red if the letter still rides")
            var red: Msg? = null
            Book.edit(ref) { c -> c.msgs.find { it.mid == lost && it.mine }?.let { if (it.advance(-1)) red = it } }
            red?.let { CoinSend.hold(it, ref) }
        }.start()
    }

    private fun land(secret: ByteArray, root: ByteArray, mid: String, text: String, name0: String): Boolean {
        // a letter of a conversation buried after it was born opens no chat again (iOS 876ab288): the funeral's moment says so
        if (Book.chat(Wire.reference(secret)) == null && Book.diedBefore(Wire.reference(secret), mid)) {
            Log.d("Montana", "rx_funeral m=" + mid.take(16) + " — no chat is opened for a letter born before its funeral"); return true
        }
        val ref = Book.establish(secret) ?: return false
        val name = name0.takeIf { it.isNotBlank() && it.length <= 64 } ?: ""
        val fresh = Book.chat(ref) == null
        Book.open(ref, name, MontanaCard.isPermanentRoot(root))
        if (fresh) Thread { readPipeFace(ref, secret) }.start()
        place(ref, mid, text, name, null, null)
        announce(ref)
        if (fresh) CodeMet.met()   // the page of the code that brought them closes (iOS onMet)
        return true
    }

    /** A letter off one of the phone's own channels lands where the box's letters land (iOS: one door, MontanaDeliveryEngine.receive). */
    fun fromChannel(ref: String, plain: ByteArray) { letter(ref, plain) }

    /** A letter under a pipe's label: a person's word becomes a row, a word of the wire changes the feed. */
    private fun letter(ref: String, plain: ByteArray): Boolean {
        val f = Wire.fields(plain)
        if (f[0].isEmpty() || f[1].isEmpty()) return false
        // THE ONE QUESTION EVERY INCOMING ROAD ASKS, WHERE THE BYTES ENTER (iOS ChatStore.refuses 874-879, 15.09): the feed's door
        // refused a blocked person's row while their name, face, deletions, edits, answers, pins, a call's ring and the erasure of
        // the chat still landed here. Taken from the box and said nothing — no receipt, no word of mine goes back.
        // THE NETWORK'S BAR RIDES THE SAME GATE (iOS ChatStore.refuses, MontanaChatStore.swift:879): barred after a report, refused
        // like a block, both here and at the root a folded pipe speaks for.
        if (PeerSafety.isBlocked(ref) || PeerSafety.isBlocked(SamePair.root(ref)) ||
            PeerSafety.isBarred(ref) || PeerSafety.isBarred(SamePair.root(ref))) return true
        // THE PERSON'S OWN LETTER IS TOLD AT ITS OPENING (iOS MTNodeWire.authorHolds, MontanaWakePush.swift:2768), by the words as
        // they rode -- a long letter's words change at its landing, its author field does not. The live road carries no tag.
        val own = f[7].isNotEmpty() && Book.secret(ref)?.let { Wire.authorHolds(f[7], LetterAuthor.key, it, f[0], f[1]) } == true
        if (!own) {
            Meeting.firstDone(ref)   // a word sealed under the pipe by the other side: the introduction is over
            Channels.heard(ref)   // the pipe lives: the moment to name my own address when no road of mine reaches them (iOS ChatStore 3976-3986)
        }
        var text = f[1]
        if (text.startsWith(Marks.LONG)) {
            // THE LETTER KEEPS ITS OWN HOUR (iOS lbDueNow 2672-2681): a pickup asks only a letter whose hour has come
            if (!lbDueNow(f[0])) return false
            val (words, gone) = fetchLongV(text)
            if (words == null) return lbFailed(f[0], ref, gone, Marks.birthMs(f[0])?.let { it / 1000.0 })   // later: the letter waits in the box
            lbForget(f[0])
            text = words.ifEmpty { text }
        }
        if (own) { landOwn(SamePair.root(ref), f[0], text, f[4].ifEmpty { null }, f[5].ifEmpty { null }, f[6].ifEmpty { null }); return true }
        // THE TWIN MIRROR (iOS receive, MontanaDeliveryEngine.swift:246-250): a correspondent's word this device took rides to the seed's
        // other devices -- the box gave it to this one, and this one's confirmation erases it there
        if (Twin.mirrors(text)) Twin.note(ref, f[0], text, at = Marks.birthMs(f[0])?.let { it / 1000.0 }, qt = f[4], qm = f[5], lp = f[6])
        place(ref, f[0], text, f[2], f[4].ifEmpty { null }, f[5].ifEmpty { null }, f[6].ifEmpty { null })
        return true
    }

    /**
     * A WORD THE SEED'S OTHER DEVICE MIRRORED HERE (iOS landMirrored → receive(mirrored: true)): the person's own walks the own road;
     * a correspondent's lands as if the box had brought it here -- a name already standing is a repeat and is answered by nobody
     * (the device that took it answered), a buried name stays buried, and it rides no further.
     */
    fun landMirrored(ref: String, mid: String, text: String, own: Boolean, qt: String?, qm: String?, lp: String?) {
        if (Book.secret(ref) == null && !Groups.isKey(ref)) return
        if (PeerSafety.isBlocked(ref) || PeerSafety.isBlocked(SamePair.root(ref)) ||
            PeerSafety.isBarred(ref) || PeerSafety.isBarred(SamePair.root(ref))) return
        if (own) { landOwn(SamePair.root(ref), mid, text, qt, qm, lp); return }
        if (Book.chat(SamePair.root(ref))?.msgs?.any { it.mid == mid } == true) return
        if (Book.isBuried(SamePair.root(ref), mid)) return
        place(ref, mid, text, "", qt, qm, lp)
    }

    /**
     * A LETTER OF THIS PERSON'S OTHER DEVICE LANDS AS MINE (iOS MontanaDeliveryEngine.landOwn, cd109c31): a row on my side, «sent»
     * until the correspondent's receipt moves it -- no banner, no receipt, no correspondent's name or face. A word that changes no
     * row (a name, a face, a receipt, presence, a ring) is that device's word to the correspondent, applied to nobody here. A coin
     * letter lands nowhere: its coins left the other device's book, and a row here would give them back to this one in a day
     * (CoinSend.expire) -- coins move only by Anna's word.
     */
    private fun landOwn(ref: String, mid: String, text: String, qt: String?, qm: String?, lp: String?) {
        // THE SEED'S OWN GROUP WORD (iOS landOwn -> MTGroup.handleOwn, 349cc053): the group stands on every device of these words, so
        // what that device said there is done here as it was done there -- never a row of the pipe it rode
        if (text.startsWith(Groups.MARK)) { Groups.handleOwn(text, ref); return }
        if (landOwnDeletion(ref, mid, text)) return
        val row = !Marks.isService(text) || text.startsWith(Marks.MEDIA) || text.startsWith(Marks.VOICE) || text.startsWith(Marks.STICKER)
        if (!row || CoinLetter.parse(text) != null) {
            Log.d("Montana", "rx_own m=" + mid.take(8) + " a word of another device of these words -- applied to nobody"); return
        }
        val gone = Book.isBuried(ref, mid) || Book.diedBefore(ref, mid)
        var landed = false
        Book.edit(ref) { c ->
            if (!gone && c.msgs.none { it.mid == mid }) {
                c.msgs.add(Msg(mid, text, true, Marks.birthMs(mid) ?: System.currentTimeMillis(), state = 1, qt = qt, qm = qm,
                    lp = lp?.takeIf { LinkCard.parse(it) != null }))
                c.msgs.sortBy { it.at }
                landed = true
            }
        }
        Log.d("Montana", "rx_own m=" + mid.take(8) + " landed=" + (if (landed) 1 else 0) + (if (gone) " buried here" else ""))
        if (landed && text.startsWith(Marks.MEDIA)) Media.fetch(Book.ctx, ref, mid, text, manual = true, own = true)
    }

    /**
     * A DELETION IS AN EVENT OF THE SEED'S CHAIN (iOS MontanaDeliveryEngine.landOwnDeletion, 44f44060; the critic B-4): my other
     * device took a letter away for everyone, or the whole conversation, and its word reached here signed by these words. Applied to
     * nobody, the conversation stood on this phone after the other had erased it. The word walks the hand's own road here -- the
     * letter's grave and its row, the conversation's funeral -- and nothing is said to the correspondent again: that device said it.
     */
    private fun landOwnDeletion(ref: String, mid: String, text: String): Boolean {
        if (text.startsWith(Marks.DELETE)) {
            val d = text.removePrefix(Marks.DELETE).removePrefix("mid:")
            if (d.isEmpty()) return true
            // a coin letter of mine on its way keeps its row whoever asks (iOS deleteLocally 122-128: every door asks first)
            if (Book.chat(ref)?.msgs?.find { it.mid == d }?.let { CoinSend.travels(it) } == true) Log.d("Montana", "rx_own m=" + d.take(8) + " a coin letter on its way -- kept")
            else Book.drop(ref, listOf(d))
            Log.d("Montana", "rx_own m=" + mid.take(8) + " a deletion of another device of these words, applied here kind=letter")
            return true
        }
        if (text.startsWith(CONVDEL_MARK)) {
            // its moment first, so a letter born before it stands nothing again (iOS 876ab288); a coin letter of mine not proven
            // delivered gives its coins back before its row goes (iOS removeConversationLocally 3484)
            Marks.birthMs(mid)?.let { Book.noteFuneral(ref, it) }
            Book.chat(ref)?.msgs?.toList()?.forEach { CoinSend.release(it, ref) }
            buryChat(ref)
            Log.d("Montana", "rx_own m=" + mid.take(8) + " a deletion of another device of these words, applied here kind=conversation")
            return true
        }
        return false
    }

    private fun place(ref: String, mid: String, text: String, name: String, qt: String?, qm: String?, lp: String? = null) {
        val sid = mid
        // A FOLDED PIPE FORWARDS (iOS MTSamePair): a word still on its way over a pipe folded into a conversation lands in that
        // conversation; a letter of theirs into it says our answer may have been lost, and it is said again.
        val speaksFor = SamePair.root(ref)
        if (speaksFor != ref && !SamePair.speaksOfPipe(text)) {
            val person = !Marks.isService(text) || text.startsWith(Marks.VOICE) || text.startsWith(Marks.MEDIA) || text.startsWith(Marks.STICKER)
            if (person) SamePair.remind(ref)
            return place(speaksFor, mid, text, name, qt, qm, lp)
        }
        when {
            // THE CORRESPONDENT NAMED THEIR ADDRESS (iOS ChatStore 3959-3967): into the book, dialled at once, mine named back
            text.startsWith(Channels.ADDRESS) -> Channels.peerAnnounced(ref, text.removePrefix(Channels.ADDRESS))
            // ONE PERSON, ONE CONVERSATION (iOS MTSamePair): the scanner's question over a pipe just born from my card —
            // answered, and folded when I share an older pipe with them — and the owner's answer to my own question.
            text.startsWith(Marks.SAME_ASK) -> {
                receipt(ref, sid)
                val q = SamePair.shared(text.removePrefix(Marks.SAME_ASK), ref)
                SamePair.answer(q, ref)
                if (q != null) Book.join(ref, q)
            }
            text.startsWith(Marks.SAME_YES) -> {
                receipt(ref, sid)
                SamePair.settle(ref)
                SamePair.proven(text.removePrefix(Marks.SAME_YES), ref)?.let { Book.join(ref, it) }
            }
            text.startsWith(Marks.DELIVERED) -> markDelivered(ref, text.removePrefix(Marks.DELIVERED))
            text.startsWith(Marks.READ) -> {
                val upTo = text.removePrefix(Marks.READ).toLongOrNull()
                if (upTo != null) PeerRead.note(ref, upTo)
                Presence.noteSeen(ref, System.currentTimeMillis(), "read")   // reading is being there (not a word a phone says by itself)
                // the door lets «read» only onto what was delivered — the bulk word never paints a letter they do not have
                Book.edit(ref) { c -> c.msgs.filter { it.mine && (upTo == null || (Marks.birthMs(it.mid) ?: 0) <= upTo) }.forEach { it.advance(3) } }
                // A BIRTH IN THE DIARY IS WRITTEN AS THE LETTER BORN THEN IS NAMED THERE (iOS MontanaP2PTrace.shortMs,
                // MontanaChatStore.swift 3232 at 2155, 23.09): the watermark's last eight digits, never the whole hidden address.
                Log.d("Montana", "read_rx from=" + ref.take(10) + " upto=" + (upTo?.let { Diary.shortMs(it) } ?: "-"))
            }
            // A VOICE OF MINE WAS PLAYED THERE (iOS playedMark): their own playing — the only road to «Listened»; the word itself
            // proves their build says it, so from now on a mere «read» of a voice stays «delivered».
            // THEIR BIO AND LINK AS STATE (iOS aboutMark): applied if it is the latest word, receipted either way.
            text.startsWith(Marks.ABOUT) -> {
                runCatching {
                    val o = JSONObject(text.removePrefix(Marks.ABOUT))
                    PeerAbout.note(ref, o.optString("b"), o.optString("l"), o.optDouble("at", System.currentTimeMillis() / 1000.0))
                }
                Book.edit(ref) {}
                receipt(ref, sid)
            }
            // THE PEER'S PAGE GROUND AS STATE (iOS ChatStore 4062-4074): applied if it is the latest word, receipted either way — the
            // receipt is the sender's one proof that my screen holds their ground; a build that speaks the word reads it
            text.startsWith(PageGround.MARK) -> {
                runCatching {
                    val o = JSONObject(text.removePrefix(PageGround.MARK))
                    PageGround.note(ref, o.optString("g"), o.optDouble("at", System.currentTimeMillis() / 1000.0))
                }
                PageGround.noteCapable(ref)
                receipt(ref, sid)
            }
            text.startsWith(CARGO_LOST) -> cargoReported(ref, text.removePrefix(CARGO_LOST))
            text.startsWith(Marks.PLAYED) -> {
                val d = text.removePrefix(Marks.PLAYED)
                Prefs.setBool("plcap_$ref", true)
                Book.edit(ref) { c -> c.msgs.find { it.mid == d && it.mine }?.heard = true }
            }
            text.startsWith(Marks.DELETE) -> {
                val d = text.removePrefix(Marks.DELETE).removePrefix("mid:")
                // THE PERSON KEEPS WHAT OTHERS DELETE (iOS MontanaChatStore.swift:4673-4693, LevelAccess.keepDeleted): the letter stays and
                // this phone says so itself, quietly -- the sender's phone never believes a deletion that did not happen here. The level
                // is read before it is asked; a letter not on this phone is not kept, the word «kept» is said only of what it holds.
                PersonChain.prime(); CoinBook.warm()
                val row = Book.chat(ref)?.msgs?.find { it.mid == d }
                if (row != null && LevelAccess.keepsDeleted) {
                    Log.i("Montana", "delete_kept mid=" + d.take(12) + " kept by the person's choice -- the sender is told")
                    Post.send(ref, Marks.mintMid(), Marks.DELETE_KEPT + "mid:" + d, quiet = true)
                }
                // a coin letter of mine on its way keeps its row whoever asks (iOS deleteLocally 122-128: every door asks first)
                else if (row?.let { CoinSend.travels(it) } != true) {
                    Book.drop(ref, listOf(d))
                    Notify.withdraw(ref, d)   // its banner leaves with it (iOS b6ab7094 at 2240)
                }
            }
            // MY DELETION WAS KEPT THERE (iOS deleteKeptMark, MontanaChatStore.swift:4674 at 2242): the keeper's own word, told as a banner
            text.startsWith(Marks.DELETE_KEPT) -> { Log.d("Montana", "delete_kept_rx to=" + ref.take(10)); Notify.kept(ref) }
            text.startsWith(Marks.EDIT) -> runCatching {
                val o = JSONObject(text.removePrefix(Marks.EDIT)); val d = o.getString("sid").removePrefix("mid:"); val tx = o.optString("tx")
                // only a person's words: within a bubble's length, carrying no service mark of their own (iOS applyEditFromPeer 3380-3387)
                if (d.isEmpty() || 128 < d.length || tx.isBlank() || 4500 < tx.length || Marks.isService(tx)) Log.d("Montana", "edit_rx refused: not a person's words")
                else if (!applyEdit(ref, d, tx)) holdEdit(ref, d, tx)
            }
            text.startsWith(Marks.REACTION) -> runCatching {
                val o = JSONObject(text.removePrefix(Marks.REACTION)); val d = o.getString("sid").removePrefix("mid:"); val e = o.getString("e")
                // coins given on a letter ride the reaction's road under their own op: credited, never an emoji (iOS 5901-5908)
                if (o.optString("op") == "coin") CoinSend.reacted(o.optLong("c"), o.optString("r"), o.optString("sid"), ref)
                // THE CORRESPONDENT HAS ONE ANSWER ON A LETTER (iOS applyReaction 5858-5866): a new one replaces their old, and taking one
                // away takes theirs — Android kept one list for both, so their taking away a sign we both gave took away mine
                else Book.edit(ref) { c -> c.msgs.find { it.mid == d }?.let { m ->
                    if (o.optString("op") == "del") { m.reactions.remove(e); if (m.peerReact == e) m.peerReact = null; if (!c.ansMine) c.noteAnswer(null, false, m) }
                    else {
                        m.peerReact?.takeIf { it != e }?.let { old -> m.reactions.remove(old) }
                        if (m.peerReact != e) m.reactions.add(e)
                        m.peerReact = e
                        c.noteAnswer(e, false, m, Marks.birthMs(sid) ?: System.currentTimeMillis())   // the row wears the answer, at its own birth
                    }
                } }
            }
            // THEIR PIN OR UNPIN OF A LETTER (iOS pinMark → applyPinFromControl): silent, the plate follows
            text.startsWith(PIN_MARK) -> applyPin(ref, text.removePrefix(PIN_MARK))
            // THE CONVERSATION WIPED AT BOTH (iOS convDelMark): the receipt settles their queue, then it is buried here too
            // a coin letter of mine not proven delivered gives its coins back before its row goes (iOS removeConversationLocally 3484)
            // THE PIPE CLOSED AT THE OTHER END (iOS pipeClosedMark, MontanaChatStore 4166-4172 and peerClosedPipe 3531-3548; fork atom
            // 1927): receipted, then a folded pipe simply dies, a meeting that never carried a word leaves no row, and a conversation keeps
            // its history, readable, with a note where the field stood. Android swallowed the word unreceipted and wrote on into nothing.
            text.startsWith(Marks.PIPE_CLOSED) -> { receipt(ref, sid); peerClosed(ref) }
            text.startsWith(CONVDEL_MARK) -> { receipt(ref, sid); peerFuneral(ref, sid) }
            text.startsWith(Marks.NAME) -> {
                val n = text.removePrefix(Marks.NAME).trim()
                // A CORRESPONDENT'S SENT NAME LOSES ITS CROWN (iOS MTCrown.plain, atom d4142dd38143): only a Royal hands one out.
                if (n.isNotEmpty() && n.length <= 64 && Book.admitState(ref, "name", Marks.birthMs(sid) ?: 0L)) Book.edit(ref) { it.name = stripCrown(n) }
                receipt(ref, sid)
            }
            // the face as the name: a word older than the one that stands changes nothing (iOS stateIsCurrent)
            text.startsWith(Marks.AVATAR) && !Book.admitState(ref, "face", Marks.birthMs(sid) ?: 0L) -> receipt(ref, sid)
            text.startsWith(Marks.AVATAR) -> {
                val b64 = text.removePrefix(Marks.AVATAR)
                val face = if (b64.isEmpty()) null else runCatching { Base64.decode(b64, Base64.DEFAULT) }.getOrNull()
                if (face == null || face.isEmpty()) Book.face(ref).delete() else if (face.size <= 262_144) Book.setFace(ref, face)
                // the answer to an ask: «no face» is asked no more in this life; a face that lands ends it as well (iOS E2E.faceNone)
                if (face == null || face.isEmpty()) Presence.faceNone.add(ref) else Presence.faceNone.remove(ref)
                Book.edit(ref) {}
                receipt(ref, sid)
            }
            // A GROUP'S WORD (iOS MTGroup.handle): an invitation, a letter or an answer of a group its owner carries over the pipes —
            // it lands in the group's own feed, never as a row of this pipe, and its copy is receipted by its own name
            text.startsWith(Groups.MARK) -> Groups.handle(ref, sid, text)
            // A WORD OF A WALL (iOS MTBoard.handle): a page of a person's wall, an ask for mine — receipted, never a row
            text.startsWith(Board.MARK) -> Board.handle(ref, sid, text)
            // A CALL AS A LETTER (iOS ringMark): it rings here and is never a row; its age and the seeds seen cut the stale (Calls);
            // a dead invitation still gets its receipt, as a missed call's repeat does (iOS 89e12948)
            text.startsWith(Marks.RING) -> { if (!Calls.ringLetter(ref, text.removePrefix(Marks.RING))) receipt(ref, sid) }
            // THE CALLER'S «MISSED» (iOS missedCallMark): the row of a call this phone never saw, receipted either way
            text.startsWith(Marks.MISSED) -> { Calls.missedLetter(ref, text.removePrefix(Marks.MISSED)); receipt(ref, sid) }
            // A DRAFT WORD BY THE QUEUE (iOS ChatStore 3884-3898): the daily link, a checkpoint, an ask — read as the live lane reads
            // it (Presence.hear), never a row; the durable link rode here and was dropped unread
            text.startsWith(LiveDraft.MARK) -> Presence.hear(ref, text)
            Marks.isService(text) && !text.startsWith(Marks.VOICE) && !text.startsWith(Marks.MEDIA) && !text.startsWith(Marks.STICKER) && !text.startsWith(Marks.LONG) -> {}
            // A BLOCKED PERSON'S LETTERS DO NOT REACH THE FEED (iOS MontanaSafety: the block is enforced on every road).
            // A STEP OF A GAME (iOS MTChessLetter.isStep): the board reads it; no bubble, no unread, the closing letter alone rings
            ChessLetter.isStep(text) && !PeerSafety.isBlocked(ref) -> ChessSend.landed(ref, mid, text)
            PeerSafety.isBlocked(ref) -> {}
            // A LETTER BORN BEFORE ITS CONVERSATION'S FUNERAL IS THE DEAD CONVERSATION'S (iOS append diedBefore, 876ab288): it lands
            // nowhere and revives nothing, and the grave answers it as it answers a buried one
            Book.diedBefore(ref, mid) -> { Log.d("Montana", "rx_funeral m=" + mid.take(16) + " — born before the conversation's funeral"); receipt(ref, sid) }
            else -> {
                var isNew = false
                if (lp != null) Log.d("Montana", "link card: rides the letter mid=" + mid.take(8))
                Presence.noteSeen(ref, Marks.birthMs(mid), "letter")   // a person's own word stamps the moment it was written (iOS append)
                Book.edit(ref) { c ->
                    val had = c.msgs.find { it.mid == mid }
                    // THE SAME LETTER AGAIN, NOW WITH ITS CARD (iOS attachPreview's copy): the card joins the row, nothing else moves
                    // THE PICTURE CATCHES UP TOO (iOS enrichLinkPreview, MontanaChatStore.swift at 2155, the critic 22.09): the
                    // envelope leg rides without the picture, so a card that came by it carried no face until the mesh copy
                    // behind it filled it in -- and only the picture moves; nothing else of a standing card does.
                    if (had != null && lp != null) LinkPreview.enrich(had, lp, mid)
                    // THE SAME LETTER WITH NEW CARGO REFILLS ITS ROW (iOS 1638, DeliveryEngine 159-169; the author's invariant: what stands
                    // in the sender's chat stands in the receiver's): a media row without its file takes the copy's manifest -- the sender
                    // re-uploaded under the same name -- and the assembly receipts when the file is whole; nothing erased, nothing doubled
                    if (had != null && text.startsWith(Marks.MEDIA) && had.text != text && had.file?.let { File(it).exists() } != true) {
                        had.text = text; had.meta = null
                        Log.d("Montana", "rx_refill m=" + mid.take(8) + " the row stands without its file — the copy's cargo is taken")
                    }
                    if (had == null && Book.isBuried(ref, mid)) Log.d("Montana", "rx_buried m=" + mid.take(8) + " — a deleted letter's copy stays out of the feed")
                    else if (had == null) {
                        val at = Marks.birthMs(mid) ?: System.currentTimeMillis()
                        c.msgs.add(Msg(mid, text, false, at, qt = qt, qm = qm, lp = lp?.takeIf { LinkCard.parse(it) != null })); c.msgs.sortBy { it.at }
                        // A LOCKED PHONE DOES NOT READ WHAT IT CANNOT SHOW (iOS placeRow, MontanaChatStore.swift:184 at 2155): a letter
                        // landing with the chat left open while the app itself is backgrounded used to be born read, and the icon never
                        // met it; the open chat alone is not enough, the app must stand before the person too (MTForeground.active).
                        if (Book.openChat != ref || !Presence.shown) c.unread++
                        if (c.name.isEmpty() && name.isNotBlank()) c.name = name
                        isNew = true
                    }
                }
                // A MEDIA LETTER IS ANSWERED ONLY ONCE ITS FILE IS ASSEMBLED (iOS: the receipt waits for the file).
                if (text.startsWith(Marks.MEDIA)) Media.fetch(Book.ctx, ref, mid, text) else receipt(ref, sid)
                if (isNew && Book.openChat == ref) markRead(ref)
                if (isNew && Book.openChat != ref) Notify.letter(ref, text, mid = mid)
                if (isNew) CoinSend.landed(ref, mid, text, qt)   // a coin letter is credited once by its wire name (iOS MTCoinSend)
                if (isNew) takeEdit(ref, mid)?.let { applyEdit(ref, mid, it) }   // the words that outran the letter (iOS takePendingEdit)
            }
        }
    }

    /**
     * THE PEER'S EDIT (iOS applyEditFromPeer, MontanaChatStore 3371-3415): only on a letter of theirs — a word off the wire never
     * rewrites my own letters, or one side could put words into the other's mouth. A text letter takes the new words; a picture's or a
     * video's caption is a person's words too (the author's word 19.09) and is rewritten inside its manifest; a voice, a file, a call
     * row and a service word are not letters whose words change. Android wrote the caption's words over a picture's whole letter.
     * False: the letter has not landed here yet.
     */
    private fun applyEdit(ref: String, mid: String, tx: String): Boolean {
        var found = false
        Book.edit(ref) { c -> c.msgs.find { it.mid == mid }?.let { m -> found = true; if (!m.mine) reword(m, tx) } }
        return found
    }
    /** New words on a letter: a text letter's own, or a picture's or a film's caption in its manifest (iOS editMessage, applyEditFromPeer). */
    fun reword(m: Msg, tx: String) {
        if (!m.text.startsWith(Marks.MEDIA)) {
            if (Marks.isService(m.text) || m.text == tx) return
            m.text = tx; m.edited = true
            return
        }
        val meta = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() }
        val man = meta ?: Media.inline(m.text) ?: return
        if (man.optString("k") != "img" && man.optString("k") != "vid") return
        if (man.optString("cap") == tx) return
        man.put("cap", tx)
        if (meta != null) m.meta = man.toString() else m.text = Marks.MEDIA + man.toString()
        m.edited = true
    }
    /** An edit for a letter still on the road is held and applied the moment it lands, so the race cannot lose the newer words (iOS pendingEdits: 32 a chat, a bound, not a memory). */
    private val pendingEdits = HashMap<String, LinkedHashMap<String, String>>()
    private fun holdEdit(ref: String, mid: String, tx: String) = synchronized(pendingEdits) {
        val held = pendingEdits.getOrPut(ref) { LinkedHashMap() }
        if (32 <= held.size) held.remove(held.keys.first())
        held[mid] = tx
        Log.d("Montana", "edit_rx held mid=" + mid.take(8) + " the letter has not landed yet")
    }
    private fun takeEdit(ref: String, mid: String): String? = synchronized(pendingEdits) {
        val held = pendingEdits[ref] ?: return null
        val tx = held.remove(mid)
        if (held.isEmpty()) pendingEdits.remove(ref)
        tx
    }

    private fun peerClosed(ref: String) {
        if (SamePair.merged(ref) != null) { Book.forget(ref); Log.i("Montana", "pipe_closed folded"); return }
        val person = Book.chat(ref)?.msgs?.any { !Marks.isService(it.text) || it.text.startsWith(Marks.MEDIA) || it.text.startsWith(Marks.VOICE) } == true
        if (!person) { buryChat(ref); Log.i("Montana", "pipe_closed empty"); return }
        Prefs.setBool("pipeClosed." + ref, true)
        Archive.closeHead(ref)   // the folder says so: no restore revives the pipe from the secret it holds (iOS closeHead)
        Book.edit(ref) {}
        Log.i("Montana", "pipe_closed kept")
    }
    /** The other side closed this conversation: it is read, not answered (iOS closedChats). */
    fun closed(ref: String) = ref.startsWith("arc:") || Prefs.bool("pipeClosed." + ref, false)   // a recovered history is read, never answered

    /** «Delivered» for a letter of theirs — under its own name, so the queue holds one per letter (iOS receiptMid). */
    // THE ONE RECEIPT DOOR also says the letter stands whole here: its name rides every presence word after «K» (iOS HeldLetters.note)
    private fun receipt(ref: String, mid: String) { HeldLetters.note(ref, mid); send(ref, "rcpt-$mid", Marks.DELIVERED + mid) }
    fun receiptFor(ref: String, mid: String) = receipt(ref, mid)

    /** THE ONE DELIVERY DOOR (iOS markDelivered): a receipt, or a presence word naming the letter whole (HeldLetters, «by=word»). */
    fun markDelivered(ref: String, d: String) {
        announcedDelivered(ref, d)   // a receipt of my name or my face writes the mark (iOS recordDelivered)
        // a group's copy witnesses the group's row, never a row of the pipe (iOS markDelivered → MTGroup.copyDelivered)
        if (Groups.copyDelivered(d)) return
        // THE READ WORD MAY HAVE OUTRUN THIS RECEIPT (iOS markDelivered 4221-4226): a film is told «delivered» only once
        // its file is whole there, while «read» leaves the moment the chat is open — the mark remembers, the letter catches up
        val u = PeerRead.upTo(ref)
        var row: Msg? = null
        Book.edit(ref) { c ->
            c.msgs.find { it.mid == d && it.mine }?.let { m ->
                row = m
                if (m.advance(2) && u != null && (Marks.birthMs(m.mid) ?: Long.MAX_VALUE) <= u) m.advance(3)
            }
        }
        // a coin letter whose row is gone: its coins that came back are taken again (iOS markDelivered 4266, MTCoinSend.arrived)
        // a red one delivered after all, its coins home: they are taken again, every door of the ladder asks (iOS hold)
        row?.let { CoinSend.hold(it, ref) } ?: CoinSend.arrived(d, ref)
    }

    /**
     * A VOICE OF THEIRS WAS PLAYED HERE (iOS notePlayed): its sender is told once, silently. Opening the chat plays nothing
     * and says nothing.
     */
    fun notePlayed(mid: String) {
        val ref = Book.refs().firstOrNull { r -> Book.chat(r)?.msgs?.any { it.mid == mid } == true } ?: return
        var fresh = false
        Book.edit(ref) { c -> c.msgs.find { it.mid == mid && !it.mine && !it.heard }?.let { it.heard = true; fresh = true } }
        if (fresh) send(ref, Marks.mintMid(), Marks.PLAYED + mid)
    }

    /**
     * THE PEER'S READ MARK PER CONVERSATION (iOS peerReadUpTo / notePeerRead 2807-2822): the newest of my letters, by its birth
     * millisecond, the peer declared read — kept sealed, so a receipt that lands after the read word still raises its letter.
     */
    object PeerRead {
        private const val KEY = "peerReadMap"
        private val lock = Any()
        private fun map(): JSONObject = DeviceVault.get(KEY)?.toString(Charsets.UTF_8)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
        fun wipe() = synchronized(lock) { DeviceVault.delete(KEY) }
        fun upTo(ref: String): Long? = synchronized(lock) { map().optLong(ref, 0L).takeIf { it > 0L } }
        /** The marks as kept, for a copy (iOS «peerReadMap», notePeerRead 2872-2879: the same map of conversation to millisecond). */
        fun carried(): ByteArray? = synchronized(lock) { DeviceVault.get(KEY) }
        /** A copy laid (iOS SeedScope.unionKeys 6307): a conversation's mark held here stands, the copy adds the others. */
        fun lay(m: Map<String, Long>) {
            synchronized(lock) {
                val have = map()
                for ((r, ms) in m) if (!have.has(r) && ms > 0) have.put(r, ms)
                DeviceVault.set(KEY, have.toString().toByteArray(Charsets.UTF_8))
            }
        }
        fun note(ref: String, ms: Long) = synchronized(lock) {
            val m = map()
            if (m.optLong(ref, 0L) < ms) { m.put(ref, ms); DeviceVault.set(KEY, m.toString().toByteArray(Charsets.UTF_8)) }
        }
    }

    /** «Read» covering the newest letter of theirs on the screen, by their birth millisecond (iOS sendReadMark). */
    fun markRead(ref: String) {
        // UNDER A LOCKED PHONE IT WAITS FOR THE RETURN (iOS sendReadMark's own guard, MontanaChatStore.swift:2848 at 2155:
        // «guard MTForeground.active else ... return»): the one emitter of the read mark refuses while the app is not before
        // the person's eyes; Presence.appShown asks again the moment it is.
        if (!Presence.shown) return
        val c = Book.chat(ref) ?: return
        if (Book.isLocal(ref)) { if (c.unread > 0) Book.edit(ref) { it.unread = 0 }; return }   // a room without an address has nobody to tell
        // THE SEED'S OTHER DEVICES READ IT TOO (iOS markRead's mirrorNote, 349cc053): what was unread here is read there up to the same letter
        if (c.unread > 0) c.msgs.filter { !it.mine }.maxOfOrNull { Marks.birthMs(it.mid) ?: it.at }?.takeIf { it > 0 }?.let { Twin.read(ref, it) }
        // A GROUP'S READ MARK RIDES THE GROUP'S OWN ROAD (iOS sendReadMark → MTGroup.tellRead, B.13): a group has no pipe to receipt on
        if (Groups.isKey(ref)) { Book.edit(ref) { it.unread = 0 }; Groups.readSoon(ref); return }
        // a blocked person hears no word of mine (iOS sendReadMark 2842: read_skip why=blocked)
        if (!Prefs.bool("readReceiptsEnabled", true) || PeerSafety.isBlocked(ref)) { Book.edit(ref) { it.unread = 0 }; return }
        val upTo = c.msgs.filter { !it.mine }.mapNotNull { Marks.birthMs(it.mid) }.maxOrNull()
        Book.edit(ref) { it.unread = 0 }
        // A BIRTH IN THE DIARY IS WRITTEN AS THE LETTER BORN THEN IS NAMED THERE (iOS MontanaP2PTrace.shortMs,
        // MontanaChatStore.swift 2067 at 2155, 23.09): the watermark's last eight digits, never the whole hidden address.
        Log.d("Montana", "read_tx to=" + ref.take(10) + " upto=" + (upTo?.let { Diary.shortMs(it) } ?: "-"))
        send(ref, Marks.mintMid(), Marks.READ + (upTo?.toString() ?: ""))
    }

    /** THE FACE BESIDE THE PIPE (iOS readPipeFace): asked at once and twice more across eight seconds. */
    private fun readPipeFace(ref: String, secret: ByteArray) {
        val bid = Wire.faceBid(secret)
        val key = Wire.faceKey(secret)
        for (pause in longArrayOf(0, 2000, 6000)) {
            if (pause > 0) Thread.sleep(pause)
            val sealed = Wire.getBlob(bid) ?: continue
            val face = Wire.open(key, sealed) ?: return
            if (face.isEmpty() || face.size > 262_144) return
            Book.setFace(ref, face)
            return
        }
    }
}

/**
 * MY WORDS ABOUT MYSELF (iOS MTPeerAbout.myBio/myLink + E2E.sendAboutIfNeeded): the bio trimmed to 140, the link only when
 * it is a web link; to every correspondent as one silent AB: {b, l, at} — again whenever they change, never twice for the
 * same words, and nothing at all while nothing was ever said and nothing is said now.
 */
object MyAbout {
    const val BIO_LIMIT = 140
    fun bio() = Prefs.str("profileBio", "").trim().take(BIO_LIMIT)
    fun link() = PeerAbout.spoken(Prefs.str("profileLink", ""))   // every link of the field, one space apart (iOS myLink, 609736de)
    private fun tag(b: String, l: String) = if (b.isEmpty() && l.isEmpty()) "0" else Wire.hex(Wire.sha((b + "\n" + l).toByteArray())).take(16)
    /**
     * THE BIO AND THE LINK ARE RECEIPTED STATE, AS THE NAME AND THE FACE (iOS atom 4c4d49f9dc26, the author's word 24.09: «my profile
     * did not show to others until I edited it»): the mark «annAbout2.» is written by the receipt of the very letter alone
     * (announcedDelivered); until it, the words are on their way for an hour and are not said twice; a letter lost past that hour goes
     * again at the next announce. The old mark «annAbout.» was written before the send and meant nothing -- it is not read.
     */
    fun sendIfNeeded(ref: String) {
        if (PeerSafety.isBlocked(ref) || SamePair.merged(ref) != null) return
        if (!Prefs.has("profileBio") && !Prefs.has("profileLink")) return   // unread words are silence, not «no words» (iOS MontanaSelf.holds)
        val b = bio(); val l = link(); val t = tag(b, l)
        val held = Prefs.str("annAbout2.$ref", "")
        if (held == t || (held.isEmpty() && t == "0") || Post.inFlight("A", ref, t)) return
        val mid = Marks.mintMid()
        Post.flight("A", ref, t, mid)
        Post.send(ref, mid, Marks.ABOUT + JSONObject().put("b", b).put("l", l).put("at", System.currentTimeMillis() / 1000.0))
    }
    fun broadcast() { Book.refs().forEach { sendIfNeeded(it) } }
}
