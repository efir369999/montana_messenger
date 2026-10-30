package quest.montana.app

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.SystemClock
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.PopupWindow
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import java.text.DateFormat
import java.text.Normalizer
import java.util.Date
import java.util.Locale

/** WHEN THE GLOBE WAS TOUCHED (iOS MontanaVPNOpen): the page cannot time its own opening, so the touch leaves the instant here and the
 *  page says how long it took, once. */
object VpnOpen {
    private var tappedAt = 0L
    fun tap() { tappedAt = SystemClock.elapsedRealtime() }
    fun msSinceTap(): Long? { if (tappedAt == 0L) return null; val ms = SystemClock.elapsedRealtime() - tappedAt; tappedAt = 0L; return ms }
}

/** THE VPN'S OWN GLYPH (iOS MontanaVPNGlyph): the author's globe on a stand (the MontanaVPNGlobe asset, a template), tinted. */
fun Context.vpnGlyph(tint: Int, sizeDp: Int): ImageView = ImageView(this).apply {
    setImageResource(R.drawable.mt_vpn_globe)
    imageTintList = ColorStateList.valueOf(tint)
    scaleType = ImageView.ScaleType.FIT_CENTER
    layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
}

/** A SERVER'S FLAG IS ITS CHIP (iOS mtServerIcon): the first emoji of the name stands on the tile and the title goes on without it. */
fun vpnServerIcon(name: String): Pair<String?, String> {
    val t = name.trim()
    val chars = android.icu.text.BreakIterator.getCharacterInstance().apply { setText(t) }
    var start = chars.first()
    var end = chars.next()
    while (end != android.icu.text.BreakIterator.DONE) {
        val g = t.substring(start, end)
        if (vpnIsEmoji(g)) {
            var clean = t.replaceFirst(g, "")
            while (clean.contains("  ")) clean = clean.replace("  ", " ")
            clean = clean.trim()
            return g to clean.ifEmpty { t }
        }
        start = end; end = chars.next()
    }
    return null to t
}
/** iOS Character.mtIsEmoji: a joined character is a glyph when any of its scalars is; a lone one above U+238C. */
private fun vpnIsEmoji(g: String): Boolean {
    val points = g.codePoints().toArray()
    if (points.isEmpty()) return false
    if (1 < points.size) return points.any { android.icu.lang.UCharacter.hasBinaryProperty(it, android.icu.lang.UProperty.EMOJI) }
    return android.icu.lang.UCharacter.hasBinaryProperty(points[0], android.icu.lang.UProperty.EMOJI) && 0x238C < points[0]
}
/** iOS mtPingColor: under 120 green, under 250 orange, else red. */
fun vpnPingColor(ms: Int): Int = if (ms < 120) MT.green else if (ms < 250) MT.orange else MT.red

/**
 * 3D CONVEX POWER BUTTON (iOS MontanaVPNPowerButton, MontanaNetworkView.swift:1014-1052): red off, amber connecting, green on -- the
 * ambient glow 184, the 150 circle with its convex highlight, its bottom shade and its rim, two shadows under it, and the power glyph
 * (60 heavy) or the platform's spinner; the state moves in 0.22 s. THE BUTTON IS THE POWER AND NOTHING ELSE (the author's word 29.09).
 */
class VpnPowerButton(c: Context) : FrameLayout(c) {
    enum class S { OFF, CONNECTING, ON }
    private fun colorOf(s: S) = when (s) {
        S.OFF -> Color.rgb(232, 59, 51)        // 0.91, 0.23, 0.20
        S.CONNECTING -> Color.rgb(245, 158, 38) // 0.96, 0.62, 0.15
        S.ON -> Color.rgb(48, 204, 92)          // 0.19, 0.80, 0.36
    }
    var state: S? = null; private set
    private var tint = colorOf(S.OFF)
    private var turn: ValueAnimator? = null
    private val d = resources.displayMetrics.density
    private val face = object : View(c) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val circle = Path()
        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f; val cy = height / 2f
            val r = 75 * d
            fun alpha(col: Int, a: Float) = Color.argb((a * 255).toInt(), Color.red(col), Color.green(col), Color.blue(col))
            // the ambient glow: 184 across, the colour at 0.22, blurred 16
            p.reset(); p.isAntiAlias = true; p.color = alpha(tint, 0.22f); p.maskFilter = BlurMaskFilter(16 * d, BlurMaskFilter.Blur.NORMAL)
            canvas.drawCircle(cx, cy, 92 * d, p)
            p.maskFilter = null
            // the two shadows under the circle: the colour's (22, y 8) and the black's (9, y 10)
            p.color = Color.BLACK
            p.setShadowLayer(9 * d, 0f, 10 * d, alpha(Color.BLACK, 0.6f)); canvas.drawCircle(cx, cy, r, p)
            p.color = tint
            p.setShadowLayer(22 * d, 0f, 8 * d, alpha(tint, 0.65f)); canvas.drawCircle(cx, cy, r, p)
            p.clearShadowLayer()
            canvas.drawCircle(cx, cy, r, p)
            canvas.save()
            circle.reset(); circle.addCircle(cx, cy, r, Path.Direction.CW)
            canvas.clipPath(circle)
            val left = cx - r; val top = cy - r; val side = 2 * r
            // the convex top highlight: white 0.7 to clear, from (0.34, 0.24), 2 to 82
            p.shader = RadialGradient(left + 0.34f * side, top + 0.24f * side, 82 * d, intArrayOf(alpha(Color.WHITE, 0.7f), alpha(Color.WHITE, 0.7f), Color.TRANSPARENT),
                floatArrayOf(0f, 2f / 82f, 1f), Shader.TileMode.CLAMP)
            canvas.drawCircle(cx, cy, r, p)
            // the bottom shade: clear to black 0.38, from (0.7, 0.85), 24 to 96
            p.shader = RadialGradient(left + 0.7f * side, top + 0.85f * side, 96 * d, intArrayOf(Color.TRANSPARENT, Color.TRANSPARENT, alpha(Color.BLACK, 0.38f)),
                floatArrayOf(0f, 24f / 96f, 1f), Shader.TileMode.CLAMP)
            canvas.drawCircle(cx, cy, r, p)
            // the rim: white 0.6, clear, black 0.4 from top to bottom, 2 wide on the edge (its inner half within the clip)
            p.shader = LinearGradient(0f, top, 0f, top + side, intArrayOf(alpha(Color.WHITE, 0.6f), Color.TRANSPARENT, alpha(Color.BLACK, 0.4f)), null, Shader.TileMode.CLAMP)
            p.style = Paint.Style.STROKE; p.strokeWidth = 2 * d
            canvas.drawCircle(cx, cy, r, p)
            p.style = Paint.Style.FILL; p.shader = null
            canvas.restore()
        }
    }.apply { setLayerType(View.LAYER_TYPE_SOFTWARE, null) }   // the blur and the shadows of shapes are drawn by the software canvas
    /** The power glyph, 60 heavy, with its shadow (black 0.45, 3, y 2). */
    private val glyph = object : View(c) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; color = Color.WHITE; strokeWidth = 7.5f * d
            setShadowLayer(3 * d, 0f, 2 * d, Color.argb(115, 0, 0, 0))
        }
        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f; val cy = height / 2f + 3 * d
            val r = 23 * d
            canvas.drawArc(RectF(cx - r, cy - r, cx + r, cy + r), -50f, 280f, false, p)
            canvas.drawLine(cx, cy - r - 6 * d, cx, cy - 3 * d, p)
        }
    }.apply { setLayerType(View.LAYER_TYPE_SOFTWARE, null) }
    private val spinner = ProgressBar(c).apply { indeterminateTintList = ColorStateList.valueOf(Color.WHITE); visibility = View.GONE }

    init {
        clipChildren = false; clipToPadding = false
        addView(face, LayoutParams((240 * d).toInt(), (240 * d).toInt(), Gravity.CENTER))   // the glow and the shadows run past the 190 frame
        addView(glyph, LayoutParams((80 * d).toInt(), (80 * d).toInt(), Gravity.CENTER))
        addView(spinner, LayoutParams((38 * d).toInt(), (38 * d).toInt(), Gravity.CENTER))
        contentDescription = "power"
    }
    fun show(s: S, animated: Boolean) {
        if (state == s) return
        val first = state == null
        state = s
        glyph.visibility = if (s == S.CONNECTING) View.GONE else View.VISIBLE
        spinner.visibility = if (s == S.CONNECTING) View.VISIBLE else View.GONE
        val to = colorOf(s)
        turn?.cancel()
        if (!animated || first) { tint = to; face.invalidate(); return }
        val from = tint
        turn = ValueAnimator.ofObject(ArgbEvaluator(), from, to).apply {
            duration = 220   // iOS .easeInOut(duration: 0.22)
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener { tint = it.animatedValue as Int; face.invalidate() }
            start()
        }
    }
}

