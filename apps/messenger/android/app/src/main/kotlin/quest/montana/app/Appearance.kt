package quest.montana.app

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

// ─────────────────────────── the bubble's style (iOS BT, MTBubbleStyle) ───────────────────────────

/**
 * THE ONE DEFAULT OF A BUBBLE (iOS BT): theirs a translucent dark grey, mine a translucent blue, white letters on both, no
 * rim. «Custom» edits from here, so a chat and the editor's preview cannot tell two stories.
 */
object BT {
    const val FILL_FLOOR = 0.20   // the fill slider's lower bound, and the default fill
    const val mF1 = "0A85FF"; const val mF2 = "0A85FF"; const val mTx = "FFFFFF"; const val mOl = "FFFFFF"
    const val mOlOp = 0.0; const val mOlW = 0.0; const val mOp = FILL_FLOOR
    const val pF1 = "6B6B6B"; const val pF2 = "6B6B6B"; const val pTx = "FFFFFF"; const val pOl = "FFFFFF"
    const val pOlOp = 0.0; const val pOlW = 0.0; const val pOp = FILL_FLOOR
    /** A colour still being chosen in the editor, before the checkmark: read through the same door as the stored one. */
    var candidate: Pair<String, String>? = null
    fun hex(key: String, stored: String) = candidate?.takeIf { it.first == key }?.second ?: stored
}

/** The classic style's own colour of my letters (iOS bubblePalette, chosen by bubbleColorIndex). */
private val bubblePalette = intArrayOf(MT.gold, Color.rgb(51, 153, 255), Color.rgb(77, 199, 115), Color.rgb(217, 82, 140),
    Color.rgb(153, 115, 242), Color.rgb(242, 115, 64), Color.rgb(51, 179, 179))

fun colorOf(hex: String): Int = try { Color.parseColor("#$hex") } catch (_: IllegalArgumentException) { Color.GRAY }
fun hexOf(color: Int): String = String.format("%06X", color and 0xFFFFFF)

object BubbleStyle {
    val style: String get() = Prefs.str("bubbleStyle", "montana")
    fun color(key: String, def: String) = colorOf(BT.hex(key, Prefs.str(key, def)))
    fun dbl(key: String, def: Double) = Prefs.dbl(key, def)
    private fun side(mine: Boolean) = if (mine) "cbMine" else "cbPeer"

    /** The letters' colour (iOS MessageBubble.bubbleText). */
    fun text(mine: Boolean): Int = when (style) {
        "custom" -> color(side(mine) + "Text", if (mine) BT.mTx else BT.pTx)
        "montana" -> colorOf(if (mine) BT.mTx else BT.pTx)
        else -> Color.WHITE
    }

    /** The time's colour (iOS metaLine). */
    fun time(mine: Boolean): Int =
        if (style == "montana") MT.withAlpha(text(mine), 0.82f)
        else if (mine) MT.withAlpha(Color.WHITE, 0.75f) else MT.gray

    /** The bubble's fill and rim (iOS MTBubbleStyle.fill / outline, the native skin). */
    fun drawable(c: Context, mine: Boolean): Drawable = BubbleDrawable(c.dp(18).toFloat(), c.resources.displayMetrics.density, mine, style)
    /** The letter's own fill and rim at the call bubble's height (54): the shape at that height is a capsule (iOS voiceCapsuleBubble). */
    fun capsule(c: Context, mine: Boolean): Drawable = BubbleDrawable(c.dp(27).toFloat(), c.resources.displayMetrics.density, mine, style)

    private class BubbleDrawable(val radius: Float, val density: Float, val mine: Boolean, val style: String) : Drawable() {
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

