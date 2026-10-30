package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.content.res.ColorStateList
import android.text.format.Formatter
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.ScrollView

/**
 * MY PAGE (iOS MontanaMyProfileView, opened from the drawer as MTMyPageFromDrawer): my profile as the people I write to see it — the
 * one face owner (FaceHead) at its circle, my name as it leaves this phone, my words and my link as they leave it, over my page's
 * ground. The back mark top left; «Edit» top right opens the profile's editor over the page, and its checkmark comes back to the page
 * drawn anew. My own wall stands under the head when the wall comes (iOS MTBoardPane(owner: nil)).
 */
fun myPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(0, dp(56), 0, dp(40)) }
    val face = FaceHead(act, body)
    fun draw() = face.draw(SelfFace.load(act), Prefs.userName, false, MyAbout.bio(), PeerAbout.url(MyAbout.link()), "")
    draw()
    body.addView(face.view, lp())
    // MY OWN WALL UNDER THE HEAD (iOS MTBoardPane(owner: nil)): the row that writes a post, then my posts, the pinned first
    val wall = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(12), dp(16), dp(12), 0) }
    fun drawWall() {
        wall.removeAllViews()
        wall.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            background = c.glassPlate()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            addView(FrameLayout(c).apply {
                background = c.glassPlate(oval = true)
                addView(c.icon(R.drawable.ic_compose, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            }, lp(dp(44), dp(44)).apply { marginEnd = dp(14) })
            addView(c.text(c.getString(R.string.pi_write_wall), 17f))
            pressable { act.push { close -> newPostPage(act, close) } }
        }, lp())
        // A POST ON ITS WAY stands at once as it will be published, under the bar of its files (iOS MTBoardRows 167-172)
        val going = MyWall.sending()
        going.forEach { o -> wall.addView(goingCell(act, o), lp().apply { topMargin = c.dp(10) }) }
        val ps = MyWall.posts()
        if (ps.isEmpty() && going.isEmpty()) wall.addView(c.text(c.getString(R.string.pi_wall_empty), 15f, MT.gray, center = true).apply { setPadding(0, dp(28), 0, dp(28)) }, lp())
        else ps.forEach { p -> wall.addView(postCell(act, Board.Item("", p), onItsWall = true), lp().apply { topMargin = c.dp(10) }) }
    }
    drawWall()
    body.addView(wall, lp())
    val heard: () -> Unit = { drawWall() }
    wall.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { MyWall.listen(heard); drawWall() }
        override fun onViewDetachedFromWindow(v: View) { MyWall.unlisten(heard) }
    })
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // my page's ground (iOS MTFacePage of .me)
        addView(ScrollView(c).apply { isVerticalScrollBarEnabled = false; addView(body); face.attach(this) }, FrameLayout.LayoutParams(MATCH, MATCH))
        // the back mark on its own round of glass, over the page (iOS MontanaBackMark)
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.back)
            addView(c.icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { onClose() }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply { setMargins(dp(14), dp(6), 0, 0) })
        // THE PAGE'S AUTHOR EDITS IT FROM IT (iOS MontanaEditMark, the author's word 25.09): the editor over the page closes itself,
        // never the page under it
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.pe_edit)
            addView(c.icon(R.drawable.ic_more_horiz, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            pressable { act.push { close -> Profile(act, onboarding = false) { close(); draw() }.view } }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply { setMargins(0, dp(6), dp(14), 0) })
    }
}

/**
 * A POST ON ITS WAY'S BAR (iOS MTBoardProgress 1542-1577): «Publishing» or «Could not post», the share and the bytes the node confirmed,
 * and -- when the node did not take it -- try again and delete; the platform's own line under them.
 */
fun goingBar(act: MainActivity, o: MyWall.Going, onRetry: (() -> Unit)?, onDiscard: (() -> Unit)?): View {
    val c: Context = act
    fun glyph(res: Int, words: Int, deed: () -> Unit) = c.icon(res, Color.WHITE, 20).apply {
        setPadding(dp(12), dp(12), dp(12), dp(12)); contentDescription = c.getString(words); pressable(deed)
    }
    return c.vstack(Gravity.NO_GRAVITY) {
        background = c.glassPlate()
        setPadding(dp(16), dp(12), dp(16), dp(12))
        addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(44)
            addView(c.text(c.getString(if (o.failed) R.string.wall_could_not_post else R.string.wall_publishing), 15f, Color.WHITE, bold = true)
                .apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
            gap(6)
            addView(c.text(c.getString(R.string.wall_share_of, (o.share * 100).toInt(), Formatter.formatShortFileSize(c, o.done),
                Formatter.formatShortFileSize(c, o.total)), 15f, MT.gray).apply { singleLineEllipsis() })
            if (o.failed && onRetry != null) addView(glyph(R.drawable.ic_refresh, R.string.try_again, onRetry), lp(dp(44), dp(44)))
            if (o.failed && onDiscard != null) addView(glyph(R.drawable.ic_delete, R.string.delete, onDiscard), lp(dp(44), dp(44)))
        }, lp())
        gap(8)
        addView(ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progress = (o.share * 1000).toInt()
            progressTintList = ColorStateList.valueOf(Color.WHITE)
            progressBackgroundTintList = ColorStateList.valueOf(MT.gray)
        }, lp())
    }
}

