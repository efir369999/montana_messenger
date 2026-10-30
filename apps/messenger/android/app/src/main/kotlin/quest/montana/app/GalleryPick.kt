package quest.montana.app

import android.animation.ValueAnimator
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.LruCache
import android.util.Size
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.BaseAdapter
import android.widget.FrameLayout
import android.widget.GridView
import android.widget.ImageView
import android.widget.ProgressBar
import java.util.concurrent.Executors
import kotlin.math.abs

// ─────────────────────────── the gallery of the compose row (iOS MTGalleryPick) ───────────────────────────

/** ONE PICTURE OF THE PHONE'S LIBRARY (iOS PHAsset): its address, a film or not, a film's length, the moment it was taken. */
class LibraryItem(val id: Long, val uri: Uri, val video: Boolean, val durMs: Long, val at: Long)

/** THE PHONE'S OWN LATEST PICTURES (iOS RecentMedia): photos and films, newest first; read only with the person's yes. */
object Library {
    fun perms(): Array<String> = when {
        34 <= Build.VERSION.SDK_INT -> arrayOf(android.Manifest.permission.READ_MEDIA_IMAGES, android.Manifest.permission.READ_MEDIA_VIDEO,
            android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        33 <= Build.VERSION.SDK_INT -> arrayOf(android.Manifest.permission.READ_MEDIA_IMAGES, android.Manifest.permission.READ_MEDIA_VIDEO)
        else -> arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
    }
    /** Whole or a part the person chose (Android 14's «selected photos», iOS limited access): either lets the grid show it. */
    fun allowed(c: Context): Boolean = perms().any { c.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    /** Only a part the person chose (iOS PHAuthorizationStatus .limited): Android 14's «selected photos», the whole library not granted. */
    fun partial(c: Context): Boolean = 34 <= Build.VERSION.SDK_INT &&
        c.checkSelfPermission(android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED &&
        c.checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) != PackageManager.PERMISSION_GRANTED

    /** What a prior warm or read already found, shown at once while a fresh read runs underneath (iOS RecentMedia.assets). */
    @Volatile private var cached: List<LibraryItem>? = null
    fun cachedNow(): List<LibraryItem>? = cached

    /** THE LIBRARY IS READ BEFORE THE FINGER ASKS FOR IT (iOS RecentMedia.warm, MontanaMedia.swift:1301-1310 at 2155,
     * atom 1cf77b0a8360, the author's word 22.09: «the first time it shows no photographs, only the second time»):
     * the chat warms it at its own opening, off the screen's thread, asking for no permission here -- only reading
     * what is already granted. */
    fun warm(c: Context) { if (allowed(c)) Thread { recent(c) }.start() }

    fun recent(c: Context, limit: Int = 600): List<LibraryItem> {
        val out = ArrayList<LibraryItem>()
        fun read(base: Uri, video: Boolean) {
            val proj = if (video) arrayOf("_id", "datetaken", "date_added", "duration") else arrayOf("_id", "datetaken", "date_added")
            c.contentResolver.query(base, proj, null, null, "date_added DESC")?.use { cur ->
                var n = 0
                while (n < limit && cur.moveToNext()) {
                    val id = cur.getLong(0)
                    val taken = cur.getLong(1)
                    out.add(LibraryItem(id, ContentUris.withAppendedId(base, id), video, if (video) cur.getLong(3) else 0L,
                        if (0L < taken) taken else cur.getLong(2) * 1000))
                    n++
                }
            }
        }
        runCatching { read(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, false) }
        runCatching { read(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true) }
        return out.sortedByDescending { it.at }.take(limit).also { cached = it }
    }

    /** The covers (iOS MTAssetImages: 360 px, one bounded cache, a tile holds its own picture). */
    private val covers = Caches.kept("gallery_covers", object : LruCache<Long, Bitmap>(24 * 1024 * 1024) { override fun sizeOf(key: Long, value: Bitmap) = value.byteCount })
    private val work = Executors.newFixedThreadPool(3)
    @Suppress("DEPRECATION")
    fun cover(c: Context, item: LibraryItem, into: ImageView) {
        into.tag = item.id
        covers.get(item.id)?.let { into.setImageBitmap(it); return }
        into.setImageDrawable(null)
        work.execute {
            val b = runCatching {
                if (29 <= Build.VERSION.SDK_INT) c.contentResolver.loadThumbnail(item.uri, Size(360, 360), null)
                else if (item.video) MediaStore.Video.Thumbnails.getThumbnail(c.contentResolver, item.id, MediaStore.Video.Thumbnails.MINI_KIND, null)
                else MediaStore.Images.Thumbnails.getThumbnail(c.contentResolver, item.id, MediaStore.Images.Thumbnails.MINI_KIND, null)
            }.getOrNull() ?: return@execute
            covers.put(item.id, b)
            into.post { if (into.tag == item.id) into.setImageBitmap(b) }
        }
    }
}

/** THE PICK CIRCLE (iOS MTPickOrder): 27 points, the white ring; chosen — the platform's tint and the number of the choice. */
private class PickCircle(c: Context) : View(c) {
    var order = -1
        set(v) { field = v; invalidate() }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    override fun onDraw(canvas: Canvas) {
        val r = width / 2f
        val ring = 2 * resources.displayMetrics.density
        paint.style = Paint.Style.FILL
        paint.color = if (order < 0) Color.argb(71, 0, 0, 0) else MT.blue
        canvas.drawCircle(r, r, r, paint)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = ring; paint.color = Color.WHITE
        canvas.drawCircle(r, r, r - ring / 2, paint)
        if (0 <= order) {
            paint.style = Paint.Style.FILL; paint.color = Color.BLACK
            paint.textSize = 13 * resources.displayMetrics.scaledDensity; paint.isFakeBoldText = true; paint.textAlign = Paint.Align.CENTER
            canvas.drawText((order + 1).toString(), r, r - (paint.descent() + paint.ascent()) / 2, paint)
        }
    }
}

/** A TILE OF THE GRID (iOS SelectableThumb): the cover, the veil over a chosen one, a film's length, the circle top right. */
private class PickTile(c: Context) : FrameLayout(c) {
    val pic = ImageView(c).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
    private val veil = View(c).apply { setBackgroundColor(MT.withAlpha(MT.blue, 0.22f)) }
    private val dur = c.text("", 11f, Color.WHITE, bold = true).apply {
        background = c.rounded(Color.argb(128, 0, 0, 0), 9); setPadding(c.dp(5), c.dp(1), c.dp(5), c.dp(1))
    }
    private val circle = PickCircle(c)
    init {
        setBackgroundColor(Color.rgb(41, 41, 41))
        addView(pic, LayoutParams(MATCH, MATCH))
        addView(veil, LayoutParams(MATCH, MATCH))
        addView(dur, LayoutParams(WRAP, WRAP, Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, c.dp(5), c.dp(5)) })
        addView(circle, LayoutParams(c.dp(27), c.dp(27), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(6), c.dp(6), 0) })
    }
    override fun onMeasure(w: Int, h: Int) = super.onMeasure(w, w)
    fun bind(item: LibraryItem, order: Int) {
        Library.cover(context, item, pic)
        veil.visibility = if (order < 0) View.GONE else View.VISIBLE
        circle.order = order
        dur.visibility = if (item.video) View.VISIBLE else View.GONE
        if (item.video) { val s = item.durMs / 1000; dur.text = String.format("%d:%02d", s / 60, s % 60) }
    }
}

