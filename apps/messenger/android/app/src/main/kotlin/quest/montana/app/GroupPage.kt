package quest.montana.app

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.text.SpannableString
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.PopupMenu
import android.widget.Toast

// ─────────────────────────── the group's and the channel's page (iOS MontanaPeerInfoScreen isGroupPage / isChannelPage, MTGroupPage.swift) ───────────────────────────

/**
 * THE GROUP'S PAGE IS THE PERSON'S PAGE (iOS one MontanaPeerInfoScreen, the author's words 17.10.2026 18:4x-18:5x MSK: «channels and
 * groups fully as in the reference folder, 1 to 1»): its head, plates, rows and panes are said for a group and a channel here and
 * laid by the one page (peerInfoPage). `onGone` — the group left this phone (left and deleted, or deleted for everyone): the page and
 * its chat close.
 */
fun groupPage(act: MainActivity, key: String, onClose: () -> Unit, onGone: () -> Unit = onClose, onSearch: () -> Unit = onClose): View =
    peerInfoPage(act, key, onClose, onGone = onGone, onSearch = onSearch)

/**
 * «N members, M online» (iOS MTGroupPage.head), said once for the chat's top and the page alike: M is this phone and whoever of the
 * group it sees online -- the owner's phone everyone it carries to, a member's phone the owner. A channel says «N subscribers»
 * (iOS MTChannelPage.head), the owner counted among them.
 */
fun groupHead(c: Context, key: String): String {
    val n = Groups.people(key) ?: 1
    if (Groups.isChannel(key)) return c.resources.getQuantityString(R.plurals.gpg_subscribers, n, n)
    val members = c.resources.getQuantityString(R.plurals.gr_members, n, n)
    val lit = 1 + Groups.heldConversations(key).count { Presence.word(c, it)?.second == true }
    return if (lit == 1) members else members + ", " + c.resources.getQuantityString(R.plurals.gpg_online, lit, lit)
}

/** THE GROUP'S HEAD ON ITS PAGE (iOS MTPeerHeader, MontanaPeerHeader.swift:40-80): the face 100, the name in title2 bold, the count, 8 between. */
internal fun groupHeadView(c: Context, key: String): View {
    val title = Book.chat(key)?.shown?.ifBlank { null } ?: ""
    return c.vstack(Gravity.CENTER_HORIZONTAL) {
        setPadding(dp(16), dp(4), dp(16), 0)
        addView(c.peerFace(key, title, 100), lp(dp(100), dp(100)))
        gap(8)
        addView(c.text(title, 22f, Color.WHITE, bold = true, center = true), lp(WRAP, WRAP))   // USER-DATA: the group's title
        gap(8)
        addView(c.text(groupHead(c, key), 15f, MT.gray, center = true), lp(WRAP, WRAP))   // USER-DATA: the people's count
    }
}

/** One plate of the page's row (iOS MTPeerAction): its glyph, its spoken name and its deed; the page lays them (peerInfoPage). */
internal class Plate(val icon: Int, val label: Int, val work: (View) -> Unit)

/**
 * THE GROUP'S BUTTONS, AS THE REFERENCE'S GROUP PAGE HAS THEM (iOS pageActions 579-589): its sound and its search, more; a channel's
 * (iOS MTChannelPage.actions): the owner's sound and search, a subscriber's sound, search, the way out and more. A voice chat and a
 * live stream stand where a room may be held (the rooms' stage).
 */
internal fun groupPlates(act: MainActivity, key: String, onSearch: () -> Unit, onGone: () -> Unit, redraw: () -> Unit): List<Plate> {
    val c: Context = act
    val sound = if (ChatMarks.isMuted(key)) Plate(R.drawable.ic_bell_off, R.string.gpg_unmute) { ChatMarks.toggleMute(key); redraw() }
        else Plate(R.drawable.ic_bell_fill, R.string.gpg_mute) { ChatMarks.toggleMute(key); redraw() }
    // the chat's own search: the page goes down to its chat (iOS perform .search)
    val search = Plate(R.drawable.ic_search, R.string.gpg_search) { onSearch() }
    if (Groups.isChannel(key)) {
        if (Groups.owns(key) || Groups.people(key) == null || Groups.isOut(key)) return listOf(sound, search)
        return listOf(sound, search,
            Plate(R.drawable.ic_leave, R.string.gpg_leave) { askLeave(act, key, onGone) },
            // A SUBSCRIBER'S «MORE» ON A CHANNEL'S PAGE (iOS 552-556): the report
            Plate(R.drawable.ic_more_horiz, R.string.gpg_more) { v ->
                PopupMenu(c, v).apply {
                    menu.add(c.getString(R.string.gpg_report)).setOnMenuItemClickListener { report(act, key); true }
                }.show()
            })
    }
    return listOf(sound, search, Plate(R.drawable.ic_more_horiz, R.string.gpg_more) { v -> groupMore(act, key, v, onGone) })
}