/** A POST ON ITS WAY, ON ITS WALL (iOS MTBoardSendingCell 1581-1592): the bar of its files over the post as it will stand. */
fun goingCell(act: MainActivity, o: MyWall.Going): View = act.vstack(Gravity.NO_GRAVITY) {
    addView(goingBar(act, o, onRetry = { Thread { MyWall.publish(o.id) }.start() }, onDiscard = { Thread { MyWall.discard(o.id) }.start() }), lp())
    gap(8)
    addView(postCell(act, Board.Item(o.wall, o.post), onItsWall = true, sending = true), lp())
}

/**
 * A NEW POST (iOS MTBoardComposer, MontanaBoardViews 1666-2028; the author's word 24.09: «the new post shows at once as it will be
 * published»): my face and my name over the words, written where they will stand; under them «Photos and videos» and «Tracks and
 * files», and the files taken, each with its miniature, its name and its size, the cross taking it off. The check mark sets the post
 * on its way (MyWall.begin) and lays its files on the node under the bar at the page's top (MyWall.publish); the page leaves when the
 * post is out, and a post the node did not take keeps its try again here and on the wall. Opened from a person's page (wall, their
 * reference) the post goes to their wall (iOS MTBoardComposer.present(on: owner), MTBoard.begin(on:) 1772).
 */