/**
 * THE VPN WALL (iOS NetworkTabView on the globe's pane, MontanaNetworkView.swift:108-997; the author's word 25.09 «a full page under the
 * time panel, with no border above or below»): the head -- the line saying what the wall is, the power, the live timer, the tunnel's
 * own error, the road's word, the page's line --, then every plan as a section of its own and the hand-added servers where their pin
 * puts them, each server a row of the library's measure. A tap chooses a server, a hold opens its menu, the swipe from the right pins
 * or deletes it; the plus at the bottom right is the one road every exit node comes in by; the coin's pull loads the plans again; the
 * page searches itself.
 */
class VpnWallPage(private val act: MainActivity) {
    private val c: Context = act
    private val side = c.dp(18)   // iOS MTLibraryRow.side
    private val rows = c.vstack(Gravity.NO_GRAVITY).apply { clipChildren = false }
    private val scroll = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        clipChildren = false
        addView(c.vstack(Gravity.NO_GRAVITY) { clipChildren = false; addView(rows, lp()); gap(120) })   // the foot's room, as the walls'
    }
    val view: FrameLayout = FrameLayout(c)

    private var query = ""
    private var note: String? = null
    private var busy = false            // iOS vpnBusy
    private var loadingPlan: String? = null
    private var servers: List<VpnConfig> = emptyList()
    private var byId: Map<String, VpnConfig> = emptyMap()
    private var byPlan: Map<String, List<VpnConfig>> = emptyMap()
    private var manual: List<VpnConfig> = emptyList()
    private var plans: List<VpnPlan> = emptyList()
    private var manualExpanded = !VpnPlans.manualFolded
    private var manualPinnedAt = VpnPlans.manualPinnedAt
    /** THE ROWS ARE PRINTED BY WHAT THEY DRAW (iOS rowPrint): a row whose print did not change keeps its view. */
    private val cache = HashMap<String, Pair<Int, View>>()

    // ── the head ──
    private val power = VpnPowerButton(c).apply { pressable { toggle() } }
    private val timer = c.text("", 36f, MT.green, bold = true, center = true).apply { typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD); visibility = View.GONE }
    private val error = c.text("", 12f, MT.red, center = true).apply { visibility = View.GONE }
    private val road = c.text("", 12f, MT.secondary, center = true).apply { visibility = View.GONE }
    private val noteLine = c.text("", 12f, MT.secondary).apply { visibility = View.GONE }
    private val empty = c.text(c.getString(R.string.vpn_add_hint), 16f, MT.secondary).apply { visibility = View.GONE; setPadding(side, c.dp(12), side, c.dp(12)) }
    private val head: View = c.vstack {
        clipChildren = false; clipToPadding = false   // the power's glow runs past its frame (SwiftUI draws it so)
        setPadding(c.dp(12), 0, c.dp(12), c.dp(6))
        addView(c.text(c.getString(R.string.vpn_caption), 13f, MT.secondary, center = true).apply { setPadding(c.dp(28), c.dp(16), c.dp(28), 0) }, lp())
        gap(16 + 8)
        addView(power, lp(c.dp(190), c.dp(190)))
        addView(timer, lp().apply { topMargin = c.dp(16) })
        addView(error, lp().apply { topMargin = c.dp(16); marginStart = c.dp(16); marginEnd = c.dp(16) })
        addView(road, lp().apply { topMargin = c.dp(16); marginStart = c.dp(16); marginEnd = c.dp(16) })
        addView(noteLine, lp().apply { topMargin = c.dp(16) })
        addView(empty, lp().apply { topMargin = c.dp(16) })
    }

    init {
        // THE ROWS RUN ON TO THE SCREEN'S EDGES (iOS MontanaTimePanelList): the one fade under the bar and at the screen's foot, and the
        // coin's pull -- on this page it loads every plan again (iOS onRefresh: MontanaVPNFreshener.coinRefresh)
        view.addView(EdgeSink(c, top = { scroll.paddingTop + c.dp(34) }, bottom = { view.height }).apply {
            addView(CoinPull(c, scroll) { Thread({ VpnFreshener.coinRefresh() }, "mt-vpn-pull").start() }, FrameLayout.LayoutParams(MATCH, MATCH))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        // THE PLUS, bottom right, as the music's plus and the chats' write (iOS mtPageAction): the road every exit node comes in by
        view.addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.vpn_add_exit)
            addView(c.icon(R.drawable.ic_plus, MT.barGlyph), FrameLayout.LayoutParams(c.dp(28), c.dp(28), Gravity.CENTER))
            pressable { plusMenu(this) }
        }, PageCorner.params(c))
        val heard: () -> Unit = { reload(log = false) }
        val tick = object : Runnable {
            override fun run() { drawTimer(); view.postDelayed(this, 1000) }
        }
        view.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { VpnBus.listen(heard); view.post(tick) }
            override fun onViewDetachedFromWindow(v: View) { VpnBus.unlisten(heard); view.removeCallbacks(tick) }
        })
        reload(log = false)
    }

    /** THE PAGE OPENS BY THE PANE'S CHOICE (iOS onChange(of: ui.pane) 307-314): the tunnel read, the list read; nothing loaded. */
    fun opened() {
        val open = VpnOpen.msSinceTap()
        vpnMark("vpn_ui", "page plans=${plans.size} manual=${manual.size} all=${servers.size} tunnel=${VpnTunnel.statusText()} open_ms=${open ?: "-"}")
        VpnTunnel.load()
        reload()
    }
    /** THE PAGE'S OWN SEARCH (iOS query): the word narrows the servers by name, host, protocol, transport and wrapper. */
    fun search(q: String) { val w = q.trim(); if (w == query) return; query = w; draw() }

    private fun fold(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)
    private fun matches(cfg: VpnConfig): Boolean {
        if (query.isEmpty()) return true
        val w = fold(query)
        return listOf(cfg.name, cfg.host, cfg.proto.raw, cfg.network, cfg.security).any { fold(it).contains(w) }   // iOS localizedStandardContains
    }

    private fun reload(log: Boolean = true) {
        val t0 = SystemClock.elapsedRealtime()
        servers = VpnStore.load()
        val ids = HashMap<String, VpnConfig>()
        val plan = HashMap<String, MutableList<VpnConfig>>()
        val hand = ArrayList<VpnConfig>()
        for (cfg in servers) {
            ids.putIfAbsent(cfg.id, cfg)
            val sub = cfg.subscription
            if (sub != null) plan.getOrPut(sub) { ArrayList() }.add(cfg) else hand.add(cfg)
        }
        byId = ids; byPlan = plan; manual = hand
        plans = VpnPlans.ordered()
        manualPinnedAt = VpnPlans.manualPinnedAt
        if (log) vpnMark("vpn_ui", "list plans=${plans.size} manual=${manual.size} all=${servers.size} ms=${SystemClock.elapsedRealtime() - t0}")
        if (byId[VpnTunnel.selectedId] == null) VpnSelection.adopt(servers.firstOrNull()?.id ?: "")
        draw()
    }

    private fun selected(): VpnConfig? = byId[VpnTunnel.selectedId]
    private fun measuring(list: List<VpnConfig>): Boolean { val f = VpnPingLine.inFlight; return f.isNotEmpty() && list.any { it.id in f } }

    // ── the rows (iOS rows, rowPrint, cell) ──

    private fun draw() {
        drawHead()
        val out = ArrayList<Pair<String, () -> Pair<Int, View>>>()
        out.add("net:head" to { 0 to head })
        val slot = VpnPlans.manualSlot(plans, manualPinnedAt)
        fun planRows(p: VpnPlan) {
            val list = byPlan[p.url].orEmpty()
            val found = list.filter(::matches)
            if (query.isNotEmpty() && found.isEmpty() && !fold(p.shownTitle).contains(fold(query))) return
            out.add("plan:" + p.url to { planPrint(p, list) to planHeader(p, list) })
            if (query.isNotEmpty() || p.folded != true) for (cfg in found) out.add("srv:" + cfg.id to { serverPrint(cfg) to serverCell(cfg) })
        }
        plans.take(slot).forEach(::planRows)
        val hand = manual.filter(::matches)
        if (hand.isNotEmpty()) {
            out.add("net:manual" to { manualPrint() to manualHeader() })
            if (manualExpanded || query.isNotEmpty()) for (cfg in hand) out.add("srv:" + cfg.id to { serverPrint(cfg) to serverCell(cfg) })
        }
        plans.drop(slot).forEach(::planRows)
        if (query.isNotEmpty() && out.size == 1) out.add("net:none" to { 0 to c.text(c.getString(R.string.nothing_found), 17f, MT.gray, center = true).apply { setPadding(0, c.dp(24), 0, c.dp(24)) } })
        val seen = HashSet<String>()
        val views = ArrayList<View>(out.size)
        for ((id, make) in out) {
            if (!seen.add(id)) continue   // one row per identity, as the list that draws them
            val held = cache[id]
            val printNow = printOf(id)
            val v = if (held != null && printNow != null && held.first == printNow) held.second else make().also { cache[id] = it }.second
            views.add(v)
        }
        cache.keys.retainAll(seen)
        if (rows.childCount != views.size || views.indices.any { rows.getChildAt(it) !== views[it] }) {
            rows.removeAllViews()
            for (v in views) { (v.parent as? ViewGroup)?.removeView(v); rows.addView(v, lp()) }
        }
    }
    /** The print a row would wear now, or none for a row that is drawn afresh every time. */
    private fun printOf(id: String): Int? = when {
        id == "net:head" -> 0
        id == "net:manual" -> manualPrint()
        id.startsWith("plan:") -> plans.firstOrNull { it.url == id.removePrefix("plan:") }?.let { planPrint(it, byPlan[it.url].orEmpty()) }
        id.startsWith("srv:") -> byId[id.removePrefix("srv:")]?.let(::serverPrint)
        else -> null
    }
    private fun planPrint(p: VpnPlan, list: List<VpnConfig>): Int = listOf(p.lastError, p.unsupported, list.size, p.folded == true, p.pinnedAt, p.updatedAt,
        p.shownTitle, p.download, p.upload, p.total, p.expire, p.unsupportedKinds, loadingPlan == p.url || loadingPlan == "*", measuring(list)).hashCode()
    private fun manualPrint(): Int = listOf(manual.size, manualExpanded, manualPinnedAt, plans.isEmpty(), measuring(manual)).hashCode()
    private fun serverPrint(cfg: VpnConfig): Int {
        val e = VpnDelayBook.entry(cfg.id)
        return listOf(cfg.name, cfg.proto.raw, cfg.network, cfg.security, cfg.engineOutbound == null, cfg.scheme, cfg.id == VpnTunnel.selectedId,
            e?.ms ?: -1, e?.err == null, e == null, (e?.age ?: 0.0) < VpnDelayBook.STALE, cfg.id in VpnPingLine.inFlight).hashCode()
    }

    // ── the head (iOS vpnHead 429-478) ──

    private fun drawHead() {
        val t = VpnTunnel
        val st = when (t.status) {
            VpnTunnel.Status.CONNECTED -> VpnPowerButton.S.ON
            VpnTunnel.Status.CONNECTING, VpnTunnel.Status.REASSERTING -> VpnPowerButton.S.CONNECTING
            else -> if (busy || t.requested) VpnPowerButton.S.CONNECTING else VpnPowerButton.S.OFF
        }
        power.show(st, animated = power.isAttachedToWindow)
        drawTimer()
        error.text = t.lastError; error.visibility = if (t.lastError.isEmpty()) View.GONE else View.VISIBLE
        val line = VpnRoad.line(c)
        road.text = line ?: ""; road.visibility = if (line == null) View.GONE else View.VISIBLE
        noteLine.text = note ?: ""; noteLine.visibility = if (note == null) View.GONE else View.VISIBLE
        empty.visibility = if (servers.isEmpty() && plans.isEmpty()) View.VISIBLE else View.GONE
    }
    /** Connected: the green live timer from the press (iOS Text(timerInterval:showsHours:) -- «0:42», «12:05», «1:02:03»). */
    private fun drawTimer() {
        val since = VpnTunnel.connectedAt
        if (VpnTunnel.status != VpnTunnel.Status.CONNECTED || since == null) { if (timer.visibility != View.GONE) timer.visibility = View.GONE; return }
        val s = maxOf(0L, (System.currentTimeMillis() - since) / 1000)
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        timer.text = if (0 < h) String.format(Locale.ROOT, "%d:%02d:%02d", h, m, sec) else String.format(Locale.ROOT, "%d:%02d", m, sec)   // USER-DATA: a duration
        timer.visibility = View.VISIBLE
    }
    private fun say(words: String?) { note = words; drawHead() }

    // ── the headers (iOS sectionHeader 501-540, planHeader 542-600, manualHeader 480-493) ──

    private fun roundMark(res: Int, sizeDp: Int, spin: Boolean, onTap: (View) -> Unit): View = FrameLayout(c).apply {
        if (spin) addView(ProgressBar(c).apply { indeterminateTintList = ColorStateList.valueOf(MT.secondary) }, FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
        else addView(c.icon(res, MT.secondary, sizeDp), FrameLayout.LayoutParams(c.dp(sizeDp), c.dp(sizeDp), Gravity.CENTER))
        if (!spin) pressable { onTap(this) }
    }
    private fun sectionHeader(expanded: Boolean, title: String, subtitle: String, busy: Boolean, onFold: () -> Unit, onRefresh: (() -> Unit)?,
                              onPing: (() -> Unit)?, measuring: Boolean, menu: () -> Unit): View = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(c.dp(6), c.dp(6), c.dp(6), c.dp(6))
        addView(roundMark(if (expanded) R.drawable.ic_chevron_down else R.drawable.ic_chevron_right, 16, false) { onFold() }, lp(c.dp(44), c.dp(44)))
        gap(4)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(title, 19f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())   // USER-DATA: a plan's own title, or its host
            gap(2)
            addView(c.text(subtitle, 12f, MT.secondary).apply { singleLineEllipsis() }, lp())
            pressable { onFold() }
        }, lp(0, WRAP, 1f))
        gap(4)
        if (onRefresh != null) { addView(roundMark(R.drawable.ic_vpn_circlepath, 22, busy) { onRefresh() }, lp(c.dp(44), c.dp(44))); gap(4) }
        if (onPing != null) { addView(roundMark(R.drawable.ic_vpn_gauge, 22, measuring) { onPing() }, lp(c.dp(44), c.dp(44))); gap(4) }
        addView(roundMark(R.drawable.ic_more_horiz, 22, false) { menu() }, lp(c.dp(44), c.dp(44)))
    }

    private fun stamp(t: Double): String = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT, locale()).format(Date((t * 1000).toLong()))
    private fun day(t: Double): String = DateFormat.getDateInstance(DateFormat.MEDIUM, locale()).format(Date((t * 1000).toLong()))
    private fun locale(): Locale = c.resources.configuration.locales[0] ?: Locale.getDefault()

    private fun planHeader(p: VpnPlan, list: List<VpnConfig>): View {
        val busyNow = loadingPlan == p.url || loadingPlan == "*"
        val expanded = p.folded != true
        val wall = VpnWallToken.isWallKey(p.url)
        val subtitle = when {
            0 < p.updatedAt -> stamp(p.updatedAt)   // USER-DATA: the moment of the last load that succeeded
            p.lastError != null -> c.getString(R.string.vpn_sub_failed_x, p.lastError)
            else -> c.getString(R.string.vpn_loading)
        }
        return c.vstack(Gravity.NO_GRAVITY) {
            setPadding(side, c.dp(12), side, 0)
            addView(sectionHeader(expanded, p.shownTitle, subtitle, busyNow, onFold = { foldPlan(p) }, onRefresh = { refreshPlan(p) },
                onPing = { pingAll(list) }, measuring = measuring(list)) {
                val items = mutableListOf(
                    VpnMenuItem(c.getString(if (p.pinnedAt == null) R.string.vpn_pin_sub else R.string.vpn_unpin_sub), if (p.pinnedAt == null) R.drawable.ic_pin else R.drawable.ic_pin_slash) { togglePin(p) },
                    VpnMenuItem(c.getString(R.string.vpn_update), R.drawable.ic_vpn_circlepath) { refreshPlan(p) })
                if (!wall) {
                    items.add(VpnMenuItem(c.getString(R.string.vpn_copy_link), R.drawable.ic_content_copy) { copy(p.url); say(c.getString(R.string.vpn_link_copied)) })
                    items.add(VpnMenuItem(c.getString(R.string.vpn_delete_sub), R.drawable.ic_delete, red = true) {
                        vpnMark("vpn_ui", "plan delete ${vpnPlanLabel(p.url)} rows=${list.size}")
                        VpnStore.removeSubscription(p.url); reload()
                    })
                }
                vpnMenu(act, p.shownTitle, null, items)
            }, lp())
            // folded, the plan is its one line; what the panel counts, and a failure under it, wait for the unfold
            if (expanded && !wall && 0 < p.updatedAt) addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(c.dp(12), 0, c.dp(6), 0)
                val used = (p.download ?: 0L) + (p.upload ?: 0L)
                val total = p.total ?: 0L
                addView(c.text(vpnBytes(used, locale()) + " / " + (if (0 < total) vpnBytes(total, locale()) else "∞"), 12f, Color.WHITE, bold = true).apply {
                    setPadding(c.dp(14), c.dp(5), c.dp(14), c.dp(5))   // USER-DATA: the bytes the panel counted; «∞» is its sign of no limit
                    background = android.graphics.drawable.GradientDrawable().apply { cornerRadius = c.dp(6).toFloat(); setStroke(c.dp(1), Color.argb(89, 255, 255, 255)) }
                }, lp(WRAP, WRAP))
                val e = p.expire
                if (e != null && 0 < e) { gap(10); addView(c.text(c.getString(R.string.vpn_expires, day(e)), 12f, Color.argb(230, 255, 255, 255)), lp(WRAP, WRAP)) }
                spacer()
                addView(roundMark(R.drawable.ic_link, 20, false) { copy(p.url); say(c.getString(R.string.vpn_link_copied)) }, lp(c.dp(44), c.dp(44)))
            }, lp())
            val n = p.unsupported ?: 0
            if (expanded && 0 < n) addView(c.text(c.getString(R.string.vpn_unsupported_n, n, p.unsupportedKinds ?: ""), 12f, MT.secondary).apply {
                setPadding(c.dp(12), c.dp(4), c.dp(12), c.dp(4)) }, lp())
            val err = p.lastError
            if (expanded && 0 < p.updatedAt && err != null) addView(c.text(c.getString(R.string.vpn_sub_failed_x, err), 12f, MT.red).apply {
                setPadding(c.dp(12), c.dp(6), c.dp(12), c.dp(6)) }, lp())
        }
    }

    private fun manualHeader(): View = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(side, c.dp(12), side, 0)
        addView(sectionHeader(manualExpanded, c.getString(if (plans.isEmpty()) R.string.vpn_exit_nodes else R.string.vpn_added_by_hand),
            c.getString(R.string.vpn_servers_n, manual.size), false, onFold = { foldManual() }, onRefresh = null,
            onPing = { pingAll(manual) }, measuring = measuring(manual)) {
            vpnMenu(act, c.getString(R.string.vpn_servers), null, listOf(
                VpnMenuItem(c.getString(if (manualPinnedAt == null) R.string.vpn_pin else R.string.vpn_unpin), if (manualPinnedAt == null) R.drawable.ic_pin else R.drawable.ic_pin_slash) { toggleManualPin() },
                VpnMenuItem(c.getString(R.string.vpn_sort_ping), R.drawable.ic_vpn_sort) { sortByPing() }))
        }, lp())
    }

    // ── a server's row (iOS MontanaVPNServerRow 1136-1193, inside the library's line and its hairline) ──

    private fun serverCell(cfg: VpnConfig): View {
        val ic = vpnServerIcon(cfg.name)
        val chosen = cfg.id == VpnTunnel.selectedId
        val unsupported = cfg.proto == VpnProto.UNSUPPORTED
        val ping = VpnDelayBook.entry(cfg.id)
        val flying = cfg.id in VpnPingLine.inFlight
        val line = c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(side, 0, side, 0)
            addView(FrameLayout(c).apply {
                background = c.rounded(Color.argb(26, 255, 255, 255), 10)
                if (ic.first != null) addView(c.text(ic.first!!, 26f, Color.WHITE, center = true), FrameLayout.LayoutParams(MATCH, MATCH))   // USER-DATA: the server's own flag
                else addView(c.vpnGlyph(if (chosen) MT.blue else Color.argb(217, 255, 255, 255), 22), FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.CENTER))
            }, lp(c.dp(48), c.dp(48)))
            gap(16)
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(ic.second, 17f, if (unsupported) MT.gray else Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())   // USER-DATA: the server's name
                gap(4)
                // USER-DATA: the protocol, the transport and the wrapper as the link names them; JSON marks a row a plan served whole
                val words = if (unsupported) (cfg.scheme ?: "?").uppercase(Locale.ROOT) + " · " + c.getString(R.string.vpn_not_supported)
                    else listOfNotNull(cfg.proto.raw.uppercase(Locale.ROOT), cfg.network, cfg.security.takeIf { it != "none" }, if (cfg.engineOutbound == null) null else "JSON").joinToString(" · ")
                addView(c.text(words, 16f, MT.gray).apply { singleLineEllipsis() }, lp())
            }, lp(0, WRAP, 1f))
            // the spacer between the words and what stands after them: the row's spacing on both its sides and its least eight
            val trail = ArrayList<View>()
            if (chosen) trail.add(c.icon(R.drawable.ic_check, MT.blue, 16))
            if (ping != null) {
                val ms = ping.ms
                trail.add(View(c).apply { background = CircleFill(if (ms != null) vpnPingColor(ms) else MT.red); layoutParams = LinearLayout.LayoutParams(c.dp(7), c.dp(7)) })
                if (ms != null) trail.add(c.text("$ms " + c.getString(R.string.vpn_ms), 15f, MT.secondary).apply {   // USER-DATA: a number of milliseconds
                    alpha = if (ping.age < VpnDelayBook.STALE) 1f else 0.45f   // the last number stands always, dimmed past half an hour
                })
            }
            if (flying) trail.add(ProgressBar(c).apply { indeterminateTintList = ColorStateList.valueOf(MT.secondary); layoutParams = LinearLayout.LayoutParams(c.dp(16), c.dp(16)) })
            gap(if (trail.isEmpty()) 24 else 40)
            trail.forEachIndexed { i, v -> if (0 < i) gap(16); addView(v, v.layoutParams ?: lp(WRAP, WRAP)) }
            setOnClickListener { selectServer(cfg) }
            setOnLongClickListener { hold(cfg); true }
        }
        val row = SwipeRow(act, line, listOf(
            Tile(R.drawable.ic_pin) { vpnMark("vpn_ui", "swipe pin row=${cfg.id.take(8)}"); pinServer(cfg) },
            Tile(R.drawable.ic_delete) { vpnMark("vpn_ui", "swipe delete row=${cfg.id.take(8)}"); deleteServer(cfg) }))
        return c.vstack(Gravity.NO_GRAVITY) {
            addView(row, lp(MATCH, c.dp(72)))
            addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = side + c.dp(48 + 16) })
        }
    }

    /** A hold (iOS hold 370-381): rename, copy the link, copy the JSON, pin, delete -- in the overlay, as the chat's message menu. */
    private fun hold(cfg: VpnConfig) {
        val ic = vpnServerIcon(cfg.name)
        vpnMenu(act, ic.second, ic.first, listOf(
            VpnMenuItem(c.getString(R.string.vpn_rename), R.drawable.ic_pencil) { rename(cfg) },
            VpnMenuItem(c.getString(R.string.vpn_copy_link), R.drawable.ic_content_copy) { copy(VpnParse.serialize(cfg)); say(c.getString(R.string.vpn_link_copied)) },
            VpnMenuItem(c.getString(R.string.vpn_copy_json), R.drawable.ic_vpn_braces) { copyJSON(cfg) },
            VpnMenuItem(c.getString(R.string.vpn_pin), R.drawable.ic_pin) { pinServer(cfg) },
            VpnMenuItem(c.getString(R.string.vpn_delete), R.drawable.ic_delete, red = true) { deleteServer(cfg) }))
    }

    // ── the plus (iOS plus 321-339): the system's own menu on the page's corner ──

    private fun plusMenu(anchor: View) {
        val sel = selected()
        val items = mutableListOf(
            VpnMenuItem(c.getString(R.string.vpn_sub_url), R.drawable.ic_vpn_link_plus) { askSubscription() },
            VpnMenuItem(c.getString(R.string.vpn_paste), R.drawable.ic_vpn_clipboard) { paste() },
            VpnMenuItem(c.getString(R.string.vpn_scan), R.drawable.ic_qr_scan) { scan() },
            VpnMenuItem(c.getString(R.string.vpn_import), R.drawable.ic_vpn_doc_plus) { importFiles() },
            VpnMenuItem(c.getString(R.string.vpn_manual), R.drawable.ic_compose) { act.push { close -> vpnManualEntryPage(act, close) { cfg -> addServers(listOf(cfg), "form", "form") } } },
            VpnMenuItem(c.getString(R.string.vpn_copy_json), R.drawable.ic_vpn_braces, enabled = sel != null && sel.proto != VpnProto.UNSUPPORTED) { copyJSON(sel) })
        if (plans.isNotEmpty()) items.add(VpnMenuItem(c.getString(R.string.vpn_update_subs), R.drawable.ic_refresh) { refreshSubscriptions() })
        vpnPlatter(act, anchor, items)
    }

    // ── the acts (iOS 604-849) ──

    private fun foldPlan(p: VpnPlan) {
        val expanded = p.folded != true
        vpnMark("vpn_ui", "fold plan=${vpnPlanLabel(p.url)} to=${if (expanded) "folded" else "open"} rows=${byPlan[p.url].orEmpty().size}")
        p.folded = if (expanded) true else null
        draw()
        Thread { VpnPlans.setFolded(p.url, expanded) }.start()   // the fold outlives the page (24.09)
    }
    private fun foldManual() {
        vpnMark("vpn_ui", "fold manual to=${if (manualExpanded) "folded" else "open"}")
        manualExpanded = !manualExpanded
        VpnPlans.setManualFolded(!manualExpanded)
        draw()
    }
    private fun togglePin(p: VpnPlan) {
        val pin = p.pinnedAt == null
        vpnMark("vpn_ui", "plan ${if (pin) "pin" else "unpin"} rows=${byPlan[p.url].orEmpty().size}")
        VpnPlans.setPinned(p.url, pin)
        reload()
    }
    private fun toggleManualPin() {
        val pin = manualPinnedAt == null
        vpnMark("vpn_ui", "plan ${if (pin) "pin" else "unpin"} manual rows=${manual.size}")
        VpnPlans.setManualPinned(pin)
        reload()
    }
    private fun attempt(k: Int): String = c.getString(R.string.vpn_loading_try, k, VpnSubscription.ATTEMPTS)
    private fun refreshPlan(p: VpnPlan) {
        if (loadingPlan != null) return
        val t0 = SystemClock.elapsedRealtime()
        loadingPlan = p.url
        vpnMark("vpn_ui", "update plan=${vpnPlanLabel(p.url)} was=${byPlan[p.url].orEmpty().size}")
        draw()
        Thread {
            var word: String? = null
            try { VpnStore.addFromSubscription(p.url) { k -> act.onMain { say(attempt(k)) } } }
            catch (e: VpnSubscription.FetchError) { vpnMark("vpn_ui", "update plan=${vpnPlanLabel(p.url)} failed ${e.label}") }   // said once, under its header
            catch (e: Exception) { word = c.getString(R.string.vpn_sub_failed); vpnMark("vpn_ui", "update plan=${vpnPlanLabel(p.url)} failed other") }
            act.onMain {
                note = word; loadingPlan = null; reload()
                vpnMark("vpn_ui", "update plan=${vpnPlanLabel(p.url)} now=${byPlan[p.url].orEmpty().size} ms=${SystemClock.elapsedRealtime() - t0}")
            }
        }.start()
    }
    /** THE GAUGE ON A SECTION'S HEADER MEASURES THAT SECTION (iOS pingAll, 29.09): six at a time by the one line. */
    private fun pingAll(list: List<VpnConfig>) { vpnMark("vpn_ui", "ping section rows=${list.size}"); VpnPingLine.ask(list); draw() }
    /** Pinned means first IN ITS OWN SECTION (iOS pinServer): nothing crosses a section's border. */
    private fun pinServer(server: VpnConfig) {
        val key = server.subscription
        VpnStore.reorder { all ->
            val group = all.filter { it.subscription == key }.toMutableList()
            val i = group.indexOfFirst { it.id == server.id }
            if (i <= 0) return@reorder
            group.add(0, group.removeAt(i))
            val headAt = all.indexOfFirst { it.subscription == key }.takeIf { 0 <= it } ?: all.size
            val rest = all.filter { it.subscription != key }.toMutableList()
            rest.addAll(minOf(headAt, rest.size), group)
            all.clear(); all.addAll(rest)
        }
        vpnMark("vpn_ui", "pin row=${server.id.take(8)} section=${if (key == null) "manual" else "plan"}")
        reload(log = false)
    }
    private fun sortByPing() {
        VpnStore.reorder { all -> all.sortBy { VpnDelayBook.entry(it.id)?.ms ?: Int.MAX_VALUE } }
        reload(log = false)
    }

    /** EVERY ROAD IN IS ONE ROAD (iOS addVPNText, 29.09): a plan's link is fetched, anything else is read in place by its shape. */
    private fun addText(raw: String, road: String, name: String = "") {
        when (val read = VpnIntake.read(raw, name)) {
            is VpnIntake.Read.Subscription -> {
                vpnMark("vpn_ui", "add from=$road kind=subscription chars=${raw.length}")
                if (loadingPlan != null) { vpnMark("vpn_ui", "add busy -- a load is already running"); return }
                loadingPlan = read.url
                say(c.getString(R.string.vpn_loading))
                Thread {
                    var word: String? = null
                    try { VpnStore.addFromSubscription(read.url) { k -> act.onMain { say(attempt(k)) } } }
                    catch (e: VpnSubscription.FetchError) { vpnMark("vpn_ui", "add failed ${e.label}") }   // the plan's header names it, once
                    catch (e: Exception) { word = c.getString(R.string.vpn_sub_failed); vpnMark("vpn_ui", "add failed other") }
                    act.onMain { note = word; loadingPlan = null; reload() }
                }.start()
            }
            is VpnIntake.Read.Servers -> {
                val unspoken = VpnParse.Report(read.body.servers).unsupportedWord
                vpnMark("vpn_ui", "add from=$road form=${read.body.form} servers=${read.body.servers.size} unsupported=${unspoken.ifEmpty { "-" }} dropped=${read.body.dropped} chars=${raw.length}")
                addServers(read.body.servers, road, read.body.form)
            }
        }
    }
    /** The rows that came by hand join the list; the page's line says once what did not (iOS addVPNServers). */
    private fun addServers(list: List<VpnConfig>, road: String, form: String) {
        if (list.isEmpty()) { say(c.getString(if (form == "links" || form == "base64") R.string.vpn_invalid_link else R.string.vpn_no_server)); return }
        val joined = VpnStore.add(list)
        vpnMark("vpn_ui", "add from=$road joined=$joined of=${list.size}")
        note = if (joined == 0) c.getString(R.string.vpn_already) else null
        reload()
    }
    private fun askSubscription() {
        val field = EditText(c).apply {
            hint = c.getString(R.string.vpn_sub_link)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            isSingleLine = true
        }
        val box = FrameLayout(c).apply { setPadding(c.dp(20), 0, c.dp(20), 0); addView(field, FrameLayout.LayoutParams(MATCH, WRAP)) }
        AlertDialog.Builder(c).setTitle(R.string.vpn_sub_url).setView(box)
            .setPositiveButton(R.string.vpn_add_sub) { _, _ -> addText(field.text.toString(), "typed") }
            .setNegativeButton(R.string.cancel, null).show()
    }
    private fun paste() {
        val s = c.getSystemService(ClipboardManager::class.java)?.primaryClip?.takeIf { 0 < it.itemCount }?.getItemAt(0)?.coerceToText(c)?.toString().orEmpty()
        if (s.isEmpty()) { say(c.getString(R.string.vpn_no_server)); return }
        addText(s, "paste")
    }
    private fun scan() {
        act.push { close -> scannerPage(act, close) { code -> act.onMain { addText(code, "scan") }; true } }
    }
    /** THE FILE ROAD (iOS importVPNFiles): any file, its shape decides; a file over a megabyte is no profile; its name names the server
     *  when its form carries none. */
    private fun importFiles() {
        act.openDocuments { uris ->
            if (uris.isEmpty()) { vpnMark("vpn_ui", "add from=file picker refused"); return@openDocuments }
            Thread {
                val texts = ArrayList<Pair<String, String>>()
                var unreadable = 0
                for (u in uris) {
                    val text = runCatching { readSmall(u) }.getOrNull()
                    if (text != null) texts.add(nameOf(u) to text) else unreadable++
                }
                act.onMain {
                    for ((name, text) in texts) addText(text, "file", name)
                    if (0 < unreadable) { say(c.getString(R.string.vpn_file_unread)); vpnMark("vpn_ui", "add from=file unreadable=$unreadable of=${uris.size}") }
                }
            }.start()
        }
    }
    private fun readSmall(u: Uri): String? {
        val bytes = c.contentResolver.openInputStream(u)?.use { s ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(16384)
            while (true) { val n = s.read(buf); if (n < 0) break; out.write(buf, 0, n); if (VpnIntake.FILE_MAX < out.size()) return null }
            out.toByteArray()
        } ?: return null
        return VpnText.utf8(bytes)
    }
    private fun nameOf(u: Uri): String {
        val shown = runCatching {
            c.contentResolver.query(u, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cur -> if (cur.moveToFirst()) cur.getString(0) else null }
        }.getOrNull() ?: u.lastPathSegment.orEmpty()
        return shown.substringBeforeLast('.', shown)   // the file's own name, without its extension
    }
    private fun copy(s: String) { c.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Montana", s)) }
    /** COPY JSON (iOS copyJSON): the row's whole engine config, in the form this page reads back. */
    private fun copyJSON(server: VpnConfig?) {
        val text = server?.let { XrayConfig.shareJSON(it) }
        if (server == null || text == null) { say(c.getString(R.string.vpn_not_supported)); return }
        copy(text)
        say(c.getString(R.string.vpn_json_copied))
        vpnMark("vpn_ui", "copy json row=${server.id.take(8)} chars=${text.length}")
    }
    private fun refreshSubscriptions() {
        if (loadingPlan != null) return
        loadingPlan = "*"
        say(c.getString(R.string.vpn_loading))
        Thread {
            VpnStore.refreshSubscriptions { k -> act.onMain { say(attempt(k)) } }
            act.onMain { note = null; loadingPlan = null; reload() }   // each plan says its own failure under its own header
        }.start()
    }
    private fun toggle() {
        val cfg = selected()
        if (servers.isEmpty()) return   // the button stands disabled while the list holds no server (iOS .disabled)
        if (cfg == null) { say(c.getString(R.string.vpn_invalid_link)); vpnMark("vpn_ui", "power no server selected"); return }
        VpnSelection.noteHand()   // the person's hand on the VPN: nothing automatic raises another row within ten minutes
        if (VpnTunnel.isOn) { vpnMark("vpn_ui", "power stop row=${cfg.id.take(8)}"); VpnTunnel.stop(); return }
        val t0 = SystemClock.elapsedRealtime()
        busy = true; note = null
        vpnMark("vpn_ui", "power start row=${cfg.id.take(8)} net=${cfg.network} sec=${cfg.security}")
        drawHead()
        VpnTunnel.start(act, cfg, byHand = true) { refused ->
            if (refused != null) { note = refused; vpnMark("vpn_ui", "power refused ms=${SystemClock.elapsedRealtime() - t0}") }
            else vpnMark("vpn_ui", "power asked ms=${SystemClock.elapsedRealtime() - t0}")
            busy = false
            drawHead()
        }
    }
    private fun selectServer(server: VpnConfig) {
        if (server.proto == VpnProto.UNSUPPORTED) {   // the grey row says what it is; a tap explains it, nothing is installed (29.09)
            say(c.getString(R.string.vpn_not_supported))
            vpnMark("vpn_ui", "select refused row=${server.id.take(8)} scheme=${server.scheme ?: "?"}")
            return
        }
        VpnSelection.select(act, server, "hand")
        draw()
    }
    /** A row leaves the list; one of a plan stays gone until that plan is asked again (iOS deleteServer). */
    private fun deleteServer(server: VpnConfig) {
        val i = servers.indexOfFirst { it.id == server.id }.takeIf { 0 <= it } ?: return
        vpnMark("vpn_ui", "delete row=${server.id.take(8)} section=${if (server.subscription == null) "manual" else "plan"}")
        VpnStore.remove(i)
        reload()
    }
    /** RENAME (iOS doRename): a server added by hand takes the name typed; a plan's server keeps the plan's word, as on the iPhone. */
    private fun rename(server: VpnConfig) {
        val field = EditText(c).apply { setText(server.name); setSelection(text.length); hint = c.getString(R.string.vpn_name); isSingleLine = true }   // USER-DATA: the server's name
        val box = FrameLayout(c).apply { setPadding(c.dp(20), 0, c.dp(20), 0); addView(field, FrameLayout.LayoutParams(MATCH, WRAP)) }
        AlertDialog.Builder(c).setTitle(R.string.vpn_rename).setView(box)
            .setPositiveButton(R.string.vpn_save) { _, _ ->
                val name = field.text.toString()
                val i = servers.indexOfFirst { it.id == server.id }
                if (server.subscription == null && 0 <= i && name.trim().isNotEmpty()) { VpnStore.rename(i, name); reload() }
            }
            .setNegativeButton(R.string.cancel, null).show()
    }
}

