package quest.montana.app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Insets
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.WindowInsetsAnimationControlListener
import android.view.WindowInsetsAnimationController
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * THE KEYS AND THE PAGE ARE ONE MOVE (iOS MTChatKeyboardGeometry and MTKeyboardRider, ContentView.swift:965-1240 at 2155; the feed's
 * keyboardDismissMode .interactive, MontanaMessageFeed.swift:62-71; atoms 8d1fa24a1d58, 35b616136ed5, bd1a5eaf86ac, ebafa0a3c3f0,
 * 12a1f8f60d21, e8c2eef20abb). One number, the keys' COVER — how far the keyboard stands above the page's safe bottom — is told to
 * the page frame by frame, in the keyboard's own animation: the bar rides the keys by its layer and the feed keeps its height, its
 * covered part an inset (iOS MTFeedFrame). The page's padding never carries the keyboard, so nothing is laid out at once for the end.
 *
 * A FINGER DRAGGING THE FEED DOWN PAST THE BAR'S TOP TAKES THE KEYS WITH IT (the author's word 20.09 «the keyboard follows the
 * finger»; iOS: the bar's height is the keys' accessory, so the drag begins at the bar's top): the platform hands the keyboard to the
 * app (WindowInsetsAnimationController), the keys and the bar go down as one under the finger and come back up with it; a release
 * moving up, or with the keys still whole, gives them back, any other release lets them go — in half the keyboard's time (iOS «a
 * release after a drag settles twice as fast»). The drag says itself in the diary (iOS kb_drag, one line per 8 points of finger).
 */
class KeyRide(private val page: View, private val place: (Int) -> Unit, private val letGo: () -> Unit, private val drawn: () -> String = { "" }) {
    /** The cover now applied, in pixels. */
    var cover = 0
        private set
    /** A finger holds the keys: the page leaves the feed's offset to it (iOS keyboardGestureActive). */
    val dragging: Boolean get() = grabbed
    private var running = false   // the platform's own move of the keys is in flight: its frames place the page
    private var grabbed = false
    private var asked = false
    private var ctl: WindowInsetsAnimationController? = null
    private var cut: CancellationSignal? = null
    private var grabY = 0f
    private var grabIme = -1
    private var lastY = 0f
    private var saidY = -1f
    private var speed: VelocityTracker? = null
    private var settle: ValueAnimator? = null

    private fun coverOf(insets: WindowInsets): Int {
        val keys = insets.getInsets(WindowInsets.Type.ime()).bottom
        val bars = insets.getInsets(WindowInsets.Type.systemBars()).bottom
        return (keys - bars).coerceAtLeast(0)
    }

    private fun apply(k: Int) {
        if (k == cover) return
        cover = k
        place(k)
    }

    /** The page's insets: the end of the keys' move. While the platform or a finger moves them, their frames place the page. */
    fun insets(insets: WindowInsets) { if (!running && !grabbed) apply(coverOf(insets)) }

