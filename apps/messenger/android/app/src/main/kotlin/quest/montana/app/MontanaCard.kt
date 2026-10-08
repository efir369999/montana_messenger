package quest.montana.app

import android.content.Context
import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * THE CARD (iOS MontanaCard): what the QR code and the shared link carry. The link holds only an INVITATION — 32 random
 * bytes — and the card itself lies on the node under it, sealed: the contact key (ML-KEM-768, 1184 bytes) and the name of
 * the one showing it. Whoever holds the link fetches the card, encapsulates to the key once, and a correspondence exists;
 * the key's secret half never leaves this phone. Byte for byte as iOS lays it: the same bids, the same keys, the same
 * sealing (the core's mt_e2e_seal_blob), the same node door (/pushwake/blob-put), so an iPhone that scans this link
 * reads it as it reads any iPhone's.
 *
 * Two kinds, as on iOS: the PERMANENT link — born once and kept for good — and the TEMPORARY one of the day, turned
 * exactly 24 hours after its birth; the day before stays able to receive, and yesterday's link answers «spent».
 */
object MontanaCard {
    const val PERM_PREFIX = "https://montana.quest/perp/"
    const val TEMP_PREFIX = "https://montana.quest/temp/"
    private const val NAME_LIMIT = 64
    private const val LIFETIME = 24 * 3600L
    private const val PERM_MAGIC = "mt-rdv-perm"
    private const val SPENT_MAGIC = "mt-rdv-spent"
    // The records, sealed in the device vault (iOS MontanaLocalVault, the same names).
    private const val KEYS = "cardKeys"            // contact key (base64url) → its secret half
    private const val PERM = "rdvPermanent"        // invitation → card payload
    private const val DAILY = "rdvCards"           // invitation → card payload (the day's and the one before)
    private const val CURRENT = "rdvCurrent"       // the day's invitation
    private const val BORN = "rdvCurrentBorn"      // when it was born, seconds
    /** The doors that keep the cards (the shipped list, iOS nodes.txt): every door that holds «blob». */
    val doors = listOf("https://api.montana.quest/pushwake", "https://montana.xxx/pushwake")

    private val lock = Any()

    // ── the bytes ──
    fun b64url(d: ByteArray): String = Base64.encodeToString(d, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    fun unb64url(s: String): ByteArray? = runCatching { Base64.decode(s, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP) }.getOrNull()
    private fun sha(label: String, inv: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(label.toByteArray() + byteArrayOf(0) + inv)
    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    fun rdvKey(inv: ByteArray) = sha("mt-rdv-k", inv)
    fun rdvBid(inv: ByteArray) = hex(sha("mt-rdv-a", inv))
    fun permBid(inv: ByteArray) = hex(sha("mt-rdv-p", inv))
    fun faceBid(inv: ByteArray) = hex(sha("mt-rdv-f", inv))
    fun faceKey(inv: ByteArray) = sha("mt-rdv-fk", inv)

    // ── the records ──
    private fun map(name: String): MutableMap<String, ByteArray> {
        val raw = DeviceVault.get(name) ?: return mutableMapOf()
        val o = runCatching { JSONObject(String(raw, Charsets.UTF_8)) }.getOrNull() ?: return mutableMapOf()
        return o.keys().asSequence().associateWith { Base64.decode(o.getString(it), Base64.NO_WRAP) }.toMutableMap()
    }
    private fun save(name: String, m: Map<String, ByteArray>): Boolean {
        val o = JSONObject(); m.forEach { (k, v) -> o.put(k, Base64.encodeToString(v, Base64.NO_WRAP)) }
        return DeviceVault.set(name, o.toString().toByteArray(Charsets.UTF_8))
    }
    private fun text(name: String) = DeviceVault.get(name)?.toString(Charsets.UTF_8)
    private fun keyHeld(payload: ByteArray) = map(KEYS).containsKey(b64url(payload.copyOf(1184)))

    /** The card's body wears the profile's name of this moment (iOS reminted): the key, and the name after it. */
    private fun withName(payload: ByteArray): ByteArray {
        val root = payload.copyOf(1184)
        val n = Prefs.userName.trim().toByteArray(Charsets.UTF_8)
        return if (n.isNotEmpty() && n.size <= NAME_LIMIT) root + n else root
    }

    /** A new card: its key drawn by the core from a seed the core drew, the secret half kept here alone (iOS offer). */
    private fun born(): Pair<ByteArray, ByteArray>? {
        val seed = MtBindings.nativeRandom(64) ?: return null
        val inv = MtBindings.nativeRandom(32) ?: return null
        val kp = MtBindings.nativeMlkemKeypair(seed) ?: return null
        val pk = kp.copyOfRange(0, 1184); val sk = kp.copyOfRange(1184, 1184 + 2400)
        val keys = map(KEYS); keys[b64url(pk)] = sk
        if (!save(KEYS, keys)) return null
        return inv to withName(pk)
    }

    /** THE PERMANENT LINK: born once, shown as long as the person keeps it, laid on the node again every two hours or at a rename. */
    fun offerPermanent(c: Context): String? = synchronized(lock) {
        val perm = map(PERM)
        perm.entries.firstOrNull()?.let { (inv64, payload) ->
            val inv = unb64url(inv64)
            if (inv != null && keyHeld(payload)) {
                val np = withName(payload)
                val renamed = !np.contentEquals(payload)
                if (renamed) save(PERM, mapOf(inv64 to np))
                if (renamed || due("rdvPermUpAt")) { upload(c, inv, np, "rdvPermUpAt"); uploadPermMark(inv) }
                return PERM_PREFIX + inv64
            }
        }
        val (inv, payload) = born() ?: return null
        save(PERM, mapOf(b64url(inv) to payload))
        upload(c, inv, payload, "rdvPermUpAt"); uploadPermMark(inv)
        PERM_PREFIX + b64url(inv)
    }

    /** THE LINK OF THE DAY: one per device, born exactly a day after the one before; the one before keeps receiving. */
    fun offerShort(c: Context): String? = synchronized(lock) {
        val daily = map(DAILY)
        val cur = text(CURRENT)
        val bornAt = text(BORN)?.toDoubleOrNull()
        if (cur != null && bornAt != null && now() - bornAt < LIFETIME) {
            val payload = daily[cur]; val inv = unb64url(cur)
            if (payload != null && inv != null && keyHeld(payload)) {
                if (due("rdvUpAt")) upload(c, inv, payload, "rdvUpAt")
                return TEMP_PREFIX + cur
            }
        }
        val (inv, payload) = born() ?: return null
        val keep = mutableMapOf<String, ByteArray>()
        if (cur != null) daily[cur]?.let { keep[cur] = it }          // the receiving generation: its secret stays
        keep[b64url(inv)] = payload
        if (!save(DAILY, keep) || !DeviceVault.set(CURRENT, b64url(inv).toByteArray()) ||
            !DeviceVault.set(BORN, now().toString().toByteArray())) return null
        // Yesterday's links answer «spent» at once; the generations older than the one before are buried whole.
        val keys = map(KEYS)
        for ((inv64, pl) in daily) {
            unb64url(inv64)?.let { old -> seal(rdvKey(old), SPENT_MAGIC.toByteArray())?.let { tomb -> Thread { put(rdvBid(old), tomb) }.start() } }
            if (inv64 != cur) keys.remove(b64url(pl.copyOf(1184)))
        }
        save(KEYS, keys)
        upload(c, inv, payload, "rdvUpAt")
        TEMP_PREFIX + b64url(inv)
    }

    /** Every live invitation — the daily generations and the permanent one (iOS outstandingInvites). */
    fun outstandingInvites(): List<ByteArray> = synchronized(lock) {
        (map(DAILY).keys + map(PERM).keys).distinct().mapNotNull { unb64url(it) }.filter { it.size == 32 }
    }

    /** The roots of the cards handed out and not spent — the points a first letter may knock at (iOS outstandingRoots). */
    fun outstandingRoots(): List<ByteArray> = synchronized(lock) {
        (map(DAILY).values + map(PERM).values).filter { keyHeld(it) }.map { it.copyOf(1184) }
    }

    /**
     * THE OFFERING SIDE, OFF A CHANNEL (iOS accept(firstLetter:root:confirmed:), openFirst 1198-1211): the point the letter knocked at
     * named the card, so exactly that one is tried; decapsulation never refuses (implicit rejection, FIPS 203), so the proof is the
     * body's own seal under the secret it gives. The secret, or null.
     */
    fun acceptAt(ct: ByteArray, root: ByteArray, proof: (ByteArray) -> Boolean): ByteArray? {
        val sk = synchronized(lock) { map(KEYS)[b64url(root)] } ?: return null
        val ss = MtBindings.nativeMlkemDecaps(sk, ct) ?: return null
        val secret = MtBindings.nativeFirstSecret(ss, root, ct)
        ss.fill(0)
        return secret?.takeIf(proof)
    }

    /** Did the letter come through the permanent card's point? (iOS isPermanentRoot) */
    fun isPermanentRoot(root: ByteArray): Boolean = synchronized(lock) { map(PERM).values.any { it.copyOf(1184).contentEquals(root) } }

    /**
     * THE OFFERING SIDE, FROM THE BOX (iOS accept(firstLetter:invite:conf:)): the invitation whose seal opened the letter names
     * the one card to try — nothing is walked. Decapsulation never refuses (implicit rejection), so the key confirmation is the
     * proof: SHA-256("mt-first-conf"‖0‖secret‖ct)[0..16] in base64url, compared in constant time. The secret and the root, or null.
     */
    fun acceptFirst(ct: ByteArray, inv64: String, conf: String): Pair<ByteArray, ByteArray>? {
        val (root, sk) = synchronized(lock) {
            val payload = (map(DAILY) + map(PERM))[inv64] ?: return null
            val root = payload.copyOf(1184)
            root to (map(KEYS)[b64url(root)] ?: return null)
        }
        val ss = MtBindings.nativeMlkemDecaps(sk, ct) ?: return null
        val secret = MtBindings.nativeFirstSecret(ss, root, ct) ?: return null
        ss.fill(0)
        val want = b64url(MessageDigest.getInstance("SHA-256").digest("mt-first-conf".toByteArray() + byteArrayOf(0) + secret + ct).copyOf(16))
        if (!MessageDigest.isEqual(want.toByteArray(), conf.toByteArray())) return null
        return secret to root
    }

    /** The words a share carries before the link (iOS MontanaConv.inviteMessage). */
    fun inviteMessage(c: Context, permanent: Boolean) = c.getString(if (permanent) R.string.invite_perm else R.string.invite_temp)

    /** The day's link and the moment it was born, seconds (iOS currentShortWithBorn): handed to a correspondent to hand on. */
    fun currentShortWithBorn(c: Context): Pair<String, Double>? {
        val link = offerShort(c) ?: return null
        val born = text(BORN)?.toDoubleOrNull() ?: return null
        return link to born
    }

    /** When the day's link turns (born + one day), or null. */
    fun renewsAt(): Long? = text(BORN)?.toDoubleOrNull()?.let { ((it + LIFETIME) * 1000).toLong() }

    /** The person leaves: the card records leave with them (iOS MontanaCard.wipe). */
    fun forget() { listOf(KEYS, PERM, DAILY, CURRENT, BORN).forEach(DeviceVault::delete); Prefs.remove("rdvPermUpAt", "rdvUpAt") }

    // ── the node ──
    private fun now() = System.currentTimeMillis() / 1000.0
    /**
     * By term, never at every showing: a top-up per showing is a beacon of the owner's activity for the node. The term is only
     * asked here: THE STAMP IS THE NODE'S OK (Business 06.10, b141246b: a card born in a run the installer closed before its upload
     * kept a stamp and was laid by nobody for two hours, while its code was shown) — upload writes it, and only on success.
     */
    private fun due(stamp: String): Boolean = now() - Prefs.dbl(stamp, 0.0) > 7200
    private fun seal(key: ByteArray, payload: ByteArray): ByteArray? {
        val nonce = MtBindings.nativeRandom(12) ?: return null
        return MtBindings.nativeSealBlob(key, nonce, payload)
    }

    /**
     * The card goes onto the node, and the face beside it. Its stamp is written by the node's ok alone, and only while the card still
     * stands at its place (a day's card turned meanwhile is not stamped for the new one); a card on its way is not sent twice.
     */
    private fun upload(c: Context, inv: ByteArray, payload: ByteArray, stamp: String) {
        val key = b64url(inv)
        if (!synchronized(flying) { flying.add(key) }) return
        val sealed = seal(rdvKey(inv), payload) ?: run { synchronized(flying) { flying.remove(key) }; return }
        Thread {
            try {
                var ok = put(rdvBid(inv), sealed)
                if (!ok) { Thread.sleep(20_000); ok = put(rdvBid(inv), sealed) }
                if (ok && stillOwn(key, stamp)) Prefs.setDbl(stamp, now())
                uploadFace(c, inv)
            } finally { synchronized(flying) { flying.remove(key) } }
        }.start()
    }
    private val flying = HashSet<String>()
    private fun stillOwn(inv64: String, stamp: String): Boolean = synchronized(lock) {
        if (stamp == "rdvPermUpAt") map(PERM).containsKey(inv64) else text(CURRENT) == inv64
    }
    private fun uploadPermMark(inv: ByteArray) {
        val sealed = seal(rdvKey(inv), PERM_MAGIC.toByteArray()) ?: return
        Thread { if (!put(permBid(inv), sealed)) { Thread.sleep(20_000); put(permBid(inv), sealed) } }.start()
    }
    /** THE FACE BESIDE THE CARD (iOS uploadFace): opening the link, the one who scans already sees the face. */
    private fun uploadFace(c: Context, inv: ByteArray) {
        val face = SelfFace.bytes(c) ?: ByteArray(0)
        val stamp = "rdvFaceUp:" + b64url(inv)
        val fp = hex(MessageDigest.getInstance("SHA-256").digest(face)).take(16)
        val last = Prefs.str(stamp, "").split(':')
        if (last.size == 2 && last[0] == fp && (last[1].toDoubleOrNull() ?: 0.0) > now() - 5 * 86400) return
        if (last.size != 2 && face.isEmpty()) return   // nothing lay beside the card, nothing to clear
        val sealed = seal(faceKey(inv), face) ?: return
        if (put(faceBid(inv), sealed)) Prefs.setStr(stamp, fp + ":" + now())
    }

    /** POST {bid, data, over} to the first door that takes it (iOS MontanaWakePush.putBlob). */
    private fun put(bid: String, data: ByteArray): Boolean {
        val body = JSONObject().put("bid", bid).put("data", Base64.encodeToString(data, Base64.NO_WRAP)).put("over", true)
            .toString().toByteArray(Charsets.UTF_8)
        for (door in doors) {
            try {
                val conn = URL("$door/blob-put").openConnection() as HttpURLConnection
                conn.requestMethod = "POST"; conn.doOutput = true
                conn.connectTimeout = 8000; conn.readTimeout = 15000
                conn.setRequestProperty("content-type", "application/json")
                conn.setFixedLengthStreamingMode(body.size)
                conn.outputStream.use { it.write(body) }
                val code = conn.responseCode
                conn.disconnect()
                if (code == 200) return true
            } catch (_: Exception) {}
        }
        return false
    }
}
