package quest.montana.app

import android.animation.ValueAnimator
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewTreeObserver
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Switch
import java.lang.ref.WeakReference
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs

// ─────────────────────────── a channel's birth and its pages (iOS MontanaChannel.swift, build 1.0 (2235)) ───────────────────────────
//
// THE CHANNEL'S OWN PAGES, ONE TO ONE AS iOS LAYS THEM (the author's words 17.10.2026 18:4x MSK: «channels ... 1 to 1», «we do not need our
// own kinds of pages inside channels»): its birth in three steps (MontanaChannel.swift:8-175), the head's count (491-495), and the owner's
// pages -- the subscribers (510-571), the invite link (573-620), the administrators (622-722), the reactions (724-745), the people taken
// out (747-790) and the deeds of the last two days (792-846). Every change is the engine's (Groups), the owner's word to every phone of the
// channel; these pages only ask it and show what it holds.

/** The owner's seat in every group and channel (iOS MTGroup.ownerSeat, MontanaGroup.swift:200). */
private const val CH_OWNER = "0"
/** iOS placeholderText (dark): #EBEBF5 at 30 % -- a field's words before they are written. */
private val CH_PLACEHOLDER = Color.argb(77, 235, 235, 245)
/** iOS tertiarySystemFill (dark): #767680 at 24 % -- the empty face's circle, the search field (MTFacePicker, .searchable). */
private val CH_TERTIARY = Color.argb(61, 118, 118, 128)
/** The cloud's own plate (iOS MTPersonMenu's head, ChatList.personPlate): the menus' material and its rim. */
private val CH_CLOUD = Color.argb(235, 44, 44, 46)
/** A row's words begin after its face (16 + 40 + 12), and so does the list's separator under it (iOS listRowSeparatorLeading). */
private const val CH_FACE_INSET = 68
private const val CH_TEXT_INSET = 16
/** The deeds the Recent Actions show: the last two days (iOS MTChannelActionsPage.span, MontanaChannel.swift:796). */
private const val CH_ACTS_SPAN_MS = 48L * 3600 * 1000

// ─────────────────────────── the birth in three steps (iOS MTChannelIntroStep, MTChannelInfoStep, MTChannelSubscribersStep; 8-128) ───────────────────────────

/**
 * THE CHANNEL IS BORN IN THREE STEPS (iOS MTChannelIntroStep, MontanaChannel.swift:4-46; the author's words 05.10.2026 19:0x MSK: «3. Channel
 * -- see the mechanics in the reference tree»): what a channel is, then its face, name and description, then the subscribers, each chosen
 * by a tick. The first step is the reference's introduction (17.10.2026 18:4x: «1 to 1»): the picture, «What is a Channel?», its one
 * sentence and «Create Channel» at the foot; the cross leaves. A channel is a group whose owner alone posts (Groups, kind channel); its
 * posts ride the pipe of each subscriber from this phone. `onCreated` -- the channel's key, once it is born: the steps close whether or
 * not the engine took it, as iOS's sheet closes (onCreate, then dismiss; MontanaChatsList.swift:1291-1298).
 */
fun channelCreatePage(act: MainActivity, onClose: () -> Unit, onCreated: (String) -> Unit): View {
    val c: Context = act
    fun born(title: String, about: String, face: ByteArray?, people: List<String>) {
        // A CHANNEL MAY START BEFORE IT HAS SUBSCRIBERS (iOS MTGroup.create): its row stands at once, an invitation rides to everyone chosen
        val key = Groups.create(channel = true, title = title, about = about, face = face, people = people)
        onClose()
        key?.let(onCreated)
    }
    // iOS VStack(spacing: 18) { Spacer; the picture; the title; the sentence; Spacer; Spacer; the button }, 32 at the sides, 12 at the foot
    val body = c.vstack(Gravity.CENTER_HORIZONTAL) {
        setPadding(dp(32), 0, dp(32), dp(12))
        spacer()
        gap(18)
        addView(c.icon(R.drawable.ic_megaphone_fill, Color.WHITE, 72), lp(dp(72), dp(72)))   // iOS megaphone.fill at 64, white
        gap(18)
        addView(c.text(c.getString(R.string.chn_what_is), 22f, Color.WHITE, bold = true, center = true), lp())   // iOS .title2.bold()
        gap(18)
        addView(c.text(c.getString(R.string.chn_what_is_sub), 17f, MT.secondary, center = true), lp())   // iOS .body, .secondary, centred
        gap(18)
        spacer()
        gap(18)
        spacer()
        gap(18)
        // «Create Channel» (iOS .headline, the whole width, 50 high, .borderedProminent on the platform's blue): on to the face and the name
        addView(c.chCapsule(c.getString(R.string.chn_create), 50, bold = true) {
            act.push { back -> channelInfoPage(act, back) { title, about, face, people -> back(); born(title, about, face, people) } }
        }, lp())
    }
    return chStepFrame(c, c.getString(R.string.chn_new_channel), c.chBarMark(R.drawable.ic_close, R.string.cancel, onClose), body)
}

/**
 * THE SECOND STEP: THE CHANNEL'S FACE, NAME AND DESCRIPTION (iOS MTChannelInfoStep, MontanaChannel.swift:48-89): the face picker beside the
 * name, the description of up to six lines under it with its caption; the tick goes on to the subscribers -- dim and deaf until the name
 * holds a letter -- and the name's field takes the keys at once. The face is framed by the app's crop (cropPage), as a group's face is.
 */
