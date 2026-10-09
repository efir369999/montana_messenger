package quest.montana.app

import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * RESOLVING A NAME INTO THE ABILITY TO REACH ITS HOLDER, AND TAKING ONE (iOS MontanaNamePlane, MontanaFirstContact.swift 271-583 at
 * 2155). The set puts one value at the slot of a claimed name — the contact root — and gives the ORDER of a slot to the chain. Until
 * the chain carries names, the nodes carry the Canon's reveal and ONE node keeps the order (a door's «name» capability). The keeper
 * hands out no link of anybody's chain; the phone proves a name its own by reading the reveal under it and finding its own key there.
 */
object NamePlane {
    sealed class Answer {
        class Found(val root: ByteArray) : Answer()
        object Unknown : Answer()        // the keeper said that nobody holds it
        object Unreachable : Answer()    // no door answered, or a door's memory disputes the keeper
    }
    sealed class Taking {
        class Taken(val name: String) : Taking()   // the keeper recorded it as this phone's
        object Held : Taking()                     // somebody else holds it
        object Full : Taking()                     // the keeper's quota is spent
        object Busy : Taking()                     // the keeper asked to wait
        object Unreachable : Taking()
        object Refused : Taking()                  // not a lawful name, or no seed to take it with
    }
    private const val TIMEOUT = 5000   // iOS MTNodeWire.postTimeoutS

