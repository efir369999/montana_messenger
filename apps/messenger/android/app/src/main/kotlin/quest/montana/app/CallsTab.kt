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
 * iOS CallsTabView.cell: the face; the name — red when the call was missed — and the clock; under them the arrow of the
 * call's direction, the camera of a video call, how it went (the length, «Missed», «No answer», «Connection failed») and the
 * call's own glyph at the end of the line.
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
        setPadding(dp(16), dp(10), dp(16), dp(10))
        addView(c.peerFace(r.ref, name, 54), lp(dp(54), dp(54)).apply { marginEnd = dp(12) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.text(name, 17f, if (i.missed) SysColor.red else Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                addView(c.text(DateFormat.getTimeFormat(c).format(Date(r.at)), 14f, MT.gray))
            }, lp())
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(c.icon(if (i.incoming) R.drawable.ic_call_received else R.drawable.ic_call_made, if (i.missed) SysColor.red else SysColor.green, 12),
                    lp(dp(12), dp(12)).apply { marginEnd = dp(5) })
                if (i.video) addView(c.icon(R.drawable.ic_peer_video, MT.gray, 11), lp(dp(11), dp(11)).apply { marginEnd = dp(5) })
                addView(c.text(how, 16f, MT.gray).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
                addView(c.icon(if (i.video) R.drawable.ic_peer_video else R.drawable.ic_peer_phone, Color.WHITE, 18), lp(dp(18), dp(18)))
            }, lp().apply { topMargin = dp(4) })
        }, lp(0, WRAP, 1f))
    }
}

/**
 * THE CALLS (iOS CallsTabView): the log of calls, a day's pill before the first call of each day, newest first; a stroke from
 * the right deletes a call's row (iOS swipeTrailing), a tap dials back. «Your audio and video calls will appear here» while there
 * are none.
 */
fun callsPane(act: MainActivity): View {
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
        fun key(glyph: Int, words: Int, on: Boolean, work: () -> Unit) = FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(words)
            alpha = if (on) 1f else 0.5f
            addView(c.icon(glyph, Color.WHITE, 22), FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.CENTER))
            if (on) pressable(work)
        }
        foot.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(10))
            addView(key(R.drawable.ic_close, R.string.cancel, true) { endSelecting() }, lp(dp(48), dp(48)))
            addView(View(c), lp(0, 1, 1f))
            addView(key(R.drawable.ic_delete, R.string.delete, selected.isNotEmpty()) {
                selected.toList().forEach { k -> delete(k.substringBefore("/"), k.substringAfter("/")) }
                endSelecting()
            }, lp(dp(48), dp(48)))
            gap(12)
            addView(key(R.drawable.ic_bin_x, R.string.delete, true) {
                callRecords().forEach { r -> delete(r.ref, r.mid) }
                endSelecting()
            }, lp(dp(48), dp(48)))
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
                // the day's pill, the same the conversation stands between its days
                val words = if (DateUtils.isToday(r.at)) c.getString(R.string.today) else DateUtils.formatDateTime(c, r.at, DateUtils.FORMAT_SHOW_DATE)
                rows.addView(FrameLayout(c).apply {
                    addView(c.text(words, 13f, Color.WHITE).apply { background = c.glassPlate(); setPadding(dp(10), dp(3), dp(10), dp(3)) },
                        FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
                }, lp().apply { topMargin = c.dp(8); bottomMargin = c.dp(4) })
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
                    holdMenu(act, row, listOf(
                        Deed(R.string.ld_select, R.drawable.ic_set_check_circle) { selecting = true; selected.clear(); selected.add(k); fill(); drawFoot() },
                        Deed(R.string.delete, R.drawable.ic_delete, red = true) { delete(r.ref, r.mid) }))
                    true
                }
                rows.addView(SwipeRow(act, row, listOf(Tile(R.drawable.ic_delete, red = true) { delete(r.ref, r.mid) })), lp())
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
        addView(foot, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { bottomMargin = c.dp(26) })
    }
}
