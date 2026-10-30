package quest.montana.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.TextWatcher
import android.text.format.DateUtils
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import android.util.Log

// ─────────────────────────── the local room (iOS savedMessagesKey, ChatStore.isLocalRoom) ───────────────────────────

/**
 * SAVED MESSAGES: the room without an address — one's letters to oneself. No wire: a letter is settled the moment it is
 * written (iOS: «no wire: settled, never red»). The letters lie on the device, in the app's own files.
 */
object SavedMessages {
    /** iOS savedMessagesKey: the room's key, English and never translated -- its archive folder is this key's own (iOS isLocalRoom). */
    const val KEY = "Saved Messages"

    class Letter(val id: String, val text: String, val at: Long)

    private fun file(ctx: Context) = File(ctx.filesDir, "saved_messages.json")
    private val lock = Any()

    fun all(ctx: Context): List<Letter> = synchronized(lock) { read(ctx) }

    /** AN UNREADABLE LIST IS NOT AN EMPTY ONE (the owner's word 24.10.2026: no loss): a file that does not parse is set aside under a
     *  name of its own and kept, never taken for an empty room the next letter would write over. */
    private fun read(ctx: Context): List<Letter> {
        val f = file(ctx)
        if (!f.exists()) return emptyList()
        return try {
            val a = JSONArray(f.readText())
            (0 until a.length()).map { a.getJSONObject(it).let { o -> Letter(o.getString("id"), o.getString("text"), o.getLong("at")) } }
        } catch (e: Exception) {
            val aside = File(ctx.filesDir, "saved_messages.unreadable-" + System.currentTimeMillis() + ".json")
            Log.w("Montana", "saved_unreadable kept=" + f.renameTo(aside))
            emptyList()
        }
    }

    /** A letter's name as iOS keeps a Saved Messages row (MontanaChatStore mintMid): mid:t<birth ms>-<ID>, the id upper-cased --
     *  the moment and Android's own id both kept, the id given back by lower-casing it. */
    fun mid(l: Letter) = "mid:t" + l.at + "-" + l.id.uppercase(Locale.ROOT)
    private fun sig(atMs: Long, text: String) = (atMs / 1000).toString() + "|" + text

    // THE ROOM RIDES THE ARCHIVE TO THE PERSON'S OTHER DEVICES (iOS: Saved Messages travels as its folder's blocks alone, the head
    // «a:Saved Messages»): every letter written here is sealed into that folder; a letter its own device wrote is named in
    // «saved.archived», so the carrying of the older ones is done once and never twice.
    private const val ARCHIVED = "saved.archived"
    private const val GONE = "saved.gone"
    private const val MIGRATED = "migrated.savedMessages"
    private fun names(key: String): MutableSet<String> = runCatching {
        val a = JSONArray(Prefs.str(key, "[]")); (0 until a.length()).mapTo(LinkedHashSet()) { a.getString(it) }
    }.getOrElse { LinkedHashSet() }
    private fun keepNames(key: String, s: Set<String>) = Prefs.setStr(key, JSONArray(s.toList().takeLast(4000)).toString())
    private fun toArchive(l: Letter) = Archive.row(KEY, Msg(mid(l), l.text, true, l.at, state = 1))

    private fun write(ctx: Context, list: List<Letter>) {
        val a = JSONArray()
        list.forEach { a.put(JSONObject().put("id", it.id).put("text", it.text).put("at", it.at)) }
        // written beside and moved over, so a letter is never half on the disk
        val tmp = File(ctx.filesDir, "saved_messages.json.tmp")
        tmp.writeText(a.toString())
        tmp.renameTo(file(ctx))
    }

    fun add(ctx: Context, text: String): Letter {
        val l = Letter(java.util.UUID.randomUUID().toString(), text, System.currentTimeMillis())
        synchronized(lock) {
            write(ctx, read(ctx) + l)
            toArchive(l)
            keepNames(ARCHIVED, names(ARCHIVED).apply { add(l.id) })
        }
        return l
    }

    /** A letter taken away here stays away (iOS: Saved Messages' deletion is local, the archive only grows): its second and words are
     *  kept, so the blocks of another device never lay it back. */
    fun delete(ctx: Context, id: String) = synchronized(lock) {
        val all = read(ctx)
        all.firstOrNull { it.id == id }?.let { l -> keepNames(GONE, names(GONE).apply { add(sig(l.at, l.text)) }) }
        write(ctx, all.filter { it.id != id })
    }

