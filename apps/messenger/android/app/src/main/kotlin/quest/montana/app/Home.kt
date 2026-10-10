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

/** THE SAME SOFTENING THE CREST WEARS, FOR ANY GROUND MY PAGE CHOSE (iOS MTSoftGround.soften 699-709 and MontanaChatBackdrop.
 * wearsPageGround 459-474 at 2155, radius 36 light 0.72): a photo or a named ground behind the pages reads as unreadably soft
 * and dimmed as the crest already does. */
private fun View.softenPageGround() {
    if (Build.VERSION.SDK_INT < 31) return
    val px = dp(36f).toFloat()
    setRenderEffect(RenderEffect.createChainEffect(
        RenderEffect.createColorFilterEffect(android.graphics.ColorMatrixColorFilter(
            android.graphics.ColorMatrix().apply { setScale(0.72f, 0.72f, 0.72f, 1f) })),
        RenderEffect.createBlurEffect(px, px, Shader.TileMode.CLAMP)))
}

/** MY PAGE'S GROUND, UNDER EVERY PAGE (iOS MontanaFeeds.swift MTUnderBarGround 568-578 at 2155, and the author's word 26.09:
 * «the ground of the pages -- the contacts, the calls, the feed, the chats, the music, the VPN, the gallery and absolutely
 * all -- must be the one set as the page's ground»): the crest while nothing is chosen, else the ground chosen for my page,
 * softened the same way -- live under every pane; a choice made in Appearance redraws it at once. */
private fun mainGround(c: Context): View = FrameLayout(c).apply {
    fun fillIn() {
        removeAllViews()
        val choice = ChatWall.choice(ChatWall.PAGE)
        if (choice == ChatWall.Choice.General) addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
        else addView(c.groundView(choice).apply { softenPageGround() }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
    fillIn()
    val l: () -> Unit = { fillIn() }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { ChatWall.listen(l); fillIn() }
        override fun onViewDetachedFromWindow(v: View) { ChatWall.unlisten(l) }
    })
}

