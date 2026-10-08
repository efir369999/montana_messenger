package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView

// ─────────────────────────── the main screen (iOS ChatsListView and its panes) ───────────────────────────

/**
 * THE CREST BEHIND THE PAGES (iOS MontanaCrestGround): the Dream Department's arms, centred on the whole screen at seven
 * tenths of its width, softened and half transparent, and the same picture filling the screen edge to edge as a gold
 * haze. The platform softens a view with its own RenderEffect from Android 12; before it, the crest stands unsoftened
 * and quieter, and the haze (a blur and nothing else) is left out.
 */
class CrestGround(c: Context) : FrameLayout(c) {
    private val crest = ImageView(c)

    init {
        setBackgroundColor(Color.BLACK)
        val picture = kept ?: BitmapFactory.decodeResource(resources, R.drawable.chats_crest).also { kept = it }
        val soft = Build.VERSION.SDK_INT >= 31
        if (soft) addView(ImageView(c).apply {
            setImageBitmap(picture)
            scaleType = ImageView.ScaleType.CENTER_CROP
            alpha = HAZE_OPACITY
            setRenderEffect(blur(HAZE_BLUR))
        }, LayoutParams(MATCH, MATCH))
        crest.setImageBitmap(picture)
        crest.scaleType = ImageView.ScaleType.FIT_CENTER
        crest.alpha = if (soft) OPACITY else OPACITY * 0.6f
        if (soft) crest.setRenderEffect(blur(BLUR))
        addView(crest, LayoutParams(0, MATCH, Gravity.CENTER))
        // THE PAGES' GROUND, SOFTENED ONCE MORE (iOS MTSoftGround, every page): the whole ground blurred so no edge of the crest
        // is readable, and dimmed as the App Library dims its wallpaper.
        if (soft) setRenderEffect(RenderEffect.createChainEffect(
            RenderEffect.createColorFilterEffect(android.graphics.ColorMatrixColorFilter(
                android.graphics.ColorMatrix().apply { setScale(SOFT_LIGHT, SOFT_LIGHT, SOFT_LIGHT, 1f) })),
            blur(SOFT_RADIUS)))
    }

    private fun blur(r: Float): RenderEffect {
        val px = dp(r).toFloat()
        return RenderEffect.createBlurEffect(px, px, Shader.TileMode.CLAMP)
    }

    /** A ground asks for no room of its own: it fills what its container is given (the preview's box, the screen). */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        fun size(spec: Int) = if (MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY) MeasureSpec.getSize(spec) else 0
        val w = size(widthMeasureSpec); val h = size(heightMeasureSpec)
        setMeasuredDimension(w, h)
        val exact = { v: Int -> MeasureSpec.makeMeasureSpec(v, MeasureSpec.EXACTLY) }
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val cw = (child.layoutParams.width).let { if (it > 0) it else w }
            child.measure(exact(cw), exact(h))
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        post { crest.layoutParams = LayoutParams((w * SCALE).toInt(), MATCH, Gravity.CENTER) }
    }

    private companion object {
        /** The crest decoded once a launch: the preview of «Appearance» draws the ground again at every slider's move. */
        var kept: android.graphics.Bitmap? = null
        const val BLUR = 8f           // the crest's own softness (iOS blur 8)
        const val OPACITY = 0.5f
        const val SCALE = 0.7f        // seven tenths of the screen's width
        const val HAZE_BLUR = 48f
        const val HAZE_OPACITY = 0.35f
        const val SOFT_RADIUS = 36f   // iOS MTSoftGround.radius
        const val SOFT_LIGHT = 0.72f  // iOS MTSoftGround.light
    }
}

/**
 * THE GLASS OF A PLATE (iOS montanaOctagonFace(bar: true), MontanaOctagon.barMaterial = .ultraThinMaterial, MTGlassCirclePlate):
 * ONE TONE, NOT SEE-THROUGH (the design word of 08.10.2026: «one-tone glass on the buttons, not see-through»). The system's thin
 * material blurs whatever runs beneath into one even tone; the platform here blurs nothing behind a view, so the plate is that
 * tone itself — the menus' own material, near-opaque — with the thin light rim of the iOS plate (white 0.18). A feed running under
 * the bars reads as one quiet plate under the glyph, never as letters through it.
 */
fun Context.glassPlate(oval: Boolean = false) = GradientDrawable().apply {
    if (oval) shape = GradientDrawable.OVAL else cornerRadius = dp(100).toFloat()
    setColor(GLASS_TONE)
    setStroke(dp(1).coerceAtMost(3), Color.argb(46, 255, 255, 255))
}
/** The one tone of the glass (the menus' material, iOS .ultraThinMaterial over the dark ground). */
val GLASS_TONE = Color.argb(235, 44, 44, 46)

/** A list's own top padding before the bar's room was added to it: the room is laid over it, never over itself again. */
private val ownTop = java.util.WeakHashMap<View, Int>()
private fun roomAbove(v: View, room: Int) {
    val own = ownTop.getOrPut(v) { v.paddingTop }
    if (v.paddingTop != own + room) v.setPadding(v.paddingLeft, own + room, v.paddingRight, v.paddingBottom)
}
/** The page's scrolling lists take the bar's room above and draw beneath it; false — the page has none. */
private fun underlap(v: View, room: Int): Boolean {
    if (v is android.widget.ScrollView) { v.clipToPadding = false; roomAbove(v, room); return true }
    var any = false
    if (v is android.view.ViewGroup) for (i in 0 until v.childCount) if (underlap(v.getChildAt(i), room)) any = true
    return any
}
private fun underlapPage(page: View, room: Int) { if (!underlap(page, room)) roomAbove(page, room) }

