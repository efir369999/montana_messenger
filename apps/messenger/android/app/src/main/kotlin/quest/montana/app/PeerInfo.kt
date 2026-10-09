package quest.montana.app

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.text.InputType
import android.text.format.DateUtils
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Date
import kotlin.math.abs

// ─────────────────────────── what the page knows of a person (iOS MTPeerAbout, MontanaSafety, SafetyStore) ───────────────────────────

/**
 * THE PERSON'S OWN WORDS ABOUT THEMSELVES (iOS MTPeerAbout): their bio and their link, told by the AB: word {b, l, at} and kept
 * here, the latest word winning. Only the web is ever opened from a link: a scheme other than https or http is not kept.
 */
object PeerAbout {
    const val BIO_LIMIT = 140
    const val LINK_LIMIT = 256

    class About(val bio: String, val link: String, val at: Double)

    fun of(ref: String): About? = runCatching {
        JSONObject(Prefs.str("about.$ref", "")).let { About(it.optString("b"), it.optString("l"), it.optDouble("at", 0.0)) }
    }.getOrNull()

    /** Every correspondent's words held here, for a copy (iOS MTPeerAbout 75, 99-101: «peerAbout», one map of conversation to bio, link, moment). */
    fun all(): Map<String, About> = Prefs.keys("about.").mapNotNull { k -> k.removePrefix("about.").let { r -> of(r)?.let { r to it } } }.toMap()
    /** A copy laid (iOS SeedScope.unionKeys 6311): a correspondent whose words stand here keeps them, the copy adds the others. */
    fun lay(m: Map<String, About>) { for ((r, a) in m) if (r.isNotEmpty() && of(r) == null) note(r, a.bio, a.link, a.at) }

    /** Their word arrived: an older word changes nothing. */
    fun note(ref: String, bio: String, link: String, at: Double) {
        val held = of(ref)
        if (held != null && held.at > at) return
        Prefs.setStr("about.$ref", JSONObject().put("b", bio.take(BIO_LIMIT)).put("l", url(link)?.toString() ?: "").put("at", at).toString())
    }

    /** A link as a person types it: «site.org» wears https; nothing but the web is a link here. */
    fun url(s: String): Uri? {
        val t = s.trim()
        if (t.isEmpty() || t.length > LINK_LIMIT) return null
        val u = Uri.parse(if (t.contains("://")) t else "https://$t")
        val scheme = u.scheme?.lowercase()
        if (scheme != "https" && scheme != "http") return null
        if (u.host?.contains('.') != true) return null
        return u
    }

    /** A link as a page shows it: the site and the path, without the scheme. */
    fun shown(u: Uri): String {
        var s = u.toString()
        for (p in listOf("https://", "http://")) if (s.lowercase().startsWith(p)) s = s.substring(p.length)
        return s.removeSuffix("/")
    }
}

/** THE BLOCK AND THE VERIFIED NUMBER (iOS MontanaSafety / SafetyStore): one owner each; every road asks here. */
/**
 * A LINK GOES AS A LINK (iOS MTShare.web, MontanaE2E.swift:267-274; the author's word 07.10.2026 00:1x MSK: «Share gives one link
 * that opens in the browser, not a text that turned into a file»): a string that is a web address goes alone; null — it is none.
 */
fun webLink(s: String): String? {
    val t = s.trim()
    val u = runCatching { Uri.parse(t) }.getOrNull() ?: return null
    val scheme = u.scheme?.lowercase()
    return if ((scheme == "https" || scheme == "http") && !u.host.isNullOrEmpty()) t else null
}

object PeerSafety {
    fun isBlocked(ref: String) = Prefs.bool("block.$ref", false)
    /**
     * THE BLOCK IS SAID TO THE BLOCKED AS «GONE» (iOS ChatStore.toggleBlocked 972-984, E2E.announceBlocked 1441-1474, the author's word
     * 15.09): my face taken back and one presence word «gone»; the unblocked one meets me anew — my name, my face, my presence.
     * Android only kept a flag: the blocked person kept my picture and saw me as before.
     */
    fun setBlocked(ref: String, on: Boolean) {
        if (isBlocked(ref) == on) return
        Prefs.setBool("block.$ref", on)
        if (on) { Presence.drop(ref); Post.blocked(ref) } else Post.unblocked(ref)
    }
    fun isVerified(ref: String) = Prefs.bool("fpVerified.$ref", false)
    fun setVerified(ref: String, on: Boolean) = Prefs.setBool("fpVerified.$ref", on)

    /** Every person blocked here: a copy carries them as the iPhone's «blockedChats» (iOS SeedScope.dataKeys, MontanaChatStore.swift 6132). */
    fun blocked(): List<String> = Prefs.keys("block.").filter { Prefs.bool(it, false) }.map { it.removePrefix("block.") }
    /**
     * A COPY LAID (iOS layCard under SeedScope.unionKeys, MontanaChatStore.swift 6307; takeStored 2134): a block the copy carries
     * stands here too, and none stands down. Said to nobody — the iPhone lays it as silently (blockedChats' didSet 861-866 only writes).
     */
    fun layBlocked(refs: List<String>) { for (r in refs) if (r.isNotEmpty() && !isBlocked(r)) Prefs.setBool("block.$r", true) }
    /** The correspondences checked face to face (iOS SafetyStore, MontanaScreens.swift 184-195): carried, and laid as a union. */
    fun verified(): List<String> = Prefs.keys("fpVerified.").filter { Prefs.bool(it, false) }.map { it.removePrefix("fpVerified.") }
    fun layVerified(refs: List<String>) { for (r in refs) if (r.isNotEmpty()) setVerified(r, true) }

    /**
     * THE BARRED ADDRESSES (iOS MontanaSafety.barred/setBarred, MontanaSafety.swift:28-41; ChatStore.refuses, MontanaChatStore.swift:879;
     * MontanaWakePush.swift:155-158): an address the network's operators barred after a report is refused like a blocked one — the
     * node itself cannot bar anyone, it sees labels, never identities, so the bar rides the doors' answer down to the phones.
     */
    /** The barred addresses as kept (iOS MontanaSafety.barred, MontanaSafety.swift 33): a copy carries them, laid as a union. */
    fun barred(): List<String> = Prefs.str("barredPeers", "").split('\n').filter { it.isNotEmpty() }
    fun isBarred(ref: String) = ref in Prefs.str("barredPeers", "").split('\n').filter { it.isNotEmpty() }
    fun setBarred(list: List<String>) {
        val clean = list.map { it.trim() }.filter { it.isNotEmpty() }
        if (clean.toSet() == Prefs.str("barredPeers", "").split('\n').filter { it.isNotEmpty() }.toSet()) return
        Prefs.setStr("barredPeers", clean.joinToString("\n"))
        android.util.Log.d("Montana", "barred n=" + clean.size)
    }

    /**
     * THE CORRESPONDENCE'S NUMBER (iOS MTPipe.fingerprint): 5200 rounds of SHA-256("mt-safety" ‖ 0 ‖ h) over the pipe's secret,
     * six groups of five digits. Both sides derive it from the same secret; a stranger in the middle would have had to replace
     * exactly that secret, and the number changes the moment they do.
     */
    fun fingerprint(ref: String): String? {
        val secret = Book.secret(ref)?.takeIf { it.size == 32 } ?: return null
        val domain = "mt-safety".toByteArray() + byteArrayOf(0)
        var h = secret
        repeat(5200) { h = MessageDigest.getInstance("SHA-256").digest(domain + h) }
        return (0 until 6).joinToString("") { i ->
            var v = 0L
            for (k in 0 until 5) v = (v shl 8) or (h[i * 5 + k].toLong() and 0xFF)
            "%05d".format(v % 100_000)
        }
    }
}

