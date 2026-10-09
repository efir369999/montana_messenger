package quest.montana.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.StyleSpan
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import org.webrtc.EglBase
import org.webrtc.EglRenderer
import org.webrtc.GlRectDrawer
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * THE CALL'S OWN SCREEN (iOS CallOverlayView, MontanaCall.swift 6442-6860). In hand (fullScreen): the ground of the peer's face
 * (MTCallGround 6406) and the system grid of two rows of three: Speaker/Audio · Video · Mute over Hold · End · Broadcast. A voice
 * call (the audio branch): the fold-away mark, the system's line — the light, «Montana Audio Call — 0:03» (or the stage) — and the
 * name at forty. A video call (the video branch, 6575-6618 and 6649-6697): two fixed slots — the big one filling the screen, the
 * corner one 110 by 156 (MTCallSurface, MTCallMini) — the pictures handed between them, never rebuilt; a tap on the picture hides
 * and brings back the buttons (a sibling layer — the picture never takes the finger), six untouched seconds hide them
 * (chromeFoldS); the top row — the fold, the name in the centre, the camera flip — the time under it, the call's events under
 * that. The far side's ask stands over the grid (6745-6767), and so does the offer to turn my camera on (6768-6788). While a
 * screen rides — mine or theirs — only the fold stands, and the stop under my own (6624-6647). Ringing while the app stands in
 * front (incomingScreen 6504): the same face, Decline and Accept. Folded (pillBody 6536): the green pill with the call's clock
 * and the red end over every page.
 */
object CallScreen {
    private const val SIDE = 76   // the face's construction default (MontanaCall.swift 6990); CallGrid and RingGrid cut the live circle from the width before the first draw
    private const val MINI_W = 110   // iOS MTCallMini: the corner picture's fixed frame
    private const val MINI_H = 156
    private const val FOLD_MS = 6000L   // iOS chromeFoldS: a video call's buttons step aside after six untouched seconds
    private val barGlyph = Color.rgb(204, 204, 204)   // iOS MontanaOctagon.barGlyph
    @Volatile var front: MainActivity? = null   // the activity on the screen (its onResume / onPause): an in-app ring stands there
    private var close: (() -> Unit)? = null
    private var ringing = false   // the page on the screen is the in-app ring, not the call in hand
    private var pill: (() -> Unit)? = null
    private var chromeHidden = false   // iOS chromeHidden: the picture was tapped and the buttons stepped aside, for the call's life
    private var corner = 1   // iOS miniCorner, for the call's life: 0 top left, 1 top right, 2 bottom left, 3 bottom right

    /** The call in hand on the screen; an in-app ring standing there gives way to it. */
    fun show(act: MainActivity, ref: String) {
        dropPill()
        if (close != null && !ringing) return
        close?.invoke()
        ringing = false
        chromeHidden = false   // iOS fullScreen .onAppear (MontanaCall.swift 6915): every reopening starts with the buttons in hand
        close = act.overlay(callPage(act, ref))
        CallFloat.refresh(act, "show")
    }

    /** The call screen folds into its pill under the window that rose from it (iOS willStart 6209-6211); a ring has no fold. */
    fun fold() = MainThread.post { if (!ringing) close?.invoke() }

    /** The call's own ground for the window over other apps (one owner of its drawing, iOS MTCallGround). */
    fun groundOf(c: Context, ref: String, name: String): View = ground(c, ref, name)

    /** A call rings while the app stands in front (iOS incomingScreen: the in-app ring). */
    fun ring(ref: String) = MainThread.post {
        val act = front ?: return@post
        if (close != null) return@post
        ringing = true
        close = act.overlay(ringPage(act, ref))
    }

    /** The call ended: the screen and the pill go, and the screen's choices end with the call. */
    fun hide() = MainThread.post { dropPill(); chromeHidden = false; corner = 1; val c = close; close = null; c?.invoke() }

    private fun dropPill() { pill?.invoke(); pill = null; foldChanged(null) }

    /**
     * THE PERSON HEARS WHY (iOS tellNoRoad, MontanaCall.swift, atom 319c1ca96b0a, 29.09): a call that found no road ends
     * with a word in the person's language, not a screen that simply closes. Android carries no network-filter probe
     * (iOS MontanaNetProbe) to tell a filtered network from a plain failure, so this build speaks the one general word.
     */
    fun tellNoRoad(filtered: Boolean = NetProbe.filtersCalls) = MainThread.post {
        val act = front ?: return@post
        // UNDER THE PERMITTED-LIST FILTER THE WORDS SAY SO (iOS tellNoRoad(filtered:) 623-636): the line's one verdict, NetProbe
        android.app.AlertDialog.Builder(act).setTitle(if (filtered) R.string.call_filtered_title else R.string.call_no_road_title)
            .setMessage(if (filtered) R.string.call_filtered_body else R.string.call_no_road_body)
            .setPositiveButton(R.string.ok, null).show()
    }

    /**
     * THE CAMERA REFUSAL IS SAID TO THE FACE (iOS cameraDenied alert 6531-6545, ensureCameraAccess 1581-1601, atom 6ebef1dc1ca8,
     * the author's word 20.09): the system's own alert, the road to the app's own page in Settings, and the call goes on with
     * sound. Android does not restart the app when the switch is turned on, so its words say to turn the video on again.
     */
    fun tellCameraOff() = MainThread.post {
        val act = front ?: return@post
        android.app.AlertDialog.Builder(act).setTitle(R.string.call_cam_off_title).setMessage(R.string.call_cam_off_body)
            .setPositiveButton(R.string.open_settings) { _, _ -> SystemSettings.open(act, callWarned = true) }
            .setNegativeButton(R.string.continue_with_voice, null).show()
    }

    private fun log(s: String) { Log.d("Montana", "call screen: " + s) }

    /** The call folded into its pill, and whose (iOS CallUIModel.foldedLive, peer): the handsets beside a name watch it. */
    @Volatile var foldedRef: String? = null
        private set
    private val foldWatch = mutableListOf<() -> Unit>()
    fun watchFold(w: () -> Unit) = synchronized(foldWatch) { foldWatch.add(w) }
    fun unwatchFold(w: () -> Unit) = synchronized(foldWatch) { foldWatch.remove(w) }
    private fun foldChanged(ref: String?) {
        if (foldedRef == ref) return
        foldedRef = ref
        val ws = synchronized(foldWatch) { foldWatch.toList() }
        MainThread.post { ws.forEach { it() } }
    }
    /** The green handset: the folded call opens again (iOS model.fold(false, why: "handset")). */
    fun unfold(act: MainActivity) { foldedRef?.let { show(act, it) } }

