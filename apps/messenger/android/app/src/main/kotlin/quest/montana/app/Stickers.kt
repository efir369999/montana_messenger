package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * STICKERS (iOS MontanaSticker / MontanaStickerScreens), in the two shapes every build already draws without a bubble:
 *   · a glyph — the invisible sticker mark and one emoji (iOS sendSticker: stickerMark + e), drawn large;
 *   · a picture of my own set — an ordinary picture letter whose manifest carries the card sticker's name «montana-card»
 *     (iOS sendStickerFile: kind img, docName MontanaCardPlate.stickerName), drawn in its own square without a bubble.
 * MY OWN SET (iOS MontanaStickerBook): the pictures lie in the app's private storage, the order in the defaults; a picture is
 * named by its own bytes, so the same sticker is kept once and, used again, moves to the front; the ceiling is a person's set.
 * Not yet here: the sets of other people and the «SP:» words that carry them (an older build buries them unread, and so does
 * this one), and the platform's subject cut — iOS lifts the subject with Vision; Android has no such native road.
 */
object Stickers {
    /** The card sticker's name in a picture's manifest (iOS MontanaCardPlate.stickerName): every build draws it bare. */
    const val CARD = "montana-card"
    private const val SHELF = "stickers.mine"
    private const val CEILING = 120                  // iOS MontanaStickerBook.ceiling
    private const val SIDE = 512                     // iOS MontanaStickerCut.side
    private const val LOOK = 192                     // iOS MTStickerLook.side: the glyph's 64, three times over
    /** The glyphs the panel offers as stickers of their own (iOS the emoji panel's sticker road). */
    private val GLYPHS = listOf("❤️", "😂", "👍", "🔥", "🥰", "😢", "😮", "🙏", "🎉", "😎", "🤔", "👋", "💯", "😘", "🤝", "✨")

    private fun dir(c: Context) = File(c.filesDir, "stickers").apply { mkdirs() }
    /** The person forgotten: their stickers leave with them (Book.wipe); the list of names lived in the person's preferences. */
    fun wipe(c: Context) = File(c.filesDir, "stickers").deleteRecursively()
    fun file(c: Context, name: String) = File(dir(c), name)
    fun names(c: Context): List<String> = Prefs.str(SHELF, "").split('\n').filter { it.isNotEmpty() && file(c, it).exists() }
    private fun keep(list: List<String>) = Prefs.setStr(SHELF, list.joinToString("\n"))

    /** A STICKER USED IS A STICKER KEPT, AND KEPT ONCE (iOS add(png:)): named by its bytes; known — it moves to the front. */
    fun add(c: Context, bytes: ByteArray, ext: String): String {
        val name = "stk_" + Wire.hex(Wire.sha(bytes)).take(16) + "." + ext
        val f = file(c, name)
        if (!f.exists()) f.writeBytes(bytes)
        val list = listOf(name) + names(c).filter { it != name }
        list.drop(CEILING).forEach { file(c, it).delete() }   // the oldest leaves with its file
        keep(list.take(CEILING))
        return name
    }
    fun forget(c: Context, name: String) { keep(names(c).filter { it != name }); file(c, name).delete() }

    // ── what a letter is ──

    private fun manifestOf(m: Msg): JSONObject? = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
    private fun isPicture(m: Msg) = m.text.startsWith(Marks.MEDIA) && manifestOf(m)?.optString("n") == CARD
    /** A sticker stands without a bubble: a glyph sticker, or a picture that says it is the card sticker. */
    fun bare(m: Msg): Boolean = m.text.startsWith(Marks.STICKER) || isPicture(m)

