package quest.montana.app

import android.animation.ValueAnimator
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.text.Editable
import android.text.InputType
import android.text.TextPaint
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.ViewTreeObserver
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

// ─────────────────────────── the folders over the chats (iOS MTChatFolders.swift at 2235) ───────────────────────────

/** THE KINDS OF CHATS A FOLDER TAKES (iOS MTChatFolder.Kind, MTChatFolders.swift:11-40): the raw word is the iPhone's own -- a copy carries
 *  it --, the glyph stands white on a circle of the kind's tint. */
enum class FolderKind(val raw: String, val title: Int, val glyph: Int, val tint: Int) {
    CONTACTS("contacts", R.string.fl_kind_contacts, R.drawable.ic_person_crop_circle, SysColor.blue),
    NON_CONTACTS("nonContacts", R.string.fl_kind_non_contacts, R.drawable.ic_person_crop_circle_question, SysColor.teal),
    GROUPS("groups", R.string.app_groups, R.drawable.ic_person_2, SysColor.green),
    CHANNELS("channels", R.string.app_channels, R.drawable.ic_megaphone, SysColor.indigo),
    BOTS("bots", R.string.fl_bots, R.drawable.ic_cpu, SysColor.purple);
    companion object { fun of(raw: String): FolderKind? = values().firstOrNull { it.raw == raw } }
}

/** THE STATES A FOLDER LEAVES OUT (iOS MTChatFolder.Leave, MTChatFolders.swift:41-64), the same way. */
enum class FolderLeave(val raw: String, val title: Int, val glyph: Int, val tint: Int) {
    MUTED("muted", R.string.fl_leave_muted, R.drawable.ic_bell_slash, SysColor.red),
    READ("read", R.string.fl_leave_read, R.drawable.ic_checkmark_message, SysColor.blue),
    ARCHIVED("archived", R.string.fl_leave_archived, R.drawable.ic_archivebox, SysColor.gray);
    companion object { fun of(raw: String): FolderLeave? = values().firstOrNull { it.raw == raw } }
}

/**
 * ONE FOLDER (iOS MTChatFolder, MTChatFolders.swift:4-105; the author's words 17.10.2026 18:4x MSK: «badges over the chats, the groups and
 * the channels, and their control in the settings»; «left of the chats, the groups and the channels a field All, every chat in it»): the
 * kinds of chats and the chats it takes, the states and the chats it leaves out. `title` is the person's own words, empty while a first
 * folder keeps the name of its kind in the person's language (`preset`). Its JSON is the iPhone's Codable one field for field -- id, title,
 * preset (absent when none), kinds, chats, leaves, excluded -- so a copy lays the same folders on either phone.
 */
data class ChatFolder(
    val id: String,
    val title: String = "",
    val preset: FolderKind? = null,
    val kinds: List<FolderKind> = emptyList(),
    val chats: List<String> = emptyList(),
    val leaves: List<FolderLeave> = listOf(FolderLeave.ARCHIVED),
    val excluded: List<String> = emptyList()) {

    val isAll: Boolean get() = id == ALL_ID

    /** The name on the tab (iOS shownTitle 77-86): All Chats, the person's words, or a first folder's kind in the person's language. */
    fun shownTitle(c: Context): String {
        if (isAll) return c.getString(R.string.fl_all_chats)
        val p = preset
        if (title.isNotEmpty() || p == null) return title   // USER-DATA: the folder's own name
        return c.getString(when (p) {
            FolderKind.CONTACTS, FolderKind.NON_CONTACTS -> R.string.chats
            FolderKind.GROUPS -> R.string.app_groups
            FolderKind.CHANNELS -> R.string.app_channels
            FolderKind.BOTS -> R.string.fl_bots
        })
    }

    /** The folder of one kind alone (iOS onlyKind 88): the drawer's Groups and Channels open theirs, and its corner gives birth to that kind. */
    val onlyKind: FolderKind? get() = if (kinds.size == 1 && chats.isEmpty()) kinds[0] else null
    val takesAnything: Boolean get() = kinds.isNotEmpty() || chats.isNotEmpty()

    /** The same folder by what it holds, whatever its name (iOS holdsAlike 91-94): a recommendation the person already has is not offered again. */
    fun holdsAlike(o: ChatFolder) = kinds.toSet() == o.kinds.toSet() && leaves.toSet() == o.leaves.toSet() &&
        chats.isEmpty() && o.chats.isEmpty() && excluded.isEmpty() && o.excluded.isEmpty()

    /** Whether a conversation stands in the folder (iOS takes 96-104): taken by its kind or by name, not left out by name or by a state. */
    fun takes(ref: String, kind: FolderKind, muted: Boolean, unread: Boolean, archived: Boolean): Boolean {
        if (isAll) return !archived
        if (ref in excluded) return false
        if (kind !in kinds && ref !in chats) return false
        if (muted && FolderLeave.MUTED in leaves) return false
        if (!unread && FolderLeave.READ in leaves) return false
        if (archived && FolderLeave.ARCHIVED in leaves) return false
        return true
    }

    fun json(): JSONObject = JSONObject().put("id", id).put("title", title).apply { preset?.let { put("preset", it.raw) } }
        .put("kinds", JSONArray(kinds.map { it.raw })).put("chats", JSONArray(chats))
        .put("leaves", JSONArray(leaves.map { it.raw })).put("excluded", JSONArray(excluded))

    companion object {
        const val ALL_ID = "all"   // NOT-UI: iOS MTChatFolder.allID
        val ALL = ChatFolder(ALL_ID, leaves = emptyList())

        /** A folder as either phone wrote it; a word this build does not know is passed over, never guessed. */
        fun of(o: JSONObject): ChatFolder? {
            val id = o.optString("id").ifEmpty { return null }
            fun words(k: String): List<String>? = o.optJSONArray(k)?.let { a -> (0 until a.length()).mapNotNull { a.opt(it) as? String } }
            return ChatFolder(id, o.optString("title"), FolderKind.of(o.optString("preset")),
                words("kinds")?.mapNotNull { FolderKind.of(it) } ?: emptyList(), words("chats") ?: emptyList(),
                words("leaves")?.mapNotNull { FolderLeave.of(it) } ?: listOf(FolderLeave.ARCHIVED), words("excluded") ?: emptyList())
        }
    }
}

/** A ROW AS THE FOLDERS READ IT (iOS Chat with store.mutedChats and store.hasUnread): a conversation of the book, the local room or our bot. */
class FolderRow(val ref: String, val chat: Chat?, val muted: Boolean, val unread: Boolean) {
    companion object {
        fun of(ch: Chat) = FolderRow(ch.ref, ch, ChatMarks.isMuted(ch.ref), ChatMarks.hasUnread(ch))
        fun saved() = FolderRow(SAVED_ROW, null, ChatMarks.isMuted(SAVED_ROW), false)
        fun bot() = FolderRow(FolderBot.ROW, null, muted = false, unread = false)
    }
}

/** The local room's name in a folder's lists (iOS savedMessagesKey, MontanaAvatarKit.swift:6): the iPhone's own, so a copy names it alike. */
const val SAVED_ROW = "Saved Messages"   // NOT-UI: a key of the folders' lists, never shown

/**
 * THE PERSON'S FOLDERS IN THE TABS' ORDER (iOS MTChatFolders, MTChatFolders.swift:107-186): All Chats among them and never taken away; kept
 * sealed in the device vault under the iPhone's own name and carried by the copy as «d:chatFolders» (iOS SeedScope.settingKeys,
 * MontanaChatStore.swift:6691) -- a setting of whoever holds the phone: a change of seed keeps them.
 */
