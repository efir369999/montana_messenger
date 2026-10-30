package quest.montana.app

import android.animation.ValueAnimator
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import kotlin.math.abs

// ─────────────────────────── the chats list's own marks (iOS MontanaChatsList: MTPersonMenu, swipe tiles, selection) ───────────────────────────

/** THE LIST'S ORDER (iOS orderedChats): the pinned ones first, in their own order; then the rest, newest letter first. The archived leave. */
fun listedChats(): List<Chat> = Book.all()
    .filter { stands(it) && !ChatMarks.isArchived(it.ref) }
    .sortedByDescending { it.last?.at ?: Groups.bornAt(it.ref) }
    .sortedBy { ChatMarks.pinPlace(it.ref) ?: Int.MAX_VALUE }   // a stable sort: the newest-first order stays under the pins

/** THE CHATS PAGE'S ROWS (iOS bare): the groups and the channels live in their own pages (the author's words 06.10.2026 11:5x). */
fun chatRows(): List<Chat> = listedChats().filter { !Groups.isKey(it.ref) }

/** THE GROUPS' OR THE CHANNELS' PAGE ROWS (iOS groupRows(channel:)): the rows of its kind alone. */
fun groupRows(channel: Boolean): List<Chat> = listedChats().filter { Groups.isKey(it.ref) && Groups.isChannel(it.ref) == channel }

fun archivedChats(): List<Chat> = Book.all().filter { stands(it) && ChatMarks.isArchived(it.ref) }

/** A row stands on letters; a group stands from its invitation, by the moment it stood here (iOS MTGroup.stand: the row at once). */
private fun stands(c: Chat) = c.msgs.isNotEmpty() || Groups.isKey(c.ref)

/** The chats chosen while the list selects (iOS selecting, selectedChats). */
class ChatSelection(val onChange: (ChatSelection) -> Unit) {
    val chosen = linkedSetOf<String>()
    var on = false
    fun toggle(ref: String) { if (!chosen.remove(ref)) chosen.add(ref); onChange(this) }
    fun begin(ref: String) { on = true; chosen.clear(); chosen.add(ref); onChange(this) }
    fun end() { on = false; chosen.clear(); onChange(this) }
}

/** THE FUNERAL'S WORD ON THE WIRE (iOS convDelMark): silent; the other side erases the conversation too. */
const val CONVDEL_MARK = "\u2063mtconvdel:"

/**
 * THE CONVERSATION LEAVES THIS DEVICE (iOS removeConversationLocally): its marks and its book. A word still queued for it (the
 * funeral, the funeral's receipt) is knocked out first — the pipe's secret must outlive the last word it carries.
 */
fun buryChat(ref: String) = Thread { Post.flush(); ChatMarks.forget(ref); Book.forget(ref) }.start()

/** Deleted at both (iOS deleteChat forBoth): the funeral leaves by the pipe, then the chat is buried here. */
fun deleteForBoth(ref: String) { Post.send(ref, Marks.mintMid(), CONVDEL_MARK); buryChat(ref) }

/**
 * THE DELETION ASKED ONCE (iOS MontanaDeleteChatSheet, ContentView 4442-4467): «Permanently delete the chat with …?» on the person's
 * face — for me and them, when a pipe still stands; for me only. The correspondent's side is erased only by the first.
 */
fun askDeleteChat(act: MainActivity, ref: String, done: () -> Unit = {}) {
    val name = Book.chat(ref)?.shown?.ifBlank { null } ?: act.getString(R.string.peer)
    val question = act.getString(R.string.dl_q, name)   // USER-DATA: the name
    // A COIN LETTER OF MINE ON ITS WAY IN THIS CHAT (iOS MontanaDeleteChatSheet coinsTravel, ChatStore.deleteChat 5427-5429): the
    // question says so and offers no deletion — the erasure would take the letter off the road with its coins
    if (CoinSend.travelsIn(ref)) { faceSheet(act, ref, question, act.getString(R.string.coins_travel_chat), emptyList()); return }
    val both = Book.secret(ref) != null
    faceSheet(act, ref, question, null, listOfNotNull(
        if (both) FaceDeed(act.getString(R.string.dl_both), true) { deleteForBoth(ref); done() } else null,
        FaceDeed(act.getString(R.string.dl_mine), false) { ChatMarks.forget(ref); Book.forget(ref); done() }))
}

