package quest.montana.app

import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.widget.ScrollView
import kotlin.math.roundToInt

/**
 * THE HONEST FRAME METER (iOS MTFrameMeter, MontanaMessageFeed.swift:268-437): the feed's feel told in numbers, not guessed --
 * how many frames a motion took, the worst gap between two of them, how many ran late against the screen's OWN rhythm and
 * how many it missed outright -- said once the motion ends, never while the screen stands still. One Choreographer callback
 * that lives only from a motion's first frame to its last, and costs nothing when none runs (iOS: "a meter that costs frames
 * of its own measures itself").
 *
 * THE PAGE'S TRANSITION IS THE SAME METER (iOS MTPageMeter + montanaMotionMeter, MontanaPeerHeader.swift:507-534; moveBegan /
 * moveEnded, MontanaMessageFeed.swift:349-355): a page's push or back begins and ends it the same way a list's drag does,
 * one line per transition, under the mark «motion» rather than «feed_fps».
 */
object Motion {
    private var callback: Choreographer.FrameCallback? = null
    private var last = 0L
    private var began = 0L
    private var frames = 0
    private var worstMs = 0
    private var late = 0
    private var missed = 0
    private var intervalNs = 16_666_667L

    /** iOS begin(rows:on:) (MontanaMessageFeed.swift:364-380): idempotent while a motion already runs. */
    fun begin(view: View? = null) {
        if (callback != null) return
        view?.display?.refreshRate?.takeIf { it > 0 }?.let { intervalNs = (1_000_000_000.0 / it).toLong() }
        frames = 0; worstMs = 0; late = 0; missed = 0
        began = System.nanoTime(); last = began
        schedule()
    }
    private fun schedule() {
        val cb = Choreographer.FrameCallback { tick(it) }
        callback = cb
        Choreographer.getInstance().postFrameCallback(cb)
    }
    private fun tick(frameTimeNanos: Long) {
        if (callback == null) return
        val dt = frameTimeNanos - last
        last = frameTimeNanos
        frames++
        val ms = (dt / 1_000_000L).toInt()
        if (ms > worstMs) worstMs = ms
        // «Late» against the display's OWN rhythm, not a fixed sixty (iOS MontanaMessageFeed.swift:421-425: a 120Hz screen's
        // 16ms frame is already a stutter, and a fixed number would call it healthy).
        if (intervalNs > 0) missed += maxOf(0, (dt.toDouble() / intervalNs).roundToInt() - 1)
        if (dt > intervalNs * 2) late++
        schedule()
    }
    /** iOS end(_:mark:) (MontanaMessageFeed.swift:383-392): one line, then silence; a flick too short to judge says nothing. */
    fun end(what: String, mark: String = "feed_fps") {
        val cb = callback ?: return
        Choreographer.getInstance().removeFrameCallback(cb)
        callback = null
        if (frames <= 5) return
        val secs = ((System.nanoTime() - began) / 1_000_000_000.0).coerceAtLeast(0.001)
        val fps = (frames / secs).toInt()
        Log.d("Montana", mark + " what=" + what + " frames=" + frames + " fps=" + fps + " worst_ms=" + worstMs + " late=" + late + " missed=" + missed)
    }

    /** iOS moveBegan/moveEnded (MontanaMessageFeed.swift:354-355): a page's own rise and fall, named «motion». */
    fun moveBegan(view: View? = null) = begin(view)
    fun moveEnded(what: String) = end(what, "motion")

    /**
     * iOS scrollViewWillBeginDragging / didEndDragging / didEndDecelerating (MontanaMessageFeed.swift:1125-1149): this app's
     * lists are plain ScrollViews with no such delegate, so the touch tells the drag's start and the scroll's own idle tells
     * when a fling that outlived the finger has settled -- the same two names, «drag» alone or «fling» once it decelerated.
     */
    fun watch(view: ScrollView, already: ((View, Int, Int, Int, Int) -> Unit)? = null) {
        var released = true
        var flung = false
        val idle = Runnable { end(if (flung) "fling" else "drag") }
        view.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> { released = false; flung = false }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    released = true
                    v.removeCallbacks(idle); v.postDelayed(idle, SETTLE_MS)
                }
            }
            false   // the view's own scroll handling runs untouched
        }
        view.setOnScrollChangeListener { v, x, y, oldX, oldY ->
            if (y != oldY) {
                begin(v)
                if (released) flung = true
                v.removeCallbacks(idle); v.postDelayed(idle, SETTLE_MS)
            }
            already?.invoke(v, x, y, oldX, oldY)
        }
    }
    private const val SETTLE_MS = 100L
}
