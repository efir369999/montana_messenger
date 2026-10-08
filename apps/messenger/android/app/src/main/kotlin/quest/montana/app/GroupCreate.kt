package quest.montana.app

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ScrollView

// ─────────────────────────── a group is born (iOS MTGroupPickStep, MTGroupNameStep) ───────────────────────────

/**
 * The people a group can carry to (iOS MTGroupPickStep.reachable): a conversation whose pipe this phone holds — a group letter
 * rides each member's own pipe, and a person without one could be shown as a member and never receive a word.
 */
private fun reachable(adding: String?): List<Chat> = chatRows().filter {
    Book.secret(SamePair.root(it.ref)) != null && (adding == null || !Groups.carriesTo(it.ref, adding))   // adding: its own people are not listed again
}

/** A step's bar (iOS the sheet's toolbar): the cross or the back on the left, the title, the tick on the right — dim and deaf until it may act. */
private class StepBar(c: Context, title: String, back: Boolean, onLead: () -> Unit, onDone: () -> Unit) : FrameLayout(c) {
    private val tick = c.icon(R.drawable.ic_check, Color.WHITE)
    init {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(if (back) R.drawable.ic_arrow_back_ios_new else R.drawable.ic_close, Color.WHITE).apply {
            setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onLead)
        }, LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), LayoutParams(WRAP, WRAP, Gravity.CENTER))
        tick.setPadding(dp(10), dp(10), dp(10), dp(10))
        tick.pressable { if (tick.alpha == 1f) onDone() }
        addView(tick, LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    fun ready(on: Boolean) { tick.alpha = if (on) 1f else 0.4f }
}

/** A step's page (iOS a sheet's List on the page's ground): the crest behind, the bar, the body that scrolls. */
private fun stepFrame(c: Context, bar: View, body: View): View = FrameLayout(c).apply {
    setBackgroundColor(Color.BLACK)
    addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
    addView(c.vstack(Gravity.NO_GRAVITY) {
        addView(bar, lp(MATCH, dp(52)))
        addView(body, lp(MATCH, 0, 1f))
    }, FrameLayout.LayoutParams(MATCH, MATCH))
}

/** A person to choose (iOS MTPickRow): the face, the name, and the platform's circle — white with its tick when chosen. */
private fun pickRow(c: Context, ch: Chat, on: Boolean, onTap: () -> Unit): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(6), dp(16), dp(6))
    minimumHeight = dp(52)
    addView(c.peerFace(ch.ref, ch.shown, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
    addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a person's name
    addView(FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; if (on) setColor(Color.WHITE) else setStroke(dp(1.5f), MT.gray) }
        if (on) addView(c.icon(R.drawable.ic_check, Color.BLACK, 14), FrameLayout.LayoutParams(dp(14), dp(14), Gravity.CENTER))
    }, lp(dp(24), dp(24)))
    pressable(onTap)
}

/**
 * THE FIRST STEP — THE PEOPLE (iOS MTGroupPickStep, the author's word 05.10.2026: «choose Contacts to add to the group»): each
 * chosen by a tick, the search over them, the tick that goes on to the name. `onCreated` — the group's key, once it is born.
 * `adding` — the group people are added to from its page (iOS MTGroupPickStep(adding:) → MTGroup.add): the tick ends the choosing.
 */