/** «Block this person?» on the person's face (iOS MontanaBlockSheet 4469-4483): one question for the profile and the contacts. */
fun askBlock(act: MainActivity, ref: String, done: () -> Unit = {}) =
    faceSheet(act, ref, act.getString(R.string.pi_block_q), act.getString(R.string.pi_block_note),
        listOf(FaceDeed(act.getString(R.string.pi_block_contact), true) { PeerSafety.setBlocked(ref, true); done() }))

/** One deed of the face-sheet: its words, red when it destroys, and what it does. */
class FaceDeed(val words: String, val destructive: Boolean, val work: () -> Unit)

/**
 * THE ONE SHEET FOR A QUESTION ABOUT A PERSON (iOS MontanaFaceSheet, ContentView 4485-4547, the author's word 15.09: the block's
 * confirmation wears the same look as the deletion's): the face, the question, an optional note in small type, the deeds in order
 * of descending consequence on one plate, «Cancel» on a plate of its own; a tap on the dim is «Cancel».
 */
fun faceSheet(act: MainActivity, ref: String, question: String, note: String?, deeds: List<FaceDeed>) {
    val c: Context = act
    var close: () -> Unit = {}
    lateinit var card: LinearLayout
    fun leave(then: () -> Unit) {
        card.animate().translationY(c.dp(40).toFloat()).alpha(0f).setDuration(150).withEndAction { close(); then() }.start()
    }
    fun plate() = android.graphics.drawable.GradientDrawable().apply { cornerRadius = c.dp(14).toFloat(); setColor(Color.argb(235, 44, 44, 46)) }
    fun deed(words: String, red: Boolean, bold: Boolean, work: () -> Unit) =
        c.text(words, 17f, if (red) SysColor.red else Color.WHITE, bold = bold, center = true).apply {
            gravity = Gravity.CENTER; setPadding(0, c.dp(16), 0, c.dp(16)); pressable { leave(work) }
        }
    card = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(8), 0, dp(8), dp(8))
        isClickable = true   // a tap on the card is not a tap on the dim
        addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
            background = plate()
            addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                setPadding(dp(20), dp(20), dp(20), dp(16))
                addView(c.peerFace(ref, Book.chat(ref)?.shown.orEmpty(), 72), lp(dp(72), dp(72)))
                addView(c.text(question, 15f, Color.WHITE, center = true), lp().apply { topMargin = dp(12) })
                if (note != null) addView(c.text(note, 13f, MT.gray, center = true), lp().apply { topMargin = dp(12) })
            }, lp())
            for (d in deeds) {
                addView(View(c).apply { setBackgroundColor(Color.argb(31, 255, 255, 255)) }, lp(MATCH, 1))
                addView(deed(d.words, d.destructive, false, d.work), lp())
            }
        }, lp())
        addView(deed(c.getString(R.string.cancel), false, true) {}.apply { background = plate() }, lp().apply { topMargin = dp(8) })
    }
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.argb(115, 0, 0, 0))   // iOS black 0.45
        setOnClickListener { leave {} }
        addView(card, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
    }
    card.translationY = c.dp(40).toFloat(); card.alpha = 0f
    close = act.overlay(page)
    card.animate().translationY(0f).alpha(1f).setDuration(300).setInterpolator(android.view.animation.DecelerateInterpolator()).start()
}

/** Pin or unpin; a sixth pin is refused as iOS refuses it — quietly, the row stays where it was. */
private fun pin(ref: String) { ChatMarks.togglePin(ref) }

