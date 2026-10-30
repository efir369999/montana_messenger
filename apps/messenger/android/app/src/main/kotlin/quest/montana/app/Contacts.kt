package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
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

/**
 * ONE PERSON'S ROW (iOS ContactsTabView.cell, ContentView.swift:2644-2665) in the App Library's measure (MTLibraryRow,
 * MontanaChatsList.swift:2258-2276: the line 72 high, the face 48, the gap 16, the side 18): the face with the platform's presence
 * dot at its lower right while the word is live (MTPresenceBadge, MontanaConversation.swift:4473-4486), the name 17 semibold, the
 * presence line 16 in grey under it, 3 apart; the page's pin at the end, 12 and turned 45 as the chats' pin.
 */
fun contactRow(act: MainActivity, ch: Chat): View {
    val c: Context = act
    val word = Presence.word(c, ch.ref)
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(18), 0, dp(18), 0)
        minimumHeight = dp(72)
        addView(FrameLayout(c).apply {
            clipChildren = false
            addView(c.chatFace(ch.ref, ch.shown, 48), FrameLayout.LayoutParams(dp(48), dp(48)))
            if (word?.second == true) addView(presenceBadge(c), FrameLayout.LayoutParams(dp(13), dp(13), Gravity.BOTTOM or Gravity.END))
        }, lp(dp(48), dp(48)).apply { marginEnd = dp(16) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(ch.shown, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())   // USER-DATA: the name
            addView(c.text(word?.first ?: "", 16f, MT.gray).apply { singleLineEllipsis() }, lp().apply { topMargin = dp(3) })
        }, lp(0, WRAP, 1f))
        if (ChatMarks.isContactPinned(ch.ref)) addView(c.icon(R.drawable.ic_pin, MT.gray, 12).apply { rotation = 45f }, lp(dp(12), dp(12)).apply { marginStart = dp(6) })
    }
}

/** THE PLATFORM'S PRESENCE DOT (iOS MTPresenceDot in MTPresenceBadge): green 9, 2 of the platform's material around it. */
fun presenceBadge(c: Context): View = FrameLayout(c).apply {
    background = c.glassPlate(oval = true)
    addView(View(c).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(SysColor.green) } },
        FrameLayout.LayoutParams(c.dp(9), c.dp(9), Gravity.CENTER))
}

/**
 * THE DEEDS ABOUT A PERSON (iOS ContactsTabView.deeds, ContentView.swift:2676-2688): Write · Profile · Audio call ·
 * Video call · Archive / Unarchive · Delete · Block / Unblock — unconditional, as the calls are now wired (act.callOut).
 */
private fun contactMenu(act: MainActivity, ch: Chat, held: View?) {
    val ref = ch.ref
    val deeds = mutableListOf(
        Deed(R.string.ct_write, R.drawable.ic_compose) { act.push { close -> conversationPage(act, ref, close) } },
        Deed(R.string.ct_profile, R.drawable.ic_person) { act.push { close -> peerInfoPage(act, ref, close).pushedMark("profile") } },
        Deed(R.string.ct_audio_call, R.drawable.ic_peer_phone) { act.callOut(ref) },
        Deed(R.string.ct_video_call, R.drawable.ic_peer_video) { act.callOut(ref, video = true) },
        if (ChatMarks.isContactArchived(ref)) Deed(R.string.cl_unarchive, R.drawable.ic_unarchive) { ChatMarks.toggleContactArchive(ref) }
        else Deed(R.string.cl_archive, R.drawable.ic_archive) { ChatMarks.toggleContactArchive(ref) },
        Deed(R.string.cl_delete, R.drawable.ic_delete, red = true) { askDeleteChat(act, ref) },
    )
    deeds += if (PeerSafety.isBlocked(ref)) Deed(R.string.pi_unblock, R.drawable.ic_set_lock) { PeerSafety.setBlocked(ref, false); Book.edit(ref) {} }
             else Deed(R.string.pi_block, R.drawable.ic_set_lock, red = true) { askBlock(act, ref) { Book.edit(ref) {} } }   // the lists hear the book
    holdMenu(act, held, deeds, personPlate(act, ref))
}

/**
 * A PAGE PUSHED OVER THE CONTACTS SAYS WHEN IT IS ON THE SCREEN AND WHEN IT LEAVES IT (iOS MTPushedMark, ContentView.swift
 * 2822-2833 at 2155; atom 17a19adc6214): «contacts_page archive=on/off», «profile=on/off» -- a page that came and never said
 * «off» is a page left standing on the stack.
 */
private fun View.pushedMark(what: String): View = apply {
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { android.util.Log.d("Montana", "contacts_page $what=on") }
        override fun onViewDetachedFromWindow(v: View) { android.util.Log.d("Montana", "contacts_page $what=off") }
    })
}

/**
 * The swipes (iOS swipeTrailing of the contacts, ContentView.swift:2689-2696): pin or unpin, archive or bring back, delete — every
 * tile of the same glass (SwipeTile.glass), the pin and the archive this page's own; no calls on a swipe (the author's word 26.09).
 */
private fun contactTiles(act: MainActivity, ch: Chat) = listOf(
    Tile(if (ChatMarks.isContactPinned(ch.ref)) R.drawable.ic_pin_slash else R.drawable.ic_pin) { ChatMarks.toggleContactPin(ch.ref) },
    Tile(if (ChatMarks.isContactArchived(ch.ref)) R.drawable.ic_unarchive else R.drawable.ic_archive) { ChatMarks.toggleContactArchive(ch.ref) },
    Tile(R.drawable.ic_delete) { askDeleteChat(act, ch.ref) },
)

