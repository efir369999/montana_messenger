package quest.montana.app

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.RectF
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.ImageView
import org.json.JSONObject
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// ─────────────────────────── the pictures of a conversation, full screen (iOS PhotoPresenter: the platform's viewer) ───────────────────────────

/**
 * THE PICTURES OF THE CONVERSATION a picture belongs to (iOS mtGalleryFiles): every picture of that chat whose file is on this
 * phone, in the feed's order. A video is not a page of it (the author's word 28.09): it opens in the player.
 */
fun picturesBeside(f: File): List<File> {
    val chat = Book.all().firstOrNull { ch -> ch.msgs.any { it.file == f.path } } ?: return listOf(f)
    return chat.msgs.mapNotNull { m ->
        val file = m.file?.let { File(it) }?.takeIf { it.exists() } ?: return@mapNotNull null
        val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
        if (man?.optString("k") == "img") file else null
    }.ifEmpty { listOf(f) }
}

/**
 * THE ALBUM (iOS MontanaPhotoViewer through PhotoPresenter.present(_:among:), MontanaProfile 1641-1875; MontanaMedia 3085-3114):
 * the conversation's pictures as pages — the page follows the finger sideways and settles; a tap in the outer 15 % of the
 * width turns the page, a tap elsewhere hides or shows the strip; pinch and a double tap enlarge; a pull down lets the picture
 * go and closes. Under the pages the strip of covers: the centred cover is the page, a tap on a cover turns to it, and the
 * picture fits above the strip's band, never under it. No buttons: the platform's back closes it, as the pull does.
 */
fun openPictures(act: MainActivity, start: File) {
    val c: Context = act
    val files = picturesBeside(start)
    val paged = 1 < files.size
    var at = files.indexOfFirst { it.path == start.path }.coerceAtLeast(0)
    lateinit var close: () -> Unit
    var chrome = true
    var foot = c.dp(34)
    val strip = if (paged) CoverStrip(act, files, at) else null
    val pager = PicturePager(act, files, at) { at = it; strip?.follow(it) }
    // the strip owns a band at the bottom and the photo fits above it (iOS stripBand: 120 + 10 + the safe inset)
    fun lay() {
        pager.setPadding(0, 0, 0, if (strip != null && chrome) c.dp(130) + foot else 0)
        strip?.animate()?.alpha(if (chrome && !pager.zoomed) 1f else 0f)?.setDuration(220)?.start()
    }
    pager.onTapAt = { x ->
        if (paged && !pager.zoomed && x < 0.15f) pager.turn(-1)
        else if (paged && !pager.zoomed && 0.85f < x) pager.turn(1)
        else { chrome = !chrome; lay() }
    }
    pager.onPull = { f -> strip?.alpha = if (chrome && f < 0.01f) 1f else 0f }   // steps aside the moment the hands work
    pager.onZoomed = { strip?.animate()?.alpha(if (chrome && !it) 1f else 0f)?.setDuration(220)?.start() }
    pager.onGone = { close() }
    strip?.onPick = { i -> pager.goTo(i) }
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        isClickable = true
        addView(pager, FrameLayout.LayoutParams(MATCH, MATCH))
        if (strip != null) addView(strip, FrameLayout.LayoutParams(MATCH, c.dp(120), Gravity.BOTTOM))
        setOnApplyWindowInsetsListener { _, ins ->
            foot = max(ins.getInsets(android.view.WindowInsets.Type.systemBars()).bottom, c.dp(16))
            (strip?.layoutParams as? FrameLayout.LayoutParams)?.let { it.bottomMargin = foot; strip?.layoutParams = it }
            lay(); ins
        }
    }
    pager.ground = page
    close = act.overlay(page)
    page.requestApplyInsets()
    lay()
}

/**
 * ONE PICTURE THAT ENLARGES (iOS MTZoomImage, the system's zooming scroll view): fitted at rest; pinch between 1× and 4×;
 * a double tap goes to 2.5× at the finger and back; while enlarged a drag moves it within its edges.
 */
class ZoomPicture(c: Context) : ImageView(c) {
    private val base = Matrix()
    private val m = Matrix()
    var scale = 1f; private set
    val zoomed get() = scale > 1.01f

    init { scaleType = ScaleType.MATRIX }

    fun show(b: Bitmap?) { setImageBitmap(b); post { fit() } }

