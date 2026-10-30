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
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.Switch

// ─────────────────────────── the group's page (iOS MontanaPeerInfoScreen for a group, MTGroupPageAsks) ───────────────────────────

/**
 * THE GROUP'S PAGE (iOS MontanaPeerInfoScreen for a group): its face, its name and its count; its people — this phone first, as
 * the creator or a member, then the people it sees (the owner's phone everyone it carries to, a member's the owner). The owner
 * adds people, takes a person out (asked first) and changes the name and the face («Edit»); a member leaves (asked first). Every
 * change is the owner's word to every phone of the group (Groups.renew, add, remove, leave), never one phone's alone.
 */
fun groupPage(act: MainActivity, key: String, onClose: () -> Unit,
              toChat: (String, String?) -> Unit = { to, mid -> act.push { close -> conversationPage(act, to, close, jump = mid) } },
              onSearch: () -> Unit = { onClose(); act.push { close -> conversationPage(act, key, close, search = true) } }): View {
    val c: Context = act
    // THE GROUP'S PANES UNDER ITS PEOPLE, AS THE REFERENCE'S PAGE HAS THEM (iOS 82c9ae3f, V.7): Media -- its photos and its videos
    // together --, Files, Links, Music and Voice; a channel keeps its page as it was
    val panes = if (Groups.isChannel(key)) null else panesOf(act, key, group = true, onClose, toChat) {}
    panes?.pane?.setPadding(0, 0, 0, 0)   // the page's own margins hold it
    val edit = c.text(c.getString(R.string.edit), 17f, SysColor.blue).apply { setPadding(c.dp(8), c.dp(10), c.dp(8), c.dp(10)) }
    edit.pressable { act.push { back -> groupEditPage(act, key, back) { back(); onClose() } } }
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
    lateinit var redraw: () -> Unit
    // A GROUP'S «MORE», AS THE REFERENCE'S MENU HAS IT (iOS groupMore, 1915a7f4): «Report» for one who does not own it, «Clear Messages»,
    // then the way out -- «Leave Group» for a member, «Delete Group» for its owner -- each asked first
    fun groupMore(v: View) {
        val title0 = Book.chat(key)?.shown ?: ""
        val items = mutableListOf<Pair<String, () -> Unit>>()
        if (!Groups.owns(key)) items += c.getString(R.string.pi_report) to {
            act.push { close -> reportPage(act, key, title0, offersBlock = false, onClose = close) }   // a group is reported, never blocked as a person
        }
        items += c.getString(R.string.gp_clear) to {
            AlertDialog.Builder(c).setTitle(c.getString(R.string.gp_clear_q, title0))   // USER-DATA: the group's title
                .setPositiveButton(R.string.gp_delete_all) { _, _ -> Book.chat(key)?.msgs?.map { it.mid }?.let { Book.drop(key, it) } }
                .setNegativeButton(R.string.cancel, null).show()
        }
        if (!Groups.isOut(key)) {
            if (Groups.owns(key)) items += c.getString(R.string.gp_dissolve) to {
                AlertDialog.Builder(c).setTitle(c.getString(R.string.gp_dissolve_q, title0))   // USER-DATA: the group's title
                    .setPositiveButton(R.string.gp_dissolve_all) { _, _ -> Groups.dissolve(key); onClose() }
                    .setNegativeButton(R.string.cancel, null).show()
            } else items += c.getString(R.string.gp_leave_group) to {
                AlertDialog.Builder(c).setTitle(c.getString(R.string.gr_erase_q, title0))
                    .setPositiveButton(R.string.gp_leave_group) { _, _ -> Groups.leaveAndErase(key); onClose() }
                    .setNegativeButton(R.string.cancel, null).show()
            }
        }
        PopupMenu(c, v).apply {
            items.forEachIndexed { i, (t, _) -> menu.add(0, i, i, t) }
            setOnMenuItemClickListener { items[it.itemId].second(); true }
        }.show()
    }
    /**
     * A GROUP'S PAGE AS THE REFERENCE LAYS IT (iOS 1915a7f4, MTGroupPage): under the head its buttons -- its sound and «More» (no voice
     * chat is held on this phone, nor has a chat its own search yet) -- the description with its caption over its words, then the people
     * with no header: «Add Member» first for the owner, the owner, the administrators, everyone else by name, this phone among them.
     * A row: the face, the name, online under it, the role on a capsule of its own colour; a tap opens the person's page where this
     * phone holds their pipe, a hold names the deeds. The ways out stand in «More» and in the editor.
     */
    fun drawGroup() {
        val owns = Groups.owns(key)
        val plates = c.hstack { setPadding(0, dp(4), 0, dp(10)) }
        fun plate(icon: Int, label: String, work: (View) -> Unit) {
            if (plates.childCount > 0) plates.addView(View(c), lp(c.dp(10), 1))
            plates.addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                background = c.glassPlate().apply { cornerRadius = dp(14).toFloat() }
                setPadding(dp(4), dp(8), dp(4), dp(6))
                contentDescription = label
                addView(c.icon(icon, SysColor.blue, 22), lp(dp(22), dp(22)))
                addView(c.text(label, 12f, SysColor.blue, center = true).apply { singleLineEllipsis() }, lp(WRAP, WRAP).apply { topMargin = dp(4) })
                pressable { work(this) }
            }, lp(0, WRAP, 1f))
        }
        val muted = ChatMarks.isMuted(key)
        plate(if (muted) R.drawable.ic_set_bell else R.drawable.ic_bell_off, c.getString(if (muted) R.string.gp_unmute else R.string.gp_mute)) {
            ChatMarks.toggleMute(key); redraw()   // the one switch of a chat's sound, the list's swipe's own
        }
        // «Search» (iOS .search, MontanaPeerInfoScreen.swift:590-596): the chat's own search, the page gone down to its chat
        plate(R.drawable.ic_search, c.getString(R.string.search)) { onSearch() }
        plate(R.drawable.ic_more_horiz, c.getString(R.string.pi_more)) { v -> groupMore(v) }
        body.addView(plates, lp())
        Groups.about(key).takeIf { it.isNotEmpty() }?.let { about ->
            body.section(null, null, c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.text(c.getString(R.string.gp_about), 13f, MT.gray), lp())   // the caption over the words, as the reference's
                addView(c.text(about, 17f, Color.WHITE).apply { setTextIsSelectable(true) }, lp())   // USER-DATA: the owner's words
            })
        }
        val rows = mutableListOf<View>()
        if (owns) rows += actionRow(R.drawable.ic_person_add, c.getString(R.string.gp_add), red = false) {
            act.push { close -> groupPickPage(act, close, {}, adding = key) }
        }
        val mySeat = Groups.mySeat(key)
        val iBan = !owns && Groups.mayBan(key)   // an administrator takes out a member who is none, while «Ban Users» stands (G.6)
        class Person(val seat: String, val name: String, val pipe: String, val me: Boolean)
        val people = Groups.pagePeople(c, key).map { Person(it.seat, it.name, it.pipe, false) } +
            listOfNotNull(mySeat?.let { Person(it, Prefs.userName, "", true) })
        fun rank(seat: String) = if (seat == Groups.OWNER) 0 else if (Groups.isAdmin(key, seat)) 1 else 2
        for (p in people.sortedWith(compareBy<Person> { rank(it.seat) }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })) {
            val r = rank(p.seat)
            val ref = Groups.seatRef(key, p.seat) ?: ""
            val root = p.pipe.takeIf { it.isNotEmpty() }?.let { SamePair.root(it) }
            val chat = root?.takeIf { Book.chat(it) != null }
            val deeds = mutableListOf<Pair<String, () -> Unit>>()
            if (chat != null) deeds += c.getString(R.string.gp_send_message) to { act.push { close -> conversationPage(act, chat, close) } }
            if (owns && !p.me) {
                if (r == 1) {
                    deeds += c.getString(R.string.gp_edit_rights) to { act.push { back -> groupAdminRightsPage(act, key, p.seat, p.name, isNew = false) { back(); redraw() } } }
                    deeds += c.getString(R.string.gp_dismiss) to { Groups.setAdmin(key, p.seat, false); redraw() }
                } else deeds += c.getString(R.string.gp_promote) to { act.push { back -> groupAdminRightsPage(act, key, p.seat, p.name, isNew = true) { back(); redraw() } } }
            }
            // the person taken out, asked first: the hold's last deed and the swipe's «Delete» (iOS MTGroupMemberLine.remove)
            val remove = if (!p.me && (owns || (iBan && r == 2))) ({
                AlertDialog.Builder(c).setTitle(R.string.gp_remove_q)
                    .setPositiveButton(R.string.gp_remove) { _, _ -> Groups.kick(key, p.seat); redraw() }
                    .setNegativeButton(R.string.cancel, null).show()
                Unit
            }) else null
            if (remove != null) deeds += c.getString(R.string.gp_remove_from) to remove
            val row = c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(8), dp(16), dp(8))
                minimumHeight = dp(56)
                val face = when {
                    p.me -> c.avatar(SelfFace.load(c), Prefs.userName, 40)
                    root != null -> c.peerFace(root, p.name, 40)
                    else -> c.avatar(null, p.name, 40).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Groups.tint(ref)) } }
                }
                addView(face, lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
                addView(c.vstack(Gravity.NO_GRAVITY) {
                    addView(c.text(p.name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp())   // USER-DATA: a person's name
                    val seen = if (p.me) c.getString(R.string.pr_online) else root?.let { Presence.word(c, it)?.first }
                    seen?.let { addView(c.text(it, 13f, MT.gray).apply { singleLineEllipsis() }, lp()) }   // the presence ladder's own word
                }, lp(0, WRAP, 1f))
                if (r < 2) {
                    // the role on a capsule of its own colour -- owner in violet, admin in green -- the custom title instead of its word (G.6)
                    val tone = if (r == 0) Color.rgb(0x95, 0x6a, 0xc8) else Color.rgb(0x49, 0xa3, 0x55)
                    val word = Groups.rank(key, p.seat) ?: c.getString(if (r == 0) R.string.gp_owner else R.string.gp_admin)
                    addView(c.text(word, 15f, tone).apply {   // USER-DATA: the owner's custom title
                        gravity = Gravity.CENTER
                        setPadding(dp(7), dp(2), dp(7), dp(2))
                        background = c.rounded(Color.argb(51, Color.red(tone), Color.green(tone), Color.blue(tone)), 100)
                    }, lp(WRAP, WRAP).apply { marginStart = dp(8) })
                }
                if (chat != null) pressable { act.push { close -> peerInfoPage(act, chat, close) } }
                if (deeds.isNotEmpty()) setOnLongClickListener {
                    AlertDialog.Builder(c).setTitle(p.name)   // USER-DATA: a person's name
                        .setItems(deeds.map { it.first }.toTypedArray()) { _, i -> deeds[i].second() }
                        .setNegativeButton(R.string.cancel, null).show()
                    true
                }
            }
            // a swipe to the left takes them out, where this phone may (iOS MTGroupMemberRow .swipeActions «Delete»)
            rows += if (remove == null) row else SwipeRow(act, row, listOf(Tile(R.drawable.ic_delete, red = true) { remove() }),
                ground = GLASS_TONE or (0xFF shl 24))   // the section's card, not the list's black (iOS insetGrouped row)
        }
        body.section(null, null, *rows.toTypedArray())
    }
    fun draw() {
        body.removeAllViews()
        val ch = Book.chat(key)
        val title = ch?.shown?.ifBlank { null } ?: c.getString(R.string.app_groups)
        val owns = Groups.owns(key)
        val channel = Groups.isChannel(key)
        // the owner edits the group, and a member the group lets change its info (iOS mayChangeInfo, G.5)
        edit.visibility = if (Groups.mayChangeInfo(key)) View.VISIBLE else View.GONE
        body.addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
            setPadding(0, dp(8), 0, dp(8))
            addView(c.peerFace(key, title, 100), lp(dp(100), dp(100)))
            gap(12)
            addView(c.text(title, 24f, Color.WHITE, bold = true, center = true), lp(WRAP, WRAP))   // USER-DATA: the group's title
            // «N members, M online», said once for the chat's top and the page (iOS MTGroupPage.head, 1915a7f4)
            Groups.headLine(c, key)?.let { addView(c.text(it, 15f, MT.gray, center = true), lp(WRAP, WRAP)) }
        }, lp())
        if (!channel) {
            drawGroup()
            panes?.let { p ->
                body.addView(p.bar, lp(MATCH, c.dp(44)).apply { topMargin = c.dp(24) })
                body.addView(p.pane, lp())
                p.heard()
            }
            return
        }
        // THE GROUP'S DESCRIPTION (iOS the group page's info above its people, stage R): the owner's words, read by all
        Groups.about(key).takeIf { it.isNotEmpty() && !channel }?.let { about ->
            body.section(null, null, c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.text(about, 17f, Color.WHITE).apply { setTextIsSelectable(true) }, lp())   // USER-DATA: the owner's words
                addView(c.text(c.getString(R.string.gp_about), 13f, MT.gray), lp())
            })
        }
        val rows = mutableListOf<View>()
        // «Add Member» heads the people, as the reference folder's group page has it (iOS stage R)
        if (owns) rows += actionRow(R.drawable.ic_person_add, c.getString(R.string.gp_add), red = false) {
            act.push { close -> groupPickPage(act, close, {}, adding = key) }
        }
        // THE ROLES, AS THE REFERENCE'S MEMBER LIST NAMES THEM (iOS stage R.6): owner, admin, member; the owner's hold on a person names
        // or dismisses an administrator and takes the person out; an administrator's takes out a member who is none
        val mySeat = Groups.mySeat(key)
        val iAdmin = !owns && mySeat?.let { Groups.isAdmin(key, it) } == true
        // an administrator takes a member out only while the owner left it «Ban Users» (iOS adminCan .ban, G.6)
        val iBan = !owns && Groups.mayBan(key)
        // the custom title the owner gave stands instead of the role's own word (iOS rank, G.6)
        fun roleWord(seat: String?, role: Int) = seat?.takeIf { role != R.string.gp_member }?.let { Groups.rank(key, it) } ?: c.getString(role)
        rows += memberRow(c.avatar(SelfFace.load(c), Prefs.userName, 40), c.getString(R.string.gp_you),
            roleWord(mySeat, if (owns) R.string.gp_owner else if (iAdmin) R.string.gp_admin else R.string.gp_member), null)
        Groups.pagePeople(c, key).forEach { s ->
            val theOwner = !owns && s.seat == Groups.OWNER
            val admin = Groups.isAdmin(key, s.seat)
            val mayRemove = owns || (iBan && !theOwner && !admin)
            val deeds = mutableListOf<Pair<String, () -> Unit>>()
            // the admin's rights page, as the reference's «Promote» and «Edit Admin Rights» open it (iOS MTGroupAdminRightsPage, G.6)
            if (owns && !channel) {
                if (admin) {
                    deeds += c.getString(R.string.gp_edit_rights) to { act.push { back -> groupAdminRightsPage(act, key, s.seat, s.name, isNew = false) { back(); draw() } } }
                    deeds += c.getString(R.string.gp_dismiss) to { Groups.setAdmin(key, s.seat, false); draw() }
                } else deeds += c.getString(R.string.gp_promote) to { act.push { back -> groupAdminRightsPage(act, key, s.seat, s.name, isNew = true) { back(); draw() } } }
            }
            if (mayRemove) deeds += c.getString(R.string.gp_remove_from) to {
                AlertDialog.Builder(c).setTitle(R.string.gp_remove_q)
                    .setPositiveButton(R.string.gp_remove) { _, _ -> Groups.kick(key, s.seat); draw() }
                    .setNegativeButton(R.string.cancel, null).show()
            }
            val face = if (s.pipe.isEmpty()) c.avatar(null, s.name, 40) else c.peerFace(SamePair.root(s.pipe), s.name, 40)
            rows += memberRow(face, s.name, roleWord(s.seat, if (theOwner) R.string.gp_owner else if (admin) R.string.gp_admin else R.string.gp_member),
                if (deeds.isEmpty()) null else ({
                    AlertDialog.Builder(c).setTitle(s.name)   // USER-DATA: a person's name
                        .setItems(deeds.map { it.first }.toTypedArray()) { _, i -> deeds[i].second() }
                        .setNegativeButton(R.string.cancel, null).show()
                }))
        }
        val title0 = Book.chat(key)?.shown ?: ""
        // the owner's way out is the group's end for everyone (iOS «Delete Group», «Delete for All»)
        if (owns && !channel) rows += actionRow(R.drawable.ic_delete, c.getString(R.string.gp_dissolve), red = true) {
            AlertDialog.Builder(c).setTitle(c.getString(R.string.gp_dissolve_q, title0))   // USER-DATA: the group's title
                .setPositiveButton(R.string.gp_dissolve_all) { _, _ -> Groups.dissolve(key); onClose() }
                .setNegativeButton(R.string.cancel, null).show()
        } else if (!owns && !Groups.isOut(key)) rows += actionRow(R.drawable.ic_leave,
            c.getString(if (channel) R.string.gp_leave_channel else R.string.gp_leave_group), red = true) {
            // LEAVE GROUP (iOS «Are you sure you want to leave and delete %@?»): the owner is told, and the chat goes; a channel is left as before
            if (channel) AlertDialog.Builder(c).setTitle(R.string.gp_leave_channel_q)
                .setPositiveButton(R.string.gp_leave_channel) { _, _ -> Groups.leave(key); draw() }
                .setNegativeButton(R.string.cancel, null).show()
            else AlertDialog.Builder(c).setTitle(c.getString(R.string.gr_erase_q, title0))
                .setPositiveButton(R.string.gp_leave_group) { _, _ -> Groups.leaveAndErase(key); onClose() }
                .setNegativeButton(R.string.cancel, null).show()
        }
        body.section(c.getString(R.string.gp_members), null, *rows.toTypedArray())
    }
    redraw = { draw() }
    draw()
    val again: () -> Unit = { act.onMain { draw() } }
    val music: () -> Unit = { panes?.music?.invoke() }
    body.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); MusicPlayer.listeners.add(music); draw() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again); MusicPlayer.listeners.remove(music) }
    })
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            // a sideways stroke turns the panes, as on a person's page; one begun on the strip rolls the strip (iOS MTSwipePanes)
            val p = panes
            addView(if (p == null) ScrollView(c).apply { addView(body) }
                else PanesScroll(c, skip = { y -> y in p.bar.top.toFloat()..p.bar.bottom.toFloat() }, turn = p.turn).apply {
                    isVerticalScrollBarEnabled = false; addView(body)
                }, lp(MATCH, 0, 1f))
            // the selection's bar and the mini player at the foot, outside the rows (iOS MontanaPeerInfoScreen.swift:69-84)
            if (p != null) { addView(p.foot, lp()); addView(liveBar(act), lp()) }
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/**
 * THE GROUP'S EDIT (iOS the group page's edit mode → MTGroup.renew): the face and the name; «Done» tells every member. A member the
 * group lets change its info edits the same three, asked of the owner (G.5); the administrators and the permissions are the owner's.
 */