/** The glyph inside a bar button (iOS MontanaOctagon.barGlyph: Color(white: 0.8)). */
private val barGlyph = Color.rgb(204, 204, 204)

/** The pages under the bar (iOS UIState.Pane): the mesh wall from the drawer, the P2P wall the globe's page. */
enum class Pane { CHATS, CONTACTS, CALLS, FEED, MUSIC, GALLERY, GROUPS, CHANNELS, MESH, P2P }

fun mainScreen(act: MainActivity, onForget: () -> Unit): View {
    val c = act
    act.setGround(CrestGround(c))
    var pane = Pane.CHATS   // iOS: the chats are the first page of a launch
    val panes = FrameLayout(c)
    val music = MusicPage(act)
    val views = mapOf(Pane.CHATS to chatsPane(act), Pane.CONTACTS to contactsPane(act), Pane.CALLS to callsPane(act),
        Pane.FEED to feedPane(act), Pane.MUSIC to music.view, Pane.GALLERY to galleryPane(act),
        Pane.GROUPS to groupsPane(act, channel = false), Pane.CHANNELS to groupsPane(act, channel = true), Pane.MESH to meshPane(act), Pane.P2P to p2pPane(act))
    views.values.forEach { v -> v.visibility = View.GONE; panes.addView(v, FrameLayout.LayoutParams(MATCH, MATCH)) }
    views.getValue(Pane.CHATS).visibility = View.VISIBLE
    // THE FLOATING PLAYER stands on the chats, the feed and the music while anything plays (iOS playerBar).
    val player = miniBar(act)
    panes.addView(player, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { bottomMargin = c.dp(8) })
    fun showPlayer() {
        val on = Playing.kind != null && pane in setOf(Pane.CHATS, Pane.FEED, Pane.MUSIC)
        player.visibility = if (on) View.VISIBLE else View.GONE
        if (on) player.live()
        music.reserve(on && pane == Pane.MUSIC)
    }
    Playing.listen { if (player.isAttachedToWindow) showPlayer() }   // a track, a voice or a note: the one gate (iOS MontanaPlayerBar.Gate)
    // THE ONE SEARCH (iOS searchResults, [C-1]): the same field and the same results stand on the chats, the contacts and the
    // calls pages; while the search is on, the system's back puts it away first.
    val results = SearchResults(act).apply { visibility = View.GONE }
    var keepBack: (() -> Unit)? = null
    var searching = false
    lateinit var search: SearchRow
    fun showResults() {
        val on = search.active && pane in setOf(Pane.CHATS, Pane.CONTACTS, Pane.CALLS)
        if (on && results.visibility != View.VISIBLE) results.scrollTo(0, 0)
        results.visibility = if (on) View.VISIBLE else View.GONE
        if (on) results.show(search.query)
        if (search.active != searching) {
            searching = search.active
            if (searching) { keepBack = act.back; act.back = { search.clear() } } else { act.back = keepBack; keepBack = null }
        }
    }
    search = SearchRow(c) { _, _ -> showResults() }
    lateinit var bar: HomeBar
    /** The pane stands: the bar's puck under it, the dynamic glyph's memory, the music's walk, the player's place. */
    fun arrived(p: Pane) {
        pane = p
        if (p == Pane.MUSIC || p == Pane.GALLERY) Prefs.setStr("lastMediaPane", if (p == Pane.MUSIC) "music" else "gallery")
        bar.showPane(p)
        if (p == Pane.MUSIC) MusicFolders.walk(act)          // what was put into the lent folders since comes in
        showPlayer()
        showResults()
    }
    fun choose(p: Pane) {
        if (p == pane) return
        val off = views.getValue(pane); val on = views.getValue(p)
        off.visibility = View.GONE
        on.translationX = 0f; on.alpha = 0f; on.visibility = View.VISIBLE
        on.animate().alpha(1f).setDuration(200).start()   // iOS .easeInOut(duration: 0.2)
        arrived(p)
    }
    val shell = DrawerShell(act)
    // THE PAGES FOLLOW THE FINGER (iOS turnOrder, turnStroke): the pane moves by the finger and the page beside it slides in
    // from its side — the next on a stroke to the left, the one before on a stroke to the right; at the release a moving finger
    // says the way, a still one the distance. The order is the bar's: contacts, calls, the feed, the chats, the dynamic glyph's
    // page — the music, or the gallery when it was the last opened — and the globe's P2P wall.
    shell.turner = object : DrawerShell.Turner {
        var next: Pane? = null
        var side = 0
        fun order(): List<Pane> {
            val media = if (pane == Pane.MUSIC || pane == Pane.GALLERY) pane
                        else if (Prefs.str("lastMediaPane", "music") == "gallery") Pane.GALLERY else Pane.MUSIC
            return listOf(Pane.CONTACTS, Pane.CALLS, Pane.FEED, Pane.CHATS, media, Pane.P2P)   // iOS turnOrder
        }
        override fun begin(side: Int): Boolean {
            val o = order(); val i = o.indexOf(pane); val j = i + side
            if (i < 0 || j !in o.indices) return false
            next = o[j]; this.side = side
            views.getValue(pane).animate().cancel()
            views.getValue(o[j]).apply { animate().cancel(); alpha = 1f; visibility = View.VISIBLE; translationX = side * panes.width.toFloat() }
            return true
        }
        override fun move(dx: Float) {
            val w = panes.width.toFloat()
            val d = if (side > 0) dx.coerceIn(-w, 0f) else dx.coerceIn(0f, w)
            views.getValue(pane).translationX = d
            next?.let { views.getValue(it).translationX = d + side * w }
        }
        override fun end(dx: Float, velocity: Float) {
            val to = next ?: return
            val w = panes.width.toFloat()
            val fling = c.dp(400)
            val go = if (kotlin.math.abs(velocity) > fling) (velocity < 0) == (side > 0) else kotlin.math.abs(dx) > w / 3
            val cur = views.getValue(pane); val nv = views.getValue(to)
            val ms = 240L
            cur.animate().translationX(if (go) -side * w else 0f).setDuration(ms).setInterpolator(android.view.animation.DecelerateInterpolator()).withEndAction {
                if (go) { cur.visibility = View.GONE; cur.translationX = 0f }
            }.start()
            nv.animate().translationX(if (go) 0f else side * w).setDuration(ms).setInterpolator(android.view.animation.DecelerateInterpolator()).withEndAction {
                if (!go) { nv.visibility = View.GONE; nv.translationX = 0f }
            }.start()
            if (go) arrived(to)
            next = null
        }
    }
    bar = HomeBar(act, onDrawer = { shell.open() }, onPane = ::choose)
    bar.showPane(Pane.CHATS, animated = false)
    // THE LISTS RUN UNDER THE BAR (iOS: the list's top inset is measured from the bar as drawn, MontanaOctagon 111-112; the design word
    // 08.10.2026: «the feed must run under the buttons»): the time panel and the search have no ground of their own — every
    // page's list keeps their height as its own room above and scrolls on beneath them; a page with nothing that scrolls keeps the
    // room itself, so nothing of it stands under the bar.
    val head = c.vstack(Gravity.NO_GRAVITY) {
        addView(bar, lp(MATCH, dp(60)).apply { setMargins(dp(12), dp(4), dp(12), dp(2)) })
        addView(search, lp(MATCH, dp(56)))
    }
    shell.page.addView(FrameLayout(c).apply {
        addView(panes, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(results, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(head, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))
    }, 1, FrameLayout.LayoutParams(MATCH, MATCH))
    head.addOnLayoutChangeListener { _, _, top, _, bottom, _, _, _, _ ->
        views.values.forEach { underlapPage(it, bottom - top) }
        underlapPage(results, bottom - top)
    }
    results.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        val again: () -> Unit = { results.again() }
        override fun onViewAttachedToWindow(v: View) { Book.listen(again) }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again) }
    })
    shell.drawer.addView(sideDrawer(act,
        onPane = { p -> shell.close { choose(p) } },
        onProfile = { shell.close { act.push { myPage(act, it) } } },   // the face with the name opens my page (iOS MTMyPageFromDrawer)
        onSettings = { shell.close { act.push { settingsRoot(act, onForget, it) } } },
        onCard = { shell.close { act.push { businessCardPage(act, it) } } },
        onPasswords = { shell.close { act.push { passwordsPage(act, it) } } },
        onWallet = { shell.close { act.push { walletPage(act, it) } } },
        onChess = { shell.close { act.push { chessLobbyPage(act, it) } } }), FrameLayout.LayoutParams(MATCH, MATCH))
    return shell
}