/**
 * THE GLASS OF A PLATE (iOS montanaOctagonFace(bar: true), MontanaOctagon.barMaterial = .ultraThinMaterial, MTGlassCirclePlate):
 * ONE TONE, NOT SEE-THROUGH (the word of 08.10.2026 16:5x: «one-tone glass on the buttons, not see-through»). The system's thin
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
    act.setGround(mainGround(c))
    var pane = Pane.CHATS   // iOS: the chats are the first page of a launch
    val panes = FrameLayout(c)
    val music = MusicPage(act)
    val feed = FeedPane(act)
    val chats = ChatsPane(act)
    var goContacts: () -> Unit = {}   // the calls' «New call» turns to the contacts (set once choose stands)
    val views = mapOf(Pane.CHATS to chats, Pane.CONTACTS to contactsPane(act), Pane.CALLS to callsPane(act) { goContacts() },
        Pane.FEED to feed, Pane.MUSIC to music.view, Pane.GALLERY to galleryPane(act),
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
        feed.reserve(on && pane == Pane.FEED)   // the write button steps above the bar, as the music's plus (iOS MTFeedTabView reserve)
        chats.reserve(on && pane == Pane.CHATS)   // the rows keep its room and «Write» steps above it too (iOS MontanaChatsList.swift:1021,1030 at 2155)
    }
    Playing.listen { if (player.isAttachedToWindow) showPlayer() }   // a track, a voice or a note: the one gate (iOS MontanaPlayerBar.Gate)
    // THE ONE SEARCH (iOS searchResults, [C-1]): the same field and the same results stand on the chats, the contacts and the
    // calls pages; while the search is on, the system's back puts it away first.
    val results = SearchResults(act).apply { visibility = View.GONE }
    var keepBack: (() -> Unit)? = null
    var searching = false
    lateinit var search: SearchRow
    var foldSearch: () -> Unit = {}   // the search folds with the panel unless it is in use (iOS barOpen || searchActive, 748)
    fun showResults() {
        foldSearch()
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
        if (p == Pane.CALLS) CallsSeen.clear()   // the calls page is looked at: the missed calls are seen (iOS 3010-3012)
        bar.badges()
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
    goContacts = { choose(Pane.CONTACTS) }
    val shell = DrawerShell(act)
    act.drawer = shell
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
            Motion.moveBegan(panes)   // the pane turned by the finger, measured to the settle's end (iOS MTTurnDrag's completion)
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
                Motion.moveEnded("pane:" + (if (go) to.name.lowercase() else "stay"))
            }.start()
            if (go) arrived(to)
            next = null
        }
    }
    bar = HomeBar(act, onDrawer = { shell.open() }, onPane = ::choose)
    bar.showPane(Pane.CHATS, animated = false)
    // FOLDED WITH THE BAR (iOS listHead 746-762, the author's word 10.09): the logo folds its glyphs and the search alike; what
    // stays under it is the search's own hairline (MTRowHairline 2247-2250: white 0.14, half a point, 29 from the leading edge,
    // twenty under the panel), and a tap on it unfolds both. A search in progress keeps its field.
    val hair = FrameLayout(c).apply {
        addView(View(c).apply { setBackgroundColor(Color.argb(36, 255, 255, 255)) },
            FrameLayout.LayoutParams(MATCH, maxOf(1, c.dp(0.5f)), Gravity.BOTTOM).apply { marginStart = c.dp(29) })
        pressable { bar.turn(true, "hairline") }
    }
    fun searchFolds() {
        val on = bar.open || search.active
        search.visibility = if (on) View.VISIBLE else View.GONE
        hair.visibility = if (on) View.GONE else View.VISIBLE
    }
    bar.onTurn = { searchFolds() }
    foldSearch = { searchFolds() }
    CoinPull.onSettled = { bar.turn(!bar.open, "coin") }   // every page under the bar: the coin's full turn presses the panel
    // THE LISTS RUN UNDER THE BAR (iOS: the list's top inset is measured from the bar as drawn, MontanaOctagon 111-112; the word of
    // 08.10.2026 16:5x «the feed must run under the buttons»): the time panel and the search have no ground of their own — every
    // page's list keeps their height as its own room above and scrolls on beneath them; a page with nothing that scrolls keeps the
    // room itself, so nothing of it stands under the bar.
    val head = c.vstack(Gravity.NO_GRAVITY) {
        addView(bar, lp(MATCH, dp(60)).apply { setMargins(dp(12), dp(4), dp(12), dp(2)) })
        addView(search, lp(MATCH, dp(56)))
        addView(hair, lp(MATCH, dp(21)))
    }
    searchFolds()
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
        onChess = { shell.close { act.push { chessLobbyPage(act, it) } } }).also { d -> shell.onReveal = { (d.tag as? Runnable)?.run() } }, FrameLayout.LayoutParams(MATCH, MATCH))
    return shell
}

/**
 * THE DRAWER LIES UNDER THE PAGE (iOS MontanaDrawerHost): the page slides right by the drawer's width — 0.78 of the screen —
 * and dims; a tap on the dimmed page or the system's back closes it. iOS also opens it by a drag from the screen's left
 * edge; on Android that edge is the system's back gesture, and at the app's root that gesture drives this page one to one
 * with the finger (MainActivity.registerBack: edgeBegin, edgeMove, edgeEnd) — the author's word 09.10 11:5x.
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

    /** The system's back from the left edge at the app's root takes the page as a finger on it would (MainActivity.registerBack). */
    fun edgeBegin() { page.animate().cancel(); dim.animate().cancel(); reveal() }
    fun edgeMove(x: Float) {
        val t = x.coerceIn(0f, width78.toFloat())
        page.translationX = t
        dim.alpha = DIM * t / width78.coerceAtLeast(1)
    }
    fun edgeEnd(open: Boolean) = settle(open)

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
        // THE DRAWER'S MOTION IS MEASURED (iOS MTFrameMeter.moveBegan/moveEnded by the animator's completion, atom b19d306a9d08)
        Motion.moveBegan(page)
        dim.animate().alpha(if (open) DIM else 0f).setDuration(ms).start()
        page.animate().translationX(to).setDuration(ms).setInterpolator(android.view.animation.DecelerateInterpolator(1.6f)).withEndAction {
            if (!open) { dim.visibility = View.GONE; drawer.visibility = View.INVISIBLE }
            Motion.moveEnded("drawer:" + (if (open) "open" else "close"))
            then()
        }.start()
        if (open && !was) { keepBack = act.back; act.back = { close() } }
        if (!open && was) act.back = keepBack
    }

    /** Asked each time the drawer comes out: its rows' counts are read then (iOS MTApplication.badge, read by every pass). */
    var onReveal: (() -> Unit)? = null

    private fun reveal() {
        onReveal?.invoke()
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
    // A ROW OF THE 1949 LIST (iOS MontanaSideDrawer.row, ContentView.swift:1713-1728): the icon 30, the word 22 bold, the page's own
    // count -- 22 apart, the count beside the word, not at the far edge
    val counts = ArrayList<Pair<android.widget.TextView, () -> Int>>()
    fun row(icon: View, word: Int, count: (() -> Int)? = null, onTap: (() -> Unit)?) = c.hstack {
        setPadding(0, dp(16), 0, dp(16))
        addView(icon, lp(dp(30), dp(30)))
        gap(22)
        addView(c.text(c.getString(word), 22f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(WRAP, WRAP))
        if (count != null) {
            val badge = c.countBadge()
            counts.add(badge to count)
            addView(badge, lp(WRAP, dp(20)).apply { marginStart = dp(22) })
        }
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
        addView(row(glyph(R.drawable.ic_bar_calls), R.string.app_calls, { CallsSeen.unseen() }) { onPane(Pane.CALLS) }, lp())
        addView(row(feedMark(), R.string.app_feed) { onPane(Pane.FEED) }, lp())
        // THE COUNTS (iOS MTApplication.badge, ContentView.swift:1489-1498): the chats with something unread, the groups' and the channels' each their own
        addView(row(glyph(R.drawable.ic_bar_chats), R.string.chats, { Book.all().count { !Groups.isKey(it.ref) && ChatMarks.hasUnread(it) } }) { onPane(Pane.CHATS) }, lp())
        // the groups and the channels, apps of their own under the chats (iOS MTApplication .groups, .channels: person.3.fill, megaphone.fill)
        addView(row(glyph(R.drawable.ic_app_groups), R.string.app_groups, { Book.all().count { Groups.isKey(it.ref) && !Groups.isChannel(it.ref) && ChatMarks.hasUnread(it) } }) { onPane(Pane.GROUPS) }, lp())
        addView(row(glyph(R.drawable.ic_app_channels), R.string.app_channels, { Book.all().count { Groups.isChannel(it.ref) && ChatMarks.hasUnread(it) } }) { onPane(Pane.CHANNELS) }, lp())
        addView(row(glyph(R.drawable.ic_bar_play), R.string.app_music) { onPane(Pane.MUSIC) }, lp())
        addView(row(glyph(R.drawable.ic_app_gallery), R.string.app_gallery) { onPane(Pane.GALLERY) }, lp())
        addView(row(android.widget.ImageView(c).apply { setImageResource(R.drawable.chess_knight) }, R.string.app_chess, onTap = onChess), lp())   // chess (iOS MTChessPage)
        addView(row(glyph(R.drawable.ic_app_wallet), R.string.app_wallet, onTap = onWallet), lp())   // TimeCoin (iOS MTWalletPage)
        // THE WALLS BESIDE THE FEED (iOS MTApplication .meshWall, .p2pWall; the author's word 29.09): the people around, phone to
        // phone; the nodes this phone reaches
        addView(row(glyph(R.drawable.ic_set_antenna), R.string.app_mesh_wall) { onPane(Pane.MESH) }, lp())
        addView(row(glyph(R.drawable.ic_language), R.string.app_p2p_wall) { onPane(Pane.P2P) }, lp())
        addView(row(glyph(R.drawable.ic_app_card), R.string.app_card, onTap = onCard), lp())   // the business card (iOS MTCardFromDrawer, the author's word 28.09)
        // PASSWORDS (iOS MTApplication .passwords, key.fill, the author's word 06.10.2026 17:4x MSK): a page of its own over the tabs
        addView(row(glyph(R.drawable.ic_key), R.string.pw_title, onTap = onPasswords), lp())
        spacer()
        addView(row(glyph(R.drawable.ic_settings), R.string.settings, onTap = onSettings), lp())
        addView(c.text(appVersionFull(c), 11f, MT.gray).apply { setPadding(dp(52), 0, 0, dp(8)) }, lp())   // USER-DATA: the build's own number
    }
    return ScrollView(c).apply {
        isFillViewport = true
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        addView(column)
        tag = Runnable { for ((badge, count) in counts) badge.showCount(count()) }   // the drawer's counts, read when it comes out
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
    // THE BADGES ON THE TIME PANEL (iOS MontanaChatsList.swift:369, 394, glyphBadge 461-465): the missed calls unseen where the calls
    // live, the chats with something unread where the chats live -- the platform's corner badge, 10 right and 4 up of the glyph's corner
    private val callsBadge = act.countBadge()
    private val chatsBadge = act.countBadge()
    private val logoBadge = act.countBadge()
    /** Unfolded, the missed calls on the calls glyph and the unread on the chats glyph; folded, their sum on the logo (iOS 369-394, panelBadge 486). */
    fun badges() {
        val calls = CallsSeen.unseen()
        val chats = Book.all().count { ChatMarks.hasUnread(it) }
        callsBadge.showCount(if (open) calls else 0)
        chatsBadge.showCount(if (open) chats else 0)
        logoBadge.showCount(if (open) 0 else calls + chats)
    }

    /**
     * THE PANEL FOLDS AND UNFOLDS IN ONE PLACE (iOS turnPanel 468-479, barSlot 504-518, the author's words 10.09, 21.09, 25.09):
     * folded, every glyph but the logo has no width and fades into it and takes no touch, the plate hugs the logo at the
     * screen's centre; the coin's pull turns it, the logo on the folded plate and the search's hairline unfold it and the page
     * stays; unfolded by default, the last choice kept; every turn is a line of the diary (panel open= by=).
     */
    var open = Prefs.bool(OPEN, true)
        private set
    var onTurn: ((Boolean) -> Unit)? = null
    private val slots = ArrayList<View>()
    private lateinit var logoBox: View
    private var fold = if (open) 1f else 0f
    private var turning: android.animation.ValueAnimator? = null
    fun turn(to: Boolean, by: String) {
        if (to == open) return
        open = to
        Prefs.setBool(OPEN, to)
        android.util.Log.d("Montana", "panel open=" + (if (to) 1 else 0) + " by=" + by)
        onTurn?.invoke(to)
        badges()
        turning?.cancel()
        Motion.moveBegan(null)   // the time panel's fold, measured to the spring's end (iOS turnPanel, atom b19d306a9d08)
        turning = android.animation.ValueAnimator.ofFloat(fold, if (to) 1f else 0f).apply {
            duration = 600
            interpolator = SwiftSpring(0.45, 0.82, 0.6)   // the coin's own spring (iOS .spring(response: 0.45, dampingFraction: 0.82))
            addUpdateListener { applyFold(it.animatedValue as Float) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { Motion.moveEnded("panel:" + (if (to) "open" else "fold")) }
            })
            start()
        }
    }
    private fun applyFold(raw: Float) {
        val f = raw.coerceIn(0f, 1f)
        fold = f
        for (s in slots) {
            val l = s.layoutParams as? LinearLayout.LayoutParams ?: continue
            if (l.weight != f) { l.weight = f; s.layoutParams = l }
            s.alpha = f
            s.visibility = if (f <= 0f) View.INVISIBLE else View.VISIBLE
        }
        val full = ((parent as? View)?.width ?: 0) - dp(24)
        (layoutParams as? LinearLayout.LayoutParams)?.let { lpb ->
            val w = if (f >= 1f || full <= 0) LinearLayout.LayoutParams.MATCH_PARENT else (height + (full - height) * f).toInt()
            if (lpb.width != w || lpb.gravity != Gravity.CENTER_HORIZONTAL) { lpb.width = w; lpb.gravity = Gravity.CENTER_HORIZONTAL; layoutParams = lpb }
        }
        post { place(false) }
    }
    private var foldLaid = false
    private lateinit var media: ImageView
    private lateinit var globe: ImageView

    init {
        background = act.glassPlate()
        addView(puck, LayoutParams(0, 0))
        addView(row, LayoutParams(MATCH, MATCH))
        glyph(R.drawable.ic_bar_drawer, 26) { onDrawer(it) }
        glyph(R.drawable.ic_bar_contacts, 26) { onPane(Pane.CONTACTS) }
        glyph(R.drawable.ic_bar_calls, 26, badge = callsBadge) { onPane(Pane.CALLS) }
        // THE LOGO ON THE GLASS (iOS MTFeedGlyph): the gold sign on a round glass plate, a quarter of its side around it.
        logoBox = FrameLayout(act).apply {
            clipChildren = false
            addView(FrameLayout(act).apply {
                background = act.glassPlate(oval = true)
                addView(ImageView(act).apply { setImageResource(R.drawable.logo); setPadding(dp(9), dp(9), dp(9), dp(9)) },
                    LayoutParams(MATCH, MATCH))
            }, LayoutParams(dp(36), dp(36), Gravity.CENTER))
            addView(logoBadge, LayoutParams(WRAP, dp(20), Gravity.CENTER))
            logoBadge.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
                v.translationX = dp(36) / 2f + dp(10) - v.width / 2f
                v.translationY = -dp(36) / 2f - dp(4) + v.height / 2f
            }
            // the logo opens the feed of my people's walls (iOS 25.09); folded, it unfolds the panel and the page stays (iOS 379)
            pressable { if (open) onPane(Pane.FEED) else turn(true, "logo") }
        }
        row.addView(logoBox, lp(0, MATCH, 1f))
        glyph(R.drawable.ic_bar_chats, 24, badge = chatsBadge) { onPane(Pane.CHATS) }
        // THE DYNAMIC GLYPH: the last opened of the player and the gallery; a tap opens that one again.
        media = glyph(R.drawable.ic_bar_play, 26) { onPane(if (Prefs.str("lastMediaPane", "music") == "gallery") Pane.GALLERY else Pane.MUSIC) }
        if (Prefs.str("lastMediaPane", "music") == "gallery") media.setImageResource(R.drawable.ic_app_gallery)
        // THE GLOBE (iOS MTBarGlobe, MontanaTransportIcon): the network's lamp — green while a machine is held, red while none is,
        // grey before the first knock (unknown is not «no»); a tap chooses the P2P wall (the author's word 25.09)
        globe = glyph(R.drawable.ic_language, 26, tint = Color.rgb(115, 115, 115)) { onPane(Pane.P2P) }
        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            place(false)
            if (!foldLaid && width > 0) { foldLaid = true; if (!open) post { applyFold(0f) } }   // a panel left folded is born folded
        }
        val lamp = object : Runnable {
            override fun run() {
                val up = Channels.nodesHeld() > 0
                globe.imageTintList = android.content.res.ColorStateList.valueOf(if (up) MT.green else if (Channels.knocked) MT.red else Color.rgb(115, 115, 115))
                postDelayed(this, 2000)
            }
        }
        val heard: () -> Unit = { act.onMain { badges() } }
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { post(lamp); Book.listen(heard); ChatMarks.listen(heard); badges() }
            override fun onViewDetachedFromWindow(v: View) { removeCallbacks(lamp); Book.unlisten(heard); ChatMarks.unlisten(heard) }
        })
    }

    private fun glyph(res: Int, sizeDp: Int, tint: Int = barGlyph, badge: android.widget.TextView? = null, onTap: ((View) -> Unit)? = null): ImageView {
        val box = FrameLayout(act).apply { clipChildren = false }
        val icon = act.icon(res, tint)
        box.addView(icon, LayoutParams(dp(sizeDp), dp(sizeDp), Gravity.CENTER))
        if (badge != null) {
            box.addView(badge, LayoutParams(WRAP, dp(20), Gravity.CENTER))
            // its top-trailing at the glyph's top-trailing, then 10 to the right and 4 up (iOS .offset(x: 10, y: -4))
            badge.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
                v.translationX = dp(sizeDp) / 2f + dp(10) - v.width / 2f
                v.translationY = -dp(sizeDp) / 2f - dp(4) + v.height / 2f
            }
        }
        if (onTap != null) box.pressable { onTap(box) }
        row.addView(box, lp(0, MATCH, 1f))
        slots.add(box)
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

    private fun slotView(i: Int): View? = when { i < 0 -> null; i < 3 -> slots.getOrNull(i); i == 3 -> logoBox; else -> slots.getOrNull(i - 1) }
    private fun place(animated: Boolean) {
        val v = slotView(slot)
        // folded, only the logo has a place for the puck (iOS: a folded slot has no width)
        puck.visibility = if (v == null || (fold < 1f && slot != 3)) View.INVISIBLE else View.VISIBLE
        if (width == 0 || v == null) return
        val w = if (v.width > 0) v.width.toFloat() else width / 7f
        val lpk = puck.layoutParams as LayoutParams
        val pw = (w - dp(6)).toInt(); val ph = height - dp(12)
        if (lpk.width != pw || lpk.height != ph) {
            lpk.width = pw; lpk.height = ph; lpk.topMargin = dp(6)
            post { puck.layoutParams = lpk }
        }
        val x = (if (v.width > 0) v.left.toFloat() else slot * w) + dp(3)
        if (animated) puck.animate().translationX(x).setDuration(200).setInterpolator(AccelerateDecelerateInterpolator()).start()
        else puck.translationX = x
    }

    private companion object { const val CHATS = 4; const val OPEN = "timePanelOpen" }
}

