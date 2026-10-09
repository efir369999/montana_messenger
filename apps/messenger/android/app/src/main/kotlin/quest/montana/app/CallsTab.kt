package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.text.format.DateFormat
import android.text.format.DateUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ScrollView
import java.util.Calendar
import java.util.Date
import java.util.Locale

// ─────────────────────────── the calls under the bar (iOS CallsTabView, ContentView.swift 2839) ───────────────────────────

/** One call of the log (iOS CallRecord): the row each phone laid for itself in the conversation (Calls.row). */
private class CallRecord(val ref: String, val mid: String, val info: Calls.Info, val at: Long)

/** THE ONE CALL LOG (iOS ChatStore.callRecords 2652): every call's row of every conversation, newest first. */
private fun callRecords(): List<CallRecord> = Book.refs().flatMap { ref ->
    val msgs = Book.chat(ref)?.let { ch -> runCatching { ch.msgs.toList() }.getOrDefault(emptyList()) } ?: emptyList()
    msgs.mapNotNull { m -> Calls.info(m.text)?.let { CallRecord(ref, m.mid, it, m.at) } }
}.sortedByDescending { it.at }

/**
 * THE MISSED CALLS UNSEEN (iOS ChatStore.missedCallsUnseen and clearMissedCallsBadge, MontanaChatStore.swift:585-614): derived, never
 * a counter -- the incoming missed rows of the log newer than the moment the calls page was last seen; the first run of this
 * construction sees the past, as the iPhone's does.
 */
object CallsSeen {
    private const val KEY = "callsSeenAt"
    private fun stamp(): Long {
        Prefs.str(KEY, "").toLongOrNull()?.let { return it }
        val now = System.currentTimeMillis()
        Prefs.setStr(KEY, now.toString())
        return now
    }
    fun unseen(): Int { val t = stamp(); return callRecords().count { it.info.incoming && it.info.missed && t < it.at } }
    /** The calls page is looked at (iOS onChange of the pane, ContentView.swift:3010-3012). */
    fun clear() { if (unseen() != 0) Prefs.setStr(KEY, System.currentTimeMillis().toString()) }
    /** The moment as kept, milliseconds, for a copy (iOS «callsSeenAt», loadCallsSeenAt 593-603: seconds there, the card converts). */
    fun kept(): Long? = Prefs.str(KEY, "").toLongOrNull()
    /** A copy laid (iOS layCard 884-891: the copy's word). */
    fun lay(ms: Long) { if (ms > 0) Prefs.setStr(KEY, ms.toString()) }
}

/**
 * THE TIME MARK FOR A FACE NOT CHOSEN (iOS MTTimeMarkAvatar, MontanaShapes.swift:529-540, the calls' AvatarCircle timeMarkWhenMissing):
 * «absence is a complete, stable visual answer of its own» -- the black round with the sign (the iPhone's Logo, the same file) at
 * 28 of the side and a rim of white 0.35; a chosen face stands as it is.
 */
private fun Context.callFace(ref: String, name: String, sizeDp: Int): View {
    if (Book.shownFace(ref).exists()) return peerFace(ref, name, sizeDp)
    return FrameLayout(this).apply {
        background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(Color.BLACK); setStroke(dp(1), Color.argb(89, 255, 255, 255))
        }
        val pad = Math.round(dp(sizeDp) * 0.36f)
        addView(android.widget.ImageView(context).apply {
            setImageResource(R.drawable.logo); scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            setPadding(pad, pad, pad, pad)
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/**
 * iOS CallsTabView.cell (ContentView.swift:2901-2943) in the App Library's measure (72, the face 48, the gap 16, the side 18): the
 * face; the name 17 semibold -- red when the call was missed -- and the clock 14, 22 high; 4 under them, 20 high, the arrow of the
 * call's direction 12, the camera of a video call 11, how it went 16 (the length, «Missed», «No answer», «Connection failed») and
 * the call's own glyph 18 at the end of the line.
 */
private fun callRow(act: MainActivity, r: CallRecord): View {
    val c: Context = act
    val i = r.info
    val name = Book.chat(r.ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
    val how = when {
        i.missed -> c.getString(if (i.incoming) R.string.call_missed_short else R.string.call_no_answer)
        i.dur > 0 -> String.format(Locale.ROOT, "%d:%02d", i.dur / 60, i.dur % 60)
        else -> c.getString(R.string.call_failed)
    }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(18), 0, dp(18), 0)
        minimumHeight = dp(72)
        addView(c.callFace(r.ref, name, 48), lp(dp(48), dp(48)).apply { marginEnd = dp(16) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.text(name, 17f, if (i.missed) SysColor.red else Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                addView(c.text(DateFormat.getTimeFormat(c).format(Date(r.at)), 14f, MT.gray))
            }, lp(MATCH, dp(22)))
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.icon(if (i.incoming) R.drawable.ic_call_received else R.drawable.ic_call_made, if (i.missed) SysColor.red else SysColor.green, 12),
                    lp(dp(12), dp(12)).apply { marginEnd = dp(5) })
                if (i.video) addView(c.icon(R.drawable.ic_peer_video, MT.gray, 11), lp(dp(11), dp(11)).apply { marginEnd = dp(5) })
                addView(c.text(how, 16f, MT.gray).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
                addView(c.icon(if (i.video) R.drawable.ic_peer_video else R.drawable.ic_peer_phone, Color.WHITE, 18), lp(dp(18), dp(18)))
            }, lp(MATCH, dp(20)).apply { topMargin = dp(4) })
        }, lp(0, WRAP, 1f))
    }
}

