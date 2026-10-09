package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONObject

/**
 * THE NAMING LAYER ON THE PHONE (iOS MontanaNames, MontanaNames.swift at 2155): only calls into the core and the record a phone
 * must not lose. Every derivation — the normalization, the slot, the chain, the commitment — lives in mt-names and is not
 * rewritten here: one implementation per project, or a phone and a node resolve one written name to two slots on the very
 * first name.
 */
object Names {
    const val CHAIN_LENGTH = 128
    const val TAU2_WINDOWS = 20_160L
    const val RENEW_WINDOWS = 6 * TAU2_WINDOWS
    const val REVEAL_MAX_WINDOWS = 2 * TAU2_WINDOWS
    /** A renewal is due six weeks after the last one — half the keeper's term — or whenever less than τ₂ of it is left. */
    const val HALF_TERM_WINDOWS = 3 * TAU2_WINDOWS
    private const val WINDOW_SECONDS = 60L   // one window is a minute, as every tag of the pipes counts it (iOS MTPipe.windowSeconds)
    private const val VAULT = "mt.name"

    fun window(): Long = System.currentTimeMillis() / 1000 / WINDOW_SECONDS

    /** The normalized name, or null when it does not pass the rules of the layer. */
    fun normalize(raw: String): String? = MtBindings.nativeNameNormalize(raw)?.takeIf { it.isNotEmpty() }
    /** The slot of a name — of the normalized form ONLY: the core refuses what a person typed. */
    fun slot(normalized: String): ByteArray? = MtBindings.nativeNameSlot(normalized)
    /** The chain's far end: the seed's branch that TAKES THE SLOT, so two names of one holder yield two chains that never join. */
    fun nameOwn(master: ByteArray, slot: ByteArray): ByteArray? = MtBindings.nativeNameOwn(master, slot)
    /** The whole chain of renewals: link k at index k, link 0 the tip a commitment carries. */
    fun chain(own: ByteArray): List<ByteArray>? {
        val all = MtBindings.nativeNameChain(own) ?: return null
        if (all.size != (CHAIN_LENGTH + 1) * 32) return null
        return (0..CHAIN_LENGTH).map { all.copyOfRange(it * 32, (it + 1) * 32) }
    }
    fun commit(slot: ByteArray, blind: ByteArray, tip: ByteArray): ByteArray? = MtBindings.nativeNameCommit(slot, blind, tip)
    /** One renewal proves continuity by a single hash: the published link hashes once to the link published before it. */
    fun verifyLink(previous: ByteArray, link: ByteArray): Boolean = MtBindings.nativeNameVerifyLink(previous, link)

    /**
     * THE PAIR A NAME PUBLISHES (iOS MontanaFirstContact.contactPair): the secret half never leaves the phone, the slot carries
     * the encapsulation key alone. Derived per NAME, not per person — once per person would join two names of one holder.
     */
    fun contactPair(master: ByteArray, slot: ByteArray): Pair<ByteArray, ByteArray>? {
        val seed = MtBindings.nativeNameContactSeed(master, slot) ?: return null
        val kp = MtBindings.nativeMlkemKeypair(seed)
        seed.fill(0)
        if (kp == null || kp.size != 1184 + 2400) return null
        return kp.copyOfRange(0, 1184) to kp.copyOfRange(1184, kp.size)
    }
    /** Where a stranger knocks for a name in a window: the shape of any tag, a domain of its own (iOS knock). */
    fun knock(root: ByteArray, window: Long): ByteArray? = MtBindings.nativeFirstTag(root, window)

