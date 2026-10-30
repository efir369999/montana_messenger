package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import java.util.UUID
import kotlin.math.roundToInt

/**
 * THE FOLDERS' PAGES (iOS MTChatFolders.swift 302-710 at 2240, d335474b + 786313d3; the author's words 17.10.2026 18:4x MSK: «badges
 * over the chats, the groups and the channels, and their control in the settings»): the folders' page in the settings and from a
 * tab's menu, a folder's page, and the chats chosen for it -- the reference's own, on the settings' list.
 */

/** The way in from a tab's menu (iOS MTChatFolders.Opening): the folders' page opens on the folder named, on its chats, or on the order. */
data class FolderOpening(val folder: String? = null, val addChats: Boolean = false, val reorder: Boolean = false)

/** Every conversation a folder can name: the list's own, and our bot (iOS MTFolderChatPicker.pool). */
private fun folderPool(): List<Chat> = listedChats() + Bot.chat
private fun poolTitle(c: Context, ch: Chat) = if (ch.ref == Bot.REF) Bot.NAME else ch.shown.ifBlank { c.getString(R.string.peer) }   // USER-DATA: a name
private fun poolFace(c: Context, ch: Chat, side: Int): View = if (ch.ref == Bot.REF) Bot.face(c, side) else c.peerFace(ch.ref, poolTitle(c, ch), side)

/** A kind's or a state's glyph on its round plate (iOS kindLine / typeLine: the glyph white on the tint, in a circle). */
private fun Context.kindGlyph(k: String, side: Int): View {
    val l = ChatFolders.look(k)
    return FrameLayout(this).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(l.tint) }
        addView(icon(l.glyph, Color.WHITE), FrameLayout.LayoutParams(dp(side * 17 / 32), dp(side * 17 / 32), Gravity.CENTER))
    }
}

/** One line of a list: what leads it (a face or a glyph), the words, and what stands at its end. */
private fun Context.folderLine(lead: View?, leadSide: Int, words: String, color: Int = Color.WHITE, end: View? = null, endSide: Int = 24,
                               onTap: (() -> Unit)? = null): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(6), dp(14), dp(6))
    minimumHeight = dp(48)
    if (lead != null) { addView(lead, lp(dp(leadSide), dp(leadSide))); gap(12) }
    addView(text(words, 16f, color).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
    if (end != null) addView(end, lp(dp(endSide), dp(endSide)).apply { marginStart = dp(8) })
    if (onTap != null) pressable(onTap)
}

/** The page's own mark at the right of its bar: the pencil, the checkmark (iOS MontanaBarMark / MontanaDoneMark). */
private fun Context.barMark(glyph: Int, words: Int, onTap: () -> Unit): View = icon(glyph, Color.WHITE).apply {
    setPadding(dp(10), dp(10), dp(10), dp(10))
    contentDescription = getString(words)
    pressable(onTap)
}

/** The page stays true to the folders while it stands: a folder kept or taken away elsewhere draws it again. */
private fun View.followFolders(redraw: () -> Unit) = addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
    override fun onViewAttachedToWindow(v: View) { ChatFolders.listen(redraw) }
    override fun onViewDetachedFromWindow(v: View) { ChatFolders.unlisten(redraw) }
})

/**
 * THE FOLDERS' PAGE (iOS MTFolderSettingsPage): what folders are for, the way to a new one, the folders with the count of their chats
 * (All among them, never taken away), the folders the reference recommends. The pencil turns the list to its editing -- the order by
 * the handles, a folder away by the minus -- and the checkmark ends it. From a tab's menu it opens on the folder named, at once at its
 * chats, or on the order.
 */