private fun channelInfoPage(act: MainActivity, onBack: () -> Unit, onCreate: (String, String, ByteArray?, List<String>) -> Unit): View {
    val c: Context = act
    var face: ByteArray? = null
    val faceBox = FrameLayout(c)
    fun drawFace() {
        faceBox.removeAllViews()
        val bmp = face?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        // iOS MTFacePicker (150-175): the picture in a circle of 60, else the camera on the platform's tertiary fill
        if (bmp != null) faceBox.addView(c.avatar(bmp, "", 60), FrameLayout.LayoutParams(c.dp(60), c.dp(60)))
        else faceBox.addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(CH_TERTIARY) }
            addView(c.icon(R.drawable.ic_camera_fill, Color.WHITE, 26), FrameLayout.LayoutParams(c.dp(26), c.dp(26), Gravity.CENTER))   // iOS camera.fill, .title3
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
    val name = chField(c, c.getString(R.string.chn_name), lines = 1).apply { setPadding(0, dp(8), 0, dp(8)) }
    val about = chField(c, c.getString(R.string.chn_about_hint), lines = 6).apply { setPadding(dp(16), dp(12), dp(16), dp(12)) }
    val tick = c.chBarMark(R.drawable.ic_check, R.string.chn_done) {
        chKeysAway(name)
        val title = name.text.toString().trim()
        val words = about.text.toString().trim()
        act.push { closeSubs -> channelSubscribersPage(act, closeSubs) { people -> closeSubs(); onCreate(title, words, face, people) } }
    }
    tick.chReady(false)
    name.chOnWords { tick.chReady(it.isNotBlank()) }
    // iOS HStack(spacing: 14) { MTFacePicker; TextField("Channel Name") }
    val faceRow = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(10), dp(16), dp(10))
        addView(faceBox, lp(dp(60), dp(60)))
        gap(14)
        addView(name, lp(0, WRAP, 1f))
    }
    val page = settingsPage(act, c.getString(R.string.chn_new_channel), { chKeysAway(name); onBack() }, trailing = tick) {
        chSection(null, null, listOf(faceRow to CH_TEXT_INSET))
        chSection(null, c.getString(R.string.chn_about_footer), listOf(about to CH_TEXT_INSET))
    }
    // the name's field takes the keys at once (iOS .onAppear { typing = true })
    name.post { name.requestFocus(); c.getSystemService(InputMethodManager::class.java).showSoftInput(name, 0) }
    return page
}

/**
 * THE THIRD STEP: THE SUBSCRIBERS (iOS MTChannelSubscribersStep, MontanaChannel.swift:91-128): each chosen by a tick among the people this
 * phone holds a pipe with -- a post rides the pipe of each person, so only the people one writes with are listed -- the search over them,
 * and the tick that gives the channel its birth, in the order they were chosen; none chosen is a channel of its owner alone, for now.
 */
private fun channelSubscribersPage(act: MainActivity, onBack: () -> Unit, onDone: (List<String>) -> Unit): View {
    val c: Context = act
    val people = chReachable()
    val chosen = linkedSetOf<String>()
    var query = ""
    val list = c.vstack(Gravity.NO_GRAVITY)
    fun fill() {
        list.removeAllViews()
        val q = query.trim()
        val shown = people.filter { q.isEmpty() || it.shown.contains(q, ignoreCase = true) }
        list.chSection(null, c.getString(R.string.chn_pick_note), shown.map { ch ->
            chPickRow(c, ch, ch.ref in chosen) { if (!chosen.remove(ch.ref)) chosen.add(ch.ref); fill() } to CH_FACE_INSET
        })
    }
    val search = chSearch(c) { query = it; fill() }
    val tick = c.chBarMark(R.drawable.ic_check, R.string.chn_done) {
        chKeysAway(search)
        onDone(chosen.filter { ref -> people.any { it.ref == ref } })
    }
    fill()
    return settingsPage(act, c.getString(R.string.chn_add_subscribers), { chKeysAway(search); onBack() }, trailing = tick) {
        gap(4)
        addView(search, lp())   // iOS .searchable(placement: .navigationBarDrawer(displayMode: .always))
        addView(list, lp())
    }
}

/**
 * The people a channel can carry to (iOS MTGroupPickStep.reachable, MontanaScreens.swift:604-609): a conversation whose pipe this phone
 * holds -- a post rides each subscriber's own pipe, and a person without one could be listed and never read a post.
 */
private fun chReachable(): List<Chat> = chatRows().filter { Book.secret(SamePair.root(it.ref)) != null }

/** A person to choose (iOS MTPickRow, MontanaChannel.swift:130-148): the face 40, the name, the platform's circle -- white with its tick when chosen, else the secondary ring; the whole row is the target. */
private fun chPickRow(c: Context, ch: Chat, on: Boolean, onTap: () -> Unit): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(6), dp(16), dp(6))
    minimumHeight = dp(52)
    addView(c.peerFace(ch.ref, ch.shown, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
    addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a person's name
    addView(FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; if (on) setColor(Color.WHITE) else setStroke(dp(1.5f), MT.secondary) }
        if (on) addView(c.icon(R.drawable.ic_check, Color.BLACK, 14), FrameLayout.LayoutParams(dp(14), dp(14), Gravity.CENTER))
    }, lp(dp(24), dp(24)))
    pressable(onTap)
}

// ─────────────────────────── the channel's head (iOS MTChannelPage.head, MontanaChannel.swift:491-495) ───────────────────────────

/** «N SUBSCRIBERS» UNDER THE CHANNEL'S NAME (iOS MTChannelPage.head): the owner counted among them -- the chat's top and the channel's page say this one line. */
fun channelHead(c: Context, key: String): String {
    val n = Groups.people(key) ?: 1
    return c.resources.getQuantityString(R.plurals.chn_subscribers, n, n)   // USER-DATA: a count of people
}

// ─────────────────────────── Subscribers (iOS MTChannelPeoplePage, MontanaChannel.swift:510-571) ───────────────────────────