    /**
     * THE CANON'S OWN VALUES (iOS MontanaNames.agreesWithCanon and MontanaFirstContact.agreesWithCanon): a name taken under
     * derivations that differ by one byte is a name inside one implementation only — another phone computes another slot,
     * and the two never meet. Asked once a run; the diary says it (names_canon), and no name is taken while it is false.
     */
    val agreesWithCanon: Boolean by lazy {
        val ok = run {
            val sl = slot("alice") ?: return@run false
            if (Wire.hex(sl) != "b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e") return@run false
            val ch = chain(ByteArray(32) { 0xEE.toByte() }) ?: return@run false
            if (Wire.hex(ch[CHAIN_LENGTH - 1]) != "83be15d760052903e3b1a2d304f56861ad92b8fed97a0b08452c6eb029fe1b5a") return@run false
            if (Wire.hex(ch[0]) != "b49373b194e6358022b8fbcbecb5beccdd4f0b275d1ccd53be130f76a1367a8e") return@run false
            val cm = commit(sl, ByteArray(32) { 0xDD.toByte() }, ch[0]) ?: return@run false
            if (Wire.hex(cm) != "929fccf5c511d3d1123707db473cf21732a9349bcb578ddea91ca08b2d9dae41") return@run false
            // a knock computed differently lands where nobody listens, so it is proved here too
            val root = ByteArray(1184) { 0xCC.toByte() }
            Wire.hex(knock(root, 1000) ?: return@run false) == "45468cdd9bcdebe6f622c46257c27fe3" &&
                Wire.hex(knock(root, 1001) ?: return@run false) == "2751a149c51e219b73fadc85ca8b107b"
        }
        Log.d("Montana", "names_canon " + (if (ok) "ok" else "FAIL — derivations differ from the Canon, no name is taken"))
        ok
    }

    /** What is happening to the name right now — shown to a person in words, never as silence. */
    sealed class State {
        object None : State()                              // no name: the account answers by its reference alone
        class Committed(val revealBy: Long) : State()      // committed, awaiting its reveal before that window
        class Held(val renewBy: Long) : State()            // taken, renewed up to that window
        object Expired : State()                           // a term went by; the slot is free
    }

    private class Record(val name: String, val commitWindow: Long, var lastRenewWindow: Long, var step: Int, val nonce: ByteArray,
                         val commitment: ByteArray, var until: Double?)

    /** Sealed at rest: the blinding factor in the clear would join a slot to a commitment for anyone who reads the disk. */
    private fun load(): Record? {
        val o = DeviceVault.get(VAULT)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: return null
        val name = o.optString("name").takeIf { it.isNotEmpty() } ?: return null
        return Record(name, o.optLong("commitWindow"), o.optLong("lastRenewWindow"), o.optInt("step"),
            Base64.decode(o.optString("nonce"), Base64.NO_WRAP), Base64.decode(o.optString("commitment"), Base64.NO_WRAP),
            if (o.has("until")) o.optDouble("until") else null)
    }
    private fun save(r: Record) {
        val o = JSONObject().put("name", r.name).put("commitWindow", r.commitWindow).put("lastRenewWindow", r.lastRenewWindow)
            .put("step", r.step).put("nonce", Base64.encodeToString(r.nonce, Base64.NO_WRAP))
            .put("commitment", Base64.encodeToString(r.commitment, Base64.NO_WRAP))
        r.until?.let { o.put("until", it) }
        DeviceVault.set(VAULT, o.toString().toByteArray(Charsets.UTF_8))
    }

    /** The name this phone's record names — held or lapsed. What is shown, handed out and listened at is `heldName`. */
    val currentName: String? get() = load()?.name
    /** The index of the last link the keeper holds, and the keeper's term. */
    val heldStep: Int? get() = load()?.step
    val heldUntil: Double? get() = load()?.until

    fun state(now: Long = window()): State {
        val r = load() ?: return State.None
        r.until?.let { until ->
            val nowS = now.toDouble() * WINDOW_SECONDS
            return if (nowS < until) State.Held((until / WINDOW_SECONDS).toLong()) else State.Expired
        }
        if (r.lastRenewWindow > 0) {
            val due = r.lastRenewWindow + RENEW_WINDOWS
            return if (now > due) State.Expired else State.Held(due)
        }
        if (r.commitWindow > 0) {
            val due = r.commitWindow + REVEAL_MAX_WINDOWS
            return if (now > due) State.Expired else State.Committed(due)
        }
        return State.None
    }
    fun isHeld(now: Long = window()): Boolean = state(now) is State.Held
    /** The name this phone holds right now. A name whose term ran out is neither shown, nor handed out, nor listened at. */
    val heldName: String? get() = if (isHeld()) currentName else null