    /** THE BLOCKS OF THE PERSON'S OTHER DEVICES (Archive.restore over the folder «Saved Messages»): every letter of theirs this room does
     *  not hold by its second and its words, and that was not taken away here, stands -- named by its own signature, so the same
     *  block read twice lays nothing twice. A file's row waits: this room holds words alone. The letters laid. */
    fun takeFromArchive(ctx: Context, items: List<Pair<Long, String>>): Int = synchronized(lock) {
        val have = read(ctx)
        val held = have.mapTo(HashSet()) { sig(it.at, it.text) }
        val gone = names(GONE)
        val fresh = items.filter { (sec, t) -> !t.startsWith(Marks.MEDIA) && t.isNotEmpty() }
            .map { (sec, t) -> sec * 1000 to t }
            .filter { (ms, t) -> held.add(sig(ms, t)) && sig(ms, t) !in gone }
            .map { (ms, t) -> Letter(java.util.UUID.nameUUIDFromBytes(("mt-saved|" + sig(ms, t)).toByteArray()).toString(), t, ms) }
        if (fresh.isNotEmpty()) {
            write(ctx, (have + fresh).sortedBy { it.at })
            keepNames(ARCHIVED, names(ARCHIVED).apply { fresh.forEach { add(it.id) } })   // they came from the archive: carried already
        }
        fresh.size
    }

    /**
     * THE LETTERS WRITTEN BEFORE THE ROOM RODE THE ARCHIVE (the owner's word 24.10.2026: a backup first, then the carrying, then the
     * count): once, at the launch, the file is copied whole into noBackupFilesDir/migrate with its manifest -- the sha-256 of the
     * file, the count, every id, every letter's moment and the sha-256 of its words -- and the copy read back; only then each letter
     * not carried yet is sealed into the folder. The original stays where it lies. The check that every letter stands in the
     * folder runs after the archive's queue (Archive.savedCheck); until it holds, the carrying is not marked done, and a letter
     * carried twice is read once (the archive's readers keep one row a signature).
     */
    fun migrate(ctx: Context) {
        if (Prefs.bool(MIGRATED, false)) return
        val list = all(ctx)
        if (list.isEmpty()) { Prefs.setBool(MIGRATED, true); return }
        val f = file(ctx)
        val raw = runCatching { f.readBytes() }.getOrNull() ?: return
        val dir = File(ctx.noBackupFilesDir, "migrate").apply { mkdirs() }
        val stamp = System.currentTimeMillis()
        val copy = File(dir, "saved_messages-$stamp.json")
        fun sha(b: ByteArray) = Wire.hex(Wire.sha(b))
        copy.writeBytes(raw)
        if (sha(copy.readBytes()) != sha(raw)) { Log.w("Montana", "saved_migrate backup unequal -- nothing carried"); return }
        val manifest = JSONObject().put("sha256", sha(raw)).put("count", list.size)
            .put("ids", JSONArray(list.map { it.id }))
            .put("letters", JSONArray(list.map { JSONObject().put("id", it.id).put("at", it.at).put("text_sha256", sha(it.text.toByteArray())) }))
        File(dir, "saved_messages-$stamp.manifest.json").writeText(manifest.toString())
        val carried = names(ARCHIVED)
        val todo = list.filter { it.id !in carried }
        synchronized(lock) {
            todo.forEach { toArchive(it) }
            keepNames(ARCHIVED, carried.apply { todo.forEach { add(it.id) } })
        }
        Log.d("Montana", "saved_migrate backup=" + copy.name + " count=" + list.size + " carried=" + todo.size)
        Archive.savedCheck(list.map { (it.at / 1000) to it.text }) { ok, inFolder ->
            Log.d("Montana", "saved_migrate check " + (if (ok) "ok" else "SHORT") + " letters=" + list.size + " folder=" + inFolder)
            if (ok) Prefs.setBool(MIGRATED, true)
        }
    }

    fun last(ctx: Context): Letter? = all(ctx).lastOrNull()

    /** «Forget this device»: the room goes with the person, and its marks with it. */
    fun forget(ctx: Context) {
        file(ctx).delete()
        Prefs.setStr(ARCHIVED, "[]"); Prefs.setStr(GONE, "[]"); Prefs.setBool(MIGRATED, false)
    }

    /** The unsent words in the field outlive the page and the launch (iOS ChatStore.draft). */
    var draft: String
        get() = Prefs.str("draft.savedMessages", "")
        set(v) = Prefs.setStr("draft.savedMessages", v)
}

/** THE LIST'S STAMP (iOS MTClock.listStamp, MontanaMessageFeed.swift:570-588 at 2155, the author's word 22.09; asked for
 * the chats row by ChatStore.rowTime, MontanaChatStore.swift:420-423): today -- the time; within a week -- the weekday's
 * short name with a capital; further -- the day and the month in the region's own order. */
fun rowTime(c: Context, at: Long): String {
    if (DateUtils.isToday(at)) return android.text.format.DateFormat.getTimeFormat(c).format(Date(at))
    val weekStart = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        add(Calendar.DAY_OF_YEAR, -6)
    }.timeInMillis
    if (at >= weekStart) {
        val w = SimpleDateFormat("EEE", Locale.getDefault()).format(Date(at))
        return w.take(1).uppercase(Locale.getDefault()) + w.drop(1)
    }
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "ddMM")
    return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(at))
}