fun groupPickPage(act: MainActivity, onClose: () -> Unit, onCreated: (String) -> Unit, adding: String? = null): View {
    val c: Context = act
    val people = reachable(adding)
    val chosen = linkedSetOf<String>()
    val rows = c.vstack(Gravity.NO_GRAVITY)
    var query = ""
    lateinit var bar: StepBar
    fun fill() {
        rows.removeAllViews()
        val q = query.trim()
        people.filter { q.isEmpty() || it.shown.contains(q, ignoreCase = true) }.forEachIndexed { i, ch ->
            if (i > 0) rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(68) })
            rows.addView(pickRow(c, ch, ch.ref in chosen) {
                if (!chosen.remove(ch.ref)) chosen.add(ch.ref)
                bar.ready(chosen.isNotEmpty())
                fill()
            }, lp())
        }
    }
    bar = StepBar(c, c.getString(R.string.gr_choose), back = false, onLead = onClose) {
        val picked = people.filter { it.ref in chosen }
        if (adding != null) { Groups.add(adding, picked.map { it.ref }); onClose() }
        else act.push { back -> groupNamePage(act, picked, back) { key -> back(); onClose(); onCreated(key) } }
    }
    bar.ready(false)
    val search = EditText(c).apply {
        hint = c.getString(R.string.search)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = c.rounded(Color.argb(61, 118, 118, 128), 10)
        setPadding(c.dp(12), c.dp(8), c.dp(12), c.dp(8))
        isSingleLine = true
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { query = s?.toString() ?: ""; fill() }
        })
    }
    fill()
    val body = ScrollView(c).apply {
        addView(c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), 0, dp(16), dp(32))
            addView(search, lp())
            gap(12)
            addView(c.plate { addView(rows, lp()) }, lp())
            addView(c.text(c.getString(R.string.gr_pick_note), 12f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) }, lp())
        })
    }
    return stepFrame(c, bar, body)
}

/** THE SECOND STEP (iOS MTGroupNameStep): the group's face and name above the people chosen, and the tick that creates it. */
private fun groupNamePage(act: MainActivity, members: List<Chat>, onBack: () -> Unit, onCreated: (String) -> Unit): View {
    val c: Context = act
    var face: ByteArray? = null
    val faceBox = FrameLayout(c)
    fun drawFace() {
        faceBox.removeAllViews()
        val bmp = face?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        // iOS MTFacePicker: the picture in a circle, or the camera on the platform's tertiary fill
        if (bmp != null) faceBox.addView(c.avatar(bmp, "", 60), FrameLayout.LayoutParams(c.dp(60), c.dp(60)))
        else faceBox.addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(61, 118, 118, 128)) }
            addView(c.icon(R.drawable.ic_add_a_photo, Color.WHITE), FrameLayout.LayoutParams(c.dp(24), c.dp(24), Gravity.CENTER))
        }, FrameLayout.LayoutParams(c.dp(60), c.dp(60)))
    }
    drawFace()
    faceBox.pressable {
        act.pickPhoto { uri ->
            val image = uri?.let { SelfFace.decode(act, it) } ?: return@pickPhoto
            lateinit var close: () -> Unit
            close = act.overlay(cropPage(act, image) { jpeg -> close(); if (jpeg != null) { face = jpeg; drawFace() } })
        }
    }
    lateinit var bar: StepBar
    val name = EditText(c).apply {
        hint = c.getString(R.string.gr_name)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        isSingleLine = true
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { bar.ready(!s.isNullOrBlank()) }
        })
    }
    bar = StepBar(c, c.getString(R.string.gr_new), back = true, onLead = onBack) {
        c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(name.windowToken, 0)
        Groups.create(channel = false, title = name.text.toString(), about = "", face = face, people = members.map { it.ref })?.let(onCreated)
    }
    bar.ready(false)
    val people = c.vstack(Gravity.NO_GRAVITY)
    members.forEachIndexed { i, ch ->
        if (i > 0) people.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(68) })
        people.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(6), dp(16), dp(6))
            minimumHeight = dp(52)
            addView(c.peerFace(ch.ref, ch.shown, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
            addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a person's name
        }, lp())
    }
    val body = ScrollView(c).apply {
        addView(c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), 0, dp(16), dp(32))
            addView(c.plate {
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(16), dp(10), dp(16), dp(10))
                    addView(faceBox, lp(dp(60), dp(60)))
                    gap(14)
                    addView(name, lp(0, WRAP, 1f))
                }, lp())
            }, lp())
            addView(c.text(c.getString(R.string.gr_people), 13f, MT.gray).apply { setPadding(dp(16), dp(22), dp(16), dp(6)) }, lp())
            addView(c.plate { addView(people, lp()) }, lp())
        })
    }
    // the name's field takes the keys at once (iOS typing = true on appear)
    name.post { name.requestFocus(); c.getSystemService(InputMethodManager::class.java).showSoftInput(name, 0) }
    return stepFrame(c, bar, body)
}
