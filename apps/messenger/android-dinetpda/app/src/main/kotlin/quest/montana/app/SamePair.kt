package quest.montana.app

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/**
 * ONE PERSON, ONE CONVERSATION (iOS MTSamePair, 24.09). Pipes cannot be linked to a person by design, so a new meeting with
 * someone already met gave birth to a second conversation beside the first. The fold is decided by the two phones alone:
 * right after a meeting the one who met asks over the NEW pipe — its freshest pipes, each tagged against the new secret,
 * filled with noise to one fixed count — and the other answers in one shape for «yes» and «no»: a proof only a holder of
 * both secrets can make, or a tag nobody can check. Both ends fold the asked pipe into the older one; a folded pipe
 * forwards into its conversation for as long as it lives.
 */
object SamePair {
    private const val SLOTS = 32
    private const val ASK_LIFE_MS = 3_600_000L
    private const val MERGED = "sameMerged"   // folded pipe → the conversation it speaks for (iOS mergedKey)
    private val lock = Any()
    private val asked = HashMap<String, Pair<Long, Set<String>>>()   // my questions still unanswered, and the pipes each named
    private val reminded = HashMap<String, Long>()
    private var kept: MutableMap<String, String>? = null

    /** The words that speak of the pipe they came by, never of a conversation: a folded pipe reads them itself. */
    fun speaksOfPipe(t: String) = t.startsWith(Marks.SAME_ASK) || t.startsWith(Marks.SAME_YES)

    private fun d(domain: String) = domain.toByteArray() + byteArrayOf(0)
    private fun tag(domain: String, older: ByteArray, newer: ByteArray) = Wire.hex(Wire.sha(d(domain), older, newer).copyOf(16))
    private fun noise() = Wire.hex(MtBindings.nativeRandom(16) ?: ByteArray(16))
    /** A pipe's place in the one order both ends compute alike — the tie between two pipes born at one meeting. */
    private fun rank(secret: ByteArray) = Wire.sha(d("mt-same-rank"), secret)
    private fun precedes(a: ByteArray, b: ByteArray): Boolean {
        for (i in 0 until minOf(a.size, b.size)) {
            val x = a[i].toInt() and 0xff; val y = b[i].toInt() and 0xff
            if (x != y) return x < y
        }
        return a.size < b.size
    }
    /** Pipes by freshness: the living first, the mute to the tail (iOS MTPipeBook.allByFreshness). */
    private fun byFreshness(): List<String> = Book.refs().sortedWith(compareByDescending<String> { Book.chat(it)?.last?.at ?: 0L }.thenByDescending { it })

    private fun waiting(conv: String): Set<String>? = synchronized(lock) {
        val q = asked[conv] ?: return null
        if (System.currentTimeMillis() - q.first < ASK_LIFE_MS) q.second else null
    }
    fun settle(conv: String) = synchronized(lock) { asked.remove(conv); Unit }

    /** The question: the silent first letter of a pipe just born at a meeting, carrying the pipe's ciphertext. */
    fun ask(conv: String) {
        val sn = Book.secret(conv) ?: return
        val named = byFreshness().filter { it != conv }.take(SLOTS)
        val tags = named.mapNotNull { q -> Book.secret(q)?.let { tag("mt-same-ask", it, sn) } }.toMutableList()
        while (tags.size < SLOTS) tags.add(noise())
        tags.shuffle()
        val payload = Base64.encodeToString(JSONObject().put("t", JSONArray(tags)).toString().toByteArray(), Base64.NO_WRAP)
        synchronized(lock) { asked[conv] = System.currentTimeMillis() to named.toSet() }
        Prefs.setBool("sameAsked.$conv", true)
        Post.send(conv, "same-" + java.util.UUID.randomUUID().toString().uppercase(), Marks.SAME_ASK + payload)
    }

    private fun decode(payload: String, key: String): JSONObject? =
        runCatching { JSONObject(String(Base64.decode(payload, Base64.DEFAULT), Charsets.UTF_8)).takeIf { it.has(key) } }.getOrNull()