/**
 * THE SAVED MESSAGES PAGE (iOS ChatConversationView for the local room): the bar with the back mark, the name and one's own
 * face; the letters, newest at the foot, a day's plate over each new day; the field on glass and the send artwork beside
 * it. A long press on a letter offers «Copy» and «Delete». The page rides the keyboard: the field stands on the keys.
 */
fun savedMessagesPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val column = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(12), dp(12), dp(12), dp(12)) }   // the feed's edges (iOS MontanaMessageFeed.swift:673)
    val scroll = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        isFillViewport = true
        addView(FrameLayout(c).apply {
            // the letters stand at the foot of the page while they are few, as in every chat
            addView(column, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        })
    }
    fun toBottom() = scroll.post { scroll.scrollTo(0, (scroll.getChildAt(0)?.height ?: 0)) }

    var lastDay: Long = -1
    fun dayOf(at: Long) = java.util.Calendar.getInstance().apply { timeInMillis = at }.let { it.get(java.util.Calendar.YEAR) * 1000L + it.get(java.util.Calendar.DAY_OF_YEAR) }
    fun place(l: SavedMessages.Letter) {
        val day = dayOf(l.at)
        if (day != lastDay) {
            lastDay = day
            // THE DAY'S PLATE (iOS MTDayHeader): the date on a small glass capsule, centred.
            val words = if (DateUtils.isToday(l.at)) c.getString(R.string.today)
                        else DateUtils.formatDateTime(c, l.at, DateUtils.FORMAT_SHOW_DATE)
            column.addView(FrameLayout(c).apply {
                addView(c.text(words, 13f, Color.WHITE).apply {
                    background = c.glassPlate(); setPadding(dp(10), dp(3), dp(10), dp(3))
                }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            }, lp().apply { topMargin = c.dp(8); bottomMargin = c.dp(8) })
        }
        val b = c.bubble(l.text, mine = true, at = Date(l.at))   // USER-DATA: one's own words
        (b as FrameLayout).getChildAt(0).setOnLongClickListener { v ->
            PopupMenu(c, v).apply {
                menu.add(0, 1, 0, c.getString(R.string.copy))
                menu.add(0, 2, 1, c.getString(R.string.delete))
                setOnMenuItemClickListener {
                    when (it.itemId) {
                        1 -> (c.getSystemService(ClipboardManager::class.java)).setPrimaryClip(ClipData.newPlainText("", l.text))
                        2 -> { SavedMessages.delete(c, l.id); column.removeAllViews(); lastDay = -1; SavedMessages.all(c).forEach { x -> place(x) } }
                    }
                    true
                }
            }.show()
            true
        }
        column.addView(b, lp().apply { topMargin = c.dp(3) })
    }
    SavedMessages.all(c).forEach { place(it) }

    // THE FIELD (iOS ChatInputBar): the one compose bar of every chat; the unsent words are kept as a draft.
    val field = EditText(c).apply { setText(SavedMessages.draft) }
    val bar = ChatInputBar(act, field) {
        val words = field.text.toString().trim()
        field.setText("")   // the field is emptied first — that is what ends the draft (iOS sendMessage)
        place(SavedMessages.add(c, words))
        toBottom()
    }
    field.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: Editable?) { SavedMessages.draft = s?.toString() ?: "" }
    })

    fun hideKeys() = (c.getSystemService(InputMethodManager::class.java)).hideSoftInputFromWindow(field.windowToken, 0)

    // THE BAR'S FACE: one's own face (iOS MTSelfFace: Saved Messages wears one's own face, the author's word 18.09)
    val face: View = c.avatar(SelfFace.load(c), Prefs.userName, 36)
    val top = c.topBar(c.getString(R.string.saved_messages), onBack = { hideKeys(); onClose() },
        trailing = FrameLayout(c).apply {
            setPadding(0, 0, dp(8), 0)
            addView(face, FrameLayout.LayoutParams(dp(36), dp(36)))
        })

    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(top)
            addView(scroll, lp(MATCH, 0, 1f))
            addView(bar, lp())
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        // The page stands inside the system bars and ON the keyboard: the field rises with the keys.
        setOnApplyWindowInsetsListener { v, insets ->
            val b = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
            v.setPadding(b.left, b.top, b.right, b.bottom)
            insets
        }
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { v.requestApplyInsets() }
            override fun onViewDetachedFromWindow(v: View) {}
        })
        // the newest letter stays in sight when the page grows short under the keys
        scroll.addOnLayoutChangeListener { _, _, t, _, b, _, ot, _, ob -> if (b - t < ob - ot) toBottom() }
        toBottom()
    }
}
