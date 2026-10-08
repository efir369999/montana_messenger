package quest.montana.app

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.Switch

/**
 * THE MESH WALL (iOS NetworkTabView on the mesh pane, MontanaNetworkView 70-320; the author's word 29.09: «the network is
 * disbanded — the mesh wall and the P2P wall are applications»). The wall's head (146-174): the antenna on the plain glass, on
 * its badge the people reached phone to phone, green while this phone is in and red while it is not — the moment findability
 * is off — and one line saying what the wall is. Then «How others see you» (283-319): the first letter and the name, said
 * honestly, and the one switch of being findable. The people near (iOS MontanaMeshCard) come with the next step.
 */
fun meshPane(act: MainActivity): View {
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
                addView(c.icon(R.drawable.ic_set_antenna, Color.WHITE, 26), FrameLayout.LayoutParams(c.dp(26), c.dp(26), Gravity.CENTER))
            }, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(badge, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP or Gravity.END))
        }, lp(c.dp(62), c.dp(62)))
        gap(12)
        addView(c.text(c.getString(R.string.mesh_wall_caption), 13f, MT.gray, center = true).apply { setPadding(c.dp(28), 0, c.dp(28), 0) }, lp())
    }
    val name = Prefs.userName.trim()   // USER-DATA: a person's name
    val first = if (name.isEmpty()) "" else String(Character.toChars(name.codePointAt(0))).uppercase()   // USER-DATA: its first letter
    val sw = Switch(c).apply {
        isChecked = Mesh.discoverable
        thumbTintList = ColorStateList.valueOf(Color.WHITE)
        trackTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(MT.green, Color.rgb(57, 57, 61)))
        contentDescription = c.getString(R.string.mesh_findable)
    }
    val me = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(side, c.dp(24), side, c.dp(12))   // iOS .padding(.top, 12) over the card's own .padding(.vertical, 12)
        addView(c.text(c.getString(R.string.mesh_seen_as), 12f, MT.gray), lp())
        gap(12)
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(c.text(first, 18f, Color.WHITE, bold = true).apply {
                gravity = Gravity.CENTER
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(26, 255, 255, 255)) }
            }, lp(c.dp(48), c.dp(48)))
            gap(12)
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(name, 15f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp())
                gap(2)
                addView(c.text(c.getString(R.string.mesh_seen_only), 11f, MT.gray), lp())
            }, lp(0, WRAP, 1f))
        }, lp())
        gap(12)
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(c.getString(R.string.mesh_findable), 14f), lp())
                gap(2)
                addView(c.text(c.getString(R.string.mesh_findable_off), 11f, MT.gray), lp())
            }, lp(0, WRAP, 1f))
            gap(8)
            addView(sw)
            setOnClickListener { sw.toggle() }   // the whole row is the target
        }, lp())
    }
    fun draw() {
        val on = Channels.nodesHeld() > 0 && Mesh.discoverable   // iOS: node.p2pUp && meshDiscoverable
        badge.text = Channels.peers().toString()   // USER-DATA: a count — the people reached phone to phone (the radio's come with it)
        badge.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (on) MT.green else MT.red) }
    }
    sw.setOnCheckedChangeListener { _, v -> Mesh.setDiscoverable(v); draw() }
    draw()
    val page = ScrollView(c).apply {
        isVerticalScrollBarEnabled = false
        clipChildren = false
        addView(c.vstack(Gravity.NO_GRAVITY) {
            clipChildren = false
            addView(head, lp())
            addView(me, lp())
            gap(120)   // the floating player's room at the foot
        })
    }
    // the badge follows the channels while the wall stands (iOS: an observed node redraws it)
    val tick = object : Runnable { override fun run() { if (page.isShown) draw(); page.postDelayed(this, 2000) } }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { page.post(tick) }
        override fun onViewDetachedFromWindow(v: View) { page.removeCallbacks(tick) }
    })
    return page
}
