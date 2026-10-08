package quest.montana.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.net.Uri
import android.os.SystemClock
import android.text.TextUtils
import android.text.util.Linkify
import android.transition.ChangeBounds
import android.transition.TransitionManager
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView

/**
 * THE FACE AND HOW IT OPENS — ONE OWNER (iOS MTFaceDock and MTFaceHeader): every page starts at the circle; a press opens it to
 * the square the crop framed, as wide as the page; a press on the open face shows it on the whole screen; the page scrolled up by
 * the finger closes it back into the circle. Nothing but a press opens it. Under the face stand the name, the blocked pill, the
 * person's own words and their link, each on its own bubble of glass, and the note I keep on them, grey — centred under the
 * circle, on the left under the open square. One slow smooth curve carries the face and everything under it together.
 */
class FaceHead(private val act: MainActivity, private val scene: ViewGroup) {
    private val c: Context = act
    val view: LinearLayout = c.vstack(Gravity.CENTER_HORIZONTAL)
    private var dock = 0             // 0 the circle, 1 the open square; the whole screen is a page of its own over it
    private var round = true         // the circle's outline; the plain square's while it opens, stands open and closes
    private var morphing = false     // the page moved by the morph itself is not the finger's scroll (iOS isMorphing)
    private var face: Bitmap? = null
    private var glyph = "?"
    private var picture: View = View(c)
    private var scroll: ScrollView? = null

    /** The page's own scroll: scrolled up by the finger past 25 points, the open face closes into the circle (iOS scrolled). */
    fun attach(page: ScrollView) {
        scroll = page
        page.setOnScrollChangeListener { _, _, y, _, _ ->
            if (dock == 1 && !morphing && c.dp(25) < y) { morphing = true; page.post { set(0) } }
        }
    }

