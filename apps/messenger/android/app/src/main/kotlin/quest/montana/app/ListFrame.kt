package quest.montana.app

import android.content.Context
import android.os.SystemClock
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.TextView

// ─────────────────────────── the lists' frame: the arrow to the top, the row's number (iOS MTChatListFrame) ───────────────────────────

/**
 * ONE OWNER FOR EVERY LIST OF THE PAGES (iOS MTChatListFrame, MontanaChatListContainer.swift:113-347 at 2155; atoms cc6b39be7456,
 * 7949c2f38f5f, ce4efce3d1c0). The author's word 30.09: «when any feed is scrolled down -- the walls, the VPN, the music, the
 * playlist -- the arrow up at the bottom right corner»; 24.09: «on the music list, at the right, the bar while it scrolls, and
 * beside the bar, in the native manner, the track's number in the list»; «let me press the number: it clings, it grows, and the
 * music's list scrolls by it».
 *
 * `host` is the page's own frame; the list is the first ScrollView in it. The arrow stands over the page's corner button
 * (`corner`, measured where it lies -- it steps above the player's room by itself), at the bottom right without one.
 * `rows` numbered: the platform's own scroll bar shows on the list and the row standing at its thumb is named beside it.
 */
class ListFrame private constructor(private val host: FrameLayout, private val list: ScrollView, private val page: String,
                                    private val corner: View?, private val rows: ViewGroup?) {
    private val c: Context = host.context
    private val arrow = ToTop(c) { toTheTop() }
    private val number = RowNumber(c)
    private var lastY = Int.MIN_VALUE
    private var held = false
    private var gripOffset = 0f
    private var fades = true

    companion object {
        fun attach(host: FrameLayout, page: String, corner: View? = null, rows: ViewGroup? = null): ListFrame? {
            val list = scrollIn(host) ?: return null
            return ListFrame(host, list, page, corner, rows)
        }
        private fun scrollIn(v: View): ScrollView? {
            if (v is ScrollView) return v
            if (v is ViewGroup) for (i in 0 until v.childCount) scrollIn(v.getChildAt(i))?.let { return it }
            return null
        }
    }

    init {
        host.addView(arrow, FrameLayout.LayoutParams(c.dp(ToTop.SIDE), c.dp(ToTop.SIDE), Gravity.TOP or Gravity.START))
        if (rows != null) {
            list.isVerticalScrollBarEnabled = true   // the platform's own bar, on the numbered list only (iOS showsVerticalScrollIndicator)
            host.addView(number, FrameLayout.LayoutParams(c.dp(RowNumber.HEIGHT), c.dp(RowNumber.HEIGHT), Gravity.TOP or Gravity.START))
            number.setOnTouchListener(Grip())
        }
        val onScroll = ViewTreeObserver.OnScrollChangedListener { if (list.scrollY != lastY) { lastY = list.scrollY; scrolled() } }
        list.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { v.viewTreeObserver.addOnScrollChangedListener(onScroll) }
            override fun onViewDetachedFromWindow(v: View) { v.viewTreeObserver.removeOnScrollChangedListener(onScroll) }
        })
        if (list.isAttachedToWindow) list.viewTreeObserver.addOnScrollChangedListener(onScroll)
        host.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> placeTop(); showTop() }
        corner?.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> placeTop() }
    }

    /** The list's top-left in the host's pixels: it may stand inside the page's coin pull or its edges' mask. */
    private fun listAt(): Pair<Int, Int> {
        val a = IntArray(2); val b = IntArray(2)
        list.getLocationInWindow(a); host.getLocationInWindow(b)
        return (a[0] - b[0]) to (a[1] - b[1])
    }

    /** THE ARROW'S PLACE, FROM ITS NEIGHBOUR (iOS placeTop): on the corner button's own vertical line, 16 over its top --
     *  the corner itself steps over the player's room; without one, 16 from the list's bottom right. */
    private fun placeTop() {
        val side = c.dp(ToTop.SIDE).toFloat(); val edge = c.dp(16).toFloat()
        val k = corner?.takeIf { it.visibility == View.VISIBLE && it.width > 0 }
        if (k != null) {
            arrow.x = k.x + k.width / 2f - side / 2
            arrow.y = k.y - edge - side
        } else {
            val (lx, ly) = listAt()
            arrow.x = lx + list.width - edge - side
            arrow.y = ly + list.height - list.paddingBottom - edge - side
        }
    }

    /** The arrow stands while the list's first screen is out of sight and leaves at its top (iOS showTop). */
    private fun showTop() {
        val screen = list.height - list.paddingTop - list.paddingBottom
        arrow.stand(0 < screen && screen < list.scrollY)
    }

    /** A tap on the arrow: the platform's own animated scroll to the list's top, said to the diary. */
    private fun toTheTop() {
        Diary.folded("list_top", "page=$page", key = page)
        list.smoothScrollTo(0, 0)
    }

    /** The bar's track as the platform draws it (View.getVerticalScrollBarBounds, inside the padding), in the host's pixels. */
    private class Rail(val n: Int, val top: Float, val track: Float, val max: Int)
    private fun rail(): Rail? {
        val rs = rows ?: return null
        val n = (0 until rs.childCount).count { rs.getChildAt(it).let { v -> v.visibility == View.VISIBLE && 1 < v.height } }
        val max = maxScroll()
        val track = (list.height - list.paddingTop - list.paddingBottom).toFloat()
        if (n == 0 || max <= 1 || track < c.dp(RowNumber.HEIGHT) * 2) return null
        return Rail(n, listAt().second + list.paddingTop.toFloat(), track, max)
    }
    private fun maxScroll(): Int {
        val child = list.getChildAt(0) ?: return 0
        return maxOf(0, child.height - (list.height - list.paddingTop - list.paddingBottom))
    }
    /** The list's place along the rail, as the finger reads it (iOS railY). */
    private fun railY(r: Rail): Float {
        val h = c.dp(RowNumber.HEIGHT).toFloat()
        val f = (list.scrollY.toFloat() / r.max).coerceIn(0f, 1f)
        return r.top + h / 2 + f * (r.track - h)
    }
    /** THE PLATFORM'S THUMB, BY THE PLATFORM'S OWN ARITHMETIC (iOS thumbMiddle; android ScrollBarUtils: the thumb's length is the
     *  track's share of extent over range, at least twice the bar's thickness, its offset the rest's share of the scroll). */
    private fun thumbMiddle(r: Rail): Float {
        val child = list.getChildAt(0) ?: return railY(r)
        val range = child.bottom.toFloat(); val extent = list.height.toFloat()
        if (range <= extent) return railY(r)
        val len = maxOf(Math.round(r.track * extent / range).toFloat(), list.verticalScrollbarWidth * 2f)
        val off = (Math.round((r.track - len) * list.scrollY / (range - extent)).toFloat()).coerceIn(0f, r.track - len)
        return r.top + off + len / 2
    }
    /** The row standing at the host's height `y`, from 1 (iOS ordinal), and its view. */
    private fun rowAt(y: Float): Pair<Int, View>? {
        val rs = rows ?: return null
        var top = 0; var v: View = rs
        while (v !== list) { top += v.top; v = v.parent as? View ?: return null }
        val at = y - listAt().second + list.scrollY - top
        var k = 0
        for (i in 0 until rs.childCount) {
            val row = rs.getChildAt(i)
            if (row.visibility != View.VISIBLE || row.height <= 1) continue
            k++
            if (at < row.bottom) return k to row
        }
        return null
    }

    /** A scroll of the list: the arrow stands or leaves; the number rides beside the bar's thumb and names the row there. */
    private fun scrolled() {
        showTop()
        if (rows == null) return
        val r = rail() ?: run { number.hide(); return }
        val h = c.dp(RowNumber.HEIGHT) / 2f
        val y = thumbMiddle(r).coerceIn(r.top + h, r.top + r.track - h)
        val item = rowAt(y)?.first ?: if (y - r.top < r.track / 2) 1 else r.n
        val (lx, _) = listAt()
        if (number.show(item.coerceIn(1, r.n), edge = lx + list.width - c.dp(RowNumber.GAP).toFloat(), centerY = y))
            Diary.folded("list_number", "page=$page rows=${r.n} by=${if (held) "number" else "scroll"}", key = page + held)
    }

    /**
     * THE NUMBER TAKEN BY THE FINGER (iOS gripped, the critic 24.09): a press held a moment on the standing number takes it -- the
     * platform's light tick, the plate grows and steps aside, the finger's height along the bar's track is the list's place and the
     * platform's bar stands beside it all the while; a tap there falls to its row, a drag before the hold is the list's own scroll.
     */
    private inner class Grip : View.OnTouchListener {
        private var downX = 0f; private var downY = 0f; private var downAt = 0L
        private var forward = false
        private val take = Runnable {
            val r = rail() ?: return@Runnable
            held = true
            list.smoothScrollBy(0, 0)   // a coasting list stops under the finger
            gripOffset = downY - railY(r)
            fades = list.isScrollbarFadingEnabled
            list.isScrollbarFadingEnabled = false   // the platform's bar stands beside the number while it is held
            number.take()
            Diary.folded("list_number", "held page=$page rows=${r.n}", key = page + "held")
        }
        override fun onTouch(v: View, e: MotionEvent): Boolean {
            val hx = e.rawX - hostX(); val hy = e.rawY - hostY()
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    if (!number.standing || !number.plateHas(hx, hy)) return false
                    downX = hx; downY = hy; downAt = SystemClock.uptimeMillis(); forward = false
                    number.postDelayed(take, 120)
                }
                MotionEvent.ACTION_MOVE -> when {
                    held -> drag(hy)
                    forward -> pass(e)
                    c.dp(12) < Math.hypot((hx - downX).toDouble(), (hy - downY).toDouble()) -> {
                        number.removeCallbacks(take); forward = true
                        pass(e, down = true); pass(e)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    number.removeCallbacks(take)
                    when {
                        held -> { held = false; list.isScrollbarFadingEnabled = fades; number.release() }
                        forward -> pass(e)
                        e.actionMasked == MotionEvent.ACTION_UP -> rowAt(hy)?.second?.performClick()   // the tap is the row's
                    }
                    forward = false
                }
            }
            return true
        }
        private fun drag(hy: Float) {
            val r = rail() ?: return
            val h = c.dp(RowNumber.HEIGHT) / 2f
            val y = (hy - gripOffset).coerceIn(r.top + h, r.top + r.track - h)
            val f = (y - r.top - h) / (r.track - 2 * h)
            list.scrollTo(0, Math.round(f * r.max))
        }
        /** The touch handed to the list as its own, from where it went down (the list's coordinates). */
        private fun pass(e: MotionEvent, down: Boolean = false) {
            val a = IntArray(2); list.getLocationOnScreen(a)
            val m = if (down) MotionEvent.obtain(downAt, e.eventTime, MotionEvent.ACTION_DOWN, downX + hostX() - a[0], downY + hostY() - a[1], 0)
                    else MotionEvent.obtain(e).apply { setLocation(e.rawX - a[0], e.rawY - a[1]) }
            list.dispatchTouchEvent(m)
            m.recycle()
        }
        private fun hostX(): Float { val a = IntArray(2); host.getLocationOnScreen(a); return a[0].toFloat() }
        private fun hostY(): Float { val a = IntArray(2); host.getLocationOnScreen(a); return a[1].toFloat() }
    }
}

