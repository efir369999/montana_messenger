package quest.montana.app

import android.util.Log
import org.json.JSONObject

/**
 * THE CLOCK GUARD OF THE FIRST FLOOR (iOS MTFloorGuard, MTPipeKey.swift; its state beside the book, MTPipeBook guardRead / heard /
 * floorDay / recoveryDay, MTPipe.swift; 67332869, Build 2313, decision 188, #38). The device's day alone decides the floor
 * (Wire.floored), and the floor is irreversible: a clock running ahead floors a book early, and it can no longer open what its peer
 * lays under the earlier days. The guard withholds the first floor, and only it, while the device day stands more than one day
 * ahead of every day a node's Date confirmed, for at most N days (the box's four); sources that disagree never withhold it, and a
 * hostile door can only raise M, which ends the wait -- the safe side. M, H and Hc are this seat's, sealed under the device key
 * beside the book (Book.wipe forgets them with it), never in the archive or a copy.
 */
object FloorGuard {
    private const val KEY = "pipeFloorGuard"
    /** N: the days a box read listens at (iOS MTNodeWire.boxDays(around: 2).count), four. */
    const val WIDTH = 4L

    /** M: the highest day a node's Date confirmed, only rising; H and Hc: the device day and the confirmed day the withholding began. */
    private class State(var mark: Long? = null, var since: Long? = null, var sinceConfirmed: Long? = null, var done: Boolean = false) {
        fun copy() = State(mark, since, sinceConfirmed, done)
        fun same(o: State) = mark == o.mark && since == o.since && sinceConfirmed == o.sinceConfirmed && done == o.done
        fun json(): JSONObject = JSONObject().apply {
            mark?.let { put("mark", it) }; since?.let { put("since", it) }; sinceConfirmed?.let { put("sinceConfirmed", it) }; put("done", done)
        }
    }
    private fun JSONObject.long(k: String): Long? = if (has(k)) optLong(k) else null

    sealed class Verdict {
        object Early : Verdict()                                        // before ERASE_DAY: nothing floors, H and Hc stay
        object Floor : Verdict()                                        // the floor applies on the device day (rules 2 and 4)
        object Free : Verdict()                                         // the floor applies and clears a withholding (rule 2)
        class Held(val since: Long, val left: Long) : Verdict()         // the first floor withheld (rule 3)
        class Ceiling(val since: Long, val byDevice: Boolean) : Verdict()   // the wait ended at its ceiling (rule 3)
    }

    private val lock = Any()
    private var state: State? = null
    private var heardDay: Long? = null      // the day of a node Date heard in this run (c of the run)
    private var heldTold: List<Long>? = null   // d, c, left of this run's last floor_held
    @Volatile private var floorDayNow = 0L     // the day the book last floored by

    /** The sealed record; null while it lies stored and does not open -- the guard then decides on a fresh state and writes nothing. */
    private fun read(): State? {
        synchronized(lock) { state?.let { return it } }
        val s = if (!DeviceVault.has(KEY)) State() else {
            val o = DeviceVault.get(KEY)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: return null
            State(o.long("mark"), o.long("since"), o.long("sinceConfirmed"), o.optBoolean("done"))
        }
        return synchronized(lock) { state ?: s.also { state = it } }
    }
    private fun write(s: State) { DeviceVault.set(KEY, s.json().toString().toByteArray()) }

    /** c: the higher of M and the day of a node Date heard in this run, never projected forward by the time since; null with neither. */
    private fun confirmed(s: State, heard: Long?): Long? = listOfNotNull(s.mark, heard).maxOrNull()