object ChatFolders {
    const val KEY = "chatFolders"   // NOT-UI: iOS MTChatFolders.key
    private val lock = Any()
    private var held: List<ChatFolder>? = null
    private val listeners = mutableListOf<() -> Unit>()

    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }
    private fun tell() { val ls = synchronized(listeners) { listeners.toList() }; MainThread.post { ls.forEach { it() } } }

    /** THE FIRST TABS (iOS firstFolders 125-131), in the author's order of 17.10.2026: All, the chats, the groups, the channels, the bots. */
    val first: List<ChatFolder> get() = listOf(ChatFolder.ALL,
        ChatFolder("chats", preset = FolderKind.CONTACTS, kinds = listOf(FolderKind.CONTACTS, FolderKind.NON_CONTACTS)),
        ChatFolder("groups", preset = FolderKind.GROUPS, kinds = listOf(FolderKind.GROUPS)),
        ChatFolder("channels", preset = FolderKind.CHANNELS, kinds = listOf(FolderKind.CHANNELS)),
        ChatFolder("bots", preset = FolderKind.BOTS, kinds = listOf(FolderKind.BOTS)))

    /** The folders as kept; none kept, or none of them All Chats, and the first ones stand (iOS init 120-124). */
    val folders: List<ChatFolder> get() = synchronized(lock) { held ?: read().also { held = it } }
    private fun read(): List<ChatFolder> {
        val raw = DeviceVault.get(KEY)?.toString(Charsets.UTF_8) ?: return first
        val kept = runCatching { JSONArray(raw).let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let { o -> ChatFolder.of(o) } } } }.getOrNull()
        return if (kept != null && kept.any { it.isAll }) kept else first
    }

    fun folder(id: String): ChatFolder? = folders.firstOrNull { it.id == id }
    fun folder(only: FolderKind): ChatFolder? = folders.firstOrNull { it.onlyKind == only }
    fun put(f: ChatFolder) = change { l -> val i = l.indexOfFirst { it.id == f.id }; if (0 <= i) l.set(i, f) else l.add(f) }
    fun remove(id: String) { if (id != ChatFolder.ALL_ID) change { l -> l.removeAll { it.id == id } } }
    /** A folder carried to another place of the tabs: from where it stood to the place it now takes. */
    fun move(from: Int, to: Int) = change { l -> if (from in l.indices) l.add(to.coerceIn(0, l.size - 1), l.removeAt(from)) }
    private fun change(work: (MutableList<ChatFolder>) -> Unit) {
        synchronized(lock) {
            val l = folders.toMutableList()
            work(l)
            held = l
            DeviceVault.set(KEY, JSONArray().apply { l.forEach { put(it.json()) } }.toString().toByteArray(Charsets.UTF_8))
        }
        tell()
    }

    /** The book is read only while a folder tells the contacts from the rest (iOS tellsContacts 154): the first folders take both. */
    val tellsContacts: Boolean get() = folders.any { (FolderKind.CONTACTS in it.kinds) != (FolderKind.NON_CONTACTS in it.kinds) }
    /** The people kept as contacts (iOS contactRefs 155-159, the book «mtContacts»), or nothing while no folder needs them. */
    fun contacts(): Set<String>? = if (tellsContacts) PeerContact.all().toSet() else null

    /** What a conversation is to the folders (iOS kind(of:) 161-165): one answer for the tabs, their badges and the folders' page. */
    fun kind(ref: String, contacts: Set<String>?): FolderKind = when {
        ref == FolderBot.ROW -> FolderKind.BOTS
        Groups.isKey(ref) -> if (Groups.isChannel(ref)) FolderKind.CHANNELS else FolderKind.GROUPS
        contacts?.contains(ref) == true -> FolderKind.CONTACTS
        else -> FolderKind.NON_CONTACTS
    }

    /** The chats page's rows in its one order (iOS orderedChats + [MTBot.chat], MontanaChatsList.swift:979): the local room -- on top here,
     *  where this phone keeps it --, the list with its pins first (listedChats), our bot last. */
    fun live(): List<FolderRow> = listOf(FolderRow.saved()) + listedChats().map { FolderRow.of(it) } + FolderRow.bot()
    fun archived(): List<FolderRow> = archivedChats().map { FolderRow.of(it) }

    /** A folder's rows in the chats' one order (iOS rows(of:) 167-175): the rows of the list, and the archived ones where the folder keeps them. */
    fun rows(f: ChatFolder, live: List<FolderRow>, archived: List<FolderRow>, contacts: Set<String>?): List<FolderRow> {
        if (f.isAll) return live
        fun keep(r: FolderRow, gone: Boolean) = f.takes(r.ref, kind(r.ref, contacts), r.muted, r.unread, gone)
        val here = live.filter { keep(it, false) }
        return if (FolderLeave.ARCHIVED in f.leaves) here else here + archived.filter { keep(it, true) }
    }

    /** The tabs and their badges (iOS folderTabs 1075-1083, badge 177-185): All Chats wears none; a folder counts its unread conversations,
     *  blue while one of them is not muted; All Chats says All when the names do not fit. */
    fun tabs(c: Context): List<FolderTabs.Tab> {
        val live = live()
        val archived = archived()
        val known = contacts()
        return folders.map { f ->
            val rows = if (f.isAll) emptyList() else rows(f, live, archived, known)
            val name = f.shownTitle(c)
            FolderTabs.Tab(f.id, name, if (f.isAll) c.getString(R.string.fl_all) else name, rows.count { it.unread }, rows.any { it.unread && !it.muted })
        }
    }

    /** The folders as a copy carries them (iOS seedCard «d:»): the vault's JSON as it stands; nothing while the person never changed them. */
    fun carried(): ByteArray? = if (DeviceVault.has(KEY)) DeviceVault.get(KEY) else null

    /** A copy laid (iOS layCard «d:», not a union -- SeedScope.unionKeys): the copy's folders replace these, and the tabs read them again. */
    fun lay(raw: ByteArray) {
        if (!DeviceVault.set(KEY, raw)) return
        synchronized(lock) { held = null }
        tell()
    }
}

/**
 * OUR BOT (iOS MTBot, MTChatFolders.swift:188-206, the author's word 17.10.2026 18:4x MSK: «a category Bots, and our bot there»): Montana's
 * bot, the door to the wallet and to Montana as its Mini App. A row of the Bots folder and of All Chats; a tap opens the bot where it lives --
 * it speaks no letter here and keeps no conversation on this phone.
 */
object FolderBot {
    const val ROW = "bot:MTBusiness_bot"                     // NOT-UI: iOS MTBot.row, the bot's name in a folder's lists
    const val NAME = "MTBusiness_bot"                        // the name the bot claimed where it lives (iOS MTBot.name), never translated
    private const val LINK = "https://t.me/MTBusiness_bot"   // iOS MTBot.link
    private var picture: Bitmap? = null

    /** Where it lives: the system's own road for the link (iOS UIApplication.open) -- its app, or the browser. */
    fun open(act: MainActivity) { runCatching { act.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(LINK))) } }

    /** Its face (iOS MTChatFace(face: montanaRoomFace), the asset IconGlassPreview in the dark appearance): the app's glass in the circle. */
    fun face(c: Context, side: Int, rim: Boolean = false): View = FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.BLACK) }
        outlineProvider = object : ViewOutlineProvider() { override fun getOutline(v: View, o: Outline) = o.setOval(0, 0, v.width, v.height) }
        clipToOutline = true
        addView(ImageView(c).apply { setImageBitmap(picture(c)); scaleType = ImageView.ScaleType.CENTER_CROP }, FrameLayout.LayoutParams(MATCH, MATCH))
        if (rim) foreground = c.rim(0.45f)
        layoutParams = LinearLayout.LayoutParams(c.dp(side), c.dp(side))
    }
    private fun picture(c: Context): Bitmap? = picture ?: BitmapFactory.decodeResource(c.resources, R.drawable.icon_glass_dark)?.also { picture = it }
}

/**
 * OUR BOT'S LINE IN THE CHATS (iOS MTBot.model 196-201, drawn by ChatRow in the App Library's measure): its glass face with the rim every face
 * of the list wears, its name, «bot» under it; no hour, no count, no swipe and no menu (MontanaChatsList.swift:790, 1025-1028); a tap opens it
 * where it lives -- while the list selects, it is not chosen (rowTapped 802-806).
 */