/**
 * A GROUP'S «MORE», AS THE REFERENCE'S MENU HAS IT (iOS groupMore 428-443): «Report» for one who does not own it, «Clear Messages»,
 * then the way out in red -- «Leave Group» for a member, «Delete Group» for its owner -- each asked first.
 */
private fun groupMore(act: MainActivity, key: String, anchor: View, onGone: () -> Unit) {
    val c: Context = act
    fun red(res: Int) = SpannableString(c.getString(res)).apply { setSpan(ForegroundColorSpan(SysColor.red), 0, length, 0) }
    PopupMenu(c, anchor).apply {
        if (!Groups.owns(key)) menu.add(c.getString(R.string.gpg_report)).setOnMenuItemClickListener { report(act, key); true }
        menu.add(c.getString(R.string.gpg_clear)).setOnMenuItemClickListener { askClear(act, key); true }
        if (Groups.people(key) != null && !Groups.isOut(key)) {
            if (Groups.owns(key)) menu.add(red(R.string.gpg_delete_group)).setOnMenuItemClickListener { askDissolve(act, key, onGone); true }
            else menu.add(red(R.string.gpg_leave_group)).setOnMenuItemClickListener { askLeave(act, key, onGone); true }
        }
    }.show()
}

private fun title(c: Context, key: String) = Book.chat(key)?.shown?.ifBlank { null } ?: ""
private fun report(act: MainActivity, key: String) = act.push { close -> reportPage(act, key, title(act, key), offersBlock = false) { close() } }   // a group is reported, never blocked as a person

/** «CLEAR MESSAGES» (iOS MTGroupClearAsk): every letter and event of the group's feed leaves this phone alone, after the question. */
private fun askClear(act: MainActivity, key: String) {
    AlertDialog.Builder(act).setMessage(act.getString(R.string.gpg_clear_q, title(act, key)))
        .setPositiveButton(R.string.gpg_delete_all) { _, _ -> Book.edit(key) { it.msgs.clear() } }
        .setNegativeButton(R.string.cancel, null).show()
}
/**
 * LEAVE GROUP (iOS MTGroupPageAsks: «Are you sure you want to leave and delete %@?»), LEAVE CHANNEL («Are you sure you want to leave the
 * channel %@?»): the owner is told, and the chat leaves this phone.
 */
private fun askLeave(act: MainActivity, key: String, onGone: () -> Unit) {
    val channel = Groups.isChannel(key)
    AlertDialog.Builder(act).setMessage(act.getString(if (channel) R.string.gpg_leave_channel_q else R.string.gpg_leave_group_q, title(act, key)))
        .setPositiveButton(if (channel) R.string.gpg_leave_channel else R.string.gpg_leave_group) { _, _ -> Groups.leaveAndErase(key); onGone() }
        .setNegativeButton(R.string.cancel, null).show()
}
/** DELETE GROUP (iOS: «Delete for All»), DELETE CHANNEL («Wait! Deleting this channel…»): every member's copy goes with the owner's. */
private fun askDissolve(act: MainActivity, key: String, onGone: () -> Unit) {
    val channel = Groups.isChannel(key)
    AlertDialog.Builder(act).setMessage(if (channel) act.getString(R.string.gpg_delete_channel_q) else act.getString(R.string.gpg_delete_group_q, title(act, key)))
        .setPositiveButton(if (channel) R.string.gpg_delete_channel else R.string.gpg_delete_for_all) { _, _ -> Groups.dissolve(key); onGone() }
        .setNegativeButton(R.string.cancel, null).show()
}
/** «Remove from the group?» (iOS MTGroupPageAsks): the owner's hand, or an administrator's ask of the owner (Groups.kick). */
private fun askRemove(act: MainActivity, key: String, seat: String, then: () -> Unit) {
    AlertDialog.Builder(act).setTitle(R.string.gpg_remove_q)
        .setPositiveButton(R.string.gpg_remove) { _, _ -> Groups.kick(key, seat); then() }
        .setNegativeButton(R.string.cancel, null).show()
}

