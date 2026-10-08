package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ScrollView

// ─────────────────────────── the contacts page (iOS ContactsTabView) ───────────────────────────

/**
 * THE PEOPLE (iOS ContactsTabView.people): every correspondence this device holds a pipe for and knows by name — a person
 * outlives the chat's rows, only this page's own delete drops them. The page's own pins first, then the freshest presence
 * (a live word above every stamp, the stamps newest first), then by name.
 */
fun contactPeople(archived: Boolean = false): List<Chat> = Book.all()
    .filter { it.shown.isNotBlank() && !Groups.isKey(it.ref) && ChatMarks.isContactArchived(it.ref) == archived }   // a group is no person
    .sortedWith(compareBy<Chat> { if (ChatMarks.isContactPinned(it.ref)) 0 else 1 }
        .thenByDescending { Presence.stamp(it.ref) }
        .thenBy(String.CASE_INSENSITIVE_ORDER) { it.shown })

/** ONE PERSON'S ROW (iOS ContactsTabView.cell): the face, the name, the presence line in grey under it; the page's pin at the end. */
fun contactRow(act: MainActivity, ch: Chat): View {
    val c: Context = act
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(10), dp(16), dp(10))
        addView(c.peerFace(ch.ref, ch.shown, 54), lp(dp(54), dp(54)).apply { marginEnd = dp(12) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(ch.shown, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())   // USER-DATA: the name
            addView(c.text(Presence.word(c, ch.ref)?.first ?: "", 15f, MT.gray).apply { singleLineEllipsis() }, lp())
        }, lp(0, WRAP, 1f))
        if (ChatMarks.isContactPinned(ch.ref)) addView(c.icon(R.drawable.ic_pin, MT.gray, 14), lp(dp(14), dp(14)).apply { marginStart = dp(6) })
    }
}

/**
 * THE DEEDS ABOUT A PERSON (iOS ContactsTabView.deeds): Write · Profile · Archive / Unarchive · Delete · Block / Unblock.
 * The calls of iOS wait for the calls themselves.
 */
private fun contactMenu(act: MainActivity, ch: Chat) {
    val ref = ch.ref
    val deeds = mutableListOf(
        Deed(R.string.ct_write, R.drawable.ic_compose) { act.push { close -> conversationPage(act, ref, close) } },
        Deed(R.string.ct_profile, R.drawable.ic_person) { act.push { close -> peerInfoPage(act, ref, close) } },
        if (ChatMarks.isContactArchived(ref)) Deed(R.string.cl_unarchive, R.drawable.ic_unarchive) { ChatMarks.toggleContactArchive(ref) }
        else Deed(R.string.cl_archive, R.drawable.ic_archive) { ChatMarks.toggleContactArchive(ref) },
        Deed(R.string.cl_delete, R.drawable.ic_delete, red = true) { askDeleteChat(act, ref) },
    )
    deeds += if (PeerSafety.isBlocked(ref)) Deed(R.string.pi_unblock, R.drawable.ic_set_lock) { PeerSafety.setBlocked(ref, false); Book.edit(ref) {} }
             else Deed(R.string.pi_block, R.drawable.ic_set_lock, red = true) { askBlock(act, ref) { Book.edit(ref) {} } }   // the lists hear the book
    holdMenu(act, contactRow(act, ch), deeds)
}

/** The swipes (iOS swipeTrailing of the contacts): pin, archive, delete — the pin and the archive are this page's own; no calls. */
private fun contactTiles(act: MainActivity, ch: Chat) = listOf(
    Tile(R.drawable.ic_pin) { ChatMarks.toggleContactPin(ch.ref) },
    Tile(if (ChatMarks.isContactArchived(ch.ref)) R.drawable.ic_unarchive else R.drawable.ic_archive) { ChatMarks.toggleContactArchive(ch.ref) },
    Tile(R.drawable.ic_delete, red = true) { askDeleteChat(act, ch.ref) },
)

/** One person as the page draws them: a tap opens the chat itself (the author's word 17.09), a hold the menu, a stroke the tiles. */
private fun contactLine(act: MainActivity, ch: Chat): View {
    val row = contactRow(act, ch)
    row.pressable { act.push { close -> conversationPage(act, ch.ref, close) } }
    row.setOnLongClickListener { contactMenu(act, ch); true }
    return SwipeRow(act, row, contactTiles(act, ch))
}

/** The rows of people, redrawn when the book, the marks or a presence change; «No contacts yet» while there are none. */
private fun contactRows(act: MainActivity, archived: Boolean): View {
    val c: Context = act
    val rows = c.vstack(Gravity.NO_GRAVITY)
    fun fill() {
        rows.removeAllViews()
        if (!archived) {
            val n = ChatMarks.contactArchiveCount()
            if (n > 0) {
                rows.addView(archiveEntry(act, n) { act.push { close -> settingsPage(act, c.getString(R.string.cl_archive), close) { addView(contactRows(act, archived = true), lp()) } } }, lp())
                rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
            }
        }
        val people = contactPeople(archived)
        if (people.isEmpty()) {
            rows.addView(View(c), lp(MATCH, c.dp(60)))
            rows.addView(c.text(c.getString(if (archived) R.string.cl_archive_empty else R.string.no_contacts), 17f, MT.gray, center = true), lp())
        }
        people.forEach { ch ->
            rows.addView(contactLine(act, ch), lp())
            rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
        }
    }
    fill()
    val again: () -> Unit = { act.onMain { fill() } }
    rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); ChatMarks.listen(again); Presence.listen(again); fill() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again); ChatMarks.unlisten(again); Presence.unlisten(again) }
    })
    return rows
}

/** THE PAGE'S LIST (iOS MontanaTimePanelList on the contacts): the rows in a scroll, room at the foot for the share button. */
fun contactsList(act: MainActivity): View = ScrollView(act).apply {
    isVerticalScrollBarEnabled = false
    addView(act.vstack(Gravity.NO_GRAVITY) {
        addView(contactRows(act, archived = false), lp())
        gap(120)
    })
}