/** The camera's tile, the first of the grid (iOS MTCameraTile): the glyph and its word on the dark tile. */
private class CameraTile(c: Context) : FrameLayout(c) {
    init {
        setBackgroundColor(Color.rgb(41, 41, 41))
        contentDescription = c.getString(R.string.gp_camera)
        addView(c.vstack {
            addView(c.icon(R.drawable.ic_add_a_photo, Color.WHITE, 26), lp(c.dp(26), c.dp(26)))
            gap(6)
            addView(c.text(c.getString(R.string.gp_camera), 11f, Color.WHITE), lp(WRAP, WRAP))
        }, LayoutParams(WRAP, WRAP, Gravity.CENTER))
    }
    override fun onMeasure(w: Int, h: Int) = super.onMeasure(w, w)
}

/**
 * ONE GRID OF TILES, THE PINCH LIVE (iOS MTTileGrid, MontanaMedia.swift:2454-2588 at 2155; atom d757ba09135c, the author's word 19.09
 * «as native as the system's grid»): 1, 2, 3, 5 or 8 in a row, three to begin with; fingers parting -- fewer, closing -- more. The grid
 * re-lays itself UNDER the fingers, its progress the pinch's own scale ((scale - 1) / 0.6 parting, (1 - scale) / 0.4 closing), and on
 * release past 0.35 it finishes to the next count, short of it it falls back (iOS startInteractiveTransition, transitionProgress).
 * The platform's grid has no transition of two layouts, so the denser of the two stands laid out and every tile is moved and sized
 * between its two places; the tile under the fingers keeps its row's height, the anchor of both. No tile is rebuilt.
 */