        override fun draw(canvas: Canvas) {
            val r = RectF(bounds)
            val t = if (mine) "cbMine" else "cbPeer"
            when (style) {
                "custom" -> {
                    val f1 = color(t + "Fill1", if (mine) BT.mF1 else BT.pF1)
                    val f2 = color(t + "Fill2", if (mine) BT.mF2 else BT.pF2)
                    fill.shader = LinearGradient(0f, r.top, 0f, r.bottom, f1, f2, Shader.TileMode.CLAMP)
                    fill.alpha = (dbl(t + "Opacity", if (mine) BT.mOp else BT.pOp) * 255).toInt()
                    canvas.drawRoundRect(r, radius, radius, fill)
                    val w = dbl(t + "OutlineW", if (mine) BT.mOlW else BT.pOlW).toFloat() * density
                    val op = dbl(t + "OutlineOp", if (mine) BT.mOlOp else BT.pOlOp).toFloat()
                    if (w > 0f && op > 0f) {
                        rim.shader = null; rim.strokeWidth = w
                        rim.color = MT.withAlpha(color(t + "Outline", if (mine) BT.mOl else BT.pOl), op)
                        val i = w / 2; canvas.drawRoundRect(RectF(r.left + i, r.top + i, r.right - i, r.bottom - i), radius, radius, rim)
                    }
                }
                "montana" -> {
                    // THE LETTER'S GLASS (iOS MTLetterGlass): the send artwork's gradient at 0.88, under a light rim.
                    val colors = if (mine) intArrayOf(Color.rgb(80, 223, 253), Color.rgb(19, 178, 252), Color.rgb(5, 140, 254), Color.rgb(0, 88, 253))
                                 else intArrayOf(Color.rgb(122, 122, 122), Color.rgb(92, 92, 92), Color.rgb(66, 66, 66), Color.rgb(46, 46, 46))
                    fill.shader = LinearGradient(r.left, r.top, r.right, r.bottom, colors, null, Shader.TileMode.CLAMP)
                    fill.alpha = (0.88f * 255).toInt()
                    canvas.drawRoundRect(r, radius, radius, fill)
                    rim.strokeWidth = density
                    rim.shader = LinearGradient(r.left, r.top, r.right, r.bottom,
                        intArrayOf(MT.withAlpha(Color.WHITE, 0.65f), MT.withAlpha(Color.WHITE, 0.08f), MT.withAlpha(if (mine) Color.CYAN else Color.WHITE, 0.6f)),
                        null, Shader.TileMode.CLAMP)
                    val i = density / 2; canvas.drawRoundRect(RectF(r.left + i, r.top + i, r.right - i, r.bottom - i), radius, radius, rim)
                }
                else -> {
                    fill.shader = null
                    fill.color = if (mine) bubblePalette[Prefs.dbl("bubbleColorIndex", 0.0).toInt().coerceIn(0, bubblePalette.size - 1)]
                                 else Color.rgb(46, 46, 46)
                    canvas.drawRoundRect(r, radius, radius, fill)
                }
            }
        }
        override fun setAlpha(alpha: Int) {}
        override fun setColorFilter(cf: ColorFilter?) {}
        @Deprecated("the platform's own") override fun getOpacity() = PixelFormat.TRANSLUCENT
    }
}

/** One letter as the chat will draw it: the words, the time under them at the trailing edge. */
fun Context.bubble(words: String, mine: Boolean, at: java.util.Date = java.util.Date()): View = FrameLayout(this).apply {
    val now = android.text.format.DateFormat.getTimeFormat(context).format(at)
    addView(vstack(Gravity.END) {
        background = BubbleStyle.drawable(context, mine)
        setPadding(dp(12), dp(7), dp(12), dp(6))
        addView(text(words, 16f, BubbleStyle.text(mine)).apply { maxWidth = dp(260) })
        addView(text(now, 11f, BubbleStyle.time(mine)))   // USER-DATA: the time of day
    }, FrameLayout.LayoutParams(WRAP, WRAP, if (mine) Gravity.END else Gravity.START))
}

// ─────────────────────────── the app's icon (iOS MTAppIconChooser) ───────────────────────────

/**
 * THE APP'S ICON, CHOSEN BY ITS PICTURE: the platform's own road is the launcher alias — exactly one of the two enabled.
 * The new one is enabled before the old one goes, so the launcher never stands without the app.
 */
