package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

// ─────────────────────────── a letter's own deeds: pin, forward, select (iOS MontanaMessageMenu and its sheets) ───────────────────────────

/** THE WORDS OF A FORWARDED LETTER'S QUOTE ON THE WIRE (iOS Message.forwardedQuote): the same literal both ways, never translated. */
const val FORWARDED_QUOTE = "↪︎ Forwarded message"

/**
 * A FORWARD OF A CHANNEL'S POST NAMES ITS CHANNEL (iOS Message.forwardedFromHead, ContentView 3762-3771 at 2315): the wire quote is
 * this head and the channel's name; a build that does not know the head draws it as the quote it reads. Never translated.
 */
const val FORWARDED_FROM_HEAD = "↪︎ Forwarded from "

/** The channel a forward names, at most 64 letters, or null (iOS Message.forwardedFrom). */
fun forwardedFrom(qt: String?): String? =
    qt?.takeIf { it.startsWith(FORWARDED_FROM_HEAD) }?.removePrefix(FORWARDED_FROM_HEAD)?.take(64)?.ifEmpty { null }

/** Whether a quote marks a forward, the bare one or a channel's -- never drawn as a quote (iOS MontanaBubble.quoted 1815). */
fun isForwardQuote(qt: String?) = qt == FORWARDED_QUOTE || qt?.startsWith(FORWARDED_FROM_HEAD) == true

/** The quote a forward from `from` carries: a channel's post names its channel, any other forward the bare mark (iOS forwardMessage 4385). */
fun forwardQuote(from: String): String {
    val title = if (Groups.isChannel(from)) Book.chat(from)?.shown?.trim().orEmpty() else ""
    return if (title.isEmpty()) FORWARDED_QUOTE else FORWARDED_FROM_HEAD + title.take(64)
}

/** THE PIN'S WORD ON THE WIRE (iOS pinMark): silent, + {sid, txt, op}. */
const val PIN_MARK = "\u200B\u200BPN:"

/**
 * THE PINNED LETTERS OF EACH CHAT (iOS ChatStore pin / unpin / isPinned, the vault's «pinnedMessages»): the letters' mids,
 * the newest pin last. Kept sealed in the device vault.
 */
object MsgPins {
    private const val KEY = "msgPins"
    private val lock = Any()
    private var map: MutableMap<String, MutableList<String>>? = null
    private val listeners = mutableListOf<() -> Unit>()

    fun listen(l: () -> Unit) { synchronized(listeners) { listeners.add(l) } }
    /** The person forgotten: the pins of every chat leave with them (Book.wipe). */
    fun wipe() = synchronized(lock) { map = null; DeviceVault.delete(KEY) }
    fun unlisten(l: () -> Unit) { synchronized(listeners) { listeners.remove(l) } }

    private fun ensure(): MutableMap<String, MutableList<String>> = map ?: mutableMapOf<String, MutableList<String>>().also { m ->
        DeviceVault.get(KEY)?.toString(Charsets.UTF_8)?.let { runCatching { JSONObject(it) }.getOrNull() }?.let { o ->
            o.keys().forEach { k -> val a = o.getJSONArray(k); m[k] = MutableList(a.length()) { a.getString(it) } }
        }
        map = m
    }
    private fun change(work: (MutableMap<String, MutableList<String>>) -> Unit) {
        synchronized(lock) {
            val m = ensure(); work(m)
            DeviceVault.set(KEY, JSONObject().apply { m.forEach { (k, v) -> if (v.isNotEmpty()) put(k, JSONArray(v)) } }.toString().toByteArray(Charsets.UTF_8))
        }
        synchronized(listeners) { listeners.toList() }.forEach { it() }
    }

    fun of(ref: String): List<String> = synchronized(lock) { ensure()[ref]?.toList() ?: emptyList() }
    fun isPinned(ref: String, mid: String) = mid in of(ref)
    fun pin(ref: String, mid: String) = change { m -> m.getOrPut(ref) { mutableListOf() }.apply { remove(mid); add(mid) } }
    fun unpin(ref: String, mid: String) = change { m -> m[ref]?.remove(mid) }
    /** The conversation gone: its pins go with it (iOS forgetConversation, f33985eb's sibling f5889c70). */
    fun forget(ref: String) { if (of(ref).isNotEmpty()) change { m -> m.remove(ref) } }
    /** Every chat's pins, for a copy (iOS ChatStore.savePinned 3232-3236: «pinnedMessages», one map of chat to letters). */
    fun carried(): Map<String, List<String>> = synchronized(lock) { ensure().filterValues { it.isNotEmpty() }.mapValues { it.value.toList() } }
    /** A copy laid (iOS SeedScope.unionKeys 6305): a chat with pins here keeps its own, a chat without takes the copy's. */
    fun lay(m: Map<String, List<String>>) = change { have -> for ((r, l) in m) if (have[r].isNullOrEmpty() && l.isNotEmpty()) have[r] = l.toMutableList() }

