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
class EdgeSink(c: Context, private val top: () -> Int, private val bottom: () -> Int) : FrameLayout(c) {
    private val mask = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
    override fun dispatchDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (w <= 0f || h <= 0f) { super.dispatchDraw(canvas); return }
        val layer = canvas.saveLayer(0f, 0f, w, h, null)
        super.dispatchDraw(canvas)
        val s = stops(h, top().toFloat(), bottom().toFloat(), resources.displayMetrics.density)
        mask.shader = LinearGradient(0f, 0f, 0f, h, IntArray(s.size) { Color.argb((s[it].second * 255).roundToInt(), 0, 0, 0) },
            FloatArray(s.size) { s[it].first }, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, h, mask)
        canvas.restoreToCount(layer)
    }

    companion object {
        private const val ALPHA = 0.75f        // iOS MTEdgeWash.alpha
        private const val TOP_FADE = 80f       // iOS MTEdgeWash.topFade, points
        private const val BOTTOM_FADE = 60f    // iOS MTEdgeWash.bottomFade
        private const val BOTTOM_REACH = 20f   // iOS MTEdgeWash.bottomReach

        /** The rows' alpha over the height `h`, straight between the stops (iOS fadeStops with up and down), in pixels at `density`. */
        fun stops(h: Float, top: Float, bottom: Float, density: Float): List<Pair<Float, Float>> {
            val topFade = TOP_FADE * density; val bottomFade = BOTTOM_FADE * density
            val clear = top; val solid = clear - topFade
            fun above(y: Float) = 1f - ALPHA * minOf(1f, maxOf(0f, (clear - y) / topFade))
            val start = bottom - BOTTOM_REACH * density; val whole = start + bottomFade
            fun below(y: Float) = 1f - ALPHA * minOf(1f, maxOf(0f, (y - start) / bottomFade))
            fun loc(y: Float) = minOf(1f, maxOf(0f, y / h))
            val s = mutableListOf(0f to above(0f), loc(solid) to above(maxOf(0f, solid)), loc(clear) to 1f,
                loc(start) to 1f, loc(whole) to below(minOf(h, whole)), 1f to below(h))
            for (i in 1 until s.size) if (s[i].first < s[i - 1].first) s[i] = s[i - 1].first to s[i].second   // a page too short meets them in the middle
            return s
        }
    }
}
