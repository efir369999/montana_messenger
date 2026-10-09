package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Rect
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.TouchDelegate
import android.view.View
import android.view.VelocityTracker
import android.view.ViewOutlineProvider
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import kotlin.math.abs

/**
 * THE COMPOSE BAR (iOS ChatInputBar): one bar for every chat, in two shapes the person chooses with its own arrow — and the
 * choice outlives the chat and the launch (iOS: «the row is folded or open by the person's own choice»).
 *
 *   folded:  [⌄] [ the words ………… ☺ ] [🎙 / ➤]
 *   open:    [ the words across the whole width ]
 *            [⌃]  ☺  🖼  🪪  📄  ➤  👤  [🎙 / ➤]
 *
 * The send artwork stands at the end while there are words; without them, the recording button — a tap switches the voice and
 * the video message (iOS composeMediaMode). The field itself never leaves its place: only what stands around it changes.
 */
class ChatInputBar(private val act: MainActivity, val field: EditText, private val onSend: () -> Unit) : LinearLayout(act) {
    private val c: Context = act
    private var open = Prefs.bool(OPEN_KEY, false)

    private val fieldRow = LinearLayout(c).apply { orientation = HORIZONTAL; gravity = Gravity.BOTTOM }
    private val actionRow = LinearLayout(c).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private val plate = FrameLayout(c)                 // the field's glass, with the emoji key inside while folded
    private val unfoldKey = glassKey(R.drawable.ic_chevron_down, R.string.compose_open) { if (!record.active) setOpen(true) }
    private val emojiInside = ImageView(c).apply {
        setImageResource(R.drawable.ic_face_smiling); imageTintList = android.content.res.ColorStateList.valueOf(GLYPH)
        contentDescription = c.getString(R.string.emoji)
        setPadding(dp(9), dp(9), dp(9), dp(9))
        pressable { showKeys() }
        setOnLongClickListener { onStickers?.invoke(); onStickers != null }   // a hold on the emoji key: the stickers
    }
    private val sendColumn = FrameLayout(c)
    private val send = ImageView(c).apply {
        setImageResource(R.drawable.send_button); scaleType = ImageView.ScaleType.FIT_CENTER
        contentDescription = c.getString(R.string.send)
        pressable { if (field.text.isNotBlank() || attached) onSend() }
        setOnLongClickListener { if (field.text.isNotBlank()) onSendLater?.invoke(it); onSendLater != null }   // a hold: «Send later» (iOS)
    }
    private val record = RecordKey(c)

    init {
        orientation = VERTICAL
        setPadding(dp(16), dp(6), dp(16), dp(8))
        // A TAP BESIDE THE FIELD IS A TAP ON IT (iOS MontanaConversation 2834-2839, atom 0203ae019f6b, the author's word 20.09):
        // the bar's own room above and below the field and the gaps between the keys wake the field; the keys and the field
        // stand over this ground and take their own touches first
        setOnClickListener { if (!field.hasFocus() && !record.active) showKeys() }
        field.apply {
            hint = c.getString(R.string.message_hint)
            setHintTextColor(MT.gray); setTextColor(Color.WHITE)
            textSize = 17f
            background = null
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            maxLines = 6
            minHeight = dp(TIER)
        }
        plate.background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }
        plate.addView(field, FrameLayout.LayoutParams(MATCH, WRAP))
        plate.addView(emojiInside, FrameLayout.LayoutParams(dp(TIER), dp(TIER), Gravity.BOTTOM or Gravity.END))

        sendColumn.addView(send, FrameLayout.LayoutParams(dp(TIER), dp(TIER), Gravity.CENTER))
        sendColumn.addView(record, FrameLayout.LayoutParams(dp(TIER), dp(TIER), Gravity.CENTER))

        addView(fieldRow, lp())
        addView(actionRow, lp().apply { topMargin = dp(10) })

