package quest.montana.app

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ScrollView

/**
 * THE P2P WALL (iOS NetworkTabView on the globe's pane, MontanaNetworkView 146-281; the author's word 23.09: «the tab is the
 * nodes»; the VPN left for its own app 08.10). The head: the globe on the plain glass, on its badge the machines held, green
 * while this phone holds one and red while it holds none, and one line saying what the wall is. Then «Reachable nodes (N)»:
 * NODES, not doors (the author's word 26.08) — one machine behind two doors is one row with its doors nested; the groups are
 * the machines the network named, else the machines the handshakes proved; every door says one of four words — open, spare
 * (alive as the folded spare of a held machine), lost (met through this door, not held now), no answer.
 */
fun p2pPane(act: MainActivity): View {
    val c = act
    val side = c.dp(18)   // iOS MTLibraryRow.side
    val badge = c.text("0", 11f, Color.WHITE, bold = true).apply {
        gravity = Gravity.CENTER
        val pad = c.dp(5)
        setPadding(pad, pad, pad, pad)
        minWidth = c.dp(22); minHeight = c.dp(22)
        translationX = c.dp(5).toFloat(); translationY = -c.dp(3).toFloat()   // iOS .offset(x: 5, y: -3)
    }
    val head = c.vstack {
        clipChildren = false
        setPadding(c.dp(12), c.dp(16), c.dp(12), c.dp(6))
        addView(FrameLayout(c).apply {
            clipChildren = false
            addView(FrameLayout(c).apply {
                background = c.glassPlate(oval = true)
                addView(c.icon(R.drawable.ic_language, Color.WHITE, 26), FrameLayout.LayoutParams(c.dp(26), c.dp(26), Gravity.CENTER))
            }, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(badge, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END))
        }, lp(c.dp(62), c.dp(62)))
        gap(12)
        addView(c.text(c.getString(R.string.p2p_wall_caption), 13f, MT.gray, center = true).apply { setPadding(c.dp(28), 0, c.dp(28), 0) }, lp())
    }
    val rows = c.vstack(Gravity.NO_GRAVITY)
    /** One line in the library's measure (iOS row 267-281): the globe on its tile, the title, the word in its colour, the hairline. */
    fun row(word: Int, color: Int, title: String, small: Boolean) {
        rows.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(side, 0, side, 0)
            addView(FrameLayout(c).apply {
                background = c.rounded(Color.argb(26, 255, 255, 255), 10)
                addView(c.icon(R.drawable.ic_language, MT.gray, 24), FrameLayout.LayoutParams(c.dp(24), c.dp(24), Gravity.CENTER))
            }, lp(c.dp(48), c.dp(48)))
            gap(16)
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(title, if (small) 13f else 17f, Color.WHITE, bold = !small).apply { singleLineEllipsis() }, lp())   // USER-DATA: a machine's name, a door's address and speed
                gap(4)
                addView(c.text(c.getString(word), 16f, color), lp())
            }, lp(0, WRAP, 1f))
        }, lp(MATCH, c.dp(72)))
        rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = side + c.dp(48 + 16) })
    }
    fun draw() {
        val nodes = Channels.nodesHeld()
        badge.text = nodes.toString()   // USER-DATA: a count — the machines held
        badge.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (nodes > 0) MT.green else MT.red) }
        rows.removeAllViews()
        rows.addView(c.text(c.getString(R.string.p2p_reachable) + " (" + nodes + ")", 12f, MT.gray).apply { setPadding(side, c.dp(12), side, c.dp(12)) }, lp())
        val live = Channels.heldLabels()
        val book = Doors.book()
        val heldNodes = Channels.heldNodes()
        val doors = Doors.list()
        // the machines the network named — every door under its machine whatever the handshakes did — else the ones the handshakes proved
        val named = Doors.machines().filter { m -> doors.any { it.label in m.second } }
        val groups: List<Triple<String, List<Doors.Door>, Boolean>> = if (named.isNotEmpty()) named.map { m ->
            val ds = doors.filter { it.label in m.second }
            val held = ds.any { it.label in live } || ds.any { d -> book[d.label]?.first?.let { o -> o in heldNodes } == true }
            Triple("node " + m.first, ds, held)
        } else doors.mapNotNull { book[it.label]?.first }.distinct().map { ov ->
            Triple("node " + ov.take(8), doors.filter { book[it.label]?.first == ov }, ov in heldNodes)
        }
        for ((title, ds, held) in groups) {
            row(if (held) R.string.p2p_held else R.string.p2p_lost, if (held) MT.green else MT.orange, title, small = false)
            for (d in ds) {
                val known = book[d.label]
                val t = known?.let { d.label + "  ·  " + it.second + " ms" } ?: d.label
                // iOS MontanaNodes.state 101-108: held — open; known behind a held machine — spare; known — lost; else no answer
                when {
                    d.label in live -> row(R.string.p2p_open, MT.green, t, small = true)
                    known != null && known.first in heldNodes -> row(R.string.p2p_spare, MT.green, t, small = true)
                    known != null -> row(R.string.p2p_lost, MT.orange, t, small = true)
                    else -> row(R.string.p2p_no_answer, MT.red, t, small = true)
                }
            }
        }
        val grouped = groups.flatMap { g -> g.second.map { it.label } }.toSet()
        for (d in doors) if (d.label !in grouped) row(R.string.p2p_no_answer, MT.red, d.label, small = true)
    }
    draw()
    val page = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        clipChildren = false
        addView(c.vstack(Gravity.NO_GRAVITY) {
            clipChildren = false
            addView(head, lp())
            addView(rows, lp())
            gap(120)   // the floating player's room at the foot
        })
    }
    // the rows follow the channels while the wall stands (iOS: an observed node redraws them)
    val tick = object : Runnable { override fun run() { if (page.isShown) draw(); page.postDelayed(this, 2000) } }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { page.post(tick) }
        override fun onViewDetachedFromWindow(v: View) { page.removeCallbacks(tick) }
    })
    return page
}