/**
 * THE DRAWER LIES UNDER THE PAGE (iOS MontanaDrawerHost): the page slides right by the drawer's width — 0.78 of the screen —
 * and dims; a tap on the dimmed page or the system's back closes it. iOS also opens it by a drag from the screen's left
 * edge; on Android that edge belongs to the system's back gesture, so the grid glyph is the one road in.
 */
class DrawerShell(private val act: MainActivity) : FrameLayout(act) {
    /** The pages under the bar turned by the same stroke (iOS turnStroke): side +1 — the next page, from a stroke to the left. */
    interface Turner {
        fun begin(side: Int): Boolean
        fun move(dx: Float)
        fun end(dx: Float, velocity: Float)
    }
    var turner: Turner? = null
    private var turning = false
    val drawer = FrameLayout(act)
    val page = FrameLayout(act)
    private val dim = View(act).apply { setBackgroundColor(Color.BLACK); alpha = 0f; visibility = View.GONE }
    private var isOpen = false
    private var keepBack: (() -> Unit)? = null

    init {
        drawer.addView(act.chatGround(ChatWall.PAGE), LayoutParams(MATCH, MATCH))   // the drawer's own ground (iOS montanaPageGround(still: true))
        page.addView(act.chatGround(ChatWall.PAGE), LayoutParams(MATCH, MATCH))     // the page carries its ground as it slides
        page.addView(dim, LayoutParams(MATCH, MATCH))
        dim.setOnClickListener { close() }
        addView(drawer, LayoutParams(0, MATCH))
        addView(page, LayoutParams(MATCH, MATCH))
        drawer.visibility = View.INVISIBLE
    }