private fun groupEditPage(act: MainActivity, key: String, onBack: () -> Unit, onGone: () -> Unit = onBack): View {
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
    // THE DESCRIPTION, AS THE REFERENCE'S GROUP EDITOR HAS IT (iOS stage R): written by the owner, carried to every member (Groups.renew)
    val channel = Groups.isChannel(key)
    val about = EditText(c).apply {
        setText(Groups.about(key))   // USER-DATA: the owner's words about the group
        hint = c.getString(R.string.gp_about_hint)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        minLines = 1; maxLines = 5
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
    }
    val done = c.text(c.getString(R.string.gp_done), 17f, SysColor.blue, bold = true).apply { setPadding(c.dp(8), c.dp(10), c.dp(8), c.dp(10)) }
    done.pressable {
        c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(name.windowToken, 0)
        Groups.renew(key, name.text.toString(), face, if (channel) null else about.text.toString())
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
                    if (!channel) {
                        gap(20)
                        addView(c.plate { addView(about, lp()) }, lp())
                        addView(c.text(c.getString(R.string.gp_about_note), 13f, MT.gray).apply { setPadding(dp(16), dp(6), dp(16), 0) }, lp())
                    }
                    if (!channel && Groups.owns(key)) {
                        // THE ADMINISTRATORS, as the reference's editor lists them, with their count (iOS MTGroupAdminsPage, G.6)
                        gap(20)
                        val count = c.text("", 17f, MT.gray)
                        fun recount() { count.text = (1 + Groups.admins(key).size).toString() }   // USER-DATA: a count
                        recount()
                        val admins = c.navRow(R.drawable.ic_checkmark_shield, c.getString(R.string.gp_admins), count) {
                            act.push { back -> groupAdminsPage(act, key) { back(); recount() } }
                        }
                        addView(c.plate { addView(admins, lp()) }, lp())
                        // WHAT THE MEMBERS MAY DO, as the reference's editor counts it (iOS MTGroupPermissionsPage, G.5): the rights left of all
                        gap(20)
                        val left = c.text("", 17f, MT.gray)
                        fun reckon() { left.text = Groups.rightsLeft(key) }   // USER-DATA: a count
                        reckon()
                        val perms = c.navRow(R.drawable.ic_key, c.getString(R.string.gp_perms), left) {
                            act.push { back -> groupPermissionsPage(act, key) { back(); reckon() } }
                        }
                        addView(c.plate { addView(perms, lp()) }, lp())
                        // THE GROUP'S TYPE, before its link, as the reference's editor names it (iOS MTGroupTypePage, G.2): always «Private»
                        gap(20)
                        val type = c.navRow(R.drawable.ic_lock, c.getString(R.string.gp_type), c.text(c.getString(R.string.gp_type_private), 17f, MT.gray)) {
                            act.push { back -> groupTypePage(act, key, back) }
                        }
                        addView(c.plate { addView(type, lp()) }, lp())
                        // THE GROUP'S LINK, where the reference's editor keeps it (iOS MTGroupInviteLinksPage, G.3)
                        gap(20)
                        val links = c.navRow(R.drawable.ic_link, c.getString(R.string.gp_links), null) {
                            act.push { back -> groupLinksPage(act, key, back) }
                        }
                        addView(c.plate { addView(links, lp()) }, lp())
                        // THE PAST FOR NEW MEMBERS, as the reference's editor names it (iOS MTGroupHistoryPage, G.4): «Visible» or «Hidden»
                        gap(20)
                        val shown = c.text("", 17f, MT.gray)
                        fun reshow() { shown.text = c.getString(if (Groups.history(key)) R.string.gp_history_on else R.string.gp_history_off) }
                        reshow()
                        val history = c.navRow(R.drawable.ic_restore, c.getString(R.string.gp_history), shown) {
                            act.push { back -> groupHistoryPage(act, key) { back(); reshow() } }
                        }
                        addView(c.plate { addView(history, lp()) }, lp())
                        // WHO ASKED TO JOIN BY THE LINK, as the reference's editor shows it while any wait (iOS MTGroupRequestsPage, G.8)
                        val asked = c.text("", 17f, MT.gray)
                        lateinit var askedPlate: View
                        fun reask() {
                            val n = Groups.requests(c, key).size
                            asked.text = n.toString()   // USER-DATA: a count
                            askedPlate.visibility = if (n == 0) View.GONE else View.VISIBLE
                        }
                        val requests = c.navRow(R.drawable.ic_person_add, c.getString(R.string.gp_requests), asked) {
                            act.push { back -> groupRequestsPage(act, key, back) { reask() } }
                        }
                        askedPlate = c.vstack(Gravity.NO_GRAVITY) {
                            gap(20)
                            addView(c.plate { addView(requests, lp()) }, lp())
                        }
                        addView(askedPlate, lp())
                        reask()
                        // THE PEOPLE KEPT OUT, as the reference's editor lists them, with their count (iOS MTGroupRemovedPage, G.7)
                        gap(20)
                        val removed = c.text("", 17f, MT.gray)
                        fun reweigh() { removed.text = Groups.bannedPeople(c, key).size.toString() }   // USER-DATA: a count
                        reweigh()
                        val out = c.navRow(R.drawable.ic_hand, c.getString(R.string.gp_removed), removed) {
                            act.push { back -> groupRemovedPage(act, key, back) { reweigh() } }
                        }
                        addView(c.plate { addView(out, lp()) }, lp())
                        // THE GROUP'S END, where the reference's editor keeps it (iOS 1915a7f4, the checklist's G.11): the owner's alone, asked first
                        if (Groups.owns(key)) {
                            gap(20)
                            addView(c.plate {
                                addView(c.text(c.getString(R.string.gp_dissolve), 17f, SysColor.red).apply {
                                    setPadding(dp(16), dp(12), dp(16), dp(12)); minimumHeight = dp(48); gravity = Gravity.CENTER_VERTICAL
                                    pressable {
                                        val title0 = Book.chat(key)?.shown ?: ""
                                        AlertDialog.Builder(c).setTitle(c.getString(R.string.gp_dissolve_q, title0))   // USER-DATA: the group's title
                                            .setPositiveButton(R.string.gp_dissolve_all) { _, _ -> Groups.dissolve(key); onGone() }
                                            .setNegativeButton(R.string.cancel, null).show()
                                    }
                                }, lp())
                            }, lp())
                        }
                    }
                })
            }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

