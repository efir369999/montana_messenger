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
    // together --, Files, Links, Music and Voice; a channel's Media and Video apart (iOS paneTabs, MontanaPeerInfoScreen 996 at 2315)
    val panes: Panes? = panesOf(act, key, group = true, onClose, toChat) {}
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
        // A SUBSCRIBER'S «MORE» ON A CHANNEL'S PAGE IS THE REPORT ALONE (iOS MontanaPeerInfoScreen 563-567 at 2315): «Leave» stands
        // among the page's buttons, and a channel's history is not the subscriber's to clear
        if (Groups.isChannel(key)) items.retainAll { it.first == c.getString(R.string.pi_report) }
        PopupMenu(c, v).apply {
            items.forEachIndexed { i, (t, _) -> menu.add(0, i, i, t) }
            setOnMenuItemClickListener { items[it.itemId].second(); true }
        }.show()
    }
    // THE PAGE'S BUTTONS under the head: a group's sound, search and «More»; a channel's as MTChannelPage.actions has them
    fun drawPlates() {
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
        // A CHANNEL'S BUTTONS (iOS MTChannelPage.actions, MontanaChannel 500-511): its owner's sound and search (the live stream
        // waits for the rooms), one out of it the same, a subscriber's sound, search, «Leave» asked first, and «More»
        val subscriber = Groups.isChannel(key) && !Groups.manages(key) && !Groups.isOut(key) && Book.chat(key) != null
        if (subscriber) plate(R.drawable.ic_leave, c.getString(R.string.ch_leave)) {
            AlertDialog.Builder(c).setTitle(R.string.gp_leave_channel_q)
                .setPositiveButton(R.string.gp_leave_channel) { _, _ -> Groups.leave(key); redraw() }
                .setNegativeButton(R.string.cancel, null).show()
        }
        if (!Groups.isChannel(key) || subscriber) plate(R.drawable.ic_more_horiz, c.getString(R.string.pi_more)) { v -> groupMore(v) }
        body.addView(plates, lp())
    }
    /**
     * A GROUP'S PAGE AS THE REFERENCE LAYS IT (iOS 1915a7f4, MTGroupPage): under the head its buttons -- its sound and «More» (no voice
     * chat is held on this phone, nor has a chat its own search yet) -- the description with its caption over its words, then the people
     * with no header: «Add Member» first for the owner, the owner, the administrators, everyone else by name, this phone among them.
     * A row: the face, the name, online under it, the role on a capsule of its own colour; a tap opens the person's page where this
     * phone holds their pipe, a hold names the deeds. The ways out stand in «More» and in the editor.
     */
    fun drawGroup() {
        val owns = Groups.manages(key)   // a group its owner ended is nobody's to add to or take from (iOS lines: g.mine && g.left != true)
        drawPlates()
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
            listOfNotNull(mySeat?.let { Person(it, Groups.myName(c), "", true) })
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
                    p.me -> c.avatar(SelfFace.load(c), p.name, 40)
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
        if (channel) drawPlates()
        if (!channel) {
            drawGroup()
            panes?.let { p ->
                body.addView(p.bar, lp(MATCH, c.dp(44)).apply { topMargin = c.dp(24) })
                body.addView(p.pane, lp())
                p.heard()
            }
            return
        }
        // THE CHANNEL'S DESCRIPTION (iOS sections .about, data.kind == .group holds a channel too): the owner's words, read by all
        Groups.about(key).takeIf { it.isNotEmpty() }?.let { about ->
            body.section(null, null, c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.text(about, 17f, Color.WHITE).apply { setTextIsSelectable(true) }, lp())   // USER-DATA: the owner's words
                addView(c.text(c.getString(R.string.gp_about), 13f, MT.gray), lp())
            })
        }
        // A CHANNEL'S ROWS, AS THE REFERENCE'S CHANNEL PAGE HAS THEM (iOS channelRows, MontanaPeerInfoScreen 404-420): its owner's
        // «Administrators» and «Subscribers» with their numbers and «Channel Settings»; an administrator who may change its info or
        // hand its link sees the settings alone; a subscriber sees no people of the channel
        val rows = mutableListOf<View>()
        val settings = { act.push { back -> groupEditPage(act, key, back) { back(); onClose() } }; Unit }
        if (Groups.manages(key)) {
            val admins = 1 + Groups.admins(key).size   // the reference counts its owner among them
            rows += c.navRow(R.drawable.ic_checkmark_shield, c.getString(R.string.gp_admins), c.text("$admins", 17f, MT.gray)) {
                act.push { back -> groupAdminsPage(act, key) { back(); draw() } }   // the number counted again on the way back
            }
            rows += c.navRow(R.drawable.ic_app_groups, c.getString(R.string.ch_subscribers), c.text("${Groups.count(key) ?: 1}", 17f, MT.gray)) {
                act.push { back -> channelPeoplePage(act, key) { back(); draw() } }
            }
            rows += c.navRow(R.drawable.ic_settings, c.getString(R.string.ch_settings), null, settings)
        } else if (Groups.mayChangeInfo(key) || Groups.heldLink(key) != null) rows += c.navRow(R.drawable.ic_settings, c.getString(R.string.ch_settings), null, settings)
        if (!owns && !Groups.isOut(key)) rows += actionRow(R.drawable.ic_leave, c.getString(R.string.gp_leave_channel), red = true) {
            AlertDialog.Builder(c).setTitle(R.string.gp_leave_channel_q)
                .setPositiveButton(R.string.gp_leave_channel) { _, _ -> Groups.leave(key); draw() }
                .setNegativeButton(R.string.cancel, null).show()
        }
        if (rows.isNotEmpty()) body.section(null, null, *rows.toTypedArray())
        panes?.let { p ->   // the channel's panes under its rows, as a group's stand under its people
            body.addView(p.bar, lp(MATCH, c.dp(44)).apply { topMargin = c.dp(24) })
            body.addView(p.pane, lp())
            p.heard()
        }
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
    val channel = Groups.isChannel(key)
    val name = EditText(c).apply {
        setText(Book.chat(key)?.shown ?: "")   // USER-DATA: the group's title
        hint = c.getString(if (channel) R.string.ch_name else R.string.gr_name)
        // an administrator who may only invite reads the name (iOS MontanaPeerInfoScreen 663, G.6)
        val named = Groups.mayChangeInfo(key)
        isEnabled = named
        setTextColor(if (named) Color.WHITE else MT.gray); setHintTextColor(MT.gray)
        background = null
        isSingleLine = true
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
    }
    // THE DESCRIPTION, AS THE REFERENCE'S GROUP EDITOR HAS IT (iOS stage R): written by the owner, carried to every member (Groups.renew);
    // a channel's by its owner alone (iOS MontanaPeerInfoScreen editor, mayChangeInfo)
    val described = !channel || Groups.mayChangeInfo(key)
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
        Groups.renew(key, name.text.toString(), face, if (described) about.text.toString() else null)
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
                    if (described) {
                        gap(20)
                        addView(c.plate { addView(about, lp()) }, lp())
                        addView(c.text(c.getString(if (channel) R.string.ch_about_note else R.string.gp_about_note), 13f, MT.gray).apply { setPadding(dp(16), dp(6), dp(16), 0) }, lp())
                    }
                    if (!channel && Groups.manages(key)) {
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
                    } else if (channel && Groups.manages(key)) {
                        // THE CHANNEL'S LINK, THE PEOPLE TAKEN OUT AND ITS END, where the reference's channel settings keep them
                        // (iOS MontanaPeerInfoScreen editor 683-711; Discussion, Reactions and Recent Actions come with their own pages)
                        gap(20)
                        val links = c.navRow(R.drawable.ic_link, c.getString(R.string.gp_links), null) {
                            act.push { back -> groupLinksPage(act, key, back) }
                        }
                        // «Discussion» (iOS editor 689): «Allow Comments» on its own page
                        val talk = c.navRow(R.drawable.ic_set_textbubble, c.getString(R.string.ch_discussion), null) {
                            act.push { back -> channelDiscussionPage(act, key, back) }
                        }
                        // «Reactions» (iOS editor 692-695): «Disabled», the number of the owner's list, or «All Reactions»
                        val said = c.text("", 17f, MT.gray)
                        fun reread() {
                            said.text = when {
                                !Groups.reactionsOn(key) -> c.getString(R.string.ch_reactions_off)
                                else -> Groups.reactionList(key)?.size?.toString() ?: c.getString(R.string.ch_reactions_all)   // USER-DATA: a count
                            }
                        }
                        reread()
                        val reactions = c.navRow(R.drawable.ic_face_smiling, c.getString(R.string.ch_reactions), said) {
                            act.push { back -> channelReactionsPage(act, key, back) { reread() } }
                        }
                        addView(c.plate { addView(links, lp()); divider(); addView(talk, lp()); divider(); addView(reactions, lp()) }, lp())
                        gap(20)
                        val removed = c.text("", 17f, MT.gray)
                        fun reweigh() { removed.text = Groups.bannedPeople(c, key).size.toString() }   // USER-DATA: a count
                        reweigh()
                        val out = c.navRow(R.drawable.ic_hand, c.getString(R.string.gp_removed), removed) {
                            act.push { back -> groupRemovedPage(act, key, back) { reweigh() } }
                        }
                        // «Recent Actions» under the people taken out (iOS editor 699-707)
                        val deeds = c.navRow(R.drawable.ic_clock_arrow, c.getString(R.string.ch_recent_actions), null) {
                            act.push { back -> channelActionsPage(act, key, back) }
                        }
                        addView(c.plate { addView(out, lp()); divider(); addView(deeds, lp()) }, lp())
                        gap(20)
                        addView(c.plate {
                            addView(c.text(c.getString(R.string.ch_dissolve), 17f, SysColor.red).apply {
                                setPadding(dp(16), dp(12), dp(16), dp(12)); minimumHeight = dp(48); gravity = Gravity.CENTER_VERTICAL
                                pressable {
                                    AlertDialog.Builder(c).setMessage(R.string.ch_dissolve_q)   // the whole question, as the reference asks it
                                        .setPositiveButton(R.string.ch_dissolve) { _, _ -> Groups.dissolve(key); onGone() }
                                        .setNegativeButton(R.string.cancel, null).show()
                                }
                            }, lp())
                        }, lp())
                    } else if (Groups.heldLink(key) != null) {
                        // an administrator who may invite holds the link the owner handed it (iOS MontanaPeerInfoScreen 795-801, G.6)
                        gap(20)
                        val links = c.navRow(R.drawable.ic_link, c.getString(R.string.gp_links), null) {
                            act.push { back -> groupLinksPage(act, key, back) }
                        }
                        addView(c.plate { addView(links, lp()) }, lp())
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
    val channel = Groups.isChannel(key)   // a channel's page has its own words and no approval (iOS MTChannelInviteLinksPage)
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
        // the owner's own link, or -- to an administrator who may invite (iOS MTGroupInviteLinksPage onAppear, G.6) -- the one the owner handed it
        val l = Groups.inviteLink(act, key) ?: Groups.heldLink(key)
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
            AlertDialog.Builder(c).setMessage(if (channel) R.string.ch_link_revoke_q else R.string.gp_link_revoke_q)
                .setPositiveButton(R.string.gp_link_revoke_do) { _, _ -> Groups.resetInvite(key); shown.text = "…"; link = null; fetch() }
                .setNegativeButton(R.string.cancel, null).show()
        }
    }
    fetch()
    return settingsPage(act, c.getString(R.string.gp_links), onBack) {
        section(c.getString(R.string.gp_link_head), c.getString(if (channel) R.string.ch_link_note else R.string.gp_link_note), c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(12), dp(16), dp(12))
            addView(shown, lp())
            gap(12)
            addView(c.hstack {
                addView(copy, lp(0, WRAP, 1f))
                gap(12)
                addView(share, lp(0, WRAP, 1f))
            }, lp())
        })
        if (!Groups.manages(key)) return@settingsPage   // the owner alone asks first and ends the links given before
        // THE LINK ASKS THE OWNER FIRST (iOS MTGroupInviteLinksPage, G.8): who opens it waits among the requests
        if (!channel) {
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
        }
        if (!channel || Groups.manages(key)) section(null, null, revoke)
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
    val channel = Groups.isChannel(key)   // a channel's page has its own words (iOS MTChannelRemovedPage)
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
                        .setItems(arrayOf(c.getString(if (channel) R.string.ch_removed_add else R.string.gp_removed_add), c.getString(R.string.delete))) { _, i ->
                            if (i == 0) Groups.add(key, listOf(p.pipe)) else Groups.unban(key, p.seat)
                            draw()
                        }
                        .setNegativeButton(R.string.cancel, null).show()
                }
            }
        }
        body.section(c.getString(R.string.gp_removed_head), c.getString(if (channel) R.string.ch_removed_note else R.string.gp_removed_note), *rows.toTypedArray())
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
/** A channel's administrator's right in the reference's words (iOS MTChannelRight.title). */
private fun channelRightWord(r: String) = when (r) {
    Groups.INFO -> R.string.ch_r_info
    Groups.POST -> R.string.ch_r_post
    Groups.DELETE -> R.string.ch_r_delete
    else -> R.string.gr_add_subscribers
}