/** iOS MTDayLabel.of (MontanaMessageFeed.swift:595-614): «Today», «Yesterday», else the day and the month in the app's language. */
private fun dayLabel(c: Context, at: Long): String {
    if (DateUtils.isToday(at)) return c.getString(R.string.today)
    if (DateUtils.isToday(at + 86_400_000L)) return c.getString(R.string.gl_yesterday)
    val loc = c.resources.configuration.locales[0]
    return java.text.SimpleDateFormat(DateFormat.getBestDateTimePattern(loc, "dMMMM"), loc).format(Date(at))
}

/**
 * THE CALLS (iOS CallsTabView): the log of calls, a day's pill before the first call of each day, newest first; a stroke from
 * the right deletes a call's row (iOS swipeTrailing), a tap dials back. «Your audio and video calls will appear here» while there
 * are none.
 */
fun callsPane(act: MainActivity, onNewCall: () -> Unit = {}): View {
    val c: Context = act
    val rows = c.vstack(Gravity.NO_GRAVITY)
    val empty = c.text(c.getString(R.string.no_calls), 17f, MT.gray, center = true)
    // THE SELECTION (iOS CallsTabView selecting, selected): «Select» in a call's hold menu begins it; the bar at the foot ends it
    var selecting = false
    val selected = linkedSetOf<String>()   // ref + "/" + mid
    val foot = FrameLayout(c).apply { visibility = View.GONE }
    lateinit var fill: () -> Unit
    fun delete(ref: String, mid: String) = Book.edit(ref) { ch -> ch.msgs.removeAll { it.mid == mid } }
    fun endSelecting() { selecting = false; selected.clear(); fill() }
    // the bar of the selection (iOS selectionBar): the cross out of it, the bin for the chosen, the cleared bin for the whole log
    fun drawFoot() {
        foot.removeAllViews()
        foot.visibility = if (selecting) View.VISIBLE else View.GONE
        if (!selecting) return
        // iOS barButton (ContentView.swift:3036-3041): the glyph 18 semibold, white, on the round of the field's tier (36) in a target of 44
        fun key(glyph: Int, words: Int, on: Boolean, work: () -> Unit) = FrameLayout(c).apply {
            contentDescription = c.getString(words)
            alpha = if (on) 1f else 0.5f
            addView(View(c).apply { background = c.glassPlate(oval = true) }, FrameLayout.LayoutParams(c.dp(36), c.dp(36), Gravity.CENTER))
            addView(c.icon(glyph, Color.WHITE, 18), FrameLayout.LayoutParams(c.dp(18), c.dp(18), Gravity.CENTER))
            if (on) pressable(work)
        }
        // iOS selectionBar (3026-3035): 12 from the sides, 8 above, 6 below, 10 between
        foot.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(6))
            addView(key(R.drawable.ic_close, R.string.cancel, true) { endSelecting() }, lp(dp(44), dp(44)))
            addView(View(c), lp(0, 1, 1f))
            addView(key(R.drawable.ic_delete, R.string.delete, selected.isNotEmpty()) {
                selected.toList().forEach { k -> delete(k.substringBefore("/"), k.substringAfter("/")) }
                endSelecting()
            }, lp(dp(44), dp(44)))
            gap(10)
            addView(key(R.drawable.ic_bin_x, R.string.delete, true) {
                callRecords().forEach { r -> delete(r.ref, r.mid) }
                endSelecting()
            }, lp(dp(44), dp(44)))
        }, FrameLayout.LayoutParams(MATCH, WRAP))
    }
    fill = {
        rows.removeAllViews()
        val log = callRecords()
        empty.visibility = if (log.isEmpty()) View.VISIBLE else View.GONE
        val cal = Calendar.getInstance()
        var lastDay = -1L
        for (r in log) {
            cal.timeInMillis = r.at
            val day = cal.get(Calendar.YEAR) * 1000L + cal.get(Calendar.DAY_OF_YEAR)
            if (day != lastDay) {
                lastDay = day
                // THE DAY'S PILL (iOS CallsTabView.cell's day row, ContentView.swift:2902-2909): the day's word 11 in grey on white 0.15,
                // 12 by 5, 4 above and below, at the middle
                rows.addView(FrameLayout(c).apply {
                    addView(c.text(dayLabel(c, r.at), 11f, MT.gray).apply { background = c.rounded(Color.rgb(38, 38, 38), 7); setPadding(dp(12), dp(5), dp(12), dp(5)) },
                        FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
                }, lp().apply { topMargin = c.dp(4); bottomMargin = c.dp(4) })
            }
            val row = callRow(act, r) as android.widget.LinearLayout
            val k = r.ref + "/" + r.mid
            if (selecting) {
                // WHILE THE PAGE SELECTS a call is a choice: the platform's circle before it, a tap chooses (iOS 2912-2914)
                val on = k in selected
                row.addView(FrameLayout(c).apply {
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        if (on) setColor(SysColor.blue) else setStroke(c.dp(1.5f), MT.gray)
                    }
                    if (on) addView(c.icon(R.drawable.ic_check, Color.WHITE, 14), FrameLayout.LayoutParams(c.dp(14), c.dp(14), Gravity.CENTER))
                }, 0, lp(c.dp(22), c.dp(22)).apply { marginEnd = c.dp(12) })
                row.pressable { if (!selected.remove(k)) selected.add(k); fill(); drawFoot() }
                rows.addView(row, lp())
            } else {
                row.pressable { act.callOut(r.ref, r.info.video) }   // a tap dials back, a video call's row by video (iOS 2983)
                // THE HOLD (iOS the call's menu 2960-2966): select, delete
                row.setOnLongClickListener {
                    // select, delete, block or unblock (iOS CallsTabView.deeds, ContentView.swift:2960-2969), the person's face at the cloud's head
                    holdMenu(act, row, listOf(
                        Deed(R.string.ld_select, R.drawable.ic_set_check_circle) { selecting = true; selected.clear(); selected.add(k); fill(); drawFoot() },
                        Deed(R.string.delete, R.drawable.ic_delete, red = true) { delete(r.ref, r.mid) },
                        if (PeerSafety.isBlocked(r.ref)) Deed(R.string.pi_unblock, R.drawable.ic_set_lock) { PeerSafety.setBlocked(r.ref, false); Book.edit(r.ref) {} }
                        else Deed(R.string.pi_block, R.drawable.ic_set_lock, red = true) { askBlock(act, r.ref) { Book.edit(r.ref) {} } }),
                        personPlate(act, r.ref))
                    true
                }
                rows.addView(SwipeRow(act, row, listOf(Tile(R.drawable.ic_delete) { delete(r.ref, r.mid) })), lp())   // the one glass (iOS swipeTrailing 2956-2959)
            }
            rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(82) })
        }
    }
    fill()
    val again: () -> Unit = { act.onMain { fill(); drawFoot() } }
    rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); fill() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again) }
    })
    return FrameLayout(c).apply {
        addView(CoinPull(c, ScrollView(c).apply {
            isVerticalScrollBarEnabled = false
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(rows, lp())
                gap(120)
            })
        }), FrameLayout.LayoutParams(MATCH, MATCH))   // one law for every page under the bar (iOS MontanaTimePanel)
        addView(empty, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        // THE CALLS' ACTION (iOS CallsTabView, ContentView.swift:3001-3009, the author's word 01.10: «on the calls create the button»): a new
        // call is chosen among one's people -- the contacts' page, where a person's row dials; the pages' one corner, away while selecting
        val action = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.new_call)
            addView(c.icon(R.drawable.ic_phone_plus, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER))
            pressable { onNewCall() }
        }
        addView(action, FrameLayout.LayoutParams(dp(60), dp(60), Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, dp(16), dp(36)) })
        foot.viewTreeObserver.addOnGlobalLayoutListener { action.visibility = if (foot.visibility == View.VISIBLE) View.GONE else View.VISIBLE }
        addView(foot, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { bottomMargin = c.dp(26) })
    }
}