// ─────────────────────────── the group's administrators (iOS MTGroupAdminsPage, MTGroupAdminRightsPage, G.6) ───────────────────────────

/** A row that opens a page: the glyph, the words, what it holds, the chevron (iOS NavigationLink in a List). */
private fun Context.navRow(glyph: Int?, words: String, trail: View?, onTap: () -> Unit) = hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(12), dp(12), dp(12))
    minimumHeight = dp(48)
    if (glyph != null) addView(icon(glyph, SysColor.blue, 24), lp(dp(24), dp(24)).apply { marginEnd = dp(16) })
    addView(text(words, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: may be a person's name
    if (trail != null) addView(trail, lp(WRAP, WRAP).apply { marginEnd = dp(6) })
    addView(icon(R.drawable.ic_chevron_right, MT.gray, 16), lp(dp(16), dp(16)))
    pressable(onTap)
}

/**
 * THE GROUP'S INVITE LINK, AS THE REFERENCE'S PAGE KEEPS IT (iOS MTGroupInviteLinksPage, G.3): the link, «Copy» and «Share» under it,
 * and «Revoke Link» -- a new mark that ends every link given before, asked first. Whoever opens the link meets the owner by its card
 * and asks with the mark; the card may be born on the network, so the link is drawn when it comes.
 */
private fun groupLinksPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    var link: String? = null
    val shown = c.text("…", 17f, Color.WHITE).apply { setSingleLine(true); ellipsize = android.text.TextUtils.TruncateAt.MIDDLE }   // USER-DATA: the group's link
    fun button(words: Int, onTap: () -> Unit) = c.text(c.getString(words), 17f, Color.WHITE, bold = true, center = true).apply {
        gravity = Gravity.CENTER
        minHeight = dp(44)
        background = c.rounded(SysColor.blue, 12)
        pressable { if (link != null) onTap() }
    }
    val copy = button(R.string.copy) {
        c.getSystemService(android.content.ClipboardManager::class.java).setPrimaryClip(android.content.ClipData.newPlainText("", link))
        android.widget.Toast.makeText(c, R.string.copied, android.widget.Toast.LENGTH_SHORT).show()
    }
    val share = button(R.string.share) {
        act.startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND)
            .setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, link), null))
    }
    fun fetch() = act.background {
        val l = Groups.inviteLink(act, key)
        act.onMain {
            link = l
            if (l == null) android.widget.Toast.makeText(c, R.string.card_failed, android.widget.Toast.LENGTH_LONG).show()
            shown.text = l ?: ""
        }
    }
    val revoke = c.text(c.getString(R.string.gp_link_revoke), 17f, SysColor.red).apply {
        setPadding(dp(16), dp(12), dp(16), dp(12))
        minHeight = dp(48)
        gravity = Gravity.CENTER_VERTICAL
        pressable {
            AlertDialog.Builder(c).setMessage(R.string.gp_link_revoke_q)
                .setPositiveButton(R.string.gp_link_revoke_do) { _, _ -> Groups.resetInvite(key); shown.text = "…"; link = null; fetch() }
                .setNegativeButton(R.string.cancel, null).show()
        }
    }
    fetch()
    return settingsPage(act, c.getString(R.string.gp_links), onBack) {
        section(c.getString(R.string.gp_link_head), c.getString(R.string.gp_link_note), c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(12), dp(16), dp(12))
            addView(shown, lp())
            gap(12)
            addView(c.hstack {
                addView(copy, lp(0, WRAP, 1f))
                gap(12)
                addView(share, lp(0, WRAP, 1f))
            }, lp())
        })
        // THE LINK ASKS THE OWNER FIRST (iOS MTGroupInviteLinksPage, G.8): who opens it waits among the requests
        var ready = false   // the switch set to what is stored is not the owner's tap
        lateinit var note: android.widget.TextView
        fun renote(on: Boolean) { note.text = c.getString(if (on) R.string.gp_approval_on_note else R.string.gp_approval_off_note) }
        val approval = c.toggleRow(c.getString(R.string.gp_approval)) { on ->
            if (!ready) return@toggleRow
            Groups.setApproval(key, on)
            renote(on)
        }.apply {
            setPadding(dp(16), dp(10), dp(16), dp(10)); minimumHeight = dp(48)
            (getChildAt(0) as android.widget.TextView).textSize = 17f
            (0 until childCount).map { getChildAt(it) }.filterIsInstance<Switch>().firstOrNull()?.isChecked = Groups.approval(key)
            ready = true
        }
        section(null, "", approval)
        note = getChildAt(childCount - 1) as android.widget.TextView   // the section's words under it change with the switch
        renote(Groups.approval(key))
        section(null, null, revoke)
    }
}