    /** The sticker's own face inside the letter's column; false — not a sticker, the bubble draws it as ever. */
    fun body(c: Context, m: Msg, into: LinearLayout): Boolean {
        if (m.text.startsWith(Marks.STICKER)) {
            // USER-DATA: the sticker's glyph
            into.addView(c.text(m.text.removePrefix(Marks.STICKER), 96f).apply { includeFontPadding = false }, LinearLayout.LayoutParams(WRAP, WRAP))
            return true
        }
        if (!isPicture(m)) return false
        val f = m.file?.let { File(it) }?.takeIf { it.exists() }
        val pic = f?.let { Media.preview(c, it, "img", SIDE) } ?: Media.thumbOf(manifestOf(m))
        val box = c.dp(LOOK)
        val (w, h) = if (pic == null) box to box else {
            val k = box.toFloat() / maxOf(pic.width, pic.height)
            (pic.width * k).toInt().coerceAtLeast(1) to (pic.height * k).toInt().coerceAtLeast(1)
        }
        into.addView(FrameLayout(c).apply {
            addView(ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER; pic?.let { setImageBitmap(it) } }, FrameLayout.LayoutParams(w, h))
            if (f == null) addView(android.widget.ProgressBar(c), FrameLayout.LayoutParams(c.dp(30), c.dp(30), Gravity.CENTER))
        }, LinearLayout.LayoutParams(WRAP, WRAP).apply { bottomMargin = c.dp(2) })
        if (m.state == -1) into.addView(c.text(c.getString(R.string.media_failed), 12f, SysColor.red))
        return true
    }

    // ── leaving ──

    /** A glyph sticker: one letter of the mark and the emoji (iOS sendSticker). */
    fun sendGlyph(ref: String, e: String) {
        val text = Marks.STICKER + e
        if (Groups.isKey(ref)) { Groups.send(ref, text, null, null); return }   // a group's letter rides the group's carrier
        val mid = Marks.mintMid()
        Book.edit(ref) { it.msgs.add(Msg(mid, text, true, Marks.birthMs(mid) ?: System.currentTimeMillis())) }
        Post.send(ref, mid, text)
    }

    /** A picture of my set leaves by the picture road with the card sticker's name, and moves to the front of the set. */
    fun sendPicture(c: Context, ref: String, name: String) {
        val f = file(c, name).takeIf { it.exists() } ?: return
        val bytes = f.readBytes()
        add(c, bytes, f.extension)
        Thread { Media.send(c, ref, Media.Picked(bytes, "img", f.extension, CARD), "") }.start()
    }

    /** A LETTER'S OWN CARD STICKER CAN BE RE-CUT (iOS onEditSticker: MontanaMessageMenu 474-476, MontanaConversation 2251-2254):
     * Android narrows this to a letter of mine, with its picture already on this phone — the other person's set carries no
     * passport yet (the header above: «not yet here»). */
    fun editable(m: Msg): Boolean = m.mine && isPicture(m) && m.file != null

    /** EDIT STICKER (iOS MontanaStickerEditor via the .stickerEdit sheet, MontanaConversation 2139-2149): the letter's own
     * picture opens in the editor; what the check keeps is a NEW sticker of my set, sent at once — the letter it came from
     * is never touched. */
    fun editFromLetter(act: MainActivity, ref: String, m: Msg) {
        val c: Context = act
        val f = m.file?.let { File(it) }?.takeIf { it.exists() } ?: return
        act.background {
            val b = BitmapFactory.decodeFile(f.path)
            if (b != null) act.onMain { editor(act, b) { bytes, ext -> val n = add(c, bytes, ext); sendPicture(c, ref, n) } }
        }
    }

    /** Light or not a sticker (iOS MontanaStickerCut.encode, HEIC 0.8): the platform's own light format with transparency. */
    private fun encode(b: Bitmap): Pair<ByteArray, String> {
        val out = ByteArrayOutputStream()
        @Suppress("DEPRECATION")
        val fmt = if (Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
        return if (b.compress(fmt, 80, out) && out.size() > 0) out.toByteArray() to "webp"
        else ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray() to "png"
    }

    // ── the panel ──

    /**
     * THE STICKER PANEL (iOS the emoji panel's sticker strip + MontanaStickerSetPage): the glyphs in a row, my set four in a
     * row under them. A tap sends, a hold asks to drop one of my own, the plus makes one from a photo. Our cross at the left.
     */
    fun panel(act: MainActivity, ref: String) {
        val c: Context = act
        lateinit var close: () -> Unit
        val grid = GridLayout(c).apply { columnCount = 4; setPadding(c.dp(10), c.dp(6), c.dp(10), c.dp(16)) }
        val empty = c.text(c.getString(R.string.stickers_empty), 15f, MT.gray, center = true).apply { setPadding(c.dp(24), c.dp(28), c.dp(24), c.dp(28)) }
        fun fill() {
            grid.removeAllViews()
            val list = names(c)
            empty.visibility = if (list.isEmpty()) View.VISIBLE else View.GONE
            val cell = (c.resources.displayMetrics.widthPixels - c.dp(20)) / 4
            for (n in list) grid.addView(ImageView(c).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
                setPadding(c.dp(8), c.dp(8), c.dp(8), c.dp(8))
                act.background { BitmapFactory.decodeFile(file(c, n).path, BitmapFactory.Options().apply { inSampleSize = 2 })?.let { b -> act.onMain { setImageBitmap(b) } } }
                pressable { close(); sendPicture(c, ref, n) }
                setOnLongClickListener {
                    AlertDialog.Builder(c).setMessage(R.string.sticker_delete_q)
                        .setPositiveButton(R.string.delete) { _, _ -> forget(c, n); fill() }
                        .setNegativeButton(R.string.cancel, null).show()
                    true
                }
            }, GridLayout.LayoutParams().apply { width = cell; height = cell })
        }
        val glyphs = HorizontalScrollView(c).apply {
            isHorizontalScrollBarEnabled = false
            addView(c.hstack {
                setPadding(c.dp(10), 0, c.dp(10), 0)
                for (e in GLYPHS) addView(c.text(e, 34f).apply { setPadding(c.dp(8), c.dp(6), c.dp(8), c.dp(6)); pressable { close(); sendGlyph(ref, e) } })   // USER-DATA: none, the glyphs are ours
            })
        }
        fun mark(res: Int, label: Int, onTap: () -> Unit) = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(label)
            addView(c.icon(res, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
            pressable(onTap)
        }
        val sheet = c.vstack(Gravity.NO_GRAVITY) {
            background = c.rounded(Color.rgb(20, 20, 22), 22)
            isClickable = true
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(6))
                addView(mark(R.drawable.ic_close, R.string.cancel) { close() }, lp(c.dp(40), c.dp(40)))
                addView(c.text(c.getString(R.string.stickers), 17f, bold = true, center = true), lp(0, WRAP, 1f))
                // THE PLUS MAKES ONE FROM A PHOTO (iOS MontanaStickerEditor): the system's picker, then the frame
                addView(mark(R.drawable.ic_plus, R.string.sticker_make) {
                    act.pickPhoto { uri -> if (uri != null) act.background { load(c, uri)?.let { b -> act.onMain { editor(act, b) { bytes, ext -> close(); fill(); val n = add(c, bytes, ext); sendPicture(c, ref, n) } } } } }
                }, lp(c.dp(40), c.dp(40)))
            }, lp())
            addView(glyphs, lp())
            addView(View(c).apply { setBackgroundColor(Color.argb(40, 255, 255, 255)) }, lp(MATCH, 1).apply { topMargin = c.dp(6) })
            addView(ScrollView(c).apply { addView(c.vstack(Gravity.NO_GRAVITY) { addView(empty, lp()); addView(grid, lp()) }) }, lp(MATCH, (c.resources.displayMetrics.heightPixels * 0.42).toInt()))
        }
        val page = FrameLayout(c).apply {
            setBackgroundColor(Color.argb(120, 0, 0, 0))
            isClickable = true
            setOnClickListener { close() }
            addView(sheet, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        }
        fill()
        close = act.overlay(page)
    }

    /** The picked photo, stood upright by its own EXIF turn and no larger than the frame needs. */
    private fun load(c: Context, uri: Uri): Bitmap? = runCatching {
        if (Build.VERSION.SDK_INT >= 28) android.graphics.ImageDecoder.decodeBitmap(android.graphics.ImageDecoder.createSource(c.contentResolver, uri)) { d, info, _ ->
            d.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
            val big = maxOf(info.size.width, info.size.height)
            if (big > 2048) d.setTargetSize(info.size.width * 2048 / big, info.size.height * 2048 / big)
        } else c.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = 2 }) }
    }.getOrNull()

    /**
     * THE STICKER EDITOR (iOS MontanaStickerEditor): the photo in a square frame, moved and scaled by the finger; what stands
     * in the frame is the sticker, on a transparent ground where the photo does not reach. The cross leaves, the check keeps.
     */
    private fun editor(act: MainActivity, image: Bitmap, onDone: (ByteArray, String) -> Unit) {
        val c: Context = act
        lateinit var close: () -> Unit
        val canvas = StickerCanvas(c, image)
        val page = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            addView(canvas, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(c.icon(R.drawable.ic_close, Color.WHITE).apply { setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12)); pressable { close() } },
                FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.TOP or Gravity.START).apply { setMargins(c.dp(8), c.dp(8), 0, 0) })
            addView(c.icon(R.drawable.ic_check, Color.WHITE).apply {
                setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
                pressable { val shot = canvas.render(SIDE); close(); act.background { val (b, ext) = encode(shot); act.onMain { onDone(b, ext) } } }
            }, FrameLayout.LayoutParams(c.dp(48), c.dp(48), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(8), c.dp(8), 0) })
        }
        close = act.overlay(page)
    }
}

