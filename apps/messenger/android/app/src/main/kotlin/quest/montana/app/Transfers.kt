package quest.montana.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout

/**
 * THE TRANSFER BOARD (iOS MTTransferBoard, MontanaBubble.swift:130-147 at 2155): the one owner of a file's live transfer --
 * the share 0..1 and the word beside it (megabytes) -- keyed by the letter's name. A tick is not content: the feed never
 * rebuilds a row for it; the mark inside the row listens to the board and redraws itself.
 */
object Transfers {
    private class Ride(val p: Float, val word: String?)
    private val rides = HashMap<String, Ride>()
    private val ears = HashMap<String, MutableSet<() -> Unit>>()
    private val main = Handler(Looper.getMainLooper())

    fun progress(mid: String): Float? = synchronized(rides) { rides[mid]?.p }
    fun word(mid: String): String? = synchronized(rides) { rides[mid]?.word }
    fun riding(mid: String): Boolean = progress(mid) != null

    /** null -- the transfer is over (done or broken): the mark leaves the tile. */
    fun set(mid: String, p: Float?, word: String? = null) {
        synchronized(rides) { if (p == null) rides.remove(mid) else rides[mid] = Ride(p.coerceIn(0f, 1f), word) }
        main.post { ears[mid]?.toList()?.forEach { it() } }
    }
    /** «1.5/4.0 MB», as iOS writes it (String(format: "%.1f/%.1f MB")). */
    fun megabytes(share: Float, total: Long): String {
        val mb = total / 1_048_576.0
        return String.format(java.util.Locale.US, "%.1f/%.1f MB", share * mb, mb)
    }

    internal fun listen(mid: String, ear: () -> Unit) { ears.getOrPut(mid) { LinkedHashSet() }.add(ear) }
    internal fun forget(mid: String, ear: () -> Unit) { ears[mid]?.let { it.remove(ear); if (it.isEmpty()) ears.remove(mid) } }
}

/** The ring itself (iOS Circle().trim … stroke 2, from twelve o'clock): a pale full circle, the done part white over it. */
private class Ring(c: Context) : View(c) {
    var share = 0f
        set(v) { if (field != v) { field = v; invalidate() } }
    private val line = c.dp(2).toFloat()
    private val pale = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = line; color = Color.argb(89, 255, 255, 255) }
    private val done = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = line; color = Color.WHITE; strokeCap = Paint.Cap.ROUND }
    private val box = RectF()
    override fun onDraw(cv: Canvas) {
        box.set(line / 2, line / 2, width - line / 2, height - line / 2)
        cv.drawOval(box, pale)
        cv.drawArc(box, -90f, 360f * share, false, done)
    }
}

/**
 * A FILE ON ITS WAY, DRAWN WHERE IT STANDS (iOS progressPill / mediaProgressOverlay 310-356 and groupTile 1485-1509 at 2155):
 * it stands over its picture only while the board holds the letter, and redraws itself on every tick.
 *   tile -- the picture dims a quarter; the ring in the middle, 16..26 by the tile's width; the percent under it only when
 *           the tile has room (wider than 96, taller than 68): never past the tile's edges, no word and no cross in a tile.
 *   plate -- a single picture dims a fifth; top-left, a dark pill: the ring of 18, the megabytes or the percent, the cross.
 *   line -- (`line`, iOS 404698df under the voice's capsule and the round note) the same pill alone, in the line under them where the
 *           voice's length stands: the capsule and the circle are never dimmed.
 * `idle` -- what stands while nothing rides (the spinner of a picture not yet here): it leaves when the ring comes.
 */
internal class TransferMark(c: Context, private val mid: String, private val tile: Pair<Float, Float>?, private val idle: View? = null,
                            line: Boolean = false) : FrameLayout(c) {
    private val ring = Ring(c)
    private val percent = c.text("", 11f, Color.WHITE, bold = true).apply { maxLines = 1 }
    private val ear: () -> Unit = { show() }

    init {
        if (tile != null) {
            setBackgroundColor(Color.argb(64, 0, 0, 0))   // iOS black 0.25
            val side = c.dp(minOf(26f, maxOf(16f, tile.first * 0.22f)))
            val roomy = 96f < tile.first && 68f < tile.second
            addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                addView(ring, LinearLayout.LayoutParams(side, side))
                if (roomy) addView(percent, LinearLayout.LayoutParams(WRAP, WRAP).apply { topMargin = c.dp(3) })
            }, LayoutParams(WRAP, WRAP, Gravity.CENTER))
        } else {
            if (!line) setBackgroundColor(Color.argb(51, 0, 0, 0))   // iOS black 0.2
            val pill = c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                background = GradientDrawable().apply { cornerRadius = c.dp(14).toFloat(); setColor(Color.argb(153, 0, 0, 0)) }
                setPadding(c.dp(8), c.dp(5), c.dp(8), c.dp(5))
                addView(ring, LinearLayout.LayoutParams(c.dp(18), c.dp(18)))
                addView(percent, LinearLayout.LayoutParams(WRAP, WRAP).apply { marginStart = c.dp(7); marginEnd = c.dp(7) })
                addView(c.icon(R.drawable.ic_close, Color.WHITE, 10).apply {
                    background = GradientDrawable().apply { cornerRadius = c.dp(10).toFloat(); setColor(Color.argb(140, 0, 0, 0)) }
                    setPadding(c.dp(5), c.dp(5), c.dp(5), c.dp(5))
                }, LinearLayout.LayoutParams(c.dp(20), c.dp(20)))
            }
            addView(pill, LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.START).apply { if (!line) setMargins(c.dp(8), c.dp(8), c.dp(8), 0) })
        }
        show()
    }

    private fun show() {
        val p = Transfers.progress(mid)
        visibility = if (p == null) GONE else VISIBLE
        idle?.visibility = if (p == null) VISIBLE else GONE
        if (p == null) return
        ring.share = p
        percent.text = (if (tile == null) Transfers.word(mid) else null) ?: "${(p * 100).toInt()}%"   // USER-DATA: a measured number, not a word
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); Transfers.listen(mid, ear); show() }
    override fun onDetachedFromWindow() { Transfers.forget(mid, ear); super.onDetachedFromWindow() }
}