private class TileGrid(c: Context) : GridView(c) {
    var columns = 3
        private set
    private var to = 0                 // the count the pinch leads to; 0 -- no transition
    private var anchor = 0             // the tile the fingers took, by position
    private var anchorY = 0f           // its row's top, kept by both layouts
    private var progress = 0f
    private var settling: ValueAnimator? = null
    private val gap = c.dp(2)
    private val pinch = android.view.ScaleGestureDetector(c, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
        var scale = 1f
        var focusX = 0f; var focusY = 0f
        override fun onScaleBegin(d: android.view.ScaleGestureDetector): Boolean {
            if (settling != null) return false
            scale = 1f; focusX = d.focusX; focusY = d.focusY; return true
        }
        override fun onScale(d: android.view.ScaleGestureDetector): Boolean {
            scale *= d.scaleFactor
            if (to == 0) {
                if (abs(scale - 1) <= 0.04f) return true
                val i = STEPS.indexOf(columns); val j = if (1 < scale) i - 1 else i + 1
                if (i < 0 || j !in STEPS.indices) return true
                begin(STEPS[j], focusX, focusY)
            }
            val p = if (to < columns) (scale - 1) / 0.6f else (1 - scale) / 0.4f
            show(p.coerceIn(0f, 1f))
            return true
        }
        override fun onScaleEnd(d: android.view.ScaleGestureDetector) { if (to != 0) settle(0.35f < progress) }
    })
    private var pinching = false   // this touch belongs to the pinch, from its second finger to the last one's lift
    init { pinch.isQuickScaleEnabled = false }   // a double tap and drag is no pinch in iOS: two fingers only

    /**
     * THE DRAG FROM THE CIRCLE (iOS MTTileGrid pan, MontanaMedia.swift:2591-2658 at 2155; atoms b8041f92ad34, b171cbb96007):
     * a touch that begins in a tile's top right 44 drags a selection along the tiles -- the scroll and the sheet's pull wait
     * for it; anywhere else the touch is the scroll's, and a press that never moves stays the tile's tap. THE TILE THE FINGER
     * TOOK IS THE TILE IT PRESSED (the author's word 22.09): the press names it, not the point where the drag got past the slop.
     * Near an edge (70) the grid rolls itself, 6 a frame of 60 a second. The owner keeps the range: [onDragBegin] the pressed
     * tile, [onDragTo] the tile under the finger; [fixed] tiles (the camera) are in no drag. Nobody to tell -- no drag.
     */
    var onDragBegin: ((Int) -> Unit)? = null
    var onDragTo: ((Int) -> Unit)? = null
    var fixed: (Int) -> Boolean = { false }
    private var pressed = -1          // the tile whose circle the finger pressed; -1 -- none
    private var dragging = false
    private var downX = 0f; private var downY = 0f
    private var lastX = 0f; private var lastY = 0f
    private val slop = ViewConfiguration.get(c).scaledTouchSlop
    private var rollSpeed = 0f        // px a 1/60 s; 0 -- no roll
    private var rollAt = 0L
    private var rollCarry = 0f
    private val roll = object : android.view.Choreographer.FrameCallback {
        override fun doFrame(t: Long) {
            if (rollSpeed == 0f || !dragging) { rollAt = 0L; return }
            val dt = if (rollAt == 0L) 1f / 60 else (t - rollAt) / 1e9f
            rollAt = t
            rollCarry += rollSpeed * dt.coerceAtMost(0.1f) * 60   // a frame of 120 a second rolls half of a 60's
            val px = rollCarry.toInt(); rollCarry -= px
            if (px != 0) scrollListBy(px)
            dragAt(lastX, lastY)   // the finger stands, the tiles go under it: the range follows them
            android.view.Choreographer.getInstance().postFrameCallback(this)
        }
    }

    /** The tile at a point, or -1: none, or one outside any drag. */
    private fun tileAt(x: Float, y: Float): Int {
        val p = pointToPosition(x.toInt(), y.toInt())
        return if (p == android.widget.AdapterView.INVALID_POSITION || fixed(p)) -1 else p
    }
    /** The circle's corner of the tile under a press: its top right 44 (iOS cell.frame.maxX - 44, minY, 44, 44). */
    private fun cornerAt(x: Float, y: Float): Int {
        val p = tileAt(x, y).takeIf { 0 <= it } ?: return -1
        val v = getChildAt(p - firstVisiblePosition) ?: return -1
        val s = context.dp(44)
        return if (v.right - s <= x && x <= v.right && v.top <= y && y <= v.top + s) p else -1
    }
    private fun dragAt(x: Float, y: Float) { tileAt(x, y).takeIf { 0 <= it }?.let { onDragTo?.invoke(it) } }
    private fun endDrag() {
        dragging = false; pressed = -1; rollSpeed = 0f; rollAt = 0L; rollCarry = 0f
        android.view.Choreographer.getInstance().removeFrameCallback(roll)
    }

    /** The drag's own share of a touch; true -- the touch is the drag's and goes no further. */
    private fun drag(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                endDrag()
                if (onDragTo != null && to == 0 && settling == null) pressed = cornerAt(e.x, e.y)
                downX = e.x; downY = e.y
                // the sheet's pull waits for the circle's drag, as the scroll does
                if (0 <= pressed) parent?.requestDisallowInterceptTouchEvent(true)
                return false
            }
            MotionEvent.ACTION_POINTER_DOWN -> if (!dragging) pressed = -1   // two fingers are the pinch's (iOS maximumNumberOfTouches 1)
            MotionEvent.ACTION_MOVE -> {
                lastX = e.x; lastY = e.y
                if (!dragging) {
                    if (pressed < 0 || 1 < e.pointerCount || abs(e.x - downX).coerceAtLeast(abs(e.y - downY)) <= slop) return false
                    dragging = true
                    // the tap and the scroll begun under the finger are let go: the touch is the drag's from here
                    val cancel = MotionEvent.obtain(e).apply { action = MotionEvent.ACTION_CANCEL }
                    super.dispatchTouchEvent(cancel); cancel.recycle()
                    onDragBegin?.invoke(pressed)
                }
                dragAt(e.x, e.y)
                val edge = context.dp(70)
                val was = rollSpeed
                // the edges of the tiles seen: the foot stands over the grid's bottom padding (iOS: its safe-area inset)
                rollSpeed = when { height - paddingBottom - edge < e.y -> context.dp(6).toFloat(); e.y < paddingTop + edge -> -context.dp(6).toFloat(); else -> 0f }
                if (rollSpeed != 0f && was == 0f) {
                    rollAt = 0L
                    android.view.Choreographer.getInstance().apply { removeFrameCallback(roll); postFrameCallback(roll) }
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { val was = dragging; endDrag(); return was }
        }
        return dragging
    }

    override fun onDetachedFromWindow() { endDrag(); super.onDetachedFromWindow() }

    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        if (drag(e)) return true
        pinch.onTouchEvent(e)
        if (e.actionMasked == MotionEvent.ACTION_DOWN) pinching = false
        if (!pinching && (1 < e.pointerCount || to != 0 || settling != null)) {
            // two fingers belong to the pinch: the scroll and the tap begun under the first finger are let go
            pinching = true
            val cancel = MotionEvent.obtain(e).apply { action = MotionEvent.ACTION_CANCEL }
            super.dispatchTouchEvent(cancel); cancel.recycle()
        }
        return if (pinching) true else super.dispatchTouchEvent(e)
    }

    private fun side(n: Int) = (width - paddingLeft - paddingRight - (n - 1) * gap) / n.toFloat()
    /** The anchor's row top in a layout of `n`: kept, unless the grid's first row would then stand below its top. */
    private fun anchorTop(n: Int) = minOf(anchorY, paddingTop + (anchor / n) * (side(n) + gap))
    /** Where the tile at `p` stands in a layout of `n` columns, the anchor's row at its kept top. */
    private fun place(p: Int, n: Int): Pair<Float, Float> {
        val step = side(n) + gap
        return (paddingLeft + (p % n) * step) to (anchorTop(n) + (p / n - anchor / n) * step)
    }

    private var holding = false   // a new count laid, the anchor not yet brought to its row: the tiles stand where they will

    private fun begin(target: Int, fx: Float, fy: Float) {
        anchor = pointToPosition(fx.toInt(), fy.toInt()).takeIf { it != android.widget.AdapterView.INVALID_POSITION } ?: firstVisiblePosition
        anchorY = getChildAt(anchor - firstVisiblePosition)?.top?.toFloat() ?: paddingTop.toFloat()
        to = target; progress = 0f
        relay(maxOf(columns, to))   // laid out as the denser; every tile is then moved to its place
    }

    /**
     * A new count, the anchor's row kept. NOT setSelectionFromTop: in touch mode the platform's grid lays its LAYOUT_SPECIFIC
     * from mSelectedPosition, which is -1 there -- the first row by luck at 2 and more in a row, and a tile at -1 at one in a
     * row (measured 14.10 on A1: IndexOutOfBounds in getView, the app gone). setSelection brings the anchor in; onLayout then
     * rolls the grid by the anchor's own miss (scrollListBy).
     */
    private fun relay(n: Int) {
        numColumns = n
        setSelection(anchor)
        holding = true
        requestLayout()
    }

    private fun show(p: Float) { progress = p; lay() }

    /**
     * Every tile drawn at its place, whatever the platform laid: during the pinch between its sparse and its dense place (k 1 --
     * the denser count, 0 -- the sparser), after it at the place of the count chosen, until the grid stands there itself.
     */
    private fun lay() {
        if (to == 0 && !holding) return
        val dense = if (to == 0) columns else maxOf(columns, to)
        val sparse = if (to == 0) columns else minOf(columns, to)
        val k = if (to == 0) 1f else if (to == dense) progress else 1 - progress
        val sd = side(dense); val ss = side(sparse)
        val size = ss + (sd - ss) * k
        for (i in 0 until childCount) {
            val v = getChildAt(i); val p = firstVisiblePosition + i
            val (sx, sy) = place(p, sparse); val (dx, dy) = place(p, dense)
            v.pivotX = 0f; v.pivotY = 0f
            v.translationX = sx + (dx - sx) * k - v.left
            v.translationY = sy + (dy - sy) * k - v.top
            v.scaleX = size / v.width.coerceAtLeast(1); v.scaleY = size / v.height.coerceAtLeast(1)
        }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        if (holding) {
            val v = getChildAt(anchor - firstVisiblePosition)
            if (v != null) {
                val miss = v.top - anchorTop(numColumns).toInt()
                if (miss != 0) scrollListBy(miss)
                if (to == 0) { holding = false; clear() }
            }
        }
        lay()
    }

    private fun clear() { for (i in 0 until childCount) getChildAt(i).apply { translationX = 0f; translationY = 0f; scaleX = 1f; scaleY = 1f } }

    /** Let go: past the line the count is the new one, short of it the old; the rest of the way runs by itself (iOS finish/cancel). */
    private fun settle(finish: Boolean) {
        settling = ValueAnimator.ofFloat(progress, if (finish) 1f else 0f).apply {
            duration = 250
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener { show(it.animatedValue as Float) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) {
                    if (finish) columns = to
                    to = 0; settling = null
                    relay(columns)
                }
            })
            start()
        }
    }

    companion object { val STEPS = listOf(1, 2, 3, 5, 8) }   // iOS MTTileGrid.columnSteps
}