private fun rightWord(r: String) = when (r) {
    Groups.INFO -> R.string.gp_r_info
    Groups.DELETE -> R.string.gp_r_delete
    Groups.BAN -> R.string.gp_r_ban
    Groups.INVITE -> R.string.gp_r_invite
    else -> R.string.gp_r_pin
}

/**
 * A CHANNEL'S SUBSCRIBERS, AS THE REFERENCE LISTS THEM (iOS MTChannelPeoplePage, MontanaChannel 514-576): «Add Subscribers» first for
 * its owner, then every person; the owner's swipe or hold takes one out, asked «Remove from the channel?» first.
 */
private fun channelPeoplePage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) {}
    fun draw() {
        body.removeAllViews()
        val manages = Groups.manages(key)
        if (manages) body.section(null, null, c.navRow(R.drawable.ic_person_add, c.getString(R.string.gr_add_subscribers), null) {
            act.push { close -> groupPickPage(act, { close(); draw() }, {}, adding = key) }
        })
        val rows = Groups.pagePeople(c, key).map { p ->
            val remove = {
                AlertDialog.Builder(c).setTitle(R.string.ch_remove_q)
                    .setPositiveButton(R.string.gp_remove) { _, _ -> Groups.remove(key, p.seat); draw() }
                    .setNegativeButton(R.string.cancel, null).show()
                Unit
            }
            val row = c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(6), dp(16), dp(6))
                minimumHeight = dp(52)
                val face = if (p.pipe.isEmpty()) c.avatar(null, p.name, 40) else c.peerFace(SamePair.root(p.pipe), p.name, 40)
                addView(face, lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
                addView(c.text(p.name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a subscriber's name
                if (manages) setOnLongClickListener {
                    AlertDialog.Builder(c).setTitle(p.name)   // USER-DATA: a subscriber's name
                        .setItems(arrayOf(c.getString(R.string.gp_remove))) { _, _ -> remove() }
                        .setNegativeButton(R.string.cancel, null).show()
                    true
                }
            }
            if (!manages) row else SwipeRow(act, row, listOf(Tile(R.drawable.ic_delete, red = true) { remove() }), ground = GLASS_TONE or (0xFF shl 24))
        }
        if (rows.isNotEmpty()) body.section(null, null, *rows.toTypedArray())
    }
    draw()
    return settingsPage(act, c.getString(R.string.ch_subscribers), onBack) { addView(body, lp()) }
}

