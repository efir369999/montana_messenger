package quest.montana.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import java.io.File
import java.util.UUID

// ─────────────────────────── the ground of one conversation (iOS MTWallpaper, MTWallpaperPicker, MTWallpaperPreview) ───────────────────────────

/**
 * THE GROUND OF ONE CONVERSATION (iOS MTWallpaper): a ground chosen for a chat stands over the general one; where none is
 * chosen the chat wears the pages' own ground (iOS «Same as my page» — on Android the pages stand on the crest). A choice is
 * a drawn ground by its name, or a picture placed by the finger and kept as placed. One owner of the storage and the files.
 */
object ChatWall {
    /** MY PAGE'S GROUND (iOS MTWallpaper.page): kept as a chat's is, under this key; «General» is no ground (the crest). */
    const val PAGE = "*page"
    sealed class Choice {
        object General : Choice()
        data class Named(val name: String) : Choice()
        data class Photo(val file: String) : Choice()
    }
    /** The drawn grounds, seen not read: the names are for the voice that reads the screen aloud (iOS MTWallpaper.names). */
    val names = listOf(
        "gold" to R.string.wall_gold, "montana" to R.string.wall_montana,
        "default" to R.string.wall_default, "black" to R.string.wall_black, "dark" to R.string.wall_dark, "blue" to R.string.wall_blue,
        "sky" to R.string.wall_sky, "dusk" to R.string.wall_dusk, "water" to R.string.wall_water, "aurora" to R.string.wall_aurora,
        "burgundy" to R.string.wall_burgundy, "rose" to R.string.wall_rose, "forest" to R.string.wall_forest)
    /** THE ONE DEFAULT (iOS MTWallpaper.byDefault, the author's word 03.10): my page's ground is gold until I choose another. */
    const val BY_DEFAULT = "gold"

    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }

    fun choice(ref: String): Choice {
        val s = Prefs.str("chatWall.$ref", "")
        return when {
            s.startsWith("named:") -> Choice.Named(s.removePrefix("named:"))
            s.startsWith("photo:") -> Choice.Photo(s.removePrefix("photo:"))
            // nothing chosen for my page reads as the gold; «No background» chosen by hand is stored as «general» (iOS 182-193)
            s.isEmpty() && ref == PAGE -> Choice.Named(BY_DEFAULT)
            else -> Choice.General
        }
    }
    fun set(ref: String, c: Choice) {
        val old = (choice(ref) as? Choice.Photo)?.file
        when (c) {
            Choice.General -> if (ref == PAGE) Prefs.setStr("chatWall.$ref", "general") else Prefs.remove("chatWall.$ref")
            is Choice.Named -> Prefs.setStr("chatWall.$ref", "named:" + c.name)
            is Choice.Photo -> Prefs.setStr("chatWall.$ref", "photo:" + c.file)
        }
        if (old != null && old != (c as? Choice.Photo)?.file) File(folder(), old).delete()   // a picture no chat wears leaves
        val ls = synchronized(listeners) { listeners.toList() }
        MainThread.post { ls.forEach { it() } }
        if (ref == PAGE) Thread { PageGround.changed() }.start()   // my page's ground to every correspondent who reads it (iOS MTPageGround.changed)
    }
    /** Beside the faces, outside the media: the pictures grounds stand on. */
    fun folder(): File = File(Book.ctx.filesDir, "wallpapers").apply { mkdirs() }
    /** The placed picture, kept lossless as the preview showed it (iOS saveRendered: PNG). */
    fun keep(b: Bitmap): String? {
        val name = "wall_${UUID.randomUUID()}.png"
        return runCatching { File(folder(), name).outputStream().use { b.compress(Bitmap.CompressFormat.PNG, 100, it) }; name }.getOrNull()
    }
    fun image(file: String): Bitmap? = File(folder(), file).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
    fun forget(ref: String) = set(ref, Choice.General)
    /** The person forgotten: the pictures their chats and their page stood on leave with them (Book.wipe); the choices lived in the person's preferences. */
    fun wipe() = File(Book.ctx.filesDir, "wallpapers").deleteRecursively()
}