/**
 * THE CHANNEL'S SUBSCRIBERS (iOS MTChannelPeoplePage, the reference's «Subscribers» page, its owner's alone): «Add Subscribers» first, then
 * every person the owner's phone carries the channel to; a hold or a swipe takes one out -- asked first, as the reference asks («Remove
 * from the channel?»). The page reads the channel again whenever the book moves while it stands.
 */
fun channelPeoplePage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    lateinit var body: LinearLayout
    var drawn: String? = null
    fun draw() {
        val manages = Groups.owns(key) && !Groups.isOut(key)   // iOS MTGroup.manages: its owner, still holding it
        val people = Groups.pagePeople(c, key)
        val look = manages.toString() + people.joinToString("") { "\n" + it.seat + "\t" + it.name + "\t" + it.pipe }
        if (look == drawn) return
        drawn = look
        body.removeAllViews()
        if (manages) body.chSection(null, null, listOf(chLabelRow(c, R.drawable.ic_person_add, c.getString(R.string.chn_add_subscribers)) {
            // iOS .sheet { MTGroupPickStep(adding: key) } → MTGroup.add: the people this phone writes with and the channel carries to not yet
            act.push { close -> groupPickPage(act, { close(); draw() }, {}, adding = key) }
        } to CH_TEXT_INSET))
        body.chSection(null, null, people.map { p ->
            val row = chPersonRow(c, key, p.seat, p.pipe, p.name, null)
            val item: Pair<View, Int> = if (!manages) row to CH_FACE_INSET else {
                val remove: () -> Unit = {
                    chAsk(act, c.getString(R.string.chn_remove_q), null, R.string.chn_remove) { Groups.remove(key, p.seat); draw() }
                }
                // iOS .contextMenu and .swipeActions: Label("Remove", systemImage: "person.fill.xmark"), destructive
                row.setOnLongClickListener {
                    holdMenu(act, row, listOf(Deed(R.string.chn_remove, R.drawable.ic_person_xmark, red = true, work = remove)), chHeld(c, key, p.seat, p.pipe, p.name))
                    true
                }
                ChannelSwipeRow(c, row, ChannelSwipeDeed(null, R.drawable.ic_person_xmark, remove)) to CH_FACE_INSET
            }
            item
        })
    }
    val page = settingsPage(act, c.getString(R.string.chn_subscribers_title), onBack) { body = this }
    draw()
    page.chRedrawsWithBook { draw() }
    return page
}

// ─────────────────────────── Invite Links (iOS MTChannelInviteLinksPage, MontanaChannel.swift:573-620) ───────────────────────────

/**
 * THE CHANNEL'S INVITE LINK, WHERE THE REFERENCE'S CHANNEL SETTINGS KEEP IT (iOS MTChannelInviteLinksPage): the link in one line cut in its
 * middle, «Copy» and «Share» under it on the platform's blue, and «Revoke Link» -- a new mark that ends every link given before
 * (Groups.resetInvite), asked first. Whoever opens the link meets the owner by its card and asks with the mark; the owner's phone adds them
 * as a subscriber. The link is read off the main thread: the first one mints the owner's permanent card.
 */
fun channelInviteLinksPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    lateinit var body: LinearLayout
    var link: String? = null
    var fetch: () -> Unit = {}
    fun draw() {
        body.removeAllViews()
        val rows = mutableListOf<Pair<View, Int>>()
        link?.let { l ->
            rows += c.text(l, 17f, Color.WHITE).apply {   // USER-DATA: the channel's link
                isSingleLine = true
                ellipsize = TextUtils.TruncateAt.MIDDLE   // iOS .lineLimit(1).truncationMode(.middle)
                gravity = Gravity.CENTER_VERTICAL
                minHeight = dp(48)
                setPadding(dp(16), dp(10), dp(16), dp(10))
            } to CH_TEXT_INSET
            // iOS HStack(spacing: 12) { «Copy»; «Share» }, each the half, 44 high, .borderedProminent .tint(.blue)
            rows += c.hstack {
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(c.chCapsule(c.getString(R.string.copy), 44, bold = false) { v ->
                    (c.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Montana", l))
                    // iOS UINotificationFeedbackGenerator .success
                    v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS)
                }, lp(0, WRAP, 1f))
                gap(12)
                addView(c.chCapsule(c.getString(R.string.share), 44, bold = false) {
                    // iOS MTShare.present([link]): the system's own share
                    runCatching { act.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, l), null)) }
                }, lp(0, WRAP, 1f))
            } to CH_TEXT_INSET
        }
        body.chSection(c.getString(R.string.chn_invite_link), c.getString(R.string.chn_invite_footer), rows)
        // «Revoke Link» (iOS Button(role: .destructive), 44 high, leading), asked first
        body.chSection(null, null, listOf(c.text(c.getString(R.string.chn_revoke_link), 17f, SysColor.red).apply {
            gravity = Gravity.CENTER_VERTICAL
            minHeight = dp(48)
            setPadding(dp(16), dp(10), dp(16), dp(10))
            pressable { chAsk(act, null, c.getString(R.string.chn_revoke_q), R.string.chn_revoke) { Groups.resetInvite(key); fetch() } }
        } to CH_TEXT_INSET))
    }
    fetch = { act.background { val l = Groups.inviteLink(act, key); act.onMain { link = l; draw() } } }
    val page = settingsPage(act, c.getString(R.string.chn_invite_links), onBack) { body = this }
    draw()
    fetch()   // iOS .onAppear { link = MTGroup.shared.inviteLink(chat) }
    return page
}

// ─────────────────────────── Administrators (iOS MTChannelAdminsPage, MontanaChannel.swift:622-722) ───────────────────────────