/**
 * THE GROUP'S ADMINISTRATORS, AS THE REFERENCE'S PAGE LISTS THEM (iOS MTGroupAdminsPage, G.6): the owner first, every administrator
 * with its custom title or its role, each opening its rights; «Add Admin» chooses among the members.
 */
private fun groupAdminsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    if (Groups.isChannel(key)) return channelAdminsPage(act, key, onBack)
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
            addView(c.text(Groups.myName(c), 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: my name, cut as it goes out (iOS MTGroup.clean)
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

/**
 * A CHANNEL'S ADMINISTRATORS, AS THE REFERENCE'S PAGE LISTS THEM (iOS MTChannelAdminsPage, MontanaChannel 631-736): «Channel Admins» --
 * the owner, every administrator opening its rights, the owner's swipe or hold dismissing one, «Add Admin» under them; then «Sign
 * Messages». A channel's admins wear their role, no custom title.
 */
private fun channelAdminsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) {}
    fun draw() {
        body.removeAllViews()
        val owns = Groups.manages(key)
        val people = Groups.pagePeople(c, key)
        val admins = Groups.admins(key).mapNotNull { s -> people.firstOrNull { it.seat == s } }
        fun role(word: Int) = c.text(c.getString(word), 17f, MT.gray)
        val rows = mutableListOf<View>()
        rows += c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            minimumHeight = dp(48)
            addView(c.text(Groups.myName(c), 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: my name
            addView(role(R.string.gp_owner_cap))
        }
        admins.forEach { p ->
            val dismiss = { Groups.setAdmin(key, p.seat, false); draw() }
            val row = c.navRow(null, p.name, role(R.string.gp_admin_cap)) {
                if (owns) act.push { back -> groupAdminRightsPage(act, key, p.seat, p.name, isNew = false) { back(); draw() } }
            }
            if (owns) row.setOnLongClickListener {
                AlertDialog.Builder(c).setTitle(p.name)   // USER-DATA: an administrator's name
                    .setItems(arrayOf(c.getString(R.string.gp_dismiss))) { _, _ -> dismiss() }
                    .setNegativeButton(R.string.cancel, null).show()
                true
            }
            rows += if (!owns) row else SwipeRow(act, row, listOf(Tile(R.drawable.ic_minus_circle, red = true) { dismiss() }), ground = GLASS_TONE or (0xFF shl 24))
        }
        if (owns) rows += c.navRow(R.drawable.ic_person_add, c.getString(R.string.gp_add_admin), null) {
            act.push { back -> groupAdminPickPage(act, key) { back(); draw() } }
        }
        body.section(c.getString(R.string.ch_admins_head), c.getString(R.string.ch_add_admin_note), *rows.toTypedArray())
        // «Sign Messages» (iOS Toggle → MTGroup.setSigns): every subscriber hears it by the invitation's word again
        if (owns) body.section(null, c.getString(R.string.ch_sign_note), c.toggleRow(c.getString(R.string.ch_sign)) { on -> Groups.setSigns(key, on) }.apply {
            setPadding(dp(16), dp(10), dp(16), dp(10))
            (0 until childCount).map { getChildAt(it) }.filterIsInstance<Switch>().firstOrNull()?.isChecked = Groups.signsOn(key)
        })
    }
    draw()   // a rights page or «Add Admin» closed: the list is drawn again (iOS tick)
    return settingsPage(act, c.getString(R.string.gp_admins), onBack) { addView(body, lp()) }
}

/**
 * WHAT A CHANNEL'S POSTS TAKE, AS THE REFERENCE'S PAGE KEEPS IT (iOS MTChannelReactionsPage, MontanaChannel 738-800): «Allow
 * Reactions», and while on, «Available Reactions» -- six to a row, the chosen bright with a check, the rest dim; at least one stays,
 * every one chosen is the whole choice. Every subscriber hears it by the invitation's word again.
 */
private fun channelReactionsPage(act: MainActivity, key: String, onBack: () -> Unit, onChange: () -> Unit): View {
    val c: Context = act
    val all = QuickReactions.channelChoice
    val chosen = (Groups.reactionList(key) ?: all).toMutableSet()
    val body = c.vstack(Gravity.NO_GRAVITY) {}
    fun draw() {
        body.removeAllViews()
        val on = Groups.reactionsOn(key)
        body.section(null, c.getString(R.string.ch_allow_reactions_note), c.toggleRow(c.getString(R.string.ch_allow_reactions)) { v ->
            if (v != Groups.reactionsOn(key)) { Groups.setReactions(key, v); onChange(); body.post { draw() } }   // the switch set while drawn changes nothing
        }.apply {
            setPadding(dp(16), dp(10), dp(16), dp(10))
            (0 until childCount).map { getChildAt(it) }.filterIsInstance<Switch>().firstOrNull()?.isChecked = on
        })
        if (!on) return
        val grid = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(10), dp(6), dp(10), dp(6)) }
        for (row in all.chunked(6)) {
            grid.addView(c.hstack {
                for (e in row) addView(FrameLayout(c).apply {
                    val glyph = c.text(e, 28f, center = true).apply { alpha = if (e in chosen) 1f else 0.3f }
                    addView(glyph, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER))
                    val tick = c.icon(R.drawable.ic_set_check_circle, Color.WHITE, 13).apply { visibility = if (e in chosen) View.VISIBLE else View.GONE }
                    addView(tick, FrameLayout.LayoutParams(dp(13), dp(13), Gravity.CENTER).apply { leftMargin = dp(16); topMargin = dp(16) })
                    contentDescription = e   // USER-DATA: a reaction's glyph
                    // one in or out: at least one stays (none at all is «Allow Reactions» off); every one chosen is the whole choice
                    pressable {
                        if (e in chosen) { if (chosen.size == 1) return@pressable; chosen.remove(e) } else chosen.add(e)
                        glyph.alpha = if (e in chosen) 1f else 0.3f
                        tick.visibility = if (e in chosen) View.VISIBLE else View.GONE
                        Groups.setReactionList(key, if (chosen.size == all.size) null else all.filter { it in chosen })
                        onChange()   // the editor's row says it at once: the system's back closes the page past onBack
                    }
                }, lp(0, dp(48), 1f))
                repeat(6 - row.size) { addView(View(c), lp(0, dp(48), 1f)) }
            }, lp(MATCH, WRAP))
        }
        body.section(c.getString(R.string.ch_available_reactions), null, grid)
    }
    draw()
    return settingsPage(act, c.getString(R.string.ch_reactions), onBack) { addView(body, lp()) }
}

