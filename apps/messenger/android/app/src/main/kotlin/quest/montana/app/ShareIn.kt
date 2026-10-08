package quest.montana.app

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast

// ─────────────────────────── «Share → Montana» from another app (iOS MontanaShare: the share extension) ───────────────────────────

/** What another app handed in (the system's «Share»): its words and its files. */
class Shared(val words: String, val files: List<Uri>)

/** The system's share (ACTION_SEND / ACTION_SEND_MULTIPLE) read into words and files; null for any other intent. */
fun sharedOf(i: Intent?): Shared? {
    if (i == null || (i.action != Intent.ACTION_SEND && i.action != Intent.ACTION_SEND_MULTIPLE)) return null
    val words = listOfNotNull(i.getStringExtra(Intent.EXTRA_SUBJECT)?.takeIf { it.isNotBlank() && i.getStringExtra(Intent.EXTRA_TEXT)?.contains(it) != true },
        i.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()).joinToString("\n").trim()
    @Suppress("DEPRECATION")
    val files: List<Uri> = if (i.action == Intent.ACTION_SEND_MULTIPLE) {
        (if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) else i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()
    } else listOfNotNull(if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java) else i.getParcelableExtra(Intent.EXTRA_STREAM))
    return if (words.isEmpty() && files.isEmpty()) null else Shared(words, files)
}

/** Words of mine as a plain letter to a chat (the one road of a typed letter: the row now, the post after). */
fun sendWords(target: String, words: String) {
    if (Groups.isKey(target)) { Groups.send(target, words, null, null); return }   // a group's letter rides the group's carrier (iOS MTGroup.send)
    val mid = Marks.mintMid()
    Book.edit(target) { it.msgs.add(Msg(mid, words, true, Marks.birthMs(mid) ?: System.currentTimeMillis())) }
    Post.send(target, mid, words)
}

/**
 * THE SHARE SHEET (iOS ShareViewController): the chats, pinned first — a tap chooses one or more; the field over the button
 * holds the words (what the other app handed in stands there already, and it becomes the pictures' caption); «Send» sends to
 * every chosen chat and, when one was chosen, opens it.
 */
fun sharePage(act: MainActivity, s: Shared, onClose: () -> Unit): View {
    val c: Context = act
    val chosen = linkedSetOf<String>()
    lateinit var send: GoldButton
    val field = EditText(c).apply {
        setText(s.words)   // USER-DATA: what the other app handed in
        hint = c.getString(R.string.message_hint)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = c.rounded(MT.plate, 12)
        setPadding(c.dp(14), c.dp(10), c.dp(14), c.dp(10))
        maxLines = 5
    }
    val rows = c.vstack(Gravity.NO_GRAVITY)
    fun fill() {
        rows.removeAllViews()
        for (ch in listedChats().filter { !Groups.isKey(it.ref) || Groups.canWrite(it.ref) }) {   // a group this phone writes into takes it by its carrier (Groups.send, carryMedia)
            val on = ch.ref in chosen
            rows.addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), dp(8), dp(4), dp(8))
                addView(c.peerFace(ch.ref, ch.shown, 46), lp(dp(46), dp(46)).apply { marginEnd = dp(12) })
                addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
                addView(FrameLayout(c).apply {
                    background = if (on) c.rounded(MT.gold, 12) else c.rounded(Color.TRANSPARENT, 12, MT.gray)
                    if (on) addView(c.icon(R.drawable.ic_check, Color.BLACK, 16), FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER))
                }, lp(dp(24), dp(24)))
                pressable { if (!chosen.remove(ch.ref)) chosen.add(ch.ref); fill(); send.setOn(chosen.isNotEmpty()) }
            }, lp())
            rows.addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = c.dp(62) })
        }
        if (rows.childCount == 0) rows.addView(c.text(c.getString(R.string.no_chats), 17f, MT.gray, center = true).apply { setPadding(0, c.dp(40), 0, 0) }, lp())
    }
    send = GoldButton(c, c.getString(R.string.send)) {
        val to = chosen.toList()
        val words = field.text.toString().trim()
        act.getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(field.windowToken, 0)
        Thread {
            var failed = false
            // the files first, each read once and sent to every chosen chat; the words ride the first picture as its caption
            val picked = s.files.mapNotNull { u ->
                val mime = c.contentResolver.getType(u) ?: ""
                Media.read(c, u, asDoc = !(mime.startsWith("image/") || mime.startsWith("video/"))).also { if (it == null) failed = true }
            }
            val captioned = picked.firstOrNull { it.kind == "img" || it.kind == "vid" }
            // pictures shared together are one group in every chat (iOS MTMediaGroup, the share sheet's own, 20.09)
            val pictures = picked.filter { it.kind == "img" || it.kind == "vid" }
            for (ref in to) {
                val slots = MediaGroup.slots(pictures.size)
                picked.forEach { p ->
                    val at = pictures.indexOfFirst { it === p }
                    Media.send(c, ref, p, if (p === captioned) words else "", group = if (at < 0) null else slots[at])
                }
                if (words.isNotEmpty() && captioned == null) sendWords(ref, words)
            }
            act.onMain { if (failed) Toast.makeText(c, R.string.media_failed, Toast.LENGTH_LONG).show() }
        }.start()
        onClose()
        if (to.size == 1) act.push { close -> conversationPage(act, to[0], close) }
    }.apply { setOn(false) }
    fill()
    return settingsPage(act, c.getString(R.string.share), onClose, cross = true) {
        addView(rows, lp())
        gap(14)
        addView(field, lp())
        gap(10)
        addView(send, lp())
    }
}

/**
 * THE SHARE HANDED IN: opened over the main screen when a person exists; before the identity and the terms nothing can be
 * sent, and the person is told so (the invitation's own word).
 */
fun MainActivity.takeShared(i: Intent?, ready: Boolean): Boolean {
    val s = sharedOf(i) ?: return false
    if (!ready) { Toast.makeText(this, R.string.invite_wait, Toast.LENGTH_LONG).show(); return true }
    // after the first layout: a cold start hands the share in before the window knows the system bars' insets
    window.decorView.post { push { close -> sharePage(this, s, close) } }
    return true
}