/**
 * THE CHANNEL'S ADMINISTRATORS (iOS MTChannelAdminsPage, the reference's «Administrators» page of a channel): «CHANNEL ADMINS» -- the owner
 * first, then every administrator it named, a swipe or a hold to dismiss one -- «Add Admin» from the channel's subscribers, and «Sign
 * Messages». An administrator posts into the channel and takes a post away; the owner alone names them, by its invitation's word, so
 * every phone reads the same list.
 */
fun channelAdminsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    lateinit var body: LinearLayout
    var drawn: String? = null
    fun draw() {
        val mine = Groups.owns(key)                  // iOS g.mine
        val owns = mine && !Groups.isOut(key)        // iOS g.canManage
        val admins = Groups.admins(key).toSet()
        val people = Groups.pagePeople(c, key)
        val look = owns.toString() + mine + admins.sorted() + people.joinToString("") { "\n" + it.seat + "\t" + it.name + "\t" + it.pipe }
        if (look == drawn) return
        drawn = look
        body.removeAllViews()
        // THE OWNER FIRST (iOS ownerName): «You» on its own phone, else the name this phone knows it by; its face as every phone draws the
        // owner's seat -- its own picture where this phone holds the owner's pipe, else the initial on the seat's colour
        val owner = people.firstOrNull { it.seat == CH_OWNER }
        val ownerName = if (mine) c.getString(R.string.chn_you) else owner?.name ?: c.getString(R.string.gr_member)
        val rows = mutableListOf<Pair<View, Int>>()
        rows += chPersonRow(c, key, CH_OWNER, if (mine) "" else owner?.pipe.orEmpty(), ownerName, c.getString(R.string.chn_owner)) to CH_FACE_INSET
        for (p in people.filter { it.seat in admins }) {
            val row = chPersonRow(c, key, p.seat, p.pipe, p.name, c.getString(R.string.chn_admin))
            if (!owns) { rows += row to CH_FACE_INSET; continue }
            val dismiss: () -> Unit = { Groups.setAdmin(key, p.seat, false); draw() }
            // iOS .swipeActions: Text("Dismiss Admin"); .contextMenu: Label("Dismiss Admin", systemImage: "person.badge.minus") -- both destructive
            row.setOnLongClickListener {
                holdMenu(act, row, listOf(Deed(R.string.chn_dismiss_admin, R.drawable.ic_person_minus, red = true, work = dismiss)), chHeld(c, key, p.seat, p.pipe, p.name))
                true
            }
            rows += ChannelSwipeRow(c, row, ChannelSwipeDeed(c.getString(R.string.chn_dismiss_admin), null, dismiss)) to CH_FACE_INSET
        }
        if (owns) rows += chLabelRow(c, R.drawable.ic_person_add, c.getString(R.string.chn_add_admin)) {
            act.push { close -> channelAddAdminPage(act, key, close) { draw() } }
        } to CH_TEXT_INSET
        body.chSection(c.getString(R.string.chn_admins_header), c.getString(R.string.chn_admins_footer), rows)
        // «Sign Messages» (iOS Toggle → MTGroup.setSigns): every subscriber hears it by the invitation's word again
        if (owns) body.chSection(null, c.getString(R.string.chn_sign_footer), listOf(
            chToggleRow(c, c.getString(R.string.chn_sign_messages), Groups.signsOn(key)) { on -> Groups.setSigns(key, on) } to CH_TEXT_INSET))
    }
    val page = settingsPage(act, c.getString(R.string.chn_administrators), onBack) { body = this }
    draw()
    page.chRedrawsWithBook { draw() }
    return page
}

/**
 * «ADD ADMIN» (iOS MTChannelAdminsPage's sheet, MontanaChannel.swift:694-715): the channel's subscribers who are no administrators yet; a tap
 * names one (Groups.setAdmin) and the sheet closes; the cross leaves.
 */
private fun channelAddAdminPage(act: MainActivity, key: String, onClose: () -> Unit, onNamed: () -> Unit): View {
    val c: Context = act
    val admins = Groups.admins(key).toSet()
    val people = Groups.pagePeople(c, key).filter { it.seat !in admins && it.seat != CH_OWNER }
    return settingsPage(act, c.getString(R.string.chn_add_admin), onClose, cross = true) {
        chSection(null, null, people.map { p ->
            chPersonRow(c, key, p.seat, p.pipe, p.name, null).apply {
                pressable { Groups.setAdmin(key, p.seat, true); onClose(); onNamed() }
            } to CH_FACE_INSET
        })
    }
}

// ─────────────────────────── Reactions (iOS MTChannelReactionsPage, MontanaChannel.swift:724-745) ───────────────────────────

/**
 * THE CHANNEL'S REACTIONS (iOS MTChannelReactionsPage, the reference's «Reactions» page of a channel): «Allow Reactions» and its caption.
 * Off, the post's menu on every subscriber's phone stands without its strip, and the owner takes no subscriber's reaction.
 */
fun channelReactionsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    return settingsPage(act, c.getString(R.string.chn_reactions), onBack) {
        chSection(null, c.getString(R.string.chn_reactions_footer), listOf(
            chToggleRow(c, c.getString(R.string.chn_allow_reactions), Groups.reactionsOn(key)) { on -> Groups.setReactions(key, on) } to CH_TEXT_INSET))
    }
}

// ─────────────────────────── Removed Users (iOS MTChannelRemovedPage, MontanaChannel.swift:747-790) ───────────────────────────

/**
 * THE CHANNEL'S REMOVED USERS (iOS MTChannelRemovedPage, the reference's page): every person its owner took out, who cannot come back by the
 * invite link; a swipe lets one back by the link («Delete», Groups.unban), a hold adds one again («Add to Channel») or lets them back.
 */
