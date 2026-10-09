package quest.montana.app

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.Switch
import android.widget.TextView

// ─────────── colours (iOS MontanaNetFrames.swift / ContentView.swift) ───────────
object MT {
    val gray = Color.rgb(142, 142, 147)         // iOS .gray
    val plate = Color.rgb(31, 31, 31)           // iOS Color(white: 0.12)
    val orange = Color.rgb(255, 159, 10)        // iOS .orange (dark)
    val red = Color.rgb(255, 69, 58)            // iOS .red (dark)
    val green = Color.rgb(48, 209, 88)          // iOS .green (dark)
    val blue = Color.rgb(10, 132, 255)          // iOS .systemBlue (dark), MontanaOctagon.platformBlue
    val hairline = Color.argb(20, 255, 255, 255)
    fun withAlpha(c: Int, a: Float) = Color.argb((a * 255).toInt(), Color.red(c), Color.green(c), Color.blue(c))
}

fun Context.dp(v: Number): Int = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

/**
 * THE SYSTEM TEXT SIZE DISTORTS NOTHING (iOS 1454: every window pinned at its trait): the app's words, its menus and its
 * dialogs keep the sizes they were drawn at, whatever the system's text size says.
 */
fun pinnedText(base: Context): Context {
    val conf = android.content.res.Configuration(base.resources.configuration)
    if (conf.fontScale == 1f) return base
    conf.fontScale = 1f
    return base.createConfigurationContext(conf)
}
fun View.dp(v: Number): Int = context.dp(v)

// ─────────── layout parameters, written once ───────────
fun lp(w: Int = ViewGroup.LayoutParams.MATCH_PARENT, h: Int = ViewGroup.LayoutParams.WRAP_CONTENT, weight: Float = 0f) =
    LinearLayout.LayoutParams(w, h, weight)
const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT

/** A vertical stack (SwiftUI VStack). */
fun Context.vstack(gravity: Int = Gravity.CENTER_HORIZONTAL, build: LinearLayout.() -> Unit = {}) =
    LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; this.gravity = gravity; build() }

/** A horizontal stack (SwiftUI HStack). */
fun Context.hstack(build: LinearLayout.() -> Unit = {}) =
    LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; build() }

/** Empty room that grows (SwiftUI Spacer()). */
fun LinearLayout.spacer() = addView(View(context), lp(if (orientation == LinearLayout.VERTICAL) MATCH else 0, if (orientation == LinearLayout.VERTICAL) 0 else MATCH, 1f))

/** A fixed gap (SwiftUI Spacer().frame(height:)). */
fun LinearLayout.gap(size: Int) = addView(View(context), if (orientation == LinearLayout.VERTICAL) lp(MATCH, dp(size)) else lp(dp(size), 1))

fun Context.text(s: CharSequence, sizeSp: Float = 17f, color: Int = Color.WHITE, bold: Boolean = false, center: Boolean = false) =
    TextView(this).apply {
        text = s
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextColor(color)
        if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        if (center) gravity = Gravity.CENTER
    }

fun Context.rounded(color: Int, radiusDp: Number, strokeColor: Int? = null) = GradientDrawable().apply {
    setColor(color); cornerRadius = dp(radiusDp).toFloat()
    if (strokeColor != null) setStroke(dp(1), strokeColor)
}

fun Context.icon(res: Int, tint: Int, sizeDp: Int = 24) = ImageView(this).apply {
    setImageResource(res)
    imageTintList = ColorStateList.valueOf(tint)
    layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
}

/** Dims while pressed (iOS: .opacity(isPressed ? 0.55 : 1)). */
fun View.pressable(onClick: () -> Unit): View {
    isClickable = true
    setOnClickListener { onClick() }
    setOnTouchListener { v, e ->
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> v.alpha = if (v.isEnabled) 0.55f else v.alpha
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> v.alpha = if (v.isEnabled) 1f else 0.4f
        }
        false
    }
    return this
}