    /**
     * serialize(name_reveal) (Canon, «The three objects of a name»): the name's length, the name zero-padded to 32, the blinding
     * factor, the contact root — 1 249 bytes, the node parses these bytes.
     */
    fun reveal(name: String, blind: ByteArray, root: ByteArray): ByteArray? {
        val b = name.toByteArray(Charsets.UTF_8)
        if (b.size !in 4..32 || blind.size != 32 || root.size != 1184) return null
        return byteArrayOf(b.size.toByte()) + b + ByteArray(32 - b.size) + blind + root
    }

    class Prepared(val name: String, val slot: ByteArray, val chain: List<ByteArray>, val blind: ByteArray, val commitment: ByteArray,
                   val reveal: ByteArray)

    /**
     * TAKING A NAME, PREPARED (iOS prepare): normalize, slot, chain, a fresh blinding factor drawn by the core, the commitment and
     * the reveal. NOTHING is kept here: a name becomes this phone's only when the keeper answers that it is, so a refused taking
     * leaves whatever the phone held untouched. Refused outright while the core and the Canon disagree by a byte.
     */
    fun prepare(raw: String, master: ByteArray): Prepared? {
        if (!agreesWithCanon) return null
        val n = normalize(raw) ?: return null
        val sl = slot(n) ?: return null
        val own = nameOwn(master, sl) ?: return null
        val ch = chain(own)
        own.fill(0)
        ch ?: return null
        val root = contactPair(master, sl)?.first ?: return null
        val nonce = MtBindings.nativeRandom(32)?.takeIf { it.size == 32 } ?: return null
        val cm = commit(sl, nonce, ch[0]) ?: return null
        val r = reveal(n, nonce, root) ?: return null
        return Prepared(n, sl, ch, nonce, cm, r)
    }

    /** The keeper said the name is ours: held from this window, the chain spent up to `step` — the last link the keeper holds. */
    fun hold(p: Prepared, window: Long, step: Int, until: Double?) = save(Record(p.name, window, window, step, p.blind, p.commitment, until))

    /** The name went to somebody else while this phone thought it held it, or the person left: the record goes, and its pair. */
    fun forget() {
        held = null
        DeviceVault.delete(VAULT)
    }

    /** The record as the vault holds it, for a copy (iOS «mt.name», MontanaNames.swift 113-132: the same JSON on both phones). */
    fun record(): ByteArray? = DeviceVault.get(VAULT)
    /** A copy's record laid (iOS layCard 884-891: the copy's word); a record that names no name lays nothing. */
    fun lay(d: ByteArray) {
        if (runCatching { JSONObject(String(d, Charsets.UTF_8)).optString("name") }.getOrNull().isNullOrEmpty()) return
        held = null
        DeviceVault.set(VAULT, d)
    }

    /**
     * THE PAIR OF THE NAME THIS PHONE HOLDS (iOS contactPair at every listening and every accept): kept beside the name it was
     * drawn for, so a frame on a channel never draws ML-KEM again; a new name, a lapse or a forgetting lets it go.
     */
    @Volatile private var held: Triple<String, ByteArray, ByteArray>? = null
    fun heldPair(): Pair<ByteArray, ByteArray>? {
        val n = heldName ?: return null
        held?.takeIf { it.first == n }?.let { return it.second to it.third }
        val master = MontanaSeed.mnemonic?.let { MtBindings.nativeMnemonicToMasterSeed(it) } ?: return null
        val pair = slot(n)?.let { contactPair(master, it) }
        master.fill(0)
        pair ?: return null
        held = Triple(n, pair.first, pair.second)
        return pair
    }
    /** The root strangers encapsulate to — the point this phone listens at for its name (iOS listeningFirstContactPoints 585-588). */
    fun heldRoot(): ByteArray? = heldPair()?.first