fun folderBotRow(act: MainActivity, selecting: Boolean): View {
    val c: Context = act
    val row = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(18), 0, dp(18), 0)
        minimumHeight = dp(72)
        addView(FolderBot.face(c, 48, rim = true), lp(dp(48), dp(48)).apply { marginEnd = dp(16) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.text(FolderBot.NAME, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
            }, lp(MATCH, dp(22)))
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.text(c.getString(R.string.fl_bot), 16f, MT.gray).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
            }, lp(MATCH, dp(20)).apply { topMargin = dp(4) })
        }, lp(0, WRAP, 1f))
    }
    if (!selecting) return row.apply { pressable { FolderBot.open(act) } }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), 0, 0, 0)
        addView(FrameLayout(c).apply { background = c.rounded(Color.TRANSPARENT, 12, MT.gray) }, lp(dp(24), dp(24)))
        addView(row, lp(0, WRAP, 1f))
    }
}

/** A FOLDER NO CONVERSATION MATCHES (iOS folderEmpty, MontanaChatsList.swift:1124-1134): the folder 44 in the secondary grey, the headline,
 *  the words under it -- deaf to the finger; a hold on its tab edits it. */
fun folderEmpty(c: Context): View = c.vstack(Gravity.CENTER_HORIZONTAL) {
    setPadding(dp(32), dp(32), dp(32), dp(32))
    addView(c.icon(R.drawable.ic_folder, MT.secondary, 46), lp(dp(46), dp(46)))
    gap(8)
    addView(c.text(c.getString(R.string.fl_empty), 17f, Color.WHITE, bold = true, center = true), lp())
    gap(8)
    addView(c.text(c.getString(R.string.fl_empty_note), 15f, MT.secondary, center = true), lp())
}

// ─────────────────────────── the tabs over the chats (iOS MTFolderTabs) ───────────────────────────

/**
 * THE FOLDERS' TABS (iOS MTFolderTabs, MTChatFolders.swift:208-300; the author's words 17.10.2026 18:4x MSK: «the groups and the channels one
 * to one as in the reference»): one glass capsule the page's width, 44 high, corner 22; the names from its left edge, 14 medium white, each
 * name 10 from its sides and 6 from the next, never narrower than 44; the chosen one on a lens of white 0.16, 36 high, that slides to the next
 * in a quarter of a second; each name followed by its badge -- the folder's unread conversations, 14 on a capsule of 18, blue while one of
 * them is loud or the tab is chosen, grey otherwise. All Chats wears none and says All when the names do not fit; then the strip scrolls under
 * the finger, the chosen tab brought to its centre. A hold on a tab is the folder's menu.
 */
class FolderTabs(private val act: MainActivity) : FrameLayout(act) {
    data class Tab(val id: String, val title: String, val short: String, val unread: Int, val loud: Boolean)

    var onPick: (String) -> Unit = {}
    var onMenu: (String, View) -> Unit = { _, _ -> }
    private var tabs: List<Tab> = emptyList()
    private var chosen: String? = null
    private var short = false
    private var slide = false          // the next placing moves the lens: the chosen changed by the person's hand
    private var center = true          // the next placing brings the chosen to the strip's middle (iOS onAppear, onChange of chosen)
    private var centerSlides = false
    private val medium = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    private val lensPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(41, 255, 255, 255) }   // iOS white 0.16
    private var lensL = 0f
    private var lensR = 0f
    private var aimL = 0f
    private var aimR = 0f
    private var lensRun: ValueAnimator? = null
    private var scrollRun: ValueAnimator? = null

    /** The names in their row, the lens drawn under them (iOS matchedGeometryEffect «lens»). */
    private val row: LinearLayout = object : LinearLayout(act) {
        override fun dispatchDraw(canvas: Canvas) {
            if (lensL < lensR) {
                val h = dp(36).toFloat()
                val top = (height - h) / 2f
                canvas.drawRoundRect(RectF(lensL, top, lensR, top + h), h / 2f, h / 2f, lensPaint)
            }
            super.dispatchDraw(canvas)
        }
        override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
            super.onLayout(changed, l, t, r, b)
            place()
        }
    }
    private val strip: HorizontalScrollView = object : HorizontalScrollView(act) {
        override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
            // a strip that scrolls keeps its stroke (iOS ScrollView under the finger); from one that does not, the pages turn as before
            if (e.actionMasked == MotionEvent.ACTION_DOWN && (canScrollHorizontally(1) || canScrollHorizontally(-1))) parent?.requestDisallowInterceptTouchEvent(true)
            return super.onInterceptTouchEvent(e)
        }
    }

    init {
        background = capsule(this)
        clipToOutline = true
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER_VERTICAL or Gravity.START
        row.setPadding(dp(4), 0, dp(4), 0)
        strip.isHorizontalScrollBarEnabled = false
        strip.isFillViewport = true
        strip.addView(row, LayoutParams(WRAP, MATCH))
        addView(strip, LayoutParams(MATCH, MATCH))
    }

    /** The tabs as they stand; `animated` -- the chosen moved by the person's hand: the lens slides and the strip scrolls. */
    fun show(next: List<Tab>, chosenId: String?, animated: Boolean) {
        val s = 0 < width && width < whole(next)
        // the same tabs stand as they are: a letter that changes nothing on the strip takes no tap from under the finger
        if (next == tabs && chosenId == chosen && s == short && row.childCount == next.size) return
        if (chosenId != chosen) { slide = animated && lensL < lensR; center = true; centerSlides = animated && lensL < lensR }
        tabs = next
        chosen = chosenId
        short = s
        build()
    }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        val s = 0 < w && w < whole(tabs)
        center = true
        centerSlides = false
        if (s != short) { short = s; post { build() } }
    }

    /** The strip's width with every name whole (iOS width 251-263), by the platform's own measure of the words. */
    private fun whole(ts: List<Tab>): Int {
        fun px(sp: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics)
        val names = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = px(14f); typeface = medium }
        val counts = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = px(14f) }
        var sum = dp(8).toFloat()
        for (t in ts) {
            var inner = ceil(names.measureText(t.title))
            if (0 < t.unread) inner += dp(4) + max(dp(18).toFloat(), ceil(counts.measureText(t.unread.toString())) + dp(8))
            sum += max(dp(44).toFloat(), inner + dp(20))
        }
        return (sum + max(0, ts.size - 1) * dp(6)).toInt()
    }

    private fun build() {
        row.removeAllViews()
        tabs.forEachIndexed { i, t ->
            row.addView(label(t).apply {
                tag = t.id
                isSelected = t.id == chosen
                pressable { onPick(t.id) }
                setOnLongClickListener { onMenu(t.id, this); true }
            }, LinearLayout.LayoutParams(WRAP, MATCH).apply { if (0 < i) marginStart = dp(6) })
        }
    }

    /** A tab's own words (iOS tab 265-299): the name, and its badge 4 after it. */
    private fun label(t: Tab): LinearLayout = LinearLayout(act).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(dp(10), 0, dp(10), 0)
        minimumWidth = dp(44)
        addView(TextView(act).apply {
            text = if (short) t.short else t.title   // USER-DATA: a folder's own name
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.WHITE)
            typeface = medium
            maxLines = 1
            includeFontPadding = false
        }, LinearLayout.LayoutParams(WRAP, WRAP))
        if (0 < t.unread) addView(TextView(act).apply {
            text = t.unread.toString()   // USER-DATA: a count
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.WHITE)
            maxLines = 1
            includeFontPadding = false
            gravity = Gravity.CENTER
            setPadding(dp(4), 0, dp(4), 0)
            minWidth = dp(18)
            minHeight = dp(18)
            background = GradientDrawable().apply { cornerRadius = dp(9).toFloat(); setColor(if (t.loud || t.id == chosen) SysColor.blue else MT.gray) }
        }, LinearLayout.LayoutParams(WRAP, WRAP).apply { marginStart = dp(4) })
    }

    /** The tab lifted for its menu (iOS .contextMenu's preview): its words on the strip's own glass, the lens where it is the chosen one. */
    fun lifted(id: String): View? {
        val t = tabs.firstOrNull { it.id == id } ?: return null
        return FrameLayout(act).apply {
            background = capsule(this)
            setPadding(dp(4), 0, dp(4), 0)
            minimumHeight = dp(44)
            addView(label(t).apply {
                if (t.id == chosen) background = GradientDrawable().apply { cornerRadius = dp(18).toFloat(); setColor(Color.argb(41, 255, 255, 255)) }
            }, LayoutParams(WRAP, dp(36), Gravity.CENTER_VERTICAL))
        }
    }

    /** The lens under the chosen name: slid there when the hand chose it, else stood there; the chosen brought to the middle when it moved. */
    private fun place() {
        val v = (0 until row.childCount).map { row.getChildAt(it) }.firstOrNull { it.tag == chosen }
        if (v == null) { lensRun?.cancel(); lensL = 0f; lensR = 0f; row.invalidate(); return }
        aimL = v.left.toFloat()
        aimR = v.right.toFloat()
        if (slide) {
            slide = false
            val fromL = lensL
            val fromR = lensR
            lensRun?.cancel()
            lensRun = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 250   // iOS withAnimation(.easeInOut(duration: 0.25))
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { a -> val f = a.animatedValue as Float; lensL = fromL + (aimL - fromL) * f; lensR = fromR + (aimR - fromR) * f; row.invalidate() }
                start()
            }
        } else if (lensRun?.isRunning != true) { lensL = aimL; lensR = aimR; row.invalidate() }
        if (center) { center = false; bring(v, centerSlides) }
    }

    /** The chosen tab to the strip's centre (iOS proxy.scrollTo(chosen, anchor: .center)), sliding when the hand chose it. */
    private fun bring(v: View, animated: Boolean) {
        val most = (row.width - strip.width).coerceAtLeast(0)
        val to = ((v.left + v.right) / 2 - strip.width / 2).coerceIn(0, most)
        scrollRun?.cancel()
        if (!animated || strip.scrollX == to) { strip.scrollTo(to, 0); return }
        scrollRun = ValueAnimator.ofInt(strip.scrollX, to).apply {
            duration = 250
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { strip.scrollTo(it.animatedValue as Int, 0) }
            start()
        }
    }

    private companion object {
        /** The strip's glass (iOS mtGlassPill(corner: 22) over MTGlassKit.plate): the app's one tone of glass with its light rim (glassPlate). */
        fun capsule(v: View) = GradientDrawable().apply {
            cornerRadius = v.dp(22).toFloat()
            setColor(GLASS_TONE)
            setStroke(v.dp(1).coerceAtMost(3), Color.argb(46, 255, 255, 255))
        }
    }
}

