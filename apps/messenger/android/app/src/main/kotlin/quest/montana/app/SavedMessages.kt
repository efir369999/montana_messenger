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
import java.util.Date

// ─────────────────────────── the local room (iOS savedMessagesKey, ChatStore.isLocalRoom) ───────────────────────────

/**
 * SAVED MESSAGES: the room without an address — one's letters to oneself. No wire: a letter is settled the moment it is
 * written (iOS: «no wire: settled, never red»). The letters lie on the device, in the app's own files.
 */
object SavedMessages {
    class Letter(val id: String, val text: String, val at: Long)

    private fun file(ctx: Context) = File(ctx.filesDir, "saved_messages.json")

    fun all(ctx: Context): List<Letter> = try {
        val a = JSONArray(file(ctx).readText())
        (0 until a.length()).map { a.getJSONObject(it).let { o -> Letter(o.getString("id"), o.getString("text"), o.getLong("at")) } }
    } catch (e: Exception) { emptyList() }

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
        write(ctx, all(ctx) + l)
        return l
    }

    fun delete(ctx: Context, id: String) = write(ctx, all(ctx).filter { it.id != id })

    fun last(ctx: Context): Letter? = all(ctx).lastOrNull()

    /** «Forget this device»: the room goes with the person. */
    fun forget(ctx: Context) { file(ctx).delete() }

    /** The unsent words in the field outlive the page and the launch (iOS ChatStore.draft). */
    var draft: String
        get() = Prefs.str("draft.savedMessages", "")
        set(v) = Prefs.setStr("draft.savedMessages", v)
}

/** The time a chats row shows: the hour today, the date before (iOS the list's time column). */
fun rowTime(c: Context, at: Long): String =
    if (DateUtils.isToday(at)) android.text.format.DateFormat.getTimeFormat(c).format(Date(at))
    else DateUtils.formatDateTime(c, at, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_NUMERIC_DATE)

/**
 * THE SAVED MESSAGES PAGE (iOS ChatConversationView for the local room): the bar with the back mark, the name and one's own
 * face; the letters, newest at the foot, a day's plate over each new day; the field on glass and the send artwork beside
 * it. A long press on a letter offers «Copy» and «Delete». The page rides the keyboard: the field stands on the keys.
 */
fun savedMessagesPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val column = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(10), dp(8), dp(10), dp(8)) }
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