fun channelRemovedPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    lateinit var body: LinearLayout
    var drawn: String? = null
    fun draw() {
        val people = Groups.bannedPeople(key)
        val look = people.joinToString("") { "\n" + it.seat + "\t" + it.name + "\t" + it.pipe }
        if (look == drawn) return
        drawn = look
        body.removeAllViews()
        body.chSection(c.getString(R.string.chn_removed_header), c.getString(R.string.chn_removed_footer), people.map { p ->
            // the face as iOS draws it (MTSpeakerFace): a seat taken out is carried to no more, so its initial stands on the seat's colour
            val row = chPersonRow(c, key, p.seat, "", p.name, null)
            val letBack: () -> Unit = { Groups.unban(key, p.seat); draw() }
            row.setOnLongClickListener {
                holdMenu(act, row, listOf(
                    Deed(R.string.chn_add_to_channel, R.drawable.ic_person_add) { Groups.add(key, listOf(p.pipe)); draw() },   // iOS person.badge.plus
                    Deed(R.string.chn_delete, R.drawable.ic_delete, red = true, work = letBack)), chHeld(c, key, p.seat, "", p.name))   // iOS trash
                true
            }
            ChannelSwipeRow(c, row, ChannelSwipeDeed(c.getString(R.string.chn_delete), null, letBack)) to CH_FACE_INSET
        })
    }
    val page = settingsPage(act, c.getString(R.string.chn_removed_users), onBack) { body = this }
    draw()
    page.chRedrawsWithBook { draw() }
    return page
}

// ─────────────────────────── Recent Actions (iOS MTChannelActionsPage, MontanaChannel.swift:792-846) ───────────────────────────

/**
 * THE CHANNEL'S RECENT ACTIONS (iOS MTChannelActionsPage, the reference's event log of a channel): the deeds of the last two days, the newest
 * first, each a sentence by the names known when it was done, and its moment; none -- the reference's two lines on no plate. Its owner's
 * phone writes them (Groups.acts).
 */
fun channelActionsPage(act: MainActivity, key: String, onBack: () -> Unit): View {
    val c: Context = act
    val now = System.currentTimeMillis()
    val acts = Groups.acts(key).filter { now - it.at < CH_ACTS_SPAN_MS }.reversed()
    return settingsPage(act, c.getString(R.string.chn_recent_actions), onBack) {
        if (acts.isEmpty()) {
            // iOS VStack(spacing: 8) { .headline; .subheadline .secondary centred }, the whole width, 36 above and below, clear
            addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                setPadding(dp(16), dp(48), dp(16), dp(36))
                addView(c.text(c.getString(R.string.chn_no_actions), 17f, Color.WHITE, bold = true, center = true), lp())
                gap(8)
                addView(c.text(c.getString(R.string.chn_no_actions_sub), 15f, MT.secondary, center = true), lp())
            }, lp())
        } else {
            val moment = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)   // iOS .formatted(date: .abbreviated, time: .shortened)
            // iOS VStack(alignment: .leading, spacing: 3) { the sentence; the moment, .caption .secondary }, 4 above and below
            chSection(null, null, acts.map { a ->
                c.vstack(Gravity.NO_GRAVITY) {
                    setPadding(dp(16), dp(10), dp(16), dp(10))
                    addView(c.text(chActWords(c, a), 17f, Color.WHITE), lp())   // USER-DATA: the people's names inside the catalogue's sentence
                    gap(3)
                    addView(c.text(moment.format(Date(a.at)), 12f, MT.secondary), lp())   // USER-DATA: the deed's moment
                } to CH_TEXT_INSET
            })
        }
    }
}

/** The deed in the reference's words, its doer this phone's owner (iOS MTChannelActionsPage.words, MontanaChannel.swift:826-845). */
private fun chActWords(c: Context, a: Groups.Act): String {
    val names = a.p.orEmpty().joinToString(", ")
    return when (a.e) {
        "invited" -> c.getString(R.string.chn_act_invited, names)
        "joined" -> c.getString(R.string.chn_act_joined, names)
        "removed" -> c.getString(R.string.chn_act_removed, names)
        "left" -> c.getString(R.string.chn_act_left, names)
        "title" -> c.getString(R.string.chn_act_title, a.t.orEmpty())
        "about" -> c.getString(R.string.chn_act_about)
        "photo" -> c.getString(R.string.chn_act_photo)
        "promoted" -> c.getString(R.string.chn_act_promoted, names)
        "demoted" -> c.getString(R.string.chn_act_demoted, names)
        "signOn" -> c.getString(R.string.chn_act_sign_on)
        "signOff" -> c.getString(R.string.chn_act_sign_off)
        "reactOn" -> c.getString(R.string.chn_act_react_on)
        else -> c.getString(R.string.chn_act_react_off)
    }
}

// ─────────────────────────── the pages' own parts (iOS List.insetGrouped on MTGlassRowPlate, the bar's marks, swipeActions) ───────────────────────────

/**
 * A SECTION OF THE PAGE'S LIST (iOS List.insetGrouped on MTGlassRowPlate, laid as the settings lay theirs -- Settings.kt section): the
 * words over it in the list's own capitals (footnote 13, grey), the rows on one glass plate with the list's separators -- each beginning
 * where the words of the row above it begin (`rows`: a row and that inset) -- and the words under it (footnote 13, grey). A section with
 * no rows keeps its words alone, as iOS's empty section does.
 */