/**
 * THE PERSON KEPT AS A CONTACT (iOS isInContacts, the list mtContacts): marked once their card is saved in the phone or a card of the
 * phone is taken for them; from then the page offers neither «Create new contact» nor «Add to existing».
 */
object PeerContact {
    fun isKept(ref: String) = Prefs.bool("contact.$ref", false)
    fun keep(ref: String) = Prefs.setBool("contact.$ref", true)
    /** Every person kept, for a copy (iOS «mtContacts», isInContacts MontanaPeerInfo.swift 395-399: kept when the list names them). */
    fun all(): List<String> = Prefs.keys("contact.").filter { Prefs.bool(it, false) }.map { it.removePrefix("contact.") }
}

// ─────────────────────────── the panes (iOS MTMediaTab) ───────────────────────────

private enum class Tab(val title: Int, val icon: Int, val empty: Int) {
    WALL(R.string.pi_wall, R.drawable.ic_compose_photo, R.string.pi_wall_empty),
    MEDIA(R.string.pi_media, R.drawable.ic_photo, R.string.pi_media_empty),
    VIDEO(R.string.pi_video, R.drawable.ic_peer_video, R.string.pi_video_empty),
    FILES(R.string.pi_files, R.drawable.ic_set_doc, R.string.pi_files_empty),
    LINKS(R.string.pi_links, R.drawable.ic_link, R.string.pi_links_empty),
    MUSIC(R.string.pi_music, R.drawable.ic_music_note, R.string.pi_music_empty),
    VOICE(R.string.pi_voice, R.drawable.ic_mic, R.string.pi_voice_empty),
}

/** A letter of the conversation as the panes read it: its kind, its file, its manifest. */
private class Item(val m: Msg, val kind: String, val file: File?, val name: String?, val size: Long, val du: Double)

private val AUDIO_EXT = setOf("mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff", "alac")

private fun itemOf(m: Msg): Item? {
    if (!m.text.startsWith(Marks.MEDIA)) return null
    val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text) ?: return null
    val f = m.file?.let { File(it) }?.takeIf { it.exists() }
    return Item(m, man.optString("k"), f, man.optString("n").ifEmpty { null }, man.optLong("sz"), man.optDouble("du", 0.0))
}
private fun Item.isMusic() = kind == "doc" && (name ?: file?.name ?: "").substringAfterLast('.', "").lowercase() in AUDIO_EXT

/**
 * A MONTANA LINK, FOUND BY ITS OWN SCHEME (iOS MTLinks.find, MontanaPeerInfo.swift:162-180, atom 20c5cef6f490): the trailing
 * punctuation a sentence glues on stays outside it.
 */
fun montanaLinkMatches(text: String): List<Pair<IntRange, Uri>> {
    val trail = ".,;:!?)]}>»›\"'’”…"
    val out = mutableListOf<Pair<IntRange, Uri>>()
    for (mm in Regex("montana://\\S+", RegexOption.IGNORE_CASE).findAll(text)) {
        var end = mm.range.last
        while (end >= mm.range.first && text[end] in trail) end--
        if (end < mm.range.first) continue
        val found = text.substring(mm.range.first, end + 1)
        if (found.lowercase().startsWith(ChessLetter.LINK)) continue   // a game's letter is no link (iOS MTLinks.find 173)
        out.add((mm.range.first..end) to Uri.parse(found))
    }
    return out
}

/**
 * THE WORDS WEARING THEIR LINKS, OPEN AT A TOUCH (iOS MTLinks.marked/MTLinks.linked, MontanaPeerInfo.swift:185-203, atom
 * 20c5cef6f490): the web's own finder and a Montana link by its own scheme alike; a Montana link opens on the app's own road,
 * a web link on the platform's.
 */
