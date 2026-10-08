package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ScrollView

// ─────────────────────────── the group's page (iOS MontanaPeerInfoScreen for a group, MTGroupPageAsks) ───────────────────────────

/**
 * THE GROUP'S PAGE (iOS MontanaPeerInfoScreen for a group): its face, its name and its count; its people — this phone first, as
 * the creator or a member, then the people it sees (the owner's phone everyone it carries to, a member's the owner). The owner
 * adds people, takes a person out (asked first) and changes the name and the face («Edit»); a member leaves (asked first). Every
 * change is the owner's word to every phone of the group (Groups.renew, add, remove, leave), never one phone's alone.
 */
fun groupPage(act: MainActivity, key: String, onClose: () -> Unit): View {
    val c: Context = act
    val edit = c.text(c.getString(R.string.edit), 17f, SysColor.blue).apply { setPadding(c.dp(8), c.dp(10), c.dp(8), c.dp(10)) }
    edit.pressable { act.push { back -> groupEditPage(act, key, back) } }
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onClose) },
            FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(edit, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER_VERTICAL or Gravity.END))
    }
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), dp(32)) }
    fun memberRow(face: View, name: String, role: String, onTap: (() -> Unit)?) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(6), dp(16), dp(6))
        minimumHeight = dp(52)
        addView(face, lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp())   // USER-DATA: a person's name
            addView(c.text(role, 13f, MT.gray), lp())
        }, lp(0, WRAP, 1f))
        if (onTap != null) pressable(onTap)
    }
    fun actionRow(glyph: Int, words: String, red: Boolean, onTap: () -> Unit) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(12), dp(16), dp(12))
        minimumHeight = dp(48)
        val tint = if (red) SysColor.red else SysColor.blue
        addView(c.icon(glyph, tint, 24), lp(dp(24), dp(24)).apply { marginEnd = dp(16) })
        addView(c.text(words, 17f, tint), lp(0, WRAP, 1f))
        pressable(onTap)
    }
    fun draw() {
        body.removeAllViews()
        val ch = Book.chat(key)
        val title = ch?.shown?.ifBlank { null } ?: c.getString(R.string.app_groups)
        val owns = Groups.owns(key)
        val channel = Groups.isChannel(key)
        edit.visibility = if (owns) View.VISIBLE else View.GONE
        body.addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
            setPadding(0, dp(8), 0, dp(8))
            addView(c.peerFace(key, title, 100), lp(dp(100), dp(100)))
            gap(12)
            addView(c.text(title, 24f, Color.WHITE, bold = true, center = true), lp(WRAP, WRAP))   // USER-DATA: the group's title
            Groups.peopleLine(c, key)?.let { addView(c.text(it, 15f, MT.gray, center = true), lp(WRAP, WRAP)) }
        }, lp())
        val rows = mutableListOf<View>()
        rows += memberRow(c.avatar(SelfFace.load(c), Prefs.userName, 40), c.getString(R.string.gp_you),
            c.getString(if (owns) R.string.gp_creator else R.string.gp_member), null)
        Groups.shownSeats(c, key).forEachIndexed { i, s ->
            val ref = SamePair.root(s.pipe)
            rows += memberRow(c.peerFace(ref, s.name, 40), s.name, c.getString(if (!owns && i == 0) R.string.gp_creator else R.string.gp_member),
                if (!owns) null else ({
                    AlertDialog.Builder(c).setTitle(R.string.gp_remove_q)
                        .setPositiveButton(R.string.gp_remove) { _, _ -> Groups.remove(key, s.seat); draw() }
                        .setNegativeButton(R.string.cancel, null).show()
                }))
        }
        if (owns) rows += actionRow(R.drawable.ic_person_add, c.getString(R.string.gp_add), red = false) {
            act.push { close -> groupPickPage(act, close, {}, adding = key) }
        } else if (!Groups.isOut(key)) rows += actionRow(R.drawable.ic_leave,
            c.getString(if (channel) R.string.gp_leave_channel else R.string.gp_leave_group), red = true) {
            AlertDialog.Builder(c).setTitle(if (channel) R.string.gp_leave_channel_q else R.string.gp_leave_group_q)
                .setPositiveButton(if (channel) R.string.gp_leave_channel else R.string.gp_leave_group) { _, _ -> Groups.leave(key); draw() }
                .setNegativeButton(R.string.cancel, null).show()
        }
        body.section(c.getString(R.string.gp_members), null, *rows.toTypedArray())
    }
    draw()
    val again: () -> Unit = { act.onMain { draw() } }
    body.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); draw() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again) }
    })
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/** THE OWNER'S EDIT (iOS the group page's edit mode → MTGroup.renew): the face and the name; «Done» tells every member. */
private fun groupEditPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    var face: ByteArray? = null
    val faceBox = FrameLayout(c)
    fun drawFace() {
        faceBox.removeAllViews()
        val bmp = face?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (bmp != null) faceBox.addView(c.avatar(bmp, "", 100), FrameLayout.LayoutParams(c.dp(100), c.dp(100)))
        else faceBox.addView(c.peerFace(key, Book.chat(key)?.shown ?: "", 100), FrameLayout.LayoutParams(c.dp(100), c.dp(100)))
    }
    drawFace()
    faceBox.pressable {
        act.pickPhoto { uri ->
            val image = uri?.let { SelfFace.decode(act, it) } ?: return@pickPhoto
            lateinit var close: () -> Unit
            close = act.overlay(cropPage(act, image) { jpeg -> close(); if (jpeg != null) { face = jpeg; drawFace() } })
        }
    }
    val name = EditText(c).apply {
        setText(Book.chat(key)?.shown ?: "")   // USER-DATA: the group's title
        hint = c.getString(R.string.gr_name)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        isSingleLine = true
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
    }
    val done = c.text(c.getString(R.string.gp_done), 17f, SysColor.blue, bold = true).apply { setPadding(c.dp(8), c.dp(10), c.dp(8), c.dp(10)) }
    done.pressable {
        c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(name.windowToken, 0)
        Groups.renew(key, name.text.toString(), face)
        onBack()
    }
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onBack) },
            FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(done, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER_VERTICAL or Gravity.END))
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply {
                addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                    setPadding(dp(16), dp(8), dp(16), dp(32))
                    addView(faceBox, lp(dp(100), dp(100)))
                    gap(20)
                    addView(c.plate { addView(name, lp()) }, lp())
                })
            }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}