    /** The newest pinned letter that still stands in the chat. */
    fun newest(ref: String): Msg? {
        val chat = Book.chat(ref) ?: return null
        return of(ref).asReversed().firstNotNullOfOrNull { mid -> chat.msgs.find { it.mid == mid } }
    }
}

/**
 * THE PIN TRAVELS (iOS tellPin: «both see it»): the letter's wire name and its words, «pin» or «unpin», silent on the one
 * delivery road.
 */
fun tellPin(ref: String, m: Msg, pin: Boolean) {
    // A GROUP'S PIN RIDES THE GROUP'S OWN ROAD (iOS tellPin, MTGroup.pin): its key is no pipe -- an unpin went to Post.send under
    // the group's key and rode nowhere (the checklist's E.5); a phone without the right unpins for itself alone.
    if (Groups.isKey(ref)) { if (Groups.mayPin(ref)) Groups.pin(ref, m, pin, notify = true); return }
    Post.send(ref, Marks.mintMid(), PIN_MARK + JSONObject().put("sid", "mid:" + m.mid).put("txt", m.text.take(200)).put("op", if (pin) "pin" else "unpin"))
}

/** A pin or an unpin of theirs (iOS applyPinFromControl): the letter is found by its wire name, else by its words; a fresh
 * pin tells the person by the app's own banner, unless this chat stands open (iOS presentPinned). */
fun applyPin(ref: String, body: String) {
    val o = runCatching { JSONObject(body) }.getOrNull() ?: return
    val op = o.optString("op"); val sid = o.optString("sid").removePrefix("mid:"); val txt = o.optString("txt")
    val chat = Book.chat(ref) ?: return
    val m = chat.msgs.find { sid.isNotEmpty() && it.mid == sid } ?: chat.msgs.lastOrNull { txt.isNotEmpty() && it.text.take(200) == txt } ?: return
    if (op == "pin") { MsgPins.pin(ref, m.mid); Notify.pinned(ref, m.mid, m) } else if (op == "unpin") MsgPins.unpin(ref, m.mid)
}

/** «Pin this message?» ON THE PERSON'S FACE (iOS the FaceSheet over the chat, MontanaConversation.swift:1798-1812 at 2155):
 * for both first, for me under it, no line of its own (note: nil); a group pins for everyone as the reference does (iOS e0bb03bf,
 * the checklist's B.11): «Pin and notify all members» or «Only Pin», and a phone without the right pins for itself; an unpin
 * asks nothing and is told. */
fun pinOrUnpin(act: MainActivity, ref: String, m: Msg) {
    if (MsgPins.isPinned(ref, m.mid)) { MsgPins.unpin(ref, m.mid); tellPin(ref, m, false); return }
    val forMe = FaceDeed(act.getString(R.string.ld_pin_me), false) { MsgPins.pin(ref, m.mid) }
    val groupPin = Groups.isKey(ref) && Groups.mayPin(ref)
    faceSheet(act, ref, act.getString(if (groupPin) R.string.ld_pin_q_group else R.string.ld_pin_q), null,
        if (groupPin) listOf(
            FaceDeed(act.getString(R.string.ld_pin_all), false) { Groups.pin(ref, m, pin = true, notify = true) },
            FaceDeed(act.getString(R.string.ld_pin_only), false) { Groups.pin(ref, m, pin = true, notify = false) })
        else if (Groups.isKey(ref)) listOf(forMe)
        else listOf(FaceDeed(act.getString(R.string.ld_pin_both), false) { MsgPins.pin(ref, m.mid); tellPin(ref, m, true) }, forMe))
}

/**
 * THE PINNED PLATE under the chat's header (iOS the pinned bar): the gold pin, «Pinned message» and the words of the newest pin;
 * a tap carries the eye to the letter, the cross unpins it (and tells, as the menu's «Unpin»).
 */