/** One deed of the VPN wall's menus: its words, its glyph, red when it destroys, dim when it cannot be done now. */
class VpnMenuItem(val title: String, val glyph: Int, val red: Boolean = false, val enabled: Boolean = true, val work: () -> Unit)

/** THE VPN WALL'S MENU (iOS presentMontanaVPNMenu and MontanaVPNMenuOverlay 1218-1279): the overlay window, the material and the spring
 *  of the chat's message menu -- the title on its own plate (the flag or the VPN's green glyph), the deeds 260 wide under it; a deed
 *  runs once the overlay has gone. */
fun vpnMenu(act: MainActivity, title: String, emoji: String?, items: List<VpnMenuItem>) {
    val c: Context = act
    lateinit var leave: (() -> Unit) -> Unit
    val head = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
        background = c.rounded(GLASS_TONE, 14, Color.argb(31, 255, 255, 255))
        if (emoji != null) addView(c.text(emoji, 24f), lp(WRAP, WRAP)) else addView(c.vpnGlyph(MT.green, 22))   // USER-DATA: the server's flag
        gap(10)
        addView(c.text(title, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a value, never a key
    }
    val plate = c.vstack(Gravity.NO_GRAVITY) { background = c.rounded(GLASS_TONE, 16, Color.argb(26, 255, 255, 255)) }
    items.forEachIndexed { i, it ->
        if (0 < i) plate.addView(View(c).apply { setBackgroundColor(Color.argb(77, 142, 142, 147)) }, lp(MATCH, 1))
        plate.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(c.dp(14), 0, c.dp(14), 0)
            minimumHeight = c.dp(44)
            addView(c.text(it.title, 16f, if (it.red) MT.red else Color.WHITE), lp(0, WRAP, 1f))
            addView(c.icon(it.glyph, if (it.red) MT.red else Color.argb(204, 255, 255, 255), 20), lp(c.dp(20), c.dp(20)))
            pressable { leave { MainThread.later(50, Runnable { it.work() }) } }
        }, lp(MATCH, WRAP))
    }
    val cloud = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(c.dp(16), 0, c.dp(16), 0)
        addView(head, lp(WRAP, WRAP))
        gap(12)
        addView(plate, lp(c.dp(260), WRAP))
    }
    leave = showCloud(act, cloud, null)
}