// ─────────────────────────── a tab's menu (iOS folderMenu) ───────────────────────────

/** The way in from a tab's menu (iOS MTChatFolders.Opening 113-118): the folders' page opens on the folder named, at once at its chats, or on
 *  the order. */
class FolderOpening(val folder: String? = null, val addChats: Boolean = false, val reorder: Boolean = false)

/** A TAB'S MENU OPENS THE FOLDERS (iOS openFolders, MontanaChatsList.swift:1117-1120, and the overlay page .folders, ContentView.swift:
 *  2417-2421): the folders' page over everything, its cross top left. */
fun openFolders(act: MainActivity, o: FolderOpening) = act.push { close -> folderSettingsPage(act, close, o) }

/**
 * A FOLDER'S MENU ON A HOLD OF ITS TAB (iOS folderMenu, MontanaChatsList.swift:1085-1116 at 2235): a folder is edited, given chats, read and
 * muted at once, or taken away; All Chats opens the folders' page; and the tabs' order, when there are two tabs to order. On the app's own
 * cloud of a hold (ChatList.holdMenu, iOS MTPersonMenu): the tab lifted where it stood, the deeds hanging under it from its nearer edge, the
 * platform's thick line between their groups.
 */
fun folderMenu(act: MainActivity, held: View, lifted: View?, id: String, onRemoved: (String) -> Unit) {
    val c: Context = act
    val f = ChatFolders.folder(id)
    val groups = ArrayList<List<Deed>>()
    if (f != null && !f.isAll) {
        val rows = ChatFolders.rows(f, ChatFolders.live(), ChatFolders.archived(), ChatFolders.contacts()).filter { it.ref != FolderBot.ROW }
        val deeds = ArrayList<Deed>()
        deeds += Deed(R.string.fl_edit_folder, R.drawable.ic_pencil) { openFolders(act, FolderOpening(folder = id)) }
        deeds += Deed(R.string.fl_add_chats, R.drawable.ic_plus) { openFolders(act, FolderOpening(folder = id, addChats = true)) }
        if (rows.any { it.unread }) deeds += Deed(R.string.fl_read_all, R.drawable.ic_checkmark_message) { rows.filter { it.unread }.forEach { markRead(it) } }
        if (rows.isNotEmpty()) {
            val muted = rows.all { it.muted }
            deeds += Deed(if (muted) R.string.fl_unmute_all else R.string.fl_mute_all, if (muted) R.drawable.ic_bell else R.drawable.ic_bell_slash) {
                rows.filter { it.muted == muted }.forEach { ChatMarks.toggleMute(it.ref) }
            }
        }
        deeds += Deed(R.string.fl_remove, R.drawable.ic_delete, red = true) { askRemove(act, f, onRemoved) }
        groups += deeds
    } else groups += listOf(Deed(R.string.fl_edit_folders, R.drawable.ic_pencil) { openFolders(act, FolderOpening()) })
    if (1 < ChatFolders.folders.size) groups += listOf(Deed(R.string.fl_reorder, R.drawable.ic_arrow_left_right) { openFolders(act, FolderOpening(reorder = true)) })

    lateinit var leave: (() -> Unit) -> Unit
    val line = Color.argb(77, 142, 142, 147)   // iOS MTMenuDivider: the gray at three tenths
    val plate = c.vstack(Gravity.NO_GRAVITY) {
        background = c.rounded(Color.argb(235, 44, 44, 46), 16, Color.argb(26, 255, 255, 255))
        clipToOutline = true
    }
    groups.forEachIndexed { gi, g ->
        if (0 < gi) plate.addView(View(c).apply { setBackgroundColor(Color.argb(64, 0, 0, 0)) }, lp(MATCH, c.dp(8)))   // the platform's Divider() in a menu
        g.forEachIndexed { i, d ->
            if (0 < i) plate.addView(View(c).apply { setBackgroundColor(line) }, lp(MATCH, 1))
            plate.addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(14), dp(11), dp(14), dp(11))
                addView(c.text(c.getString(d.words), 16f, if (d.red) SysColor.red else Color.WHITE), lp(0, WRAP, 1f))
                addView(c.icon(d.glyph, if (d.red) SysColor.red else Color.argb(204, 255, 255, 255), 20), lp(dp(20), dp(20)))
                pressable { leave(d.work) }
            }, lp())
        }
    }
    val at = IntArray(2).also { held.getLocationOnScreen(it) }
    val screen = c.resources.displayMetrics.widthPixels
    val pad = c.dp(12)
    val plateWidth = c.dp(250)
    // from the tab's leading edge on the screen's left half, to its trailing edge on the right half (iOS context menus)
    val left = if (at[0] + held.width / 2 < screen / 2) at[0] else at[0] + held.width - plateWidth
    val cloud = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(pad, pad, pad, pad)
        if (lifted != null) { addView(lifted, lp(WRAP, WRAP).apply { marginStart = (at[0] - pad).coerceAtLeast(0) }); gap(12) }
        addView(plate, lp(plateWidth, WRAP).apply { marginStart = (left - pad).coerceIn(0, (screen - 2 * pad - plateWidth).coerceAtLeast(0)) })
    }
    leave = showCloud(act, cloud, at[1])
}

/** A conversation read here, the correspondent told nothing (iOS store.markRead(tellPeer: false), MontanaChatStore.swift:3106-3131): its
 *  count, the hand's mark and its banners go. */
private fun markRead(r: FolderRow) {
    val ch = r.chat ?: return
    if (0 < ch.unread) Book.edit(ch.ref) { it.unread = 0 }
    ChatMarks.opened(ch.ref)
    Notify.clear(ch.ref)
}