/**
 * WHAT WAS DONE IN A CHANNEL, AS THE REFERENCE'S PAGE SHOWS IT (iOS MTChannelActionsPage, MontanaChannel 847-903): the deeds of the last
 * two days, newest first, each in the reference's words with its moment; none -- «No actions here yet».
 */
private fun channelActionsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val acts = Groups.recentActs(key)
    return settingsPage(act, c.getString(R.string.ch_recent_actions), onBack) {
        if (acts.isEmpty()) {
            addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                setPadding(dp(16), dp(36), dp(16), dp(36))
                addView(c.text(c.getString(R.string.ch_no_actions), 17f, Color.WHITE, bold = true, center = true), lp(MATCH, WRAP))
                gap(8)
                addView(c.text(c.getString(R.string.ch_no_actions_note), 15f, MT.gray, center = true), lp(MATCH, WRAP))
            }, lp())
            return@settingsPage
        }
        val moment = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
        section(null, null, *acts.map { a ->
            c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.text(actWords(c, a), 17f, Color.WHITE), lp())   // USER-DATA: the people's names inside the catalogue's sentence
                gap(3)
                addView(c.text(moment.format(java.util.Date(a.at)), 12f, MT.gray), lp())   // USER-DATA: the deed's moment
            }
        }.toTypedArray())
    }
}