/**
 * THE PLATFORM'S SPRING, AS SWIFTUI DRAWS IT (.spring(response:dampingFraction:)): the damped oscillator whose undamped period
 * is the response, read over `seconds` -- one curve for a move the iPhone springs.
 */
class SwiftSpring(response: Double, private val damping: Double, private val seconds: Double) : android.view.animation.Interpolator {
    private val w0 = 2 * Math.PI / response
    private val wd = w0 * Math.sqrt(1 - damping * damping)
    override fun getInterpolation(f: Float): Float {
        if (f >= 1f) return 1f
        val t = f * seconds
        val e = Math.exp(-damping * w0 * t)
        return (1 - e * (Math.cos(wd * t) + damping * w0 / wd * Math.sin(wd * t))).toFloat()
    }
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

/** Words compared as a person reads them: case and marks aside, the dotted e as the plain one (iOS .caseInsensitive, .diacriticInsensitive). */
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
/** THE CHATS LIST KEEPS ITS OWN ROOM FOR THE FLOATING PLAYER TOO (iOS MontanaChatsList.swift:856,1021,1030 at 2155,
 *  atoms 93ab0f2ba212 and eb49f096614a): the rows reserve the bar's room at the foot while it stands, and «Write»
 *  steps above it, as the music's plus (MusicPage.reserve) and the feed's write (FeedPane.reserve) do. */
private class ChatsPane(private val act: MainActivity) : FrameLayout(act) {
    private val c = act
    // THE SELECTION (iOS selecting): «Select» in a row's menu begins it; the bar at the foot acts on the chosen chats
    private val bar = FrameLayout(c).apply { visibility = View.GONE }
    private lateinit var write: View
    private lateinit var redrawRows: () -> Unit
    private var archiveRevealed = false   // the archive's row is summoned by a pull (iOS archiveRevealed)
    private var revealArchive: (Boolean) -> Unit = {}
    private val foot = View(c)   // the floating player's room at the foot (reserve)
    private val sel = ChatSelection { s ->
        redrawRows()
        bar.removeAllViews()
        if (s.on) bar.addView(selectionBar(act, s), FrameLayout.LayoutParams(MATCH, WRAP))
        bar.visibility = if (s.on) View.VISIBLE else View.GONE
        write.visibility = if (s.on) View.GONE else View.VISIBLE
    }
    private val list = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        addView(c.vstack(Gravity.NO_GRAVITY) {
            // The local room: stands in the list from the first moment; a tap opens it (iOS: the row opens its conversation).
            val preview = c.text("", 16f, MT.gray).apply { maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }
            val time = c.text("", 14f, MT.gray)
            val face = FrameLayout(c)
            fun refresh() {
                // Saved Messages wears one's own face (iOS MTSelfFace, the author's word 11.09): read again on every return
                face.removeAllViews()
                face.addView(c.avatar(SelfFace.load(c), Prefs.userName, 48))
                val last = SavedMessages.last(c)
                preview.text = last?.text ?: ""   // USER-DATA: one's own last letter
                preview.visibility = if (last == null) View.GONE else View.VISIBLE
                time.text = last?.let { rowTime(c, it.at) } ?: ""
            }
            refresh()
            // the local room's line in the chats page's measure (iOS ChatRow with library: 72, the face 48, the gap 16, the side 18; 22 and 20)
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(18), 0, dp(18), 0)
                minimumHeight = dp(72)
                addView(face, lp(dp(48), dp(48)).apply { marginEnd = dp(16) })
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.hstack {
                        gravity = Gravity.CENTER_VERTICAL
                        addView(c.text(c.getString(R.string.saved_messages), 17f, Color.WHITE, bold = true), lp(0, WRAP, 1f))
                        addView(time)
                    }, lp(MATCH, dp(22)))
                    addView(preview, lp(MATCH, dp(20)).apply { topMargin = dp(4) })
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
                // THE ARCHIVE'S ROW over the chats while it is summoned and something is archived (iOS archiveRevealed: a pull-down
                // summons it, a stroke up folds it -- the contacts' one law, «as on the chats»)
                val archived = archivedChats().size
                if (archiveRevealed && archived > 0 && !sel.on) {
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
            revealArchive = { on ->
                if (on != archiveRevealed && !(on && archivedChats().isEmpty())) {
                    archiveRevealed = on
                    fillRows()
                    if (on) rows.getChildAt(0)?.let { v ->
                        v.translationY = -c.dp(72).toFloat(); v.alpha = 0f
                        v.animate().translationY(0f).alpha(1f).setDuration(300).setInterpolator(android.view.animation.AccelerateDecelerateInterpolator()).start()
                    }
                }
            }
            fillRows()
            val onBook: () -> Unit = { act.onMain { fillRows() } }
            rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) { Book.listen(onBook); ChatMarks.listen(onBook); refresh(); fillRows() }
                override fun onViewDetachedFromWindow(v: View) { Book.unlisten(onBook); ChatMarks.unlisten(onBook) }
            })
            addView(rows, lp())
            addView(foot, lp(MATCH, dp(120)))
        })
    }
    /** The bar stands: the rows keep room under it and «Write» steps above it, as the music's plus and the feed's write. */
    fun reserve(on: Boolean) {
        foot.layoutParams = lp(MATCH, dp(if (on) 180 else 120)); foot.requestLayout()
        write.layoutParams = PageCorner.params(c, reserve = on)
    }
    init {
        // THE LIST'S OWN DRAG AND ITS FLING, MEASURED (iOS MTFrameMeter, MontanaMessageFeed.swift:268-437, 1125-1149).
        Motion.watch(list) { _, _, y, _, _ -> if (c.dp(25) < y) revealArchive(false) }   // a stroke up folds the archive's row
        addView(CoinPull(c, list).apply { onPull = { pull -> if (25f < pull) revealArchive(true) } }, FrameLayout.LayoutParams(MATCH, MATCH))   // the coin's pull refreshes the feed (iOS MontanaCoinSpinner) and summons the archive's row
        // «WRITE» (iOS composeButton): the one door to the code and the link — the QR opens here and nowhere else.
        write = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.share)
            addView(c.icon(R.drawable.ic_compose, barGlyph), FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
            pressable { act.push { cardPage(act, it) } }
        }
        addView(write, PageCorner.params(c))
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
        }, PageCorner.params(c))
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
        addView(contactsList(act), FrameLayout.LayoutParams(MATCH, MATCH))   // the coin's pull inside: one law for every page under the bar
        // THE CHATS PAGE'S COMPOSE BUTTON ONE TO ONE (iOS ContactsTabView 2777-2786: «the plate, the size», mtPageAction; MTPageCorner:
        // the bar's tier of 60, 16 from the edge): the share glyph on it, as «Write» wears its pencil
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.share)
            addView(c.icon(R.drawable.ic_share, barGlyph), FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER))
            pressable { shareCard(act) }   // the one share of one's card (iOS MontanaCardShare)
        }, PageCorner.params(c))
    }
}