/** THE SYSTEM'S OWN MENU AT THE PLUS (iOS Menu on the page's octagon, the platform's platter): it rises from the button, the first deed
 *  nearest to it (the platform's automatic order), the words to the left and the glyph to the right; a tap off it lets it go. */
fun vpnPlatter(act: MainActivity, anchor: View, items: List<VpnMenuItem>) {
    val c: Context = act
    val width = c.dp(250)
    lateinit var pop: PopupWindow
    val plate = c.vstack(Gravity.NO_GRAVITY) { background = c.rounded(Color.rgb(44, 44, 46), 13, Color.argb(26, 255, 255, 255)) }
    items.reversed().forEachIndexed { i, it ->
        if (0 < i) plate.addView(View(c).apply { setBackgroundColor(Color.argb(77, 142, 142, 147)) }, lp(MATCH, 1))
        plate.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(c.dp(16), c.dp(11), c.dp(16), c.dp(11))
            minimumHeight = c.dp(44)
            alpha = if (it.enabled) 1f else 0.35f
            addView(c.text(it.title, 17f, Color.WHITE).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END }, lp(0, WRAP, 1f))
            gap(12)
            addView(c.icon(it.glyph, Color.WHITE, 20), lp(c.dp(20), c.dp(20)))
            if (it.enabled) pressable { pop.dismiss(); it.work() }
        }, lp(MATCH, WRAP))
    }
    pop = PopupWindow(plate, width, ViewGroup.LayoutParams.WRAP_CONTENT, true).apply {
        setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        isOutsideTouchable = true
        elevation = c.dp(12).toFloat()
    }
    plate.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
    val at = IntArray(2).also { anchor.getLocationInWindow(it) }
    pop.showAtLocation(anchor, Gravity.TOP or Gravity.START, at[0] + anchor.width - width, at[1] - plate.measuredHeight - c.dp(8))
    plate.pivotX = width.toFloat(); plate.pivotY = plate.measuredHeight.toFloat()
    plate.scaleX = 0.6f; plate.scaleY = 0.6f; plate.alpha = 0f
    plate.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(220).setInterpolator(android.view.animation.OvershootInterpolator(1.1f)).start()
}

