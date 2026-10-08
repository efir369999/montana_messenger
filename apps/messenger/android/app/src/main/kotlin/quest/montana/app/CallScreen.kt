package quest.montana.app

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
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
        close = act.overlay(callPage(act, ref))
    }

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
        val state = c.text("", 17f, Color.WHITE, bold = true, center = true).apply { singleLineEllipsis() }
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
        // ── the video branch's top (iOS 6660-6696): the name in the row's centre, the time under it, the events under that ──
        val title = c.text(name, 32f, Color.WHITE).apply {   // USER-DATA: the peer's name
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
        val back = mark(c, R.drawable.ic_chevron_down, R.string.call_back) { close?.invoke() }
        val flip = mark(c, R.drawable.ic_camera_rotate, R.string.call_camera) { CallLine.switchCamera() }
        val roomL = View(c)   // the mask's twin room keeps the name in the centre (iOS 6665); the mask itself is not in this build
        val roomR = View(c)
        val route = routeButton(c)
        fun line() {
            val tint = if (CallLine.lost) SysColor.red else SysColor.green   // iOS MTCallLight: red while the link is lost
            light.setColorFilter(tint)
            vlight.setColorFilter(tint)
            val since = CallLine.connectedAt
            val tail = if (since > 0L) ((System.currentTimeMillis() - since) / 1000).toInt().let { String.format(Locale.ROOT, "%d:%02d", it / 60, it % 60) }
                else c.getString(Calls.stage() ?: R.string.call_connecting)   // «Calling…», «Ringing…», then «Connecting…»
            status.text = c.getString(R.string.call_title_audio) + " — " + tail
            clock.text = tail
            route.second.invoke()
            // under the name, the call's own state in bold (iOS 6725-6738); a video call's one line puts a break before a hold (5357)
            val held = CallLine.held || CallLine.heldByPeer
            val word = if (held) R.string.call_on_hold else if (CallLine.lost) R.string.call_lost else null
            state.visibility = if (word == null) View.GONE else View.VISIBLE
            if (word != null) state.text = c.getString(word)
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
            addView(roomR, lp(dp(44), dp(44)))
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
        val miniBox = FrameLayout(c).apply {
            setBackgroundColor(Color.BLACK)
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(v: View, o: Outline) { o.setRoundRect(0, 0, v.width, v.height, v.dp(12).toFloat()) }
            }
            clipToOutline = true
            foreground = c.rounded(Color.TRANSPARENT, 12, Color.argb(64, 255, 255, 255))
            addView(mini, FrameLayout.LayoutParams(MATCH, MATCH))
            visibility = View.GONE
        }
        val shade = View(c).apply {
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(Color.argb(89, 0, 0, 0), Color.TRANSPARENT, Color.argb(115, 0, 0, 0)))
        }
        val tap = View(c).apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        val pictures = FrameLayout(c).apply {
            addView(big, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
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
        // WHICH PICTURE FILLS WHICH SLOT has one owner (iOS CallUIModel.applySides 5512): their picture, once drawn, fills the
        // screen and mine rides the corner — until the corner is tapped; before theirs comes, mine fills the screen
        fun sides() {
            // the sharer sees the peer's ground, not the screen it shares (iOS 6566-6574): no picture is drawn
            if (CallLine.sharing) { CallLine.theirs.into = null; CallLine.own.into = null; miniBox.visibility = View.GONE; return }
            val pip = CallLine.video && CallLine.remoteLive
            val shown = pip && !CallLine.peerSharing && CallLine.camera
            val bigLocal = !pip || (CallLine.swapped && shown)
            CallLine.theirs.into = if (!pip) null else if (bigLocal) mini else big
            CallLine.own.into = if (bigLocal) big else if (shown) mini else null
            big.mirror(bigLocal && CallLine.front)
            mini.mirror(!bigLocal && CallLine.front)
            big.fit = !bigLocal && CallLine.peerSharing   // a shared screen is fitted on black, never cut
            miniBox.visibility = if (shown) View.VISIBLE else View.GONE
            shade.visibility = if (!shown && !CallLine.peerSharing) View.VISIBLE else View.GONE
        }
        // THE CORNER PICTURE'S PLACE, THE 2155 FORM (iOS MTCallMini, MontanaCall.swift 6321-6338): one fact for each edge,
        // read off chromeVisible, not a number measured a frame late -- the top panel up: ten points under its measured
        // bottom; buttons up (CallUIModel.buttonsTop, 6879-6880): ten points over the grid's own measured top; either
        // edge down: fourteen off the safe side. Where the buttons stand, the touch is theirs (6406-6428, blockRect):
        // Android needs no such mask -- column is laid out after pictures, so a button under the finger claims the
        // touch before it ever reaches miniBox underneath.
        var placed = false
        fun placeMini(glide: Boolean) {
            if (miniBox.visibility != View.VISIBLE || pictures.width == 0) return
            val up = column.visibility == View.VISIBLE
            val topEdge = if (up && events.bottom > 0) events.bottom + c.dp(10) else column.paddingTop + c.dp(14)
            val raised = if (grid.top > 0) grid.top - c.dp(10) else pictures.height - column.paddingBottom - c.dp(220)
            val bottomEdge = if (up) raised else pictures.height - column.paddingBottom - c.dp(14)
            val x = (if (corner % 2 == 0) c.dp(14) else pictures.width - c.dp(14) - c.dp(MINI_W)).toFloat()
            val y = (if (corner < 2) topEdge else maxOf(topEdge, bottomEdge - c.dp(MINI_H))).toFloat()
            if (glide && placed) miniBox.animate().translationX(x).translationY(y).setDuration(300).start()
            else { miniBox.animate().cancel(); miniBox.translationX = x; miniBox.translationY = y }
            placed = true
        }
        var foldAt = 0L
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
            roomL.visibility = head; title.visibility = head; roomR.visibility = head
            flip.visibility = if (v && !screen && CallLine.camera) View.VISIBLE else View.INVISIBLE
            timeLine.visibility = if (v && !screen) View.VISIBLE else View.GONE
            events.visibility = timeLine.visibility
            voiceHead.visibility = if (v || mine) View.GONE else View.VISIBLE
            grid.visibility = if (screen) View.GONE else View.VISIBLE
            stopShare.visibility = if (mine) View.VISIBLE else View.GONE
            askPlate.visibility = if (CallLine.asked && !screen) View.VISIBLE else View.GONE
            turnPlate.visibility = if (CallLine.offerMine && v && !screen) View.VISIBLE else View.GONE
            page.keepScreenOn = v   // iOS applyScreenHold: a video call holds the screen awake
            sides()
            videoLit?.invoke()
            page.post { placeMini(true) }
        }
        again = { redraw() }
        // the picture is the switch (iOS 6602-6610): a tap hides the buttons, the next brings them back
        tap.setOnClickListener { chromeHidden = !chromeHidden; foldAt = 0L; redraw() }
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
                        if (!dragging) { v.performClick(); CallLine.swapped = !CallLine.swapped; sides() }
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
            val want = CallLine.video && CallLine.connectedAt > 0L && !CallLine.peerSharing && !CallLine.sharing && !CallLine.asked &&
                !CallLine.offerMine && !chromeHidden
            if (!want) { foldAt = 0L; return }
            val now = System.currentTimeMillis()
            if (foldAt == 0L) foldAt = now + FOLD_MS
            else if (now >= foldAt) { foldAt = 0L; chromeHidden = true; redraw() }
        }
        line()
        var live = true
        MainThread.later(1000, object : Runnable {
            override fun run() { if (!live) return; line(); fold(); MainThread.later(1000, this) }
        })
        val hook: () -> Unit = { line(); redraw() }
        // the page goes by the fold, by the system's back or by the call's end; a call still in hand leaves its pill
        page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { CallLine.changed = hook; redraw() }
            override fun onViewDetachedFromWindow(v: View) {
                live = false
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
    private fun mark(c: Context, glyph: Int, label: Int, work: () -> Unit) = FrameLayout(c).apply {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(label)
        addView(c.icon(glyph, Color.WHITE, 22), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
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
    private fun ground(c: Context, ref: String, name: String): View = FrameLayout(c).apply {
        background = GradientDrawable(GradientDrawable.Orientation.TR_BL, intArrayOf(Color.rgb(33, 38, 48), Color.rgb(41, 51, 71), Color.rgb(26, 28, 33)))
        val face = Book.shownFace(ref).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
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
            addView(c.text(name.take(1).uppercase(), 160f, Color.argb(56, 255, 255, 255), bold = true, center = true),   // USER-DATA: the name's first letter
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