private fun LinearLayout.chSection(header: String?, footer: String?, rows: List<Pair<View, Int>>) {
    val c = context
    addView(c.text(header?.uppercase() ?: "", 13f, MT.gray).apply { setPadding(dp(16), dp(if (header == null) 12 else 22), dp(16), dp(if (header == null) 0 else 6)) }, lp())
    if (rows.isNotEmpty()) addView(c.plate {
        rows.forEachIndexed { i, (r, _) ->
            if (i > 0) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(rows[i - 1].second) })
            addView(r, lp())
        }
    }, lp())
    if (footer != null) addView(c.text(footer, 13f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) }, lp())
}

/**
 * A STEP OF THE BIRTH THAT DOES NOT SCROLL (iOS the sheet's NavigationStack on montanaPageGround): the crest behind, the bar of 52 with its
 * mark and the inline title, the body under it -- the settings' page (settingsPage) without its list.
 */
private fun chStepFrame(c: Context, title: String, lead: View, body: View): View = FrameLayout(c).apply {
    setBackgroundColor(Color.BLACK)
    addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // my page's ground (iOS montanaPageGround)
    addView(c.vstack(Gravity.NO_GRAVITY) {
        addView(FrameLayout(c).apply {
            setPadding(dp(8), 0, dp(8), 0)
            addView(lead, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
            addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        }, lp(MATCH, dp(52)))
        addView(body, lp(MATCH, 0, 1f))
    }, FrameLayout.LayoutParams(MATCH, MATCH))
}

/**
 * A BAR'S MARK (iOS MontanaBarMark: MontanaDoneMark's checkmark, MontanaCloseMark's cross, MontanaShapes.swift:1113-1134, 1222-1234): the
 * glyph on the toolbar's own glass circle in the finger's 44 -- the one glass of the app (glassPlate), as the group's page wears its
 * «Done»; a mark not yet open is dimmed to 0.4 and deaf (iOS .disabled + .opacity(0.4), chReady).
 */
private fun Context.chBarMark(glyph: Int, words: Int, onTap: () -> Unit): View = FrameLayout(this).apply {
    background = glassPlate(oval = true)
    contentDescription = getString(words)
    addView(icon(glyph, MT.barGlyph, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
    pressable(onTap)
}
private fun View.chReady(on: Boolean) { isEnabled = on; alpha = if (on) 1f else 0.4f }

/**
 * THE PLATFORM'S FILLED BUTTON (iOS .buttonStyle(.borderedProminent).tint(.blue)): a capsule of the platform's blue `height` high, its words
 * white -- the headline's weight where iOS asks for it.
 */
private fun Context.chCapsule(words: String, height: Int, bold: Boolean, onTap: (View) -> Unit): View = text(words, 17f, Color.WHITE, bold = bold, center = true).apply {
    background = rounded(MT.blue, height / 2f)
    minHeight = dp(height)
    setPadding(dp(14), 0, dp(14), 0)
    singleLineEllipsis()
    pressable { onTap(this) }
}

/**
 * A FIELD OF THE LIST (iOS TextField on the row's glass): the words white at 17, the platform's placeholder, no plate of its own; `lines`
 * over one -- the field grows with its words up to that many (iOS TextField(axis: .vertical).lineLimit(1...6)).
 */
private fun chField(c: Context, placeholder: String, lines: Int): EditText = EditText(c).apply {
    hint = placeholder
    setTextColor(Color.WHITE)
    setHintTextColor(CH_PLACEHOLDER)
    textSize = 17f
    background = null
    if (lines <= 1) {
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        imeOptions = EditorInfo.IME_ACTION_DONE
    } else {
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        isSingleLine = false
        minLines = 1
        maxLines = lines
        gravity = Gravity.TOP or Gravity.START
    }
}

/** THE SEARCH OVER THE PEOPLE (iOS .searchable in the bar's drawer, always shown): the platform's field on its tertiary fill, the magnifier and «Search» in grey, the words white. */
private fun chSearch(c: Context, onQuery: (String) -> Unit): View {
    val field = EditText(c).apply {
        hint = c.getString(R.string.search)
        setTextColor(Color.WHITE)
        setHintTextColor(MT.gray)
        textSize = 17f
        background = null
        isSingleLine = true
        imeOptions = EditorInfo.IME_ACTION_SEARCH
        setPadding(0, dp(8), 0, dp(8))
        setOnEditorActionListener { v, _, _ -> chKeysAway(v); true }
        chOnWords(onQuery)
    }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = c.rounded(CH_TERTIARY, 10)
        setPadding(dp(8), 0, dp(10), 0)
        addView(c.icon(R.drawable.ic_search, MT.gray, 18), lp(dp(18), dp(18)))
        gap(6)
        addView(field, lp(0, WRAP, 1f))
    }
}

private fun EditText.chOnWords(work: (String) -> Unit) = addTextChangedListener(object : TextWatcher {
    override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
    override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
    override fun afterTextChanged(s: Editable?) { work(s?.toString() ?: "") }
})

/** The keyboard leaves with the step (iOS: the field's step leaves the screen, and its keys with it). */
private fun chKeysAway(v: View) { v.context.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(v.windowToken, 0) }

/** A LIST'S BUTTON WITH ITS GLYPH (iOS Label inside a Button on the list, 44 high at the least): the glyph and the words in the page's tint -- the label colour (MontanaPeerInfoScreen.swift:48). */
private fun chLabelRow(c: Context, glyph: Int, words: String, onTap: () -> Unit): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(10), dp(16), dp(10))
    minimumHeight = dp(48)
    addView(c.icon(glyph, Color.WHITE, 24), lp(dp(24), dp(24)).apply { marginEnd = dp(16) })
    addView(c.text(words, 17f, Color.WHITE), lp(0, WRAP, 1f))
    pressable(onTap)
}