/** The bytes as the platform counts them in the binary style (iOS .byteCount(style: .binary)): adaptive digits, the person's language. */
fun vpnBytes(n: Long, locale: Locale): String {
    val ru = locale.language == "ru"; val zh = locale.language == "zh"
    val units = if (ru) listOf("байт", "КБ", "МБ", "ГБ", "ТБ", "ПБ") else if (zh) listOf("字节", "KB", "MB", "GB", "TB", "PB") else listOf("bytes", "KB", "MB", "GB", "TB", "PB")
    if (n <= 0L) return if (ru || zh) "0 " + units[1] else "Zero KB"
    var v = n.toDouble(); var u = 0
    while (1024.0 <= v && u < units.size - 1) { v /= 1024.0; u++ }
    val digits = when (u) { 0, 1 -> 0; 2 -> 1; else -> 2 }
    val f = java.text.NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = digits; minimumFractionDigits = 0 }
    return f.format(v) + " " + units[u]
}

/**
 * THE FORM OF A SERVER BY HAND (iOS MontanaVPNManualEntry, MontanaNetworkView.swift:1281-1492): the platform's own form -- a section per
 * question, a picker for the protocol, the transport and the wrapper, a field for every word the engine honours of that protocol --
 * under the bar's cross and checkmark. The checkmark stands only while the record can be dialled (sealed).
 */