/** One person as the page draws them: a tap opens the chat itself (the author's word 17.09), a hold the menu, a stroke the tiles. */
private fun contactLine(act: MainActivity, ch: Chat): View {
    val row = contactRow(act, ch)
    row.pressable { act.push { close -> conversationPage(act, ch.ref, close) } }
    row.setOnLongClickListener { contactMenu(act, ch, row); true }
    return SwipeRow(act, row, contactTiles(act, ch))
}

/**
 * The rows of people, redrawn when the book, the marks or a presence change; «No contacts yet» in the middle of the page while there
 * are none (iOS ContactsTabView.body 2771-2774). THE ARCHIVE ROW IS SUMMONED (iOS archiveShown, onPull 2762-2766: «as on the chats: a
 * pull-down summons the archive row, a pull-up folds it»): it stands while it is summoned and there is an archive, riding in from the
 * top in 0.3 s; `reveal` is the page's hand on it.
 */
private class ContactRows(val view: android.widget.LinearLayout, val reveal: (Boolean) -> Unit) {
    /** The archive row stands over the list or leaves it (iOS archiveShown, read by the column and by the list alike). */
    var onHead: (Boolean) -> Unit = {}
}

private fun contactRows(act: MainActivity, archived: Boolean): ContactRows {
    val c: Context = act
    val rows = c.vstack(Gravity.NO_GRAVITY)
    var revealed = false
    var out: ContactRows? = null
    fun fill() {
        rows.removeAllViews()
        var head = false
        if (!archived) {
            val n = ChatMarks.contactArchiveCount()
            if (revealed && n > 0) {
                head = true
                rows.addView(archiveEntry(act, n) { act.push { close -> settingsPage(act, c.getString(R.string.cl_archive), close) { addView(contactRows(act, archived = true).view, lp()) }.pushedMark("archive") } }, lp())
                rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
            }
        }
        val people = contactPeople(archived)
        rows.gravity = if (people.isEmpty()) Gravity.CENTER else Gravity.NO_GRAVITY
        if (people.isEmpty()) {
            rows.addView(c.text(c.getString(if (archived) R.string.cl_archive_empty else R.string.no_contacts), 17f, MT.gray, center = true), lp())
        }
        people.forEach { ch ->
            rows.addView(contactLine(act, ch), lp())
            rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
        }
        out?.onHead(head)
    }
    fill()
    val again: () -> Unit = { act.onMain { fill() } }
    rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); ChatMarks.listen(again); Presence.listen(again); fill() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again); ChatMarks.unlisten(again); Presence.unlisten(again) }
    })
    out = ContactRows(rows) reveal@{ on ->
        if (on == revealed || (on && ChatMarks.contactArchiveCount() == 0)) return@reveal
        val head = if (revealed) rows.getChildAt(0) else null
        if (on) {
            revealed = true
            fill()
            rows.getChildAt(0)?.let { v ->
                v.translationY = -c.dp(72).toFloat(); v.alpha = 0f
                v.animate().translationY(0f).alpha(1f).setDuration(300).setInterpolator(android.view.animation.AccelerateDecelerateInterpolator()).start()
            }
        } else if (head != null) {
            revealed = false
            out?.onHead(false)   // the rows' top washes again as the row leaves (iOS fade(animated: true) at the fold)
            head.animate().translationY(-c.dp(72).toFloat()).alpha(0f).setDuration(300).setInterpolator(android.view.animation.AccelerateDecelerateInterpolator())
                .withEndAction { fill() }.start()
        } else { revealed = false; fill() }
    }
    return out!!
}

/**
 * THE PAGE'S LIST (iOS MontanaTimePanelList on the contacts): the rows in a scroll that fills the page, room at the foot for the share
 * button; the coin's pull past 25 summons the archive row, a stroke up past 25 folds it (iOS onPull 2762-2766).
 */
fun contactsList(act: MainActivity): View {
    val rows = contactRows(act, archived = false)
    val scroll = ScrollView(act).apply {
        isVerticalScrollBarEnabled = false
        isFillViewport = true
        addView(act.vstack(Gravity.NO_GRAVITY) {
            addView(rows.view, lp(MATCH, 0, 1f))
            gap(120)
        })
        setOnScrollChangeListener { _, _, y, _, _ -> if (act.dp(25) < y) rows.reveal(false) }
    }
    // THE ROWS RUN ON TO THE SCREEN'S EDGES, AS THE CHATS' (iOS ContactsTabView: MontanaTimePanelList, MTChatListFrame
    // page: "contacts", ContentView.swift:2862-2880; atoms 17a19adc6214, 3678e78b9465): the chats page's one EdgeSink mask without
    // the folders' tabs -- past the bar's room the rows sink into the page's ground, and below into the screen's edge; while the
    // archive row stands they stop at the list's top (headFloats), while the search holds the list at the page's bottom (pinned).
    var self: View? = null
    return EdgeSink(act, top = { scroll.paddingTop + act.dp(34) }, bottom = { self?.height ?: 0 }, edgeTop = { scroll.paddingTop }).apply {
        self = this; page = "contacts"; tag = EdgeSink.TAG
        rows.onHead = { up = !it }
        addView(CoinPull(act, scroll).apply { onPull = { pull -> if (25f < pull) rows.reveal(true) } }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}