fun linkedWords(text: String, openMontana: (Uri) -> Unit): android.text.SpannableString {
    val s = android.text.SpannableString(text)
    android.text.util.Linkify.addLinks(s, android.text.util.Linkify.WEB_URLS)
    for ((range, uri) in montanaLinkMatches(text)) {
        s.setSpan(object : android.text.style.ClickableSpan() {
            override fun onClick(widget: View) { openMontana(uri) }
        }, range.first, range.last + 1, android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
    return s
}

/** The links a letter carries: the platform's own finder, and a Montana link by its own scheme (iOS MTLinks, atom 20c5cef6f490). */
private fun linksIn(text: String): List<Uri> {
    if (Marks.isService(text) || text.length > 20_000) return emptyList()
    val out = mutableListOf<Uri>()
    val m = android.util.Patterns.WEB_URL.matcher(text)
    while (m.find()) PeerAbout.url(m.group())?.let { out.add(it) }
    montanaLinkMatches(text).forEach { out.add(it.second) }
    return out
}

private fun select(tab: Tab, msgs: List<Msg>): List<Msg> = when (tab) {
    Tab.WALL -> emptyList()   // the wall is its owner's posts, not the letters
    Tab.MEDIA -> msgs.filter { itemOf(it)?.kind == "img" }
    Tab.VIDEO -> msgs.filter { itemOf(it)?.kind == "vid" }
    Tab.FILES -> msgs.filter { itemOf(it)?.let { i -> i.kind == "doc" && !i.isMusic() } == true }
    Tab.LINKS -> msgs.filter { linksIn(it.text).isNotEmpty() }
    Tab.MUSIC -> msgs.filter { itemOf(it)?.isMusic() == true }
    Tab.VOICE -> msgs.filter { itemOf(it)?.kind == "aud" }
}

// ─────────────────────────── the page (iOS MontanaPeerInfoScreen) ───────────────────────────

/**
 * THE CORRESPONDENT'S PAGE (iOS MontanaPeerInfoScreen): the face, their name, their bio and their link each on its own glass
 * bubble; the four plates — message, call, video, more; the fingerprint and the sharing of the contact; report and block; and
 * the strip of panes — the wall, then what the conversation carried: media, video, files, links, music, voices, newest on top,
 * cut by day. The whole page scrolls as one. A hold on an item opens the chat's own menu of its letter; «Show in chat» and a
 * forward land through [toChat] — the chat beneath jumps, or another opens (iOS ui.showLetter).
 */
fun peerInfoPage(act: MainActivity, ref: String, onClose: () -> Unit,
                 toChat: (String, String?) -> Unit = { to, mid -> act.push { close -> conversationPage(act, to, close, jump = mid) } }): View {
    val c: Context = act
    var name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(0, dp(56), 0, dp(40)) }

    fun notYet() = Toast.makeText(c, R.string.compose_not_yet, Toast.LENGTH_SHORT).show()
    lateinit var redrawAll: () -> Unit

    // ── the face and the head's lines: one owner, the settings' and my page's own (iOS MTFacePage, MTFaceHeader) ──
    val face = FaceHead(act, body)
    fun drawHead() {
        name = Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)
        val about = PeerAbout.of(ref)
        val f = Book.shownFace(ref)
        face.draw(if (f.exists()) BitmapFactory.decodeFile(f.path) else null, name, PeerSafety.isBlocked(ref),
            about?.bio.orEmpty(), PeerAbout.url(about?.link ?: ""), Book.chat(ref)?.note.orEmpty())
    }

    // ── the four plates (iOS MTPeerAction): message, voice call, video call, more; a blocked person is not called ──
    val actions = c.hstack { setPadding(dp(16), dp(10), dp(16), dp(6)) }
    fun drawActions() {
        actions.removeAllViews()
        fun plate(icon: Int, label: Int, work: (View) -> Unit) {
            if (actions.childCount > 0) actions.addView(View(c), lp(c.dp(10), 1))
            actions.addView(FrameLayout(c).apply {
                background = c.glassPlate().apply { cornerRadius = dp(22).toFloat() }
                contentDescription = c.getString(label)
                addView(c.icon(icon, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
                pressable { work(this) }
            }, lp(0, c.dp(44), 1f))   // the touch target's height, the glyph 20 (iOS actionFace)
        }
        plate(R.drawable.ic_peer_message, R.string.pi_message) { onClose() }   // opened from the chat: back to it
        if (!PeerSafety.isBlocked(ref)) {
            plate(R.drawable.ic_peer_phone, R.string.pi_voice_call) { act.callOut(ref) }
            plate(R.drawable.ic_peer_video, R.string.pi_video_call) { act.callOut(ref, video = true) }
        }
        plate(R.drawable.ic_more_horiz, R.string.pi_more) { v ->
            PopupMenu(c, v).apply {
                menu.add(c.getString(R.string.pi_chat_background))
                setOnMenuItemClickListener { act.push { close -> wallpaperPicker(act, ref, close) }; true }   // iOS: More → Chat background
            }.show()
        }
    }

    // ── the rows (iOS MTInfoSectionsView): the fingerprint and the contact; then report and block ──
    fun row(icon: Int, title: String, detail: String? = null, red: Boolean = false, chevron: Boolean = false, tint: Int? = null,
            work: () -> Unit): View = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(12), dp(14), dp(12))
        minimumHeight = dp(52)
        addView(c.icon(icon, tint ?: if (red) SysColor.red else MT.gray), lp(dp(22), dp(22)).apply { marginEnd = dp(14) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(title, 17f, if (red) SysColor.red else Color.WHITE))
            if (detail != null) addView(c.text(detail, 11f, tint ?: MT.gray))   // the detail in the glyph's own tint (iOS disclosure)
        }, lp(0, WRAP, 1f))
        if (chevron) addView(c.icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18), lp(dp(18), dp(18)))
        pressable(work)
    }
    fun glassGroup(vararg rows: View): View = c.vstack(Gravity.NO_GRAVITY) {
        background = c.glassPlate().apply { cornerRadius = dp(20).toFloat() }
        rows.forEachIndexed { i, r ->
            if (i > 0) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(52) })
            addView(r, lp())
        }
    }
    val sections = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), dp(10), dp(16), 0) }
    fun drawSections() {
        sections.removeAllViews()
        val verified = PeerSafety.isVerified(ref)
        val first = mutableListOf<View>()
        // grey until compared, green once compared (iOS info.fingerprint: checkmark.shield.fill, shield.lefthalf.filled)
        if (Book.secret(ref) != null) first.add(row(if (verified) R.drawable.ic_checkmark_shield else R.drawable.ic_shield,
            c.getString(R.string.pi_fingerprint), c.getString(if (verified) R.string.pi_verified else R.string.pi_not_verified), chevron = true,
            tint = if (verified) MT.green else MT.gray) {
            act.push { close -> safetyPage(act, ref, name) { close(); redrawAll() } }
        })
        // SHARE CONTACT (iOS shareContact, MontanaPeerInfoScreen.swift:379-390): the correspondent's own daily link, handed to us to
        // hand on. A LINK GOES AS A LINK (iOS MTShare.web, MontanaE2E.swift:267-274, the author's word 07.10 00:1x): a web address
        // goes alone, so the receiving app opens it in the browser; anything else goes as «<name> is in Montana!» and the link
        // (MontanaConv.contactMessage, MontanaPQ.swift:212-216). Without a fresh link it is asked for, «Asking for the contact
        // link…» standing on the screen, and a peer that does not answer within six seconds is asleep or older — said honestly
        first.add(row(R.drawable.ic_share, c.getString(R.string.pi_share_contact)) {
            fun share(link: String) = runCatching {
                val text = webLink(link) ?: (c.getString(R.string.pi_contact_share_msg, name) + "\n" + link)
                act.startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND)
                    .setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, text), null))
            }
            PeerLinks.fresh(ref)?.let { share(it); return@row }
            LiveDraft.askLink(ref)
            var cancelled = false
            val asking = AlertDialog.Builder(c).setMessage(R.string.pi_asking_link)
                .setNegativeButton(R.string.cancel) { d, _ -> cancelled = true; d.dismiss() }.show()
            val asked = System.currentTimeMillis()
            lateinit var wait: Runnable
            wait = Runnable {
                if (!cancelled) {
                    val got = PeerLinks.fresh(ref)
                    when {
                        got != null -> { asking.dismiss(); share(got) }
                        System.currentTimeMillis() - asked < 6000 -> MainThread.later(300, wait)
                        else -> { asking.dismiss(); AlertDialog.Builder(c).setMessage(R.string.pi_link_unavailable).setPositiveButton(android.R.string.ok, null).show() }
                    }
                }
            }
            MainThread.later(300, wait)
        })
        sections.addView(glassGroup(*first.toTypedArray()), lp())
        val blocked = PeerSafety.isBlocked(ref)
        val second = mutableListOf<View>()
        // THE PHONE'S ADDRESS BOOK (iOS settings.newContact / settings.existingContact), WHILE THE PERSON IS NOT KEPT (iOS
        // !isInContacts): a new card of the phone with the person's name, kept once the phone says it is saved; or a card of the
        // phone whose name becomes my name for this person (iOS attachToExistingCard)
        if (!PeerContact.isKept(ref)) {
            second.add(row(R.drawable.ic_person_add, c.getString(R.string.pi_new_contact)) {
                val card = android.content.Intent(android.provider.ContactsContract.Intents.Insert.ACTION)
                    .setType(android.provider.ContactsContract.RawContacts.CONTENT_TYPE)
                    .putExtra(android.provider.ContactsContract.Intents.Insert.NAME, Book.chat(ref)?.shown ?: "")
                act.addContact(card) { saved -> if (saved) { PeerContact.keep(ref); redrawAll() } }
            })
            second.add(row(R.drawable.ic_bar_contacts, c.getString(R.string.pi_existing_contact)) {
                act.pickContact { uri ->
                    if (uri == null) return@pickContact
                    val shown = runCatching {
                        c.contentResolver.query(uri, arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME), null, null, null)
                            ?.use { cur -> if (cur.moveToFirst()) cur.getString(0) else null }
                    }.getOrNull()?.trim()
                    if (!shown.isNullOrEmpty()) {
                        val parts = shown.split(" ", limit = 2)
                        Book.saveCard(ref, parts[0], parts.getOrElse(1) { "" }, Book.chat(ref)?.note ?: "", null, false)
                    }
                    PeerContact.keep(ref)
                    redrawAll()
                }
            })
        }
        second.add(row(R.drawable.ic_report, c.getString(R.string.pi_report), red = true) {
            act.push { close -> reportPage(act, ref, name) { close(); redrawAll() } }
        })
        second.add(row(R.drawable.ic_hand, c.getString(if (blocked) R.string.pi_unblock else R.string.pi_block), red = true) {
            if (blocked) { PeerSafety.setBlocked(ref, false); redrawAll() }
            else askBlock(act, ref) { redrawAll() }
        })
        sections.addView(glassGroup(*second.toTypedArray()), lp().apply { topMargin = c.dp(22) })
    }

    // ── THE STRIP (iOS MTTabStrip): the system's glass capsule 44 tall stands still on the page's margin and the words roll inside it,
    // under its edge; the chosen word wears the system's grey pill, which rides to the next one; while every word fits, the tabs
    // share the capsule equally ──
    var tab = Tab.WALL   // a page opens on its wall
    val dim = Color.argb(153, 235, 235, 245)   // iOS .secondaryLabel
    val words = Tab.values().map { t ->
        c.text(c.getString(t.title), 15f, dim, center = true).apply { typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL); maxLines = 1 }
    }
    val pill = View(c).apply { background = c.rounded(Color.rgb(58, 58, 60), 19) }   // iOS .systemGray4
    val wordRow = c.hstack { setPadding(dp(3), dp(3), dp(3), dp(3)) }
    words.forEach { wordRow.addView(it, lp(WRAP, c.dp(38))) }
    val track = FrameLayout(c).apply {
        addView(pill, FrameLayout.LayoutParams(0, dp(38)).apply { topMargin = dp(3) })
        addView(wordRow, FrameLayout.LayoutParams(WRAP, MATCH))
    }
    val roll = HorizontalScrollView(c).apply {
        isHorizontalScrollBarEnabled = false; overScrollMode = View.OVER_SCROLL_NEVER
        addView(track, FrameLayout.LayoutParams(WRAP, MATCH))
    }
    val bar = FrameLayout(c).apply {
        background = c.glassPlate()
        clipToOutline = true   // the words roll under the capsule's own edge
        addView(roll, FrameLayout.LayoutParams(MATCH, MATCH))
    }
    var slots = IntArray(0)   // each word's place in the track
    var spans = IntArray(0)   // and its width
    // the words' places: equal shares of the capsule while all fit, else each its own width and 16 on either side (iOS layoutSubviews)
    fun lay() {
        val inner = bar.width - c.dp(6)
        if (inner == minOf(inner, 0)) return
        val natural = words.map { v -> v.paint.measureText(v.text.toString()).toInt() + 1 + c.dp(32) }
        val fits = natural.sum() == minOf(natural.sum(), inner)
        val n = words.size
        val share = inner / n
        var x = c.dp(3)
        slots = IntArray(n); spans = IntArray(n)
        words.forEachIndexed { i, v ->
            val w = if (!fits) natural[i] else if (i == n - 1) inner - share * (n - 1) else share
            slots[i] = x; spans[i] = w; x += w
            v.layoutParams = (v.layoutParams as LinearLayout.LayoutParams).apply { width = w }
        }
    }
    // the pill under the chosen word, ridden there on the platform's spring of 0.4 s (iOS place, usingSpringWithDamping 0.85)
    fun place(animated: Boolean) {
        val i = tab.ordinal
        if (i == maxOf(i, slots.size)) return
        words.forEachIndexed { k, v -> v.setTextColor(if (k == i) Color.WHITE else dim) }
        val p = pill.layoutParams as FrameLayout.LayoutParams
        if (!animated || pill.width == 0) { p.width = spans[i]; pill.layoutParams = p; pill.translationX = slots[i].toFloat(); return }
        val fromX = pill.translationX; val fromW = pill.width
        android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 400; interpolator = android.view.animation.DecelerateInterpolator(2f)
            addUpdateListener { a ->
                val f = a.animatedValue as Float
                pill.translationX = fromX + (slots[i] - fromX) * f
                p.width = (fromW + (spans[i] - fromW) * f).toInt(); pill.layoutParams = p
            }
        }.start()
    }
    val pane = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), 0) }
    lateinit var drawPane: () -> Unit

    // ── THE ITEM LAW AND THE SELECTION (iOS MTProfileItem, selectionBar): a hold opens the chat's menu of the letter, «Select» in it
    // begins the page's own selection; the bar at the foot forwards the chosen through the chat's picker or deletes them for me ──
    var selecting = false
    val chosen = linkedSetOf<String>()
    val foot = FrameLayout(c).apply { visibility = View.GONE }
    lateinit var drawFoot: () -> Unit
    fun endSelecting() { selecting = false; chosen.clear(); drawPane(); drawFoot() }
    // the page closes first, then the chat beneath jumps to the letter or another chat opens (iOS dismiss, ui.showLetter)
    fun leaveFor(to: String, mid: String?) { onClose(); toChat(to, mid) }
    fun forward(letters: List<Msg>) {
        val sendable = letters.filter { canForward(it) }
        if (sendable.isNotEmpty()) act.push { close -> forwardPage(act, ref, sendable, close) { to -> close(); leaveFor(to, null) } }
    }
    val law = ItemLaw(
        selecting = { selecting },
        chosen = { m -> m.mid in chosen },
        toggle = { m -> if (!chosen.remove(m.mid)) chosen.add(m.mid); drawPane(); drawFoot() },
        menu = { m ->
            letterMenu(act, ref, m, onReply = {}, onEdit = {}, onForward = { forward(listOf(m)) },
                onSelect = { selecting = true; chosen.clear(); chosen.add(m.mid); drawPane(); drawFoot() },
                onShowInChat = { leaveFor(ref, m.mid) })
        },
        redraw = { drawPane() })
    drawFoot = {
        foot.removeAllViews()
        foot.visibility = if (selecting) View.VISIBLE else View.GONE
        body.setPadding(0, c.dp(56), 0, c.dp(if (selecting) 104 else 40))   // the bar's room under the last row (iOS safeAreaInset)
        if (selecting) {
            val letters = (Book.chat(ref)?.msgs ?: emptyList()).filter { it.mid in chosen }
            val any = letters.isNotEmpty()
            fun key(glyph: Int, words: Int, tint: Int, on: Boolean, mirrored: Boolean = false, work: () -> Unit) = FrameLayout(c).apply {
                contentDescription = c.getString(words)
                addView(c.icon(glyph, tint, 20).apply { if (mirrored) scaleX = -1f }, FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER))
                if (on) pressable(work)
            }
            foot.addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setBackgroundColor(Color.argb(235, 44, 44, 46))   // the menus' own material (iOS .ultraThinMaterial)
                setPadding(dp(16), dp(10), dp(16), dp(10))
                addView(key(R.drawable.ic_close, R.string.cancel, Color.rgb(204, 204, 204), true) { endSelecting() }, lp(dp(44), dp(44)))
                addView(View(c), lp(0, 1, 1f))
                addView(c.text(letters.size.toString(), 17f, MT.gray).apply { fontFeatureSettings = "tnum" }, lp(WRAP, WRAP))
                addView(View(c), lp(0, 1, 1f))
                addView(key(R.drawable.ic_reply, R.string.ld_forward, if (any) Color.WHITE else MT.gray, any, mirrored = true) {
                    endSelecting(); forward(letters)
                }, lp(dp(44), dp(44)))
                addView(key(R.drawable.ic_delete, R.string.delete, if (any) SysColor.red else MT.gray, any) {
                    val mids = letters.filter { !CoinSend.travels(it) }.map { it.mid }.toSet()   // a coin letter on its way keeps its row (iOS deleteLocally)
                    Book.edit(ref) { ch -> ch.msgs.removeAll { it.mid in mids } }
                    endSelecting()
                }, lp(dp(44), dp(44)).apply { marginStart = dp(18) })
            }, FrameLayout.LayoutParams(MATCH, WRAP))
        }
    }
    // the chosen word rides into view, a hundred points of its neighbour showing beside it (iOS reveal)
    fun reveal(animated: Boolean) {
        val i = tab.ordinal
        val w = roll.width
        if (w == 0 || i == maxOf(i, slots.size)) return
        val from = slots[i]
        val to = slots[i] + spans[i]
        var x = roll.scrollX
        if (x + w - c.dp(100) < to) x = to - w + c.dp(100)
        if (from - c.dp(100) < x) x = from - c.dp(100)
        x = x.coerceIn(0, maxOf(0, track.width - w))
        if (animated) roll.smoothScrollTo(x, 0) else roll.scrollTo(x, 0)
    }
    fun choose(t: Tab) { if (t != tab) { tab = t; place(true); reveal(true); drawPane() } }
    words.forEachIndexed { i, v -> v.setOnClickListener { choose(Tab.values()[i]) } }
    // the capsule measured anew (the first layout, a turn of the phone): the words take their places again
    bar.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
        if (right - left != oldRight - oldLeft) bar.post { lay(); wordRow.requestLayout(); wordRow.post { place(false); reveal(false) } }
    }
    // THE PANES ARE TURNED BY THE FINGER (iOS MTSwipePanes): one step along the strip, stopping at its ends
    fun turnPane(step: Int) {
        val j = tab.ordinal + step
        if (j in Tab.values().indices) choose(Tab.values()[j])
    }
    fun emptyPane(): View = c.vstack(Gravity.CENTER_HORIZONTAL) {
        setPadding(0, dp(36), 0, dp(36))
        addView(c.icon(tab.icon, MT.gray), lp(dp(42), dp(42)))
        addView(c.text(c.getString(tab.empty), 15f, MT.gray, center = true), lp().apply { topMargin = dp(10) })
    }
    drawPane = {
        pane.removeAllViews()
        val msgs = select(tab, Book.chat(ref)?.msgs ?: emptyList())
        if (tab == Tab.WALL) {
            // THE WRITE BUTTON WHILE THE OWNER LETS ME WRITE (iOS MTBoardRows, MontanaBoardViews.swift:156-161 at 2155): it opens the
            // one new post's page over their wall (MTBoardComposer.present(on: owner)), and the post goes to them
            if (Board.canWrite(ref)) pane.addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                background = c.glassPlate()
                setPadding(dp(14), dp(10), dp(14), dp(10))
                addView(FrameLayout(c).apply {
                    background = c.glassPlate(oval = true)
                    addView(c.icon(R.drawable.ic_compose, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
                }, lp(dp(44), dp(44)).apply { marginEnd = dp(14) })
                addView(c.text(c.getString(R.string.pi_write_wall), 17f))
                pressable { act.push { close -> newPostPage(act, close, wall = ref) } }
            }, lp().apply { topMargin = c.dp(12) })
            // A POST ON ITS WAY TO THEIR WALL stands at once as it will be published, under the bar of its files (iOS MTBoardRows 167-172)
            val onItsWay = MyWall.sending(ref)
            onItsWay.forEach { o -> pane.addView(goingCell(act, o), lp().apply { topMargin = c.dp(10) }) }
            // THE WALL'S OWN ROWS (iOS MTBoardRows, MontanaPeerInfoScreen.swift:646): a person's page shows their wall --
            // the same cells the feed draws (Board.postCell), with no "on X's wall" line of its own (onItsWall).
            val wallPosts = Board.posts(ref)
            if (wallPosts.isEmpty() && onItsWay.isEmpty()) pane.addView(emptyPane(), lp())
            else wallPosts.forEach { item -> pane.addView(postCell(act, item, onItsWall = true), lp().apply { topMargin = c.dp(10) }) }
        } else if (msgs.isEmpty()) pane.addView(emptyPane(), lp())
        else paneRows(act, tab, msgs.reversed(), pane, law)   // newest on top
    }

    redrawAll = { drawHead(); drawActions(); drawSections(); drawPane() }
    body.addView(face.view, lp())
    body.addView(actions, lp())
    body.addView(sections, lp())
    body.addView(bar, lp(MATCH, c.dp(44)).apply { topMargin = c.dp(24); marginStart = c.dp(16); marginEnd = c.dp(16) })
    body.addView(pane, lp())
    redrawAll()
    // THE LOOK ASKS (iOS look, MontanaBoard.swift:609-613, MontanaPeerInfoScreen.swift:636-638, the author's word 25.09):
    // the wall not held, or held more than ten minutes, is asked for the moment this page opens.
    Board.look(ref)
    val wallHeard: () -> Unit = { if (tab == Tab.WALL) drawPane() }

    val listener: () -> Unit = { drawHead(); drawPane(); if (selecting) drawFoot() }
    // the one player's turn redraws the music's glyphs, and only its turn: the clock's ticks change nothing here
    var heard = MusicPlayer.current?.uri to MusicPlayer.playing
    val music: () -> Unit = {
        val now = MusicPlayer.current?.uri to MusicPlayer.playing
        if (now != heard) { heard = now; if (tab == Tab.MUSIC) drawPane() }
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(PageGround.keyOf(ref)), FrameLayout.LayoutParams(MATCH, MATCH))   // the ground they sent, mine where they sent none (iOS MTFacePage 377-406)
        // a stroke begun on the strip rolls the strip and turns nothing; the page scrolled up closes the open face
        val rows = PanesScroll(c, skip = { y -> y in bar.top.toFloat()..bar.bottom.toFloat() }, turn = { turnPane(it) }).apply {
            isVerticalScrollBarEnabled = false; clipToPadding = false; addView(body); face.attach(this)
        }
        // THE ROWS SINK INTO THE GROUND PAST THE MARKS ON TOP AND THE BARS AT THE FOOT (iOS MTPageEdges, MontanaPeerHeader.swift:401)
        lateinit var foot0: View
        addView(EdgeSink(c, top = { c.dp(50) }, bottom = { height - paddingTop - paddingBottom - foot0.height }).apply {
            addView(rows, FrameLayout.LayoutParams(MATCH, MATCH))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        // the back mark on its own round of glass, over the page
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            addView(c.icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { onClose() }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply { setMargins(dp(14), dp(6), 0, 0) })
        // THE DOTS STAND TOP RIGHT (iOS MontanaEditMark: «Edit» behind the platform's three dots): the card's edit page
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.pe_edit)
            addView(c.icon(R.drawable.ic_more_horiz, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            pressable { act.push { close -> peerEditPage(act, ref, close) } }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(6), dp(14), 0) })
        // THE BARS OVER THE PAGE'S BOTTOM STAND OUTSIDE ITS ROWS (iOS MontanaPeerInfoScreen.swift:69-84): the selection's bar over
        // the mini player, both at the foot, and the rows end above them. THE MINI PLAYER STANDS HERE TOO (the author's word 18.09):
        // the same bar as the chat's and the list's, by reference — music and voices started on this page play in it, and a tap on
        // it goes to the letter by the one road (liveBar follows the global Playing state while attached).
        val bars = c.vstack(Gravity.NO_GRAVITY) { addView(foot, lp()); addView(liveBar(act), lp()) }
        foot0 = bars
        bars.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ -> if (rows.paddingBottom != v.height) v.post { rows.setPadding(0, 0, 0, v.height) } }
        addView(bars, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM))
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { Book.listen(listener); Board.listen(wallHeard); MyWall.listen(wallHeard); MusicPlayer.listeners.add(music) }
            override fun onViewDetachedFromWindow(v: View) { Book.unlisten(listener); Board.unlisten(wallHeard); MyWall.unlisten(wallHeard); MusicPlayer.listeners.remove(music) }
        })
    }
}