fun folderSettingsPage(act: MainActivity, close: () -> Unit, opening: FolderOpening? = null, cross: Boolean = false): View {
    val c: Context = act
    var editing = opening?.reorder == true
    val body = c.vstack(Gravity.NO_GRAVITY)
    val mark = FrameLayout(c)
    lateinit var redraw: () -> Unit
    fun edit(f: ChatFolder, isNew: Boolean, addChats: Boolean) = act.push { back -> folderEditPage(act, back, f, isNew, addChats) }
    fun askRemove(f: ChatFolder) {
        AlertDialog.Builder(act).setTitle(c.getString(R.string.cf_remove_q, f.shownTitle(c))).setMessage(R.string.cf_remove_note)
            .setPositiveButton(R.string.cf_remove) { _, _ -> ChatFolders.remove(f.id) }
            .setNegativeButton(R.string.cancel, null).show()
    }
    class Suggestion(val folder: ChatFolder, val title: Int, val words: Int)
    // What the reference recommends and the person has not got yet: the unread, the personal chats, and each first folder taken away.
    fun suggestions() = listOf(
        Suggestion(ChatFolder("", kinds = ChatFolders.KINDS, leaves = listOf(ChatFolders.READ, ChatFolders.ARCHIVED)), R.string.cf_unread, R.string.cf_unread_note),
        Suggestion(ChatFolder("", kinds = listOf(ChatFolders.CONTACTS, ChatFolders.NON_CONTACTS)), R.string.cf_personal, R.string.cf_personal_note),
        Suggestion(ChatFolder("", preset = ChatFolders.GROUPS, kinds = listOf(ChatFolders.GROUPS)), R.string.app_groups, R.string.cf_groups_note),
        Suggestion(ChatFolder("", preset = ChatFolders.CHANNELS, kinds = listOf(ChatFolders.CHANNELS)), R.string.app_channels, R.string.cf_channels_note),
        Suggestion(ChatFolder("", preset = ChatFolders.BOTS, kinds = listOf(ChatFolders.BOTS)), R.string.cf_bots, R.string.cf_bots_note),
    ).filter { s -> ChatFolders.folders().none { it.holdsAlike(s.folder) } }

    /**
     * THE ORDER BY THE HANDLE (iOS onMove): the row held by its handle follows the finger, the rows it passes step aside by one, and
     * where it is let go the folder stands.
     */
    fun handle(row: View, at: Int, rows: List<View>): View = c.icon(R.drawable.ic_drag_handle, MT.gray, 22).apply {
        var y0 = 0f
        var shift = 0
        setOnTouchListener { v, e ->
            val step = row.height + 1   // the row and the list's separator under it
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    v.parent.requestDisallowInterceptTouchEvent(true); y0 = e.rawY; shift = 0
                    row.background = c.rounded(GLASS_TONE, 12); row.elevation = c.dp(8).toFloat()   // the row lifted covers the rows it passes
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = (e.rawY - y0).coerceIn(-(at * step).toFloat(), ((rows.size - 1 - at) * step).toFloat())
                    row.translationY = dy
                    shift = (dy / step).roundToInt()
                    rows.forEachIndexed { j, o ->
                        if (j == at) return@forEachIndexed
                        o.translationY = when {
                            0 < shift && j in (at + 1)..(at + shift) -> -step.toFloat()
                            shift < 0 && j in (at + shift) until at -> step.toFloat()
                            else -> 0f
                        }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    rows.forEach { it.translationY = 0f; it.elevation = 0f; it.background = null }
                    android.util.Log.d("Montana", "folder_move from=" + at + " to=" + (at + shift))
                    if (shift != 0) ChatFolders.move(at, at + shift)
                }
            }
            true
        }
    }

    redraw = {
        mark.removeAllViews()
        mark.addView(if (editing) c.barMark(R.drawable.ic_check, R.string.cf_done) { editing = false; redraw() }
            else c.barMark(R.drawable.ic_pencil, R.string.edit) { editing = true; redraw() }, FrameLayout.LayoutParams(MATCH, MATCH))
        body.removeAllViews()
        body.addView(c.vstack {
            setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(4))
            addView(c.icon(R.drawable.ic_folder, Color.WHITE), lp(c.dp(64), c.dp(64)))
            gap(14)
            addView(c.text(c.getString(R.string.cf_intro), 15f, MT.gray, center = true), lp())
        }, lp())
        val live = folderPool()
        val known = ChatFolders.contacts()
        val folders = ChatFolders.folders()
        val folderRows = mutableListOf<View>()
        folders.forEachIndexed { i, f ->
            val count = if (f.isAll) 0 else ChatFolders.rows(f, live, emptyList(), known).size
            folderRows += c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(c.dp(16), c.dp(6), c.dp(14), c.dp(6))
                minimumHeight = c.dp(48)
                if (editing && !f.isAll) {
                    addView(c.icon(R.drawable.ic_minus_circle, SysColor.red, 22).apply { pressable { askRemove(f) } }, lp(c.dp(22), c.dp(22)))
                    gap(12)
                }
                addView(c.text(f.shownTitle(c), 16f).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
                if (!editing && 0 < count) addView(c.text(count.toString(), 16f, MT.gray), lp(WRAP, WRAP).apply { marginStart = c.dp(8) })
                if (!editing && !f.isAll) addView(c.icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18), lp(c.dp(18), c.dp(18)).apply { marginStart = c.dp(6) })
                if (!editing && !f.isAll) pressable { edit(f, isNew = false, addChats = false) }
            }
        }
        if (editing) folderRows.forEachIndexed { i, r -> (r as LinearLayout).addView(handle(r, i, folderRows), lp(c.dp(22), c.dp(22)).apply { marginStart = c.dp(8) }) }
        val create = c.folderLine(null, 0, c.getString(R.string.cf_create), MT.blue) { edit(ChatFolder(UUID.randomUUID().toString()), isNew = true, addChats = false) }
        body.section(c.getString(R.string.cf_folders), c.getString(R.string.cf_list_note), create, *folderRows.toTypedArray())
        val offered = suggestions()
        if (offered.isNotEmpty()) body.section(c.getString(R.string.cf_recommended), null, *offered.map { s ->
            c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(c.dp(16), c.dp(8), c.dp(14), c.dp(8))
                minimumHeight = c.dp(48)
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.text(c.getString(s.title), 16f), lp())
                    addView(c.text(c.getString(s.words), 13f, MT.gray), lp())
                }, lp(0, WRAP, 1f))
                addView(c.icon(R.drawable.ic_plus_circle, MT.blue, 26), lp(c.dp(26), c.dp(26)).apply { marginStart = c.dp(8) })
                contentDescription = c.getString(s.title)
                pressable {
                    val f = s.folder.copy(id = UUID.randomUUID().toString())
                    ChatFolders.put(if (f.preset == null) f.copy(title = c.getString(s.title)) else f)
                }
            }
        }.toTypedArray())
    }
    redraw()
    body.followFolders { act.onMain { redraw() } }
    val page = settingsPage(act, c.getString(R.string.cf_folders), close, cross = cross, trailing = mark) { addView(body, lp()) }
    // A tab's menu asked for this page: the folder it named, at once at its chats (iOS take)
    opening?.folder?.let { id -> ChatFolders.folder(id)?.let { f -> body.post { edit(f, isNew = false, addChats = opening.addChats) } } }
    return page
}

