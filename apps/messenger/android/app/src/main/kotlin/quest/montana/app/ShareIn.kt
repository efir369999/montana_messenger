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
    // A FILE'S PATH IS NEVER ITS WORDS (iOS ShareRead.text, ShareViewController.swift:712, atom 20c5cef6f490): an app that hands a file's
    // own address as its text sent «file:///...» as a letter -- the file rides the stream, the address is no word of the person's
    val words = listOfNotNull(i.getStringExtra(Intent.EXTRA_SUBJECT)?.takeIf { it.isNotBlank() && i.getStringExtra(Intent.EXTRA_TEXT)?.contains(it) != true },
        i.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.takeIf { t -> !t.trim().let { it.startsWith("file://", ignoreCase = true) && it.none { ch -> ch.isWhitespace() } } })
        .joinToString("\n").trim()
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
 * THE SHARE SHEET (iOS ShareViewController and SharePickerController at 2155, atom 8bf2e50c1cdb; the author's word 30.09): the platform's
 * own sheet -- the cross and «Send to Montana», the search on its glass plate (44 high, corner 22, 16 from the edges; buildUI 174-191,
 * 250-257) and the grid of round faces, four to five columns of the sheet's width (sizeForItemAt 797-806): each face 60 with the thin
 * white rim and its name in two lines of 11 under it (ShareAvatarCell 819-877). ONE'S OWN WALL IS THE FIRST CIRCLE (ShareChat.wall, the
 * author's words 29.09 and 02.10 19:17): my own face, as the Saved Messages row wears it, with the platform's write glyph where a tick
 * would stand; written on, never sent to. ONLY THE FINGER CHOOSES AND ONLY THE FINGER SENDS: a chosen face shrinks into the platform's
 * blue ring and wears the blue tick (configure 898-902), and once a chat is chosen the bar floats over the grid (updateSendState
 * 360-364) -- the caption on its own glass and, beside it, the round send of the label's colour with the arrow glyph and no word
 * (ShareGlass.prominent 105-115, the bar 213-232 and 268-285). The send goes to every chosen chat and, when one was chosen, opens it.
 */
fun sharePage(act: MainActivity, s: Shared, onClose: () -> Unit): View {
    val c: Context = act
    val chosen = linkedSetOf<String>()
    val chats = listedChats().filter { !Groups.isKey(it.ref) || Groups.canWrite(it.ref) }   // a group this phone writes into takes it by its carrier (Groups.send, carryMedia)
    var query = ""
    val field = EditText(c).apply {
        setText(s.words)   // USER-DATA: what the other app handed in
        hint = c.getString(R.string.share_caption)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        textSize = 17f
        setPadding(c.dp(14), c.dp(12), c.dp(14), c.dp(12))
        minHeight = c.dp(44)
        maxHeight = c.dp(120)   // iOS textViewDidChange 353-358: 44 to 120 high, the words past it scroll inside the field
    }
    fun hideKeys() { act.getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(field.windowToken, 0) }
    // THE SEND'S OWN ROAD IN THE SHEET (iOS ShareViewController road, status and progress 150-151, 237-240, showStage 390-409 and
    // beginSend 415-426 at 2155; atom 8bf2e50c1cdb): the round send gives way to the words and the platform's bar while the pick is
    // shaped and handed over -- the item's number on a batch, the stage, the whole per cents -- and the faces take no finger meanwhile
    val roadWords = c.text("", 15f, Color.WHITE)
    val roadBar = android.widget.ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
        max = 100; progressTintList = android.content.res.ColorStateList.valueOf(MT.blue)   // the platform's own blue (iOS 238)
    }
    val road = c.vstack(Gravity.NO_GRAVITY) {
        background = c.glassPlate().apply { cornerRadius = c.dp(22).toFloat() }
        setPadding(dp(16), dp(14), dp(16), dp(14))
        visibility = View.GONE
        isClickable = true   // a finger on the road reaches nothing under it
        addView(roadWords, lp())
        addView(roadBar, lp().apply { topMargin = dp(10) })
    }
    val shield = View(c).apply { isClickable = true; visibility = View.GONE }   // the faces and the search take no finger while it goes
    lateinit var barView: View   // the round send's bar, built below: the road takes its place
    fun stage(word: Int, i: Int, n: Int, f: Double) = act.onMain {
        val pct = (f.coerceIn(0.0, 1.0) * 100).toInt()
        roadBar.progress = pct
        roadWords.text = (if (1 < n) "$i/$n  " else "") + c.getString(word) + "  " + pct + "%"
    }
    // THE ONE BIRTH OF A SEND (iOS beginSend): the finger on the round send, to the chats the finger chose
    fun send() {
        val to = chosen.toList()
        if (to.isEmpty()) return
        val words = field.text.toString().trim()
        hideKeys()
        barView.visibility = View.GONE; road.visibility = View.VISIBLE; shield.visibility = View.VISIBLE
        roadWords.text = c.getString(R.string.share_sending)
        Thread {
            var failed = false
            // a text handed as a file is a text letter (textFace); the files first, each read once and sent to every chosen chat;
            // the words ride the first picture as its caption
            val texts = ArrayList<String>()
            val picked = s.files.withIndex().mapNotNull { (i, u) ->
                stage(R.string.share_preparing, i + 1, s.files.size, i.toDouble() / maxOf(1, s.files.size))
                textFace(c, u)?.let { texts.add(it); return@mapNotNull null }
                val mime = c.contentResolver.getType(u) ?: ""
                Media.read(c, u, asDoc = !(mime.startsWith("image/") || mime.startsWith("video/"))).also { if (it == null) failed = true }
            }
            val captioned = picked.firstOrNull { it.kind == "img" || it.kind == "vid" }
            // pictures shared together are one group in every chat (iOS MTMediaGroup, the share sheet's own, 20.09)
            val pictures = picked.filter { it.kind == "img" || it.kind == "vid" }
            for ((n, ref) in to.withIndex()) {
                stage(R.string.share_sending, n + 1, to.size, n.toDouble() / to.size)
                val slots = MediaGroup.slots(pictures.size)
                picked.forEach { p ->
                    val at = pictures.indexOfFirst { it === p }
                    Media.send(c, ref, p, if (p === captioned) words else "", group = if (at < 0) null else slots[at])
                }
                if (words.isNotEmpty() && captioned == null) sendWords(ref, words)
                texts.forEach { sendWords(ref, it) }
            }
            stage(R.string.share_sending, to.size, to.size, 1.0)
            // A PICK THAT DID NOT ALL GO IS SAID IN THE SHEET, THEN THE SHEET GOES (iOS 556-562): Montana sends the rest itself
            if (failed) { act.onMain { roadWords.text = c.getString(R.string.share_still_on_way) }; Thread.sleep(1800) }
            act.onMain {
                onClose()
                if (to.size == 1) act.push { close -> conversationPage(act, to[0], close) }
            }
        }.start()
    }
    // THE WALL IS WRITTEN ON, NEVER SENT TO (iOS didSelectItemAt 310-311): its circle chooses nothing and opens the wall's one new-post
    // page with all that was handed in already taken (iOS MTBoard.takeFromSheet and laySheet, MontanaBoard 1934-1991, then
    // MTBoardComposer.reopen, MontanaBoardViews 2050-2058); only its check posts
    fun openWall() {
        val typed = field.text.toString().trim()
        hideKeys()
        onClose()
        // A TEXT HANDED AS A FILE IS THE POST'S WORDS (iOS ShareRead.wallPart and ShareWallHandoff.hand, ShareViewController 722-740, 779 at 2155;
        // atom 2183eafbeab2): a .txt of bubble size joins the words line by line, only the rest are the post's files
        Thread {
            val texts = ArrayList<String>()
            val files = s.files.filter { u -> textFace(c, u)?.let { texts.add(it); false } ?: true }
            val words = (listOf(typed) + texts).filter { it.isNotEmpty() }.joinToString("\n")
            android.util.Log.d("Montana", "wall_sheet files=" + files.size + " texts=" + texts.size + " chars=" + words.length + " page")
            act.onMain { act.push { close -> newPostPage(act, close, sharedWords = words, sharedFiles = files) } }
        }.start()
    }
    val bar = c.hstack {
        gravity = Gravity.BOTTOM
        visibility = View.GONE
        addView(FrameLayout(c).apply {
            background = c.glassPlate().apply { cornerRadius = c.dp(22).toFloat() }
            addView(field, FrameLayout.LayoutParams(MATCH, WRAP))
        }, lp(0, WRAP, 1f))
        gap(8)
        addView(FrameLayout(c).apply {
            background = android.graphics.drawable.GradientDrawable().apply { shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(Color.WHITE) }
            contentDescription = c.getString(R.string.send)
            addView(c.icon(R.drawable.ic_arrow_up, Color.BLACK, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { send() }
        }, lp(dp(44), dp(44)))
    }
    barView = bar
    val wDp = c.resources.displayMetrics.widthPixels / c.resources.displayMetrics.density
    val cols = maxOf(4, ((wDp - 24) / 84).toInt())   // iOS sizeForItemAt 799: four columns at the least, one more for every 84 of the width
    val grid = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(12), dp(4), dp(12), dp(12)) }   // iOS insetForSectionAt 805
    val empty = c.text(c.getString(R.string.no_chats), 15f, MT.gray, center = true).apply { setPadding(c.dp(32), c.dp(150), c.dp(32), 0); visibility = View.GONE }
    // ONE ROUND FACE OF THE GRID (iOS ShareAvatarCell 811-903): the face 60 under the thin white rim; chosen, it shrinks to 0.867 in the
    // platform's blue ring with the blue tick at its corner; the wall's circle wears the write glyph there; the name under it, two lines of 11
    fun cell(face: View, title: String, on: Boolean, wall: Boolean, tap: () -> Unit): View = c.vstack(Gravity.CENTER_HORIZONTAL) {
        setPadding(0, dp(4), 0, dp(4))
        addView(FrameLayout(c).apply {
            addView(FrameLayout(c).apply {
                addView(face, FrameLayout.LayoutParams(MATCH, MATCH))
                addView(View(c).apply {
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        if (on) setStroke(c.dp(2), MT.blue) else setStroke(c.dp(1), Color.argb(115, 255, 255, 255))
                    }
                }, FrameLayout.LayoutParams(MATCH, MATCH))
                if (on) { scaleX = 0.867f; scaleY = 0.867f }
            }, FrameLayout.LayoutParams(dp(60), dp(60)))
            if (on || wall) addView(FrameLayout(c).apply {
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(MT.blue)
                    if (on) setStroke(c.dp(1), Color.WHITE)
                }
                addView(c.icon(if (wall) R.drawable.ic_compose else R.drawable.ic_check, Color.WHITE, 12), FrameLayout.LayoutParams(dp(12), dp(12), Gravity.CENTER))
            }, FrameLayout.LayoutParams(dp(22), dp(22), Gravity.BOTTOM or Gravity.END))
        }, lp(dp(62), dp(62)))
        addView(c.text(title, 11f, Color.WHITE, center = true).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END },
            lp(MATCH, WRAP).apply { topMargin = dp(4); marginStart = dp(2); marginEnd = dp(2) })
        pressable(tap)
    }
    fun fill() {
        grid.removeAllViews()
        val q = query.trim().lowercase()
        val cells = ArrayList<View>()
        val mine = c.getString(R.string.wall_mine)
        if (q.isEmpty() || mine.lowercase().contains(q)) cells.add(cell(c.avatar(SelfFace.load(c), Prefs.userName, 60), mine, on = false, wall = true) { openWall() })
        for (ch in chats) {
            val title = ch.shown.ifBlank { c.getString(R.string.peer) }   // USER-DATA: the name
            // iOS searchChanged 345-349: the word typed narrows the faces by their names
            if (q.isNotEmpty() && !title.lowercase().contains(q) && !ch.ref.lowercase().contains(q)) continue
            cells.add(cell(c.peerFace(ch.ref, ch.shown, 60), title, ch.ref in chosen, wall = false) {
                if (!chosen.remove(ch.ref)) chosen.add(ch.ref)
                fill()
            })
        }
        for (k in cells.indices step cols) grid.addView(c.hstack {
            gravity = Gravity.TOP
            for (j in 0 until cols) addView(cells.getOrNull(k + j) ?: View(c), lp(0, WRAP, 1f))
        }, lp().apply { if (0 < k) topMargin = c.dp(4) })   // iOS minimumLineSpacing 195
        empty.visibility = if (chats.isEmpty()) View.VISIBLE else View.GONE
        // THE BAR STANDS ONCE THE FINGER CHOSE A CHAT, the grid keeping room under its last row for it (iOS updateSendState 360-364)
        bar.visibility = if (chosen.isEmpty()) View.GONE else View.VISIBLE
        grid.setPadding(grid.paddingLeft, grid.paddingTop, grid.paddingRight, c.dp(if (chosen.isEmpty()) 12 else 84))
    }
    val search = EditText(c).apply {
        hint = c.getString(R.string.search)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = null
        textSize = 17f
        setSingleLine(true)
        gravity = Gravity.CENTER_VERTICAL
        imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
        setPadding(c.dp(38), 0, c.dp(8), 0)   // iOS the magnifier's room, 38, and 8 at the end (187-188, 257)
        addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(t: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(t: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(t: android.text.Editable?) { query = t?.toString() ?: ""; fill() }
        })
    }
    val searchPlate = FrameLayout(c).apply {
        background = c.glassPlate().apply { cornerRadius = c.dp(22).toFloat() }
        addView(c.icon(R.drawable.ic_search, MT.gray, 20), FrameLayout.LayoutParams(c.dp(20), c.dp(20), Gravity.CENTER_VERTICAL or Gravity.START).apply { marginStart = c.dp(12) })
        addView(search, FrameLayout.LayoutParams(MATCH, MATCH))
    }
    fill()
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // the pages' one ground under the sheet's glass
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(FrameLayout(c).apply {
                setPadding(dp(8), 0, dp(8), 0)
                addView(c.icon(R.drawable.ic_close, Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable { hideKeys(); onClose() } },
                    FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
                addView(c.text(c.getString(R.string.share_to_montana), 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            }, lp(MATCH, dp(52)))
            addView(searchPlate, lp(MATCH, dp(44)).apply { setMargins(dp(16), dp(8), dp(16), dp(8)) })
            addView(FrameLayout(c).apply {
                addView(android.widget.ScrollView(c).apply { isVerticalScrollBarEnabled = false; addView(grid) }, FrameLayout.LayoutParams(MATCH, MATCH))
                addView(empty, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP))
            }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(shield, FrameLayout.LayoutParams(MATCH, MATCH))
        addView(bar, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { setMargins(dp(12), 0, dp(12), dp(10)) })
        addView(road, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.BOTTOM).apply { setMargins(dp(12), 0, dp(12), dp(10)) })
    }
}