object AppIcon {
    private const val GLASS = "quest.montana.app.IconGlass"
    private const val GOLD = "quest.montana.app.IconGold"
    fun gold(c: Context): Boolean = c.packageManager.getComponentEnabledSetting(ComponentName(c.packageName, GOLD)) ==
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
    fun choose(c: Context, gold: Boolean) {
        if (gold == gold(c)) return
        val pm = c.packageManager
        val on = ComponentName(c.packageName, if (gold) GOLD else GLASS)
        val off = ComponentName(c.packageName, if (gold) GLASS else GOLD)
        pm.setComponentEnabledSetting(on, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        pm.setComponentEnabledSetting(off, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
    }
}

// ─────────────────────────── the page (iOS AppearanceView) ───────────────────────────

/**
 * THE PAGE «APPEARANCE»: the preview is the chat — the very bubbles, on the very ground, with the person's own settings;
 * then the app's icon, the video notes' quality, the feed's motion and the message style with its own colours.
 * Not here yet, each for its own reason: the application icons (Android has no app library yet), the keyboard (the keys
 * are the input method's own window — Android gives an app no word over their look), the voice message style (no voice orb yet).
 */
class AppearancePage(private val act: MainActivity, private val onClose: () -> Unit) {
    val view: View
    private val previewBox = FrameLayout(act)
    private val custom = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL }
    private val styleRows = LinearLayout(act).apply { orientation = LinearLayout.VERTICAL }

    init {
        val c: Context = act
        val list = c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), 0, dp(16), dp(24))
            // THE APP'S ICON: the liquid glass or the gold on black, chosen by their pictures.
            addView(header(c, R.string.app_icon))
            addView(c.plate { addView(iconChooser(), lp()) }, lp())
            // The note's picture quality: three steps.
            addView(header(c, R.string.note_quality))
            addView(c.plate {
                setPadding(dp(12), dp(10), dp(12), dp(10))
                addView(segmented(c, listOf(R.string.q_min to "low", R.string.q_medium to "medium", R.string.q_max to "high"),
                    Prefs.str("noteQuality", "medium")) { Prefs.setStr("noteQuality", it) }, lp())
            }, lp())
            addView(header(c, R.string.feed_motion))
            val motion = c.vstack(Gravity.NO_GRAVITY)
            fun fillMotion() {
                motion.removeAllViews()
                motion.addView(slider(c, R.string.springiness, "chatSpringBounce", 0.18, 0.0, 0.4, big = true), lp())
                motion.addView(slider(c, R.string.anim_duration, "chatSpringDuration", 0.55, 0.25, 0.8, big = true), lp())
            }
            fillMotion()
            addView(c.plate {
                addView(motion, lp())
                divider()
                addView(actionRow(c, R.string.reset_motion) { Prefs.remove("chatSpringBounce", "chatSpringDuration"); fillMotion() }, lp())
            }, lp())
            addView(footer(c, R.string.feed_motion_footer))
            addView(header(c, R.string.message_style))
            addView(c.plate { addView(styleRows, lp()) }, lp())
            addView(custom, lp())
        }
        fillStyles()
        fillCustom()
        refresh()
        view = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.topBar(c.getString(R.string.appearance), onBack = onClose))
                addView(previewBox, lp().apply { setMargins(dp(16), dp(10), dp(16), dp(4)) })
                addView(ScrollView(c).apply { addView(list) }, lp(MATCH, 0, 1f))
            }, FrameLayout.LayoutParams(MATCH, MATCH))
        }
    }

    /** The preview drawn again from the stored settings (and a colour still being chosen). */
    private fun refresh() {
        BT.candidate = null   // an editor left by the back gesture leaves no colour behind
        previewBox.removeAllViews()
        previewBox.addView(previewStack(act), FrameLayout.LayoutParams(MATCH, WRAP))
    }

    private fun iconChooser(): View {
        val c: Context = act
        val row = c.hstack { setPadding(dp(12), dp(6), dp(12), dp(6)) }
        fun fill() {
            row.removeAllViews()
            val gold = AppIcon.gold(c)
            listOf(Triple(false, R.drawable.app_icon_glass_art, R.string.icon_glass), Triple(true, R.drawable.icon_gold_preview, R.string.icon_gold)).forEach { (isGold, pic, word) ->
                row.addView(FrameLayout(c).apply {
                    setPadding(dp(4), dp(4), dp(4), dp(4))
                    contentDescription = c.getString(word)
                    // the chosen one ringed in the platform's blue
                    if (isGold == gold) foreground = GradientDrawable().apply { cornerRadius = dp(17).toFloat(); setStroke(dp(3), MT.blue) }
                    addView(ImageView(c).apply {
                        setImageResource(pic); scaleType = ImageView.ScaleType.CENTER_CROP
                        outlineProvider = object : ViewOutlineProvider() {
                            override fun getOutline(v: View, o: Outline) = o.setRoundRect(0, 0, v.width, v.height, dp(15).toFloat())
                        }
                        clipToOutline = true
                    }, FrameLayout.LayoutParams(dp(64), dp(64)))
                    pressable { AppIcon.choose(c, isGold); fill() }
                }, lp(WRAP, WRAP).apply { marginEnd = c.dp(12) })
            }
        }
        fill()
        return row
    }

    private fun fillStyles() {
        val c: Context = act
        styleRows.removeAllViews()
        listOf(R.string.style_montana to "montana", R.string.style_classic to "classic", R.string.style_custom to "custom").forEachIndexed { i, (word, key) ->
            if (i > 0) styleRows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(16) })
            styleRows.addView(c.hstack {
                setPadding(dp(16), dp(12), dp(16), dp(12))
                addView(c.text(c.getString(word), 16f), lp(0, WRAP, 1f))
                addView(c.icon(R.drawable.ic_check, MT.blue).apply { alpha = if (BubbleStyle.style == key) 1f else 0f }, lp(dp(20), dp(20)))
                pressable { Prefs.setStr("bubbleStyle", key); fillStyles(); fillCustom(); refresh() }
            }, lp())
        }
    }

    /** «Custom»: both bubbles' colours and numbers, then swap and reset. */
    private fun fillCustom() {
        val c: Context = act
        custom.removeAllViews()
        if (BubbleStyle.style != "custom") return
        for (mine in listOf(true, false)) {
            val t = if (mine) "cbMine" else "cbPeer"
            custom.addView(header(c, if (mine) R.string.your_bubble else R.string.their_bubble))
            custom.addView(c.plate {
                addView(colorRow(R.string.fill_top, t + "Fill1", if (mine) BT.mF1 else BT.pF1), lp()); divider()
                addView(colorRow(R.string.fill_bottom, t + "Fill2", if (mine) BT.mF2 else BT.pF2), lp()); divider()
                addView(slider(c, R.string.fill_opacity, t + "Opacity", BT.FILL_FLOOR, BT.FILL_FLOOR, 1.0) { refresh() }, lp()); divider()
                addView(colorRow(R.string.bubble_text, t + "Text", if (mine) BT.mTx else BT.pTx), lp()); divider()
                addView(colorRow(R.string.outline, t + "Outline", if (mine) BT.mOl else BT.pOl), lp()); divider()
                addView(slider(c, R.string.outline_opacity, t + "OutlineOp", 0.0, 0.0, 1.0) { refresh() }, lp()); divider()
                addView(slider(c, R.string.outline_width, t + "OutlineW", 0.0, 0.0, 3.0) { refresh() }, lp())
            }, lp())
        }
        custom.addView(View(c), lp(MATCH, c.dp(20)))
        custom.addView(c.plate {
            addView(actionRow(c, R.string.swap_sides) { swapSides(); fillCustom(); refresh() }, lp()); divider()
            addView(actionRow(c, R.string.reset_montana) { resetMontana(); fillCustom(); refresh() }, lp())
        }, lp())
    }

    private val sideKeys = listOf("Fill1", "Fill2", "Opacity", "Text", "Outline", "OutlineOp", "OutlineW")
    private val numbers = setOf("Opacity", "OutlineOp", "OutlineW")
    private fun swapSides() {
        for (k in sideKeys) {
            if (k in numbers) {
                val m = Prefs.dbl("cbMine$k", mineDefault(k) as Double); val p = Prefs.dbl("cbPeer$k", peerDefault(k) as Double)
                Prefs.setDbl("cbMine$k", p); Prefs.setDbl("cbPeer$k", m)
            } else {
                val m = Prefs.str("cbMine$k", mineDefault(k).toString()); val p = Prefs.str("cbPeer$k", peerDefault(k).toString())
                Prefs.setStr("cbMine$k", p); Prefs.setStr("cbPeer$k", m)
            }
        }
    }
    private fun mineDefault(k: String): Any = when (k) { "Fill1" -> BT.mF1; "Fill2" -> BT.mF2; "Opacity" -> BT.mOp; "Text" -> BT.mTx; "Outline" -> BT.mOl; "OutlineOp" -> BT.mOlOp; else -> BT.mOlW }
    private fun peerDefault(k: String): Any = when (k) { "Fill1" -> BT.pF1; "Fill2" -> BT.pF2; "Opacity" -> BT.pOp; "Text" -> BT.pTx; "Outline" -> BT.pOl; "OutlineOp" -> BT.pOlOp; else -> BT.pOlW }
    private fun resetMontana() = Prefs.remove(*sideKeys.flatMap { listOf("cbMine$it", "cbPeer$it") }.toTypedArray())

    /** A colour row: the words, and the colour's swatch; the whole row opens the colour editor. */
    private fun colorRow(word: Int, key: String, def: String): View {
        val c: Context = act
        return c.hstack {
            setPadding(dp(16), dp(12), dp(16), dp(12))
            addView(c.text(c.getString(word), 16f), lp(0, WRAP, 1f))
            addView(View(c).apply { background = swatch(c, colorOf(Prefs.str(key, def))) }, lp(dp(30), dp(22)))
            pressable {
                lateinit var close: () -> Unit
                close = act.overlay(ColorEditor(act, c.getString(word), Prefs.str(key, def), key,
                    onSave = { Prefs.setStr(key, it); fillCustom(); refresh() }, onClose = { close() }).view)
            }
        }
    }
}