/**
 * ONE ROW OF THE LIST (iOS chatRowCell): the chat's own row, and around it the list's marks — a tap opens the chat (and
 * lifts the hand mark), a long press opens the person's menu, a stroke from the row's right edge uncovers the tiles; while
 * the list selects, a tap chooses and a circle on the left says whether it is chosen.
 */
fun listRow(act: MainActivity, chat: Chat, inArchive: Boolean, sel: ChatSelection?): View {
    val c: Context = act
    val row = chatRow(act, chat)
    val open = {
        ChatMarks.opened(chat.ref)
        act.push { close -> conversationPage(act, chat.ref, close) }
    }
    if (sel != null && sel.on) {
        val chosen = chat.ref in sel.chosen
        val mark = FrameLayout(c).apply {
            background = if (chosen) c.rounded(Color.WHITE, 12) else c.rounded(Color.TRANSPARENT, 12, MT.gray)
            if (chosen) addView(c.icon(R.drawable.ic_check, Color.BLACK, 16), FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER))
        }
        return c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), 0, 0, 0)
            addView(mark, lp(dp(24), dp(24)))
            addView(row.apply { isClickable = false; isLongClickable = false; setOnClickListener(null); setOnLongClickListener(null) }, lp(0, WRAP, 1f))
            pressable { sel.toggle(chat.ref) }
        }
    }
    row.setOnClickListener { open() }
    row.setOnLongClickListener { personMenu(act, chat, inArchive, sel, row); true }
    return SwipeRow(act, row, rowTiles(act, chat, inArchive), callTiles(act, chat))
}

/** Left to right the two calls (iOS swipeLeading 773-777): a pair's chat only — no group, no room without an address. */
private fun callTiles(act: MainActivity, chat: Chat): List<Tile> {
    if (Groups.isKey(chat.ref) || Book.secret(chat.ref) == null) return emptyList()
    return listOf(Tile(R.drawable.ic_peer_phone) { act.callOut(chat.ref, video = false) }, Tile(R.drawable.ic_peer_video) { act.callOut(chat.ref, video = true) })
}

/** A tile under the row: its glyph and its deed (iOS SwipeTile). */
class Tile(val glyph: Int, val red: Boolean = false, val deed: () -> Unit)

/**
 * THE ROW'S TILES, right to left as iOS draws them (swipeTrailing): unread / read, pin, mute, archive, delete. In the archive
 * the archive tile takes the row back out (ArchivedChatsView: «unarchive»).
 */
fun rowTiles(act: MainActivity, chat: Chat, inArchive: Boolean): List<Tile> = listOf(
    Tile(if (ChatMarks.hasUnread(chat)) R.drawable.ic_mark_read else R.drawable.ic_dot) { ChatMarks.toggleUnread(chat) },
    Tile(if (ChatMarks.isPinned(chat.ref)) R.drawable.ic_pin_slash else R.drawable.ic_pin) { pin(chat.ref) },   // pin.slash.fill on a pinned chat (iOS 782)
    Tile(if (ChatMarks.isMuted(chat.ref)) R.drawable.ic_set_bell else R.drawable.ic_bell_off) { ChatMarks.toggleMute(chat.ref) },
    Tile(if (inArchive) R.drawable.ic_unarchive else R.drawable.ic_archive) {
        if (inArchive) ChatMarks.unarchive(chat.ref) else ChatMarks.archive(chat.ref)
    },
    Tile(R.drawable.ic_delete) { askDeleteChat(act, chat.ref) },   // every tile the same glass (iOS swipeTrailing 778-786)
)

/**
 * THE PERSON'S MENU (iOS MTPersonMenu): the room dims, the row stands lifted, and the deeds under it — Pin · Mute · Select ·
 * Mark as read / unread · Archive · Delete. In the archive: Unarchive · Mute · Mark · Delete (ArchivedChatsView's menu).
 */