fun newPostPage(act: MainActivity, onClose: () -> Unit, sharedWords: String = "", sharedFiles: List<android.net.Uri> = emptyList(), wall: String = ""): View {
    val c: Context = act
    val files = mutableListOf<MyWall.Attachment>()
    var taking = 0
    var sending: String? = null
    var closed = false
    val field = android.widget.EditText(c).apply {
        hint = c.getString(R.string.write_something)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray); background = null
        textSize = 17f
        minLines = 3
        setPadding(dp(16), dp(12), dp(16), dp(16))
    }
    val barSlot = FrameLayout(c)
    val picks = c.plate {}
    val taken = c.plate {}
    val failedLine = c.text(c.getString(R.string.wall_could_not_post), 15f, MT.red).apply { setPadding(dp(16), dp(12), dp(16), dp(12)); visibility = View.GONE }
    lateinit var done: View
    fun empty() = field.text.isBlank() && files.isEmpty()
    fun dress() {
        val off = empty() || 0 < taking || sending != null
        done.alpha = if (off) 0.4f else 1f
        picks.visibility = if (sending == null) View.VISIBLE else View.GONE
    }
    fun leave() {
        closed = true
        if (sending == null) files.forEach { it.file.delete() }   // a page closed unposted leaves no copy of what it was given
        onClose()
    }
    fun drawTaken() {
        taken.removeAllViews()
        for (f in files) taken.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(56)
            setPadding(dp(16), dp(6), dp(4), dp(6))
            val visual = f.kind == "img" || f.kind == "vid"
            addView(if (visual) ImageView(c).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                background = c.rounded(MT.hairline, 8); outlineProvider = ViewOutlineProvider.BACKGROUND; clipToOutline = true
                Thread { Media.preview(c, f.file, f.kind, 132)?.let { b -> MainThread.post { setImageBitmap(b) } } }.start()
            } else FrameLayout(c).apply {
                background = c.rounded(Color.rgb(41, 41, 41), 8)
                addView(c.icon(if (f.kind == "aud") R.drawable.ic_music_note else R.drawable.ic_compose_doc, MT.gray, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            }, lp(dp(44), dp(44)))
            gap(12)
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(f.name, 17f).apply { singleLineEllipsis() }, lp())   // USER-DATA: the file's own name
                addView(c.text(Formatter.formatShortFileSize(c, f.file.length()), 12f, MT.gray), lp())
            }, lp(0, WRAP, 1f))
            if (sending == null) addView(c.icon(R.drawable.ic_cancel, MT.gray, 22).apply {
                setPadding(dp(11), dp(11), dp(11), dp(11))
                contentDescription = c.getString(R.string.wall_remove)
                pressable { files.remove(f); f.file.delete(); drawTaken() }
            }, lp(dp(44), dp(44)))
        }, lp())
        // a file on its way from the picker: the platform's wheel where its row will stand
        if (0 < taking) taken.addView(ProgressBar(c).apply { indeterminateTintList = ColorStateList.valueOf(Color.WHITE) }, lp(MATCH, c.dp(44)).apply { setMargins(0, c.dp(6), 0, c.dp(6)) })
        taken.visibility = if (files.isEmpty() && taking == 0) View.GONE else View.VISIBLE
        dress()
    }
    fun take(uris: List<android.net.Uri>) {
        if (uris.isEmpty()) return
        taking += uris.size
        drawTaken()
        Thread {
            for (u in uris) {
                val a = WallFiles.take(c, u)
                MainThread.post {
                    taking--
                    if (a != null && files.size < MEDIA_LIMIT && !closed) files.add(a) else a?.file?.delete()
                    drawTaken()
                }
            }
        }.start()
    }
    fun showBar() {
        barSlot.removeAllViews()
        val pid = sending?.takeIf { it.isNotEmpty() } ?: return
        val o = MyWall.sending().firstOrNull { it.id == pid } ?: return
        barSlot.addView(goingBar(act, o, onRetry = {
            Thread { val ok = MyWall.publish(pid); MainThread.post { if (ok && !closed) leave() } }.start()
        }, onDiscard = null), FrameLayout.LayoutParams(MATCH, WRAP).apply { setMargins(c.dp(16), c.dp(6), c.dp(16), c.dp(6)) })
    }
    fun post() {
        if (sending != null || empty() || 0 < taking) return
        failedLine.visibility = View.GONE
        sending = ""   // the check stands down at once; the bar comes with the post
        drawTaken()
        val words = field.text.toString()
        val atts = files.toList()
        Thread {
            val pid = MyWall.begin(words, atts, wall)
            if (pid == null) { MainThread.post { sending = null; failedLine.visibility = View.VISIBLE; drawTaken() }; return@Thread }
            MainThread.post { sending = pid; files.clear(); drawTaken(); showBar() }
            val ok = MyWall.publish(pid)
            MainThread.post { if (ok && !closed) leave() }
        }.start()
    }
    done = c.icon(R.drawable.ic_check, Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10))
        contentDescription = c.getString(R.string.wall_publish)
        pressable { post() }
    }
    field.addTextChangedListener(object : android.text.TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun afterTextChanged(s: android.text.Editable?) { dress() }
    })
    fun pickRow(glyph: Int, words: Int, deed: () -> Unit) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(48)
        setPadding(dp(16), 0, dp(16), 0)
        addView(c.icon(glyph, Color.WHITE, 22), lp(dp(22), dp(22)))
        gap(14)
        addView(c.text(c.getString(words), 17f).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))
        pressable(deed)
    }
    picks.addView(pickRow(R.drawable.ic_photo, R.string.wall_photos_videos) {
        val room = MEDIA_LIMIT - files.size - taking
        if (0 < room) act.pickVisualMany(room) { take(it.take(room)) }
    }, lp())
    picks.addView(pickRow(R.drawable.ic_queue_music, R.string.wall_tracks_files) {
        val room = MEDIA_LIMIT - files.size - taking
        if (0 < room) act.openDocuments { take(it.take(room)) }
    }, lp())
    val page = settingsPage(act, c.getString(R.string.new_post), { leave() }, cross = true, trailing = done) {
        addView(barSlot, lp())
        addView(c.plate {
            addView(c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(14), dp(16), 0)
                addView(c.avatar(SelfFace.load(c), Prefs.userName, 40), lp(dp(40), dp(40)))
                gap(10)
                addView(c.text(Prefs.userName, 15f, Color.WHITE, bold = true).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: my name
            }, lp())
            addView(field, lp())
        }, lp().apply { topMargin = dp(12) })
        addView(picks, lp().apply { topMargin = dp(16) })
        addView(taken, lp().apply { topMargin = dp(16) })
        addView(failedLine, lp().apply { topMargin = dp(16) })
    }
    drawTaken()
    // WHAT ANOTHER APP HANDED IN STANDS ON THE PAGE ALREADY TAKEN (iOS MTBoard.laySheet 1974-1991: the words joined, the files held to
    // what a post takes, then MTBoardComposer.reopen 2054-2058): the words to change, more files to pick, the check to post
    if (sharedWords.isNotEmpty()) { field.setText(sharedWords); field.setSelection(field.text.length) }
    take(sharedFiles.take(MEDIA_LIMIT))
    // the bar follows the node's count while the post is on its way
    val heard: () -> Unit = { if (sending != null) showBar() }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { MyWall.listen(heard) }
        override fun onViewDetachedFromWindow(v: View) { MyWall.unlisten(heard) }
    })
    field.post {
        field.requestFocus()
        c.getSystemService(android.view.inputmethod.InputMethodManager::class.java).showSoftInput(field, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
    }
    return page
}

private const val MEDIA_LIMIT = 10   // iOS MTPostMeasure.files