/**
 * A TEXT IS A TEXT, WHATEVER FACE IT WEARS (iOS loadTextFace, ShareViewController 473-477 and 574-592; the author's word 13.09: a
 * shared link must always arrive as a link). Some apps hand a link or a note as a .txt file — it rode the document road and arrived
 * as «text.txt», unreadable in the bubble. Text of bubble size is a text letter from any app; only bigger text is a file.
 */
private fun textFace(c: Context, u: Uri): String? {
    val cr = c.contentResolver
    val name = runCatching { cr.query(u, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } }
        .getOrNull() ?: u.lastPathSegment ?: ""
    val ext = name.substringAfterLast('.', "").lowercase()
    if (cr.getType(u) != "text/plain" && ext != "txt" && ext != "text") return null
    val bytes = runCatching {
        cr.openInputStream(u)?.use { s ->
            val out = java.io.ByteArrayOutputStream(); val buf = ByteArray(8192)
            while (out.size() <= TEXT_FILE_MAX) { val n = s.read(buf); if (n < 0) break; out.write(buf, 0, n) }
            out.toByteArray()
        }
    }.getOrNull() ?: return null
    if (bytes.size > TEXT_FILE_MAX) return null
    val text = runCatching { Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString() }.getOrNull()?.trim() ?: return null
    return text.takeIf { it.isNotEmpty() && it.codePointCount(0, it.length) <= TEXT_LETTER_MAX }
}
private const val TEXT_FILE_MAX = 64_000   // iOS: a .txt read whole only up to 64 000 bytes
private const val TEXT_LETTER_MAX = 4_500   // iOS: the bubble's size of a text letter

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