fun personMenu(act: MainActivity, chat: Chat, inArchive: Boolean, sel: ChatSelection?, held: View? = null) {
    val deeds = mutableListOf<Deed>()
    if (inArchive) deeds += Deed(R.string.cl_unarchive, R.drawable.ic_unarchive) { ChatMarks.unarchive(chat.ref) }
    else {
        val pinned = ChatMarks.isPinned(chat.ref)
        deeds += Deed(if (pinned) R.string.cl_unpin else R.string.cl_pin, R.drawable.ic_pin) { pin(chat.ref) }
    }
    val muted = ChatMarks.isMuted(chat.ref)
    deeds += Deed(if (muted) R.string.cl_unmute else R.string.cl_mute, if (muted) R.drawable.ic_set_bell else R.drawable.ic_bell_off) { ChatMarks.toggleMute(chat.ref) }
    if (!inArchive && sel != null) deeds += Deed(R.string.cl_select, R.drawable.ic_set_check_circle) { sel.begin(chat.ref) }
    val unread = ChatMarks.hasUnread(chat)
    deeds += Deed(if (unread) R.string.cl_mark_read else R.string.cl_mark_unread, if (unread) R.drawable.ic_mark_read else R.drawable.ic_dot) { ChatMarks.toggleUnread(chat) }
    if (!inArchive) deeds += Deed(R.string.cl_archive, R.drawable.ic_archive) { ChatMarks.archive(chat.ref) }
    deeds += Deed(R.string.cl_delete, R.drawable.ic_delete, red = true) { askDeleteChat(act, chat.ref) }
    holdMenu(act, held, deeds, personPlate(act, chat.ref))
}

/** One deed of a hold's menu: its words, its glyph, red when it destroys. */
class Deed(val words: Int, val glyph: Int, val red: Boolean = false, val work: () -> Unit)

/**
 * THE CLOUD'S PLACE AND SPRING (iOS MTMenuPlace, MontanaMessageMenu.swift:153-167, and MTPersonMenu.body 576-603): the cloud stands
 * where the held thing stood -- its top 12 over the thing's top, kept 8 from the top and 10 from the foot; a place unknown, the
 * middle -- over the platform's ultra-thin material (MainActivity.cloud), and rises by the spring (0.94 to 1 from its leading edge,
 * the light coming up; response 0.32, damping 0.68). A tap off it, or the back, lets it go in 0.15 s; the returned leave does the
 * same and then runs what it is handed.
 */
fun showCloud(act: MainActivity, cloud: View, anchorTop: Int?): (() -> Unit) -> Unit {
    val c: Context = act
    lateinit var gone: () -> Unit
    var leaving = false
    val leave: (() -> Unit) -> Unit = { then ->
        if (!leaving) {
            leaving = true
            cloud.animate().alpha(0f).scaleX(0.94f).scaleY(0.94f).setDuration(150).setInterpolator(android.view.animation.DecelerateInterpolator())
                .withEndAction { gone(); then() }.start()
        }
    }
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.argb(51, 0, 0, 0))   // the material's own shade over the blur
        isClickable = true
        setOnClickListener { leave {} }
        addView(cloud.apply { isClickable = true; alpha = 0f }, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))
    }
    gone = act.cloud(page) { leave {} }
    page.viewTreeObserver.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
        override fun onPreDraw(): Boolean {
            page.viewTreeObserver.removeOnPreDrawListener(this)
            val room = page.height - page.paddingTop - page.paddingBottom
            val h = cloud.height
            val pageTop = IntArray(2).also { page.getLocationOnScreen(it) }[1] + page.paddingTop
            var t = if (anchorTop != null) anchorTop - pageTop - c.dp(12) else (room - h) / 2
            if (room - c.dp(10) < t + h) t = room - c.dp(10) - h
            cloud.translationY = maxOf(c.dp(8), t).toFloat()
            cloud.pivotX = 0f; cloud.pivotY = h / 2f
            cloud.scaleX = 0.94f; cloud.scaleY = 0.94f
            cloud.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(320).setInterpolator(android.view.animation.OvershootInterpolator(1.2f)).start()
            return true
        }
    })
    return leave
}