    private fun fit() {
        val d = drawable ?: return
        if (width == 0 || height == 0) return
        base.setRectToRect(RectF(0f, 0f, d.intrinsicWidth.toFloat(), d.intrinsicHeight.toFloat()), RectF(0f, 0f, width.toFloat(), height.toFloat()), Matrix.ScaleToFit.CENTER)
        m.reset(); scale = 1f; apply()
    }
    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) { super.onSizeChanged(w, h, ow, oh); fit() }

    private fun apply() { imageMatrix = Matrix(base).apply { postConcat(m) } }

    /** Keep the enlarged picture within the screen: no black gap at an edge it can cover. */
    private fun bound() {
        val d = drawable ?: return
        val r = RectF(0f, 0f, d.intrinsicWidth.toFloat(), d.intrinsicHeight.toFloat())
        Matrix(base).apply { postConcat(m) }.mapRect(r)
        var dx = 0f; var dy = 0f
        if (r.width() <= width) dx = width / 2f - r.centerX() else { if (r.left > 0) dx = -r.left; if (r.right < width) dx = width - r.right }
        if (r.height() <= height) dy = height / 2f - r.centerY() else { if (r.top > 0) dy = -r.top; if (r.bottom < height) dy = height - r.bottom }
        m.postTranslate(dx, dy)
    }

    fun zoomBy(f: Float, px: Float, py: Float) {
        val to = (scale * f).coerceIn(1f, 4f)
        m.postScale(to / scale, to / scale, px, py); scale = to
        if (!zoomed) { m.reset(); scale = 1f }
        bound(); apply()
    }
    fun panBy(dx: Float, dy: Float) { m.postTranslate(dx, dy); bound(); apply() }

    /** Returns how far the picture could still move sideways before its edge (to let the page turn at the edge). */
    fun atEdge(dx: Float): Boolean {
        val d = drawable ?: return true
        val r = RectF(0f, 0f, d.intrinsicWidth.toFloat(), d.intrinsicHeight.toFloat())
        Matrix(base).apply { postConcat(m) }.mapRect(r)
        return if (dx > 0) r.left >= -1f else r.right <= width + 1f
    }

    fun toggleAt(px: Float, py: Float) {
        val from = scale; val to = if (zoomed) 1f else 2.5f
        ValueAnimator.ofFloat(from, to).apply {
            duration = 220
            addUpdateListener { a -> val v = a.animatedValue as Float; zoomBy(v / scale, px, py) }
            start()
        }
    }
}

/**
 * THE PAGES (iOS the platform viewer's paging): three pictures stand side by side — the one on the screen and its neighbours;
 * a sideways stroke moves them together and settles on the next page past a third of the width or on a fling. A stroke down
 * on a picture at rest pulls it away: the ground fades, and past a quarter of the height the viewer closes.
 */
class PicturePager(private val act: MainActivity, private val files: List<File>, start: Int, private val onPage: (Int) -> Unit) : FrameLayout(act) {
    var onTap: () -> Unit = {}
    var onTapAt: (Float) -> Unit = {}   // where across the page the tap landed, 0…1 (iOS MTAlbumPage onTap)
    var onZoomed: (Boolean) -> Unit = {}
    var onPull: (Float) -> Unit = {}
    var onGone: () -> Unit = {}
    var ground: View? = null
    private var at = start
    private val views = List(3) { ZoomPicture(act) }   // left, centre, right
    private val slop = ViewConfiguration.get(act).scaledTouchSlop
    private var axis = 0   // 0 undecided, 1 sideways, 2 pull
    private var downX = 0f; private var downY = 0f; private var lastX = 0f; private var lastY = 0f
    private var tracker: VelocityTracker? = null
    private var scaling = false
    private val cache = HashMap<Int, Bitmap?>()