/** «Remove %@?» (iOS removingFolder's alert, MontanaChatsList.swift:1054-1063, 1121-1123): the folder goes, the chats stay. */
private fun askRemove(act: MainActivity, f: ChatFolder, onRemoved: (String) -> Unit) {
    val d = AlertDialog.Builder(act).setTitle(act.getString(R.string.fl_remove_q, f.shownTitle(act)))   // USER-DATA: the folder's own name
        .setMessage(R.string.fl_remove_note)
        .setPositiveButton(R.string.fl_remove) { _, _ -> onRemoved(f.id); ChatFolders.remove(f.id) }
        .setNegativeButton(R.string.cancel, null)
        .show()
    d.getButton(AlertDialog.BUTTON_POSITIVE)?.setTextColor(SysColor.red)   // the destructive word in red (iOS role: .destructive)
}

// ─────────────────────────── the folders' page (iOS MTFolderSettingsPage) ───────────────────────────

/** A folder the reference recommends (iOS Suggestion 312-317). */
private class FolderSuggestion(val folder: ChatFolder, val title: Int, val words: Int)

/** What the reference recommends (iOS suggestions 318-338): the unread, the personal chats, and each first folder taken away. */
private fun suggestions(): List<FolderSuggestion> = listOf(
    FolderSuggestion(ChatFolder("", kinds = FolderKind.values().toList(), leaves = listOf(FolderLeave.READ, FolderLeave.ARCHIVED)), R.string.fl_unread, R.string.fl_unread_words),
    FolderSuggestion(ChatFolder("", kinds = listOf(FolderKind.CONTACTS, FolderKind.NON_CONTACTS)), R.string.fl_personal, R.string.fl_personal_words),
    FolderSuggestion(ChatFolder("", preset = FolderKind.GROUPS, kinds = listOf(FolderKind.GROUPS)), R.string.app_groups, R.string.fl_groups_words),
    FolderSuggestion(ChatFolder("", preset = FolderKind.CHANNELS, kinds = listOf(FolderKind.CHANNELS)), R.string.app_channels, R.string.fl_channels_words),
    FolderSuggestion(ChatFolder("", preset = FolderKind.BOTS, kinds = listOf(FolderKind.BOTS)), R.string.fl_bots, R.string.fl_bots_words))

/** A new folder's name as the iPhone draws it (iOS UUID().uuidString): the same form on both phones. */
private fun folderId() = UUID.randomUUID().toString().uppercase()

/**
 * THE FOLDERS' PAGE (iOS MTFolderSettingsPage, MTChatFolders.swift:302-464): what folders are for, the way to a new one, the folders with the
 * count of their chats (All Chats among them, never taken away), the folders the reference recommends. The pencil turns the list to its
 * editing -- the order by the handles, a folder away by the minus and its «Delete» -- and the checkmark ends it; a stroke from a folder's right
 * takes it away as the platform's list does. From Settings the page has the back chevron; from a tab's menu, the cross (`opening`).
 */
fun folderSettingsPage(act: MainActivity, onClose: () -> Unit, opening: FolderOpening? = null): View {
    val c: Context = act
    var editing = opening?.reorder == true
    var confirming: String? = null   // the folder whose «Delete» its minus uncovered
    var carrying = false             // a folder is being carried by its handle
    var stale = false                // something changed meanwhile: drawn once it is put down
    lateinit var body: LinearLayout
    lateinit var draw: () -> Unit
    val mark = c.icon(R.drawable.ic_pencil, Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        pressable { editing = !editing; confirming = null; draw() }
    }
    val page = settingsPage(act, c.getString(R.string.fl_folders), onClose, cross = opening != null, trailing = mark) { body = this }
    fun openEditor(f: ChatFolder, addChats: Boolean) = act.push { close -> folderEditPage(act, f, ChatFolders.folder(f.id) == null, addChats, close) }
    // what the page draws, in one word: a letter that moves no count and no folder leaves the page -- and a stroke on it -- as they are
    fun print(): String {
        val pool = ChatFolders.live()
        val known = ChatFolders.contacts()
        return ChatFolders.folders.joinToString("\n") { f -> f.json().toString() + "#" + f.shownTitle(c) + "#" + (if (f.isAll) 0 else ChatFolders.rows(f, pool, emptyList(), known).size) }
    }
    var drawn = ""

    draw = draw@{
        stale = false
        drawn = print()
        mark.setImageResource(if (editing) R.drawable.ic_check else R.drawable.ic_pencil)   // iOS MontanaDoneMark / MontanaBarMark «pencil»
        mark.contentDescription = c.getString(if (editing) R.string.pe_done else R.string.edit)
        body.removeAllViews()
        // WHAT FOLDERS ARE FOR (iOS 345-358): the folder 64 white over the words, on the page's own ground
        body.addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
            setPadding(dp(16), dp(18), dp(16), dp(6))
            addView(c.icon(R.drawable.ic_folder_fill, Color.WHITE, 68), lp(dp(68), dp(68)))
            gap(14)
            addView(c.text(c.getString(R.string.fl_intro), 15f, MT.secondary, center = true), lp())
        }, lp())
        // THE FOLDERS (iOS 359-382): «Create a Folder», then every folder with the count of its chats
        body.addView(sectionHead(c, c.getString(R.string.fl_folders)), lp())
        val plate = c.plate { clipToOutline = true }
        plate.addView(c.text(c.getString(R.string.fl_create), 17f, SysColor.blue).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), 0, dp(14), 0)
            minimumHeight = dp(48)
            pressable { openEditor(ChatFolder(folderId()), false) }
        }, lp())
        val folders = ChatFolders.folders
        val pool = ChatFolders.live()
        val known = ChatFolders.contacts()
        val items = ArrayList<View>()
        folders.forEachIndexed { index, f ->
            val count = if (f.isAll) 0 else ChatFolders.rows(f, pool, emptyList(), known).size
            val content = c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), 0, dp(14), 0)
                minimumHeight = dp(48)
                // the platform's delete control (iOS List edit mode): All Chats has none, it is never taken away
                if (editing && !f.isAll) addView(c.duoGlyph(R.drawable.ic_minus_circle_fill, SysColor.red, 24).apply {
                    rotation = if (confirming == f.id) 90f else 0f
                    contentDescription = c.getString(R.string.cl_delete)
                    pressable { confirming = if (confirming == f.id) null else f.id; draw() }
                }, lp(dp(24), dp(24)).apply { marginEnd = dp(14) })
                addView(c.text(f.shownTitle(c), 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a folder's name
                if (0 < count) addView(c.text(count.toString(), 17f, MT.secondary), lp(WRAP, WRAP).apply { marginStart = dp(8) })   // USER-DATA: a count
                if (!f.isAll) addView(c.icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18), lp(dp(18), dp(18)).apply { marginStart = dp(6) })
                if (!editing && !f.isAll) pressable { openEditor(f, false) }
            }
            val frame = FrameLayout(c).apply { addView(content, FrameLayout.LayoutParams(MATCH, WRAP)) }
            val item = c.vstack(Gravity.NO_GRAVITY) {
                addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })
                addView(if (!editing && !f.isAll) SwipeDelete(c, frame) { ChatFolders.remove(f.id) } else frame, lp())
            }
            if (editing) {
                if (confirming == f.id) frame.addView(c.text(c.getString(R.string.cl_delete), 17f, Color.WHITE).apply {
                    gravity = Gravity.CENTER
                    setPadding(dp(18), 0, dp(18), 0)
                    setBackgroundColor(SysColor.red)
                    pressable { confirming = null; ChatFolders.remove(f.id) }
                }, FrameLayout.LayoutParams(WRAP, MATCH, Gravity.END))
                else content.addView(c.icon(R.drawable.ic_line_3_horizontal, MT.gray, 22).apply {
                    // THE ORDER BY THE HANDLE (iOS List .onMove): the folder lifts under the finger, the others make way, it lands where let go
                    setOnTouchListener(object : View.OnTouchListener {
                        var startY = 0f
                        var to = index
                        override fun onTouch(v: View, e: MotionEvent): Boolean {
                            when (e.actionMasked) {
                                MotionEvent.ACTION_DOWN -> {
                                    v.parent?.requestDisallowInterceptTouchEvent(true)
                                    carrying = true
                                    startY = e.rawY
                                    to = index
                                    item.setBackgroundColor(GLASS_TONE)   // the folder lifted covers the ones it passes
                                    item.elevation = c.dp(8).toFloat()
                                }
                                MotionEvent.ACTION_MOVE -> {
                                    val h = item.height.toFloat()
                                    val dy = (e.rawY - startY).coerceIn((items.first().top - item.top).toFloat(), (items.last().bottom - item.bottom).toFloat())
                                    item.translationY = dy
                                    val mid = item.top + dy + h / 2f
                                    to = index
                                    items.forEachIndexed { j, o ->
                                        if (j == index) return@forEachIndexed
                                        val oMid = (o.top + o.bottom) / 2f
                                        val shift = if (index < j && oMid < mid) { to++; -h } else if (j < index && mid < oMid) { to--; h } else 0f
                                        if (o.tag != shift) { o.tag = shift; o.animate().translationY(shift).setDuration(150).start() }
                                    }
                                }
                                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                                    carrying = false
                                    items.forEach { o -> o.animate().cancel(); o.translationY = 0f; o.tag = null }
                                    item.elevation = 0f
                                    item.background = null
                                    if (to != index) {
                                        plate.removeView(item)
                                        plate.addView(item, 1 + to)   // laid where it was let go at once; the page is drawn again by the store's word
                                        ChatFolders.move(index, to)
                                    } else if (stale) draw()
                                }
                            }
                            return true
                        }
                    })
                }, lp(c.dp(22), c.dp(22)).apply { marginStart = c.dp(12) })
            }
            items.add(item)
            plate.addView(item, lp())
        }
        body.addView(plate, lp())
        body.addView(sectionFoot(c, c.getString(R.string.fl_folders_footer)), lp())
        // RECOMMENDED FOLDERS (iOS 383-390, suggestionRow 441-463): those the person has not got, each with the plus white on blue
        val offered = suggestions().filter { s -> folders.none { it.holdsAlike(s.folder) } }
        if (offered.isEmpty()) return@draw
        body.addView(sectionHead(c, c.getString(R.string.fl_recommended)), lp())
        body.addView(c.plate {
            offered.forEachIndexed { i, s ->
                if (0 < i) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(16), dp(8), dp(14), dp(8))
                    minimumHeight = dp(48)
                    addView(c.vstack(Gravity.NO_GRAVITY) {
                        addView(c.text(c.getString(s.title), 17f, Color.WHITE), lp())
                        addView(c.text(c.getString(s.words), 13f, MT.secondary), lp().apply { topMargin = dp(2) })
                    }, lp(0, WRAP, 1f))
                    addView(c.duoGlyph(R.drawable.ic_plus_circle_fill, SysColor.blue, 27), lp(dp(27), dp(27)).apply { marginStart = dp(12) })
                    contentDescription = c.getString(s.title)
                    pressable {
                        // a recommendation of a first folder's kind keeps following the language; the others take their name now (iOS 442-446)
                        val nf = s.folder.copy(id = folderId())
                        ChatFolders.put(if (nf.preset == null) nf.copy(title = c.getString(s.title)) else nf)
                    }
                }, lp())
            }
        }, lp())
    }
    draw()
    // the book and the marks speak from any thread (ChatMarks.forget rides buryChat's own): the page is drawn on the screen's
    val again: () -> Unit = { act.onMain { if (carrying) stale = true else if (print() != drawn) draw() } }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { ChatFolders.listen(again); Book.listen(again); ChatMarks.listen(again) }
        override fun onViewDetachedFromWindow(v: View) { ChatFolders.unlisten(again); Book.unlisten(again); ChatMarks.unlisten(again) }
    })
    // A TAB'S MENU ASKED FOR THIS PAGE (iOS take 417-423): the folder it named, at once at its chats
    opening?.folder?.let { id -> ChatFolders.folder(id)?.let { f -> page.post { openEditor(f, opening.addChats) } } }
    return page
}