/** The person as the row showed them, on the cloud's own plate (iOS MTPersonMenu's head: MontanaChatFace 44, 14 by 8, corner 16). */
fun personPlate(c: Context, ref: String): View {
    val name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = c.rounded(Color.argb(235, 44, 44, 46), 16, Color.argb(26, 255, 255, 255))
        setPadding(dp(14), dp(8), dp(14), dp(8))
        addView(c.peerFace(ref, name, 44), lp(dp(44), dp(44)).apply { marginEnd = dp(12) })
        addView(c.text(name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(WRAP, WRAP))   // USER-DATA: the name
    }
}

/**
 * THE MENU OF A HOLD (iOS MTPersonMenu, MontanaMessageMenu.swift:560-626: «the chat's own cloud -- the same material, the same rows,
 * the same spring and the same place-keeping as the menu about a letter»): what was held keeps its place on the screen -- the head
 * (the person's face and name, when the hold is about a person) at its top -- and the deeds stand under it, 250 wide, each the
 * menu's own row (MTMenuRow: 16, 14 by 11, the glyph white 0.8 or red); a deed runs once the cloud has gone. The held view itself
 * stays in its list -- it was lifted out of it before, which a row with a parent could not survive.
 */
fun holdMenu(act: MainActivity, held: View?, deeds: List<Deed>, head: View? = null) {
    val c: Context = act
    lateinit var leave: (() -> Unit) -> Unit
    val line = Color.argb(77, 142, 142, 147)   // iOS MTMenuDivider: the gray at three tenths
    val plate = c.vstack(Gravity.NO_GRAVITY) { background = c.rounded(Color.argb(235, 44, 44, 46), 16, Color.argb(26, 255, 255, 255)) }
    deeds.forEach { d ->
        if (plate.childCount > 0) plate.addView(View(c).apply { setBackgroundColor(line) }, lp(MATCH, 1))
        plate.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(11), dp(14), dp(11))
            addView(c.text(c.getString(d.words), 16f, if (d.red) SysColor.red else Color.WHITE), lp(0, WRAP, 1f))
            addView(c.icon(d.glyph, if (d.red) SysColor.red else Color.argb(204, 255, 255, 255), 20), lp(dp(20), dp(20)))
            pressable { leave(d.work) }
        }, lp())
    }
    val cloud = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(12), dp(12), dp(12), dp(12))
        if (head != null) { addView(head, lp(WRAP, WRAP)); gap(12) }
        addView(plate, lp(dp(250), WRAP))
    }
    leave = showCloud(act, cloud, held?.let { v -> IntArray(2).also { v.getLocationOnScreen(it) }[1] })
}

/**
 * THE SELECTION BAR at the list's foot (iOS selectionBar): the cross out of it, then Read all · Archive · Delete for the
 * chosen chats; dim and deaf while nothing is chosen.
 */
fun selectionBar(act: MainActivity, sel: ChatSelection): View {
    val c: Context = act
    val any = sel.chosen.isNotEmpty()
    fun pill(words: Int, red: Boolean = false, work: () -> Unit) = c.text(c.getString(words), 15f, if (red) SysColor.red else Color.WHITE, bold = true, center = true).apply {
        background = c.glassPlate()
        setPadding(dp(14), dp(10), dp(14), dp(10))
        alpha = if (any) 1f else 0.5f
        if (any) pressable { work(); sel.end() }
    }
    fun chosen() = sel.chosen.mapNotNull { Book.chat(it) }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(10))
        addView(FrameLayout(c).apply {
            background = c.glassPlate()
            addView(c.icon(R.drawable.ic_close, Color.WHITE, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { sel.end() }
        }, lp(dp(44), dp(44)))
        gap(10)
        addView(pill(R.string.cl_read_all) { chosen().forEach { ch -> if (ch.unread > 0) Book.edit(ch.ref) { it.unread = 0 }; ChatMarks.opened(ch.ref) } }, lp(0, WRAP, 1f))
        gap(8)
        addView(pill(R.string.cl_archive) { chosen().forEach { ChatMarks.archive(it.ref) } }, lp(0, WRAP, 1f))
        gap(8)
        addView(pill(R.string.cl_delete, red = true) {
            val refs = sel.chosen.toList().filter { !CoinSend.travelsIn(it) }   // a chat with coins on their way waits (iOS deleteChat 5429)
            AlertDialog.Builder(act).setMessage(R.string.delete_chat_q)
                .setItems(arrayOf(c.getString(R.string.dl_both), c.getString(R.string.dl_mine))) { _, which ->
                    refs.forEach { if (which == 0 && Book.secret(it) != null) deleteForBoth(it) else { ChatMarks.forget(it); Book.forget(it) } }
                }
                .setNegativeButton(R.string.cancel, null).show()
        }, lp(0, WRAP, 1f))
    }
}