/**
 * THE GROUP'S ROWS (iOS sections for a group, MontanaPeerInfoScreen.swift:258-336, 397-425): the owner's words about it; then a group's
 * people -- «Add Member» first for its owner, then every person as the reference lists them -- or a channel owner's Administrators,
 * Subscribers and Channel Settings; a subscriber sees no people of the channel.
 */
internal fun groupSections(act: MainActivity, key: String, onGone: () -> Unit, redraw: () -> Unit): List<View> {
    val c: Context = act
    val out = mutableListOf<View>()
    // THE GROUP'S DESCRIPTION (iOS group.about, .labeledValue): the owner's words, read by all, «description» under them
    val about = Groups.about(key)
    if (about.isNotEmpty()) out += glassGroup(c, listOf(c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(16), dp(10), dp(16), dp(10))
        addView(c.text(about, 17f, Color.WHITE).apply { setTextIsSelectable(true) }, lp())   // USER-DATA: the group's description
        addView(c.text(c.getString(R.string.gpg_description_caption), 13f, MT.gray), lp().apply { topMargin = dp(2) })
    }), inset = 16)
    if (Groups.isChannel(key)) {
        if (!Groups.owns(key) || Groups.isOut(key)) return out
        val n = Groups.people(key) ?: 1
        val admins = 1 + Groups.admins(key).size   // the reference counts its owner among them
        out += glassGroup(c, listOf(
            disclosure(c, R.drawable.ic_person_shield, c.getString(R.string.gpg_admins), admins.toString()) { openChannelPage(act, key, "admins") },
            disclosure(c, R.drawable.ic_person_2, c.getString(R.string.gpg_subscribers_row), n.toString()) { openChannelPage(act, key, "people") },
            disclosure(c, R.drawable.ic_settings, c.getString(R.string.gpg_channel_settings), "") { act.push { back -> groupEditPage(act, key, back, onGone) } }),
            inset = 52)
        return out
    }
    val rows = mutableListOf<View>()
    val owns = Groups.owns(key) && !Groups.isOut(key)
    if (owns) rows += c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(12), dp(14), dp(12))
        minimumHeight = dp(52)
        addView(c.icon(R.drawable.ic_person_add, MT.gray), lp(dp(22), dp(22)).apply { marginEnd = dp(14) })
        addView(c.text(c.getString(R.string.gpg_add_member), 17f, Color.WHITE), lp(0, WRAP, 1f))
        pressable { act.push { close -> groupPickPage(act, close, {}, adding = key) } }
    }
    for (line in memberLines(act, key, redraw)) rows += line
    out += glassGroup(c, rows, inset = 64)
    return out
}

/**
 * THE PEOPLE OF A GROUP'S PAGE, AS THE REFERENCE LISTS THEM (iOS MTGroupPage.lines, MTGroupMemberRow): the owner first, the administrators
 * after, everyone else by name, this phone among them under its own name; each row the face 40, the name, whether they are online under
 * it, the role on a capsule of its own colour at the right. The row opens the person; a hold names what this phone may do -- write to
 * them, name or dismiss an administrator (the owner), take a person out (the owner; an administrator a member who is none).
 */