/**
 * THE SHEET THAT RISES HALF AND IS PULLED WHOLE (iOS presentationDetents [.medium, .large]): a pull up grows it before its
 * grid scrolls; a pull down from the grid's top lowers it, and let go low it closes.
 */
private class PullSheet(c: Context, private val grid: GridView, private val onGone: () -> Unit) : FrameLayout(c) {
    var low = 0
    var high = 0
    private var downY = 0f
    private var startH = 0
    private var pulling = false
    private val slop = ViewConfiguration.get(c).scaledTouchSlop
    fun setH(h: Int) { layoutParams.height = h; requestLayout() }
    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { downY = e.rawY; startH = height; pulling = false }
            MotionEvent.ACTION_MOVE -> {
                if (1 < e.pointerCount) return false   // two fingers are the grid's pinch, never the sheet's pull
                val dy = e.rawY - downY
                val up = dy < 0 && height < high
                val down = 0 < dy && !grid.canScrollVertically(-1)
                if (slop < abs(dy) && (up || down)) { pulling = true; downY = e.rawY; startH = height; return true }
            }
        }
        return false
    }
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_MOVE -> if (pulling) setH((startH - (e.rawY - downY)).toInt().coerceIn(0, high))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (pulling) { pulling = false; settle() }
        }
        return true
    }
    private fun settle() {
        val h = height
        val to = if (h < low * 2 / 3) 0 else if (h < (low + high) / 2) low else high
        ValueAnimator.ofInt(h, to).apply {
            duration = 220
            addUpdateListener { setH(it.animatedValue as Int) }
            if (to == 0) addListener(object : android.animation.AnimatorListenerAdapter() { override fun onAnimationEnd(a: android.animation.Animator) { onGone() } })
        }.start()
    }
}