/** The preview: their letter and mine, on the pages' ground, in a rounded box (iOS previewStack). */
fun previewStack(c: Context): View = FrameLayout(c).apply {
    outlineProvider = object : ViewOutlineProvider() {
        override fun getOutline(v: View, o: Outline) = o.setRoundRect(0, 0, v.width, v.height, dp(12).toFloat())
    }
    clipToOutline = true
    addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
    addView(c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(12), dp(14), dp(12), dp(14))
        addView(c.bubble(c.getString(R.string.their_message), mine = false), lp())
        gap(7)
        addView(c.bubble(c.getString(R.string.your_message), mine = true), lp())
    }, FrameLayout.LayoutParams(MATCH, WRAP))
}

private fun header(c: Context, res: Int) = c.text(c.getString(res), 13f, MT.gray).apply { setPadding(c.dp(16), c.dp(20), c.dp(16), c.dp(6)) }
private fun footer(c: Context, res: Int) = c.text(c.getString(res), 12f, MT.gray).apply { setPadding(c.dp(16), c.dp(8), c.dp(16), 0) }
private fun swatch(c: Context, color: Int) = GradientDrawable().apply {
    setColor(color); cornerRadius = c.dp(5).toFloat(); setStroke(c.dp(1), MT.withAlpha(Color.WHITE, 0.3f))
}