// ─────────────────────────── a folder's page (iOS MTFolderEditPage) ───────────────────────────

/**
 * A FOLDER'S PAGE (iOS MTFolderEditPage, MTChatFolders.swift:466-598): its name, the chats it takes -- kinds and conversations -- and the chats
 * it leaves out -- states and conversations; each line goes by the platform's swipe. The checkmark keeps it, open only with a name and
 * something taken; the cross leaves it, asking first when something was changed -- and the system's back asks as the cross does (the iPhone
 * hides its back there).
 */
fun folderEditPage(act: MainActivity, folder: ChatFolder, isNew: Boolean, addChats: Boolean, onClose: () -> Unit): View {
    val c: Context = act
    val original = folder
    var draft = folder
    val was = if (isNew) "" else folder.shownTitle(c)
    val field = EditText(c).apply {
        setText(was)   // USER-DATA: the folder's own name
        hint = c.getString(R.string.fl_name)
        setTextColor(Color.WHITE)
        setHintTextColor(MT.gray)
        textSize = 17f
        background = null
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        imeOptions = EditorInfo.IME_ACTION_DONE
        setPadding(0, 0, 0, 0)
    }
    // iOS trimmingCharacters(in: .whitespaces): the spaces and the tab, never a letter
    fun typed() = field.text.toString().trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
    fun changed() = draft != original || typed() != was
    fun canKeep() = typed().isNotEmpty() && draft.takesAnything
    fun keysAway() = c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(field.windowToken, 0)
    val done = c.icon(R.drawable.ic_check, Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        contentDescription = c.getString(R.string.pe_done)
    }
    fun refreshDone() { val on = canKeep(); done.isEnabled = on; done.alpha = if (on) 1f else 0.4f }
    done.pressable {
        if (!canKeep()) return@pressable
        // A FIRST FOLDER KEEPS FOLLOWING THE PERSON'S LANGUAGE WHILE ITS NAME IS THE ONE IT WAS GIVEN (iOS keep 552-563)
        val f = if (!isNew && original.title.isEmpty() && typed() == original.shownTitle(c)) draft.copy(title = "")
                else draft.copy(title = typed(), preset = null)   // USER-DATA: the folder's own name
        ChatFolders.put(f)
        keysAway()
        onClose()
    }
    lateinit var page: View
    fun leave() {
        if (!changed()) { keysAway(); onClose(); return }
        if (page.translationX != 0f) page.animate().translationX(0f).setDuration(150).start()   // a back the finger began stands the page back
        val d = AlertDialog.Builder(act).setMessage(R.string.fl_discard_q)
            .setPositiveButton(R.string.fl_discard) { _, _ -> keysAway(); onClose() }
            .setNegativeButton(R.string.cancel, null)
            .show()
        d.getButton(AlertDialog.BUTTON_POSITIVE)?.setTextColor(SysColor.red)   // iOS role: .destructive
    }
    val lists = c.vstack(Gravity.NO_GRAVITY)
    lateinit var drawLists: () -> Unit
    fun pick(taking: Boolean) {
        keysAway()
        act.push { close -> folderChatPicker(act, taking, { draft }, { draft = it; drawLists(); refreshDone() }, close) }
    }
    drawLists = {
        lists.removeAllViews()
        val pool = ChatFolders.live().associateBy { it.ref }
        fun chat(ref: String) = pool[ref]?.chat
        // INCLUDED CHATS (iOS 502-514): «Add Chats», the kinds taken, the conversations taken
        lists.addView(sectionHead(c, c.getString(R.string.fl_included)), lp())
        lists.addView(c.plate {
            clipToOutline = true
            addView(addLine(c, R.string.fl_add_chats, R.drawable.ic_plus_circle_fill) { pick(true) }, lp())
            for (k in draft.kinds) {
                folderLine(60)
                addView(SwipeDelete(c, kindLine(c, k.glyph, k.tint, c.getString(k.title))) { draft = draft.copy(kinds = draft.kinds - k); drawLists(); refreshDone() }, lp())
            }
            for (n in draft.chats) {
                folderLine(60)
                addView(SwipeDelete(c, chatLine(c, n, chat(n), 32)) { draft = draft.copy(chats = draft.chats - n); drawLists(); refreshDone() }, lp())
            }
        }, lp())
        lists.addView(sectionFoot(c, c.getString(R.string.fl_included_footer)), lp())
        // EXCLUDED CHATS (iOS 515-527): «Add Chats to Exclude», the states left out, the conversations left out
        lists.addView(sectionHead(c, c.getString(R.string.fl_excluded)), lp())
        lists.addView(c.plate {
            clipToOutline = true
            addView(addLine(c, R.string.fl_exclude_add, R.drawable.ic_minus_circle_fill) { pick(false) }, lp())
            for (l in draft.leaves) {
                folderLine(60)
                addView(SwipeDelete(c, kindLine(c, l.glyph, l.tint, c.getString(l.title))) { draft = draft.copy(leaves = draft.leaves - l); drawLists(); refreshDone() }, lp())
            }
            for (n in draft.excluded) {
                folderLine(60)
                addView(SwipeDelete(c, chatLine(c, n, chat(n), 32)) { draft = draft.copy(excluded = draft.excluded - n); drawLists(); refreshDone() }, lp())
            }
        }, lp())
        lists.addView(sectionFoot(c, c.getString(R.string.fl_excluded_footer)), lp())
    }
    page = settingsPage(act, c.getString(if (isNew) R.string.fl_new else R.string.fl_edit_folder), { leave() }, cross = true, trailing = done) {
        // THE NAME (iOS 495-501)
        addView(sectionHead(c, c.getString(R.string.fl_name)), lp())
        addView(c.plate {
            addView(c.hstack {
                setPadding(dp(16), 0, dp(16), 0)
                minimumHeight = dp(48)
                addView(field, lp(0, WRAP, 1f))
            }, lp())
        }, lp())
        addView(lists, lp())
    }
    drawLists()
    refreshDone()
    field.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: Editable?) { refreshDone() }
    })
    // the system's back is the cross (asked once the page stands, after the slide that set its own); a tab's «Add Chats» opens the picker at once
    page.post {
        act.back = { leave() }
        if (addChats) pick(true)
    }
    return page
}

