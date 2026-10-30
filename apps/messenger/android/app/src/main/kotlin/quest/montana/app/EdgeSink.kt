package quest.montana.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.widget.FrameLayout
import kotlin.math.roundToInt

/**
 * THE PAGE'S EDGES SINK INTO ITS GROUND (iOS MTPageEdges, MontanaPeerHeader.swift:441-455 at 2155; atom 144387d85238): past the
 * bars at the page's top and bottom the rows fade into the page's ground by the chats page's own numbers (MTChatListFrame.fadeStops,
 * MontanaChatListContainer.swift:324-339; MTEdgeWash, ContentView.swift:1187-1194) -- one mask on the rows' own layer, the ground
 * not drawn twice. `top` and `bottom` are where the rows stand clear, in this view's own pixels.
 */
class EdgeSink(c: Context, private val top: () -> Int, private val bottom: () -> Int,
               private val edgeTop: () -> Int = top, private val edgeBottom: () -> Int = bottom) : FrameLayout(c) {
    private val mask = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
    /**
     * THE TWO EDGES' MODES (iOS MTChatListFrame.headFloats / pinned, MontanaChatListContainer.swift:86-90, 305-317 at 2155): `up`
     * off -- a row of the page stands over the rows' head with no plate of its own (the archive row), and the rows stop at
     * `edgeTop`, never showing through it; `down` off -- the search holds the list, and the rows stop at `edgeBottom`. A change
     * is one smooth move of the same six stops over 0.3 s (iOS fade(animated: true), CATransaction 0.3).
     */
    var up = true; set(v) { if (v != field) { field = v; move() } }
    var down = true; set(v) { if (v != field) { field = v; move() } }
    /** THE PAGE, NAMED IN THE DIARY (iOS MTChatListFrame.page, MontanaChatListContainer.swift:95-97 at 2155; atom 17a19adc6214):
     *  a page that names itself writes «list_edges page=… over=… under=… h=…» (points) whenever its run-on changes -- folded, a
     *  page the screen animates lays its edges out on every frame of the move. */
    var page = ""
    private var edges = Triple(-1, -1, -1)
    private var upK = 1f      // 1 -- the top's wash, 0 -- the hard stop, between -- on the way
    private var downK = 1f
    private var moving: android.animation.ValueAnimator? = null
    private fun move() {
        moving?.cancel()
        if (!isAttachedToWindow || width == 0) { upK = if (up) 1f else 0f; downK = if (down) 1f else 0f; invalidate(); return }
        val u0 = upK; val d0 = downK; val u1 = if (up) 1f else 0f; val d1 = if (down) 1f else 0f
        moving = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 300
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener { val t = it.animatedValue as Float; upK = u0 + (u1 - u0) * t; downK = d0 + (d1 - d0) * t; invalidate() }
            start()
        }
    }
    override fun dispatchDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (w <= 0f || h <= 0f) { super.dispatchDraw(canvas); return }
        val layer = canvas.saveLayer(0f, 0f, w, h, null)
        super.dispatchDraw(canvas)
        if (page.isNotEmpty()) {
            val d = resources.displayMetrics.density
            val e = Triple((top() / d).roundToInt(), ((h - bottom()) / d).roundToInt(), (h / d).roundToInt())
            if (e != edges) { edges = e; Diary.folded("list_edges", "page=" + page + " over=" + e.first + " under=" + e.second + " h=" + e.third) }
        }
        val s = stops(h, top().toFloat(), bottom().toFloat(), resources.displayMetrics.density, upK, downK,
            edgeTop().toFloat(), edgeBottom().toFloat())
        mask.shader = LinearGradient(0f, 0f, 0f, h, IntArray(s.size) { Color.argb((s[it].second * 255).roundToInt(), 0, 0, 0) },
            FloatArray(s.size) { s[it].first }, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, h, mask)
        canvas.restoreToCount(layer)
    }

    companion object {
        /** A page's own mask, found by the page that holds the search (the pinned bottom on the contacts and the calls). */
        const val TAG = "edge_sink"
        private const val ALPHA = 0.75f        // iOS MTEdgeWash.alpha
        private const val TOP_FADE = 80f       // iOS MTEdgeWash.topFade, points
        private const val BOTTOM_FADE = 60f    // iOS MTEdgeWash.bottomFade
        private const val BOTTOM_REACH = 20f   // iOS MTEdgeWash.bottomReach

        /**
         * The rows' alpha over the height `h`, straight between the stops (iOS fadeStops), in pixels at `density`. `up` and `down`
         * are 1 for the wash, 0 for the hard stop at `edgeTop` / `edgeBottom` (iOS up: false, down: false), and between them while
         * the mode changes: the six stops of one mode moved straight to the six of the other, as Core Animation moves them.
         */
        fun stops(h: Float, top: Float, bottom: Float, density: Float, up: Float = 1f, down: Float = 1f,
                  edgeTop: Float = top, edgeBottom: Float = bottom): List<Pair<Float, Float>> {
            val topFade = TOP_FADE * density; val bottomFade = BOTTOM_FADE * density
            val clear = top; val solid = clear - topFade
            fun above(y: Float) = 1f - ALPHA * minOf(1f, maxOf(0f, (clear - y) / topFade))
            val start = bottom - BOTTOM_REACH * density; val whole = start + bottomFade
            fun below(y: Float) = 1f - ALPHA * minOf(1f, maxOf(0f, (y - start) / bottomFade))
            fun loc(y: Float) = minOf(1f, maxOf(0f, y / h))
            fun mix(k: Float, on: Pair<Float, Float>, off: Pair<Float, Float>) =
                (off.first + (on.first - off.first) * k) to (off.second + (on.second - off.second) * k)
            val cut = loc(edgeTop); val end = loc(edgeBottom)
            val s = mutableListOf(mix(up, 0f to above(0f), 0f to 0f), mix(up, loc(solid) to above(maxOf(0f, solid)), cut to 0f),
                mix(up, loc(clear) to 1f, cut to 1f),
                mix(down, loc(start) to 1f, end to 1f), mix(down, loc(whole) to below(minOf(h, whole)), end to 0f), mix(down, 1f to below(h), 1f to 0f))
            for (i in 1 until s.size) if (s[i].first < s[i - 1].first) s[i] = s[i - 1].first to s[i].second   // a page too short meets them in the middle
            return s
        }
    }
}