fun pinnedPlate(act: MainActivity, ref: String, onJump: (String) -> Unit): View {
    val c: Context = act
    val words = c.text("", 14f, Color.WHITE).apply { singleLineEllipsis() }
    lateinit var plate: View
    fun draw() {
        val m = MsgPins.newest(ref)
        plate.visibility = if (m == null) View.GONE else View.VISIBLE
        if (m != null) { words.text = letterWords(c, m); plate.tag = m.mid }   // USER-DATA: the pinned letter
    }
    plate = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        background = c.glassPlate()
        setPadding(dp(12), dp(6), dp(4), dp(6))
        addView(c.icon(R.drawable.ic_pin, Color.WHITE, 16), lp(dp(16), dp(16)).apply { marginEnd = dp(10) })
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.text(c.getString(R.string.ld_pinned), 12f, MT.gray))   // iOS «Pinned message»: caption2, secondary (MontanaConversation 2528)
            addView(words)
        }, lp(0, WRAP, 1f))
        addView(c.icon(R.drawable.ic_close, MT.gray, 18).apply {
            setPadding(dp(9), dp(9), dp(9), dp(9))
            pressable { MsgPins.newest(ref)?.let { m -> MsgPins.unpin(ref, m.mid); tellPin(ref, m, false) } }
        }, lp(dp(36), dp(36)))
        pressable { (tag as? String)?.let(onJump) }
    }
    draw()
    val again: () -> Unit = { act.onMain { draw() } }
    plate.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { MsgPins.listen(again); Book.listen(again); draw() }
        override fun onViewDetachedFromWindow(v: View) { MsgPins.unlisten(again); Book.unlisten(again) }
    })
    return plate
}

/** Whether a letter can be forwarded: words of a person, or a file that is here on this phone. */
fun canForward(m: Msg): Boolean =
    if (m.text.startsWith(Marks.MEDIA)) m.file?.let { File(it).exists() } == true else !Marks.isService(m.text)

/**
 * ONE LETTER FORWARDED (iOS forward(_:to:)): words leave as a new letter of mine with the forwarded quote; a picture, a film,
 * a voice or a file leaves as a fresh copy of the local file — new pieces on the node, never the old keys.
 */
fun forwardOne(c: Context, target: String, m: Msg, qt: String = FORWARDED_QUOTE) {
    if (m.text.startsWith(Marks.MEDIA)) {
        val f = m.file?.let { File(it) }?.takeIf { it.exists() } ?: return
        val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text) ?: JSONObject()
        val wave = man.optString("wv").takeIf { it.isNotEmpty() }?.let { w ->
            runCatching { Base64.decode(w, Base64.NO_WRAP) }.getOrNull()?.let { b -> FloatArray(b.size) { (b[it].toInt() and 0xFF) / 255f } }
        }
        val p = Media.Picked(f.readBytes(), man.optString("k").ifEmpty { "doc" }, man.optString("e").ifEmpty { f.extension },
            man.optString("n").ifEmpty { null }, man.optDouble("du").takeIf { !it.isNaN() }, wave, man.optBoolean("r"))
        Media.send(c, target, p, man.optString("cap"), qt = qt)
        return
    }
    if (Marks.isService(m.text)) return
    // into a group the words ride the group's carrier with the forwarded quote (iOS forward → ChatStore.send → MTGroup.send)
    if (Groups.isKey(target)) { Groups.send(target, m.text, qt, null); return }
    val mid = Marks.mintMid()
    // THE LINK'S CARD RIDES WITH THE FORWARDED WORDS (iOS forward → store.send(linkCard: m.linkPreview), ba4026d9f232): the card
    // the letter already wears is the forward's own, never fetched again and never lost on the way
    Book.edit(target) { it.msgs.add(Msg(mid, m.text, true, Marks.birthMs(mid) ?: System.currentTimeMillis(), qt = qt, lp = m.lp)) }
    Post.send(target, mid, m.text, qt, lp = m.lp)
}

/**
 * «FORWARD TO…» (iOS ForwardPickerView): the chats of the list, the pinned first; a tap sends the letters there in their own
 * order and opens that chat.
 */