/** The page's act (iOS bigButton, MontanaScreens 579-581 at 2155): the accent's fill -- white in the dark (AccentColor) --, black headline, corner 14. */
class AccentButton(ctx: Context, title: String, onClick: () -> Unit) : LinearLayout(ctx) {
    private val label = ctx.text(title, 17f, Color.BLACK, bold = true)
    private val spinner = ProgressBar(ctx).apply {
        indeterminateTintList = ColorStateList.valueOf(Color.BLACK); visibility = View.GONE
    }
    init {
        orientation = HORIZONTAL; gravity = Gravity.CENTER
        background = ctx.rounded(Color.WHITE, 14)
        setPadding(0, dp(16), 0, dp(16))
        addView(spinner, LayoutParams(dp(18), dp(18)).apply { marginEnd = dp(8) })
        addView(label)
        pressable(onClick)
    }
    fun setTitle(s: String) { label.text = s }
    fun setBusy(busy: Boolean) { spinner.visibility = if (busy) View.VISIBLE else View.GONE; setOn(!busy) }
    /** Enabled or dimmed to 0.4, as iOS dims a disabled button. */
    fun setOn(on: Boolean) { isEnabled = on; alpha = if (on) 1f else 0.4f }
}

/**
 * THE DOOR OF THE PATH (iOS MTLoginDoorStyle, MontanaSettings 2651-2689): every act from the first screen to the chats —
 * create, open, show and copy the words, restore, open from the account, go on without the copy, agree to the terms — wears
 * this one plate, never a fill of its own: the 52-point capsule of the dark material with its rim (the face before the
 * platform's glass), the page's main act rimmed in the platform's blue, a second act clear; the word white and semibold, an
 * act not yet open dimmed to 0.4. Gold is the sign's alone.
 */
class PathDoor(ctx: Context, title: String, tint: Int? = null, onClick: () -> Unit) : LinearLayout(ctx) {
    private val label = ctx.text(title, 17f, Color.WHITE, bold = true, center = true).apply { singleLineEllipsis() }
    private val spinner = ProgressBar(ctx).apply { indeterminateTintList = ColorStateList.valueOf(Color.WHITE); visibility = View.GONE }
    init {
        orientation = HORIZONTAL; gravity = Gravity.CENTER
        background = android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = ctx.dp(26).toFloat()
            setColor(Color.argb(150, 28, 28, 30))
            // the rim of a clear door is the platform's faint light, of a tinted one its own colour (iOS rim, at 0.45)
            setStroke(ctx.dp(1), if (tint != null) MT.withAlpha(tint, 0.45f) else MT.withAlpha(Color.WHITE, 0.6f * 0.45f))
        }
        minimumHeight = ctx.dp(52)
        setPadding(ctx.dp(18), 0, ctx.dp(18), 0)
        addView(spinner, LayoutParams(ctx.dp(18), ctx.dp(18)).apply { marginEnd = ctx.dp(8) })
        addView(label)
        pressable(onClick)
    }
    fun setTitle(s: String) { label.text = s }
    fun setBusy(busy: Boolean) { spinner.visibility = if (busy) View.VISIBLE else View.GONE; setOn(!busy) }
    fun setOn(on: Boolean) { isEnabled = on; alpha = if (on) 1f else 0.4f }
}

/** iOS Button("Back").font(.caption).foregroundColor(.gray) */
fun Context.backLink(onClick: () -> Unit) =
    text(getString(R.string.back), 12f, MT.gray, center = true).apply { setPadding(dp(16), dp(8), dp(16), dp(8)); pressable(onClick) }

/** A row with the words on the left and the system switch on the right (SwiftUI Toggle). */
fun Context.toggleRow(title: String, onChange: (Boolean) -> Unit): LinearLayout {
    val sw = Switch(this).apply {
        thumbTintList = ColorStateList.valueOf(Color.WHITE)
        trackTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(MT.green, Color.rgb(57, 57, 61)))   // iOS Toggle: the platform's green
        setOnCheckedChangeListener { _, on -> onChange(on) }
    }
    return hstack {
        addView(text(title, 15f), lp(0, WRAP, 1f))
        addView(sw)
        setOnClickListener { sw.toggle() }
    }
}

