package quest.montana.app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Outline
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView

/**
 * THE COIN'S PULL (iOS MontanaCoinSpinner, MontanaChatsList 94-148; the author's words 10.09 and 11.09): a pull on the whole feed, as on
 * a web page, refreshes — and what turns while it does is the Montana coin, face and back, the size of a row's avatar. The coin is not
 * there before the feed is drawn forty points; let go past 140 and the feed refreshes, short of it nothing; the turn is the pull — the
 * back up at the trigger, the whole round at 240, never a second one; let go past the trigger, the round it has begun completes in
 * 0.35 s while the feed keeps a gap of 82 open. The refresh is the activation road (iOS pullRefresh 828-835): the box asked, the queue
 * drained, the waiting files retried (Post.fetch), every peer's last word swept (Signal.sweep); the mesh needs no raising here — the
 * channels are knocked every five seconds while the app lives (Channels.start), and Android has no extension's stash to drain.
 * One law for every page under the bar (iOS MontanaTimePanel 150-162): the page hands its list in and draws nothing of it itself.
 */
class CoinPull(c: Context, private val list: View, private val onRefresh: () -> Unit = { activationRoad() }) : FrameLayout(c) {
    companion object {
        const val SIDE = 58f       // the row's avatar circle
        const val START = 40f      // the coin is not there before the feed is drawn this far
        const val TRIGGER = 140f   // let go past this and the feed refreshes; short of it, nothing
        const val HOLD = 82f       // the gap the feed keeps open while the round completes
        const val FULL = 240f      // drawn this far the coin has made its whole round — never more than one
        const val FINISH = 350L    // let go: the round it has begun completes this fast

        /** THE ROUND IS THE PULL (iOS angle(forPull:) 117-119): the back up at the trigger, the whole round at FULL. */
        fun angle(pull: Float) = 360f * ((pull - START) / (FULL - START)).coerceIn(0f, 1f)

        /** The activation road (iOS 829-831: drainInbox, onForeground, drainAll): the box asked, every waiting letter tried. */
        fun activationRoad() { Thread { runCatching { Post.fetch() }; runCatching { Signal.sweep() } }.start() }
    }

    private val density = resources.displayMetrics.density
    private val slop = ViewConfiguration.get(c).scaledTouchSlop
    private val coin = ImageView(c).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        setImageResource(R.drawable.coin_face)
        outlineProvider = object : ViewOutlineProvider() { override fun getOutline(v: View, o: Outline) { o.setOval(0, 0, v.width, v.height) } }
        clipToOutline = true
        cameraDistance = 8000 * resources.displayMetrics.density
        alpha = 0f
    }
    private var downY = 0f
    private var pulling = false
    private var busy = false
    private var pull = 0f   // how far the feed is drawn down, in points

    init {
        addView(list, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(coin, LayoutParams((SIDE * density).toInt(), (SIDE * density).toInt(), Gravity.TOP or Gravity.CENTER_HORIZONTAL))
    }

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downY = e.y; pulling = false }
            MotionEvent.ACTION_MOVE -> if (!busy && !list.canScrollVertically(-1) && slop < e.y - downY) { pulling = true; downY = e.y; return true }
        }
        return false
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!pulling) return super.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_MOVE -> { pull = maxOf(0f, (e.y - downY) / density * 0.55f); draw(angle(pull), held = true) }   // the feed's own give, as a rubber band
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { pulling = false; release() }
        }
        return true
    }

    /** One frame: the feed drawn down by the pull, the coin centred in the gap, its face the face really up at this angle (iOS face 137-147). */
    private fun draw(a: Float, held: Boolean) {
        list.translationY = pull * density
        val fraction = ((pull - START) / (TRIGGER - START)).coerceIn(0f, 1f)
        val front = a % 360f < 90f || 270f < a % 360f
        coin.setImageResource(if (front) R.drawable.coin_face else R.drawable.coin_back)
        coin.scaleX = if (front) 1f else -1f   // the rotation mirrors whatever is behind the edge: mirrored back again
        coin.rotationY = a
        coin.translationY = list.paddingTop + maxOf(0f, (pull - SIDE) / 2f) * density   // the list's room under the bar is above the gap
        if (held) { val s = 0.6f + 0.4f * fraction; coin.scaleY = s; coin.scaleX *= s; coin.alpha = fraction }
    }

    private fun release() {
        if (TRIGGER <= pull) {
            busy = true
            val from = angle(pull)
            val gap0 = pull
            onRefresh()
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = FINISH
                interpolator = DecelerateInterpolator()
                addUpdateListener { v ->
                    val t = v.animatedValue as Float
                    pull = gap0 + (HOLD - gap0) * t
                    coin.alpha = 1f; coin.scaleY = 1f
                    draw(from + (360f - from) * t, held = false)
                }
                start()
            }
            postDelayed({ settle() }, FINISH + 650)   // the round completes, the gap stays a breath, then the feed returns
        } else settle()
    }

    private fun settle() {
        val gap0 = pull
        val a0 = coin.alpha
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 250
            interpolator = DecelerateInterpolator()
            addUpdateListener { v ->
                val t = v.animatedValue as Float
                pull = gap0 * (1 - t)
                list.translationY = pull * density
                coin.translationY = list.paddingTop + maxOf(0f, (pull - SIDE) / 2f) * density
                coin.alpha = a0 * (1 - t)
            }
            start()
        }
        postDelayed({ busy = false }, 260)
    }
}