    /** The ring's face (iOS incomingScreen 6504-6533): the light and the kind of call, the name at forty, Decline and Accept. */
    private fun ringPage(act: MainActivity, ref: String): View {
        val c: Context = act
        val name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
        val title = if (Calls.ringVideo()) R.string.call_title_video else R.string.call_title_audio
        val column = c.vstack(Gravity.CENTER_HORIZONTAL) {
            addView(NotchGap(c), lp(MATCH, WRAP))
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.icon(R.drawable.ic_dot, SysColor.green, 11), lp(dp(11), dp(11)).apply { marginEnd = dp(6) })
                addView(c.text(c.getString(title), 20f, Color.argb(153, 255, 255, 255)).apply { singleLineEllipsis() }, lp(WRAP, WRAP))
            }, lp(WRAP, WRAP).apply { leftMargin = dp(16); rightMargin = dp(16) })
            gap(10)
            addView(bigName(c, name), lp(MATCH, dp(52)).apply { leftMargin = dp(16); rightMargin = dp(16) })
            addView(View(c), lp(MATCH, 0, 1f))
            // iOS incomingScreen 6566-6574: Decline and Accept wear the live call's own grid(_:) circle, seventy-two apart
            val decline = button(c, R.string.call_decline, R.drawable.ic_phone_down, SysColor.red, { false }) { Thread { Calls.hangUp() }.start() }
            val accept = button(c, R.string.call_accept, R.drawable.ic_peer_phone, SysColor.green, { false }) {
                val cl = close; close = null; ringing = false; cl?.invoke()
                act.answerCall()
            }
            addView(RingGrid(c, listOf(decline, accept)), lp(WRAP, WRAP))
            gap(46)
        }
        return Page(c).apply {
            isClickable = true   // the screen takes every touch: nothing under it is reached
            addView(ground(c, ref, name), FrameLayout.LayoutParams(MATCH, MATCH))
            addView(column, FrameLayout.LayoutParams(MATCH, MATCH))
            inner = column
        }
    }

    /** The call in hand (iOS fullScreen 6561-6860): one page for both branches — the video's views stand ready and step in when the call carries pictures. */
    private fun callPage(act: MainActivity, ref: String): View {
        val c: Context = act
        val name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
        var hold: (() -> Unit)? = null   // the hold button repaints with the tick: the far side's word may change nothing, mine may
        var videoLit: (() -> Unit)? = null
        var again: () -> Unit = {}
        val medium = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        val haze = Color.argb(128, 0, 0, 0)   // legible over whatever the picture shows (iOS .shadow 0.5, 3)
        // ── the audio branch's line (iOS 6702-6738): the light, «Montana Audio Call — 0:03», the name at forty, the state ──
        val light = c.icon(R.drawable.ic_dot, SysColor.green, 11)
        val status = c.text("", 20f, Color.argb(153, 255, 255, 255)).apply { singleLineEllipsis(); fontFeatureSettings = "tnum" }
        val state = c.text("", 17f, Color.WHITE, bold = true, center = true).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END }
        val voiceHead = c.vstack(Gravity.CENTER_HORIZONTAL) {
            gap(20)
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(light, lp(dp(11), dp(11)).apply { marginEnd = dp(6) })
                addView(status, lp(WRAP, WRAP))
            }, lp(WRAP, WRAP).apply { leftMargin = dp(16); rightMargin = dp(16) })
            gap(10)
            addView(bigName(c, name), lp(MATCH, dp(52)).apply { leftMargin = dp(16); rightMargin = dp(16) })
            addView(state, lp().apply { leftMargin = dp(16); rightMargin = dp(16); topMargin = dp(2) })
        }
        // ── the video branch's top (iOS MTCallTopTitle/MTCallTimeLine/MTCallStateLine, MontanaCall.swift 5301-5422, the
        // call site 6694-6743 in 2155, atom a14135b48a1d): the name in the row's centre, the time under it, the events under that ──
        // THE NAME IS AS LARGE AS THE MARKS ALLOW (iOS MTCallTopTitle.nameSize, MontanaCall.swift 5311-5315): the largest
        // semibold size whose own line fits the 44dp row, read from the platform's font metrics, not guessed ("too small" —
        // the author, 23.09).
        val nameSp = run {
            val target = c.dp(44).toFloat()
            val paint = Paint().apply { typeface = medium }
            var s = 40f
            while (s > 12f) {
                paint.textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, s, c.resources.displayMetrics)
                val fm = paint.fontMetrics
                if (fm.descent - fm.ascent <= target) break
                s -= 1f
            }
            s
        }
        val title = c.text(name, nameSp, Color.WHITE).apply {   // USER-DATA: the peer's name
            typeface = medium
            gravity = Gravity.CENTER
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.MARQUEE   // iOS MTCallMarquee: a name wider than its room runs three times
            marqueeRepeatLimit = 3
            isSelected = true
            setShadowLayer(dp(3).toFloat(), 0f, 0f, haze)
        }
        val vlight = c.icon(R.drawable.ic_dot, SysColor.green, 11)
        val clock = c.text("", 17f, Color.argb(217, 255, 255, 255)).apply {
            typeface = medium; fontFeatureSettings = "tnum"; singleLineEllipsis(); setShadowLayer(dp(3).toFloat(), 0f, 0f, haze)
        }
        val timeLine = c.hstack {
            gravity = Gravity.CENTER
            addView(vlight, lp(dp(11), dp(11)).apply { marginEnd = dp(5) })
            addView(clock, lp(WRAP, WRAP))
        }
        val events = c.text("", 17f, Color.WHITE, bold = true, center = true).apply { singleLineEllipsis(); setShadowLayer(dp(3).toFloat(), 0f, 0f, haze) }
        // THE FOLD IS THE APP'S LEAVING (iOS 6702-6708, the author's word 29.09): the mark asks the platform's own window to
        // rise; with no window to ask (a ring, a system without it, the person's switch off) it folds the call into the app
        val back = mark(c, R.drawable.ic_chevron_down, R.string.call_back) { if (!CallFloat.foldAway(act, "back")) close?.invoke() }
        val flip = mark(c, R.drawable.ic_camera_rotate, R.string.call_camera) { CallLine.switchCamera() }
        val roomL = View(c)   // the mask's twin room keeps the name in the centre (iOS MontanaCall.swift 6709-6713)
        // THE MASK (iOS MontanaCall.swift 6723-6727, the author's word 30.09, atom c98a92d589e3): a glyph mark with no word on the
        // platform's 44, beside the camera flip -- the filled masks while it is on (theatermasks.fill)
        val maskMark = mark(c, R.drawable.ic_theatermasks, R.string.call_mask) { AvatarMask.toggle("tap") }
        var maskGlyph = R.drawable.ic_theatermasks
        val route = routeButton(c)
        fun line() {
            // iOS MTCallLight 5427-5433: green clean at the top step, yellow (the system's orange) held below it, red squeezed
            // now or broken
            val level = if (CallLine.lost) 0 else CallLine.signal
            val tint = if (level >= 2) SysColor.green else if (level == 1) SysColor.orange else SysColor.red
            // THE LIGHT WEARS THE BATTERY (iOS MTCallLight, MontanaCall.swift 5427-5433, build bd83db719a66): while the
            // power floor holds the picture down, the same light carries the battery glyph instead of the dot.
            // The battery is a wide glyph (SF battery.25percent at .footnote): its slot widens, the dot's height kept.
            val glyph = if (CallLine.powerSaving) R.drawable.ic_battery_quarter else R.drawable.ic_dot
            val wide = c.dp(if (CallLine.powerSaving) 23 else 11)
            for (v in listOf(light, vlight)) {
                v.setImageResource(glyph)
                v.setColorFilter(tint)
                v.layoutParams?.let { if (it.width != wide) { it.width = wide; v.layoutParams = it } }
            }
            val since = CallLine.connectedAt
            // the clock runs only while the call stands connected: a break says «Connecting…» there (iOS statusText 6516-6523,
            // «reconnecting» -> «Connecting…»; the time line shows the timer for «connected» alone, 5342, 6753)
            val tail = if (since > 0L && !CallLine.lost) ((System.currentTimeMillis() - since) / 1000).toInt().let { String.format(Locale.ROOT, "%d:%02d", it / 60, it % 60) }
                else c.getString(Calls.stage() ?: R.string.call_connecting)   // «Calling…», «Ringing…», then «Connecting…»
            status.text = c.getString(R.string.call_title_audio) + " — " + tail
            clock.text = tail
            route.second.invoke()
            // under the name, the call's own state in bold (iOS 6771-6784): the hold line, then the break's own line, each from
            // the call's state -- both stand when both are so; a video call's one line puts a break before a hold (5399-5414)
            val held = CallLine.held || CallLine.heldByPeer
            val words = listOfNotNull(if (held) c.getString(R.string.call_on_hold) else null, if (CallLine.lost) c.getString(R.string.call_lost) else null)
            state.visibility = if (words.isEmpty()) View.GONE else View.VISIBLE
            if (words.isNotEmpty()) state.text = words.joinToString("\n")
            events.text = if (CallLine.lost) c.getString(R.string.call_lost) else if (held) c.getString(R.string.call_on_hold) else ""
            hold?.invoke()
            videoLit?.invoke()
        }
        fun capsule(word: Int, fill: Int, ink: Int, work: () -> Unit) = FrameLayout(c).apply {
            addView(c.text(c.getString(word), 15f, ink, bold = true).apply {
                background = c.rounded(fill, 17); setPadding(dp(14), dp(7), dp(14), dp(7)); maxLines = 1
            }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            contentDescription = c.getString(word)
            pressable { performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); work() }
        }
        fun plate(build: LinearLayout.() -> Unit) = c.hstack {
            background = c.rounded(Color.argb(115, 0, 0, 0), 26)
            setPadding(dp(16), dp(2), dp(10), dp(2))
            build()
        }
        // THE FAR SIDE ASKS (iOS 6745-6767): «NAME is calling with video», Accept in green, Decline in red
        val askWords = SpannableStringBuilder().append(name, StyleSpan(Typeface.BOLD), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)   // USER-DATA: the peer's name
            .append(" ").append(c.getString(R.string.call_video_ask))
        val askPlate = plate {
            addView(c.text(askWords, 15f, Color.WHITE).apply { maxLines = 2; ellipsize = TextUtils.TruncateAt.END }, lp(WRAP, WRAP, 1f))
            gap(12)
            addView(capsule(R.string.call_accept, SysColor.green, Color.BLACK) { CallLine.acceptAsk() }, lp(WRAP, dp(44)))
            gap(8)
            addView(capsule(R.string.call_decline, SysColor.red, Color.WHITE) { CallLine.declineAsk() }, lp(WRAP, dp(44)))
        }
        // MY CAMERA, OFFERED (iOS 6768-6788): their picture came while mine sleeps — «Turn on your video?», «Turn On», the close
        val turnPlate = plate {
            addView(c.text(c.getString(R.string.call_turn_on_video), 15f, Color.WHITE).apply { maxLines = 2 }, lp(WRAP, WRAP, 1f))
            gap(12)
            addView(capsule(R.string.call_turn_on, Color.WHITE, Color.BLACK) { CallLine.turnOn() }, lp(WRAP, dp(44)))
            addView(FrameLayout(c).apply {
                addView(FrameLayout(c).apply {
                    background = c.rounded(Color.argb(46, 255, 255, 255), 14)
                    addView(c.icon(R.drawable.ic_close, Color.WHITE, 12), FrameLayout.LayoutParams(dp(12), dp(12), Gravity.CENTER))
                }, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))
                contentDescription = c.getString(R.string.cancel)
                pressable { CallLine.offerMine = false; again() }
            }, lp(dp(44), dp(44)))
        }
        // the microphone off as the system's own call shows it: the lit plate, the crossed microphone in red (iOS 6801)
        val mute = button(c, R.string.call_mute, R.drawable.ic_mic_slash, null, { CallLine.muted }, SysColor.red) { CallLine.setMuted(!CallLine.muted) }
        val end = button(c, R.string.call_end, R.drawable.ic_phone_down, SysColor.red, { false }) { Thread { Calls.hangUp("hangup") }.start() }
        // «Video» (iOS 6799): lit while the call carries pictures or my ask waits; the camera is asked of the system first
        val videoBtn = button(c, R.string.call_video_btn, R.drawable.ic_peer_video, null, { (CallLine.video && !CallLine.sharing) || CallLine.asking }) {
            if (CallLine.video || c.checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) CallLine.toggleVideo()
            else act.askCamera { ok -> if (ok) CallLine.toggleVideo() }
        }
        // «Broadcast» (iOS 6814-6825): the system's own question, then the screen rides the call and the call folds away — the
        // sharer lands on the very screen being shared; lit while it rides
        val shareBtn = button(c, R.string.call_broadcast, R.drawable.ic_broadcast, null, { CallLine.sharing }) {
            if (CallLine.sharing) CallLine.stopShare()
            else if (CallLine.connectedAt > 0L) act.askScreen { data -> if (data != null) { CallLine.startShare(data); close?.invoke() } }
        }
        // the stop of my share (iOS 6638-6645): the white circle with the share's glyph, the call's end lives on the pill
        val stopShare = FrameLayout(c).apply {
            addView(FrameLayout(c).apply {
                background = c.rounded(Color.WHITE, 28)
                addView(c.icon(R.drawable.ic_broadcast, Color.BLACK, 22), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            }, FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER))
            contentDescription = c.getString(R.string.call_broadcast)
            pressable { performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); CallLine.stopShare() }
        }
        videoLit = { listOf(videoBtn, shareBtn).forEach { b -> b.tag?.let { (it as () -> Unit)() } } }
        // «Swap» while a second call waits parked (iOS model.hasParked, MontanaCall.swift 6854-6856) has no road here:
        // Calls carries one line only, so Hold stays Hold -- there is never a second call to swap to.
        val holdBtn = button(c, R.string.call_hold, R.drawable.ic_pause_fill, null, { CallLine.held }) { CallLine.setHeld(!CallLine.held) }
        hold = { holdBtn.tag?.let { (it as () -> Unit)() } }
        // iOS grid(_:) (6506-6515) cuts the circle, the column and the gap from the width; the row (6835-6905) stands
        // two of three in portrait, turns to one of six lying on its side (vClass == .compact, 6499)
        val grid = CallGrid(c, listOf(route.first, videoBtn, mute, holdBtn, end, shareBtn))
        val top = c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(back, lp(dp(44), dp(44)))
            addView(roomL, lp(dp(44), dp(44)))
            addView(title, lp(0, dp(44), 1f))
            addView(maskMark, lp(dp(44), dp(44)))
            addView(flip, lp(dp(44), dp(44)))
        }
        val column = c.vstack(Gravity.CENTER_HORIZONTAL) {
            addView(top, lp().apply { leftMargin = dp(16); rightMargin = dp(16); topMargin = dp(8) })
            addView(timeLine, lp(MATCH, dp(22)).apply { topMargin = dp(4) })
            addView(events, lp(MATCH, dp(22)).apply { leftMargin = dp(16); rightMargin = dp(16) })
            addView(voiceHead, lp())
            addView(View(c), lp(MATCH, 0, 1f))
            addView(askPlate, lp(WRAP, WRAP).apply { leftMargin = dp(16); rightMargin = dp(16); bottomMargin = dp(12) })
            addView(turnPlate, lp(WRAP, WRAP).apply { leftMargin = dp(16); rightMargin = dp(16); bottomMargin = dp(12) })
            addView(grid, lp(WRAP, WRAP))
            addView(stopShare, lp(dp(56), dp(56)))
            addView(GridFloor(c), lp(MATCH, WRAP))   // iOS 6888/6904: twelve under the row lying on its side, forty-six standing up
        }
        // ── the pictures (iOS 6599-6616): the big slot, the switch over it, the dial's shade, the corner slot ──
        val big = Picture(c)
        val mini = Picture(c)
        // THE STALE PICTURE'S COVER (iOS MTCallSurface overlay 6268-6274, MTCallGround 6406, applyCovers 5491-5495):
        // held, held by the far side, or two witnessed samples without a fresh frame -- the slot carrying their
        // picture wears their own blurred face instead of the stale frame, whichever slot it rides (sides()).
        val remoteCoverBig = ground(c, ref, name).apply { visibility = View.GONE; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val remoteCoverMini = ground(c, ref, name).apply { visibility = View.GONE; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        // MY OWN PICTURE'S COVER (iOS MTCallSurface 6274, MTCallGround(own: true) 6452-6457, atom 8bb2dae00749): my own face,
        // the same haze, while I hold, while my camera is off, and while the system has taken my camera
        val selfCoverBig = ground(c, ref, name, own = true).apply { visibility = View.GONE; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val selfCoverMini = ground(c, ref, name, own = true).apply { visibility = View.GONE; importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val miniBox = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(v: View, o: Outline) { o.setRoundRect(0, 0, v.width, v.height, v.dp(12).toFloat()) }
            }
            clipToOutline = true
            foreground = c.rounded(Color.TRANSPARENT, 12, Color.argb(64, 255, 255, 255))
            addView(mini, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(remoteCoverMini, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(selfCoverMini, FrameLayout.LayoutParams(MATCH, MATCH))
            visibility = View.GONE
        }
        val shade = View(c).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(Color.argb(89, 0, 0, 0), Color.TRANSPARENT, Color.argb(115, 0, 0, 0)))
        }
        val tap = View(c).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val pictures = FrameLayout(c).apply {
            addView(big, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
            addView(remoteCoverBig, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
            addView(selfCoverBig, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
            addView(tap, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(shade, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(miniBox, FrameLayout.LayoutParams(c.dp(MINI_W), c.dp(MINI_H), Gravity.TOP or Gravity.START))
            visibility = View.INVISIBLE
        }
        val page = Page(c).apply {
            isClickable = true   // the screen takes every touch: nothing under it is reached
            addView(ground(c, ref, name), FrameLayout.LayoutParams(MATCH, MATCH))
            addView(pictures, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(column, FrameLayout.LayoutParams(MATCH, MATCH))
            inner = column
        }
        // WHICH PICTURE FILLS WHICH SLOT has one owner (iOS CallUIModel.applySides 5558-5567): their picture, once drawn, fills
        // the screen and mine rides the corner — until the corner is tapped; before theirs comes, mine fills the screen. The
        // corner stands whether my camera runs or not (iOS shown = pip && !peerSharing): a sleeping camera wears my own face.
        var coverSaid = ""
        fun sides() {
            if (CallFloat.standing) return   // the window over other apps holds the peer's picture while it stands
            // the sharer sees the peer's ground, not the screen it shares (iOS 6566-6574): no picture is drawn
            if (CallLine.sharing) {
                CallLine.theirs.into = null; CallLine.own.into = null; miniBox.visibility = View.GONE
                remoteCoverBig.visibility = View.GONE; remoteCoverMini.visibility = View.GONE
                selfCoverBig.visibility = View.GONE; selfCoverMini.visibility = View.GONE
                return
            }
            val pip = CallLine.video && CallLine.remoteLive
            val shown = pip && !CallLine.peerSharing
            val bigLocal = !pip || (CallLine.swapped && shown)
            CallLine.theirs.into = if (!pip) null else if (bigLocal) mini else big
            CallLine.own.into = if (bigLocal) big else if (shown) mini else null
            big.mirror(bigLocal && CallLine.front)
            mini.mirror(!bigLocal && CallLine.front)
            big.fit = !bigLocal && CallLine.peerSharing   // a shared screen is fitted on black, never cut
            miniBox.visibility = if (shown) View.VISIBLE else View.GONE
            shade.visibility = if (!shown && !CallLine.peerSharing) View.VISIBLE else View.GONE
            // THE COVER (iOS applyCovers 5491-5495): held, held by the far side, or the witnessed frames stood
            // still -- the slot carrying their picture wears their blurred face instead of the stale frame.
            val covered = pip && (CallLine.held || CallLine.heldByPeer || (CallLine.peerPaused && !CallLine.peerSharing))
            remoteCoverBig.visibility = if (covered && !bigLocal) View.VISIBLE else View.GONE
            remoteCoverMini.visibility = if (covered && bigLocal && shown) View.VISIBLE else View.GONE
            // THE COVERS HAVE ONE OWNER (iOS applyCovers 5484-5497): mine while I hold, my camera is off or the system took it
            val ownCovered = CallLine.video && (CallLine.held || !CallLine.camera || CallLine.selfPaused)
            selfCoverBig.visibility = if (ownCovered && bigLocal) View.VISIBLE else View.GONE
            selfCoverMini.visibility = if (ownCovered && !bigLocal && shown) View.VISIBLE else View.GONE
            val said = "remote=" + (if (covered) 1 else 0) + " self=" + (if (ownCovered) 1 else 0)
            if (said != coverSaid) { coverSaid = said; Log.d("Montana", "call_cover " + said) }
        }
        // THE CORNER PICTURE'S PLACE, THE 2155 FORM (iOS MTCallMini, MontanaCall.swift 6321-6338): one fact for each edge,
        // read off chromeVisible, not a number measured a frame late -- the top panel up: ten points under its measured
        // bottom; buttons up (CallUIModel.buttonsTop, 6879-6880): ten points over the grid's own measured top; either
        // edge down: fourteen off the safe side. Where the buttons stand, the touch is theirs (6406-6428, blockRect):
        // Android needs no such mask -- column is laid out after pictures, so a button under the finger claims the
        // touch before it ever reaches miniBox underneath.
        // AND IT TELLS WHEN IT IS GONE (iOS blockRect, MontanaCall.swift 6324: "(model.chromeVisible && !model.screenSharing)
        // ? model.bottomRowRect : .zero", plus the .onDisappear at 6887/6903, atom 9efa2d90b61b): the grid goes GONE while a
        // screen rides but column stays VISIBLE, so grid.top alone would read the stale rect from before the share — up
        // asks the grid's own visibility too, not only the column's.
        var placed = false
        var pipLogged = false
        var pipCorner = -1
        var pipUp = -1
        var pipW = 0
        var pipH = 0
        // WHERE IT STANDS IS WRITTEN, NOT GUESSED (iOS MTCallMini.note, MontanaCall.swift 6391-6394 in 2155, atom
        // f4c97f3cc8b0): its corner, its bottom edge, and whether the buttons were up — at birth, at every settle
        // and when the buttons come or go.
        fun notePip(why: String, y: Float, up: Boolean) {
            Log.d("Montana", "call_pip " + why + " corner=" + corner + " bottom=" + (y.toInt() + c.dp(MINI_H)) +
                " top=" + y.toInt() + " screen=" + pictures.width + "x" + pictures.height + " buttons=" + (if (up) 1 else 0))
        }
        fun placeMini(glide: Boolean) {
            if (miniBox.visibility != View.VISIBLE || pictures.width == 0) return
            val up = column.visibility == View.VISIBLE && grid.visibility == View.VISIBLE
            val topEdge = if (up && events.bottom > 0) events.bottom + c.dp(10) else column.paddingTop + c.dp(14)
            val raised = if (grid.top > 0) grid.top - c.dp(10) else pictures.height - column.paddingBottom - c.dp(220)
            val bottomEdge = if (up) raised else pictures.height - column.paddingBottom - c.dp(14)
            val x = (if (corner % 2 == 0) c.dp(14) else pictures.width - c.dp(14) - c.dp(MINI_W)).toFloat()
            val y = (if (corner < 2) topEdge else maxOf(topEdge, bottomEdge - c.dp(MINI_H))).toFloat()
            if (glide && placed) miniBox.animate().translationX(x).translationY(y).setDuration(300).start()
            else { miniBox.animate().cancel(); miniBox.translationX = x; miniBox.translationY = y }
            placed = true
            val why = if (!pipLogged) "born" else if (pipCorner != corner) "moved" else if ((pipUp == 1) != up) "buttons"
                else if (pipW != pictures.width || pipH != pictures.height) "screen" else null
            if (why != null) {
                notePip(why, y, up)
                pipLogged = true; pipCorner = corner; pipUp = if (up) 1 else 0; pipW = pictures.width; pipH = pictures.height
            }
        }
        var foldAt = 0L
        // AN AUDIO CALL ON A PHONE STANDS UPRIGHT (iOS MTCallUpright, MontanaCall.swift 6919-6935, atom 4513e11ddfeb, the
        // author's word 24.09: «during an audio call from the phone the screen must not turn, it stays vertical»). A video
        // call, a folded call (the page detached, below) and a tablet keep the system's own free rotation.
        val phone = c.resources.configuration.smallestScreenWidthDp < 600
        fun upright() {
            act.requestedOrientation = if (!CallLine.video && phone) android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        fun redraw() {
            val v = CallLine.video
            val mine = CallLine.sharing
            val theirs = CallLine.peerSharing
            // while a screen rides — mine or theirs — only the fold stands, and the stop under mine (iOS 6624-6647)
            val screen = mine || theirs
            if (!v || screen) chromeHidden = false
            pictures.visibility = if (v && !mine) View.VISIBLE else View.INVISIBLE
            pictures.setBackgroundColor(if (v && theirs) Color.BLACK else Color.TRANSPARENT)
            tap.visibility = if (v && !screen) View.VISIBLE else View.GONE
            column.visibility = if (v && chromeHidden) View.INVISIBLE else View.VISIBLE
            val head = if (v && !screen) View.VISIBLE else View.INVISIBLE
            roomL.visibility = head; title.visibility = head
            flip.visibility = if (v && !screen && CallLine.camera) View.VISIBLE else View.INVISIBLE
            // the mask stands with the flip (iOS 6722-6733): without my camera both places stand empty, the name stays centred
            maskMark.visibility = flip.visibility
            val glyph = if (AvatarMask.masked) R.drawable.ic_theatermasks_fill else R.drawable.ic_theatermasks
            if (glyph != maskGlyph) { maskGlyph = glyph; (maskMark.getChildAt(0) as ImageView).setImageResource(glyph) }
            timeLine.visibility = if (v && !screen) View.VISIBLE else View.GONE
            events.visibility = timeLine.visibility
            voiceHead.visibility = if (v || mine) View.GONE else View.VISIBLE
            grid.visibility = if (screen) View.GONE else View.VISIBLE
            stopShare.visibility = if (mine) View.VISIBLE else View.GONE
            askPlate.visibility = if (CallLine.asked && !screen) View.VISIBLE else View.GONE
            turnPlate.visibility = if (CallLine.offerMine && v && !screen) View.VISIBLE else View.GONE
            page.keepScreenOn = v   // iOS applyScreenHold: a video call holds the screen awake
            sides()
            upright()
            videoLit?.invoke()
            page.post { placeMini(true) }
        }
        again = { redraw() }
        // the picture is the switch (iOS 6602-6610): a tap hides the buttons, the next brings them back
        tap.setOnClickListener { chromeHidden = !chromeHidden; foldAt = 0L; redraw(); log(if (chromeHidden) "call_chrome hidden by tap" else "call_chrome shown by tap") }
        // THE CORNER PICTURE'S TOUCH (iOS MTCallMiniTouch 6359): a tap that does not move swaps the pictures, a finger that moves
        // drags it, and it settles in the nearest corner
        val slop = ViewConfiguration.get(c).scaledTouchSlop
        miniBox.setOnTouchListener(object : View.OnTouchListener {
            var x0 = 0f; var y0 = 0f; var tx0 = 0f; var ty0 = 0f; var dragging = false
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> { x0 = e.rawX; y0 = e.rawY; tx0 = v.translationX; ty0 = v.translationY; dragging = false; v.animate().cancel() }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = e.rawX - x0; val dy = e.rawY - y0
                        if (!dragging && Math.hypot(dx.toDouble(), dy.toDouble()) > slop) dragging = true
                        if (dragging) { v.translationX = tx0 + dx; v.translationY = ty0 + dy }
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!dragging) { v.performClick(); CallLine.swapped = !CallLine.swapped; sides(); log("call_pip tapped — swap") }
                        else {
                            corner = (if (v.translationX + v.width / 2f > pictures.width / 2f) 1 else 0) +
                                (if (v.translationY + v.height / 2f > pictures.height / 2f) 2 else 0)
                            placeMini(true)
                        }
                    }
                    MotionEvent.ACTION_CANCEL -> placeMini(true)
                }
                return true
            }
        })
        // iOS armChromeFold 5481: a video call that stands, asking nothing of the person, hides its buttons after six seconds
        fun fold() {
            // iOS armChromeFold 5527-5529: a video call that stands connected -- not broken -- with nothing riding or asked
            val want = CallLine.video && CallLine.connectedAt > 0L && !CallLine.lost && !CallLine.peerSharing && !CallLine.sharing && !CallLine.asked &&
                !CallLine.offerMine && !chromeHidden
            if (!want) { foldAt = 0L; return }
            val now = System.currentTimeMillis()
            if (foldAt == 0L) foldAt = now + FOLD_MS
            else if (now >= foldAt) { foldAt = 0L; chromeHidden = true; redraw() }
        }
        line()
        var live = true
        MainThread.later(1000, object : Runnable {
            // sides() here too (iOS applyCovers is didSet-driven; the hold toggle itself calls no moved()): the
            // cover over a held or stalled picture updates on the same breath as the clock, never later than a second.
            override fun run() { if (!live) return; line(); sides(); fold(); MainThread.later(1000, this) }
        })
        val hook: () -> Unit = { line(); redraw() }
        // the page goes by the fold, by the system's back or by the call's end; a call still in hand leaves its pill
        page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { CallLine.changed = hook; redraw() }
            override fun onViewDetachedFromWindow(v: View) {
                live = false
                // a folded call frees the turn (iOS MTCallUpright, atom 4513e11ddfeb): the platform shows it, not us
                act.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                if (CallLine.changed === hook) CallLine.changed = null
                if (CallLine.theirs.into === big || CallLine.theirs.into === mini) CallLine.theirs.into = null
                if (CallLine.own.into === big || CallLine.own.into === mini) CallLine.own.into = null
                big.release(); mini.release()
                close = null
                if (Calls.held() == ref) showPill(act, ref)
            }
        })
        page.addOnLayoutChangeListener { _, l, t, r, b, l0, t0, r0, b0 -> if (r - l != r0 - l0 || b - t != b0 - t0) placeMini(false) }
        return page
    }

    // iOS 6562-6564 / 6762-6764: the name at forty bold standing up, twenty-eight lying down, scaled no smaller than six tenths (minimumScaleFactor 0.6).
    private fun bigName(c: Context, name: String): View = object : TextView(c) {
        init {   // USER-DATA: the peer's name
            text = name
            setTextColor(Color.WHITE)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            singleLineEllipsis()
        }
        override fun onMeasure(widthSpec: Int, heightSpec: Int) {
            val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val max = if (landscape) 28 else 40
            val min = if (landscape) 17 else 24
            setAutoSizeTextTypeUniformWithConfiguration(min, max, 1, TypedValue.COMPLEX_UNIT_SP)
            super.onMeasure(widthSpec, heightSpec)
        }
    }

    /** A mark of the chat's own (iOS MontanaCallMark): the glass circle, its glyph, the finger's forty-four. */
    /** THE CALL'S MARK (iOS MontanaCallMark, MontanaShapes.swift 1092-1114, atom 710032f3b132): the bar's glyph colour on the
     * bar's glass circle with a white 0.28 rim, a 44-point target, a press -- the chat's scroll-down face, one to one. */
    private fun mark(c: Context, glyph: Int, label: Int, work: () -> Unit) = FrameLayout(c).apply {
        background = c.glassPlate(oval = true).apply { setStroke(c.dp(1), Color.argb(71, 255, 255, 255)) }
        contentDescription = c.getString(label)
        addView(c.icon(glyph, barGlyph, 22), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
        pressable { work() }
    }

    /** The page is laid edge to edge; the system bars' room the overlay gives it goes to the column, not to the ground. */
    private class Page(c: Context) : FrameLayout(c) {
        var inner: View? = null
        override fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {
            val i = inner
            if (i != null) i.setPadding(left, top, right, bottom) else super.setPadding(left, top, right, bottom)
        }
    }

    /**
     * THE AUDIO BUTTON WEARS THE SYSTEM CALL'S OWN WORDS (iOS routeBtn 6923, MontanaAudioRoute.face 7261): the phone alone —
     * «Speaker», lit on the loudspeaker, one press moves the sound; a device outside the phone — «Audio» with the glyph of where
     * the sound is, and a press opens the platform's own menu of the ways, the one in use checked.
     */
    private fun routeButton(c: Context): Pair<View, () -> Unit> {
        val icon = c.icon(R.drawable.ic_speaker_wave3, barGlyph, 26)
        val face = FrameLayout(c).apply { addView(icon, FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER)) }
        val caption = c.text("", 15f, Color.WHITE, center = true).apply { singleLineEllipsis() }
        var shown: CallLine.Face? = null
        fun paint() {
            val f = CallLine.face()
            if (f == shown) return
            shown = f
            icon.setImageResource(f.icon)
            icon.setColorFilter(if (f.lit) Color.BLACK else barGlyph)
            face.background = if (f.lit) c.rounded(Color.WHITE, SIDE / 2) else c.glassPlate(oval = true)
            caption.text = c.getString(f.caption)
            face.contentDescription = caption.text
        }
        paint()
        face.pressable {
            val f = CallLine.face()
            if (!f.menu) {
                face.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                CallLine.setSpeaker(!f.lit)
                paint()
                return@pressable
            }
            face.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)   // the press that opens the route menu is felt too (iOS atom bae0da066289)
            val ways = CallLine.ways(c)
            PopupMenu(c, face).apply {
                ways.forEachIndexed { i, w -> menu.add(0, i, i, w.name).apply { isCheckable = true; isChecked = w.chosen } }
                menu.setGroupCheckable(0, true, true)
                setOnMenuItemClickListener { item -> ways.getOrNull(item.itemId)?.take?.invoke(); paint(); true }
            }.show()
        }
        val col = c.vstack(Gravity.CENTER_HORIZONTAL) {
            addView(face, lp(dp(SIDE), dp(SIDE)))
            gap(8)
            addView(caption, lp())
        }
        return col to { paint() }
    }

    /** iOS gridBtn: the circle with its glyph, white when lit, and its one-line caption under it; the press answers under the finger. */
    private fun button(c: Context, caption: Int, glyph: Int, tint: Int?, lit: () -> Boolean, litGlyph: Int = Color.BLACK, work: () -> Unit): View {
        val icon = c.icon(glyph, Color.WHITE, 26)
        val face = FrameLayout(c).apply { addView(icon, FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER)) }
        fun paint() {
            val on = lit()
            face.background = when {
                tint != null -> c.rounded(tint, SIDE / 2)
                on -> c.rounded(Color.WHITE, SIDE / 2)
                else -> c.glassPlate(oval = true)
            }
            icon.setColorFilter(if (tint != null) Color.WHITE else if (on) litGlyph else barGlyph)
        }
        paint()
        face.contentDescription = c.getString(caption)
        face.pressable { face.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY); work(); paint() }
        return c.vstack(Gravity.CENTER_HORIZONTAL) {
            tag = { paint() }
            addView(face, lp(dp(SIDE), dp(SIDE)))
            gap(8)
            addView(c.text(c.getString(caption), 15f, Color.WHITE, center = true).apply { singleLineEllipsis() }, lp())
        }
    }

    /** iOS pillBody (6536-6559): the green capsule — the call's glyph and its clock, «Call» before it joins — and the red end. */
    private fun showPill(act: MainActivity, ref: String) {
        if (pill != null) return
        val c: Context = act
        val clock: TextView = c.text("", 13f, Color.WHITE, bold = true).apply { fontFeatureSettings = "tnum" }
        fun tick() {
            val since = CallLine.connectedAt
            clock.text = if (since > 0L) ((System.currentTimeMillis() - since) / 1000).toInt().let { String.format(Locale.ROOT, "%d:%02d", it / 60, it % 60) }
                else c.getString(R.string.call_pill)
        }
        tick()
        val v = c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                background = c.rounded(SysColor.green, 18)
                elevation = dp(4).toFloat()
                setPadding(dp(14), dp(8), dp(14), dp(8))
                addView(c.icon(R.drawable.ic_peer_phone, Color.WHITE, 14), lp(dp(14), dp(14)).apply { marginEnd = dp(8) })
                addView(clock, lp(WRAP, WRAP))
                pressable { show(act, ref) }
            }, lp(WRAP, WRAP))
            gap(8)
            // the red end, its 32-point face inside the finger's 44
            addView(FrameLayout(c).apply {
                addView(FrameLayout(c).apply {
                    background = c.rounded(SysColor.red, 16)
                    elevation = dp(4).toFloat()
                    addView(c.icon(R.drawable.ic_phone_down, Color.WHITE, 16), FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER))
                }, FrameLayout.LayoutParams(dp(32), dp(32), Gravity.CENTER))
                contentDescription = c.getString(R.string.call_end)
                pressable { Thread { Calls.hangUp("pill") }.start() }
            }, lp(dp(44), dp(44)))
        }
        val gone = act.floating(v, 40)
        var live = true
        pill = { live = false; gone() }
        foldChanged(ref)
        MainThread.later(1000, object : Runnable {
            override fun run() { if (!live) return; tick(); MainThread.later(1000, this) }
        })
    }

    /** iOS MTCallGround: the blue-grey wash, the face filling it as a haze, and the face itself at seven tenths, softened. */
    private fun ground(c: Context, ref: String, name: String, own: Boolean = false): View = FrameLayout(c).apply {
        background = GradientDrawable(GradientDrawable.Orientation.TR_BL, intArrayOf(Color.rgb(33, 38, 48), Color.rgb(41, 51, 71), Color.rgb(26, 28, 33)))
        // my own face for the cover over my own picture (iOS MTCallGround own: MontanaSelfFace.image, 6457)
        val face = if (own) SelfFace.load(c) else Book.shownFace(ref).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
        val soft = Build.VERSION.SDK_INT >= 31
        val m = c.resources.displayMetrics
        val side = (minOf(m.widthPixels, m.heightPixels) * 0.7f).toInt()
        fun blur(r: Int) = RenderEffect.createBlurEffect(c.dp(r).toFloat(), c.dp(r).toFloat(), Shader.TileMode.CLAMP)
        if (face != null) {
            if (soft) addView(ImageView(c).apply {
                setImageBitmap(face); scaleType = ImageView.ScaleType.CENTER_CROP; alpha = 0.35f; setRenderEffect(blur(48))
            }, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(ImageView(c).apply {
                setImageBitmap(face); scaleType = ImageView.ScaleType.FIT_CENTER; alpha = if (soft) 0.5f else 0.3f
                if (soft) setRenderEffect(blur(8))
            }, FrameLayout.LayoutParams(side, side, Gravity.CENTER))
        } else {
            addView(c.text((if (own) Prefs.userName.trim() else name).take(1).uppercase(), 160f, Color.argb(56, 255, 255, 255), bold = true, center = true),   // USER-DATA: the name's first letter
                FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        }
    }
}

/**
 * iOS grid(_:) (MontanaCall.swift 6506-6515): the circle, the column and the gap are cut from the width, not a fixed
 * number -- three columns in portrait, one row of six lying on its side (vClass == .compact, 6499).
 */
private fun gridMetrics(widthPx: Int, density: Float, landscape: Boolean): Triple<Int, Int, Int> {
    val w = (widthPx / density).toInt()
    return if (landscape) {
        val gap = 12   // iOS 6508
        val col = minOf(84, (w - 32 - 5 * gap) / 6)   // iOS 6509
        Triple(maxOf(44, minOf(64, col - 4)), col, gap)   // iOS 6510
    } else {
        val gap = 24   // iOS 6512
        val col = minOf(100, (w - 32 - 2 * gap) / 3)   // iOS 6513
        Triple(maxOf(44, minOf(76, col - 4)), col, gap)   // iOS 6514
    }
}

/**
 * iOS fullScreen's grid (6835-6905): the system two rows of three in portrait, one row of six lying on its side
 * (vClass == .compact, 6499) -- re-measured from the width on every layout, the six columns never rebuilt.
 */
private class CallGrid(c: Context, private val buttons: List<View>) : ViewGroup(c) {
    private var colPx = 0
    private var gapPx = 0
    private var rowH = 0
    init { buttons.forEach { addView(it) } }
    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val (side, col, gap) = gridMetrics(MeasureSpec.getSize(widthSpec), resources.displayMetrics.density, landscape)
        colPx = dp(col); gapPx = dp(gap)
        val sidePx = dp(side)
        val glyphPx = dp((side * 0.34f).roundToInt())   // iOS gridBtn/routeBtn (MontanaCall.swift 6979, 6994): the glyph is side * 0.34, not a fixed 26
        buttons.forEach { btn ->
            val face = (btn as ViewGroup).getChildAt(0) as ViewGroup
            (face.layoutParams as LinearLayout.LayoutParams).apply { width = sidePx; height = sidePx }
            (face.getChildAt(0).layoutParams as FrameLayout.LayoutParams).apply { width = glyphPx; height = glyphPx }
            btn.measure(MeasureSpec.makeMeasureSpec(colPx, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        }
        rowH = buttons[0].measuredHeight
        val width = if (landscape) 6 * colPx + 5 * gapPx else 3 * colPx + 2 * gapPx
        val height = if (landscape) rowH else rowH * 2 + dp(30)   // iOS VStack(spacing: 30), 6890
        setMeasuredDimension(width, height)
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        var x = 0; var y = 0
        buttons.forEachIndexed { i, btn ->
            if (!landscape && i == 3) { x = 0; y = rowH + dp(30) }
            btn.layout(x, y, x + colPx, y + rowH)
            x += colPx + gapPx
        }
    }
}

/**
 * iOS incomingScreen's row (MontanaCall.swift 6566-6574): Decline and Accept wear the exact circle and column the
 * live call's grid(_:) cuts from the width (gridMetrics) -- only the row's own gap is iOS's fixed seventy-two,
 * never the grid's own.
 */
private class RingGrid(c: Context, private val buttons: List<View>) : ViewGroup(c) {
    init { buttons.forEach { addView(it) } }
    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val (side, col, _) = gridMetrics(MeasureSpec.getSize(widthSpec), resources.displayMetrics.density, landscape)
        val colPx = dp(col)
        val glyphPx = dp((side * 0.34f).roundToInt())
        buttons.forEach { btn ->
            val face = (btn as ViewGroup).getChildAt(0) as ViewGroup
            (face.layoutParams as LinearLayout.LayoutParams).apply { width = dp(side); height = dp(side) }
            (face.getChildAt(0).layoutParams as FrameLayout.LayoutParams).apply { width = glyphPx; height = glyphPx }
            btn.measure(MeasureSpec.makeMeasureSpec(colPx, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
        }
        setMeasuredDimension(colPx * 2 + dp(72), buttons[0].measuredHeight)
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val colPx = buttons[0].measuredWidth
        val x1 = colPx + dp(72)
        buttons[0].layout(0, 0, colPx, buttons[0].measuredHeight)
        buttons[1].layout(x1, 0, x1 + colPx, buttons[1].measuredHeight)
    }
}

/** iOS incomingScreen's Spacer (MontanaCall.swift 6556): the room under the notch, six lying down, twenty-two standing up. */
private class NotchGap(c: Context) : View(c) {
    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        setMeasuredDimension(MeasureSpec.getSize(widthSpec), dp(if (landscape) 6 else 22))
    }
}

/** iOS 6888/6904: the room under the grid -- twelve points lying on its side, forty-six standing up. */
private class GridFloor(c: Context) : View(c) {
    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        setMeasuredDimension(MeasureSpec.getSize(widthSpec), dp(if (landscape) 12 else 46))
    }
}

/**
 * A PICTURE OF THE CALL (iOS VideoView): the platform's own texture view, drawn by the engine's renderer. It shows and never takes
 * the finger — the switch over it is a sibling layer (the law of the platform view). A camera fills its room, cut to its shape;
 * a shared screen is fitted whole, its room taking the frame's own shape.
 */
/**
 * THE CALL'S WINDOW OVER OTHER APPS (iOS MTCallFloat, MontanaCall.swift 5997-6260; atoms e0cf5ed44256, 78a602cb45d7,
 * caca0a041069, 9dc4853b6793, 2fefcf4e8cfe, e135ac1d6ea2): the platform's own picture in picture. A call of any kind that
 * stands arms it -- not an incoming ring, whose own screen rules it: a video call shows the peer's picture in it, a voice call
 * (and a picture that does not flow or stands covered) the peer's cover, the call's own ground. It rises by itself when the
 * person leaves the app -- the platform's auto-enter, the person's own switch in Settings deciding -- and the call screen's
 * fold mark asks it to rise (the author's word 29.09: «our own fold button must count as the app folded away»). Its shape is
 * the peer's picture's from its birth (upright 1080x1920 until the picture says otherwise) and follows the picture as it
 * turns. On Android the window IS the app: the app's return is the window's own end, so the peer is never seen on two
 * screens; a tap on it brings the app back with the call screen. Whether it stands is the platform's own word
 * (onPictureInPictureModeChanged), never a flag that could outlive it; a call that ends with the window up takes it away.
 */
/**
 * THE ONE DOOR TO THE APP'S PAGE IN SETTINGS (iOS MontanaSystemSettings, MontanaP2PNode.swift 1305-1330, atom 4543d66a9265):
 * Android ends the app when an access is turned off there, and a call standing then pauses or ends with it -- the platform
 * does not warn; this door does, while a call stands, and the person decides knowing it: a call whose peer rebuilds goes on
 * when the person comes back within a minute (Calls.rejoinHeldCall). A road whose own words already say it passes callWarned.
 */
object SystemSettings {
    fun open(act: MainActivity, callWarned: Boolean = false) {
        val go = { runCatching { act.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", act.packageName, null))) } }
        if (callWarned || Calls.held() == null) { go(); return }
        val goesOn = CallLine.peerRebuilds && CallLine.connectedAt > 0L
        Log.d("Montana", "privacy_access call warned before settings goes_on=" + (if (goesOn) 1 else 0))
        android.app.AlertDialog.Builder(act).setTitle(if (goesOn) R.string.call_will_pause else R.string.call_will_end)
            .setMessage(if (goesOn) R.string.call_will_pause_body else R.string.call_will_end_body)
            .setNegativeButton(R.string.cancel, null)
            .setPositiveButton(R.string.open_settings) { _, _ -> Log.d("Montana", "privacy_access settings opened under a call"); go() }
            .show()
    }
}

/**
 * THE CALL HOLDS THE SOUND WHILE IT LASTS (iOS MontanaAudioSession.refusedUnderCall, ContentView.swift 3203-3220, atom
 * 25da76a76fd0): every other road of sound -- a voice message, a track, a voice tape, a round note -- passes here; under a
 * call none of them starts, and the person who asked is told so in the platform's own alert. True when refused.
 */
object CallSound {
    fun refused(what: String): Boolean {
        if (!Calls.busy()) return false
        Log.d("Montana", "audio_refused " + what + " -- the call holds the sound")
        MainThread.post {
            val act = CallScreen.front ?: return@post
            android.app.AlertDialog.Builder(act).setTitle(R.string.call_sound_busy_title).setMessage(R.string.call_sound_busy_body)
                .setPositiveButton(R.string.ok, null).show()
        }
        return true
    }
    /** A call is born: a track or a voice that plays stands down (iOS VoicePlayer.yieldToCall at setState «born», 4413). */
    fun yieldToCall() = MainThread.post {
        if (MusicPlayer.playing) { MusicPlayer.pause(); Log.d("Montana", "audio_yield music -- a call is born") }
        if (VoicePlayer.playing != null) { VoicePlayer.stop(); Log.d("Montana", "audio_yield voice -- a call is born") }
    }
}

object CallFloat {
    @Volatile var standing = false
        private set
    private var at: java.lang.ref.WeakReference<MainActivity>? = null
    private var face: FrameLayout? = null
    private var picture: Picture? = null
    private var cover: View? = null
    private var shape = android.util.Rational(1080, 1920)
    private var armed = false
    private var foldAsked: String? = null

    private fun supported(act: MainActivity) = act.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
    /** iOS want = state != idle && state != incoming: a call dialled or answered. */
    private fun want() = Calls.held() != null
    private fun params(): android.app.PictureInPictureParams = android.app.PictureInPictureParams.Builder().setAspectRatio(shape).apply {
        if (Build.VERSION.SDK_INT >= 31) { setAutoEnterEnabled(want()); setSeamlessResizeEnabled(true) }
    }.build()

    /** Re-asked at every move of the call and at every showing of its screen: armed while a call stands, its shape the peer's. */
    fun refresh(act: MainActivity? = at?.get(), why: String) {
        val a = act ?: return
        at = java.lang.ref.WeakReference(a)
        if (!supported(a)) return
        CallLine.peerShape?.let { (w, h) ->
            val r = android.util.Rational(w, h).let { if (it.toFloat() < 0.42f) android.util.Rational(42, 100) else if (it.toFloat() > 2.39f) android.util.Rational(239, 100) else it }
            if (r != shape) { shape = r; Log.d("Montana", "call_float shape " + w + "x" + h) }
        }
        val w = want()
        if (w != armed) { armed = w; Log.d("Montana", "call_float " + (if (w) "armed kind=" + (if (CallLine.video) "video" else "voice") else "disarmed") + " why=" + why) }
        runCatching { a.setPictureInPictureParams(params()) }
        // the window stands on the call: a call that ends under it takes it away (iOS e135ac1d6ea2)
        if (!w && a.isInPictureInPictureMode) { Log.d("Montana", "call_float the call ended under the window -- it goes"); a.moveTaskToBack(false) }
        paint()
    }

    /** The fold mark's ask (iOS foldAway 6146-6167): false when there is no window to ask, and the fold takes its old road. */
    fun foldAway(act: MainActivity, why: String): Boolean {
        if (!supported(act) || !want() || act.isInPictureInPictureMode) { Log.d("Montana", "call_float fold by=" + why + " refused"); return false }
        foldAsked = why
        val ok = runCatching { act.enterPictureInPictureMode(params()) }.getOrDefault(false)
        Log.d("Montana", "call_float fold by=" + why + (if (ok) ": asked to rise size=" + shape else " refused by the system"))
        if (!ok) foldAsked = null
        return ok
    }

    /** The person left the app on a system older than the platform's auto-enter (Android 12): the window is asked here. */
    fun leaving(act: MainActivity) {
        if (Build.VERSION.SDK_INT < 31 && supported(act) && want() && !act.isInPictureInPictureMode)
            runCatching { act.enterPictureInPictureMode(params()) }
    }

    /** The platform's own word: the window stands, or it is gone. */
    fun changed(act: MainActivity, inPip: Boolean) {
        standing = inPip
        if (inPip) {
            val ref = Calls.held() ?: return
            val c: Context = act
            val name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
            val p = Picture(c)
            val g = CallScreen.groundOf(c, ref, name)
            val f = FrameLayout(c).apply {
                setBackgroundColor(Color.BLACK)
                isClickable = true
                addView(g, FrameLayout.LayoutParams(MATCH, MATCH))
                addView(p, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
            }
            (act.window.decorView as FrameLayout).addView(f, FrameLayout.LayoutParams(MATCH, MATCH))
            face = f; picture = p; cover = g
            CallLine.theirs.into = p
            if (foldAsked != null) CallScreen.fold()   // the fold mark's ask: the call screen folds away under the window
            Log.d("Montana", "call_float stands" + (foldAsked?.let { " by=" + it } ?: "") + " peer_live=" + (if (CallLine.remoteLive) 1 else 0))
            foldAsked = null
            paint()
        } else {
            face?.let { runCatching { (act.window.decorView as FrameLayout).removeView(it) } }
            if (CallLine.theirs.into === picture) CallLine.theirs.into = null
            picture?.release()
            face = null; picture = null; cover = null
            Log.d("Montana", "call_float gone")
            CallLine.changed?.invoke()   // the call screen takes its pictures back
            // a tap on the window brings the app back with the call screen (iOS restore); a window closed leaves the app away
            MainThread.later(400) { if (CallScreen.front === act && want()) CallScreen.unfold(act) }
        }
    }

    /** The picture while it flows and is not covered, else the cover (iOS drawCover 6130-6144). */
    private fun paint() {
        val p = picture ?: return
        val live = CallLine.video && CallLine.remoteLive && !(CallLine.held || CallLine.heldByPeer || CallLine.peerPaused)
        p.visibility = if (live) View.VISIBLE else View.INVISIBLE
        cover?.visibility = if (live) View.INVISIBLE else View.VISIBLE
    }
}

private class Picture(c: Context) : TextureView(c), TextureView.SurfaceTextureListener, VideoSink {
    private val egl = EglRenderer("mt_picture")
    @Volatile private var ready = false
    @Volatile private var fw = 0
    @Volatile private var fh = 0
    var fit = false
        set(v) { if (field != v) { field = v; requestLayout(); aspect() } }

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        surfaceTextureListener = this
        CallEngine.egl?.let { egl.init(it.eglBaseContext, EglBase.CONFIG_PLAIN, GlRectDrawer()); ready = true }
    }

    fun mirror(on: Boolean) { if (ready) egl.setMirror(on) }

    fun release() { if (ready) { ready = false; egl.release() } }

    override fun onFrame(f: VideoFrame) {
        if (!ready) return
        if (f.rotatedWidth != fw || f.rotatedHeight != fh) { fw = f.rotatedWidth; fh = f.rotatedHeight; post { requestLayout(); aspect() } }
        egl.onFrame(f)
    }

    private fun aspect() { if (ready) egl.setLayoutAspectRatio(if (fit || width == 0 || height == 0) 0f else width.toFloat() / height) }

    override fun onMeasure(wSpec: Int, hSpec: Int) {
        val w = MeasureSpec.getSize(wSpec)
        val h = MeasureSpec.getSize(hSpec)
        if (!fit || fw == 0 || fh == 0 || w == 0 || h == 0) return super.onMeasure(wSpec, hSpec)
        val scale = minOf(w.toFloat() / fw, h.toFloat() / fh)
        setMeasuredDimension((fw * scale).toInt(), (fh * scale).toInt())
    }

    override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) { if (ready) { egl.createEglSurface(st); aspect() } }
    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) { aspect() }
    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
        if (ready) { val done = CountDownLatch(1); egl.releaseEglSurface { done.countDown() }; done.await(1, TimeUnit.SECONDS) }
        return true
    }
    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
}