/**
 * THE PANES ARE TURNED BY THE FINGER (iOS MTSwipePanes): a quick sideways stroke over the page moves to the next tab and back.
 * The page keeps its own scrolling and every row its own tap; a stroke that turned the pane opens nothing under it.
 */
private class PanesScroll(c: Context, private val skip: (Float) -> Boolean, private val turn: (Int) -> Unit) : ScrollView(c) {
    private var turned = false
    private val stroke = GestureDetector(c, object : GestureDetector.SimpleOnGestureListener() {
        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            val from = e1 ?: return false
            if (skip(from.y + scrollY) || abs(vx) < 2 * abs(vy) || abs(e2.x - from.x) < dp(48)) return false
            turned = true
            turn(if (vx < 0) 1 else -1)
            return true
        }
    })
    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        if (e.actionMasked == MotionEvent.ACTION_DOWN) turned = false
        stroke.onTouchEvent(e)
        if (turned && e.actionMasked == MotionEvent.ACTION_UP) e.action = MotionEvent.ACTION_CANCEL
        return super.dispatchTouchEvent(e)
    }
}

/** The day's word over a pane's group (iOS MTDayLabel): «Today», else the date. */
private fun dayWord(c: Context, at: Long) =
    if (DateUtils.isToday(at)) c.getString(R.string.today) else DateUtils.formatDateTime(c, at, DateUtils.FORMAT_SHOW_DATE)