    private val scaler = ScaleGestureDetector(act, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScaleBegin(d: ScaleGestureDetector): Boolean { scaling = true; return true }
        override fun onScale(d: ScaleGestureDetector): Boolean { views[1].zoomBy(d.scaleFactor, d.focusX, d.focusY); return true }
    })
    private val taps = GestureDetector(act, object : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean { onTapAt(e.x / max(1, width)); onTap(); return true }
        override fun onDoubleTap(e: MotionEvent): Boolean { views[1].toggleAt(e.x, e.y); postDelayed({ onZoomed(views[1].zoomed) }, 260); return true }
    })

    init {
        views.forEach { addView(it, LayoutParams(MATCH, MATCH)) }
        load()
    }

    private var turning = false
    val zoomed get() = views[1].zoomed
    /** An edge tap turns the page the way a swipe would (iOS MontanaPhotoViewer.turn); one turn at a time. */
    fun turn(d: Int) { if (!turning && at + d in files.indices) settle(d) }
    /** The strip chose a page: a neighbour slides in, a far one stands at once. */
    fun goTo(i: Int) {
        if (turning || i == at || i !in files.indices) return
        if (abs(i - at) == 1) settle(i - at) else { at = i; load() }
    }

    private fun bitmap(i: Int, done: (Bitmap?) -> Unit) {
        if (i !in files.indices) { done(null); return }
        if (cache.containsKey(i)) { done(cache[i]); return }
        act.background {
            val b = Media.preview(act, files[i], "img", 2400)
            act.onMain { cache[i] = b; if (cache.size > 7) cache.keys.filter { abs(it - at) > 2 }.forEach { cache.remove(it) }; done(b) }
        }
    }

    private fun load() {
        for (k in 0..2) {
            val i = at - 1 + k
            val v = views[k]
            v.show(null); v.visibility = if (i in files.indices) VISIBLE else INVISIBLE
            bitmap(i) { b -> if (at - 1 + k == i) v.show(b) }
        }
        place(0f)
        onPage(at)
    }

    private fun place(dx: Float) {
        views[0].translationX = dx - width
        views[1].translationX = dx
        views[2].translationX = dx + width
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) { super.onLayout(changed, l, t, r, b); place(views[1].translationX) }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        taps.onTouchEvent(e)
        if (tracker == null) tracker = VelocityTracker.obtain()
        tracker?.addMovement(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downX = e.x; downY = e.y; lastX = e.x; lastY = e.y; axis = 0; scaling = false }
            MotionEvent.ACTION_MOVE -> {
                if (scaling || e.pointerCount > 1) { lastX = e.x; lastY = e.y; return true }
                val dx = e.x - lastX; val dy = e.y - lastY
                val centre = views[1]
                if (axis == 0 && (abs(e.x - downX) > slop || abs(e.y - downY) > slop)) {
                    axis = when {
                        centre.zoomed -> if (centre.atEdge(e.x - downX) && abs(e.x - downX) > abs(e.y - downY) && files.size > 1) 1 else 3
                        abs(e.x - downX) > abs(e.y - downY) -> if (files.size > 1) 1 else 0
                        e.y > downY -> 2
                        else -> 0
                    }
                }
                when (axis) {
                    1 -> place(views[1].translationX + dx)
                    2 -> {
                        val f = ((e.y - downY) / height).coerceAtLeast(0f)
                        centre.translationY = e.y - downY
                        ground?.setBackgroundColor(Color.argb((255 * (1 - min(0.75f, f * 2))).toInt(), 0, 0, 0))
                        onPull(f)
                    }
                    3 -> centre.panBy(dx, dy)
                }
                lastX = e.x; lastY = e.y
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                tracker?.computeCurrentVelocity(1000)
                val vx = tracker?.xVelocity ?: 0f; val vy = tracker?.yVelocity ?: 0f
                tracker?.recycle(); tracker = null
                when (axis) {
                    1 -> {
                        val x = views[1].translationX
                        val go = when {
                            x < -width / 3f || vx < -act.dp(600) -> 1
                            x > width / 3f || vx > act.dp(600) -> -1
                            else -> 0
                        }.let { if (at + it in files.indices) it else 0 }
                        settle(go)
                    }
                    2 -> {
                        val c = views[1]
                        if (c.translationY > height / 4f || vy > act.dp(900)) {
                            c.animate().translationY(height.toFloat()).alpha(0f).setDuration(180).withEndAction { onGone() }.start()
                        } else {
                            c.animate().translationY(0f).setDuration(200).start()
                            ground?.setBackgroundColor(Color.BLACK); onPull(0f)
                        }
                    }
                }
                axis = 0
                onZoomed(views[1].zoomed)
            }
        }
        return true
    }

    private fun settle(go: Int) {
        turning = true
        val from = views[1].translationX
        val to = -go * width.toFloat()
        ValueAnimator.ofFloat(from, to).apply {
            duration = 220
            addUpdateListener { place(it.animatedValue as Float) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { turning = false; if (go != 0) { at += go; load() } }
            })
            start()
        }
    }
}