/**
 * THE GROUP'S TYPE, AS THE REFERENCE'S PAGE SAYS IT (iOS MTGroupTypePage, G.2): a group here is private -- joined by the owner's hand
 * or by its invite link -- and the page says so in the reference's words, with the link under it. A public group is found by a search
 * of all groups, and this network keeps no list of them: no server holds one, so no switch stands that could not keep its word.
 */
private fun groupTypePage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val private = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(12), dp(16), dp(12)); minimumHeight = dp(48)
        addView(c.text(c.getString(R.string.gp_type_private), 17f, Color.WHITE), lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_check, Color.WHITE), lp(dp(20), dp(20)))
    }
    val links = c.navRow(R.drawable.ic_link, c.getString(R.string.gp_links), null) {
        act.push { back -> groupLinksPage(act, key, back) }
    }
    return settingsPage(act, c.getString(R.string.gp_type), onBack) {
        section(c.getString(R.string.gp_type_head), c.getString(R.string.gp_type_note), private)
        section(null, null, links)
    }
}

/**
 * THE GROUP'S MEMBER REQUESTS, AS THE REFERENCE'S PAGE KEEPS THEM (iOS MTGroupRequestsPage, G.8): who asked to join by the link
 * while it asks the owner first, the newest first -- «Add to Group» adds them by the owner's own road, «Dismiss» lets the request go.
 */