/**
 * A pane's rows, cut by day: tiles three to a row for media and video, glass rows for files, links, music and voices, each under
 * the item law. Music and voices play through the one player, the pane's own in feed order as the queue whichever day the tap lands
 * in (iOS musicList, playVoice); the one playing wears the pause.
 */
private fun paneRows(act: MainActivity, tab: Tab, msgs: List<Msg>, into: LinearLayout, law: ItemLaw) {
    val c: Context = act
    val feed = msgs.reversed()   // the conversation's own order: a queue walks forward from the one tapped
    val days = msgs.groupBy { dayWord(c, it.at) }   // groupBy keeps the order of first appearance: newest day first
    val tracks = if (tab == Tab.MUSIC) feed.mapNotNull { m -> itemOf(m)?.let { i -> i.file?.let { f -> Track(Uri.fromFile(f), i.name ?: f.name) } } } else emptyList()
    val voices = if (tab == Tab.VOICE) feed.filter { m -> itemOf(m)?.file != null } else emptyList()
    fun playVoice(m: Msg) {
        val f = itemOf(m)?.file ?: return
        val next = voices.getOrNull(voices.indexOf(m) + 1)
        VoicePlayer.toggle(f.path, onProgress = { _, _ -> }, stopped = { law.redraw() }, then = next?.let { n -> { playVoice(n) } })
        // their voice played here: its sender is told once, silently, as from the bubble (iOS notePlayed)
        if (!m.mine && VoicePlayer.playing == f.path) Thread { Post.notePlayed(m.mid) }.start()
        law.redraw()
    }
    for ((day, items) in days) {
        into.addView(c.text(day, 12f, MT.gray), lp().apply { topMargin = c.dp(14); bottomMargin = c.dp(6) })
        when (tab) {
            Tab.MEDIA, Tab.VIDEO -> items.chunked(3).forEach { three ->
                into.addView(c.hstack {
                    three.forEachIndexed { i, m -> addView(tile(act, m, law), lp(0, c.dp(120), 1f).apply { if (i > 0) marginStart = c.dp(3) }) }
                    repeat(3 - three.size) { addView(View(c), lp(0, c.dp(120), 1f).apply { marginStart = c.dp(3) }) }
                }, lp().apply { bottomMargin = c.dp(3) })
            }
            Tab.LINKS -> items.forEach { m -> linksIn(m.text).forEach { u ->
                into.addView(glassRow(c, R.drawable.ic_link, u.host ?: u.toString(), u.toString(), m, law) {
                    runCatching { act.startActivity(Intent(Intent.ACTION_VIEW, u)) }
                }, lp().apply { bottomMargin = c.dp(8) })
            } }
            Tab.FILES -> items.forEach { m ->
                val it = itemOf(m) ?: return@forEach
                into.addView(glassRow(c, R.drawable.ic_set_doc, it.name ?: it.file?.name ?: c.getString(R.string.pi_file),
                    android.text.format.Formatter.formatShortFileSize(c, it.size), m, law) {
                    it.file?.let { f -> openMedia(act, f, "doc") }
                }, lp().apply { bottomMargin = c.dp(8) })
            }
            Tab.MUSIC -> items.forEach { m ->
                val it = itemOf(m) ?: return@forEach
                val title = it.name ?: it.file?.name ?: c.getString(R.string.pi_file)
                val uri = it.file?.let { f -> Uri.fromFile(f) }
                val on = uri != null && MusicPlayer.current?.uri == uri && MusicPlayer.playing
                into.addView(glassRow(c, if (on) R.drawable.ic_pause_fill else R.drawable.ic_play_fill, title.substringBeforeLast('.'),
                    android.text.format.Formatter.formatShortFileSize(c, it.size), m, law) {
                    // the one playing pauses and goes on; another starts the queue at itself
                    if (uri != null) {
                        if (MusicPlayer.current?.uri == uri) MusicPlayer.toggle()
                        else tracks.indexOfFirst { t -> t.uri == uri }.takeIf { i -> i != -1 }?.let { i -> MusicPlayer.play(act, tracks, i) }
                    }
                }, lp().apply { bottomMargin = c.dp(8) })
            }
            Tab.VOICE -> items.forEach { m ->
                val it = itemOf(m) ?: return@forEach
                val s = it.du.toInt()
                val on = it.file != null && VoicePlayer.playing == it.file.path
                into.addView(glassRow(c, if (on) R.drawable.ic_pause_fill else R.drawable.ic_play_fill, c.getString(R.string.pi_voice_message),
                    "%d:%02d".format(s / 60, s % 60), m, law) { playVoice(m) }, lp().apply { bottomMargin = c.dp(8) })
            }
            Tab.WALL -> {}
        }
    }
}