/**
 * ONE PAINT PER GROUND (iOS MTWallpaper.paint): the full screen and the thumbnail draw the very same drawable, so a ground
 * never looks one way in the chooser and another in the chat. Gradients as iOS lays them: stops, directions, the soft lights.
 */
class GroundPaint(private val c: Context, private val name: String) : Drawable() {
    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val logo: Bitmap? = if (name == "default") logoBitmap(c) else null
    // THE AUTHOR'S PICTURES, HIS FILES AS THEY CAME (iOS paint «montana», «burgundy», «gold»: scaledToFill, nothing drawn over them)
    private val picture: Bitmap? = PICTURES[name]?.let { picture(c, it) }
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    private fun rgb(r: Double, g: Double, b: Double, a: Double = 1.0) = Color.argb((a * 255).toInt(), (r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt())
    private fun linear(x0: Float, y0: Float, x1: Float, y1: Float, vararg colors: Int) = LinearGradient(x0, y0, x1, y1, colors, null, Shader.TileMode.CLAMP)
    private fun fill(canvas: Canvas, s: Shader) { p.shader = s; canvas.drawRect(bounds, p) }
    /** A soft light (iOS RadialGradient from a colour to clear): the radius in points, the centre in unit coordinates. */
    private fun light(canvas: Canvas, color: Int, cx: Float, cy: Float, radiusPt: Float) {
        val w = bounds.width().toFloat(); val h = bounds.height().toFloat()
        val r = c.dp(radiusPt).toFloat().coerceAtLeast(1f)
        fill(canvas, RadialGradient(cx * w, cy * h, r, intArrayOf(color, color and 0x00FFFFFF), null, Shader.TileMode.CLAMP))
    }

    override fun draw(canvas: Canvas) {
        val w = bounds.width().toFloat(); val h = bounds.height().toFloat()
        picture?.let { b ->
            // the picture fills the ground edge to edge, cut at its centre (scaledToFill)
            val k = maxOf(w / b.width, h / b.height)
            val sw = w / k; val sh = h / k
            val left = (b.width - sw) / 2f; val top = (b.height - sh) / 2f
            canvas.drawBitmap(b, Rect(left.toInt(), top.toInt(), (left + sw).toInt(), (top + sh).toInt()), bounds, bitmapPaint)
            return
        }
        when (name) {
            "black" -> canvas.drawColor(Color.BLACK)
            "dark" -> fill(canvas, dark(h))
            "blue" -> fill(canvas, linear(0f, 0f, 0f, h, rgb(0.10, 0.20, 0.32), rgb(0.05, 0.10, 0.18)))
            "sky" -> {
                fill(canvas, linear(0f, 0f, 0f, h, rgb(0.36, 0.62, 0.86), rgb(0.74, 0.86, 0.94)))
                light(canvas, rgb(1.0, 1.0, 1.0, 0.55), 0.7f, 0.22f, 320f)
            }
            "dusk" -> {
                fill(canvas, linear(0f, 0f, 0f, h, rgb(0.13, 0.12, 0.28), rgb(0.58, 0.32, 0.36), rgb(0.95, 0.62, 0.36)))
                light(canvas, rgb(1.0, 0.85, 0.60, 0.7), 0.5f, 0.86f, 260f)
            }
            "water" -> {
                fill(canvas, linear(0f, 0f, w, h, rgb(0.62, 0.80, 0.84), rgb(0.90, 0.93, 0.94), rgb(0.55, 0.72, 0.80)))
                // iOS AngularGradient in soft light: the platform's own sweep, laid thin
                p.alpha = 110
                fill(canvas, SweepGradient(0.4f * w, 0.4f * h, intArrayOf(rgb(1.0, 1.0, 1.0, 0.35), Color.TRANSPARENT,
                    rgb(0.70, 0.85, 0.90, 0.4), Color.TRANSPARENT, rgb(1.0, 1.0, 1.0, 0.35)), null))
                p.alpha = 255
            }
            "aurora" -> {
                fill(canvas, linear(0f, 0f, 0f, h, rgb(0.04, 0.04, 0.12), rgb(0.08, 0.10, 0.24)))
                light(canvas, rgb(0.25, 0.85, 0.75, 0.65), 0.32f, 0.38f, 280f)
                light(canvas, rgb(0.55, 0.35, 0.95, 0.6), 0.72f, 0.60f, 300f)
            }
            "rose" -> {
                fill(canvas, linear(0f, 0f, 0f, h, rgb(0.42, 0.10, 0.36), rgb(0.95, 0.35, 0.62)))
                light(canvas, rgb(1.0, 0.75, 0.85, 0.5), 0.3f, 0.75f, 280f)
            }
            "forest" -> {
                fill(canvas, linear(0f, 0f, w, h, rgb(0.05, 0.18, 0.16), rgb(0.12, 0.36, 0.30), rgb(0.06, 0.14, 0.14)))
                light(canvas, rgb(0.55, 0.85, 0.60, 0.28), 0.65f, 0.3f, 260f)
            }
            else -> {   // «default»: the dark gradient and the faint logo pattern (iOS MontanaChatGround)
                fill(canvas, dark(h))
                logo?.let { pattern(canvas, it) }
            }
        }
        p.shader = null
    }
    private fun dark(h: Float) = linear(0f, 0f, 0f, h, rgb(0.05, 0.05, 0.07), rgb(0.09, 0.08, 0.06), rgb(0.13, 0.10, 0.05))
    /** iOS MontanaLogoPattern: a cell of 140, the logo at three tenths of it, every other row shifted by half, at 3.5 %. */
    private fun pattern(canvas: Canvas, logo: Bitmap) {
        val tile = c.dp(140f).toFloat(); val side = tile * 0.3f
        val lp = Paint(Paint.FILTER_BITMAP_FLAG).apply { alpha = (0.035 * 255).toInt() }
        val cols = (bounds.width() / tile).toInt() + 2; val rows = (bounds.height() / tile).toInt() + 2
        for (r in 0 until rows) for (col in 0 until cols) {
            val x = bounds.left + col * tile + (if (r % 2 == 0) 0f else tile / 2) + (tile - side) / 2
            val y = bounds.top + r * tile + (tile - side) / 2
            canvas.drawBitmap(logo, null, RectF(x, y, x + side, y + side), lp)
        }
    }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(cf: ColorFilter?) {}
    @Deprecated("the platform's own") override fun getOpacity() = PixelFormat.OPAQUE

    companion object {
        private var kept: Bitmap? = null
        fun logoBitmap(c: Context): Bitmap? = kept ?: runCatching { BitmapFactory.decodeResource(c.resources, R.drawable.logo) }.getOrNull()?.also { kept = it }
        private val PICTURES = mapOf("gold" to R.drawable.montana_gold_ground, "montana" to R.drawable.montana_wallpaper, "burgundy" to R.drawable.montana_burgundy)
        private val pictures = HashMap<Int, Bitmap>()
        /** Decoded once, when a ground first wears it. */
        fun picture(c: Context, res: Int): Bitmap? = synchronized(pictures) {
            pictures[res] ?: runCatching { BitmapFactory.decodeResource(c.resources, res) }.getOrNull()?.also { pictures[res] = it }
        }
    }
}

/** A drawn ground, or my page's ground for «general», or the kept picture (CENTER_CROP) — the one view every chat draws. */
fun Context.groundView(choice: ChatWall.Choice): View = when (choice) {
    ChatWall.Choice.General -> pageGround()
    is ChatWall.Choice.Named -> View(this).apply { background = GroundPaint(context, choice.name) }
    is ChatWall.Choice.Photo -> ChatWall.image(choice.file)?.let { b ->
        ImageView(this).apply { setImageBitmap(b); scaleType = ImageView.ScaleType.CENTER_CROP; setBackgroundColor(Color.BLACK) }
    } ?: CrestGround(this)
}

/**
 * MY PAGE'S GROUND (iOS montanaPageGround, rule 30: «the page's ground is every page's and every chat's»): the ground I chose
 * in my profile, or the pages' crest while I chose none. A chat on «Same as my page» wears it.
 */
fun Context.pageGround(): View = ChatWall.choice(ChatWall.PAGE).let { if (it == ChatWall.Choice.General) CrestGround(this) else groundView(it) }

/** The ground slot of a chat's page — or of any page, with ChatWall.PAGE: it follows the choice while the page stands. */
fun Context.chatGround(ref: String): FrameLayout = FrameLayout(this).apply {
    fun fillIn() { removeAllViews(); addView(groundView(ChatWall.choice(ref)), FrameLayout.LayoutParams(MATCH, MATCH)) }
    fillIn()
    val l: () -> Unit = { fillIn() }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { ChatWall.listen(l); fillIn() }
        override fun onViewDetachedFromWindow(v: View) { ChatWall.unlisten(l) }
    })
}