    private val width78 get() = Math.round(width * 0.78f)

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        post { drawer.layoutParams = LayoutParams(Math.round(w * 0.78f), MATCH) }
    }

    fun open() = settle(true)

    /** Closes, and does what the drawer's row asked once the page is home (iOS leave(then:)). */
    fun close(then: () -> Unit = {}) {
        if (!isOpen && page.translationX == 0f) { then(); return }
        settle(false, then)
    }

    /** The page slides to where the finger or the tap sent it: open over the drawer, or home. */
    private fun settle(open: Boolean, then: () -> Unit = {}) {
        val was = isOpen
        isOpen = open
        reveal()
        val to = if (open) width78.toFloat() else 0f
        val ms = (280 * kotlin.math.abs(to - page.translationX) / width78.coerceAtLeast(1)).toLong().coerceIn(120, 320)
        dim.animate().alpha(if (open) DIM else 0f).setDuration(ms).start()
        page.animate().translationX(to).setDuration(ms).setInterpolator(android.view.animation.DecelerateInterpolator(1.6f)).withEndAction {
            if (!open) { dim.visibility = View.GONE; drawer.visibility = View.INVISIBLE }
            then()
        }.start()
        if (open && !was) { keepBack = act.back; act.back = { close() } }
        if (!open && was) act.back = keepBack
    }

    private fun reveal() {
        dim.bringToFront()
        drawer.visibility = View.VISIBLE
        dim.visibility = View.VISIBLE
    }

    // THE PAGE FOLLOWS THE FINGER (the user's word 29.09: «a swipe to the right from the chats opens the side panel, a swipe to the
    // left brings me back»): a stroke that is plainly sideways takes the page — to the right it uncovers the drawer, to the left it
    // covers it again — and at the release a moving finger says the way, a still one the distance (half the drawer). A stroke
    // that is mostly up or down stays the list's; a control that holds its own drag (the player's plate) asks not to be taken.
    private val slop = android.view.ViewConfiguration.get(act).scaledTouchSlop
    private var downX = 0f; private var downY = 0f; private var startT = 0f
    private var dragging = false
    private var tracker: android.view.VelocityTracker? = null

    override fun onInterceptTouchEvent(e: android.view.MotionEvent): Boolean {
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                downX = e.x; downY = e.y; dragging = false
                tracker?.recycle(); tracker = android.view.VelocityTracker.obtain().also { it.addMovement(e) }
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                tracker?.addMovement(e)
                val dx = e.x - downX; val dy = e.y - downY
                if (!dragging && kotlin.math.abs(dx) > slop && kotlin.math.abs(dx) > 1.5f * kotlin.math.abs(dy)) {
                    // THE ROW'S LEFT END (iOS turnAtRowStart): the pages turn under the stroke; past the first page a stroke to
                    // the right is the drawer's; with the drawer open, a stroke to the left closes it.
                    if (isOpen) { if (dx > 0) return false }
                    else if (turner?.begin(if (dx < 0) 1 else -1) == true) {
                        turning = true; dragging = true; downX = e.x
                        parent?.requestDisallowInterceptTouchEvent(true)
                        return true
                    } else if (dx < 0) return false
                    dragging = true
                    startT = page.translationX
                    downX = e.x
                    page.animate().cancel(); dim.animate().cancel()
                    reveal()
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
        }
        return false
    }

    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        // A touch no child took comes here straight, never through the interception: the same reading of the stroke.
        if (!dragging) {
            val took = onInterceptTouchEvent(e)
            return e.actionMasked == android.view.MotionEvent.ACTION_DOWN || took || dragging
        }
        tracker?.addMovement(e)
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_MOVE -> {
                if (turning) { turner?.move(e.x - downX); return true }
                val t = (startT + e.x - downX).coerceIn(0f, width78.toFloat())
                page.translationX = t
                dim.alpha = DIM * t / width78.coerceAtLeast(1)
            }
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                dragging = false
                tracker?.computeCurrentVelocity(1000)
                val v = tracker?.xVelocity ?: 0f
                tracker?.recycle(); tracker = null
                if (turning) { turning = false; turner?.end(e.x - downX, v); return true }
                val fling = dp(400)
                settle(if (kotlin.math.abs(v) > fling) v > 0 else page.translationX > width78 / 2f)
            }
        }
        return true
    }

    private companion object { const val DIM = 0.35f }
}

/**
 * THE SIDE DRAWER (iOS MontanaSideDrawer, the 1949 list): my face with its name at the head, then every application as a
 * row — the white glyph, the bold word — and «Settings» pressed to the foot with the build's number under it. The rows of
 * pages Android does not have yet stand in their places, quieter, and take no tap. The plus of a second login is iOS's
 * multi-login, which Android does not have.
 */