/** What a pane's item asks of its page (iOS MTProfileItem's inputs): the selection, the item's mark, its menu, the pane drawn again. */
private class ItemLaw(val selecting: () -> Boolean, val chosen: (Msg) -> Boolean, val toggle: (Msg) -> Unit, val menu: (Msg) -> Unit,
                      val redraw: () -> Unit)

/**
 * THE ITEM LAW (iOS MTProfileItem, one for every pane): the hit area is the item's frame; a tap opens it, a hold opens the chat's
 * own menu of the letter, and while the page selects a tap marks it, the mark in the corner. The press shrinks the item a little.
 */
private fun itemLaw(c: Context, face: View, m: Msg, law: ItemLaw, open: () -> Unit): View = FrameLayout(c).apply {
    addView(face, FrameLayout.LayoutParams(MATCH, MATCH))
    if (law.selecting()) {
        val on = law.chosen(m)
        // iOS checkmark.circle.fill in the accent (white since the gold left) or the empty circle, 22 points, 6 from the corner
        addView(FrameLayout(c).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; if (on) setColor(Color.WHITE) else setStroke(c.dp(1.5f), Color.WHITE) }
            if (on) addView(c.icon(R.drawable.ic_check, Color.BLACK, 14), FrameLayout.LayoutParams(c.dp(14), c.dp(14), Gravity.CENTER))
        }, FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.TOP or Gravity.END).apply { setMargins(0, c.dp(6), c.dp(6), 0) })
    }
    setOnClickListener { if (law.selecting()) law.toggle(m) else open() }
    setOnLongClickListener { law.menu(m); true }
    setOnTouchListener { v, e ->
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> v.animate().scaleX(0.965f).scaleY(0.965f).setDuration(150).start()
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> v.animate().scaleX(1f).scaleY(1f).setDuration(150).start()
        }
        false
    }
}

/** One tile: the picture's own face (the gallery's cache, drawn off the main thread), a play mark on a film; a tap opens it whole. */
private fun tile(act: MainActivity, m: Msg, law: ItemLaw): View {
    val c: Context = act
    val item = itemOf(m)
    val f = item?.file
    val kind = item?.kind ?: "img"
    val face = FrameLayout(c).apply {
        setBackgroundColor(Color.argb(40, 255, 255, 255))
        val img = ImageView(c).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
        addView(img, FrameLayout.LayoutParams(MATCH, MATCH))
        // THE COVER AT THE CELL'S OWN PIXELS (iOS MTCover side, MontanaProfile.swift:1919-1951; MontanaPeerInfoScreen.swift:720 at 2155):
        // a picture is asked so its SHORT side fills 180 points, kept under its own key beside the gallery's smaller drawing of it
        val key = f?.let { x -> if (kind == "img") x.path + "#" + c.dp(180) else x.path }
        val held = key?.let { k -> tileCache.get(k) }
        if (held != null) img.setImageBitmap(held)
        else {
            val man = m.meta?.let { j -> runCatching { JSONObject(j) }.getOrNull() } ?: Media.inline(m.text)
            tileWork.execute {
                val drawn = if (f == null) null else if (kind == "img") cellCover(c, f) else Media.preview(c, f, kind, 360)
                if (drawn != null && key != null) tileCache.put(key, drawn)
                val pic = drawn ?: Media.thumbOf(man)
                if (pic != null) img.post { img.setImageBitmap(pic) }
            }
        }
        if (kind == "vid") addView(c.icon(R.drawable.ic_play_fill, Color.WHITE), FrameLayout.LayoutParams(c.dp(28), c.dp(28), Gravity.CENTER))
    }
    return itemLaw(c, face, m, law) { if (f != null) openMedia(act, f, kind) }
}