/** A SWITCH ON THE LIST (iOS Toggle with its words, 44 high at the least): the words at 17, the platform's green, the whole row the target -- the settings' switch without a glyph. */
private fun chToggleRow(c: Context, words: String, on: Boolean, onChange: (Boolean) -> Unit): View {
    val sw = Switch(c).apply {
        isChecked = on
        thumbTintList = ColorStateList.valueOf(Color.WHITE)
        trackTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(MT.green, Color.rgb(57, 57, 61)))
        contentDescription = words
        setOnCheckedChangeListener { _, v -> onChange(v) }
    }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(8), dp(14), dp(8))
        minimumHeight = dp(48)
        addView(c.text(words, 17f, Color.WHITE), lp(0, WRAP, 1f))
        addView(sw, lp(WRAP, WRAP))
        setOnClickListener { sw.toggle() }
    }
}

/** A PERSON OF THE CHANNEL'S LISTS (iOS MontanaChannel.swift:535-541, 645-660, 761-766): the face 40, the name in one line, the role at the end in the secondary colour (.subheadline). */
private fun chPersonRow(c: Context, key: String, seat: String, pipe: String, name: String, role: String?): LinearLayout = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), dp(6), dp(16), dp(6))
    minimumHeight = dp(52)
    addView(chSpeakerFace(c, key, seat, pipe, name, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
    addView(c.text(name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a person's name
    if (role != null) addView(c.text(role, 15f, MT.secondary), lp(WRAP, WRAP).apply { marginStart = dp(8) })
}

/** The person held, at the top of the hold's cloud (iOS .contextMenu's preview of the row; ChatList.personPlate): the face and the name on the cloud's plate. */
private fun chHeld(c: Context, key: String, seat: String, pipe: String, name: String): View = c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    background = c.rounded(CH_CLOUD, 16, Color.argb(26, 255, 255, 255))
    setPadding(dp(14), dp(8), dp(14), dp(8))
    addView(chSpeakerFace(c, key, seat, pipe, name, 44), lp(dp(44), dp(44)).apply { marginEnd = dp(12) })
    addView(c.text(name, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(WRAP, WRAP))   // USER-DATA: a person's name
}

/**
 * THE SPEAKER'S FACE (iOS MTSpeakerFace, MontanaConversation.swift:4659-4680): the person's own picture where this phone holds their pipe
 * (`pipe`: the owner's phone, every subscriber; a subscriber's phone, the owner), else their initial, white and bold, on the colour every
 * phone gives the seat -- a circle under the native skin (MontanaHexagon).
 */
private fun chSpeakerFace(c: Context, key: String, seat: String, pipe: String, name: String, side: Int): View =
    speakerFace(c, chSpeakerRef(key, seat), pipe, name, side)
/** The face of a speaker by their reference name (`ref`, the seed of their colour) and the pipe this phone holds to them, if any. */
internal fun speakerFace(c: Context, ref: String, pipe: String, name: String, side: Int): View {
    val root = pipe.takeIf { it.isNotEmpty() }?.let { SamePair.root(it) }
    if (root != null && Book.shownFace(root).exists()) return c.peerFace(root, name, side)
    val g = avatarInitial(name)
    return FrameLayout(c).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(MT.memberTint(ref)) }
        addView(c.text(g, side * avatarGlyphScale(g), Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(MATCH, MATCH))   // USER-DATA: the first letter of a person's name
    }
}
/** [COMPAT-LOCAL] a speaker's reference name (iOS MTGroup.speaker: «gm:», the group, «/», the seat): this phone's own, the seed of the seat's colour, never on the wire. */
private fun chSpeakerRef(key: String, seat: String) = "gm:" + key.removePrefix("grp:") + "/" + seat

/**
 * THE PLATFORM'S QUESTION BEFORE A DEED (iOS .confirmationDialog(titleVisibility: .visible) with one Button(role: .destructive)): the app's
 * own dialog (Theme.Montana.Dialog, as the group's page and the settings ask), the question as its title -- a long one as its words --, the
 * deed in the platform's red, «Cancel» beside it.
 */
internal fun chAsk(act: MainActivity, title: String?, words: String?, deed: Int, work: () -> Unit) {
    val d = AlertDialog.Builder(act).apply {
        if (title != null) setTitle(title)
        if (words != null) setMessage(words)
    }.setPositiveButton(deed) { _, _ -> work() }.setNegativeButton(R.string.cancel, null).show()
    d.getButton(AlertDialog.BUTTON_POSITIVE)?.setTextColor(SysColor.red)
}

/** THE PAGE READS THE CHANNEL AGAIN WHILE IT STANDS (iOS the pages' @EnvironmentObject store: a moved store draws them again): told by the book on the main thread, from the moment the page stands until it leaves. */
private fun View.chRedrawsWithBook(draw: () -> Unit) {
    val again: () -> Unit = { draw() }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { Book.listen(again); draw() }
        override fun onViewDetachedFromWindow(v: View) { Book.unlisten(again) }
    })
}

/** The deed a row's swipe uncovers (iOS .swipeActions(edge: .trailing) with one Button(role: .destructive)): a Label shows its glyph alone, a Text its words. */
private class ChannelSwipeDeed(val words: String?, val glyph: Int?, val work: () -> Unit)

/** The row standing open: one row of the pages stands open at a time, as on iOS's list. */
private var chOpenRow: WeakReference<ChannelSwipeRow>? = null

/**
 * A ROW THAT UNCOVERS ITS DEED (iOS List .swipeActions, MontanaChannel.swift:542-546, 661-663, 768-770): the row follows the finger to the
 * left over the platform's red, the deed riding the row's edge; let go past half the deed it stays open, past half the row the deed is
 * done at once (the platform's full swipe, felt as it is reached); a tap on the deed does it, a tap on the open row or the list's move
 * closes it. The plate under the rows keeps its rounded corners over the red (clipToOutline). The stroke is the row's anywhere on it: the
 * page under a channel's page has no pager to take it sideways.
 */