        field.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { syncSend() }
        })
        shape()
    }

    /** The one writer of the shape is the finger (iOS composeOpen); it is kept for the next chat and the next launch. */
    private fun setOpen(v: Boolean) {
        open = v
        Prefs.setBool(OPEN_KEY, v)
        shape()
    }

    private fun shape() {
        (sendColumn.parent as? LinearLayout)?.removeView(sendColumn)
        (unfoldKey.parent as? LinearLayout)?.removeView(unfoldKey)
        (plate.parent as? LinearLayout)?.removeView(plate)
        fieldRow.removeAllViews(); actionRow.removeAllViews()
        if (open) {
            // the words take the whole upper tier; the room of the emoji key is given back to them
            fieldRow.addView(plate, lp(0, WRAP, 1f))
            emojiInside.visibility = View.GONE
            field.setPadding(dp(14), dp(8), dp(14), dp(8))
            val keys = listOf(
                glassKey(R.drawable.ic_chevron_up, R.string.compose_fold) { if (!record.active) setOpen(false) },
                glassKey(R.drawable.ic_face_smiling, R.string.emoji) { showKeys() }.apply { setOnLongClickListener { onStickers?.invoke(); onStickers != null } },
                glassKey(R.drawable.ic_compose_photo, R.string.gallery) { onGallery?.invoke() ?: notYet() },
                glassKey(R.drawable.ic_compose_card, R.string.business_card) { onCard?.invoke() ?: notYet() },
                glassKey(R.drawable.ic_compose_doc, R.string.file) { onFile?.invoke() ?: notYet() },
                glassKey(R.drawable.ic_compose_location, R.string.location) { onLocation?.invoke() ?: notYet() },
                glassKey(R.drawable.ic_compose_contact, R.string.contact) { onContact?.invoke() ?: notYet() },
                sendColumn)
            // the first and the last flush with the row's edges, the ones between shared evenly
            keys.forEachIndexed { i, k ->
                if (i > 0) actionRow.addView(View(c), lp(0, 1, 1f))
                actionRow.addView(k, lp(dp(TIER), dp(TIER)))
            }
            actionRow.visibility = View.VISIBLE
        } else {
            fieldRow.addView(unfoldKey, lp(dp(TIER), dp(TIER)).apply { marginEnd = dp(10) })
            fieldRow.addView(plate, lp(0, WRAP, 1f))
            fieldRow.addView(sendColumn, lp(dp(TIER), dp(TIER)).apply { marginStart = dp(10) })
            emojiInside.visibility = View.VISIBLE
            field.setPadding(dp(14), dp(8), dp(TIER + 4), dp(8))
            actionRow.visibility = View.GONE
        }
        syncSend()
        widenTouchTarget()
    }

    /** Pictures wait above the field (iOS hasAttachment): the send artwork stands even without words — it sends them. */
    var attached = false
        set(v) { field = v; syncSend() }

    /** Words or a waiting picture → the send artwork; neither → the recording button (iOS sendColumn). */
    fun syncSend() {
        val words = this.field.text.isNotBlank() || attached
        send.visibility = if (words) View.VISIBLE else View.GONE
        record.visibility = if (words) View.GONE else View.VISIBLE
    }

    private fun showKeys() {
        field.requestFocus()
        c.getSystemService(InputMethodManager::class.java).showSoftInput(field, 0)
    }

    /** What iOS does here and Android does not do yet says so in words instead of doing nothing. */
    /** The gallery and file keys' deeds, given by the page that owns the letters (the conversation sends media). */
    var onGallery: (() -> Unit)? = null
    /** The place key (iOS onLocation → MTLocationPicker): this spot as a letter. */
    var onLocation: (() -> Unit)? = null
    var onSendLater: ((View) -> Unit)? = null   // the send key's hold (Schedule.kt)
    var onContact: (() -> Unit)? = null   // the phone's contact as a letter (iOS ContactPicker)
    var onFile: (() -> Unit)? = null
    /** The card key (iOS .card → MontanaCardNoteView with onSend): the person's business card, sent as a photo. */
    var onCard: (() -> Unit)? = null
    var onStickers: (() -> Unit)? = null   // the sticker panel, opened by a hold on the emoji key (Stickers.kt)
    /** The voice's deeds: start the tape (false — it could not start), and end it (true — dropped, not sent). */
    var onVoiceStart: (() -> Boolean)? = null
    var onVoiceEnd: ((Boolean) -> Unit)? = null
    /** The tape's time is up (the note's 6:39): the hold ends as if the finger let go. */
    fun stopRecording() = record.endHold()
    /** The bin of a locked tape (iOS «Cancel» on the bar's line): the tape is dropped. */
    fun cancelRecording() = record.cancelHold()
    /** THE LOCK (iOS MTHoldOverlayView lockPlate): the finger's way up, 0…1, shown over the key; 1 — the tape rolls hands-free. */
    var onRecLift: ((Float) -> Unit)? = null
    var onRecLocked: (() -> Unit)? = null
    /** The tape ended (sent, dropped, or cut by its minute): the page takes its lock and its controls away. */
    var onRecIdle: (() -> Unit)? = null

    /** The round note's deeds, the same shape as the voice's (iOS MontanaVideoNoteHold under the held camera mark). */
    var onNoteStart: (() -> Boolean)? = null
    var onNoteEnd: ((Boolean) -> Unit)? = null

    private fun notYet() = Toast.makeText(c, R.string.compose_not_yet, Toast.LENGTH_SHORT).show()

    /**
     * THE TARGET IS WIDER THAN THE PLATFORM'S LEAST (iOS MontanaHoldControl.point(inside:), MontanaHoldControl.swift:69-75
     * at 2155, the author's word 22.09: «I do not always hit it»): the record key's own frame stays 36dp, but the finger
     * lands on it a little past its top and left edges and well past its right and bottom ones (iOS: -10/-8/+40/+16 pt).
     */
    private fun widenTouchTarget() {
        record.post {
            val r = Rect()
            record.getDrawingRect(r)   // the key's own frame, carried into the bar's coordinates below
            if (runCatching { offsetDescendantRectToMyCoords(record, r) }.isSuccess) {
                r.left -= dp(10); r.top -= dp(8); r.right += dp(40); r.bottom += dp(8)
                touchDelegate = TouchDelegate(r, record)
                // THE HOLD IS THE KEY'S, NOT THE SYSTEM'S BACK (measured on A1 09.10.2026 21:46 MSK: the key stands at the right edge,
                // where the platform's back gesture lives; it took the finger -- startBackNavigation -- and the tape was left locked):
                // the key and its reach are kept out of the system's edge gestures
                if (29 <= android.os.Build.VERSION.SDK_INT) systemGestureExclusionRects = listOf(Rect(r))
            }
        }
    }

    /** A HOLD TOO SHORT FOR A TAPE (iOS tooShortTape, MontanaConversation.swift:3909-3919 at 2155, atom 3f439964b9a6):
     * the platform's warning tap and the field's own word, instead of silence. */
    fun tooShortHint() {
        field.performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30) android.view.HapticFeedbackConstants.REJECT else android.view.HapticFeedbackConstants.LONG_PRESS)
        field.hint = c.getString(R.string.hold_to_record)   // in the placeholder's own grey, as the iPhone's (MontanaConversation.swift:911)
        MainThread.later(1600) { field.hint = c.getString(R.string.message_hint) }
    }

    /** One round glass key at the tier's height with the grey glyph (iOS .montanaOctagon(square: true, bar: true)). */
    private fun glassKey(res: Int, label: Int, onTap: () -> Unit): View = FrameLayout(c).apply {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(label)
        addView(c.icon(res, GLYPH), FrameLayout.LayoutParams(dp(21), dp(21), Gravity.CENTER))
        pressable(onTap)
    }

    /**
     * THE RECORDING BUTTON (iOS MTComposeMark .voice / .video under MontanaHoldControl): the artwork, grown by a third and cut round.
     * It tracks its own touch as the iOS control does (MontanaHoldControl 25-149, the author's word 19.09): a press shorter than 0.19 s
     * is a tap — it switches the microphone and the camera, and the choice is remembered; a longer one records. Held, the key is the
     * send artwork riding up with the finger towards the lock and fading towards the bin (iOS swollen, MTHoldOverlayView 941-965).
     * ONE VERDICT WHEN THE FINGER LEAVES, on the dominant axis only: a hundred points left or a flick left past four hundred a second
     * drops the tape, sixty up or a flick up locks it, anything else sends; on the way, a hundred and fifty left drops and a hundred
     * and ten up locks. The system taking the touch never throws a tape away: a second later it locks and rolls on.
     */
    private inner class RecordKey(c: Context) : FrameLayout(c) {
        private val face = ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
        private var recording = false
        /** A HOLD ROLLING KEEPS THE ROW STILL (iOS MontanaConversation.swift:787,847 «guard !recording else
         * return», in unfoldKey and the fold arrow alike): a shape change under a rolling tape would move
         * the swollen button's own coordinates out from under the finger. Read by the two keys above. */
        val active: Boolean get() = recording
        private var recordingNote = false
        private var locked = false
        private var processing = false   // this touch is still the key's to judge
        private var began = false        // the press outlived the mode timeout: a tape was asked for
        private var lastDown = 0L
        private var downX = 0f
        private var downY = 0f
        private var velocity: VelocityTracker? = null
        private val begin = Runnable { if (processing) { began = true; scaleX = 1f; scaleY = 1f; start() } }
        init {
            addView(face, LayoutParams(MATCH, MATCH))
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(v: View, o: Outline) { o.setOval(0, 0, v.width, v.height) }
            }
            draw()
            // the tap's deed, and an accessibility click's: a locked tape's key is its send arrow, otherwise the mark switches
            setOnClickListener {
                if (locked) { finish(cancel = false); return@setOnClickListener }
                VoiceTape.standDown()   // the hold ended as a tap: the readied tape is not wanted (iOS MontanaConversation.swift:1047 at 2155)
                Prefs.setStr(MODE_KEY, if (video) "mic" else "video")
                draw()
            }
            setOnTouchListener { v, e -> track(v, e); true }
        }
        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            // the swell rides above the bar (iOS: a window of its own over every layer): nothing between the key and the page cuts it
            var p = parent
            repeat(4) { (p as? android.view.ViewGroup)?.let { it.clipChildren = false; it.clipToPadding = false }; p = p?.parent }
        }
        private fun track(v: View, e: MotionEvent) {
            val d = resources.displayMetrics.density
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    // a second press right after the first is a bounce, not a hold (iOS 85-88)
                    if (e.eventTime - lastDown < BOUNCE_MS) { processing = false; return }
                    lastDown = e.eventTime
                    processing = true; began = false
                    downX = e.rawX; downY = e.rawY
                    velocity?.recycle(); velocity = VelocityTracker.obtain().also { it.addMovement(e) }
                    v.parent?.requestDisallowInterceptTouchEvent(true)
                    if (!locked) {
                        scaleX = 0.94f; scaleY = 0.94f; postDelayed(begin, MODE_TIMEOUT_MS)   // the small mark sinks under the finger
                        if (!video) VoiceTape.prewarm(act)   // the tape is readied while the timeout runs (iOS MontanaRecording.ready 88-91)
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    velocity?.addMovement(e)
                    if (!processing || !began) return
                    val dx = minOf(0f, (e.rawX - downX) / d)
                    val dy = minOf(0f, (e.rawY - downY) / d)
                    if (dx < -CANCEL_WAY_LIVE) { processing = false; finish(cancel = true); return }
                    if (dy < -LOCK_WAY_LIVE) { processing = false; lockTape(); return }
                    ride(minOf(1f, -dy / LOCK_WAY), dx < -CANCEL_WAY)
                }
                MotionEvent.ACTION_UP -> {
                    removeCallbacks(begin); if (!began) { scaleX = 1f; scaleY = 1f }
                    if (!processing) return
                    processing = false
                    if (!began) { performClick(); return }
                    var dx = minOf(0f, (e.rawX - downX) / d)
                    var dy = minOf(0f, (e.rawY - downY) / d)
                    // ONE AXIS DECIDES (iOS 121-123): a thumb rolling off the key diagonally is judged by its dominant way
                    if (abs(dx) > abs(dy)) dy = 0f else dx = 0f
                    val vt = velocity
                    vt?.addMovement(e); vt?.computeCurrentVelocity(1000)
                    val vx = (vt?.xVelocity ?: 0f) / d
                    val vy = (vt?.yVelocity ?: 0f) / d
                    if (vx < -FLICK || dx < -CANCEL_WAY) finish(cancel = true)
                    else if (vy < -FLICK || dy < -LOCK_WAY_END) lockTape()
                    else finish(cancel = false)
                }
                MotionEvent.ACTION_CANCEL -> {
                    removeCallbacks(begin); if (!began) { scaleX = 1f; scaleY = 1f }
                    if (!processing) return
                    processing = false
                    // THE SYSTEM TOOK THE TOUCH, NOT THE PERSON (iOS 132-142): the tape is not thrown away — a second later it locks
                    if (began) postDelayed({ lockTape() }, 1000)
                }
            }
        }
        private fun start() {
            // the mark's mode decides the tape: the microphone's voice or the camera's round note (iOS MTComposeMark)
            val start = if (video) onNoteStart else onVoiceStart
            if (start == null) { processing = false; notYet(); return }
            recordingNote = video
            recording = start.invoke()
            if (!recording) { processing = false; return }
            field.isEnabled = false
            draw(); ride(0f, false)
        }
        /** The swell under the finger (iOS swollen 941-965, «Release to send / cancel» over the strip): up with the finger, faint towards the bin. */
        private fun ride(lift: Float, away: Boolean) {
            translationY = -lift * dp(LOCK_WAY)
            alpha = if (away) 0.45f else 1f
            scaleX = if (away) 0.9f else 1f; scaleY = scaleX
            field.hint = c.getString(if (away) R.string.release_cancel else R.string.release_send)
            field.setHintTextColor(if (away) SysColor.red else Color.WHITE)
            onRecLift?.invoke(lift)
        }
        private fun rest() { translationY = 0f; alpha = 1f; scaleX = 1f; scaleY = 1f }
        /** Let go at the lock, or carried past it, or the system took the touch: the tape rolls on hands-free and this key sends it. */
        private fun lockTape() {
            if (!recording || locked) return
            locked = true; rest(); field.hint = ""   // no «release to send» over a locked tape (iOS)
            onRecLocked?.invoke()
            performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
        }
        private fun finish(cancel: Boolean) {
            if (!recording) return
            recording = false; locked = false
            rest(); draw()
            onRecIdle?.invoke()
            field.isEnabled = true; field.hint = c.getString(R.string.message_hint); field.setHintTextColor(MT.gray)
            if (recordingNote) onNoteEnd?.invoke(cancel) else onVoiceEnd?.invoke(cancel)
        }
        fun endHold() = finish(cancel = false)
        fun cancelHold() = finish(cancel = true)
        private val video get() = Prefs.str(MODE_KEY, "mic") == "video"
        /** While a tape rolls the key is the send artwork, whole (iOS swell: MTComposeMark .send); at rest the mode's artwork, cut round. */
        private fun draw() {
            face.scaleX = if (recording) 1f else 1.33f; face.scaleY = face.scaleX
            clipToOutline = !recording
            if (recording) { face.setImageResource(R.drawable.send_button); contentDescription = c.getString(R.string.send); return }
            face.setImageResource(if (video) R.drawable.video_record_button else R.drawable.voice_record_button)
            contentDescription = c.getString(if (video) R.string.record_video else R.string.record_voice)
        }
    }

    private companion object {
        const val LOCK_WAY = 72                            // iOS lockWay: the swell's way up to the lock plate, in points
        const val MODE_TIMEOUT_MS = 190L                   // iOS MontanaHoldControl.modeTimeout: a shorter press is a tap
        const val BOUNCE_MS = 400L                         // a press this soon after the last one is a bounce (iOS beginTracking)
        const val CANCEL_WAY = 100f                        // iOS cancelWay at the release, cancelWayLive on the way
        const val CANCEL_WAY_LIVE = 150f
        const val LOCK_WAY_END = 60f                       // iOS lockWayEnd at the release, lockWayLive on the way
        const val LOCK_WAY_LIVE = 110f
        const val FLICK = 400f                             // iOS flick, points a second
        const val TIER = 36                                // iOS MontanaOctagon.composeHeight
        val GLYPH = Color.rgb(204, 204, 204)               // iOS MontanaOctagon.barGlyph
        const val OPEN_KEY = "composeOpen"
        const val MODE_KEY = "composeMediaMode"            // iOS @AppStorage("composeMediaMode")
    }
}