fun forwardPage(act: MainActivity, from: String, letters: List<Msg>, onBack: () -> Unit, onSent: (String) -> Unit): View {
    val c: Context = act
    return settingsPage(act, c.getString(R.string.ld_forward_to), onBack) {
        // the list's chats, groups included (iOS ForwardPickerView: store.listChats()) — a group this phone writes into
        for (ch in (listedChats().filter { it.ref != from } + listOfNotNull(Book.chat(from))).filter { !Groups.isKey(it.ref) || Groups.canWrite(it.ref) }) {
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), dp(8), dp(4), dp(8))
                addView(c.peerFace(ch.ref, ch.shown, 46), lp(dp(46), dp(46)).apply { marginEnd = dp(12) })
                addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                pressable {
                    val to = ch.ref
                    val qt = forwardQuote(from)
                    Thread { letters.sortedBy { it.at }.forEach { forwardOne(c, to, it, qt) } }.start()
                    onSent(to)
                }
            }, lp())
            addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(62) })
        }
    }
}

/**
 * THE CHAT'S SELECTION HEAD (iOS selectionTopBar, MontanaConversation.swift:4433-4453 at 2240): «Delete chat» on the left where the
 * road allows it, «Selected: N» in the middle, the cross on the right.
 */
fun letterSelectionHead(act: MainActivity, count: Int, canDeleteChat: Boolean, onDeleteChat: () -> Unit, onClose: () -> Unit): View {
    val c: Context = act
    return FrameLayout(c).apply {
        background = c.glassPlate()   // the bar's own glass (iOS .ultraThinMaterial)
        setPadding(dp(16), dp(4), dp(4), dp(4))
        if (canDeleteChat) addView(c.text(c.getString(R.string.delete_chat), 15f, SysColor.red, bold = true).apply {
            setPadding(0, dp(10), dp(10), dp(10))
            pressable(onDeleteChat)
        }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.START or Gravity.CENTER_VERTICAL))
        addView(c.text(c.getString(R.string.cl_selected, count), 15f, Color.WHITE), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        addView(FrameLayout(c).apply {
            contentDescription = c.getString(R.string.cancel)
            addView(c.icon(R.drawable.ic_close, Color.WHITE, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable(onClose)
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.END or Gravity.CENTER_VERTICAL))
    }
}

/**
 * THE CHAT'S SELECTION FOOT (iOS selectionBar, MontanaConversation.swift:4454-4463 at 2240): Delete, Share, Forward for the chosen
 * letters; dim and deaf while nothing is chosen.
 */
fun letterSelectionFoot(act: MainActivity, count: Int, onDelete: () -> Unit, onShare: () -> Unit, onForward: () -> Unit): View {
    val c: Context = act
    val any = count > 0
    fun pill(words: String, red: Boolean = false, work: () -> Unit) = c.text(words, 15f, if (red) SysColor.red else Color.WHITE, bold = true, center = true).apply {
        background = c.glassPlate()
        setPadding(dp(10), dp(10), dp(10), dp(10))
        alpha = if (any) 1f else 0.5f
        if (any) pressable(work)
    }
    return c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(10))
        addView(pill(c.getString(R.string.delete), red = true, work = onDelete), lp(0, WRAP, 1f))
        gap(8)
        addView(pill(c.getString(R.string.share), work = onShare), lp(0, WRAP, 1f))
        gap(8)
        addView(pill(c.getString(R.string.ld_forward), work = onForward), lp(0, WRAP, 1f))
    }
}

/**
 * THE CHOSEN LETTERS SHARED (iOS shareSelected): the words of each and every finished file that stands on this phone, through the
 * platform's one share. False when there is nothing to give.
 */
fun shareLetters(act: MainActivity, letters: List<Msg>): Boolean {
    val words = letters.filter { !it.text.startsWith(Marks.MEDIA) && !Marks.isService(it.text) && it.text.isNotBlank() }.map { it.text }
    val files = ArrayList(letters.mapNotNull { m -> m.file?.let { File(it) }?.takeIf { it.exists() }?.let { Media.uri(act, it) } })
    if (words.isEmpty() && files.isEmpty()) return false
    val send = if (files.size > 1) android.content.Intent(android.content.Intent.ACTION_SEND_MULTIPLE).setType("*/*").putParcelableArrayListExtra(android.content.Intent.EXTRA_STREAM, files)
        else android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            if (files.isEmpty()) setType("text/plain")
            else { setType(act.contentResolver.getType(files[0]) ?: "*/*"); putExtra(android.content.Intent.EXTRA_STREAM, files[0]) }
        }
    if (words.isNotEmpty()) send.putExtra(android.content.Intent.EXTRA_TEXT, words.joinToString("\n\n"))
    send.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
    return runCatching { act.startActivity(android.content.Intent.createChooser(send, null)) }.isSuccess
}
