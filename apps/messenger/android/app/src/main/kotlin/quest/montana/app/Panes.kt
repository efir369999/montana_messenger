package quest.montana.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout

// ─────────────────────────── the pages under the bar that wait for the network ───────────────────────────

/** A page with nothing in it yet: its words at the centre, as each iOS page says it. */
private fun emptyPane(c: Context, words: Int, above: View? = null): View = FrameLayout(c).apply {
    addView(c.vstack {
        if (above != null) { addView(above, lp(c.dp(56), c.dp(56))); gap(12) }
        addView(c.text(c.getString(words), if (above != null) 15f else 17f, MT.gray, center = true))
    }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
}

/** ONE MOMENT OF THE GALLERY (iOS MTMoment): a photo or a video lying in a conversation — the file, where it lies, when. */
private class Moment(val file: java.io.File, val photo: Boolean, val ref: String, val mid: String, val at: Long)

/** THE MOMENTS (iOS ChatStore.mediaLibrary): every picture and film of every conversation whose file is here, oldest first. */
private fun moments(): List<Moment> = Book.all().flatMap { ch ->
    ch.msgs.mapNotNull { m ->
        if (!m.text.startsWith(Marks.MEDIA)) return@mapNotNull null
        val man = m.meta?.let { runCatching { org.json.JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
        val kind = man?.optString("k")
        val f = m.file?.let { java.io.File(it) }?.takeIf { it.exists() }
        // a round note and a sticker are letters of their own kind, not moments of the library
        if (f == null || (kind != "img" && kind != "vid") || man.optBoolean("r") || man.optString("n") == Stickers.CARD) null
        else Moment(f, kind == "img", ch.ref, m.mid, m.at)
    }
}.sortedBy { it.at }

/** The tiles' small drawings, decoded off the frame once and kept by their size (iOS mtTileSharp, MontanaCaches): one cache for the
 *  gallery and the correspondent's page, by the file's path. */
val tileCache: android.util.LruCache<String, android.graphics.Bitmap> = Caches.kept("tiles", object : android.util.LruCache<String, android.graphics.Bitmap>(24 * 1024 * 1024) {
    override fun sizeOf(key: String, value: android.graphics.Bitmap) = value.byteCount
})
val tileWork = java.util.concurrent.Executors.newSingleThreadExecutor()

/**
 * THE GALLERY (iOS GalleryTabView, the author's word 25.09): every moment of every conversation in the order the platform's photos
 * keep — the days oldest to newest, each day a header and its tiles three to a row, the newest at the bottom, the page opened at
 * its end. A tile is the file's small drawing, a film wears its glyph; a tap opens the moment in the viewer (the chat's own,
 * openMedia); a hold opens its deeds — show in chat, forward. «No photos yet» while there is none. iOS's stories and the plus
 * that adds one come with the stories.
 */
fun galleryPane(act: MainActivity): View {
    val c: Context = act
    val column = c.vstack(Gravity.NO_GRAVITY)
    val empty = emptyPane(c, R.string.no_photos, PetalsGlyph(c))
    // THE SWIPE AMONG THE GALLERY'S OWN PHOTOS (iOS MTMomentsViewer/DocPreviewQL, MontanaFeeds.swift:2706-2772 at 2155, the
    // author's word 25.09: "take the feed out of the gallery; viewing as native as it gets"): the full list a tile opens
    // among, kept across refills so a tap always pages the gallery as it stands, not the frame it was built in.
    var all: List<Moment> = emptyList()
    // THREE TO A ROW, AS THE WALL'S (iOS GalleryTabView.columns, MontanaFeeds.swift:903, 929 at 2155): the page has no pinch --
    // the grid that changes its columns under two fingers is the attachment picker's (MTTileGrid, MontanaMedia.swift:2454-2576)
    val columns = 3
    val scroll = android.widget.ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(column, lp()); gap(120) })   // the floating player's room at the foot
    }
    fun tile(m: Moment): View = FrameLayout(c).apply {
        setBackgroundColor(Color.rgb(41, 41, 41))
        val pic = android.widget.ImageView(c).apply { scaleType = android.widget.ImageView.ScaleType.CENTER_CROP }
        addView(pic, FrameLayout.LayoutParams(MATCH, MATCH))
        if (!m.photo) addView(c.icon(R.drawable.ic_peer_video, Color.WHITE, 12), FrameLayout.LayoutParams(c.dp(12), c.dp(12), Gravity.BOTTOM or Gravity.START).apply { setMargins(c.dp(6), 0, 0, c.dp(6)) })
        val key = m.file.path
        tileCache.get(key)?.let { pic.setImageBitmap(it) } ?: tileWork.execute {
            val b = Media.preview(c, m.file, if (m.photo) "img" else "vid", 360) ?: return@execute
            tileCache.put(key, b)
            post { pic.setImageBitmap(b) }
        }
        // THE SWIPE BETWEEN MOMENTS (iOS MTMomentsViewer over QLPreviewController, MontanaFeeds.swift:2706-2772 at 2155):
        // a photo opens among every photo of the gallery, so the finger pages across conversations as the platform's own
        // viewer does; a film still opens alone -- the system's own player here carries no such list of its own (gap: the
        // iPhone's one viewer pages photos and films together, Android pages photos only).
        pressable { if (m.photo) openPictures(act, m.file, all.filter { it.photo }.map { it.file }) else openMedia(act, m.file, "vid") }
        setOnLongClickListener {
            holdMenu(act, this, listOf(
                Deed(R.string.gl_show_in_chat, R.drawable.ic_bar_chats) { act.push { close -> conversationPage(act, m.ref, close, jump = m.mid) } },
                Deed(R.string.ld_forward, R.drawable.ic_reply) {
                    Book.chat(m.ref)?.msgs?.firstOrNull { it.mid == m.mid }?.let { letter ->
                        act.push { close -> forwardPage(act, m.ref, listOf(letter), close) { to -> close(); act.push { c2 -> conversationPage(act, to, c2) } } }
                    }
                }))
            true
        }
    }
    fun dayWords(at: Long): String {
        if (android.text.format.DateUtils.isToday(at)) return c.getString(R.string.today)
        if (android.text.format.DateUtils.isToday(at + 86_400_000L)) return c.getString(R.string.gl_yesterday)
        return android.text.format.DateUtils.formatDateTime(c, at, android.text.format.DateUtils.FORMAT_SHOW_DATE)
    }
    fun fill() {
        column.removeAllViews()
        all = moments()
        empty.visibility = if (all.isEmpty()) View.VISIBLE else View.GONE
        val cal = java.util.Calendar.getInstance()
        var day = -1L
        var row: android.widget.LinearLayout? = null
        var inRow = 0
        fun closeRow() { row?.let { r -> while (inRow < columns) { r.addView(View(c), lp(0, c.dp(1), 1f)); inRow++ } } }
        for (m in all) {
            cal.timeInMillis = m.at
            val d = cal.get(java.util.Calendar.YEAR) * 1000L + cal.get(java.util.Calendar.DAY_OF_YEAR)
            if (d != day) {
                closeRow(); row = null
                day = d
                column.addView(c.text(dayWords(m.at), 20f, Color.WHITE, bold = true).apply { setPadding(c.dp(16), c.dp(18), c.dp(16), c.dp(6)) }, lp())
            }
            if (row == null || inRow == columns) {
                closeRow()
                row = c.hstack { }
                inRow = 0
                column.addView(row, lp().apply { bottomMargin = c.dp(2) })
            }
            // a tile is a square, a third of the width less the hairlines between
            val side = (c.resources.displayMetrics.widthPixels - c.dp(2 * (columns - 1))) / columns
            row!!.addView(tile(m), lp(0, side, 1f).apply { if (inRow > 0) marginStart = c.dp(2) })
            inRow++
        }
        closeRow()
        scroll.post { scroll.scrollTo(0, scroll.getChildAt(0)?.height ?: 0) }   // opened at its end, the newest at the bottom
    }
    var dirty = true
    val again: () -> Unit = { dirty = true; if (scroll.isShown) act.onMain { if (dirty) { dirty = false; fill() } } }
    return FrameLayout(c).apply {
        addView(scroll, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(empty, FrameLayout.LayoutParams(MATCH, MATCH))
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { Book.listen(again) }
            override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again) }
        })
        // the page is drawn when it is looked at: a gallery built under every letter of every chat would be work for nobody
        viewTreeObserver.addOnGlobalLayoutListener { if (isShown && dirty) { dirty = false; fill() } }
    }
}

/** The system's own photos glyph (iOS MontanaPetalsGlyph): eight petals of the spectrum around one centre. */
class PetalsGlyph(c: Context) : View(c) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    override fun onDraw(canvas: Canvas) {
        val s = minOf(width, height).toFloat()
        val cx = width / 2f; val cy = height / 2f
        val petal = RectF(cx - s * 0.15f, cy - s * 0.19f - s * 0.31f, cx + s * 0.15f, cy - s * 0.19f + s * 0.31f)
        for (i in 0 until 8) {
            paint.color = Color.HSVToColor((0.85f * 255).toInt(), floatArrayOf(i * 45f, 0.72f, 0.96f))
            canvas.save()
            canvas.rotate(i * 45f, cx, cy)
            canvas.drawOval(petal, paint)
            canvas.restore()
        }
    }
}