private fun sideDrawer(act: MainActivity, onPane: (Pane) -> Unit, onProfile: () -> Unit, onSettings: () -> Unit, onCard: () -> Unit, onPasswords: () -> Unit, onWallet: () -> Unit, onChess: () -> Unit): View {
    val c: Context = act
    fun row(icon: View, word: Int, onTap: (() -> Unit)?) = c.hstack {
        setPadding(0, dp(16), 0, dp(16))
        addView(icon, lp(dp(30), dp(30)))
        gap(22)
        addView(c.text(c.getString(word), 22f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
        if (onTap != null) pressable(onTap) else alpha = 0.35f
    }
    fun glyph(res: Int) = c.icon(res, Color.WHITE, 30)
    // THE FEED'S WHITE MARK (iOS MTFeedMark): the logo drawn white inside a thin white ring.
    fun feedMark() = FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(dp(1.6f), Color.WHITE) }
        addView(c.icon(R.drawable.logo, Color.WHITE), FrameLayout.LayoutParams(MATCH, MATCH).apply { setMargins(dp(6), dp(6), dp(6), dp(6)) })
        setPadding(dp(2), dp(2), dp(2), dp(2))
    }
    val name = Prefs.userName.trim()
    val face = c.vstack {
        addView(c.avatar(SelfFace.load(c), name, 48).apply {
            foreground = GradientDrawable().apply { shape = GradientDrawable.OVAL; setStroke(dp(3), MT.blue) }   // the ring of the shown shell
        }, lp(dp(48), dp(48)))
        if (name.isNotEmpty()) addView(c.text(name, 12f, Color.WHITE, center = true).apply { maxLines = 2 }, lp(dp(88), WRAP).apply { topMargin = dp(6) })   // USER-DATA: the person's own name
        pressable(onProfile)
    }
    val column = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(24), dp(20), dp(16), 0)
        addView(face, lp(dp(88), WRAP).apply { marginStart = -dp(20) })
        gap(14)
        addView(row(glyph(R.drawable.ic_bar_contacts), R.string.contacts) { onPane(Pane.CONTACTS) }, lp())
        addView(row(glyph(R.drawable.ic_bar_calls), R.string.app_calls) { onPane(Pane.CALLS) }, lp())
        addView(row(feedMark(), R.string.app_feed) { onPane(Pane.FEED) }, lp())
        addView(row(glyph(R.drawable.ic_bar_chats), R.string.chats) { onPane(Pane.CHATS) }, lp())
        // the groups and the channels, apps of their own under the chats (iOS MTApplication .groups, .channels: person.3.fill, megaphone.fill)
        addView(row(glyph(R.drawable.ic_app_groups), R.string.app_groups) { onPane(Pane.GROUPS) }, lp())
        addView(row(glyph(R.drawable.ic_app_channels), R.string.app_channels) { onPane(Pane.CHANNELS) }, lp())
        addView(row(glyph(R.drawable.ic_bar_play), R.string.app_music) { onPane(Pane.MUSIC) }, lp())
        addView(row(glyph(R.drawable.ic_app_gallery), R.string.app_gallery) { onPane(Pane.GALLERY) }, lp())
        addView(row(android.widget.ImageView(c).apply { setImageResource(R.drawable.chess_knight) }, R.string.app_chess, onChess), lp())   // chess (iOS MTChessPage)
        addView(row(glyph(R.drawable.ic_app_wallet), R.string.app_wallet, onWallet), lp())   // TimeCoin (iOS MTWalletPage)
        // THE WALLS BESIDE THE FEED (iOS MTApplication .meshWall, .p2pWall; the author's word 29.09): the people around, phone to
        // phone; the nodes this phone reaches
        addView(row(glyph(R.drawable.ic_set_antenna), R.string.app_mesh_wall) { onPane(Pane.MESH) }, lp())
        addView(row(glyph(R.drawable.ic_language), R.string.app_p2p_wall) { onPane(Pane.P2P) }, lp())
        addView(row(glyph(R.drawable.ic_app_card), R.string.app_card, onCard), lp())   // the business card (iOS MTCardFromDrawer, the author's word 28.09)
        // PASSWORDS (iOS MTApplication .passwords, key.fill, the author's word 06.10.2026 17:4x MSK): a page of its own over the tabs
        addView(row(glyph(R.drawable.ic_key), R.string.pw_title, onPasswords), lp())
        spacer()
        addView(row(glyph(R.drawable.ic_settings), R.string.settings, onSettings), lp())
        addView(c.text(appVersionFull(c), 11f, MT.gray).apply { setPadding(dp(52), 0, 0, dp(8)) }, lp())   // USER-DATA: the build's own number
    }
    return ScrollView(c).apply {
        isFillViewport = true
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        addView(column)
    }
}

/**
 * THE TIME PANEL (iOS chatsTopBarPlate): ONE glass capsule at the bar's height, and on it seven glyphs with equal shares of
 * the width, left to right — the drawer, the contacts, the calls, THE LOGO AT THE CENTRE, the chats, the player and the
 * globe. One puck stands under the chosen glyph and flows to the one tapped next; the globe is the network's lamp and opens
 * the P2P wall.
 */
class HomeBar(private val act: MainActivity, onDrawer: (View) -> Unit, onPane: (Pane) -> Unit) : FrameLayout(act) {
    private val puck = View(act).apply {
        background = GradientDrawable().apply { cornerRadius = dp(100).toFloat(); setColor(Color.argb(41, 255, 255, 255)) }   // iOS MTBarPuck: white 0.16
    }
    private val row = act.hstack { }
    private var slot = CHATS
    private lateinit var media: ImageView
    private lateinit var globe: ImageView