/** The page's glass plate: rows on a rounded dark card (iOS MTGlassRowPlate inside a List section). */
fun Context.plate(build: LinearLayout.() -> Unit) = vstack(Gravity.NO_GRAVITY) {
    background = rounded(GLASS_TONE, 12, Color.argb(26, 255, 255, 255))   // the settings' cards on one-tone glass (iOS MTGlassCardPlate, MontanaBoardViews.swift:2764)
    build()
}

fun LinearLayout.divider() = addView(View(context).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })

/**
 * THE LETTER OR EMOJI OF A FACE, ONE DERIVATION FOR THE WHOLE CLIENT (iOS MontanaAvatar.initial/isEmoji/glyphScale,
 * MontanaAvatarKit.swift:22-54, atom 344e5535221e/1783): a glyph the person put first IS their face, drawn as is
 * and larger, as the face itself; otherwise the first letter, uppercased, at the caption's share.
 */
fun avatarInitial(name: String): String {
    val t = name.trim()
    if (t.isEmpty()) return "?"
    // the first CHARACTER as the person sees it (iOS t.first, a grapheme): a flag or a family of joined glyphs is one
    val chars = android.icu.text.BreakIterator.getCharacterInstance().apply { setText(t) }
    val g = t.substring(0, chars.next().takeIf { 0 < it } ?: t.offsetByCodePoints(0, 1))
    return if (isAvatarEmoji(g)) g else g.uppercase()
}
/** iOS MontanaAvatar.isEmoji (MontanaAvatarKit.swift:22-26): a joined character is a glyph when any of its scalars is; a lone one above U+238C. */
private fun isAvatarEmoji(g: String): Boolean {
    val points = g.codePoints().toArray()
    if (points.isEmpty()) return false
    if (1 < points.size) return points.any { android.icu.lang.UCharacter.hasBinaryProperty(it, android.icu.lang.UProperty.EMOJI) }
    return 0x238C < points[0] && android.icu.lang.UCharacter.hasBinaryProperty(points[0], android.icu.lang.UProperty.EMOJI)
}
/** iOS MontanaAvatar.glyphScale (MontanaAvatarKit.swift:31-34): a letter 0.40 of the circle, a glyph -- the face itself -- 0.62. */
fun avatarGlyphScale(g: String): Float = if (g.isNotEmpty() && isAvatarEmoji(g)) 0.62f else 0.40f

/**
 * THE PLATFORM'S COUNT BADGE (iOS MTCountBadge, ContentView.swift:1436-1455): a red capsule 20 high, the number 13 semibold, 6 at
 * its sides and never narrower than 20; above 99 «99+»; nothing at all at zero.
 */
fun Context.countBadge(): TextView = text("", 13f, Color.WHITE, bold = true).apply {
    background = rounded(SysColor.red, 10)
    gravity = Gravity.CENTER
    minWidth = dp(20)
    setPadding(dp(6), 0, dp(6), 0)
    visibility = View.GONE
}
fun TextView.showCount(n: Int) {
    text = if (99 < n) "99+" else n.toString()   // USER-DATA: a count
    visibility = if (0 < n) View.VISIBLE else View.GONE
}

/** The face (iOS AvatarCircle): the photo, or the avatar's own initial, bold and white, on a black circle. */
fun Context.avatar(face: Bitmap?, name: String, sizeDp: Int): View {
    val box = FrameLayout(this)
    box.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.BLACK) }
    box.clipToOutline = true
    box.outlineProvider = object : ViewOutlineProvider() {
        override fun getOutline(v: View, o: Outline) = o.setOval(0, 0, v.width, v.height)
    }
    val inner: View = when {
        face != null -> ImageView(this).apply { setImageBitmap(face); scaleType = ImageView.ScaleType.CENTER_CROP }
        name.isNotBlank() -> avatarInitial(name).let { g -> text(g, sizeDp * avatarGlyphScale(g), Color.WHITE, bold = true, center = true) }
        else -> icon(R.drawable.ic_add_a_photo, Color.WHITE, (sizeDp * 0.36f).toInt())
    }
    val p = if (inner is ImageView && face == null) FrameLayout.LayoutParams(dp(sizeDp * 0.36f), dp(sizeDp * 0.36f), Gravity.CENTER)
            else FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER)
    if (inner is TextView) inner.gravity = Gravity.CENTER
    box.addView(inner, p)
    box.layoutParams = LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp))
    return box
}