fun vpnManualEntryPage(act: MainActivity, onClose: () -> Unit, onSave: (VpnConfig) -> Unit): View {
    val c: Context = act
    val draft = VpnConfig.empty(VpnProto.VLESS)
    var portText = "443"
    var mtuText = ""
    val done = c.icon(R.drawable.ic_check, Color.WHITE).apply { setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10)); contentDescription = c.getString(R.string.vpn_save) }
    fun sealed() = VpnManual.sealed(draft, portText, mtuText)
    fun refreshDone() { val on = sealed() != null; done.isEnabled = on; done.alpha = if (on) 1f else 0.4f }
    done.pressable { sealed()?.let { onSave(it); onClose() } }
    val body = c.vstack(Gravity.NO_GRAVITY)
    lateinit var draw: () -> Unit
    /** A technical field (iOS field): no capitals, no correction, the keyboard for its kind. */
    fun field(label: Int, value: String, kind: Int = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS, set: (String) -> Unit): View =
        EditText(c).apply {
            setText(value)   // USER-DATA: what the person typed
            hint = c.getString(label)
            setHintTextColor(MT.gray); setTextColor(Color.WHITE); textSize = 16f
            background = null; isSingleLine = true; inputType = kind
            typeface = Typeface.DEFAULT   // the visible-password keys bring the monospace face; the iPhone's field keeps the system's
            setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun afterTextChanged(s: Editable?) { set(s?.toString().orEmpty()); refreshDone() }
            })
        }
    /** A word the record may not carry: an empty field is no word (nil). */
    fun opt(label: Int, get: () -> String?, set: (String?) -> Unit, kind: Int? = null): View =
        if (kind == null) field(label, get() ?: "") { set(it.ifEmpty { null }) } else field(label, get() ?: "", kind) { set(it.ifEmpty { null }) }
    /** The platform's picker in a form (iOS Picker): the label, the value chosen, the menu of the choices. */
    fun picker(label: Int, value: String, options: List<Pair<String, String>>, pick: (String) -> Unit): View = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
        addView(c.text(c.getString(label), 16f), lp(0, WRAP, 1f))
        val shown = c.text(options.firstOrNull { it.first == value }?.second ?: value, 16f, MT.secondary)   // USER-DATA: the engine's own names
        addView(shown, lp(WRAP, WRAP))
        gap(6)
        addView(c.icon(R.drawable.ic_arrow_left_right, MT.secondary, 14).apply { rotation = 90f }, lp(c.dp(14), c.dp(14)))
        pressable {
            PopupMenu(c, shown).apply {
                options.forEachIndexed { i, o -> menu.add(0, i, i, o.second) }
                setOnMenuItemClickListener { item -> pick(options[item.itemId].first); draw(); true }
                show()
            }
        }
    }
    val number = InputType.TYPE_CLASS_NUMBER
    draw = {
        body.removeAllViews()
        val p = draft.proto
        body.section(c.getString(R.string.vpn_f_server), null,
            picker(R.string.vpn_f_protocol, p.raw, VpnManual.protocols.map { it.raw to VpnManual.word(it) }) { raw -> draft.proto = VpnProto.of(raw); VpnManual.reset(draft) },
            field(R.string.vpn_name, draft.name, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES) { draft.name = it },
            field(R.string.vpn_f_address, draft.host, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI) { draft.host = it },
            field(R.string.vpn_f_port, portText, number) { portText = it })
        val cred = when (p) {
            VpnProto.VLESS -> listOf(field(R.string.vpn_f_uuid, draft.uuidOrPassword) { draft.uuidOrPassword = it }, field(R.string.vpn_f_flow, draft.flow) { draft.flow = it },
                opt(R.string.vpn_f_encryption, { draft.encryption }, { draft.encryption = it }))
            VpnProto.VMESS -> listOf(field(R.string.vpn_f_uuid, draft.uuidOrPassword) { draft.uuidOrPassword = it }, field(R.string.vpn_f_cipher, draft.method) { draft.method = it })
            VpnProto.TROJAN -> listOf(field(R.string.vpn_f_password, draft.uuidOrPassword) { draft.uuidOrPassword = it })
            VpnProto.SHADOWSOCKS -> listOf(field(R.string.vpn_f_password, draft.uuidOrPassword) { draft.uuidOrPassword = it }, field(R.string.vpn_f_cipher, draft.method) { draft.method = it })
            VpnProto.HYSTERIA2 -> listOf(field(R.string.vpn_f_password, draft.uuidOrPassword) { draft.uuidOrPassword = it }, field(R.string.vpn_f_sni, draft.sni) { draft.sni = it },
                opt(R.string.vpn_f_obfs, { draft.obfsPassword }, { draft.obfsPassword = it }), opt(R.string.vpn_f_hop, { draft.mport }, { draft.mport = it }),
                opt(R.string.vpn_f_up, { draft.up }, { draft.up = it }, number), opt(R.string.vpn_f_down, { draft.down }, { draft.down = it }, number),
                opt(R.string.vpn_f_pin, { draft.pinSHA256 }, { draft.pinSHA256 = it }))
            VpnProto.WIREGUARD -> listOf(field(R.string.vpn_f_private, draft.uuidOrPassword) { draft.uuidOrPassword = it }, field(R.string.vpn_f_public, draft.publicKey) { draft.publicKey = it },
                opt(R.string.vpn_f_psk, { draft.presharedKey }, { draft.presharedKey = it }), opt(R.string.vpn_f_local, { draft.localIPs }, { draft.localIPs = it }),
                field(R.string.vpn_f_mtu, mtuText, number) { mtuText = it }, opt(R.string.vpn_f_reserved, { draft.reserved }, { draft.reserved = it }))
            VpnProto.SOCKS -> listOf(opt(R.string.vpn_f_user, { draft.user }, { draft.user = it }), field(R.string.vpn_f_password, draft.uuidOrPassword) { draft.uuidOrPassword = it })
            VpnProto.UNSUPPORTED -> emptyList()
        }
        body.section(c.getString(R.string.vpn_f_credentials), null, *cred.toTypedArray())
        if (VpnManual.hasStream(p)) {
            val net = ArrayList<View>()
            net.add(picker(R.string.vpn_f_transport, draft.network, VpnManual.transports.map { it to it }) { draft.network = it })
            when (draft.network) {
                "ws", "httpupgrade" -> { net.add(opt(R.string.vpn_f_path, { draft.path }, { draft.path = it })); net.add(opt(R.string.vpn_f_host, { draft.hostHeader }, { draft.hostHeader = it })) }
                "xhttp" -> {
                    net.add(opt(R.string.vpn_f_path, { draft.path }, { draft.path = it })); net.add(opt(R.string.vpn_f_host, { draft.hostHeader }, { draft.hostHeader = it }))
                    net.add(picker(R.string.vpn_f_mode, draft.mode ?: "auto", VpnManual.modes.map { it to it }) { draft.mode = it })
                }
                "grpc" -> net.add(opt(R.string.vpn_f_service, { draft.serviceName }, { draft.serviceName = it }))
                "kcp" -> net.add(opt(R.string.vpn_f_seed, { draft.seed }, { draft.seed = it }))
            }
            body.section(c.getString(R.string.vpn_f_transport), null, *net.toTypedArray())
            val sec = ArrayList<View>()
            sec.add(picker(R.string.vpn_f_security, draft.security, VpnManual.wrappers.map { it to it }) { draft.security = it })
            if (draft.security != "none") { sec.add(field(R.string.vpn_f_sni, draft.sni) { draft.sni = it }); sec.add(field(R.string.vpn_f_fingerprint, draft.fingerprint) { draft.fingerprint = it }) }
            if (draft.security == "tls") sec.add(opt(R.string.vpn_f_alpn, { draft.alpn }, { draft.alpn = it }))
            if (draft.security == "reality") {
                sec.add(field(R.string.vpn_f_public, draft.publicKey) { draft.publicKey = it }); sec.add(field(R.string.vpn_f_short, draft.shortId) { draft.shortId = it })
                sec.add(opt(R.string.vpn_f_spider, { draft.spiderX }, { draft.spiderX = it }))
            }
            body.section(c.getString(R.string.vpn_f_security), null, *sec.toTypedArray())
        }
        refreshDone()
    }
    draw()
    return settingsPage(act, c.getString(R.string.vpn_new_server), onClose, cross = true, trailing = done) { addView(body, lp()) }
}