    /** The name changed (taken, lost, released): the pages that show it redraw (iOS .montanaNameChanged). */
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) = synchronized(listeners) { listeners.add(l) }
    fun unlisten(l: () -> Unit) = synchronized(listeners) { listeners.remove(l) }
    private fun changed() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }
    /** What the person is told when the name is not theirs any more — never a silent disappearance (iOS lost's verdict). */
    @Volatile var lostWord: String? = null

    private fun master(): ByteArray? = MontanaSeed.mnemonic?.let { MtBindings.nativeMnemonicToMasterSeed(it) }

    /** The doors that carry the plane of names — by their own word, in the network's order, the elected first. */
    private fun doors(): List<String> = Doors.ordered("name")

    /** One question to one door. The code is knowledge in itself — 409 is «held», 404 «nobody», 507 «full» — so it comes back whole. */
    private fun ask(door: String, path: String, body: JSONObject): Pair<Int, JSONObject> {
        val (code, text) = Wire.post(door, path, body, TIMEOUT, whole = true)
        if (code == -1) Log.d("Montana", "name_ask " + path + " unreachable at=" + (android.net.Uri.parse(door).host ?: "-"))
        return code to (text?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject())
    }

    /** A 404 is «nobody holds it» ONLY in the keeper's own words: a door that carries no names answers 404 too. */
    private fun nobody(code: Int, obj: JSONObject) = code == 404 && obj.optString("error") == "no such name"

    /** ONE DOOR AT A TIME (the critic's P10): the elected door first, the next only when a door is silent, fails, or carries no names. */
    private fun askFirst(path: String, body: JSONObject): Pair<Int, JSONObject> {
        var last = -1 to JSONObject()
        for (d in doors()) {
            val a = ask(d, path, body)
            if (a.first in setOf(200, 400, 409, 429, 507) || nobody(a.first, a.second)) return a
            last = a
        }
        return last
    }

    /** The contact root inside the Canon's reveal of `name`, or null when the bytes are not that (a reveal of another name is refused). */
    fun rootInReveal(d: ByteArray, name: String): ByteArray? {
        if (d.size != 1249) return null
        val n = d[0].toInt() and 0xff
        if (n !in 4..32) return null
        if (!d.copyOfRange(1, 1 + n).contentEquals(name.toByteArray(Charsets.UTF_8))) return null
        if ((1 + n until 33).any { d[it] != 0.toByte() }) return null
        return d.copyOfRange(65, 1249)
    }
    private fun reveal(obj: JSONObject): ByteArray? =
        obj.optString("reveal").takeIf { it.isNotEmpty() }?.let { runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull() }

    /** Another's name, asked of every door: a door's memory («stale») stands only while no door says «nobody» (the critic's P12). */
    fun resolve(raw: String): Answer {
        val n = Names.normalize(raw) ?: return Answer.Unknown
        val sl = Names.slot(n) ?: return Answer.Unknown
        val all = doors()
        if (all.isEmpty()) return fallback(n, "no door carries names")
        var remembered: ByteArray? = null
        for (d in all) {
            val (code, obj) = ask(d, "/name-get", JSONObject().put("slot", Wire.hex(sl)))
            val r = if (code == 200) reveal(obj)?.let { rootInReveal(it, n) } else null
            if (r != null) {
                if (obj.optBoolean("stale")) { if (remembered == null) remembered = r; continue }
                Names.remember(n, r)
                Log.d("Montana", "name_resolve found")
                return Answer.Found(r)
            }
            if (nobody(code, obj)) {
                if (remembered != null) { Log.d("Montana", "name_resolve DISPUTED — a door's memory against the keeper's «nobody»"); return Answer.Unreachable }
                Log.d("Montana", "name_resolve nobody holds it")
                return Answer.Unknown
            }
        }
        remembered?.let { Log.d("Montana", "name_resolve from a door's memory — the keeper is silent"); return Answer.Found(it) }
        return fallback(n, "no door answered")
    }
    /** The doors are silent: the root this phone heard last — ONLY for a name already met here, and named in the diary. */
    private fun fallback(n: String, why: String): Answer {
        val r = Names.rootFor(n)
        if (r != null && Meeting.metAtRoot(r)) { Log.d("Montana", "name_resolve from memory, a name met before — " + why); return Answer.Found(r) }
        Log.d("Montana", "name_resolve unreachable — " + why)
        return Answer.Unreachable
    }

    /** Whether the reveal under a name carries this phone's own key — the one proof a phone has that a name is its own. Null: no answer. */
    private fun ownsSlot(name: String, master: ByteArray): Boolean? {
        val sl = Names.slot(name) ?: return null
        val mine = Names.contactPair(master, sl)?.first ?: return null
        val (code, obj) = askFirst("/name-get", JSONObject().put("slot", Wire.hex(sl)))
        if (code == 200 && !obj.optBoolean("stale")) reveal(obj)?.let { return rootInReveal(it, name)?.contentEquals(mine) == true }
        if (nobody(code, obj)) return false
        return null
    }

    private sealed class Probe {
        class Taken(val step: Int, val until: Double?) : Probe()
        class Ours(val step: Int) : Probe()
        object Held : Probe(); object Full : Probe(); object Busy : Probe(); object Unreachable : Probe(); object Exhausted : Probe()
    }
    private fun until(obj: JSONObject): Double? = if (obj.has("until") && !obj.isNull("until")) obj.optDouble("until") else null

    /**
     * Taking a slot with the first link of this phone's chain the keeper has not seen: an earlier holding of the same seed may have
     * published links, the keeper answers «spent» for those, and the probe doubles (1, 2, 4, …).
     */
    private fun probe(p: Names.Prepared, start: Int, master: ByteArray): Probe {
        var k = maxOf(0, start)
        while (k <= Names.CHAIN_LENGTH) {
            val (code, obj) = askFirst("/name-take", JSONObject().put("reveal", Base64.encodeToString(p.reveal, Base64.NO_WRAP)).put("last", Wire.hex(p.chain[k])))
            when {
                code == 200 -> return Probe.Taken(k, until(obj))
                code == 409 && obj.optBoolean("spent") -> k = if (k == 0) 1 else k * 2
                code == 409 -> return when (ownsSlot(p.name, master)) { true -> Probe.Ours(k); false -> Probe.Held; null -> Probe.Unreachable }
                code == 507 -> return Probe.Full
                code == 429 -> return Probe.Busy
                else -> return Probe.Unreachable
            }
        }
        Log.d("Montana", "name_take every probed link is spent")
        return Probe.Exhausted
    }

    /**
     * TAKING A NAME AT THE KEEPER (iOS take 438-462): the phone holds it only once the keeper says so — or once the reveal under the name
     * proves to carry this phone's own key; a new name releases the one held before it, and the release is final.
     */
    fun take(raw: String): Taking {
        val master = master() ?: return Taking.Refused
        try {
            val p = Names.prepare(raw, master) ?: return Taking.Refused
            val recorded = Names.currentName
            val former = if (recorded != null && recorded != p.name && Names.isHeld()) Names.nextRenewal(master) else null
            val start = if (recorded == p.name) (Names.heldStep ?: -1) + 1 else 0
            val window = Names.window()
            return when (val pr = probe(p, start, master)) {
                is Probe.Taken -> {
                    Names.hold(p, window, pr.step, pr.until)
                    former?.let { release(it.first, it.second) }
                    settle(p.name, master, "taken at step " + pr.step)
                }
                is Probe.Ours -> {
                    // our own reveal stands under the name (an answer lost, another phone of this seed): a renewal reads the term back
                    Names.hold(p, window, pr.step, null)
                    former?.let { release(it.first, it.second) }
                    renew(master)
                    settle(p.name, master, "ours again")
                }
                Probe.Held -> Taking.Held
                Probe.Full -> Taking.Full
                Probe.Busy -> Taking.Busy
                Probe.Unreachable, Probe.Exhausted -> Taking.Unreachable
            }
        } finally { master.fill(0) }
    }

    private fun settle(n: String, master: ByteArray, trace: String): Taking {
        Names.contactRoot(master)?.let { Names.remember(n, it) }
        Channels.dropFirstPoints()   // the phone listens at the point of the new name from this window
        Log.d("Montana", "name_take " + trace)
        changed()
        return Taking.Taken(n)
    }

    // ONE RENEWAL AT A TIME (the critic's P3): every return used to start its own, and links were published twice
    private val renewing = AtomicBoolean(false)

    /** Extends the term with the next link; the step moves only when the keeper takes it, and the reveal is read after every renewal. */
    fun renew(master: ByteArray) {
        if (!renewing.compareAndSet(false, true)) { Log.d("Montana", "name_renew one renewal is already on its way"); return }
        try { renewOnce(master, again = true) } finally { renewing.set(false) }
    }

    private fun renewOnce(master: ByteArray, again: Boolean) {
        val n = Names.currentName ?: return
        val step = Names.heldStep ?: return
        val ch = Names.heldChain(master) ?: return
        val sl = Names.slot(n) ?: return
        val next = step + 1
        if (next > Names.CHAIN_LENGTH) { Log.d("Montana", "name_renew the chain is spent"); return }
        val window = Names.window()
        val (code, obj) = askFirst("/name-renew", JSONObject().put("slot", Wire.hex(sl)).put("link", Wire.hex(ch[next])))
        when {
            code == 200 && obj.optBoolean("again") -> {
                // the keeper already held that link: the answer to its publishing was lost; the due renewal is the link after it, once
                Names.renewed(next, null, until(obj))
                Log.d("Montana", "name_renew again at step " + next)
                if (again) renewOnce(master, again = false)
            }
            code == 200 -> {
                Names.renewed(next, window, until(obj))
                Log.d("Montana", "name_renew ok step=" + next)
                if (ownsSlot(n, master) == false) lost("another key stands under the name")
            }
            code == 409 -> when (ownsSlot(n, master)) {
                true -> walk(next + 1, ch, sl)
                false -> lost("another chain holds the slot")
                null -> Log.d("Montana", "name_renew 409 and the reveal did not come — asked again at the next return")
            }
            nobody(code, obj) -> {
                // the keeper holds no such name: the term lapsed unseen — taken again from the first link this phone has not published
                val p = Names.prepare(n, master) ?: return
                when (val pr = probe(p, next, master)) {
                    is Probe.Taken -> { Names.hold(p, window, pr.step, pr.until); Log.d("Montana", "name_renew taken again at step " + pr.step) }
                    is Probe.Ours -> Names.hold(p, window, pr.step, null)
                    Probe.Held -> lost("taken by another after a lapse")
                    else -> Log.d("Montana", "name_renew the retaking did not go through — asked again at the next return")
                }
            }
            else -> Log.d("Montana", "name_renew code=" + code + " — asked again at the next return")
        }
    }

    /** The phone stands behind the keeper on its own chain (a copy restored, answers lost): it walks forward, at most sixteen links. */
    private fun walk(start: Int, ch: List<ByteArray>, sl: ByteArray) {
        val window = Names.window()
        var k = start
        while (k <= minOf(start + 15, Names.CHAIN_LENGTH)) {
            val (code, obj) = askFirst("/name-renew", JSONObject().put("slot", Wire.hex(sl)).put("link", Wire.hex(ch[k])))
            if (code == 200) {
                val again = obj.optBoolean("again")
                Names.renewed(k, if (again) null else window, until(obj))
                if (again && k + 1 <= Names.CHAIN_LENGTH) {
                    val (c2, o2) = askFirst("/name-renew", JSONObject().put("slot", Wire.hex(sl)).put("link", Wire.hex(ch[k + 1])))
                    if (c2 == 200) Names.renewed(k + 1, window, until(o2))
                }
                Log.d("Montana", "name_renew caught up at step " + k)
                return
            }
            if (code != 409) { Log.d("Montana", "name_renew the walk stopped code=" + code); return }
            k++
        }
        lost("the keeper holds a chain this phone does not continue")
    }

    /** The name is not this phone's any more: the record goes, the phone stops listening at its point, and the person is told. */
    private fun lost(why: String) {
        Names.forget()
        Log.d("Montana", "name_lost " + why)
        Channels.dropFirstPoints()
        lostWord = Book.ctx.getString(R.string.name_lost)
        changed()
        // never a silent disappearance (iOS montanaMeetVerdict): the person is told by the platform's own word
        MainThread.post { android.widget.Toast.makeText(Book.ctx, Book.ctx.getString(R.string.name_lost), android.widget.Toast.LENGTH_LONG).show() }
    }

    /** The name held before a new one: released with a link nobody has seen; a keeper out of reach leaves it to lapse by its term. */
    private fun release(slot: ByteArray, link: ByteArray) {
        val (code, obj) = askFirst("/name-drop", JSONObject().put("slot", Wire.hex(slot)).put("link", Wire.hex(link)))
        Log.d("Montana", "name_release " + when {
            code == 200 -> "released"
            nobody(code, obj) -> "the keeper held nothing — it had lapsed"
            else -> "code=" + code + " — the former name lapses by its term"
        })
    }

    /**
     * EVERYTHING A NAME REQUIRES OF A PHONE WHEN THE PERSON RETURNS (iOS MontanaNames.keepInStep 284-292): the term extended at the
     * keeper when it has come due — and ONLY then, a question at every return would tell the keeper when the holder is present —,
     * our own pair of the name in the book, and the phone standing at the point strangers knock at in this window.
     */
    fun keepInStep() {
        val n = Names.heldName ?: return
        val master = master() ?: return
        try {
            if (Names.renewalDue()) renew(master)
            Names.contactRoot(master)?.let { Names.remember(n, it) }
            Names.heldRoot()?.let { r -> Names.knock(r, Names.window())?.let { Log.d("Montana", "knock_listen point=" + Wire.hex(it).take(8) + " window=" + Names.window()) } }
        } finally { master.fill(0) }
    }
}