    /** The rule, asked wherever the book floors; `floored`: a pipe of the book is floored already. */
    private fun decide(s: State, d: Long, heard: Long?, floored: Boolean): Verdict {
        if (floored || s.done) return Verdict.Floor                      // rule 4: after the first floor the guard is never asked
        if (d < Wire.ERASE_DAY) return Verdict.Early                     // rule 1
        val c = confirmed(s, heard)
        if (c == null || d <= c + 1) {                                   // rule 2: no confirmed source, or the device day is not ahead
            val was = s.since != null
            s.since = null; s.sinceConfirmed = null; s.done = true
            return if (was) Verdict.Free else Verdict.Floor
        }
        if (s.since == null) { s.since = d; s.sinceConfirmed = c }       // rule 3: the first moment of the withholding
        val h = s.since ?: d; val hc = s.sinceConfirmed ?: c
        if (d >= h + WIDTH || c >= hc + WIDTH) {                         // the ceiling: whichever count ends first
            s.since = null; s.sinceConfirmed = null; s.done = true
            return Verdict.Ceiling(h, d >= h + WIDTH)
        }
        return Verdict.Held(h, minOf(h + WIDTH - d, hc + WIDTH - c))     // the nearer of the two ends
    }

    /** The trace, one format on every port: the days as plain integers, no names, no keys; floor_held once per run and on change. */
    private fun line(v: Verdict, d: Long, c: Long?): String? {
        val cs = c?.toString() ?: "none"
        val l = when (v) {
            Verdict.Early, Verdict.Floor -> null
            Verdict.Free -> "floor_free d=$d c=$cs"
            is Verdict.Held -> "floor_held d=$d c=$cs since=${v.since} left=${v.left}"
            is Verdict.Ceiling -> "floor_ceiling d=$d c=$cs since=${v.since} by=" + (if (v.byDevice) "device" else "confirmed")
        }
        if (v is Verdict.Held) {
            val now = listOf(d, c ?: 0L, v.left)
            if (heldTold == now) return null
            heldTold = now
        } else if (l != null) heldTold = null
        return l
    }

    /** A node's Date was heard (NodeClock.learn, iOS learnSkew): it is the confirmed day of this run, and M rises to it. */
    fun heard(serverMs: Long) {
        if (serverMs <= 0L) return
        val day = serverMs / 86_400_000
        val read = read()
        var rose = false
        val s = synchronized(lock) {
            heardDay = maxOf(heardDay ?: 0L, day)
            val g = state ?: read ?: State()
            if (day > (g.mark ?: 0L)) { g.mark = day; rose = true }
            if (read != null) state = g
            g.copy()
        }
        if (rose && read != null) write(s)
    }

    /**
     * The day a book about to be floored floors by: the device day, or the day before ERASE_DAY while the guard withholds the first
     * floor. A book with no pipe is not asked (H does not start on an empty book); `floored` is asked only when the rule needs it.
     */
    fun floorDay(nonEmpty: Boolean, floored: () -> Boolean): Long {
        val d = Wire.day()
        if (!nonEmpty || d < Wire.ERASE_DAY) { floorDayNow = d; return d }
        val read = read()
        var told: String? = null
        val (fd, changed) = synchronized(lock) {
            val g = state ?: read ?: State()
            if (g.done) { floorDayNow = d; return d }
            val before = g.copy()
            val v = decide(g, d, heardDay, floored())
            told = line(v, d, confirmed(g, heardDay))
            if (read != null) state = g
            val fd = if (v is Verdict.Held) Wire.ERASE_DAY - 1 else d
            floorDayNow = fd
            fd to (if (!g.same(before) && read != null) g.copy() else null)
        }
        changed?.let { write(it) }
        told?.let { Log.d("Montana", it) }
        return fd
    }

    /** The day the book last floored by; the device day before any book was read. */
    fun lastFloorDay(): Long = floorDayNow.takeIf { it != 0L } ?: Wire.day()

    /** The day a restore by the words floors the heads it reads by: the later of the device day and M (iOS recoveryDay, decision 188, E). */
    fun recoveryDay(): Long = maxOf(Wire.day(), read()?.mark ?: 0L)

    /** The seat leaves: the guard is the book's own and goes with it (iOS forgetAll, SeedScope.seatKeys «pipeFloorGuard»). */
    fun wipe() {
        synchronized(lock) { state = null; heldTold = null; heardDay = null; floorDayNow = 0L }
        DeviceVault.delete(KEY)
    }
}