private class ChannelSwipeRow(c: Context, private val content: View, private val deed: ChannelSwipeDeed) : FrameLayout(c) {
    private val red = View(c).apply { setBackgroundColor(SysColor.red); visibility = INVISIBLE }
    private val box = FrameLayout(c).apply { visibility = INVISIBLE }
    private val side: Int
    private val slop = ViewConfiguration.get(c).scaledTouchSlop
    private var downX = 0f
    private var downY = 0f
    private var startT = 0f
    private var shift = 0f
    private var watching = false
    private var dragging = false
    private var armed = false
    private var anim: ValueAnimator? = null
    // AN OPEN ROW CLOSES WHEN THE LIST MOVES (iOS: the platform's own swipe actions close on scroll)
    private val onScroll = ViewTreeObserver.OnScrollChangedListener { if (shift < 0f && !dragging) settle(0f) }

    init {
        val glyph = deed.glyph
        if (glyph != null) {
            side = dp(74)
            box.addView(c.icon(glyph, Color.WHITE, 22), LayoutParams(dp(22), dp(22), Gravity.CENTER))
        } else {
            val words = c.text(deed.words.orEmpty(), 15f, Color.WHITE).apply { typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL); isSingleLine = true }
            words.measure(MeasureSpec.UNSPECIFIED, MeasureSpec.UNSPECIFIED)
            side = maxOf(dp(74), words.measuredWidth + dp(32))
            box.addView(words, LayoutParams(WRAP, WRAP, Gravity.CENTER))
        }
        box.setOnClickListener { settle(0f); deed.work() }
        addView(red, LayoutParams(MATCH, MATCH))
        addView(box, LayoutParams(side, MATCH, Gravity.END))
        addView(content, LayoutParams(MATCH, WRAP))
    }

    /** The row moved by `x` (0 closed, below it open): the red uncovered alone, the deed at the row's edge. */
    private fun place(x: Float) {
        shift = x
        content.translationX = x
        val moved = x < 0f
        red.visibility = if (moved) VISIBLE else INVISIBLE
        box.visibility = if (moved) VISIBLE else INVISIBLE
        if (!moved) return
        red.clipBounds = Rect((width + x).toInt().coerceAtLeast(0), 0, width, height)
        box.translationX = side + x   // in its own place when the row stands open, past the row's end when it is closed
    }

    /** Where a pull becomes the full swipe: past half the row, and well past the deed's own width. */
    private fun fullAt() = minOf(width * 0.9f, maxOf(width * 0.55f, (side + dp(48)).toFloat()))

    /** Whether a stroke becomes the row's: sideways past the slop, to the left -- or either way on an open row. */
    private fun decide(e: MotionEvent): Boolean {
        val dx = e.x - downX
        val dy = e.y - downY
        if (abs(dy) > slop && abs(dy) > abs(dx)) { watching = false; return false }   // the list's own scroll
        if (abs(dx) > slop && abs(dx) > abs(dy) && (dx < 0f || startT < 0f)) {
            watching = false; dragging = true
            downX = e.x; startT = shift   // the row moves on from where the finger is, never with a jump
            parent?.requestDisallowInterceptTouchEvent(true)
            return true
        }
        return false
    }

    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                anim?.cancel()
                chOpenRow?.get()?.takeIf { it !== this }?.settle(0f)   // another open row closes as this one is touched
                downX = e.x; downY = e.y; startT = shift; watching = true; dragging = false
            }
            MotionEvent.ACTION_MOVE -> if (watching) return decide(e)
            // a tap on the open row closes it and opens nothing under it; a tap on the deed is the deed's
            MotionEvent.ACTION_UP -> if (watching && startT < 0f && e.x < width + shift) { watching = false; settle(0f); return true }
            MotionEvent.ACTION_CANCEL -> watching = false
        }
        return false
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> return true   // a stroke no part of the row took may still become the row's
            MotionEvent.ACTION_MOVE -> {
                if (!dragging) { if (watching) decide(e); return true }
                place((startT + e.x - downX).coerceIn(-width.toFloat(), 0f))
                val past = -shift > fullAt()
                if (past != armed) {
                    armed = past
                    if (past) performHapticFeedback(if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE else HapticFeedbackConstants.LONG_PRESS)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val up = e.actionMasked == MotionEvent.ACTION_UP
                val full = dragging && armed && up
                val pulled = dragging
                dragging = false; armed = false; watching = false
                when {
                    full -> { settle(0f); deed.work() }
                    !pulled -> if (shift < 0f && up) settle(0f)
                    -shift > side / 2f -> settle(-side.toFloat())
                    else -> settle(0f)
                }
            }
        }
        return true
    }

    /** The row goes to `to` by the platform's short ease; open, it is the one open row. */
    private fun settle(to: Float) {
        anim?.cancel()
        chOpenRow = if (to < 0f) WeakReference(this) else chOpenRow?.takeIf { it.get() !== this }
        if (width == 0 || shift == to) { place(to); return }
        anim = ValueAnimator.ofFloat(shift, to).apply {
            duration = 220
            interpolator = DecelerateInterpolator(1.6f)
            addUpdateListener { place(it.animatedValue as Float) }
            start()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnScrollChangedListener(onScroll)
        (parent as? View)?.clipToOutline = true   // the plate's rounded corners over the red
    }

    override fun onDetachedFromWindow() {
        viewTreeObserver.removeOnScrollChangedListener(onScroll)
        anim?.cancel()
        if (chOpenRow?.get() === this) chOpenRow = null
        super.onDetachedFromWindow()
    }
}