/** A CHANNEL'S DISCUSSION (iOS MTChannelDiscussionPage, MontanaChannel 1045-1061): «Allow Comments» -- every post then wears its
 *  comments' footer on every subscriber's phone; the comments ride the channel itself, no group hosts them. */
private fun channelDiscussionPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val row = c.toggleRow(c.getString(R.string.ch_allow_comments)) { v -> if (v != Groups.talks(key)) Groups.setTalks(key, v) }.apply {
        setPadding(dp(16), dp(10), dp(16), dp(10))
        (0 until childCount).map { getChildAt(it) }.filterIsInstance<Switch>().firstOrNull()?.isChecked = Groups.talks(key)
    }
    return settingsPage(act, c.getString(R.string.ch_discussion), onBack) {
        addView(c.vstack(Gravity.NO_GRAVITY) { section(null, c.getString(R.string.ch_allow_comments_note), row) }, lp())
    }
}

/**
 * THE COMMENTS OF A POST (iOS MTChannelCommentsSheet, MontanaChannel 966-1041): the post's words over the comments, each with its
 * speaker's name in their colour and its moment; while comments are on and I am inside, the field under them, and the slowmode's
 * words while this phone waits (Groups.commentWait). The list follows the book as comments come.
 */
internal fun channelCommentsPage(act: MainActivity, key: String, post: Msg, onBack: () -> Unit): View {
    val c: Context = act
    val list = ChannelComments.comments(post.mid, key)
    val title = if (list.isEmpty()) c.getString(R.string.ch_comments) else c.resources.getQuantityString(R.plurals.ch_comments_n, list.size, list.size)
    val rows = c.vstack(Gravity.NO_GRAVITY) {}
    val time = android.text.format.DateFormat.getTimeFormat(c)
    fun fill() {
        rows.removeAllViews()
        val now = ChannelComments.comments(post.mid, key)
        rows.background = c.rounded(MT.plate, 12)
        if (now.isEmpty()) rows.addView(c.text(c.getString(R.string.ch_no_comments), 17f, MT.gray, center = true).apply {
            setPadding(dp(16), dp(24), dp(16), dp(24))
        }, lp(MATCH, WRAP))
        for (cm in now) rows.addView(c.vstack(Gravity.NO_GRAVITY) {
            setPadding(dp(16), dp(8), dp(16), dp(8))
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                val who = if (cm.mine) Groups.myName(c) else cm.name.ifEmpty { c.getString(R.string.gr_member) }
                addView(c.text(who, 15f, Groups.tint(Groups.speakerOf(key, cm.seat)), bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the speaker's name
                addView(c.text(time.format(java.util.Date(cm.at)), 11f, MT.gray), lp(WRAP, WRAP))   // USER-DATA: the comment's moment
            }, lp(MATCH, WRAP))
            gap(3)
            addView(c.text(cm.text, 17f, Color.WHITE), lp(MATCH, WRAP))   // USER-DATA: the comment's words
        }, lp(MATCH, WRAP))
    }
    fill()
    val heard: () -> Unit = { fill() }
    return settingsPage(act, title, onBack, cross = true) {
        val words = post.text.takeIf { !Marks.isService(it) }.orEmpty()
        if (words.isNotEmpty()) addView(c.vstack(Gravity.NO_GRAVITY) {
            section(null, null, c.text(words, 17f, Color.WHITE).apply { maxLines = 8; ellipsize = android.text.TextUtils.TruncateAt.END; setPadding(dp(16), dp(12), dp(16), dp(12)) })   // USER-DATA: the post's words
        }, lp())
        addView(rows, lp(MATCH, WRAP).apply { setMargins(dp(16), dp(12), dp(16), dp(12)) })
        if (Groups.talks(key) && !Groups.isOut(key)) {
            // THE FIELD SAYS WHAT IS LEFT (the reference's slowmode words): one comment in thirty seconds (Groups.COMMENT_GAP)
            val slow = c.text("", 13f, MT.gray, center = true).apply { visibility = View.GONE; setPadding(dp(16), 0, dp(16), dp(4)) }
            val field = EditText(c).apply {
                hint = c.getString(R.string.ch_comment)
                setTextColor(Color.WHITE); setHintTextColor(MT.gray)
                background = c.rounded(MT.plate, 22)
                minLines = 1; maxLines = 5
                setPadding(dp(14), dp(11), dp(14), dp(11))
            }
            val send = c.icon(R.drawable.ic_arrow_up, Color.WHITE, 22).apply {
                background = c.rounded(MT.blue, 18); setPadding(dp(7), dp(7), dp(7), dp(7))
                contentDescription = c.getString(R.string.send)
            }
            fun ready() { send.alpha = if (field.text.toString().isBlank()) 0.4f else 1f }
            field.addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun afterTextChanged(s: android.text.Editable?) = ready()
            })
            ready()
            send.setOnClickListener {
                if (field.text.toString().isBlank()) return@setOnClickListener
                if (Groups.comment(field.text.toString(), post.mid, key)) field.setText("")
            }
            val tick = object : Runnable {
                override fun run() {
                    val wait = Groups.commentWait(key)
                    slow.visibility = if (0 < wait) View.VISIBLE else View.GONE
                    if (0 < wait) slow.text = c.getString(R.string.ch_slowmode, String.format(java.util.Locale.ROOT, "0:%02d", wait))
                    slow.postDelayed(this, 1000)
                }
            }
            addView(slow, lp(MATCH, WRAP))
            addView(c.hstack {
                gravity = Gravity.BOTTOM
                setPadding(dp(12), dp(8), dp(12), dp(8))
                addView(field, lp(0, WRAP, 1f).apply { marginEnd = dp(8) })
                addView(send, lp(dp(36), dp(36)).apply { bottomMargin = dp(4) })
            }, lp(MATCH, WRAP))
            slow.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) { tick.run() }
                override fun onViewDetachedFromWindow(v: View) { v.removeCallbacks(tick) }
            })
        }
        rows.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { ChannelComments.listen(heard); fill() }
            override fun onViewDetachedFromWindow(v: View) { ChannelComments.unlisten(heard) }
        })
    }.apply { standAboveKeys() }
}