    /** The face and the lines as they stand now; the face keeps whether it is open. */
    fun draw(face: Bitmap?, name: String, blocked: Boolean, bio: String, link: Uri?, note: String) {
        this.face = face
        glyph = name.trim().let { if (it.isEmpty()) "?" else it.substring(0, it.offsetByCodePoints(0, 1)) }
        view.removeAllViews()
        picture = drawPicture()
        view.addView(picture)
        fun line(v: View) = view.addView(v, lp(WRAP, WRAP).apply { topMargin = c.dp(8); marginStart = c.dp(18); marginEnd = c.dp(18) })
        line(bubble(c.text(name, 20f, Color.WHITE, bold = true).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END }))   // USER-DATA: their name
        if (blocked) line(blockedPill())
        if (bio.isNotEmpty()) line(bubble(c.text("", 17f, Color.WHITE).apply {
            // their links live, as the iPhone's MTLinks.linked: a tap on a link opens it, the words around it stay selectable
            autoLinkMask = Linkify.WEB_URLS; setLinkTextColor(MT.blue); setTextIsSelectable(true)
            text = bio   // USER-DATA: their bio
        }))
        if (link != null) line(bubble(c.text(PeerAbout.shown(link), 17f, MT.blue).apply {   // USER-DATA: their link
            maxLines = 1; ellipsize = TextUtils.TruncateAt.MIDDLE
            setOnClickListener { runCatching { act.startActivity(Intent(Intent.ACTION_VIEW, link)) } }
            // the hold is the platform's own menu with «Copy», as the iPhone's context menu
            setOnLongClickListener { v ->
                PopupMenu(c, v).apply {
                    menu.add(c.getString(R.string.copy))
                    setOnMenuItemClickListener {
                        c.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("", link.toString())); true
                    }
                }.show()
                true
            }
        }))
        if (note.isNotEmpty()) line(c.text(note, 15f, MT.gray))   // USER-DATA: the note I keep on this person, plain grey words
        lay()
    }

    private fun drawPicture(): View {
        val b = face
        val p: View = if (b != null) ImageView(c).apply { setImageBitmap(b); scaleType = ImageView.ScaleType.CENTER_CROP }
            else c.text(glyph, 17f, Color.WHITE, bold = true, center = true)   // USER-DATA: their glyph; it grows with the face
        p.setBackgroundColor(Color.BLACK)
        p.clipToOutline = true
        p.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(v: View, o: Outline) = if (round) o.setOval(0, 0, v.width, v.height) else o.setRect(0, 0, v.width, v.height)
        }
        p.setOnClickListener { if (dock == 0) set(1) else whole() }
        return p
    }

    /** Where everything stands for the face's state: the face's side and place, the lines' side. */
    private fun lay() {
        val open = dock == 1
        val w = view.width.takeIf { it != 0 } ?: c.resources.displayMetrics.widthPixels
        val side = if (open) maxOf(c.dp(105), minOf(w, (c.resources.displayMetrics.heightPixels * 0.8f).toInt())) else c.dp(104)
        val at = if (open) Gravity.START else Gravity.CENTER_HORIZONTAL
        view.setPadding(0, if (open) 0 else c.dp(8), 0, 0)
        (picture as? TextView)?.setTextSize(TypedValue.COMPLEX_UNIT_PX, side * 0.42f)
        picture.layoutParams = lp(side, side).apply { gravity = at }
        for (i in 1 until view.childCount) {
            val v = view.getChildAt(i)
            v.layoutParams = (v.layoutParams as LinearLayout.LayoutParams).apply { gravity = at }
            (v as? TextView)?.gravity = at
        }
    }

    /** The one place that changes the face (iOS MTFaceDock.set): the press and the scroll both come here. */
    private fun set(next: Int) {
        if (next == dock) { morphing = false; return }
        morphing = true
        view.postDelayed({ morphing = false }, 600)
        // the page returns to its top at the change, at once and under the morph; a finger holding it is let go there
        scroll?.let { s ->
            if (s.scrollY != 0) {
                val now = SystemClock.uptimeMillis()
                val letGo = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
                s.dispatchTouchEvent(letGo); letGo.recycle()
                s.scrollTo(0, 0)
            }
        }
        // SLOW AND SMOOTH (iOS MTFaceDock.morph, .smooth 0.8 s): one curve for the face and every row under it
        TransitionManager.beginDelayedTransition(scene, ChangeBounds().apply { duration = 800; interpolator = PathInterpolator(0.2f, 0f, 0f, 1f) })
        dock = next
        if (next == 1) { round = false; picture.invalidateOutline() }
        else view.postDelayed({ if (dock == 0) { round = true; picture.invalidateOutline() } }, 800)
        lay()
    }

    /** The whole screen (iOS MontanaPhotoViewer from the open face): the picture, or their glyph without one; a press closes it. */
    private fun whole() {
        lateinit var close: () -> Unit
        close = act.overlay(FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            val b = face
            if (b != null) addView(ImageView(c).apply { setImageBitmap(b); scaleType = ImageView.ScaleType.FIT_CENTER }, FrameLayout.LayoutParams(MATCH, MATCH))
            else addView(c.text(glyph, 160f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(MATCH, MATCH))   // USER-DATA: their glyph
            pressable { close() }
        })
    }

    /** A line of the head on its own bubble of glass, hugging its words (iOS montanaFieldGlass). */
    private fun bubble(v: TextView): View = v.apply {
        background = c.glassPlate().apply { cornerRadius = dp(22).toFloat() }
        setPadding(dp(16), dp(9), dp(16), dp(9))
    }

    /** «Blocked» on its own red capsule with the platform's no-sign (iOS MTBlockedPill). */
    private fun blockedPill(): View = c.hstack {
        background = c.rounded(Color.rgb(140, 38, 64), 100)
        setPadding(dp(12), dp(5), dp(12), dp(5))
        addView(c.icon(R.drawable.ic_nosign, Color.WHITE, 15), lp(dp(15), dp(15)).apply { marginEnd = dp(6) })
        addView(c.text(c.getString(R.string.pi_blocked), 15f, Color.WHITE).apply { typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL) })
    }
}