    /** The answering side's choice: the pipe it shares with the one who asked, or none. */
    fun shared(payload: String, conv: String): String? {
        val sn = Book.secret(conv) ?: return null
        val t = decode(payload, "t")?.optJSONArray("t") ?: return null
        val heard = (0 until minOf(t.length(), SLOTS)).map { t.optString(it) }.toSet()
        val matches = byFreshness().filter { q -> q != conv && Book.secret(q)?.let { heard.contains(tag("mt-same-ask", it, sn)) } == true }
        matches.firstOrNull { waiting(it) == null }?.let { return it }
        matches.firstOrNull { waiting(it)?.contains(conv) != true }?.let { return it }
        val mine = rank(sn)
        return matches.firstOrNull { q -> Book.secret(q)?.let { precedes(rank(it), mine) } == true }
    }

    /** The answer, one shape for «yes» and «no»: the proof over the chosen pipe, or a tag nobody can check. */
    fun answer(older: String?, conv: String) {
        val sn = Book.secret(conv) ?: return
        val p = older?.let { Book.secret(it) }?.let { tag("mt-same-yes", it, sn) } ?: noise()
        val payload = Base64.encodeToString(JSONObject().put("p", p).toString().toByteArray(), Base64.NO_WRAP)
        Post.send(conv, "same-" + java.util.UUID.randomUUID().toString().uppercase(), Marks.SAME_YES + payload)
    }

    /** The asker's reading of the answer: the pipe the other side proved, or none. */
    fun proven(payload: String, conv: String): String? {
        val sn = Book.secret(conv) ?: return null
        val p = decode(payload, "p")?.optString("p") ?: return null
        return Book.refs().firstOrNull { q -> q != conv && Book.secret(q)?.let { tag("mt-same-yes", it, sn) == p } == true }
    }

    /** They wrote into a pipe folded here: the answer may have been lost on the way, so it is said again, once an hour at most. */
    fun remind(folded: String) {
        val now = System.currentTimeMillis()
        val due = synchronized(lock) { (now - (reminded[folded] ?: 0L) > ASK_LIFE_MS).also { if (it) reminded[folded] = now } }
        if (due) answer(merged(folded), folded)
    }

    /**
     * Pipes this phone met by a scan and never asked about — the meetings made before this build knew to ask
     * (the twin chat of 30.09): asked once, so a pair already doubled folds too.
     */
    fun askUnasked() {
        for (ref in Meeting.metByScan()) if (merged(ref) == null && Book.secret(ref) != null && !Prefs.bool("sameAsked.$ref", false)) ask(ref)
    }

    // ── a folded pipe forwards into its conversation until it dies ──
    private fun book(): MutableMap<String, String> = synchronized(lock) {
        kept ?: (DeviceVault.get(MERGED)?.let { raw ->
            runCatching { JSONObject(String(raw, Charsets.UTF_8)).let { o -> o.keys().asSequence().associateWith { o.getString(it) } } }.getOrNull()
        }?.toMutableMap() ?: mutableMapOf()).also { kept = it }
    }
    private fun store(m: Map<String, String>) { DeviceVault.set(MERGED, JSONObject(m).toString().toByteArray()) }

    fun merged(conv: String): String? = synchronized(lock) { book()[conv] }
    /** The conversation a pipe speaks for: itself, or the one it was folded into. */
    fun root(conv: String): String = synchronized(lock) {
        val b = book(); var c = conv
        repeat(8) { val n = b[c]; if (n == null || n == c) return c; c = n }
        c
    }
    /** Every pipe folded into this conversation. */
    fun folded(into: String): List<String> = synchronized(lock) { book().keys.filter { it != into && root(it) == into } }
    fun noteMerged(newer: String, older: String) = synchronized(lock) {
        val m = book(); m[newer] = older
        m.keys.retainAll { Book.secret(it) != null }   // a folded pipe that died forwards nothing more
        store(m)
    }
    fun drop(refs: Collection<String>) = synchronized(lock) {
        val m = book(); if (m.keys.removeAll(refs.toSet()) or m.values.removeAll(refs.toSet())) store(m)
    }
    fun wipe() = synchronized(lock) { kept = null; asked.clear(); DeviceVault.delete(MERGED) }
}