/**
 * THE TWO HANDSETS BESIDE A NAME (iOS CallInlineHandset, MontanaCall 5638-5676): with a call folded, green left of the name
 * returns to it, red right ends it and asks first, in the platform's own dialog; the face 26, the finger's target 44.
 * A null peer: any folded call (the chat's head); a peer: only the call with that person (the list's row).
 */
fun callHandset(act: MainActivity, green: Boolean, peer: String?): View = FrameLayout(act).apply {
    val c: Context = act
    addView(FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (green) SysColor.green else SysColor.red) }
        addView(c.icon(if (green) R.drawable.ic_peer_phone else R.drawable.ic_phone_down, Color.WHITE, 12), FrameLayout.LayoutParams(dp(12), dp(12), Gravity.CENTER))
    }, FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER))
    contentDescription = c.getString(if (green) R.string.call_pill else R.string.call_end)
    val update = { val f = CallScreen.foldedRef; visibility = if (f != null && (peer == null || peer == f)) View.VISIBLE else View.GONE }
    update()
    pressable {
        if (green) CallScreen.unfold(act)
        else android.app.AlertDialog.Builder(c).setTitle(R.string.call_end_ask)
            .setPositiveButton(R.string.call_end) { _, _ -> Thread { Calls.hangUp(if (peer == null) "handset-chat" else "handset-row") }.start() }
            .setNegativeButton(android.R.string.cancel, null).show()
    }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { CallScreen.watchFold(update); update() }
        override fun onViewDetachedFromWindow(v: View) { CallScreen.unwatchFold(update) }
    })
}