/**
 * THE «ARCHIVE» ROW (iOS ContactsTabView.archiveRow, ContentView.swift:2697-2716: «the chats page's, one to one»), in the App
 * Library's measure (72, the face 48, the gap 16, the side 18): a circle of white 0.15 with the grey archive box 24 and a rim of
 * white 0.45, «Archive» 17 semibold over its count 16 in grey, the platform's chevron 14 in grey at the end.
 */
fun archiveEntry(act: MainActivity, count: Int, onOpen: (() -> Unit)? = null): View {
    val c: Context = act
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(18), 0, dp(18), 0)
        minimumHeight = dp(72)
        addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.rgb(38, 38, 38)); setStroke(dp(1), Color.argb(115, 255, 255, 255)) }
            addView(c.icon(R.drawable.ic_archive, MT.gray, 24), FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER))
        }, lp(dp(48), dp(48)).apply { marginEnd = dp(16) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(c.getString(R.string.cl_archive), 17f, Color.WHITE, bold = true), lp())
            addView(c.text(count.toString(), 16f, MT.gray), lp().apply { topMargin = dp(3) })   // USER-DATA: a count
        }, lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_chevron_right, MT.gray, 14), lp(dp(14), dp(14)))
        pressable { onOpen?.invoke() ?: act.push { archivePage(act, it) } }
    }
}

/** THE ARCHIVE (iOS ArchivedChatsView): the same rows as the list, the same tiles and menu — only «archive» turns to «unarchive». */
fun archivePage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val rows = c.vstack(Gravity.NO_GRAVITY)
    fun fill() {
        rows.removeAllViews()
        val all = archivedChats()
        if (all.isEmpty()) {
            rows.addView(View(c), lp(MATCH, c.dp(60)))
            rows.addView(c.text(c.getString(R.string.cl_archive_empty), 17f, MT.gray, center = true), lp())
        }
        for (ch in all) {
            rows.addView(listRow(act, ch, inArchive = true, sel = null), lp())
            rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
        }
    }
    fill()
    val again: () -> Unit = { act.onMain { fill() } }
    rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); ChatMarks.listen(again); fill() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again); ChatMarks.unlisten(again) }
    })
    return settingsPage(act, c.getString(R.string.cl_archive), onBack) { addView(rows, lp()) }
}

/**
 * A ROW THAT UNCOVERS ITS TILES (iOS SwipeChatRow; MontanaChatsList 771-786: left to right the two calls, right to left the
 * marks). The stroke is the row's only when it begins in one of the row's edge zones — a sixth of the width, 22 to 80 points
 * (iOS MTTabPan's edge zones): from the centre the stroke turns the pages, as it did before. Released past half the tiles,
 * the row stays open; a tap on the open row closes it, and so does the list's move.
 */
class SwipeRow(private val act: MainActivity, private val content: View, tiles: List<Tile>, leading: List<Tile> = emptyList()) : FrameLayout(act) {
    private val tray = act.hstack { gravity = Gravity.CENTER_VERTICAL or Gravity.END; setPadding(0, 0, dp(10), 0) }
    private val lead = act.hstack { gravity = Gravity.CENTER_VERTICAL or Gravity.START; setPadding(dp(10), 0, 0, 0) }
    private val tileSize = dp(44)
    private val gapPx = dp(8)
    private val trayWidth = tiles.size * (tileSize + gapPx) + dp(10)
    private val leadWidth = if (leading.isEmpty()) 0 else leading.size * (tileSize + gapPx) + dp(10)
    private val slop = ViewConfiguration.get(act).scaledTouchSlop
    private var downX = 0f; private var downY = 0f; private var startT = 0f
    private var edge = false; private var dragging = false