/** A row that acts (iOS Button in a List: the accent's words). */
private fun actionRow(c: Context, res: Int, onTap: () -> Unit) =
    c.text(c.getString(res), 16f, MT.gold).apply { setPadding(c.dp(16), c.dp(13), c.dp(16), c.dp(13)); pressable(onTap) }

/**
 * A slider over a stored number (iOS Slider): the caption above, the platform's SeekBar in gold. The number is kept in its
 * range; `big` is the feed motion's larger caption.
 */
private fun slider(c: Context, word: Int, key: String, def: Double, lo: Double, hi: Double, big: Boolean = false, onChange: () -> Unit = {}): View =
    c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(16), dp(10), dp(16), dp(6))
        addView(c.text(c.getString(word), if (big) 16f else 12f, if (big) Color.WHITE else MT.gray))
        addView(SeekBar(c).apply {
            max = 1000
            progress = (((Prefs.dbl(key, def).coerceIn(lo, hi) - lo) / (hi - lo)) * 1000).toInt()
            progressTintList = ColorStateList.valueOf(MT.gold); thumbTintList = ColorStateList.valueOf(MT.gold)
            contentDescription = c.getString(word)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar, p: Int, fromUser: Boolean) {
                    if (fromUser) { Prefs.setDbl(key, lo + (hi - lo) * p / 1000.0); onChange() }
                }
                override fun onStartTrackingTouch(s: SeekBar) {}
                override fun onStopTrackingTouch(s: SeekBar) {}
            })
        }, lp())
    }

/**
 * THE SEGMENTED CHOICE (iOS .pickerStyle(.segmented)): the platform has no segmented control of its own, so it is the
 * capsule of equal segments with the chosen one lit — words and a stored value each.
 */