/**
 * A FOLDER'S PAGE (iOS MTFolderEditPage): its name, the chats it takes -- kinds and conversations -- and the chats it leaves out --
 * states and conversations; each line goes by its minus. The checkmark keeps it; the cross leaves it, asking first when something
 * was changed.
 */
fun folderEditPage(act: MainActivity, close: () -> Unit, folder: ChatFolder, isNew: Boolean, addChats: Boolean): View {
    val c: Context = act
    var draft = folder
    val first = if (isNew) "" else folder.shownTitle(c)
    val body = c.vstack(Gravity.NO_GRAVITY)
    lateinit var done: View
    val name = EditText(c).apply {
        setText(first); setSelection(text.length)
        hint = c.getString(R.string.cf_name); setTextColor(Color.WHITE); setHintTextColor(MT.gray); textSize = 16f
        background = null; isSingleLine = true
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
    }
    fun typed() = name.text.toString().trim()
    fun changed() = draft != folder || typed() != first
    fun canKeep() = typed().isNotEmpty() && draft.takesAnything
    fun markDone() { done.alpha = if (canKeep()) 1f else 0.4f }
    fun keep() {
        if (!canKeep()) return
        // A first folder keeps following the person's language while its name is the one it was given.
        ChatFolders.put(if (!isNew && folder.title.isEmpty() && typed() == folder.shownTitle(c)) draft.copy(title = "") else draft.copy(title = typed(), preset = null))
        android.util.Log.d("Montana", "folder_keep " + draft.id + " kinds=" + draft.kinds.size + " chats=" + draft.chats.size)
        close()
    }
    fun leave() {
        if (!changed()) { close(); return }
        AlertDialog.Builder(act).setMessage(R.string.cf_discard_q)
            .setPositiveButton(R.string.cf_discard) { _, _ -> close() }
            .setNegativeButton(R.string.cancel, null).show()
    }
    lateinit var redraw: () -> Unit
    fun pick(taking: Boolean) = act.push { back -> folderChatPicker(act, back, taking, draft) { draft = it; redraw() } }
    fun minus(gone: () -> Unit) = c.icon(R.drawable.ic_minus_circle, SysColor.red, 22).apply { pressable { gone(); redraw() } }
    fun addLine(words: Int, glyph: Int, onTap: () -> Unit) =
        c.folderLine(FrameLayout(c).apply { addView(c.icon(glyph, MT.blue, 26), FrameLayout.LayoutParams(c.dp(26), c.dp(26), Gravity.CENTER)) }, 32,
            c.getString(words), MT.blue, onTap = onTap)
    fun chatLine(ref: String, gone: () -> Unit): View {
        val ch = folderPool().firstOrNull { it.ref == ref } ?: Book.chat(ref) ?: Chat(ref, "")
        return c.folderLine(poolFace(c, ch, 32), 32, poolTitle(c, ch), end = minus(gone), endSide = 22)
    }
    redraw = {
        body.removeAllViews()
        val taken = mutableListOf(addLine(R.string.cf_add_chats, R.drawable.ic_plus_circle) { pick(true) })
        draft.kinds.forEach { k -> taken += c.folderLine(c.kindGlyph(k, 32), 32, c.getString(ChatFolders.look(k).words), end = minus { draft = draft.copy(kinds = draft.kinds - k) }, endSide = 22) }
        draft.chats.forEach { r -> taken += chatLine(r) { draft = draft.copy(chats = draft.chats - r) } }
        body.section(c.getString(R.string.cf_included), c.getString(R.string.cf_included_note), *taken.toTypedArray())
        val left = mutableListOf(addLine(R.string.cf_add_excluded, R.drawable.ic_minus_circle) { pick(false) })
        draft.leaves.forEach { l -> left += c.folderLine(c.kindGlyph(l, 32), 32, c.getString(ChatFolders.look(l).words), end = minus { draft = draft.copy(leaves = draft.leaves - l) }, endSide = 22) }
        draft.excluded.forEach { r -> left += chatLine(r) { draft = draft.copy(excluded = draft.excluded - r) } }
        body.section(c.getString(R.string.cf_excluded), c.getString(R.string.cf_excluded_note), *left.toTypedArray())
        markDone()
    }
    done = c.barMark(R.drawable.ic_check, R.string.cf_done) { keep() }
    name.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: Editable?) { markDone() }
    })
    redraw()
    val page = settingsPage(act, c.getString(if (isNew) R.string.cf_new else R.string.cf_edit), { leave() }, cross = true, trailing = done) {
        section(c.getString(R.string.cf_name), null, name)
        addView(body, lp())
    }
    if (addChats) body.post { pick(true) }
    return page
}