/** The strip's covers, small pictures born off the frame and kept for the album's life (iOS mtCoverCache, 256 px). */
private val stripCovers = object : android.util.LruCache<String, Bitmap>(16 * 1024 * 1024) { override fun sizeOf(key: String, value: Bitmap) = value.byteCount }

/**
 * THE STRIP OF COVERS (iOS MontanaPhotoViewer.thumbStrip, MontanaProfile 1822-1873): the album covers' own scroll — the centred
 * cover large and flat, its neighbours turned in perspective and receding, overlapping by more than a quarter; the scroll snaps
 * to a cover, and the centred cover IS the page; a tap on a cover turns to it. 96 points a cover, 120 the strip.
 */
class CoverStrip(private val act: MainActivity, private val files: List<File>, start: Int) : FrameLayout(act) {
    var onPick: (Int) -> Unit = {}
    private val side = act.dp(96)
    private val step = side * 0.72f   // iOS HStack(spacing: -side * 0.28)
    private var pos = start.toFloat()
    private val covers = HashMap<Int, ImageView>()
    private var downX = 0f
    private var lastX = 0f
    private var moved = false
    private var tracker: VelocityTracker? = null
    private var glide: ValueAnimator? = null
    private val slop = ViewConfiguration.get(act).scaledTouchSlop

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) { super.onLayout(changed, l, t, r, b); place() }

    /** The page turned by a swipe or an edge tap: the strip follows it to its cover. */
    fun follow(i: Int) { if (glide == null && tracker == null && i.toFloat() != pos) slide(i, tell = false) }

    private fun cover(i: Int): ImageView = covers.getOrPut(i) {
        ImageView(act).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            setBackgroundColor(Color.rgb(51, 51, 51))
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(6).toFloat())
            }
            clipToOutline = true
            cameraDistance = 8000 * resources.displayMetrics.density
            this@CoverStrip.addView(this, LayoutParams(side, side, Gravity.CENTER_VERTICAL or Gravity.START))
            val f = files[i]
            val kept = stripCovers.get(f.path)
            if (kept != null) setImageBitmap(kept)
            else act.background {
                val b = Media.preview(act, f, "img", 256) ?: return@background
                stripCovers.put(f.path, b)
                act.onMain { setImageBitmap(b) }
            }
        }
    }

    private fun place() {
        val w = width
        if (w == 0) return
        val reach = w / 2f / step + 2
        val first = max(0, (pos - reach).toInt())
        val last = min(files.size - 1, (pos + reach).toInt() + 1)
        covers.keys.filter { it < first || last < it }.forEach { k -> removeView(covers.remove(k)) }
        for (i in first..last) {
            val v = cover(i)
            val cx = w / 2f + (i - pos) * step
            v.translationX = cx - side / 2f
            // the distance from the strip's centre, -1…1 across one cover: the centred cover flat and full, a neighbour turned away
            val t = ((cx - w / 2f) / (side * 1.1f)).coerceIn(-1f, 1f)
            v.rotationY = -t * 55f
            v.scaleX = 1 - 0.28f * abs(t); v.scaleY = v.scaleX
            v.alpha = 1 - 0.35f * abs(t)
            v.translationZ = -abs(i - pos) * act.dp(4)
        }
    }

    private fun slide(to: Int, tell: Boolean) {
        glide?.cancel()
        glide = ValueAnimator.ofFloat(pos, to.toFloat()).apply {
            duration = 240
            addUpdateListener { pos = it.animatedValue as Float; place() }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { glide = null; pos = to.toFloat(); place(); if (tell) onPick(to) }
            })
            start()
        }
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (tracker == null) tracker = VelocityTracker.obtain()
        tracker?.addMovement(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { glide?.cancel(); glide = null; downX = e.x; lastX = e.x; moved = false; parent?.requestDisallowInterceptTouchEvent(true) }
            MotionEvent.ACTION_MOVE -> {
                if (slop < abs(e.x - downX)) moved = true
                if (moved) { pos = (pos - (e.x - lastX) / step).coerceIn(-0.4f, files.size - 0.6f); place() }
                lastX = e.x
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                tracker?.computeCurrentVelocity(1000)
                val vx = tracker?.xVelocity ?: 0f
                tracker?.recycle(); tracker = null
                // a drag snaps to the cover it carries to; a tap turns to the cover under the finger
                val to = if (moved) Math.round(pos - vx / step * 0.25f) else Math.round(pos + (e.x - width / 2f) / step)
                slide(to.coerceIn(0, files.size - 1), tell = true)
            }
        }
        return true
    }
}