/** The deed in the reference's words, its doer this phone's owner (iOS MTChannelActionsPage.words). */
private fun actWords(c: Context, a: Groups.Act): String {
    val names = (a.p ?: emptyList()).map { it.ifEmpty { c.getString(R.string.gr_member) } }.joinToString(", ")
    return when (a.e) {
        "invited" -> c.getString(R.string.cha_invited, names)
        "joined" -> c.getString(R.string.cha_joined, names)
        "removed" -> c.getString(R.string.cha_removed, names)
        "left" -> c.getString(R.string.cha_left, names)
        "title" -> c.getString(R.string.cha_title, a.t ?: "")
        "about" -> c.getString(R.string.cha_about)
        "photo" -> c.getString(R.string.cha_photo)
        "promoted" -> c.getString(R.string.cha_promoted, names)
        "demoted" -> c.getString(R.string.cha_demoted, names)
        "signOn" -> c.getString(R.string.cha_sign_on)
        "signOff" -> c.getString(R.string.cha_sign_off)
        "reactOn" -> c.getString(R.string.cha_react_on)
        "reactSome" -> c.getString(R.string.cha_react_some)
        "talkOn" -> c.getString(R.string.cha_talk_on)
        "talkOff" -> c.getString(R.string.cha_talk_off)
        else -> c.getString(R.string.cha_react_off)
    }
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
        pressable {
            hideKeys(); Groups.setAdmin(key, seat, true, taken, rank.text.toString())
            if (Groups.INVITE !in taken) act.background { Groups.handLink(act, key) }   // the link to an admin who invites, once a card stands
            onBack()
        }
    }
    // a channel's administrator has its own rights and no custom title (iOS MTChannelAdminRightsPage, MTChannelRight)
    val channel = Groups.isChannel(key)
    return settingsPage(act, c.getString(R.string.gp_rights), { hideKeys(); onBack() }, trailing = done) {
        section(null, null, c.text(name, 17f, Color.WHITE, bold = true).apply {   // USER-DATA: a person's name
            setPadding(dp(16), dp(12), dp(16), dp(12)); singleLineEllipsis()
        })
        if (!channel) section(c.getString(R.string.gp_rank), c.getString(R.string.gp_rank_note), rank)
        section(c.getString(if (channel) R.string.ch_rights_q else R.string.gp_rights_q), null, *Groups.rights(key).map { r ->
            var ready = false   // the switch set to what is stored is not the owner's tap
            c.toggleRow(c.getString(if (channel) channelRightWord(r) else rightWord(r))) { on ->
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