/**
 * BACK TO THE TOP (iOS MTToTopButton): the round glass plate of the pages' buttons with the platform's arrow and no word, a
 * target of 44; it comes and leaves as the platform's controls do -- a short fade with a small scale -- and out of sight takes
 * no touch.
 */
private class ToTop(c: Context, onTap: () -> Unit) : FrameLayout(c) {
    companion object { const val SIDE = 44 }
    private var standing = false
    init {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(R.string.back_to_top)
        addView(c.icon(R.drawable.ic_arrow_up, android.graphics.Color.WHITE), LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
        alpha = 0f; scaleX = 0.6f; scaleY = 0.6f; visibility = INVISIBLE
        pressable(onTap)
    }
    fun stand(on: Boolean) {
        if (on == standing) return
        standing = on
        animate().cancel()
        if (on) visibility = VISIBLE
        animate().alpha(if (on) 1f else 0f).scaleX(if (on) 1f else 0.6f).scaleY(if (on) 1f else 0.6f).setDuration(200)
            .withEndAction { if (!standing) visibility = INVISIBLE }.start()
    }
}

/**
 * THE ROW'S NUMBER BESIDE THE BAR (iOS MTRowNumber): the platform draws no word beside its scroll bar, so the number is ours in
 * the pages' dress -- the glass capsule, white digits of one width; it comes with a scroll and leaves 1.5 s after the last one,
 * never while held. Taken, it grows 1.35 times and steps 60 aside from the finger.
 */
private class RowNumber(c: Context) : FrameLayout(c) {
    /** ROOM_X / ROOM_Y: the frame's room left of and around the plate -- the page clips its children to their frames, so the
     *  step aside and the growth must happen inside this one (439/440 lost the taken plate behind its own frame's edge). */
    companion object { const val HEIGHT = 28; const val GAP = 14; const val LIFT = 60; const val ROOM_X = LIFT + 16; const val ROOM_Y = 8 }
    private val label = TextView(c).apply {
        background = c.glassPlate()
        setTextColor(android.graphics.Color.WHITE)
        textSize = 15f
        typeface = android.graphics.Typeface.DEFAULT_BOLD
        fontFeatureSettings = "tnum"
        gravity = Gravity.CENTER
        isSingleLine = true
        setPadding(c.dp(10), 0, c.dp(10), 0)
    }
    private var shown = 0
    private var held = false
    private var on = false
    private val leave = Runnable { hide() }
    val standing get() = on && 0.01f < alpha
    init {
        clipChildren = false
        addView(label, LayoutParams(c.dp(HEIGHT), c.dp(HEIGHT), Gravity.END or Gravity.CENTER_VERTICAL))
        alpha = 0f; visibility = INVISIBLE
    }
    /** The plate's resting place holds the host's point: only there the finger takes it; the frame's room is the list's. */
    fun plateHas(hx: Float, hy: Float): Boolean {
        val w = label.width.toFloat(); val top = y + context.dp(ROOM_Y)
        return x + width - w <= hx && hx <= x + width && top <= hy && hy <= top + context.dp(HEIGHT)
    }
    /** The number `n`, its right edge at `edge`, its middle at `centerY` (the host's pixels); true when it was not standing.
     *  The frame stands still at its place; the plate inside carries the slide, the growth and the step aside. */
    fun show(n: Int, edge: Float, centerY: Float): Boolean {
        val h = context.dp(HEIGHT)
        if (n != shown) { shown = n; label.text = n.toString() }   // USER-DATA: the row's place in the list, digits
        // THE PLATE'S WIDTH FROM THE DIGITS THEMSELVES: a TextView measured unbounded reads its width from the layout it already
        // holds -- the one made in the plate's first 28 -- so 441 and 442 stood one digit wide
        val w = maxOf(Math.ceil(label.paint.measureText(label.text.toString()).toDouble()).toInt() + label.paddingLeft + label.paddingRight, h)
        if (label.layoutParams.width != w) { label.layoutParams = label.layoutParams.apply { width = w } }
        val fw = w + context.dp(ROOM_X); val fh = h + 2 * context.dp(ROOM_Y)
        if (layoutParams.width != fw || layoutParams.height != fh) { layoutParams = layoutParams.apply { width = fw; height = fh } }
        x = edge - fw; y = centerY - fh / 2f
        if (!held) linger()
        if (on) return false
        on = true
        visibility = VISIBLE
        if (!held) label.translationX = context.dp(GAP) + w / 2f
        animate().cancel()
        animate().alpha(1f).setDuration(200).start()
        label.animate().translationX(0f).setDuration(200).start()
        return true
    }
    /** Taken: the platform's light tick, the plate grows and steps aside from the finger, and stays while held. */
    fun take() {
        held = true
        removeCallbacks(leave)
        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        animate().cancel(); alpha = 1f
        label.animate().translationX(-context.dp(LIFT).toFloat()).scaleX(1.35f).scaleY(1.35f).setDuration(300)
            .setInterpolator(android.view.animation.OvershootInterpolator(1.2f)).start()
    }
    /** Let go: the plate returns to its place and leaves a moment after. */
    fun release() {
        if (!held) return
        held = false
        label.animate().translationX(0f).scaleX(1f).scaleY(1f).setDuration(250).setInterpolator(null).start()
        linger()
    }
    private fun linger() { removeCallbacks(leave); postDelayed(leave, 1500) }
    fun hide() {
        if (held || !on) return
        on = false
        removeCallbacks(leave)
        animate().alpha(0f).setDuration(300).withEndAction { if (!on) visibility = INVISIBLE }.start()
    }
}