private fun groupRequestsPage(act: MainActivity, key: String, onBack: () -> Unit, onLeft: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) {}
    val stamp = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
    fun draw() {
        body.removeAllViews()
        val list = Groups.requests(c, key)
        if (list.isEmpty()) {
            body.addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                setPadding(dp(16), dp(24), dp(16), dp(24))
                addView(c.text(c.getString(R.string.gp_requests_none), 17f, Color.WHITE, bold = true, center = true), lp())
                gap(8)
                addView(c.text(c.getString(R.string.gp_requests_none_note), 15f, MT.gray, center = true), lp())
            }, lp())
            return
        }
        fun button(words: Int, tone: Int, onTap: () -> Unit) = c.text(c.getString(words), 17f, Color.WHITE, bold = true, center = true).apply {
            gravity = Gravity.CENTER
            minHeight = dp(44)
            background = c.rounded(tone, 12)
            pressable(onTap)
        }
        body.section(null, null, *list.map { r ->
            c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.peerFace(SamePair.root(r.pipe), r.name, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
                    addView(c.vstack(Gravity.NO_GRAVITY) {
                        addView(c.text(r.name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp())   // USER-DATA: the asker's name
                        addView(c.text(stamp.format(java.util.Date(r.at)), 12f, MT.gray), lp())   // USER-DATA: when they asked
                    }, lp(0, WRAP, 1f))
                }, lp())
                gap(8)
                addView(c.hstack {
                    addView(button(R.string.gp_requests_add, SysColor.blue) { Groups.approve(key, r.pipe); draw() }, lp(0, WRAP, 1f))
                    gap(10)
                    addView(button(R.string.gp_requests_dismiss, Color.rgb(57, 57, 61)) { Groups.dismiss(key, r.pipe); draw() }, lp(0, WRAP, 1f))
                }, lp())
            }
        }.toTypedArray())
    }
    draw()
    val page = settingsPage(act, c.getString(R.string.gp_requests), onBack) { addView(body, lp()) }
    // the editor counts again however the page leaves: its own mark or the system's back
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {}
        override fun onViewDetachedFromWindow(v: View) { onLeft() }
    })
    return page
}