    init {
        if (30 <= Build.VERSION.SDK_INT) page.setWindowInsetsAnimationCallback(object : WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
            private fun keys(a: WindowInsetsAnimation) = (a.typeMask and WindowInsets.Type.ime()) != 0
            override fun onPrepare(a: WindowInsetsAnimation) { if (keys(a)) running = true }
            override fun onProgress(insets: WindowInsets, all: MutableList<WindowInsetsAnimation>): WindowInsets {
                if (running && all.any { keys(it) }) apply(coverOf(insets))
                return insets
            }
            override fun onEnd(a: WindowInsetsAnimation) {
                if (!keys(a)) return
                running = false
                if (!grabbed) page.rootWindowInsets?.let { apply(coverOf(it)) }
            }
        })
    }

    /**
     * The feed's touches, before the feed takes them. `edge` is the bar's top on the screen. Answers true while the finger holds the
     * keys. A finger that crosses the edge on its way down with the keys up takes them.
     */
    fun touch(e: MotionEvent, down: Boolean, edge: Int): Boolean {
        if (Build.VERSION.SDK_INT < 30) return false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { speed?.recycle(); speed = VelocityTracker.obtain().also { it.addMovement(e) } }
            MotionEvent.ACTION_MOVE -> {
                speed?.addMovement(e)
                val y = e.rawY
                if (grabbed) follow(y)
                else if (down && edge <= y.toInt() && settle == null && keysUp()) grab(y, edge)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                speed?.addMovement(e)
                val v = speed?.let { it.computeCurrentVelocity(1000); it.yVelocity } ?: 0f
                speed?.recycle(); speed = null
                if (grabbed) release(if (e.actionMasked == MotionEvent.ACTION_CANCEL) -1f else v)
            }
        }
        return grabbed
    }

    private fun keysUp() = page.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true

    private fun grab(y: Float, edge: Int) {
        val wic = page.windowInsetsController ?: return
        grabbed = true; asked = true
        grabY = edge.toFloat(); lastY = y; saidY = -1f; grabIme = -1   // from the bar's top: the bar stands under the finger at once
        Log.d("Montana", "kb_drag_begin finger=" + y.roundToInt() + " cover=" + cover)
        val signal = CancellationSignal().also { cut = it }
        wic.controlWindowInsetsAnimation(WindowInsets.Type.ime(), -1L, LinearInterpolator(), signal, object : WindowInsetsAnimationControlListener {
            override fun onReady(c: WindowInsetsAnimationController, types: Int) {
                if (!asked) { c.finish(true); return }
                ctl = c
                grabIme = c.currentInsets.bottom
                if (grabbed) follow(lastY) else release(0f)
            }
            override fun onFinished(c: WindowInsetsAnimationController) { done(c) }
            override fun onCancelled(c: WindowInsetsAnimationController?) { done(c) }
        })
    }

    private fun done(c: WindowInsetsAnimationController?) {
        if (c != null && ctl != null && ctl !== c) return
        settle?.cancel(); settle = null
        ctl = null; cut = null; asked = false; grabbed = false
        page.rootWindowInsets?.let { apply(coverOf(it)) }
    }

    private fun follow(y: Float) {
        lastY = y
        val c = ctl ?: return
        if (grabIme < 0) return
        val shown = c.shownStateInsets.bottom
        val hidden = c.hiddenStateInsets.bottom
        val want = (grabIme - (y - grabY)).roundToInt().coerceIn(hidden, shown)
        c.setInsetsAndAlpha(Insets.of(0, 0, 0, want), 1f, if (shown == hidden) 1f else (want - hidden).toFloat() / (shown - hidden))
        // the drag's own line, one per 8 points of finger (iOS kb_drag; the finger, the keys' top, the cover, the page's own)
        val d = page.resources.displayMetrics.density
        if (saidY < 0f || 8 * d <= abs(y - saidY)) {
            saidY = y
            Log.d("Montana", "kb_drag finger=" + (y / d).roundToInt() + " guide=" + ((page.rootView.height - want) / d).roundToInt() +
                " cover=" + (cover / d).roundToInt() + drawn())
        }
    }

    /** The finger let go: the keys stay if it was moving up or never took them down, else they go — in half the keyboard's time. */
    private fun release(v: Float) {
        grabbed = false
        val c = ctl
        if (c == null) { asked = false; cut?.cancel(); return }   // the platform had not handed them yet: they stay as they stood
        val shown = c.shownStateInsets.bottom
        val hidden = c.hiddenStateInsets.bottom
        val now = c.currentInsets.bottom
        val d = page.resources.displayMetrics.density
        val stay = v < -FLING * d || shown - 1 <= now
        val to = if (stay) shown else hidden
        Log.d("Montana", "kb_drag_end v=" + (v / d).roundToInt() + " stay=" + stay)
        grabbed = true   // the settle is still the finger's move: the page keeps the feed's offset to itself until it ends
        settle = ValueAnimator.ofInt(now, to).apply {
            duration = SETTLE_MS
            interpolator = PathInterpolator(0.2f, 0f, 0f, 1f)
            addUpdateListener { a ->
                val i = a.animatedValue as Int
                if (ctl === c) c.setInsetsAndAlpha(Insets.of(0, 0, 0, i), 1f, if (shown == hidden) 1f else (i - hidden).toFloat() / (shown - hidden))
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: Animator) {
                    if (settle !== a) return
                    settle = null
                    if (ctl === c) c.finish(stay)
                    if (!stay) page.post { letGo() }
                }
            })
            start()
        }
    }

    private companion object {
        const val FLING = 300f      // points a second upward that give the keys back whatever their place
        const val SETTLE_MS = 250L  // iOS MTKeyboardSpring 0.5 s / speed 2 after a drag
    }
}