    init {
        background = act.glassPlate()
        addView(puck, LayoutParams(0, 0))
        addView(row, LayoutParams(MATCH, MATCH))
        glyph(R.drawable.ic_bar_drawer, 26) { onDrawer(it) }
        glyph(R.drawable.ic_bar_contacts, 26) { onPane(Pane.CONTACTS) }
        glyph(R.drawable.ic_bar_calls, 26) { onPane(Pane.CALLS) }
        // THE LOGO ON THE GLASS (iOS MTFeedGlyph): the gold sign on a round glass plate, a quarter of its side around it.
        row.addView(FrameLayout(act).apply {
            addView(FrameLayout(act).apply {
                background = act.glassPlate(oval = true)
                addView(ImageView(act).apply { setImageResource(R.drawable.logo); setPadding(dp(9), dp(9), dp(9), dp(9)) },
                    LayoutParams(MATCH, MATCH))
            }, LayoutParams(dp(36), dp(36), Gravity.CENTER))
            pressable { onPane(Pane.FEED) }   // the logo opens the feed of my people's walls (iOS 25.09)
        }, lp(0, MATCH, 1f))
        glyph(R.drawable.ic_bar_chats, 24) { onPane(Pane.CHATS) }
        // THE DYNAMIC GLYPH: the last opened of the player and the gallery; a tap opens that one again.
        media = glyph(R.drawable.ic_bar_play, 26) { onPane(if (Prefs.str("lastMediaPane", "music") == "gallery") Pane.GALLERY else Pane.MUSIC) }
        if (Prefs.str("lastMediaPane", "music") == "gallery") media.setImageResource(R.drawable.ic_app_gallery)
        // THE GLOBE (iOS MTBarGlobe, MontanaTransportIcon): the network's lamp — green while a machine is held, red while none is,
        // grey before the first knock (unknown is not «no»); a tap chooses the P2P wall (the author's word 25.09)
        globe = glyph(R.drawable.ic_language, 26, tint = Color.rgb(115, 115, 115)) { onPane(Pane.P2P) }
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> place(false) }
        val lamp = object : Runnable {
            override fun run() {
                val up = Channels.nodesHeld() > 0
                globe.imageTintList = android.content.res.ColorStateList.valueOf(if (up) MT.green else if (Channels.knocked) MT.red else Color.rgb(115, 115, 115))
                postDelayed(this, 2000)
            }
        }
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { post(lamp) }
            override fun onViewDetachedFromWindow(v: View) { removeCallbacks(lamp) }
        })
    }

    private fun glyph(res: Int, sizeDp: Int, tint: Int = barGlyph, onTap: ((View) -> Unit)? = null): ImageView {
        val box = FrameLayout(act)
        val icon = act.icon(res, tint)
        box.addView(icon, LayoutParams(dp(sizeDp), dp(sizeDp), Gravity.CENTER))
        if (onTap != null) box.pressable { onTap(box) }
        row.addView(box, lp(0, MATCH, 1f))
        return icon
    }

    /** The puck goes under the pane's slot; the dynamic glyph wears the music's or the gallery's face (iOS slot(of:)). */
    fun showPane(p: Pane, animated: Boolean = true) {
        // the groups and the channels are opened from the drawer: no glyph of the bar is theirs, the puck stands away (iOS slot nil)
        slot = when (p) { Pane.CONTACTS -> 1; Pane.CALLS -> 2; Pane.FEED -> 3; Pane.CHATS -> 4; Pane.MUSIC, Pane.GALLERY -> 5; Pane.P2P -> 6; Pane.GROUPS, Pane.CHANNELS, Pane.MESH -> -1 }
        if (p == Pane.MUSIC) media.setImageResource(R.drawable.ic_bar_play)
        if (p == Pane.GALLERY) media.setImageResource(R.drawable.ic_app_gallery)
        place(animated)
    }

    private fun place(animated: Boolean) {
        puck.visibility = if (slot < 0) View.INVISIBLE else View.VISIBLE
        if (width == 0 || slot < 0) return
        val w = width / 7f
        val lpk = puck.layoutParams as LayoutParams
        val pw = (w - dp(6)).toInt(); val ph = height - dp(12)
        if (lpk.width != pw || lpk.height != ph) {
            lpk.width = pw; lpk.height = ph; lpk.topMargin = dp(6)
            post { puck.layoutParams = lpk }
        }
        val x = slot * w + dp(3)
        if (animated) puck.animate().translationX(x).setDuration(200).setInterpolator(AccelerateDecelerateInterpolator()).start()
        else puck.translationX = x
    }

    private companion object { const val CHATS = 4 }
}

/**
 * THE SEARCH ROW (iOS MTSearchField, the platform's own search bar in its minimal style): a capsule with the magnifier and
 * «Search», and the round cross beside it while the search is on (iOS searchBar: the cross appears in search mode).
 * `onChange(query, active)` — active is «focused or holding text» (iOS searchActive).
 */
private class SearchRow(val c: Context, onChange: (String, Boolean) -> Unit) : LinearLayout(c) {
    val field = EditText(c)
    private val cross = FrameLayout(c)
    val query get() = field.text.toString()
    val active get() = field.hasFocus() || query.isNotEmpty()

    init {
        orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(19), 0, dp(19), 0)
        addView(c.hstack {
            background = c.glassPlate()
            setPadding(dp(12), 0, dp(12), 0)
            addView(c.icon(R.drawable.ic_search, Color.rgb(230, 230, 230)), lp(dp(22), dp(22)).apply { marginEnd = dp(8) })
            addView(field.apply {
                hint = c.getString(R.string.search)
                setHintTextColor(MT.gray); setTextColor(Color.WHITE)
                textSize = 17f
                background = null
                isSingleLine = true
                inputType = InputType.TYPE_CLASS_TEXT
                imeOptions = EditorInfo.IME_ACTION_SEARCH
                setPadding(0, 0, 0, 0)
            }, lp(0, WRAP, 1f))
        }, LayoutParams(0, dp(40), 1f))
        addView(cross.apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.cancel)
            addView(c.icon(R.drawable.ic_close, barGlyph), FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER))
            visibility = GONE
            pressable { clear() }
        }, LayoutParams(dp(40), dp(40)).apply { marginStart = dp(8) })
        val tell = { cross.visibility = if (active) VISIBLE else GONE; onChange(query, active) }
        field.setOnFocusChangeListener { _, _ -> tell() }
        field.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) { tell() }
        })
        field.setOnEditorActionListener { _, _, _ -> hideKeys(); true }   // the search key only puts the keys away (iOS searchBarSearchButtonClicked)
    }
    private fun hideKeys() = c.getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(field.windowToken, 0)
    /** The cross, the back gesture: the words go, the focus goes, the keys go. */
    fun clear() { hideKeys(); field.setText(""); field.clearFocus() }
}

/** Words compared as a person reads them: case and marks aside, «ё» as «е» (iOS .caseInsensitive, .diacriticInsensitive). */
private fun fold(s: String) = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()

/**
 * THE SEARCH RESULTS (iOS searchResults, refreshSearchHits): nothing typed — the recent people; a word — the chats whose name
 * holds it, then the letters that hold it, newest sixty; nothing — «Nothing found». Android has no book of contacts
 * without a conversation, so iOS's «Contacts» section of such cards has nothing to show here.
 */
private class SearchResults(val act: MainActivity) : ScrollView(act) {
    private val list = act.vstack(Gravity.NO_GRAVITY)
    private var q = ""
    private val redraw = Runnable { draw() }
    init {
        isVerticalScrollBarEnabled = false
        setBackgroundColor(Color.BLACK)
        addView(list)
    }
    /** A word typed through is scanned once, after the keys settle (iOS: 120 ms). */
    fun show(query: String) { q = query; removeCallbacks(redraw); postDelayed(redraw, if (query.isEmpty()) 0 else 120) }
    fun again() { if (visibility == VISIBLE) show(q) }