/**
 * THE GROUP'S REMOVED USERS, AS THE REFERENCE'S PAGE KEEPS THEM (iOS MTGroupRemovedPage, G.7): everyone the owner or an administrator
 * took out; a tap offers «Add To Group» (added again by the owner's own road, the ban lifts) and «Delete» (let back, no longer kept out).
 */
private fun groupRemovedPage(act: MainActivity, key: String, onBack: () -> Unit, onLeft: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) {}
    fun draw() {
        body.removeAllViews()
        val rows = Groups.bannedPeople(c, key).map { p ->
            c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(6), dp(16), dp(6))
                minimumHeight = dp(52)
                addView(c.peerFace(SamePair.root(p.pipe), p.name, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
                addView(c.text(p.name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a removed person's name
                pressable {
                    AlertDialog.Builder(c).setTitle(p.name)   // USER-DATA: a person's name
                        .setItems(arrayOf(c.getString(R.string.gp_removed_add), c.getString(R.string.delete))) { _, i ->
                            if (i == 0) Groups.add(key, listOf(p.pipe)) else Groups.unban(key, p.seat)
                            draw()
                        }
                        .setNegativeButton(R.string.cancel, null).show()
                }
            }
        }
        body.section(c.getString(R.string.gp_removed_head), c.getString(R.string.gp_removed_note), *rows.toTypedArray())
    }
    draw()
    val page = settingsPage(act, c.getString(R.string.gp_removed), onBack) { addView(body, lp()) }
    // the editor counts again however the page leaves: its own mark or the system's back, which closes it without onBack
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {}
        override fun onViewDetachedFromWindow(v: View) { onLeft() }
    })
    return page
}

/** The rights' rows in the reference's own words (iOS MTAdminRight.title). */
private fun rightWord(r: String) = when (r) {
    Groups.INFO -> R.string.gp_r_info
    Groups.DELETE -> R.string.gp_r_delete
    Groups.BAN -> R.string.gp_r_ban
    Groups.INVITE -> R.string.gp_r_invite
    else -> R.string.gp_r_pin
}

/**
 * THE GROUP'S ADMINISTRATORS, AS THE REFERENCE'S PAGE LISTS THEM (iOS MTGroupAdminsPage, G.6): the owner first, every administrator
 * with its custom title or its role, each opening its rights; «Add Admin» chooses among the members.
 */
private fun groupAdminsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) {}
    fun role(seat: String, owner: Boolean) = c.text(Groups.rank(key, seat) ?: c.getString(if (owner) R.string.gp_owner_cap else R.string.gp_admin_cap), 17f, MT.gray)   // USER-DATA: the owner's custom title
    fun draw() {
        body.removeAllViews()
        val people = Groups.pagePeople(c, key)
        val admins = Groups.admins(key).mapNotNull { s -> people.firstOrNull { it.seat == s } }
        val rows = mutableListOf<View>()
        rows += c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            minimumHeight = dp(48)
            addView(c.text(Prefs.userName, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: my name
            addView(role(Groups.OWNER, owner = true))
        }
        admins.forEach { p ->
            rows += c.navRow(null, p.name, role(p.seat, owner = false)) {
                act.push { back -> groupAdminRightsPage(act, key, p.seat, p.name, isNew = false) { back(); draw() } }
            }
        }
        body.section(null, null, *rows.toTypedArray())
        body.section(null, c.getString(R.string.gp_add_admin_note), c.navRow(R.drawable.ic_person_add, c.getString(R.string.gp_add_admin), null) {
            act.push { back -> groupAdminPickPage(act, key) { back(); draw() } }
        })
    }
    draw()   // a rights page or «Add Admin» closed: the list is drawn again (iOS onAppear tick)
    return settingsPage(act, c.getString(R.string.gp_admins), onBack) { addView(body, lp()) }
}