private fun segmented(c: Context, items: List<Pair<Int, String>>, chosen: String, onPick: (String) -> Unit): View {
    val row = c.hstack { background = c.rounded(Color.argb(40, 118, 118, 128), 9); setPadding(dp(2), dp(2), dp(2), dp(2)) }
    fun fill(now: String) {
        row.removeAllViews()
        items.forEach { (word, value) ->
            row.addView(c.text(c.getString(word), 14f, Color.WHITE, bold = value == now, center = true).apply {
                setPadding(0, dp(7), 0, dp(7))
                if (value == now) background = c.rounded(Color.rgb(99, 99, 102), 7)
                pressable { onPick(value); fill(value) }
            }, lp(0, WRAP, 1f))
        }
    }
    fill(chosen)
    return row
}

// ─────────────────────────── the colour editor (iOS ColorEditorSheet) ───────────────────────────

/**
 * THE COLOUR IS CHOSEN WITH THE PREVIEW ABOVE IT: the live preview stands over the picker, and the change lands only on the
 * checkmark; the cross leaves everything as it was. iOS opens the system's own colour picker; Android has none of its own,
 * so the colour is chosen by its hue, saturation and brightness on the platform's sliders, with its hex number under them.
 */
class ColorEditor(act: MainActivity, title: String, start: String, private val key: String,
                  private val onSave: (String) -> Unit, private val onClose: () -> Unit) {
    val view: View
    private val hsv = FloatArray(3).also { Color.colorToHSV(colorOf(start), it) }
    private val preview = FrameLayout(act)
    private val swatchView = View(act)
    private val hexView = act.text("", 13f, MT.gray).apply { typeface = Typeface.MONOSPACE }   // USER-DATA: the colour's hex number

    init {
        val c: Context = act
        fun mark(res: Int, onTap: () -> Unit) = c.icon(res, Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onTap) }
        val bar = FrameLayout(c).apply {
            setPadding(dp(8), 0, dp(8), 0)
            addView(mark(R.drawable.ic_close) { leave() }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
            addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            addView(mark(R.drawable.ic_check) { val h = current(); leave(); onSave(h) },
                FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
        }
        fun hsvSlider(word: Int, i: Int, top: Float) = c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(8), dp(16), dp(4))
            addView(c.text(c.getString(word), 12f, MT.gray))
            addView(SeekBar(c).apply {
                max = 1000; progress = (hsv[i] / top * 1000).toInt()
                progressTintList = ColorStateList.valueOf(MT.gold); thumbTintList = ColorStateList.valueOf(MT.gold)
                contentDescription = c.getString(word)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar, p: Int, fromUser: Boolean) { if (fromUser) { hsv[i] = top * p / 1000f; show() } }
                    override fun onStartTrackingTouch(s: SeekBar) {}
                    override fun onStopTrackingTouch(s: SeekBar) {}
                })
            }, lp())
        }
        val list = c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(10), dp(16), dp(24))
            addView(preview, lp())
            gap(20)
            addView(c.plate {
                addView(c.hstack {
                    setPadding(dp(16), dp(12), dp(16), dp(12))
                    addView(c.text(c.getString(R.string.colour), 16f), lp(0, WRAP, 1f))
                    addView(swatchView, lp(dp(44), dp(28)))
                }, lp())
                divider()
                addView(hsvSlider(R.string.hue, 0, 360f), lp())
                addView(hsvSlider(R.string.saturation, 1, 1f), lp())
                addView(hsvSlider(R.string.brightness, 2, 1f), lp())
                addView(hexView.apply { setPadding(dp(16), dp(6), dp(16), dp(12)) }, lp())
            }, lp())
        }
        view = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            addView(CrestGround(c), FrameLayout.LayoutParams(MATCH, MATCH))
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(bar, lp(MATCH, dp(52)))
                addView(ScrollView(c).apply { addView(list) }, lp(MATCH, 0, 1f))
            }, FrameLayout.LayoutParams(MATCH, MATCH))
        }
        show()
    }

    private fun current() = hexOf(Color.HSVToColor(hsv))

    /** The candidate rides through BT.candidate — the preview reads it through the same door as the stored colour. */
    private fun show() {
        val h = current()
        BT.candidate = key to h
        swatchView.background = swatch(view0(), colorOf(h))
        hexView.text = "#$h"
        preview.removeAllViews()
        preview.addView(previewStack(view0()), FrameLayout.LayoutParams(MATCH, WRAP))
    }
    private fun view0(): Context = preview.context

    private fun leave() { BT.candidate = null; onClose() }
}