/**
 * THE LONGEST SIDE TO ASK SO THE PICTURE'S SHORT SIDE FILLS THE CELL (iOS MTCover.longest, MontanaProfile.swift:1954-1961 at 2155): 180
 * points of short side, never more than the picture has -- the gallery's drawing, sampled by 360 pixels, left a long picture's short
 * side under the cell's.
 */
private fun cellCover(c: Context, f: File): android.graphics.Bitmap? {
    val short = c.dp(180)
    val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(f.path, o)
    val long = maxOf(o.outWidth, o.outHeight)
    val side = minOf(o.outWidth, o.outHeight)
    if (side <= 0) return Media.preview(c, f, "img", short)
    return Media.preview(c, f, "img", minOf(long.toLong(), (short.toLong() * long + side - 1) / side).toInt())
}

/** A row on the bar's own glass (iOS glassRow): the square plate with the glyph, the long plate with the words and the time. */
private fun glassRow(c: Context, icon: Int, title: String, detail: String, m: Msg, law: ItemLaw, open: () -> Unit): View = itemLaw(c, c.hstack {
    gravity = Gravity.CENTER_VERTICAL
    addView(FrameLayout(c).apply {
        background = c.glassPlate().apply { cornerRadius = dp(16).toFloat() }
        addView(c.icon(icon, Color.rgb(204, 204, 204)), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
    }, lp(dp(56), dp(56)).apply { marginEnd = dp(10) })
    addView(c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = c.glassPlate().apply { cornerRadius = dp(16).toFloat() }
        setPadding(dp(14), 0, dp(14), 0)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(title, 16f).apply { singleLineEllipsis() })   // USER-DATA
            addView(c.text(detail, 12f, MT.gray).apply { maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.MIDDLE })
        }, lp(0, WRAP, 1f))
        addView(c.text(android.text.format.DateFormat.getTimeFormat(c).format(Date(m.at)), 11f, MT.gray), lp(WRAP, WRAP).apply { marginStart = dp(8) })
    }, lp(0, dp(56), 1f))
}, m, law, open)

// ─────────────────────────── the fingerprint (iOS SafetyNumberView) ───────────────────────────

/**
 * THE NUMBER OF THIS CORRESPONDENCE: my fingerprint as a code and as sixty digits in groups of five, to compare aloud or face
 * to face; «Verified» marks it compared. (Scanning their code from here comes with the fingerprint scanner.)
 */
private fun safetyPage(act: MainActivity, ref: String, name: String, onClose: () -> Unit): View {
    val c: Context = act
    val digits = PeerSafety.fingerprint(ref) ?: ""
    return settingsPage(act, c.getString(R.string.pi_fingerprint), onClose) {
        val status = c.text("", 15f, MT.gray, bold = true, center = true)
        val mark = c.text("", 17f, Color.BLACK, bold = true, center = true)
        fun draw() {
            val v = PeerSafety.isVerified(ref)
            status.text = c.getString(if (v) R.string.pi_fp_verified_mark else R.string.pi_not_verified)
            status.setTextColor(if (v) MT.green else MT.gray)
            mark.text = c.getString(if (v) R.string.pi_fp_unverify else R.string.pi_fp_verified)
            mark.setTextColor(if (v) Color.WHITE else Color.BLACK)
            // NO YELLOW WORD (iOS MontanaScreens.swift:254, 2155: Color.accentColor, white in the dark): the fill lost its gold with every other word.
            mark.background = c.rounded(if (v) Color.argb(76, 142, 142, 147) else Color.WHITE, 10)
        }
        addView(status, lp().apply { topMargin = c.dp(14) })
        if (digits.isNotEmpty()) addView(QrView(c).apply { code = QrCode.encode("mt:fp:$digits", QrCode.Ecc.M) },
            LinearLayout.LayoutParams(c.dp(200), c.dp(200)).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = c.dp(18) })
        addView(c.text(digits.chunked(5).joinToString(" "), 17f, Color.WHITE, center = true).apply { typeface = Typeface.MONOSPACE },
            lp().apply { topMargin = c.dp(18) })
        addView(c.text(c.getString(R.string.pi_fp_compare), 12f, MT.gray, center = true), lp().apply { topMargin = c.dp(12) })
        addView(mark.apply {
            setPadding(0, dp(12), 0, dp(12))
            pressable { PeerSafety.setVerified(ref, !PeerSafety.isVerified(ref)); draw() }
        }, lp().apply { topMargin = c.dp(18) })
        // THEIR QR READ BY THE CAMERA (iOS SafetyNumberView's scan): only a fingerprint of this shape is compared — any other
        // code keeps the camera looking; the same number verifies, a different one unverifies and is said (it is evidence)
        // NO YELLOW WORD (iOS MontanaScreens.swift:261-262, 2155: Color.accentColor, white in the dark): the text and the stroke alike.
        if (digits.isNotEmpty()) addView(c.text(c.getString(R.string.sn_scan), 17f, Color.WHITE, bold = true, center = true).apply {
            setPadding(0, dp(12), 0, dp(12))
            background = c.rounded(Color.TRANSPARENT, 10, Color.WHITE)
            pressable {
                act.push { close ->
                    scannerPage(act, close) { code ->
                        val payload = code.substringBefore('#').removePrefix("mt:fp:")
                        if (payload.length != digits.length || !payload.all { it in '0'..'9' }) return@scannerPage false
                        val same = payload == digits
                        PeerSafety.setVerified(ref, same)
                        act.onMain {
                            draw()
                            if (!same) android.app.AlertDialog.Builder(act).setTitle(R.string.sn_mismatch).setMessage(R.string.sn_mismatch_note)
                                .setPositiveButton(R.string.ok, null).show()
                        }
                        true
                    }
                }
            }
        }, lp().apply { topMargin = c.dp(10) })
        draw()
    }
}

// ─────────────────────────── the report (iOS MontanaReportSheet) ───────────────────────────