/** «Add Admin» (iOS MTGroupAdminPickPage): the members who are none yet, each opening the rights it would have. */
private fun groupAdminPickPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val admins = Groups.admins(key)
    val people = Groups.pagePeople(c, key).filter { it.seat !in admins && it.seat != Groups.OWNER }
    return settingsPage(act, c.getString(R.string.gp_add_admin), onBack) {
        if (people.isNotEmpty()) section(null, null, *people.map { p ->
            c.navRow(null, p.name, null) {
                act.push { back -> groupAdminRightsPage(act, key, p.seat, p.name, isNew = true) { back(); onBack() } }
            }
        }.toTypedArray())
    }
}

/**
 * AN ADMINISTRATOR'S RIGHTS, AS THE REFERENCE'S PAGE KEEPS THEM (iOS MTGroupAdminRightsPage, G.6): the custom title, «What can this
 * admin do?» one switch a right, and «Dismiss Admin»; the checkmark names or renews the administrator, carried to every member.
 */
private fun groupAdminRightsPage(act: MainActivity, key: String, seat: String, name: String, isNew: Boolean, onBack: () -> Unit): View {
    val c: Context = act
    val taken = Groups.taken(key, seat).toMutableSet()
    val rank = EditText(c).apply {
        setText(Groups.rank(key, seat) ?: "")   // USER-DATA: the owner's custom title
        hint = c.getString(R.string.gp_admin)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        isSingleLine = true
        filters = arrayOf(android.text.InputFilter.LengthFilter(16))
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
    }
    fun hideKeys() = c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(rank.windowToken, 0)
    val done = c.icon(R.drawable.ic_check, Color.WHITE).apply {
        setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10))
        contentDescription = c.getString(R.string.gp_done)
        pressable { hideKeys(); Groups.setAdmin(key, seat, true, taken, rank.text.toString()); onBack() }
    }
    return settingsPage(act, c.getString(R.string.gp_rights), { hideKeys(); onBack() }, trailing = done) {
        section(null, null, c.text(name, 17f, Color.WHITE, bold = true).apply {   // USER-DATA: a person's name
            setPadding(dp(16), dp(12), dp(16), dp(12)); singleLineEllipsis()
        })
        section(c.getString(R.string.gp_rank), c.getString(R.string.gp_rank_note), rank)
        section(c.getString(R.string.gp_rights_q), null, *Groups.RIGHTS.map { r ->
            var ready = false   // the switch set to what is stored is not the owner's tap
            c.toggleRow(c.getString(rightWord(r))) { on ->
                if (!ready) return@toggleRow
                if (on) taken.remove(r) else taken.add(r)
            }.apply {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                (0 until childCount).map { getChildAt(it) }.filterIsInstance<Switch>().firstOrNull()?.isChecked = r !in taken
                ready = true
            }
        }.toTypedArray())
        if (!isNew) section(null, null, c.text(c.getString(R.string.gp_dismiss), 17f, SysColor.red).apply {
            setPadding(dp(16), dp(12), dp(16), dp(12)); minimumHeight = dp(48)
            pressable { hideKeys(); Groups.setAdmin(key, seat, false); onBack() }
        })
    }
}

// ─────────────────────────── chat history for new members (iOS MTGroupHistoryPage, G.4) ───────────────────────────

/**
 * CHAT HISTORY FOR NEW MEMBERS, AS THE REFERENCE'S PAGE ASKS IT (iOS MTGroupHistoryPage, G.4): «Visible» -- one added reads the
 * group's newest words; «Hidden» -- they begin where they came in, the reference's default. A tap is the choice (Groups.setHistory).
 */
private fun groupHistoryPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val marks = HashMap<Boolean, View>()
    lateinit var note: android.widget.TextView
    fun paint() {
        val on = Groups.history(key)
        marks.forEach { (v, m) -> m.alpha = if (v == on) 1f else 0f }
        note.text = c.getString(if (on) R.string.gp_history_on_note else R.string.gp_history_off_note)
    }
    fun choice(visible: Boolean, word: Int) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(12), dp(16), dp(12)); minimumHeight = dp(48)
        addView(c.text(c.getString(word), 17f, Color.WHITE), lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_check, Color.WHITE).also { marks[visible] = it }, lp(dp(20), dp(20)))
        pressable { Groups.setHistory(key, visible); paint() }
    }
    val page = settingsPage(act, c.getString(R.string.gp_history_title), onBack) {
        section(c.getString(R.string.gp_history_head), "", choice(true, R.string.gp_history_on), choice(false, R.string.gp_history_off))
        note = getChildAt(childCount - 1) as android.widget.TextView   // the section's words under it change with the choice
    }
    paint()
    return page
}

// ─────────────────────────── the members' permissions and slow mode (iOS MTGroupPermissionsPage, G.5) ───────────────────────────

/** The members' rights in the reference's own words (iOS MTGroupRight.title). */
private fun memberRightWord(r: String) = when (r) {
    Groups.M_TEXT -> R.string.gm_text
    Groups.M_PHOTOS -> R.string.gm_photos
    Groups.M_VIDEOS -> R.string.gm_videos
    Groups.M_STICKERS -> R.string.gm_stickers
    Groups.M_MUSIC -> R.string.gm_music
    Groups.M_FILES -> R.string.gm_files
    Groups.M_VOICE -> R.string.gm_voice
    Groups.M_ROUNDS -> R.string.gm_rounds
    Groups.M_LINKS -> R.string.gm_links
    Groups.M_REACTIONS -> R.string.gm_reactions
    Groups.M_PIN -> R.string.gp_r_pin
    else -> R.string.gp_r_info
}
/** A slow mode step's word (iOS MTGroupPermissionsPage.word): «Off», seconds, minutes, an hour, in the language's short units. */
private fun slowWord(c: Context, s: Int) = when {
    s <= 0 -> c.getString(R.string.gp_slow_off)
    s < 60 -> c.getString(R.string.gp_slow_s, s)
    s < 3600 -> c.getString(R.string.gp_slow_m, s / 60)
    else -> c.getString(R.string.gp_slow_h, s / 3600)
}