private fun memberLines(act: MainActivity, key: String, redraw: () -> Unit): List<View> {
    val c: Context = act
    val me = Groups.mySeat(key) ?: return emptyList()
    val owns = Groups.owns(key) && !Groups.isOut(key)
    val admins = Groups.admins(key)
    val iAdmin = !Groups.owns(key) && !Groups.isOut(key) && me in admins
    val people = Groups.pagePeople(c, key).map { it.seat to it.name } + (me to Prefs.userName)
    fun role(seat: String): Int? = if (seat == "0") R.string.gr_role_owner else if (seat in admins) R.string.gr_role_admin else null
    fun rank(seat: String) = when (role(seat)) { R.string.gr_role_owner -> 0; R.string.gr_role_admin -> 1; else -> 2 }
    val ordered = people.sortedWith(compareBy<Pair<String, String>> { rank(it.first) }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.second })
    return ordered.map { (seat, said) ->
        val mine = seat == me
        val pipe = if (mine) null else Groups.seatPipe(key, seat)?.let { SamePair.root(it) }
        val chat = pipe?.let { Book.chat(it) }
        val r = role(seat)
        val mayRemove = !mine && (owns || (iAdmin && r == null))
        val name = said.ifBlank { c.getString(R.string.gr_member) }
        c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            minimumHeight = dp(56)
            // one's own face wears the row's own name: its initial, «M» of «Member» for a phone with no name (iOS MTSelfFace(initial: line.name))
            val face = if (mine) c.avatar(SelfFace.load(c), name, 40) else if (pipe != null) c.peerFace(pipe, name, 40) else c.avatar(null, name, 40)
            addView(face, lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(name, 17f, Color.WHITE).apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END }, lp())   // USER-DATA: a person's name
                val presence = if (mine) c.getString(R.string.gpg_online_word) else pipe?.let { Presence.word(c, it)?.first }
                if (presence != null) addView(c.text(presence, 12f, MT.gray).apply { maxLines = 1 }, lp().apply { topMargin = dp(2) })   // USER-DATA: the presence's word
            }, lp(0, WRAP, 1f))
            if (r != null) {
                val tint = if (r == R.string.gr_role_owner) MT.roleOwner else MT.roleAdmin
                addView(c.text(c.getString(r), 15f, tint).apply {
                    background = c.rounded(MT.withAlpha(tint, 0.2f), 100); setPadding(dp(7), dp(2), dp(7), dp(2))
                }, lp(WRAP, WRAP).apply { marginStart = dp(8) })
            }
            if (chat != null) pressable { act.push { close -> peerInfoPage(act, pipe, close) } }
            setOnLongClickListener { v ->
                val deeds = PopupMenu(c, v)
                if (chat != null) deeds.menu.add(c.getString(R.string.gpg_send_message)).setOnMenuItemClickListener {
                    act.push { close -> conversationPage(act, pipe, close) }; true
                }
                if (owns && !mine && !Groups.isChannel(key)) {
                    if (r == R.string.gr_role_admin) deeds.menu.add(c.getString(R.string.gpg_dismiss)).setOnMenuItemClickListener { Groups.setAdmin(key, seat, false); redraw(); true }
                    else if (r == null) deeds.menu.add(c.getString(R.string.gpg_promote)).setOnMenuItemClickListener { Groups.setAdmin(key, seat, true); redraw(); true }
                }
                if (mayRemove) deeds.menu.add(SpannableString(c.getString(R.string.gpg_remove_from)).apply { setSpan(ForegroundColorSpan(SysColor.red), 0, length, 0) })
                    .setOnMenuItemClickListener { askRemove(act, key, seat, redraw); true }
                if (deeds.menu.size() > 0) deeds.show()
                true
            }
        }
    }
}

/** A disclosure row of the page (iOS MTInfoRow .disclosure): the glyph in its grey, the words, the detail and the chevron. */
private fun disclosure(c: Context, icon: Int, title: String, detail: String, onTap: () -> Unit): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(12), dp(14), dp(12))
    minimumHeight = dp(52)
    addView(c.icon(icon, MT.gray), lp(dp(22), dp(22)).apply { marginEnd = dp(14) })
    addView(c.text(title, 17f, Color.WHITE), lp(0, WRAP, 1f))
    if (detail.isNotEmpty()) addView(c.text(detail, 17f, MT.gray), lp(WRAP, WRAP).apply { marginEnd = dp(6) })   // USER-DATA: a count
    addView(c.icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18), lp(dp(18), dp(18)))
    pressable(onTap)
}
/** The page's rows on one glass plate of radius 20, the hairlines from `inset` (the person's page's own, PeerInfo glassGroup). */
private fun glassGroup(c: Context, rows: List<View>, inset: Int): View = c.vstack(Gravity.NO_GRAVITY) {
    background = c.glassPlate().apply { cornerRadius = dp(20).toFloat() }
    rows.forEachIndexed { i, r ->
        if (i > 0) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(inset) })
        addView(r, lp())
    }
}