/**
 * THE CHATS OF A FOLDER, CHOSEN (iOS MTFolderChatPicker): the kinds first -- or the states, for the chats left out -- then every
 * conversation, each a line with the platform's tick; the search narrows the conversations; the checkmark returns to the folder.
 */
fun folderChatPicker(act: MainActivity, close: () -> Unit, taking: Boolean, start: ChatFolder, changed: (ChatFolder) -> Unit): View {
    val c: Context = act
    var f = start
    val body = c.vstack(Gravity.NO_GRAVITY)
    lateinit var redraw: () -> Unit
    val search = EditText(c).apply {
        hint = c.getString(R.string.search); setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = c.rounded(Color.argb(61, 118, 118, 128), 10); setPadding(c.dp(12), c.dp(8), c.dp(12), c.dp(8)); isSingleLine = true
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { redraw() }
        })
    }
    fun tick(on: Boolean) = c.icon(if (on) R.drawable.ic_set_check_circle else R.drawable.ic_circle, if (on) Color.WHITE else MT.gray, 24)
    fun flip(list: List<String>, x: String) = if (x in list) list - x else list + x
    fun put(n: ChatFolder) { f = n; changed(n); redraw() }
    redraw = {
        body.removeAllViews()
        val q = search.text.toString().trim()
        if (q.isEmpty()) body.section(c.getString(R.string.cf_types), null, *(if (taking) ChatFolders.KINDS else ChatFolders.LEAVES).map { k ->
            val on = if (taking) k in f.kinds else k in f.leaves
            c.folderLine(c.kindGlyph(k, 40), 40, c.getString(ChatFolders.look(k).words), end = tick(on)) {
                put(if (taking) f.copy(kinds = flip(f.kinds, k)) else f.copy(leaves = flip(f.leaves, k)))
            }
        }.toTypedArray())
        val shown = folderPool().filter { q.isEmpty() || poolTitle(c, it).contains(q, ignoreCase = true) }
        if (shown.isNotEmpty()) body.section(c.getString(R.string.chats), null, *shown.map { ch ->
            val on = if (taking) ch.ref in f.chats else ch.ref in f.excluded
            c.folderLine(poolFace(c, ch, 40), 40, poolTitle(c, ch), end = tick(on)) {
                // a conversation taken is no longer left out, and one left out no longer taken (iOS flip(chat:))
                put(if (taking) f.copy(excluded = f.excluded - ch.ref, chats = flip(f.chats, ch.ref))
                    else f.copy(chats = f.chats - ch.ref, excluded = flip(f.excluded, ch.ref)))
            }
        }.toTypedArray())
    }
    redraw()
    return settingsPage(act, c.getString(if (taking) R.string.cf_include_title else R.string.cf_exclude_title), close,
        trailing = c.barMark(R.drawable.ic_check, R.string.cf_done, close)) {
        addView(search, lp().apply { topMargin = c.dp(8) })
        addView(body, lp())
    }
}
