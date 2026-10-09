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
        return out.sortedByDescending { it.at }.take(limit)
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
 * latest pictures, newest first, three in a row, the camera the first tile; chosen one at a time, at most ten, the circle in the
 * platform's tint with the number of the choice. At the foot: the way back, and «All photos» — the system's own picker with its
 * albums and its ten — or, once something is chosen, «Add N photos». What is chosen is never sent from here: it waits above the
 * field (the conversation's staging), and the field's send key sends it with the words as one group.
 */
fun galleryPick(act: MainActivity, onPick: (List<Uri>) -> Unit, onCamera: () -> Unit, onAll: () -> Unit) {
    val c: Context = act
    val limit = MediaGroup.CEILING
    val chosen = ArrayList<Long>()
    var items: List<LibraryItem> = emptyList()
    lateinit var close: () -> Unit
    lateinit var drawFoot: () -> Unit
    val grid = GridView(c).apply {
        numColumns = 3
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
        // one at a time, up to the ceiling; a second touch takes the picture back out of the pick (iOS toggle)
        if (!chosen.remove(id) && chosen.size < limit) chosen.add(id)
        adapter.notifyDataSetChanged()
        drawFoot()
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