    private fun tileView(t: Tile) = FrameLayout(act).apply {
        background = act.glassPlate(oval = true)
        addView(act.icon(t.glyph, if (t.red) SysColor.red else Color.WHITE, 20), LayoutParams(dp(20), dp(20), Gravity.CENTER))
        pressable { settle(0f); t.deed() }
    }

    init {
        tiles.forEach { t -> tray.addView(tileView(t), LinearLayout.LayoutParams(tileSize, tileSize).apply { marginStart = gapPx }) }
        leading.forEach { t -> lead.addView(tileView(t), LinearLayout.LayoutParams(tileSize, tileSize).apply { marginEnd = gapPx }) }
        addView(tray, LayoutParams(MATCH, MATCH))
        addView(lead, LayoutParams(MATCH, MATCH))
        tray.visibility = INVISIBLE
        lead.visibility = INVISIBLE
        addView(content, LayoutParams(MATCH, WRAP))
    }

    private fun zone(): Float = (width / 6f).coerceIn(dp(22).toFloat(), dp(80).toFloat())

    // AN OPEN ROW CLOSES WHEN THE LIST MOVES (iOS 15.26, 1367: the platform's own swipe actions close on scroll)
    private val onScroll = android.view.ViewTreeObserver.OnScrollChangedListener { if (content.translationX != 0f && !dragging) settle(0f) }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); viewTreeObserver.addOnScrollChangedListener(onScroll) }
    override fun onDetachedFromWindow() { viewTreeObserver.removeOnScrollChangedListener(onScroll); super.onDetachedFromWindow() }

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.x; downY = e.y; startT = content.translationX; dragging = false
                edge = startT != 0f || e.x > width - zone() || (leadWidth > 0 && e.x < zone())
                // the edge zone is the row's: the pages must not take this stroke sideways
                if (edge) parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                if (!edge) return false
                val dx = e.x - downX; val dy = e.y - downY
                if (abs(dy) > slop && abs(dy) > abs(dx)) { edge = false; parent?.requestDisallowInterceptTouchEvent(false); return false }   // a scroll: the list's
                if (abs(dx) > slop) {
                    // the row covers its tiles while it moves; closed, it is clear again over the page's ground
                    dragging = true; tray.visibility = VISIBLE; lead.visibility = VISIBLE; content.setBackgroundColor(Color.BLACK); return true
                }
            }
            // a tap on the open row closes it; a tap on a tile is the tile's
            MotionEvent.ACTION_UP -> if (startT != 0f && abs(e.x - downX) < slop && e.x > content.translationX && e.x < width + content.translationX) { settle(0f); return true }
        }
        return false
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!dragging) return super.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_MOVE -> content.translationX = (startT + e.x - downX).coerceIn(-trayWidth.toFloat(), leadWidth.toFloat())
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragging = false
                val t = content.translationX
                settle(if (t < -trayWidth / 2f) -trayWidth.toFloat() else if (leadWidth > 0 && t > leadWidth / 2f) leadWidth.toFloat() else 0f)
            }
        }
        return true
    }

    private fun settle(to: Float) {
        ValueAnimator.ofFloat(content.translationX, to).apply {
            duration = 220
            addUpdateListener { content.translationX = it.animatedValue as Float }
            doOnEnd { if (to == 0f) { tray.visibility = INVISIBLE; lead.visibility = INVISIBLE; content.background = null } }
            start()
        }
    }

    private fun ValueAnimator.doOnEnd(work: () -> Unit) = addListener(object : android.animation.AnimatorListenerAdapter() {
        override fun onAnimationEnd(animation: android.animation.Animator) = work()
    })
}