// ── the chooser ──

/**
 * THE CHOOSER (iOS MTWallpaperPicker): two tabs clearly apart — the ready-made grounds, and the photos. The first holds the
 * round «Same as my page», the round photo now chosen, and the drawn grounds three to a row; a tap opens the preview. The
 * photos: iOS shows the library inline on the page; Android offers an app no inline library, so the tab opens the system's
 * own picker and the chosen photo goes to the preview. The cross and the checkmark leave; the preview's checkmark keeps.
 */
fun wallpaperPicker(act: MainActivity, ref: String, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY)
    lateinit var draw: () -> Unit

    fun preview(choice: ChatWall.Choice, picture: Bitmap? = null) {
        act.push { close -> wallpaperPreview(act, ref, choice, picture) { kept -> close(); if (kept) draw() } }
    }
    fun pickPhoto() = act.pickPhoto { uri ->
        val b = uri?.let { SelfFace.decode(act, it) } ?: return@pickPhoto
        preview(ChatWall.Choice.General, b)
    }
    /** A tile: the thumbnail, the platform's check badge when chosen, the whole tile answering the finger. */
    fun tile(chosen: Boolean, label: String, round: Boolean, paint: View, act0: () -> Unit): View = FrameLayout(c).apply {
        contentDescription = label
        val rim = GradientDrawable().apply { if (round) shape = GradientDrawable.OVAL else cornerRadius = dp(18).toFloat() }
        outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(v: View, o: android.graphics.Outline) =
                if (round) o.setOval(0, 0, v.width, v.height) else o.setRoundRect(0, 0, v.width, v.height, dp(18).toFloat())
        }
        clipToOutline = true
        addView(paint, FrameLayout.LayoutParams(MATCH, MATCH))
        foreground = rim.apply { setColor(Color.TRANSPARENT); setStroke(if (chosen) dp(3) else dp(1), if (chosen) MT.blue else Color.argb(31, 255, 255, 255)) }
        if (chosen) addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(MT.blue); setStroke(dp(2), Color.WHITE) }
            addView(c.icon(R.drawable.ic_check, Color.WHITE), FrameLayout.LayoutParams(dp(14), dp(14), Gravity.CENTER))
        }, FrameLayout.LayoutParams(dp(22), dp(22), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, dp(6), dp(6)) })
        pressable(act0)
    }

    val tabs = c.hstack { background = c.rounded(Color.argb(40, 118, 118, 128), 9); setPadding(dp(2), dp(2), dp(2), dp(2)) }
    listOf(R.string.wall_tab_ready, R.string.wall_tab_photos).forEachIndexed { i, res ->
        tabs.addView(c.text(c.getString(res), 14f, Color.WHITE, bold = i == 0, center = true).apply {
            setPadding(0, dp(6), 0, dp(6))
            if (i == 0) background = c.rounded(Color.rgb(99, 99, 102), 7)
            pressable { if (i == 1) pickPhoto() }
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
    }

    draw = {
        body.removeAllViews()
        body.addView(tabs, lp().apply { setMargins(c.dp(20), c.dp(8), c.dp(20), c.dp(10)) })
        val now = ChatWall.choice(ref)
        body.addView(c.hstack {
            setPadding(dp(20), dp(10), dp(20), 0)
            // my page's own chooser offers «No background» (the crest); a chat's offers «Same as my page» (iOS task.isPage)
            val page = ref == ChatWall.PAGE
            addView(tile(now == ChatWall.Choice.General, c.getString(if (page) R.string.pg_none else R.string.wall_same_as_page), true,
                if (page) CrestGround(c) else c.pageGround()) {
                preview(ChatWall.Choice.General)
            }, lp(dp(78), dp(78)))
            if (now is ChatWall.Choice.Photo) ChatWall.image(now.file)?.let { b ->
                addView(View(c), lp(dp(18), 1))
                addView(tile(true, c.getString(R.string.wall_choose_photo), true,
                    ImageView(c).apply { setImageBitmap(b); scaleType = ImageView.ScaleType.CENTER_CROP }) { pickPhoto() }, lp(dp(78), dp(78)))
            }
        }, lp())
        // the drawn grounds, three to a row, each 168 tall (iOS adaptive 104…150, spacing 14)
        val grid = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(20), dp(18), dp(20), dp(24)) }
        ChatWall.names.chunked(3).forEachIndexed { r, row ->
            grid.addView(c.hstack {
                row.forEachIndexed { i, (key, res) ->
                    if (i > 0) addView(View(c), lp(dp(14), 1))
                    addView(tile(now == ChatWall.Choice.Named(key), c.getString(res), false, View(c).apply { background = GroundPaint(c, key) }) {
                        preview(ChatWall.Choice.Named(key))
                    }, LinearLayout.LayoutParams(0, dp(168), 1f))
                }
                repeat(3 - row.size) { addView(View(c), lp(dp(14), 1)); addView(View(c), LinearLayout.LayoutParams(0, dp(168), 1f)) }
            }, lp().apply { if (r > 0) topMargin = c.dp(14) })
        }
        body.addView(grid, lp())
    }
    draw()

    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(barOf(c, c.getString(if (ref == ChatWall.PAGE) R.string.pg_title else R.string.pi_chat_background), onClose, onClose), lp(MATCH, dp(56)))
            addView(ScrollView(c).apply { isVerticalScrollBarEnabled = false; addView(body) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/** A page's bar as iOS draws it here: the cross at the left, the title, the checkmark at the right (MontanaCloseMark / DoneMark). */
private fun barOf(c: Context, title: String, onCross: () -> Unit, onCheck: () -> Unit): View = FrameLayout(c).apply {
    fun mark(icon: Int, words: Int, gravity: Int, work: () -> Unit) = addView(FrameLayout(c).apply {
        background = c.glassPlate(oval = true); contentDescription = c.getString(words)
        addView(c.icon(icon, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        pressable(work)
    }, FrameLayout.LayoutParams(dp(44), dp(44), gravity or Gravity.CENTER_VERTICAL).apply { setMargins(dp(14), 0, dp(14), 0) })
    mark(R.drawable.ic_close, R.string.cancel, Gravity.START, onCross)
    addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
    mark(R.drawable.ic_check, R.string.pe_done, Gravity.END, onCheck)
}

// ── the preview ──

/**
 * THE PREVIEW (iOS MTWallpaperPreview): the ground being tried stands full-screen under the chat's own bubbles — three
 * examples at the top, where the eye starts; a picture is placed by the finger over its own mirrored blur. The cross leaves
 * everything as it was; the checkmark keeps the choice, and a picture exactly as the screen shows it.
 */
fun wallpaperPreview(act: MainActivity, ref: String, choice: ChatWall.Choice, picture: Bitmap?, onDone: (Boolean) -> Unit): View {
    val c: Context = act
    val placer = picture?.let { WallPlacer(c, it) }
    val ground: View = placer ?: c.groundView(choice)
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(ground, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(barOf(c, c.getString(R.string.wall_preview), { onDone(false) }) {
                if (placer != null) {
                    // my page's ground is kept light, as it leaves the phone; a chat's ground stays the lossless PNG (iOS lightData)
                    val file = placer.render()?.let { if (ref == ChatWall.PAGE) PageGround.keepLight(it) else ChatWall.keep(it) }
                    if (file != null) ChatWall.set(ref, ChatWall.Choice.Photo(file))
                } else ChatWall.set(ref, choice)
                onDone(true)
            }, lp(MATCH, dp(56)))
            // the bubbles are the picture's dress; the finger is the picture's
            addView(c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(12), dp(8), dp(12), 0)
                addView(c.bubble(c.getString(R.string.wall_hello), mine = false), lp())
                gap(7)
                addView(c.bubble(c.getString(R.string.your_message), mine = true), lp())
                gap(7)
                addView(c.bubble(c.getString(R.string.their_message), mine = false), lp())
                isClickable = false
            }, lp())
        }, FrameLayout.LayoutParams(MATCH, WRAP))
    }
}

