package quest.montana.app

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.view.View
import android.widget.PopupMenu
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

// ─────────────────────────── a letter sent later (iOS ScheduledMsg, schedule, fireDueScheduled) ───────────────────────────

/**
 * THE LETTERS WAITING FOR THEIR MOMENT (iOS ChatStore.scheduled): the chat, the words, the moment. Kept sealed in the device
 * vault; the app's own clock sends every one whose moment has come — while the app runs, and at its next start for the ones
 * whose moment passed while it slept (iOS fireDueScheduled: the clock of the running app).
 */
object Scheduled {
    private const val KEY = "scheduledLetters"
    private val lock = Any()
    private var running = false

    private fun all(): JSONArray = DeviceVault.get(KEY)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONArray()
    private fun save(a: JSONArray) = DeviceVault.set(KEY, a.toString().toByteArray(Charsets.UTF_8))
    /** The person forgotten: the letters they set for later never leave for anyone (Book.wipe). */
    fun wipe() = synchronized(lock) { DeviceVault.delete(KEY) }

    /**
     * The letters waiting, in the iPhone's form for a copy (iOS ScheduledMsg 31-37, saveScheduled 3237-3241): one name each, the chat,
     * the conversation, the words and the moment in seconds.
     */
    fun carried(): JSONArray = synchronized(lock) {
        val a = all()
        val out = JSONArray()
        for (i in 0 until a.length()) a.optJSONObject(i)?.let { o ->
            val ref = o.optString("ref")
            out.put(JSONObject().put("id", nameOf(o)).put("chat", o.optString("chat").ifEmpty { ref }).put("convRef", ref)
                .put("text", o.optString("t")).put("fireAt", o.optLong("at") / 1000.0))
        }
        out
    }
    /**
     * A copy laid (iOS SeedScope.unionKeys 6305, known by «id» 6318): a letter waiting here stays and the copy adds the others; a note to
     * oneself (no conversation) has no room here, and the card keeps it.
     */
    fun lay(a: JSONArray) {
        synchronized(lock) {
            val have = all()
            val known = HashSet<String>()
            for (i in 0 until have.length()) have.optJSONObject(i)?.let { known.add(nameOf(it)) }
            var added = 0
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val ref = if (o.isNull("convRef")) "" else o.optString("convRef")
                val id = o.optString("id")
                val at = o.optDouble("fireAt", Double.NaN)
                if (ref.isEmpty() || id.isEmpty() || at.isNaN() || !known.add(id)) continue
                have.put(JSONObject().put("ref", ref).put("t", o.optString("text")).put("at", (at * 1000).toLong()).put("id", id).put("chat", o.optString("chat")))
                added++
            }
            if (added > 0) save(have)
        }
    }
    /** A letter's one name: the iPhone's, or one drawn from what the letter is — the same on every copy (a name-based UUID, the iPhone's form). */
    private fun nameOf(o: JSONObject): String = o.optString("id").ifEmpty {
        java.util.UUID.nameUUIDFromBytes((o.optString("ref") + "\n" + o.optLong("at") + "\n" + o.optString("t")).toByteArray()).toString().uppercase()
    }

    fun add(ref: String, words: String, at: Long) = synchronized(lock) {
        save(all().put(JSONObject().put("ref", ref).put("t", words).put("at", at)))
    }

    /** Every letter whose moment has come leaves now, by the one road of a typed letter (iOS send). */
    fun fireDue() {
        val now = System.currentTimeMillis()
        val due = mutableListOf<JSONObject>()
        synchronized(lock) {
            val a = all(); val keep = JSONArray()
            for (i in 0 until a.length()) a.getJSONObject(i).let { if (it.optLong("at") <= now) due += it else keep.put(it) }
            if (due.isNotEmpty()) save(keep)
        }
        due.forEach { o ->
            val ref = o.getString("ref"); val words = o.getString("t")
            if (Book.chat(ref) == null) return@forEach   // the chat is gone: nobody to send to
            if (Groups.isKey(ref)) { Groups.send(ref, words, null, null); return@forEach }   // a group's letter rides the group's carrier
            val mid = Marks.mintMid()
            Book.edit(ref) { it.msgs.add(Msg(mid, words, true, Marks.birthMs(mid) ?: now)) }
            Post.send(ref, mid, words)
            LinkPreview.attend(ref, mid, words, null, null)
        }
    }

    /** The app's clock: once now, then every half minute while the process lives. */
    fun run() {
        if (running) return
        running = true
        val tick = object : Runnable {
            override fun run() { Thread { fireDue() }.start(); MainThread.later(30_000, this) }
        }
        MainThread.post { tick.run() }
    }
}

/**
 * «SEND LATER» (iOS: a hold on the send key opens the platform's menu; its one row opens the moment's picker): the system's
 * own date and time pickers, a moment in the future only; the words leave the field and wait for it.
 */
fun sendLaterMenu(act: MainActivity, anchor: View, ref: String, words: () -> String, onScheduled: () -> Unit) {
    PopupMenu(act, anchor).apply {
        menu.add(act.getString(R.string.sl_later))
        setOnMenuItemClickListener {
            val text = words().trim()
            if (text.isNotEmpty()) pickMoment(act) { at -> Scheduled.add(ref, text, at); onScheduled() }
            true
        }
    }.show()
}

private fun pickMoment(act: MainActivity, done: (Long) -> Unit) {
    val cal = Calendar.getInstance().apply { add(Calendar.MINUTE, 10) }
    DatePickerDialog(act, { _, y, mo, d ->
        TimePickerDialog(act, { _, h, mi ->
            val at = Calendar.getInstance().apply { set(y, mo, d, h, mi, 0) }.timeInMillis
            if (at > System.currentTimeMillis()) done(at)
        }, cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE), android.text.format.DateFormat.is24HourFormat(act)).show()
    }, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)).apply {
        datePicker.minDate = System.currentTimeMillis() - 1000
    }.show()
}