    private fun keysAway() = act.getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(windowToken, 0)
    private fun header(words: Int) = list.addView(act.text(act.getString(words), 12f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(6)) }, lp())
    private fun hairline() = list.addView(View(act).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(82) })

    /** A person's row: the face and the name (iOS contactRow). */
    private fun personRow(ch: Chat) = act.hstack {
        setPadding(dp(16), dp(8), dp(16), dp(8))
        addView(act.peerFace(ch.ref, ch.shown, 46), lp(dp(46), dp(46)).apply { marginEnd = dp(12) })
        addView(act.text(ch.shown.ifBlank { act.getString(R.string.peer) }, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
        pressable { keysAway(); act.push { close -> conversationPage(act, ch.ref, close) } }
    }
    /** A letter found: the face, the name, the hour and the words (iOS messageHitRow); a tap opens the chat on that letter. */
    private fun hitRow(ch: Chat, m: Msg) = act.hstack {
        setPadding(dp(16), dp(8), dp(16), dp(8))
        addView(act.peerFace(ch.ref, ch.shown, 46), lp(dp(46), dp(46)).apply { marginEnd = dp(12) })
        addView(act.vstack(Gravity.NO_GRAVITY) {
            addView(act.hstack {
                // the chat's own name, whoever wrote the letter (iOS: the one face and the one title of a chat)
                addView(act.text(ch.shown.ifBlank { act.getString(R.string.peer) }, 15f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                addView(act.text(rowTime(act, m.at), 12f, MT.gray))
            }, lp())
            addView(act.text(m.text, 13f, MT.gray).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END }, lp())   // USER-DATA: the letter
        }, lp(0, WRAP, 1f))
        pressable { keysAway(); act.push { close -> conversationPage(act, ch.ref, close, jump = m.mid) } }
    }

    private fun draw() {
        list.removeAllViews()
        val people = Book.all().filter { it.msgs.isNotEmpty() && !Groups.isKey(it.ref) }   // people only: a group is no person
        if (q.isEmpty()) {
            // nothing typed yet — the recent people only (iOS recentContacts: twelve, people only)
            if (people.isNotEmpty()) header(R.string.search_contacts)
            people.take(12).forEach { list.addView(personRow(it), lp()); hairline() }
            return
        }
        val w = fold(q.trim())
        if (w.isEmpty()) return
        val chats = people.filter { fold(it.shown + " " + it.name).contains(w) }   // a person is found as they are seen, and by their own word (iOS shownName)
        // the words of a person only: a word of the wire is never read as theirs, a voice or a file has no words to find
        val found = people.flatMap { ch -> ch.msgs.filter { !Marks.isService(it.text) && fold(it.text).contains(w) }.map { ch to it } }
            .sortedByDescending { it.second.at }.take(60)
        if (chats.isNotEmpty()) { header(R.string.search_chats); chats.forEach { list.addView(personRow(it), lp()); hairline() } }
        if (found.isNotEmpty()) { header(R.string.search_messages); found.forEach { (ch, m) -> list.addView(hitRow(ch, m), lp()); hairline() } }
        if (chats.isEmpty() && found.isEmpty())
            list.addView(act.text(act.getString(R.string.nothing_found), 17f, MT.gray, center = true).apply { setPadding(0, dp(40), 0, 0) }, lp())
    }
}

/**
 * THE CHATS PAGE as a new person first sees it (iOS, the author's word 17.09): the local room in one's own face, under it
 * «No chats yet» with the code's card, and the round «Write» button at the foot (iOS composeButton).
 */
private fun chatsPane(act: MainActivity): View {
    val c = act
    // THE SELECTION (iOS selecting): «Select» in a row's menu begins it; the bar at the foot acts on the chosen chats
    val bar = FrameLayout(c).apply { visibility = View.GONE }
    lateinit var write: View
    lateinit var redrawRows: () -> Unit
    val sel = ChatSelection { s ->
        redrawRows()
        bar.removeAllViews()
        if (s.on) bar.addView(selectionBar(act, s), FrameLayout.LayoutParams(MATCH, WRAP))
        bar.visibility = if (s.on) View.VISIBLE else View.GONE
        write.visibility = if (s.on) View.GONE else View.VISIBLE
    }
    val list = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        addView(c.vstack(Gravity.NO_GRAVITY) {
            // The local room: stands in the list from the first moment; a tap opens it (iOS: the row opens its conversation).
            val preview = c.text("", 15f, MT.gray).apply { maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }
            val time = c.text("", 13f, MT.gray)
            val face = FrameLayout(c)
            fun refresh() {
                // Saved Messages wears one's own face (iOS MTSelfFace, the author's word 11.09): read again on every return
                face.removeAllViews()
                face.addView(c.avatar(SelfFace.load(c), Prefs.userName, 54))
                val last = SavedMessages.last(c)
                preview.text = last?.text ?: ""   // USER-DATA: one's own last letter
                preview.visibility = if (last == null) View.GONE else View.VISIBLE
                time.text = last?.let { rowTime(c, it.at) } ?: ""
            }
            refresh()
            addView(c.hstack {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(face, lp(dp(54), dp(54)).apply { marginEnd = dp(12) })
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.hstack {
                        addView(c.text(c.getString(R.string.saved_messages), 17f, Color.WHITE, bold = true), lp(0, WRAP, 1f))
                        addView(time)
                    }, lp())
                    addView(preview, lp())
                }, lp(0, WRAP, 1f))
                pressable {
                    act.push { close ->
                        savedMessagesPage(act, close).apply {
                            // back by the arrow or by the system's gesture alike: the row reads the room again
                            addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                                override fun onViewAttachedToWindow(v: View) {}
                                override fun onViewDetachedFromWindow(v: View) { refresh() }
                            })
                        }
                    }
                }
            }, lp())
            addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(82) })
            // THE CONVERSATIONS (iOS MTChatListView): newest first, each row a person; «No chats yet» while there are none.
            val rows = c.vstack(Gravity.NO_GRAVITY)
            // THE EMPTY LIST (iOS MontanaQRCard, the author's word 17.09): «No chats yet» and the code itself under the local
            // room; a tap on the code opens its whole page. Built once: the rows are drawn again on every letter.
            val emptyCard by lazy {
                c.vstack {
                    setPadding(dp(8), dp(50), dp(8), dp(20))
                    addView(c.text(c.getString(R.string.no_chats), 20f, Color.WHITE, bold = true, center = true), lp())
                    gap(16)
                    addView(CardView(act) { act.push { cardPage(act, it) } }.view, lp())
                }
            }
            fun fillRows() {
                rows.removeAllViews()
                // THE ARCHIVE'S ROW over the chats while something is archived (iOS ArchivedChatsView behind «Archive»)
                val archived = archivedChats().size
                if (archived > 0 && !sel.on) {
                    rows.addView(archiveEntry(act, archived), lp())
                    rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(82) })
                }
                // a meeting that never carried a word leaves no row (iOS: the list stands on letters) — the silent question
                // of a scan must not raise an empty person here; the pinned stand first (listedChats)
                val all = chatRows()   // the groups and the channels stand in their own pages (iOS bare, 06.10)
                if (all.isEmpty() && archived == 0) rows.addView(emptyCard, lp())
                for (ch in all) {
                    rows.addView(listRow(act, ch, inArchive = false, sel = sel), lp())
                    rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(82) })
                }
            }
            redrawRows = { fillRows() }
            fillRows()
            val onBook: () -> Unit = { act.onMain { fillRows() } }
            rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) { Book.listen(onBook); ChatMarks.listen(onBook); refresh(); fillRows() }
                override fun onViewDetachedFromWindow(v: View) { Book.unlisten(onBook); ChatMarks.unlisten(onBook) }
            })
            addView(rows, lp())
            gap(120)   // the floating player's room at the foot
        })
    }
    return FrameLayout(c).apply {
        addView(CoinPull(c, list), FrameLayout.LayoutParams(MATCH, MATCH))   // the coin's pull refreshes the feed (iOS MontanaCoinSpinner)
        // «WRITE» (iOS composeButton): the one door to the code and the link — the QR opens here and nowhere else.
        write = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.share)
            addView(c.icon(R.drawable.ic_compose, barGlyph), FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
            pressable { act.push { cardPage(act, it) } }
        }
        addView(write, FrameLayout.LayoutParams(dp(60), dp(60), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, dp(16), dp(36)) })
        addView(bar, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { bottomMargin = dp(26) })
    }
}