// ─────────────────────────── the chats of a folder, chosen (iOS MTFolderChatPicker) ───────────────────────────

/**
 * THE CHATS OF A FOLDER, CHOSEN (iOS MTFolderChatPicker, MTChatFolders.swift:600-710): the kinds first -- or the states, for the chats left
 * out -- then every conversation and our bot, each a line with the platform's tick; the search narrows the conversations and hides the
 * kinds; the checkmark returns to the folder. Every tick is the folder's at once, as the iPhone binds it.
 */
fun folderChatPicker(act: MainActivity, taking: Boolean, get: () -> ChatFolder, set: (ChatFolder) -> Unit, onClose: () -> Unit): View {
    val c: Context = act
    val pool = ChatFolders.live()   // iOS pool 610: the list's own rows, and our bot
    val list = c.vstack(Gravity.NO_GRAVITY)
    val field = EditText(c).apply {
        hint = c.getString(R.string.search)
        setHintTextColor(MT.gray)
        setTextColor(Color.WHITE)
        textSize = 17f
        background = null
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT
        imeOptions = EditorInfo.IME_ACTION_SEARCH
        setPadding(0, 0, 0, 0)
    }
    fun keysAway() = c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(field.windowToken, 0)
    fun tick(on: Boolean) = c.icon(if (on) R.drawable.ic_set_check_circle else R.drawable.ic_circle, if (on) Color.WHITE else MT.secondary, 24)
    lateinit var draw: () -> Unit
    draw = {
        list.removeAllViews()
        val q = field.text.toString().trim()
        val f = get()
        if (q.isEmpty()) {
            // CHAT TYPES (iOS 627-644): the kinds a folder takes, or the states it leaves out
            list.addView(sectionHead(c, c.getString(R.string.fl_chat_types)), lp())
            list.addView(c.plate {
                if (taking) FolderKind.values().forEachIndexed { i, k ->
                    if (0 < i) folderLine(68)
                    addView(typeLine(c, k.glyph, k.tint, c.getString(k.title), tick(k in f.kinds)) {
                        set(f.copy(kinds = if (k in f.kinds) f.kinds - k else f.kinds + k)); draw()
                    }, lp())
                } else FolderLeave.values().forEachIndexed { i, l ->
                    if (0 < i) folderLine(68)
                    addView(typeLine(c, l.glyph, l.tint, c.getString(l.title), tick(l in f.leaves)) {
                        set(f.copy(leaves = if (l in f.leaves) f.leaves - l else f.leaves + l)); draw()
                    }, lp())
                }
            }, lp())
        }
        // CHATS (iOS 645-663): every conversation, its tick for the side chosen; a chat taken is never left out, and back
        list.addView(sectionHead(c, c.getString(R.string.chats)), lp())
        val shown = pool.filter { r -> q.isEmpty() || folderTitle(c, r.ref, r.chat).contains(q, ignoreCase = true) }
        list.addView(c.plate {
            shown.forEachIndexed { i, r ->
                if (0 < i) folderLine(68)
                val on = if (taking) r.ref in f.chats else r.ref in f.excluded
                addView(chatLine(c, r.ref, r.chat, 40, tick(on)).apply {
                    pressable {
                        val now = get()
                        val n = r.ref
                        set(if (taking) now.copy(excluded = now.excluded.filter { it != n }, chats = if (n in now.chats) now.chats - n else now.chats + n)
                            else now.copy(chats = now.chats.filter { it != n }, excluded = if (n in now.excluded) now.excluded - n else now.excluded + n))
                        draw()
                    }
                }, lp())
            }
        }, lp())
    }
    field.addTextChangedListener(object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: Editable?) { draw() }
    })
    field.setOnEditorActionListener { _, _, _ -> keysAway(); true }
    draw()
    // the sheet's bar (iOS navigationTitle and ToolbarItem(placement: .confirmationAction)): the title, the checkmark top right, nothing on the left
    val done = c.icon(R.drawable.ic_check, Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        contentDescription = c.getString(R.string.pe_done)
        pressable { keysAway(); onClose() }
    }
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.text(c.getString(if (taking) R.string.fl_include else R.string.fl_exclude), 17f, Color.WHITE, bold = true, center = true),
            FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        addView(done, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    // THE SEARCH ALWAYS STANDS UNDER THE TITLE (iOS .searchable(placement: .navigationBarDrawer(displayMode: .always))): the capsule of the chats'
    // own search (Home.kt SearchRow)
    val search = c.hstack {
        background = c.glassPlate()
        setPadding(dp(12), 0, dp(12), 0)
        addView(c.icon(R.drawable.ic_search, Color.rgb(230, 230, 230)), lp(dp(22), dp(22)).apply { marginEnd = dp(8) })
        addView(field, lp(0, WRAP, 1f))
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // my page's ground (iOS montanaPageGround)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(search, lp(MATCH, dp(40)).apply { setMargins(dp(16), dp(2), dp(16), dp(6)) })
            addView(ScrollView(c).apply {
                isVerticalScrollBarEnabled = false
                addView(c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), dp(32)); addView(list, lp()) })
            }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

// ─────────────────────────── the lines of the folders' pages ───────────────────────────

/** A section's words over its plate, and under it (Settings.section's own measures: iOS List header and footer). */
private fun sectionHead(c: Context, words: String) = c.text(words, 13f, MT.gray).apply { setPadding(c.dp(16), c.dp(22), c.dp(16), c.dp(6)) }
private fun sectionFoot(c: Context, words: String) = c.text(words, 12f, MT.gray).apply { setPadding(c.dp(16), c.dp(8), c.dp(16), 0) }
/** The list's separator, from the line's words (iOS List: the separator starts where the first words of the line do). */
private fun LinearLayout.folderLine(inset: Int) = addView(View(context).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(inset) })