/** The logo with its soft halo breathing behind it (iOS intro: 2.3 s, autoreverse), in the accent — white in the dark (iOS AccentColor). */
fun Context.glowingLogo(logoDp: Int, haloDp: Int, periodMs: Long): FrameLayout {
    val halo = View(this).apply {
        background = GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT
            gradientRadius = dp(haloDp / 2).toFloat()
            colors = intArrayOf(MT.withAlpha(Color.WHITE, 0.55f), Color.TRANSPARENT)
        }
    }
    val logo = ImageView(this).apply { setImageResource(R.drawable.logo) }
    ValueAnimator.ofFloat(0f, 1f).apply {
        duration = periodMs; repeatMode = ValueAnimator.REVERSE; repeatCount = ValueAnimator.INFINITE
        interpolator = AccelerateDecelerateInterpolator()
        addUpdateListener { a ->
            val g = a.animatedValue as Float
            halo.alpha = 0.5f + 0.5f * g
            halo.scaleX = 0.92f + 0.16f * g; halo.scaleY = halo.scaleX
        }
        start()
    }
    return FrameLayout(this).apply {
        addView(halo, FrameLayout.LayoutParams(dp(haloDp), dp(haloDp), Gravity.CENTER))
        addView(logo, FrameLayout.LayoutParams(dp(logoDp), dp(logoDp), Gravity.CENTER))
        clipChildren = false
    }
}

fun TextView.singleLineEllipsis() { maxLines = 1; ellipsize = TextUtils.TruncateAt.END }

/**
 * The door of the first screen (iOS MTLoginDoorStyle without a tint, the pre-glass face): a 52dp capsule on a thin dark
 * material with the platform's faint rim; the glyph at the left, the word in the middle, the
 * chevron at the right; the whole capsule is the target and gives under the finger (0.97).
 */
fun Context.loginDoor(glyph: Int, word: String, onClick: () -> Unit): View {
    val glyphView = ImageView(this).apply { setImageResource(glyph) }
    val door = hstack {
        background = GradientDrawable().apply {
            cornerRadius = dp(26).toFloat()
            setColor(Color.argb(150, 28, 28, 30))
            // iOS: a clear door's rim is white at 0.6, drawn at 0.45
            setStroke(dp(1), MT.withAlpha(Color.WHITE, 0.6f * 0.45f))
        }
        setPadding(dp(18), 0, dp(18), 0)
        addView(glyphView, lp(dp(26), dp(26)))
        addView(text(word, 17f, Color.WHITE, bold = true, center = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
        addView(icon(R.drawable.ic_chevron_right, MT.withAlpha(Color.WHITE, 0.55f), 20))
        minimumHeight = dp(52)
    }
    door.isClickable = true
    door.setOnClickListener { onClick() }
    door.setOnTouchListener { v, e ->
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> v.animate().scaleX(0.97f).scaleY(0.97f).setDuration(120).start()
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> v.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
        }
        false
    }
    return door
}

/**
 * Words with links written as iOS writes them in its catalogue — `[the words](url)` — so one string
 * serves both platforms. The links are drawn in [linkColor]; a tap hands the url to [onLink].
 */
fun Context.linkedText(markup: String, sizeSp: Float, color: Int, linkColor: Int, onLink: (String) -> Unit): TextView {
    val out = android.text.SpannableStringBuilder()
    val re = Regex("""\[([^\]]+)]\(([^)]+)\)""")
    var at = 0
    for (m in re.findAll(markup)) {
        out.append(markup, at, m.range.first)
        val start = out.length
        out.append(m.groupValues[1])
        val url = m.groupValues[2]
        out.setSpan(object : android.text.style.ClickableSpan() {
            override fun onClick(w: View) = onLink(url)
            override fun updateDrawState(ds: android.text.TextPaint) { ds.color = linkColor; ds.isUnderlineText = false }
        }, start, out.length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        at = m.range.last + 1
    }
    out.append(markup, at, markup.length)
    return text(out, sizeSp, color, center = true).apply {
        movementMethod = android.text.method.LinkMovementMethod.getInstance()
        highlightColor = Color.TRANSPARENT
    }
}