/**
 * THE GROUPS' PAGE AND THE CHANNELS' PAGE (iOS ChatsTabView .groups / .channels, the author's words 06.10.2026 11:5x-12:0x MSK:
 * «in the side panel, under Chats, separate apps Groups and Channels — whole apps of their own, where groups and channels are
 * created and where they live; the chats list does not show them»): the rows of its kind alone, drawn as the chats list draws them.
 */
private fun groupsPane(act: MainActivity, channel: Boolean): View {
    val c = act
    val rows = c.vstack(Gravity.NO_GRAVITY)
    fun fill() {
        rows.removeAllViews()
        for (ch in groupRows(channel)) {
            rows.addView(listRow(act, ch, inArchive = false, sel = null), lp())
            rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
        }
    }
    val onBook: () -> Unit = { act.onMain { fill() } }
    rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(onBook); ChatMarks.listen(onBook); fill() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(onBook); ChatMarks.unlisten(onBook) }
    })
    val list = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(rows, lp()); gap(120) })   // the floating player's room at the foot
    }
    if (channel) return list   // a channel is born by its own three steps (the plan's stage 6)
    // THE CORNER CREATES ONE OF THE PAGE'S KIND (iOS createButton): the plus on the bar's glass, the group's two steps
    return FrameLayout(c).apply {
        addView(list, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.app_groups)
            addView(c.icon(R.drawable.ic_plus, barGlyph), FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
            pressable { act.push { close -> groupPickPage(act, close, onCreated = { key -> act.push { back -> conversationPage(act, key, back) } }) } }
        }, FrameLayout.LayoutParams(dp(60), dp(60), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, dp(16), dp(36)) })
    }
}

/**
 * THE CONTACTS PAGE (iOS ContactsTabView): the people (Contacts.kt), and at the bottom right the round glass button with
 * the share glyph that hands out one's card (MontanaCardShare: the words and the link).
 */
private fun contactsPane(act: MainActivity): View {
    val c = act
    return FrameLayout(c).apply {
        // THE PEOPLE (iOS ContactsTabView): pins, then presence, then name; «No contacts yet» while there are none (Contacts.kt)
        addView(CoinPull(c, contactsList(act)), FrameLayout.LayoutParams(MATCH, MATCH))   // one law for every page under the bar
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.share)
            addView(c.icon(R.drawable.ic_share, barGlyph), FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
            pressable { shareCard(act) }   // the one share of one's card (iOS MontanaCardShare)
        }, FrameLayout.LayoutParams(dp(56), dp(56), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, dp(16), dp(36)) })
    }
}