/**
 * THE PICTURE IS PLACED BY THE FINGER (iOS MTWallpaperCropView): moved and scaled — down to a third of the filling size,
 * up to three times — over a dress of the picture itself, mirrored and blurred (the bubble's own dress). What the screen
 * shows at the checkmark is exactly what the chat wears: the view drawn once more into a picture of its own size.
 */
class WallPlacer(c: Context, private val image: Bitmap) : View(c) {
    private val dress: Bitmap = mirrorBlur(image)
    private val m = Matrix()
    private var fill = 0f
    private var scale = 1f
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val scaler = ScaleGestureDetector(c, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean {
            val next = (scale * d.scaleFactor).coerceIn(fill * 0.33f, fill * 3f)
            val k = next / scale; scale = next
            m.postScale(k, k, d.focusX, d.focusY); clamp(); invalidate(); return true
        }
    })
    private val mover = GestureDetector(c, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent) = true
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean { m.postTranslate(-dx, -dy); clamp(); invalidate(); return true }
    })
    /** THE ROOM AROUND THE CONTENT IS A WHOLE SCREEN ON EVERY SIDE (iOS MTWallpaperCropView.layoutSubviews, MontanaSettings.swift:
     * 691-694 at 2155): a shrunk picture is dragged into any corner, an enlarged one past its own edges -- one screen's room, not past it. */
    private fun clamp() {
        if (width <= 0 || height <= 0) return
        val v = FloatArray(9); m.getValues(v)
        v[Matrix.MTRANS_X] = v[Matrix.MTRANS_X].coerceIn(-(image.width * scale), width.toFloat())
        v[Matrix.MTRANS_Y] = v[Matrix.MTRANS_Y].coerceIn(-(image.height * scale), height.toFloat())
        m.setValues(v)
    }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        if (w <= 1 || h <= 1 || fill != 0f) return
        fill = maxOf(w / image.width.toFloat(), h / image.height.toFloat())
        scale = fill
        m.setScale(fill, fill)
        m.postTranslate((w - image.width * fill) / 2, (h - image.height * fill) / 2)
    }
    override fun onDraw(canvas: Canvas) = drawInto(canvas)
    private fun drawInto(canvas: Canvas) {
        canvas.drawColor(Color.BLACK)
        // the dress, filling the screen (aspect fill)
        val k = maxOf(width / dress.width.toFloat(), height / dress.height.toFloat())
        val dw = dress.width * k; val dh = dress.height * k
        canvas.drawBitmap(dress, null, RectF((width - dw) / 2, (height - dh) / 2, (width + dw) / 2, (height + dh) / 2), paint)
        canvas.drawBitmap(image, m, paint)
    }
    @android.annotation.SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        scaler.onTouchEvent(e)
        if (!scaler.isInProgress) mover.onTouchEvent(e)
        return true
    }
    /** The view as it stands, at its own size and pixels (iOS rendered: drawHierarchy). */
    fun render(): Bitmap? {
        if (width <= 1 || height <= 1) return null
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { drawInto(Canvas(it)) }
    }

    companion object {
        /** The picture mirrored and blurred once, small — drawn large it is smooth (iOS mirrorBlur, radius width/40); the feed's narrow picture stands on it too. */
        fun mirrorBlur(b: Bitmap): Bitmap {
            val small = maxOf(8, b.width / 40)
            val h = maxOf(8, (b.height * small / b.width.toFloat()).toInt())
            val tiny = Bitmap.createScaledBitmap(b, small, h, true)
            var out = Bitmap.createBitmap(tiny, 0, 0, tiny.width, tiny.height, Matrix().apply { setScale(-1f, 1f) }, true)
            // doubled step by step, each step filtered: the blocks melt into a blur instead of standing as squares
            repeat(4) { out = Bitmap.createScaledBitmap(out, out.width * 2, out.height * 2, true) }
            return out
        }
    }
}