/**
 * THE GALLERY OF THE COMPOSE ROW (iOS MTGalleryPick, MontanaMedia 2734-2828; MontanaConversation 2114-2131): the phone's own
 * latest pictures, newest first, three in a row to begin with (the pinch: 1, 2, 3, 5, 8 — TileGrid), the camera the first tile; chosen one at a time, as many as the
 * person wants (iOS 1e46c25e, the author's word 23.10 20:5x: «mass choice, the order of choosing is the order of sending, without a
 * limit» — the wire folds a pick into groups of ten by itself, MediaGroup), the circle in the platform's tint with the number of
 * the choice. At the foot: the way back, and «All photos» — the system's own picker with its albums — or, once something is
 * chosen, «Add N photos». What is chosen is never sent from here: it waits above the
 * field (the conversation's staging), and the field's send key sends it with the words as one group.
 */
fun galleryPick(act: MainActivity, onPick: (List<Uri>) -> Unit, onCamera: () -> Unit, onAll: () -> Unit) {
    val c: Context = act
    // UNDER LIMITED ACCESS THE GALLERY IS THE WHOLE LIBRARY AT ONCE (iOS openGallery, MontanaConversation.swift:3839-3849, the
    // author's word 24.09, atom ea8f63c10a16): the row's own page would show only the few pictures allowed; the system's picker asks
    // no permission and opens the whole library clean. Every other state keeps the row's page with its camera tile.
    if (Library.partial(c)) { android.util.Log.d("Montana", "gallery_open limited: the whole library at once"); onAll(); return }
    val chosen = ArrayList<Long>()
    var items: List<LibraryItem> = emptyList()
    lateinit var close: () -> Unit
    lateinit var drawFoot: () -> Unit
    val grid = TileGrid(c).apply {
        numColumns = columns
        horizontalSpacing = c.dp(2); verticalSpacing = c.dp(2)
        stretchMode = GridView.STRETCH_COLUMN_WIDTH
        selector = ColorDrawable(Color.TRANSPARENT)
        isVerticalScrollBarEnabled = false
        clipToPadding = false
    }
    val adapter = object : BaseAdapter() {
        override fun getCount() = items.size + 1
        override fun getItem(p: Int): Any = p
        override fun getItemId(p: Int) = p.toLong()
        override fun getViewTypeCount() = 2
        override fun getItemViewType(p: Int) = if (p == 0) 0 else 1
        override fun getView(p: Int, v: View?, parent: ViewGroup): View {
            if (p == 0) return v ?: CameraTile(c)
            val tile = (v as? PickTile) ?: PickTile(c)
            val item = items[p - 1]
            tile.bind(item, chosen.indexOf(item.id))
            return tile
        }
    }
    grid.adapter = adapter
    grid.setOnItemClickListener { _, _, p, _ ->
        if (p == 0) { close(); onCamera(); return@setOnItemClickListener }
        val id = items[p - 1].id
        // one at a time; a second touch takes the picture back out of the pick (iOS toggle)
        if (!chosen.remove(id)) chosen.add(id)
        adapter.notifyDataSetChanged()
        drawFoot()
    }
    // THE DRAG'S RANGE (iOS MTTileGrid.applyRange): from the circle the drag began on to the tile under the finger, every
    // tile takes the start tile's new state; a tile that leaves the range goes back to what it was before the drag.
    var dragStart = -1
    var dragMode = true
    var dragBase: List<Long> = emptyList()
    grid.fixed = { it == 0 }   // the camera
    grid.onDragTo = drag@{ p ->
        val a = dragStart; val b = p - 1
        if (a !in items.indices || b !in items.indices) return@drag
        val range = (minOf(a, b)..maxOf(a, b)).map { items[it].id }
        val next = ArrayList(dragBase)
        if (dragMode) { for (x in range) if (x !in next) next.add(x) } else next.removeAll(range.toSet())
        if (next != chosen) { chosen.clear(); chosen.addAll(next); adapter.notifyDataSetChanged(); drawFoot() }
    }
    grid.onDragBegin = { p ->
        dragStart = p - 1
        if (dragStart in items.indices) {
            dragMode = items[dragStart].id !in chosen
            dragBase = ArrayList(chosen)
            grid.onDragTo?.invoke(p)
        }
    }
    val note = c.text(c.getString(R.string.gp_no_access), 15f, MT.gray, center = true).apply { visibility = View.GONE }
    val spinner = ProgressBar(c)
    val glyph = Color.rgb(204, 204, 204)   // iOS MontanaOctagon.barGlyph
    val back = FrameLayout(c).apply {
        background = c.glassPlate(oval = true); contentDescription = c.getString(R.string.back)
        addView(c.icon(R.drawable.ic_arrow_back_ios_new, glyph), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
        pressable { close() }
    }
    val action = c.text("", 16f, Color.WHITE).apply { gravity = Gravity.CENTER; setPadding(c.dp(20), 0, c.dp(20), 0) }
    drawFoot = {
        if (chosen.isEmpty()) {
            action.text = c.getString(R.string.cm_all); action.setTextColor(Color.WHITE)
            action.background = c.glassPlate().apply { cornerRadius = c.dp(22).toFloat() }
            action.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        } else {
            action.text = c.resources.getQuantityString(R.plurals.gp_add, chosen.size, chosen.size); action.setTextColor(Color.BLACK)
            action.background = c.rounded(Color.WHITE, 22)
            action.typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
    }
    action.pressable {
        if (chosen.isEmpty()) { close(); onAll() }
        else {
            val picked = chosen.mapNotNull { id -> items.firstOrNull { it.id == id }?.uri }
            close(); onPick(picked)
        }
    }
    drawFoot()
    val foot = FrameLayout(c).apply {
        addView(back, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.START or Gravity.CENTER_VERTICAL))
        addView(action, FrameLayout.LayoutParams(WRAP, c.dp(44), Gravity.END or Gravity.CENTER_VERTICAL))
        setPadding(c.dp(16), 0, c.dp(16), c.dp(10))
    }
    lateinit var sheet: PullSheet
    sheet = PullSheet(c, grid) { close() }.apply {
        background = GradientDrawable().apply {
            setColor(Color.BLACK); val r = c.dp(12).toFloat(); cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
        }
        clipToOutline = true
        addView(grid, FrameLayout.LayoutParams(MATCH, MATCH).apply { topMargin = c.dp(8) })
        addView(spinner, FrameLayout.LayoutParams(c.dp(36), c.dp(36), Gravity.CENTER))
        addView(note, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.CENTER))
        addView(foot, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
    }
    val root = FrameLayout(c).apply {
        setBackgroundColor(Color.argb(102, 0, 0, 0))
        setOnClickListener { close() }   // the dim above the sheet lets it go, as the platform's sheet
        addView(sheet, FrameLayout.LayoutParams(MATCH, 0, Gravity.BOTTOM))
        sheet.isClickable = true
        setOnApplyWindowInsetsListener { _, ins ->
            val b = ins.getInsets(WindowInsets.Type.systemBars())
            foot.setPadding(c.dp(16), 0, c.dp(16), c.dp(10) + b.bottom)
            grid.setPadding(0, 0, 0, c.dp(64) + b.bottom)
            sheet.high = height - b.top - c.dp(10)
            ins
        }
    }
    close = act.overlay(root)
    root.post {
        root.requestApplyInsets()
        sheet.low = (root.height * 0.55f).toInt()
        if (sheet.high <= 0) sheet.high = root.height - c.dp(40)
        sheet.setH(sheet.low)
    }
    fun load() {
        // A WARM LIBRARY SHOWS AT ONCE (iOS RecentMedia.assets, atom 1cf77b0a8360): what a prior warm already found
        // stands in the grid before this very read returns, instead of a spinner over nothing a second time.
        Library.cachedNow()?.let { items = it; spinner.visibility = View.GONE; adapter.notifyDataSetChanged() }
        act.background {
            val got = if (Library.allowed(c)) Library.recent(c) else emptyList()
            act.onMain {
                items = got
                spinner.visibility = View.GONE
                note.visibility = if (Library.allowed(c)) View.GONE else View.VISIBLE   // only a refusal is said in words (iOS)
                adapter.notifyDataSetChanged()
            }
        }
    }
    if (Library.allowed(c)) load() else act.askMedia { load() }
}

/** THE STAGED PICTURE'S FACE (iOS MTLetterThumb.plate for the plate above the field): small, decoded once; a film's first frame. */
internal fun stagedFace(c: Context, p: Media.Picked): Bitmap? = runCatching {
    when (p.kind) {
        "img" -> {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(p.bytes, 0, p.bytes.size, o)
            var s = 1
            while (240 <= maxOf(o.outWidth, o.outHeight) / (s * 2)) s *= 2
            BitmapFactory.decodeByteArray(p.bytes, 0, p.bytes.size, BitmapFactory.Options().apply { inSampleSize = s })
        }
        "vid" -> {
            val f = java.io.File(c.cacheDir, "staged-face." + p.ext).apply { writeBytes(p.bytes) }
            val r = android.media.MediaMetadataRetriever()
            try { r.setDataSource(f.path); r.frameAtTime?.let { b -> Bitmap.createScaledBitmap(b, 240, maxOf(1, 240 * b.height / maxOf(1, b.width)), true) } }
            finally { r.release(); f.delete() }
        }
        else -> null
    }
}.getOrNull()