/** The form's own rules (iOS MontanaVPNManualEntry's statics): the protocols, the transports, the wrappers, and the record as it is kept. */
object VpnManual {
    val protocols = listOf(VpnProto.VLESS, VpnProto.VMESS, VpnProto.TROJAN, VpnProto.SHADOWSOCKS, VpnProto.HYSTERIA2, VpnProto.WIREGUARD, VpnProto.SOCKS)
    val transports = listOf("tcp", "ws", "grpc", "xhttp", "httpupgrade", "kcp")
    val wrappers = listOf("none", "tls", "reality")
    val modes = listOf("auto", "packet-up", "stream-up", "stream-one")
    /** The protocols that dial through the stream layer (a transport and a wrapper); the others carry their own. */
    fun hasStream(p: VpnProto) = p in setOf(VpnProto.VLESS, VpnProto.VMESS, VpnProto.TROJAN, VpnProto.SHADOWSOCKS)
    /** The protocol's own name, as the rows print it (NOT-UI). */
    fun word(p: VpnProto) = when (p) {
        VpnProto.VLESS -> "VLESS"; VpnProto.VMESS -> "VMess"; VpnProto.TROJAN -> "Trojan"; VpnProto.SHADOWSOCKS -> "Shadowsocks"
        VpnProto.HYSTERIA2 -> "Hysteria 2"; VpnProto.WIREGUARD -> "WireGuard"; VpnProto.SOCKS -> "SOCKS"; VpnProto.UNSUPPORTED -> p.raw
    }
    /** The protocol chosen: the transport and the wrapper it dials with, as the link parser sets them (iOS reset). */
    fun reset(c: VpnConfig) {
        when (c.proto) {
            VpnProto.HYSTERIA2 -> { c.network = "hysteria"; c.security = "tls" }
            VpnProto.WIREGUARD -> { c.network = "udp"; c.security = "none" }
            VpnProto.SOCKS -> { c.network = "tcp"; c.security = "none" }
            else -> {
                if (c.network !in transports) c.network = "tcp"
                if (c.security !in wrappers) c.security = "none"
                if (c.proto == VpnProto.TROJAN && c.security == "none") c.security = "tls"
            }
        }
    }
    /** Pure (iOS sealed): the record as it is kept, or none while it cannot be dialled -- a machine, a port, the secret its protocol
     *  needs; empty words are no words, the name is the machine's when none was given, and a word of a section the protocol does not
     *  show is not kept. */
    fun sealed(draft: VpnConfig, port: String, mtu: String): VpnConfig? {
        val r = draft.copy()
        r.host = r.host.trim(); r.uuidOrPassword = r.uuidOrPassword.trim(); r.name = r.name.trim(); r.publicKey = r.publicKey.trim()
        r.shortId = r.shortId.trim(); r.sni = r.sni.trim(); r.fingerprint = r.fingerprint.trim(); r.flow = r.flow.trim(); r.method = r.method.trim()
        val p = port.trim().toIntOrNull()?.takeIf { it in 1..65535 }
        if (r.host.isEmpty() || p == null) return null
        r.port = p
        when (r.proto) {
            VpnProto.SOCKS -> {}
            VpnProto.WIREGUARD -> if (r.uuidOrPassword.isEmpty() || r.publicKey.isEmpty()) return null
            VpnProto.SHADOWSOCKS -> if (r.uuidOrPassword.isEmpty() || r.method.isEmpty()) return null
            VpnProto.UNSUPPORTED -> return null
            else -> if (r.uuidOrPassword.isEmpty()) return null
        }
        fun t(v: String?): String? = v?.trim()?.ifEmpty { null }
        r.path = t(r.path); r.hostHeader = t(r.hostHeader); r.mode = t(r.mode); r.extra = t(r.extra); r.serviceName = t(r.serviceName)
        r.spiderX = t(r.spiderX); r.encryption = t(r.encryption); r.pqv = t(r.pqv); r.alpn = t(r.alpn); r.pinSHA256 = t(r.pinSHA256)
        r.headerType = t(r.headerType); r.seed = t(r.seed); r.authority = t(r.authority); r.obfsPassword = t(r.obfsPassword); r.up = t(r.up)
        r.down = t(r.down); r.mport = t(r.mport); r.presharedKey = t(r.presharedKey); r.localIPs = t(r.localIPs); r.reserved = t(r.reserved); r.user = t(r.user)
        r.mtu = if (r.proto == VpnProto.WIREGUARD) mtu.trim().toIntOrNull() else null
        if (hasStream(r.proto)) {
            if (r.security == "reality" && r.publicKey.isEmpty()) return null
            if (r.security != "reality") { r.publicKey = ""; r.shortId = ""; r.spiderX = null }
            if (r.security == "none") { r.sni = ""; r.fingerprint = "" }
            if (r.security != "tls") r.alpn = null
            if (r.network !in setOf("ws", "httpupgrade", "xhttp")) { r.path = null; r.hostHeader = null }
            if (r.network != "xhttp") r.mode = null
            if (r.network != "grpc") r.serviceName = null
            if (r.network != "kcp") r.seed = null
        }
        if (r.name.isEmpty()) r.name = r.host
        return r
    }
}
