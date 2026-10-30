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
        pressable { onEmojiKey?.invoke() ?: showKeys() }
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
        setPadding(dp(16), dp(BAR_PAD), dp(16), dp(BAR_PAD))
        // A TAP BESIDE THE FIELD IS A TAP ON IT (iOS MontanaConversation 2834-2839, atom 0203ae019f6b, the author's word 20.09):
        // the bar's own room above and below the field and the gaps between the keys wake the field; the keys and the field
        // stand over this ground and take their own touches first
        setOnClickListener { if (!field.hasFocus() && !record.active) showKeys() }
        field.apply {
            hint = c.getString(R.string.message_hint)
            setHintTextColor(MT.gray); setTextColor(Color.WHITE)
            textSize = FONT
            // THE LINE IS 21 (iOS MTInputField.minH): in the font's own unit, so a larger font size of the phone grows it with the words
            if (android.os.Build.VERSION.SDK_INT >= 28) lineHeight = Math.round(android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, LINE, resources.displayMetrics))
            background = null
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            minHeight = dp(TIER)
        }
        plate.background = c.glassPlate().apply { cornerRadius = dp(18).toFloat() }
        plate.addView(field, FrameLayout.LayoutParams(MATCH, WRAP))
        plate.addView(emojiInside, FrameLayout.LayoutParams(dp(TIER), dp(TIER), Gravity.BOTTOM or Gravity.END))

        sendColumn.addView(send, FrameLayout.LayoutParams(dp(TIER), dp(TIER), Gravity.CENTER))
        sendColumn.addView(record, FrameLayout.LayoutParams(dp(TIER), dp(TIER), Gravity.CENTER))

        addView(fieldRow, lp())
        addView(actionRow, lp().apply { topMargin = dp(TIER_GAP) })

        field.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { syncSend() }
        })
        shape()
    }

    /**
     * THE WHOLE TIER IS THE FIELD (iOS MTInputField.inset): the room around the words is the field's own padding -- above and below
     * the tier less the line, halved (7.5); 16 at the start; at the end 46, the emoji key's side, or 16 where the key is not inside.
     */
    private fun inset(end: Int) {
        val v = (dp(TIER) - field.lineHeight) / 2f
        field.setPadding(dp(INSET_SIDE), Math.floor(v.toDouble()).toInt(), end, Math.ceil(v.toDouble()).toInt())
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
            inset(dp(INSET_SIDE))
            val keys = listOf(
                glassKey(R.drawable.ic_chevron_up, R.string.compose_fold) { if (!record.active) setOpen(false) },
                glassKey(R.drawable.ic_face_smiling, R.string.emoji) { onEmojiKey?.invoke() ?: showKeys() }.apply { emojiRowKey = this; setOnLongClickListener { onStickers?.invoke(); onStickers != null } },
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
            inset(dp(INSET_EMOJI))
            actionRow.visibility = View.GONE
        }
        syncSend()
        widenTouchTarget()
        if (panelOn) panelShown(true)   // the row's keys are made anew: the emoji key keeps the keyboard's glyph while the panel stands
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
    var onStickers: (() -> Unit)? = null   // the field's panel on the stickers, opened by a hold on the emoji key (Picker.kt)
    /** The emoji key's tap: the keyboard and the field's own panel swap places (iOS showEmoji.toggle()). */
    var onEmojiKey: (() -> Unit)? = null
    private var emojiRowKey: View? = null
    private var panelOn = false
    /** While the panel stands the emoji key wears the keyboard (iOS «keyboard» : «face.smiling», MontanaConversation.swift 809, 851). */
    fun panelShown(on: Boolean) {
        panelOn = on
        val res = if (on) R.drawable.ic_set_keyboard else R.drawable.ic_face_smiling
        emojiInside.setImageResource(res)
        ((emojiRowKey as? android.view.ViewGroup)?.getChildAt(0) as? ImageView)?.setImageResource(res)
    }
    /** The voice's deeds: start the tape (false — it could not start), and end it (true — dropped, not sent). */
    var onVoiceStart: (() -> Boolean)? = null
    var onVoiceEnd: ((Boolean) -> Unit)? = null
    /** The tape's time is up (the note's 6:39): the hold ends as if the finger let go. */
    /**
     * THE FIELD'S CEILING (iOS MTInputField.cap and fieldCap at 2308; atoms 46e0a8f8b3ce, 287fb11d4941): thirteen lines and the
     * field's own insets, never past the room -- the window's own height, the keyboard taken off once -- less the bar at rest for
     * the chosen shape and one tier of the feed, never below the tier. Both inputs are stable (the window, the keys), so the
     * field's growth never moves its own ceiling.
     */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val keys = rootWindowInsets?.getInsets(android.view.WindowInsets.Type.ime())?.bottom ?: 0
        val room = rootView.height - keys
        val most = field.lineHeight * LINES + field.paddingTop + field.paddingBottom
        val bar = if (open) dp(TIER + TIER_GAP + TIER) else dp(TIER)
        if (0 < room) field.maxHeight = maxOf(dp(TIER), minOf(most, room - bar - dp(TIER)))
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    fun stopRecording() = record.endHold()
    /** The bin of a locked tape (iOS «Cancel» on the bar's line): the tape is dropped. */
    fun cancelRecording() = record.cancelHold()
    /** The tape rolling is a round note, not a voice (iOS st.video). */
    val recordingNote: Boolean get() = record.note
    /** The reply at the ear starts a voice tape with no finger (iOS rec.begin(.voice, why: "ear")); false -- it could not start. */
    fun earStart(): Boolean = record.earStart()
    /** The phone left the ear: the tape stands locked for the screen to decide (iOS rec.lock(why: "ear")); false -- no tape rolls. */
    fun earLock(): Boolean = record.earLock()
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
                reach.recordReach = TouchDelegate(r, record)
                touchDelegate = reach
                // THE HOLD IS THE KEY'S, NOT THE SYSTEM'S BACK (measured on A1 09.10.2026 21:46 MSK: the key stands at the right edge,
                // where the platform's back gesture lives; it took the finger -- startBackNavigation -- and the tape was left locked):
                // the key and its reach are kept out of the system's edge gestures
                if (29 <= android.os.Build.VERSION.SDK_INT) systemGestureExclusionRects = listOf(Rect(r))
            }
        }
    }

    /**
     * THE FINGER'S ROOM HANGS OUTSIDE THE LAYOUT (iOS fingerRoom, MontanaConversation.swift 735-741, 798, 885 at 2155; the author's
     * word 23.09): every plate of the bar is the tier (36) and every plate's touch is the platform's least target (44) -- the four
     * points round each plate are its own, not the bar's ground (which wakes the field). The record key keeps its wider reach.
     * A touch that lands on a plate itself never comes here: the plate takes it.
     */
    private inner class Reach : TouchDelegate(Rect(), this@ChatInputBar) {
        var recordReach: TouchDelegate? = null
        private var held: View? = null
        private var toRecord = false
        private val box = Rect()
        private fun keys(): List<View> {
            val ks = if (open) (0 until actionRow.childCount).map { actionRow.getChildAt(it) }.filter { it is FrameLayout }
                     else listOf(unfoldKey, emojiInside, sendColumn)
            return ks.filter { it.visibility == View.VISIBLE && it.isAttachedToWindow && !(it === sendColumn && record.visibility == View.VISIBLE) }
        }
        private fun frame(v: View): Boolean {
            v.getDrawingRect(box)
            return runCatching { offsetDescendantRectToMyCoords(v, box) }.isSuccess
        }
        override fun onTouchEvent(e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                held = null; toRecord = false
                val room = (dp(TOUCH) - dp(TIER)) / 2
                for (k in keys()) if (frame(k)) {
                    box.inset(-room, -room)
                    if (box.contains(e.x.toInt(), e.y.toInt())) { held = k; break }
                }
                if (held == null) toRecord = recordReach?.onTouchEvent(e) == true
                if (held == null) return toRecord
            } else if (toRecord) {
                val r = recordReach?.onTouchEvent(e) == true
                if (e.actionMasked == MotionEvent.ACTION_UP || e.actionMasked == MotionEvent.ACTION_CANCEL) toRecord = false
                return r
            }
            val k = held ?: return false
            if (e.actionMasked == MotionEvent.ACTION_UP || e.actionMasked == MotionEvent.ACTION_CANCEL) held = null
            if (!frame(k)) return false
            val ev = MotionEvent.obtain(e)
            ev.offsetLocation(-box.left.toFloat(), -box.top.toFloat())
            // the plate's own centre when the finger is outside it: its click asks for a point inside it
            if (!box.contains(e.x.toInt(), e.y.toInt())) ev.setLocation(k.width / 2f, k.height / 2f)
            val r = k.dispatchTouchEvent(ev)
            ev.recycle()
            return r
        }
    }
    private val reach = Reach()

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
        private val st = RecState()   // the tape's one truth: the key, the ear and the page ask it and draw from it
        private val recording get() = st.phase != RecState.IDLE
        /** A HOLD ROLLING KEEPS THE ROW STILL (iOS MontanaConversation.swift:787,847 «guard !recording else
         * return», in unfoldKey and the fold arrow alike): a shape change under a rolling tape would move
         * the swollen button's own coordinates out from under the finger. Read by the two keys above. */
        val active: Boolean get() = recording
        private val recordingNote get() = st.note
        val note: Boolean get() = recordingNote
        private val locked get() = st.phase == RecState.LOCKED
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
                if (locked) { finish(cancel = false, why = "arrow"); return@setOnClickListener }
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
                    if (e.eventTime - lastDown < BOUNCE_MS) { processing = false; android.util.Log.d("Montana", "hold_down bounce"); return }
                    android.util.Log.d("Montana", "hold_down mode=" + (if (video) "video" else "mic") + " state=" + st.name() + " tape=" + st.tape)
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
                    if (dy < -LOCK_WAY_LIVE) { processing = false; lockTape("rose-live"); return }
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
                    else if (vy < -FLICK || dy < -LOCK_WAY_END) lockTape(if (vy < -FLICK) "flick" else "rose")
                    else finish(cancel = false)
                }
                MotionEvent.ACTION_CANCEL -> {
                    removeCallbacks(begin); if (!began) { scaleX = 1f; scaleY = 1f }
                    if (!processing) return
                    processing = false
                    // THE SYSTEM TOOK THE TOUCH, NOT THE PERSON (iOS 132-142): the tape is not thrown away — a second later it locks
                    // the late lock names its tape: a verdict born under an earlier tape is refused by that number (iOS lock(tape:))
                    if (began) { val t = st.tape; postDelayed({ lockTape("system-took", t) }, 1000) }
                }
            }
        }
        private fun start() {
            // the mark's mode decides the tape: the microphone's voice or the camera's round note (iOS MTComposeMark)
            val start = if (video) onNoteStart else onVoiceStart
            if (start == null) { processing = false; notYet(); return }
            st.begin(video, "hold")
            if (!start.invoke()) { st.end("start-failed"); processing = false; return }
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
        private fun lockTape(why: String, tape: Int? = null) {
            if (!st.lock(why, tape)) return
            rest(); field.hint = ""   // no «release to send» over a locked tape (iOS)
            onRecLocked?.invoke()
            performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
        }
        private fun finish(cancel: Boolean, why: String = if (cancel) "cancel" else "send") {
            if (!st.end(why)) return
            rest(); draw()
            onRecIdle?.invoke()
            field.isEnabled = true; field.hint = c.getString(R.string.message_hint); field.setHintTextColor(MT.gray)
            if (recordingNote) onNoteEnd?.invoke(cancel) else onVoiceEnd?.invoke(cancel)
        }
        fun endHold() = finish(cancel = false)
        fun cancelHold() = finish(cancel = true)
        fun earStart(): Boolean {
            if (recording) return false
            val start = onVoiceStart ?: return false
            st.begin(false, "ear")   // a voice, whatever the key's mode (iOS .voice)
            if (!start.invoke()) { st.end("start-failed"); return false }
            field.isEnabled = false; draw()
            return true
        }
        fun earLock(): Boolean {
            if (!recording || recordingNote) return false
            lockTape("ear")
            return true
        }
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

    /**
     * ONE STATE OF A RECORDING, ONE OWNER (iOS MontanaRecording, atom 858fd5f25ef6): idle → recording(kind) → locked(kind) → idle.
     * The key, the ear and the page only ask it (begin / lock / end) and draw from it; nobody keeps a copy. Every move is one diary
     * line, rec_state, and every tape has a number: a lock named for an older tape (the system's late lock) is refused by it.
     */
    private class RecState {
        var phase = IDLE; private set
        var note = false; private set
        var tape = 0; private set
        fun begin(note: Boolean, why: String) { if (phase != IDLE) return; tape = ++tapes; this.note = note; move(RECORDING, why) }
        fun lock(why: String, named: Int? = null): Boolean {
            if (named != null && named != tape) { android.util.Log.d("Montana", "rec_state refused lock tape=$named now=$tape why=$why"); return false }
            if (phase != RECORDING) return false
            move(LOCKED, why); return true
        }
        fun end(why: String): Boolean { if (phase == IDLE) return false; move(IDLE, why); return true }
        fun name(p: Int = phase) = when (p) { RECORDING -> "recording-"; LOCKED -> "locked-"; else -> "idle" } + if (p == IDLE) "" else if (note) "note" else "voice"
        private fun move(to: Int, why: String) {
            android.util.Log.d("Montana", "rec_state " + name() + "→" + name(to) + " why=" + why + " tape=" + tape)
            phase = to
        }
        companion object {
            const val IDLE = 0
            const val RECORDING = 1
            const val LOCKED = 2
            private var tapes = 0   // grows on every begin, across every bar: tape numbers never repeat in one run
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
        // THE ONE OWNER OF THE COMPOSE TIER (iOS MTInputField 2499-2543): every number of the row lives here and nowhere else
        const val TIER = 36                                // iOS MontanaOctagon.composeHeight
        const val FONT = 17f                               // iOS MTInputField.fontSize
        const val LINE = 21f                               // iOS MTInputField.minH: one line of words
        const val LINES = 13                               // iOS MTInputField.lines: the field grows to thirteen, then scrolls inside
        const val INSET_SIDE = 16                          // iOS MTInputField.inset.left
        const val INSET_EMOJI = 46                         // iOS MTInputField.inset.right: the emoji key's side
        const val BAR_PAD = 8                              // iOS MTInputField.barPad: the bar's breathing room above and below
        const val TIER_GAP = 6                             // iOS MTInputField.tierGap: between the words and the keys
        const val TOUCH = 44                               // iOS montanaTouchTarget: the platform's least target
        val GLYPH = Color.rgb(204, 204, 204)               // iOS MontanaOctagon.barGlyph
        const val OPEN_KEY = "composeOpen"
        const val MODE_KEY = "composeMediaMode"            // iOS @AppStorage("composeMediaMode")
    }
}