    /**
     * THE HOLDER'S SIDE (iOS MontanaFirstContact.accept(firstLetter:masterSeed:confirmed:) 193-206): the first letter's ciphertext
     * decapsulated under the name's own key, the secret every later tag stands on. Decapsulation never refuses (implicit rejection,
     * FIPS 203), so the proof is the body's own seal under the secret it gives: the garbage of a foreign letter opens nothing.
     */
    fun acceptFirst(ct: ByteArray, proof: (ByteArray) -> Boolean): ByteArray? {
        val (root, sk) = heldPair() ?: return null
        val ss = MtBindings.nativeMlkemDecaps(sk, ct) ?: return null
        val secret = MtBindings.nativeFirstSecret(ss, root, ct)
        ss.fill(0)
        if (secret == null || !proof(secret)) { Log.d("Montana", "first_ghost card=name"); return null }
        return secret
    }

    // ── the names this phone met, each with the root it resolved to (iOS MTPipeBook.rememberName / contactRoot(forName:)) ──
    private const val BOOK = "mt.names.book"
    private fun book(): JSONObject = DeviceVault.get(BOOK)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONObject()
    fun rootFor(name: String): ByteArray? = book().optString(name).takeIf { it.isNotEmpty() }?.let { Base64.decode(it, Base64.NO_WRAP) }
    fun remember(name: String, root: ByteArray): Boolean = synchronized(this) {
        if (name.isEmpty() || root.size != 1184) return false
        DeviceVault.set(BOOK, book().put(name, Base64.encodeToString(root, Base64.NO_WRAP)).toString().toByteArray(Charsets.UTF_8))
    }
    fun wipeBook() = DeviceVault.delete(BOOK)

    /** The chain of the name this phone holds: where a keeper's «last link» is looked up. A link not in it is somebody else's. */
    fun heldChain(master: ByteArray): List<ByteArray>? {
        val r = load() ?: return null
        val sl = slot(r.name) ?: return null
        val own = nameOwn(master, sl) ?: return null
        return chain(own).also { own.fill(0) }
    }

    /**
     * The link the next renewal publishes, WITHOUT spending it: the step moves only when the keeper takes the link, so a renewal
     * lost on the way is published again rather than skipped — a skipped link would never hash to what the keeper holds.
     */
    fun nextRenewal(master: ByteArray): Pair<ByteArray, ByteArray>? {
        val r = load() ?: return null
        val sl = slot(r.name) ?: return null
        val ch = heldChain(master) ?: return null
        val next = r.step + 1
        if (next > CHAIN_LENGTH) return null   // the chain is spent and the slot is released
        if (!verifyLink(ch[next - 1], ch[next])) return null
        return sl to ch[next]
    }

    /** The keeper holds link `step` and said the term's end; `window` — the moment of a renewal taken NOW, null when only confirmed. */
    fun renewed(step: Int, window: Long?, until: Double?) {
        val r = load() ?: return
        r.step = step
        if (window != null) r.lastRenewWindow = window
        if (until != null) r.until = until
        save(r)
    }

    /** Due at the first return six weeks after the last renewal, or whenever less than τ₂ of the term is left. */
    fun renewalDue(now: Long = window()): Boolean {
        val r = load() ?: return false
        val s = state(now) as? State.Held ?: return false
        return now >= r.lastRenewWindow + HALF_TERM_WINDOWS || now + TAU2_WINDOWS >= s.renewBy
    }

    /** The key a stranger encapsulates to for the name this phone holds; derived per name, its secret half never leaves here. */
    fun contactRoot(master: ByteArray): ByteArray? {
        val n = heldName ?: return null
        val sl = slot(n) ?: return null
        return contactPair(master, sl)?.first
    }

    /** Where a stranger knocks for this phone's name in a window. */
    fun knockPoint(master: ByteArray, window: Long): ByteArray? = contactRoot(master)?.let { knock(it, window) }

    /** The name a person is shown: the sign stands ONLY before a name the network vouched for. */
    fun display(name: String, resolved: Boolean): String = if (resolved) "@" + name else name
}