/**
 * THE FRAME OVER THE PHOTO (iOS MTZoomPicture): the photo fits the square at first and may be scaled up to five times and
 * moved; unlike the face's crop it may stand smaller than the frame — the rest of the square is the sticker's air.
 */
private class StickerCanvas(ctx: Context, private val image: Bitmap) : View(ctx) {
    private var zoom = 1f
    private var panX = 0f
    private var panY = 0f
    private var side = 0f
    private var fit = 1f
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val dim = Paint().apply { color = Color.argb(153, 0, 0, 0) }
    private val air = Paint().apply { color = Color.rgb(36, 36, 38) }
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.argb(51, 255, 255, 255); strokeWidth = context.dp(1).toFloat().coerceAtLeast(1f) }
    private val scaler = ScaleGestureDetector(ctx, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean { zoom = (zoom * d.scaleFactor).coerceIn(1f, 5f); invalidate(); return true }
    })
    private var lastX = 0f
    private var lastY = 0f
    private var pointer = -1

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        side = (minOf(w, h) - context.dp(24)).toFloat().coerceAtLeast(context.dp(120).toFloat())
        fit = side / maxOf(image.width, image.height)
    }
    private fun frame() = RectF(width / 2f - side / 2, height / 2f - side / 2, width / 2f + side / 2, height / 2f + side / 2)
    /** Where the photo stands on the screen: centred in the frame, then scaled and moved by the finger. */
    private fun matrix(into: RectF, k: Float): Matrix = Matrix().apply {
        val s = fit * zoom * k
        postTranslate(-image.width / 2f, -image.height / 2f)
        postScale(s, s)
        postTranslate(into.centerX() + panX * k, into.centerY() + panY * k)
    }

    override fun onDraw(c: Canvas) {
        val f = frame()
        val round = Path().apply { addRoundRect(f, context.dp(20).toFloat(), context.dp(20).toFloat(), Path.Direction.CW) }
        c.save(); c.clipPath(round); c.drawRect(f, air); c.restore()
        c.drawBitmap(image, matrix(f, 1f), paint)
        c.save(); c.clipOutPath(round); c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dim); c.restore()
        c.drawPath(round, rim)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { pointer = e.getPointerId(0); lastX = e.x; lastY = e.y }
            MotionEvent.ACTION_POINTER_UP -> { pointer = -1 }
            MotionEvent.ACTION_MOVE -> {
                val i = e.findPointerIndex(pointer)
                if (i >= 0 && !scaler.isInProgress) {
                    panX += e.getX(i) - lastX; panY += e.getY(i) - lastY
                    val lim = side / 2 + fit * zoom * maxOf(image.width, image.height) / 2   // the photo never leaves the frame whole
                    panX = panX.coerceIn(-lim, lim); panY = panY.coerceIn(-lim, lim)
                    invalidate()
                }
                if (i >= 0) { lastX = e.getX(i); lastY = e.getY(i) } else { pointer = e.getPointerId(0); lastX = e.getX(0); lastY = e.getY(0) }
            }
        }
        return true
    }

    /** What stands in the frame, to the pixel, on a transparent square of `px` (iOS MTStickerCanvas.png). */
    fun render(px: Int): Bitmap {
        val out = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val k = px / side
        Canvas(out).drawBitmap(image, matrix(RectF(0f, 0f, px.toFloat(), px.toFloat()), k), paint)
        return out
    }
}