/** A glyph of two colours (iOS .foregroundStyle(.white, tint) on plus.circle.fill and minus.circle.fill): the disc in its tint, its mark white. */
private fun Context.duoGlyph(res: Int, tint: Int, side: Int): View = FrameLayout(this).apply {
    addView(View(context).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE) } },
        FrameLayout.LayoutParams(dp(side * 0.5f), dp(side * 0.5f), Gravity.CENTER))
    addView(icon(res, tint, side), FrameLayout.LayoutParams(dp(side), dp(side), Gravity.CENTER))
}

/** A glyph white on a circle of its tint (iOS .background(tint, in: Circle())). */
private fun Context.tintedCircle(glyph: Int, tint: Int, side: Int, glyphSide: Int): View = FrameLayout(this).apply {
    background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(tint) }
    addView(icon(glyph, Color.WHITE, glyphSide), FrameLayout.LayoutParams(dp(glyphSide), dp(glyphSide), Gravity.CENTER))
}

/** A line that adds (iOS addLine 565-576): the glyph 22, white on blue, in a frame of 32, the words in blue. */
private fun addLine(c: Context, words: Int, glyph: Int, onTap: () -> Unit): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), 0, dp(14), 0)
    minimumHeight = dp(48)
    addView(FrameLayout(c).apply { addView(c.duoGlyph(glyph, SysColor.blue, 25), FrameLayout.LayoutParams(dp(25), dp(25), Gravity.CENTER)) }, lp(dp(32), dp(32)))
    gap(12)
    addView(c.text(c.getString(words), 17f, SysColor.blue), lp(0, WRAP, 1f))
    pressable(onTap)
}

/** A kind or a state of chats (iOS kindLine 578-588): its glyph 15 semibold, white on a circle of 32 in its tint, the words white. */
private fun kindLine(c: Context, glyph: Int, tint: Int, words: String): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), 0, dp(14), 0)
    minimumHeight = dp(48)
    addView(c.tintedCircle(glyph, tint, 32, 19), lp(dp(32), dp(32)))
    gap(12)
    addView(c.text(words, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
}

/** A kind or a state with its tick (iOS typeLine 681-694): the glyph 17 semibold, white on a circle of 40 in its tint. */
private fun typeLine(c: Context, glyph: Int, tint: Int, words: String, tick: View, onTap: () -> Unit): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(8), dp(14), dp(8))
    minimumHeight = dp(48)
    addView(c.tintedCircle(glyph, tint, 40, 22), lp(dp(40), dp(40)))
    gap(12)
    addView(c.text(words, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
    addView(tick, lp(dp(24), dp(24)).apply { marginStart = dp(12) })
    pressable(onTap)
}

/** A conversation's line (iOS chatLine 590-597, the picker's 646-659): its face, its name on one line, and a tick where it is chosen. */
private fun chatLine(c: Context, ref: String, chat: Chat?, side: Int, tick: View? = null): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    val v = if (32 < side) dp(8) else 0
    setPadding(dp(16), v, dp(14), v)
    minimumHeight = dp(48)
    addView(folderFace(c, ref, chat, side), lp(dp(side), dp(side)))
    gap(12)
    addView(c.text(folderTitle(c, ref, chat), 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a chat's name
    if (tick != null) addView(tick, lp(dp(24), dp(24)).apply { marginStart = dp(12) })
}

/** A row's name in the folders' pages (iOS MTFolderChatPicker.title 611-613): our bot's own, the local room's, the name on the screen. */
private fun folderTitle(c: Context, ref: String, chat: Chat?): String = when (ref) {
    FolderBot.ROW -> FolderBot.NAME
    SAVED_ROW -> c.getString(R.string.saved_messages)
    else -> (chat ?: Book.chat(ref))?.shown?.ifBlank { null } ?: c.getString(R.string.peer)   // USER-DATA: a chat's name
}

/** A row's face (iOS MTFolderChatPicker.face 614-620): our bot's glass, one's own face for the local room, the chat's own face -- the time mark
 *  where none was sent (iOS MTChatFace, AvatarCircle timeMarkWhenMissing). */
private fun folderFace(c: Context, ref: String, chat: Chat?, side: Int): View = when {
    ref == FolderBot.ROW -> FolderBot.face(c, side)
    ref == SAVED_ROW -> c.avatar(SelfFace.load(c), Prefs.userName, side)
    Book.shownFace(ref).exists() -> c.peerFace(ref, folderTitle(c, ref, chat), side)
    else -> c.timeMark(side)
}

/**
 * THE PLATFORM'S SWIPE TO DELETE (iOS List .onDelete -- the folders' page, a folder's own lines): the line slides left under the finger and
 * uncovers the red «Delete» growing with it; let go past half of it, the line stays open; a stroke past three fifths of the line deletes at
 * once; a tap on «Delete» deletes; a tap on the open line or the list's scroll closes it.
 */
class SwipeDelete(c: Context, private val content: View, private val onDelete: () -> Unit) : FrameLayout(c) {
    private val action: TextView = c.text(c.getString(R.string.cl_delete), 17f, Color.WHITE).apply {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(c.dp(18), 0, c.dp(18), 0)
        setBackgroundColor(SysColor.red)
        visibility = INVISIBLE
        setOnClickListener { settle(-this@SwipeDelete.width.toFloat(), onDelete) }
    }
    private val openWidth: Float get() = action.paint.measureText(action.text.toString()) + dp(36)
    private val slop = ViewConfiguration.get(c).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var startT = 0f
    private var decided = false
    private var dragging = false

    init {
        addView(content, LayoutParams(MATCH, WRAP))
        addView(action, LayoutParams(MATCH, MATCH))
    }

    private fun place(t: Float) {
        content.translationX = t
        action.translationX = width + t
    }

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = e.x; downY = e.y; startT = content.translationX; decided = false; dragging = false }
            MotionEvent.ACTION_MOVE -> if (!decided) {
                val dx = e.x - downX
                val dy = e.y - downY
                if (slop < abs(dx) || slop < abs(dy)) {
                    decided = true
                    if (abs(dy) < abs(dx) && (dx < 0 || startT < 0f)) {
                        dragging = true
                        downX = e.x
                        parent?.requestDisallowInterceptTouchEvent(true)
                        action.visibility = VISIBLE
                        return true
                    }
                }
            }
            // a tap on the open line closes it; a tap on «Delete» is its own
            MotionEvent.ACTION_UP -> if (startT < 0f && !decided && e.x < width + startT) { settle(0f); return true }
        }
        return false
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!dragging) {
            // a touch no child took comes here straight: the same reading of the stroke
            val took = onInterceptTouchEvent(e)
            return e.actionMasked == MotionEvent.ACTION_DOWN || took || dragging
        }
        when (e.actionMasked) {
            MotionEvent.ACTION_MOVE -> place((startT + e.x - downX).coerceIn(-width.toFloat(), 0f))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragging = false
                val t = -content.translationX
                when {
                    width * 0.6f < t -> settle(-width.toFloat(), onDelete)
                    openWidth / 2f < t -> settle(-openWidth)
                    else -> settle(0f)
                }
            }
        }
        return true
    }

    private fun settle(to: Float, then: (() -> Unit)? = null) {
        ValueAnimator.ofFloat(content.translationX, to).apply {
            duration = 200
            interpolator = DecelerateInterpolator()
            addUpdateListener { place(it.animatedValue as Float) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) {
                    if (to == 0f) action.visibility = INVISIBLE
                    then?.invoke()
                }
            })
            start()
        }
    }

    // AN OPEN LINE CLOSES WHEN THE LIST MOVES (the platform's own swipe actions close on scroll; SwipeRow's same law)
    private val onScroll = ViewTreeObserver.OnScrollChangedListener { if (content.translationX != 0f && !dragging) settle(0f) }
    override fun onAttachedToWindow() { super.onAttachedToWindow(); viewTreeObserver.addOnScrollChangedListener(onScroll) }
    override fun onDetachedFromWindow() { viewTreeObserver.removeOnScrollChangedListener(onScroll); super.onDetachedFromWindow() }
}