/**
 * THE OWNER'S EDITOR (iOS editor for a group, MontanaPeerInfoScreen.swift:645-705): the face, the name, the description and its
 * footer; a group's Invite Links and its end; a channel's Invite Links and Reactions, its Removed Users and Recent Actions, its end.
 * «Done» tells every member (Groups.renew).
 */
fun groupEditPage(act: MainActivity, key: String, onBack: () -> Unit, onGone: () -> Unit = {}): View {
    val c: Context = act
    val channel = Groups.isChannel(key)
    val owns = Groups.owns(key) && !Groups.isOut(key)
    var face: ByteArray? = null
    val faceBox = FrameLayout(c)
    fun drawFace() {
        faceBox.removeAllViews()
        val bmp = face?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (bmp != null) faceBox.addView(c.avatar(bmp, "", 100), FrameLayout.LayoutParams(c.dp(100), c.dp(100)))
        else faceBox.addView(c.peerFace(key, title(c, key), 100), FrameLayout.LayoutParams(c.dp(100), c.dp(100)))
    }
    drawFace()
    // THE FACE IS PICKED UNDER ITS CIRCLE (iOS MTPeerHeader showsCamera: «Edit» under the face, the system's picker)
    fun pick() = act.pickPhoto { uri ->
        val image = uri?.let { SelfFace.decode(act, it) } ?: return@pickPhoto
        lateinit var close: () -> Unit
        close = act.overlay(cropPage(act, image) { jpeg -> close(); if (jpeg != null) { face = jpeg; drawFace() } })
    }
    faceBox.pressable { pick() }
    fun field(hint: Int, value: String, lines: Int) = EditText(c).apply {
        setText(value)   // USER-DATA: the group's title or its description
        this.hint = c.getString(hint)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray); textSize = 17f
        background = null
        if (lines == 1) isSingleLine = true else { minLines = 1; maxLines = lines }
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
    }
    val name = field(if (channel) R.string.gpg_channel_name else R.string.gpg_group_name, title(c, key), 1)
    val about = field(R.string.gpg_description, Groups.about(key), 5)
    val done = FrameLayout(c).apply {
        background = c.glassPlate(oval = true)
        contentDescription = c.getString(R.string.gpg_done)
        addView(c.icon(R.drawable.ic_check, Color.WHITE), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
        pressable {
            c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(name.windowToken, 0)
            Groups.renew(key, name.text.toString(), face, if (owns) about.text.toString() else null)
            onBack()
        }
    }
    return settingsPage(act, c.getString(R.string.gpg_edit), onBack, trailing = done) {
        addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
            setPadding(0, dp(8), 0, 0)
            addView(faceBox, lp(dp(100), dp(100)))
            addView(c.text(c.getString(R.string.gpg_edit), 17f, SysColor.blue).apply { setPadding(dp(12), dp(10), dp(12), dp(10)); pressable { pick() } }, lp(WRAP, WRAP))
        }, lp())
        section(null, null, name)
        if (owns) section(null, c.getString(if (channel) R.string.gpg_description_channel_footer else R.string.gpg_description_group_footer), about)
        if (owns && channel) {
            // THE CHANNEL'S LINK AND ITS END, where the reference's channel settings keep them (iOS 665-692)
            section(null, null,
                c.settingsRow(R.drawable.ic_link, MT.gray, c.getString(R.string.gpg_invite_links)) { openChannelPage(act, key, "links") },
                c.settingsRow(R.drawable.ic_face_smiling, MT.gray, c.getString(R.string.gpg_reactions),
                    value = c.text(c.getString(if (Groups.reactionsOn(key)) R.string.gpg_reactions_all else R.string.gpg_reactions_off), 17f, MT.gray)) {
                    openChannelPage(act, key, "reactions")
                })
            section(null, null,
                c.settingsRow(R.drawable.ic_person_xmark, MT.gray, c.getString(R.string.gpg_removed_users),
                    value = c.text(Groups.bannedPeople(key).size.toString(), 17f, MT.gray)) { openChannelPage(act, key, "removed") },
                c.settingsRow(R.drawable.ic_history, MT.gray, c.getString(R.string.gpg_recent_actions)) { openChannelPage(act, key, "actions") })
            section(null, null, c.text(c.getString(R.string.gpg_delete_channel), 17f, SysColor.red).apply {
                setPadding(dp(16), dp(13), dp(16), dp(13)); pressable { askDissolve(act, key) { onBack(); onGone() } }
            })
        }
        if (owns && !channel) {
            // THE GROUP'S LINK AND ITS END, where the reference's editor keeps them (iOS 693-705)
            section(null, null, c.settingsRow(R.drawable.ic_link, MT.gray, c.getString(R.string.gpg_invite_links)) { act.push { back -> groupInviteLinksPage(act, key, back) } })
            section(null, null, c.text(c.getString(R.string.gpg_delete_group), 17f, SysColor.red).apply {
                setPadding(dp(16), dp(13), dp(16), dp(13)); pressable { askDissolve(act, key) { onBack(); onGone() } }
            })
        }
    }
}