/** A report by mail to the network's address: the reason, «block this person too», the platform's own mail road. */
// A post whose writer the wall never named is reported through its wall, and nobody is offered to be blocked for another's words
// (iOS MontanaReportSheet(offersBlock:), MontanaBoardViews.swift:58-60 at 2155).
fun reportPage(act: MainActivity, ref: String, name: String, offersBlock: Boolean = true, onClose: () -> Unit): View {
    val c: Context = act
    val reasons = listOf("spam" to R.string.pi_spam, "abuse" to R.string.pi_abuse, "hate" to R.string.pi_hate,
        "illegal" to R.string.pi_illegal, "other" to R.string.pi_other)
    var reason = "spam"
    var blockToo = offersBlock
    val mail = "contact@montana.quest"
    return settingsPage(act, c.getString(R.string.pi_report), onClose, cross = true) {
        val rows = reasons.map { (key, words) ->
            c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(12), dp(16), dp(12))
                addView(c.text(c.getString(words), 16f), lp(0, WRAP, 1f))
                // NO YELLOW WORD (iOS MontanaSafety.swift:176, 2155: Color.accentColor, white in the dark): the chosen reason's mark.
                addView(c.icon(R.drawable.ic_check, Color.WHITE, 20).apply { tag = key }, lp(dp(20), dp(20)))
            }
        }
        fun mark() = rows.forEach { r -> (r as LinearLayout).getChildAt(1).visibility = if (r.getChildAt(1).tag == reason) View.VISIBLE else View.INVISIBLE }
        rows.forEachIndexed { i, r -> r.pressable { reason = reasons[i].first; mark() } }
        mark()
        section(c.getString(R.string.pi_reason), null, *rows.toTypedArray())
        if (offersBlock) section(null, null, c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(14), dp(8))
            addView(c.text(c.getString(R.string.pi_block_too), 16f), lp(0, WRAP, 1f))
            addView(Switch(c).apply { isChecked = true; setOnCheckedChangeListener { _, v -> blockToo = v } })
        })
        section(null, c.getString(R.string.pi_reports_go, mail), c.text(c.getString(R.string.pi_send_report), 16f, Color.WHITE).apply {   // iOS .accentColor, white since the gold left (MontanaSafety.swift:204, 2155)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            pressable {
                if (blockToo) PeerSafety.setBlocked(ref, true)
                val text = "Report ($reason)\nReported: $name\n\nBuild: ${versionFooter(c)}"
                val send = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).putExtra(Intent.EXTRA_EMAIL, arrayOf(mail))
                    .putExtra(Intent.EXTRA_SUBJECT, "Montana report ($reason)").putExtra(Intent.EXTRA_TEXT, text)
                val ok = runCatching { act.startActivity(send) }.isSuccess
                if (!ok) {
                    // no mail app: the report and the address are copied, to paste into any mail
                    c.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("", "$mail\n\n$text"))
                    Toast.makeText(c, mail, Toast.LENGTH_LONG).show()
                }
                onClose()
            }
        })
    }
}

/**
 * THE EDIT PAGE (iOS MontanaPeerInfoScreen editor): the face with «Edit» under it — the system's picker, then the circle's
 * crop; the name fields, prefilled with the name as it stands, and «Show original name» with the name they gave themselves
 * when my own stands over it; the note; «Restore original photo» while a picture of mine is on the card. The checkmark
 * saves (iOS MontanaDoneMark); the back mark leaves the card as it was.
 */
fun peerEditPage(act: MainActivity, ref: String, onClose: () -> Unit): View {
    val c: Context = act
    val chat = Book.chat(ref)
    val theirs = chat?.name?.trim().orEmpty()
    val shown = chat?.shown?.trim().orEmpty()
    var photo: ByteArray? = null          // picked just now
    var photoCleared = false              // «Restore original photo» pressed
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), dp(64), dp(16), dp(40)) }

    fun field(hintWords: Int, value: String, multi: Boolean = false) = EditText(c).apply {
        hint = c.getString(hintWords); setText(value)
        setHintTextColor(MT.gray); setTextColor(Color.WHITE); textSize = 17f
        background = null; setPadding(dp(16), dp(13), dp(16), dp(13))
        if (multi) { inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES; minLines = 1; maxLines = 5 }
        else { isSingleLine = true; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_WORDS }
    }
    fun group(vararg rows: View): LinearLayout = c.vstack(Gravity.NO_GRAVITY) {
        background = c.glassPlate().apply { cornerRadius = dp(20).toFloat() }
        rows.forEachIndexed { i, r ->
            if (i > 0) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })
            addView(r, lp())
        }
    }

    // ── the face and «Edit» under it ──
    val faceBox = FrameLayout(c)
    lateinit var drawPhotoRows: () -> Unit
    fun drawFace() {
        faceBox.removeAllViews()
        val bmp = photo?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            ?: (if (photoCleared) Book.face(ref) else Book.shownFace(ref)).let { f -> if (f.exists()) BitmapFactory.decodeFile(f.path) else null }
        faceBox.addView(c.avatar(bmp, shown.ifBlank { "?" }, 100), FrameLayout.LayoutParams(c.dp(100), c.dp(100), Gravity.CENTER_HORIZONTAL))
    }
    fun pick() = act.pickPhoto { uri ->
        val image = uri?.let { SelfFace.decode(act, it) } ?: return@pickPhoto
        lateinit var close: () -> Unit
        close = act.overlay(cropPage(act, image) { jpeg ->
            close()
            if (jpeg != null) { photo = jpeg; photoCleared = false; drawFace(); drawPhotoRows() }
        })
    }
    drawFace()
    body.addView(faceBox, lp(MATCH, WRAP))
    body.addView(c.text(c.getString(R.string.pe_edit), 17f, MT.blue, center = true).apply {
        setPadding(dp(12), dp(10), dp(12), dp(10)); pressable { pick() }
    }, lp(WRAP, WRAP).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = c.dp(16) })

    // ── the name fields; their own name revealed under them when mine stands over it (iOS overName) ──
    val first = field(R.string.pe_first, shown.substringBefore(' '))
    val last = field(R.string.pe_last, if (shown.contains(' ')) shown.substringAfter(' ') else "")
    val overName = chat?.pin != null && theirs.isNotEmpty()
    val original = c.text(theirs, 13f, MT.gray).apply { setPadding(dp(16), dp(6), dp(16), 0); visibility = View.GONE }   // USER-DATA: their own name
    body.addView(if (overName) group(first, last, c.text(c.getString(R.string.pe_show_original), 17f, MT.blue).apply {
        setPadding(dp(16), dp(13), dp(16), dp(13))
        pressable { original.visibility = if (original.visibility == View.VISIBLE) View.GONE else View.VISIBLE }
    }) else group(first, last), lp())
    body.addView(original, lp())

    // ── the note, and «Restore original photo» while a picture of mine stands ──
    val note = field(R.string.pe_note, chat?.note.orEmpty(), multi = true)
    val second = c.vstack(Gravity.NO_GRAVITY)
    drawPhotoRows = {
        second.removeAllViews()
        val mine = photo != null || (!photoCleared && Book.myFace(ref).exists())
        if (note.parent != null) (note.parent as ViewGroup).removeView(note)
        second.addView(if (!mine) group(note) else group(note, c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(10))
            val f = Book.face(ref)
            addView(c.avatar(if (f.exists()) BitmapFactory.decodeFile(f.path) else null, theirs.ifBlank { "?" }, 36), lp(dp(36), dp(36)).apply { marginEnd = dp(12) })
            addView(c.text(c.getString(R.string.pe_restore_photo), 17f, MT.blue))
            pressable { photo = null; photoCleared = true; drawFace(); drawPhotoRows() }
        }), lp())
    }
    drawPhotoRows()
    body.addView(second, lp().apply { topMargin = c.dp(22) })

    fun keysAway() = c.getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(body.windowToken, 0)
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(PageGround.keyOf(ref)), FrameLayout.LayoutParams(MATCH, MATCH))   // the ground they sent, mine where they sent none (iOS MTFacePage 377-406)
        addView(ScrollView(c).apply { isVerticalScrollBarEnabled = false; addView(body) }, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(c.text(c.getString(R.string.pe_edit), 17f, Color.WHITE, bold = true, center = true),
            FrameLayout.LayoutParams(WRAP, dp(44), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(6) })
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            addView(c.icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { keysAway(); onClose() }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply { setMargins(dp(14), dp(6), 0, 0) })
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.pe_done)
            addView(c.icon(R.drawable.ic_check, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            pressable {
                keysAway()
                Book.saveCard(ref, first.text.toString(), last.text.toString(), note.text.toString(), photo, photoCleared)
                onClose()
            }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(6), dp(14), 0) })
        // the marks stay inside the system bars, and the keys push the page up rather than over it (as the chat's page does)
        setOnApplyWindowInsetsListener { v, insets ->
            val b = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.ime())
            v.setPadding(b.left, b.top, b.right, b.bottom); insets
        }
    }
}