/**
 * THE GROUP'S PERMISSIONS, AS THE REFERENCE'S PAGE KEEPS THEM (iOS MTGroupPermissionsPage, G.5): «What can members of this group
 * do?» -- one switch a right, «Send Media» opening its own under it -- and «Slowmode» below; what the owner leaves goes to every
 * member as the page closes (Groups.setRights), one word for all the changes.
 */
private fun groupPermissionsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val barred = Groups.barred(key).toMutableSet()
    var slow = Groups.slow(key).let { s -> Groups.SLOW_STEPS.lastOrNull { it <= s } ?: 0 }
    var told = false
    fun tell() { if (!told) { told = true; Groups.setRights(key, barred, slow) } }
    var quiet = true   // the switches set to what is stored, or to each other, are not the owner's taps
    fun switchOf(row: android.widget.LinearLayout) = (0 until row.childCount).map { row.getChildAt(it) }.filterIsInstance<Switch>().first()
    val mediaSwitches = HashMap<String, Switch>()
    val mediaCount = c.text("", 17f, MT.gray)
    lateinit var mediaAll: Switch
    fun recount() {
        val left = Groups.MEDIA_RIGHTS.count { it !in barred }
        mediaCount.text = left.toString() + "/" + Groups.MEDIA_RIGHTS.size   // USER-DATA: a count
        quiet = true; mediaAll.isChecked = left == Groups.MEDIA_RIGHTS.size; quiet = false
    }
    fun toggle(r: String, indent: Int = 0) = c.toggleRow(c.getString(memberRightWord(r))) { on ->
        if (quiet) return@toggleRow
        if (on) barred.remove(r) else barred.add(r)
        if (r in Groups.MEDIA_RIGHTS) recount()
    }.apply {
        setPadding(dp(16 + indent), dp(10), dp(16), dp(10)); minimumHeight = dp(48)
        switchOf(this).isChecked = r !in barred
        if (r in Groups.MEDIA_RIGHTS) mediaSwitches[r] = switchOf(this)
    }
    // the nine of «Send Media», shown under it while it is open
    val mediaBox = c.vstack(Gravity.NO_GRAVITY) { visibility = View.GONE }
    Groups.MEDIA_RIGHTS.forEach { r ->
        mediaBox.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(16) })
        mediaBox.addView(toggle(r, indent = 20), lp())
    }
    val chevron = c.icon(R.drawable.ic_chevron_down, MT.gray, 14)
    // «Send Media» with how many of its own are left: the words open them, the switch turns them all (iOS mediaRow)
    val mediaRow = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(10), dp(16), dp(10)); minimumHeight = dp(48)
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(c.text(c.getString(R.string.gm_media), 15f), lp(WRAP, WRAP).apply { marginEnd = dp(6) })
            addView(mediaCount, lp(WRAP, WRAP).apply { marginEnd = dp(6) })
            addView(chevron, lp(dp(14), dp(14)))
            pressable {
                val open = mediaBox.visibility != View.VISIBLE
                mediaBox.visibility = if (open) View.VISIBLE else View.GONE
                chevron.rotation = if (open) 180f else 0f
            }
        }, lp(0, WRAP, 1f))
        mediaAll = c.toggleRow("") { on ->
            if (quiet) return@toggleRow
            Groups.MEDIA_RIGHTS.forEach { r -> if (on) barred.remove(r) else barred.add(r) }
            quiet = true; mediaSwitches.forEach { (r, sw) -> sw.isChecked = r !in barred }; quiet = false
            recount()
        }.let { row -> switchOf(row).also { row.removeView(it) } }
        addView(mediaAll)
    }
    recount()
    // SLOWMODE (iOS the slider over its steps): off, ten and thirty seconds, one, five and fifteen minutes, an hour
    val words = c.hstack {
        Groups.SLOW_STEPS.forEach { s -> addView(c.text(slowWord(c, s), 11f, if (s == slow) Color.WHITE else MT.gray, center = true), lp(0, WRAP, 1f)) }
    }
    fun paint() { for (i in 0 until words.childCount) (words.getChildAt(i) as android.widget.TextView).setTextColor(if (Groups.SLOW_STEPS[i] == slow) Color.WHITE else MT.gray) }
    val slider = android.widget.SeekBar(c).apply {
        max = Groups.SLOW_STEPS.size - 1
        progress = Groups.SLOW_STEPS.indexOf(slow).coerceAtLeast(0)
        setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(b: android.widget.SeekBar, p: Int, user: Boolean) { slow = Groups.SLOW_STEPS[p]; paint() }
            override fun onStartTrackingTouch(b: android.widget.SeekBar) {}
            override fun onStopTrackingTouch(b: android.widget.SeekBar) {}
        })
    }
    val slowBox = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(8), dp(8), dp(8), dp(10))
        addView(slider, lp(MATCH, dp(44)))
        addView(words, lp())
    }
    quiet = false
    val page = settingsPage(act, c.getString(R.string.gp_perms), { tell(); onBack() }) {
        section(c.getString(R.string.gp_perms_q), null, toggle(Groups.M_TEXT), c.vstack(Gravity.NO_GRAVITY) {
            addView(mediaRow, lp()); addView(mediaBox, lp())
        }, toggle(Groups.M_PIN), toggle(Groups.M_INFO))
        section(c.getString(R.string.gp_slow), c.getString(R.string.gp_slow_note), slowBox)
    }
    // the page leaving by the system's back too: what the owner left goes as it closes (iOS onDisappear)
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {}
        override fun onViewDetachedFromWindow(v: View) { tell() }
    })
    return page
}