/**
 * THE GROUP'S INVITE LINK, AS THE REFERENCE'S PAGE KEEPS IT (iOS MTGroupInviteLinksPage, MTGroupPage.swift:145-189): the link, «Copy» and
 * «Share» under it, and «Revoke Link» -- a new mark that ends every link given before (Groups.resetInvite), asked first.
 */
fun groupInviteLinksPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    var link = Groups.inviteLink(c, key)
    val shown = c.text(link ?: "", 17f, Color.WHITE).apply {   // USER-DATA: the group's link
        maxLines = 1; ellipsize = TextUtils.TruncateAt.MIDDLE; setPadding(dp(16), dp(12), dp(16), dp(12))
    }
    // iOS borderedProminent in the platform's blue: a capsule 44 high, the words in their regular weight (iOS 26)
    fun button(words: Int, work: () -> Unit) = c.text(c.getString(words), 17f, Color.WHITE, center = true).apply {
        background = c.rounded(SysColor.blue, 22); minHeight = c.dp(44); gravity = Gravity.CENTER; pressable(work)
    }
    val buttons = c.hstack {
        setPadding(dp(16), dp(4), dp(16), dp(12))
        addView(button(R.string.gpg_copy) {
            val l = link ?: return@button
            c.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Montana", l))
            Toast.makeText(c, R.string.gpg_copy, Toast.LENGTH_SHORT).show()
        }, lp(0, WRAP, 1f))
        gap(12)
        addView(button(R.string.gpg_share) {
            val l = link ?: return@button
            runCatching { act.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, l), null)) }
        }, lp(0, WRAP, 1f))
    }
    return settingsPage(act, c.getString(R.string.gpg_invite_links), onBack) {
        section(c.getString(R.string.gpg_invite_link), c.getString(R.string.gpg_link_footer), shown, buttons)
        section(null, null, c.text(c.getString(R.string.gpg_revoke_link), 17f, SysColor.red).apply {
            setPadding(dp(16), dp(13), dp(16), dp(13))
            pressable {
                AlertDialog.Builder(act).setMessage(R.string.gpg_revoke_q)
                    .setPositiveButton(R.string.gpg_revoke) { _, _ -> Groups.resetInvite(key); link = Groups.inviteLink(c, key); shown.text = link ?: "" }
                    .setNegativeButton(R.string.cancel, null).show()
            }
        })
    }
}

/** A channel's own pages (iOS MontanaChannel.swift: Administrators, Subscribers, Invite Links, Reactions, Removed Users, Recent Actions). */
private fun openChannelPage(act: MainActivity, key: String, which: String) = act.push { back ->
    when (which) {
        "admins" -> channelAdminsPage(act, key, back)
        "people" -> channelPeoplePage(act, key, back)
        "links" -> channelInviteLinksPage(act, key, back)
        "reactions" -> channelReactionsPage(act, key, back)
        "removed" -> channelRemovedPage(act, key, back)
        else -> channelActionsPage(act, key, back)
    }
}
